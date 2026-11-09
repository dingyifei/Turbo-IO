#!/usr/bin/env python3
"""Independent re-derivation of the stock 1.0.5.5 -> 1.0.5.12 rebase. Offline: reads two stock ZIPs and two trees.

  python3 -I firmware/tests/rebase_independent_test.py                 # exports fw/tmg9 itself with git archive
  python3 -I firmware/tests/rebase_independent_test.py --old-tree DIR  # DIR = a `git archive fw/tmg9 firmware
                                                                       #   firmware-research/strix-1.0.5.5/stock` export

It does not read the rebase table to find an address, and it does not use the decomp study or rebase_derive.py. Every
address is derived again here, at run time, from the two stock AP images, and only then compared with the new tree
and with the table (baseline/rebase-1.0.5.5-to-1.0.5.12.json).

Universe. Every stock address in the OLD tree (fw/tmg9): the link.ld callees and module start, the 25 edits of
build-inputs.json, the stock ABI ranges of tests/stock_abi_test.py, and every hex token under src/, include/, tests/,
trampolines.S and ImageWireFormat.h that falls inside the 1.0.5.5 AP image or the RAM window 0x18000000-0x1a000000.
A token in that window that is not a stock address must be listed in NOT_STOCK with a reason, else the run fails.

Image layout. The AP image is mapped at FLASH 0x10190000. Its start-up copy table (word triples src, src_end, dst
in the first 4 KiB) is parsed from each image, which gives the copy region (dst 0x100000) and the .data copy
(dst 0x18000000) without hard-coding their file offsets.

Thumb bit. All code searches work on even byte addresses (bit 0 stripped). A code value keeps the bit it had in
the old tree (new = derived | (old & 1)); patch sites and ABI ranges are even; RAM and .data values are plain byte
addresses and are taken whole from literal votes. The run asserts old & 1 == new & 1 for every code value.

Methods.
  sig    Masked signature. A window of old bytes around the address (several shapes: 0..32, 0..48, 0..64, -16..16,
         -32..32, -32..0, -64..0, 0..24, 0..16) is decoded as Thumb-2. The immediate bits of BL and B.W (T4), the
         offset of pc-relative loads, and every literal-pool word those loads reach (pools referenced from up to
         4 KiB before the window included) are masked. Each window is searched over the whole new image (even
         positions). The answer is the hit of the windows that have exactly one hit. Windows holding 16 bytes or
         more at or after the address decide; windows that end before that (the code before the address) only
         decide when no forward window is unique, and their disagreement is printed as "follows a different body"
         (that is how the matcher's tgr_intercept partner went wrong). All deciding windows must agree, and a
         forward window with several hits must contain the answer. A weak answer (no deciding window of 32 bytes,
         or backward windows only) with no caller vote must be corroborated by an edge (below).
  edge   Every BL/B.W inside a matched window gives an (old target, new target) pair. Any pair whose old target is
         a universe code address must equal that address's derived value; pairs are pooled over the whole run.
  call   Caller votes. Up to 12 old BL/B.W sites that target the address are paired by their own masked windows,
         and the new branch target at the paired site is a vote. The top vote must match sig (when both exist).
  lit    Literal votes, for RAM/.data/code-pointer values: every aligned old literal word equal to the value, every
         pc-relative load that reaches it, that load paired by its masked window, and the literal it reads in the
         new image is a vote. At least 75 % of the votes must agree.
  field  For a RAM value with no literal of its own: a resolved RAM base R with 0 < value - R < 0x400, the old
         ldr.w/str.w [Rn,#value-R] sites that use the base literal R, and at their paired new sites the same
         instruction with the same offset and the new base literal. Then new = R' + (value - R).
  str    For .data values: the NUL-terminated string at the old address equals the one at the new address.
  struct The module VA: the old tree's module start is FLASH + AP bytes - k with the same k-byte trailer in both
         images; the new one is FLASH + new AP bytes - k.
  copy   Copy-region callees (below FLASH): the function bytes in the copy region are identical in both images,
         at the same runtime address, so the value does not move.

Checks, all fatal: every universe address resolved (no conflicts, every method that applies agrees); every value in
the new tree equals the derived one at the same files and counts as the old tree (and no old value is left); every
table value equals it; universe count == count of rows checked (printed); the edits' `before` bytes match the new
image at the derived address; ABI range hashes match the new image; the known-bad tgr_intercept value 0x10625941 is
rejected and 0x1062c439 found; the four copy-region callees are unchanged and the strcmp veneer still reaches strcmp.
resume_X equals trampoline edit X + 5. A mutation check (in a temp copy, never the repo) sets one link.ld address
and one source RAM value of the new tree, and one link.ld row and one edit row of the table, to a neighbour's value,
and requires each to be reported.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile

FW = Path(__file__).resolve().parents[1]
ROOT = FW.parent
FLASH = 0x10190000
RAM_LO, RAM_HI = 0x18000000, 0x1a000000
OLD_STOCK_REL = 'firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip'
NEW_STOCK_REL = 'firmware-research/strix-1.0.5.12/stock/Strix-OS-1.0.5.12-original.zip'
TABLE_REL = 'baseline/rebase-1.0.5.5-to-1.0.5.12.json'
SCANNED = ('src', 'include', 'tests', 'trampolines.S', 'ImageWireFormat.h')
SELF = 'tests/rebase_independent_test.py'

# Tokens inside the scanned address windows that are not stock addresses. Each is also checked at run time to have
# no literal in either stock image, except the region bases, which are checked against the parsed copy table.
NOT_STOCK = {
    '0x10190000': 'FLASH base of the AP image (region bound, not an address in it)',
    '0x18000000': 'RAM base / .data copy destination (region bound)',
    '0x18001000': 'fake display unit in native_display_test.c',
    '0x18002000': 'fake display in native_display_test.c',
    '0x18617cb0': 'fake key in render_idle_test.c (no literal in either stock image; not a 1.0.5.5 address)',
    '0x19000000': 'fake unit in render_idle_test.c', '0x1900000c': 'fake unit field', '0x19000018': 'fake unit field',
    '0x19000100': 'fake unit in render_idle_test.c', '0x1900010c': 'fake unit field', '0x19000118': 'fake unit field',
    '0x19100000': 'fake display in render_idle_test.c', '0x191002a0': 'fake display field',
    '0x19200000': 'fake layer in render_idle_test.c', '0x19200038': 'fake layer field',
    '0x19200040': 'fake layer field',
}
# The one value known to be wrong upstream: the decomp matcher's tgr_intercept partner (a different function).
KNOWN_BAD = {'tgr_intercept': (0x10625941, 0x1062c439)}
COPY_CALLEES = ('memcpy', 'memset', 'strcmp', 'strlen')
STRCMP_VENEER = 'ce_ext_10941968'

SIG_WINDOWS = ((0, 32), (0, 48), (0, 64), (-16, 16), (-32, 32), (-32, 0), (-64, 0), (0, 24), (0, 16))
SITE_WINDOWS = ((-16, 20), (-24, 28), (-32, 36), (-12, 16), (-8, 12), (0, 24), (-24, 4))


# ---------------------------------------------------------------- image and Thumb-2 decoding

class Image:
    def __init__(self, raw, name):
        self.raw, self.name, self.end = raw, name, FLASH + len(raw)
        self.tables = copy_tables(raw)
        self._branches = None
        self._words = None

    def has(self, va, n=1):
        return FLASH <= va and va + n <= self.end

    def h(self, va):
        return struct.unpack_from('<H', self.raw, va - FLASH)[0]

    def w(self, va):
        return struct.unpack_from('<I', self.raw, va - FLASH)[0]

    def file_of(self, runtime):
        """File offset of a runtime address in a copied region (copy region, .data), or of a flash address."""
        for s, e, d in self.tables:
            if d <= runtime < d + (e - s):
                return s - FLASH + runtime - d
        if self.has(runtime):
            return runtime - FLASH
        return None

    def region(self, dst):
        return next((s, e, d) for s, e, d in self.tables if d == dst)

    def code_end(self):
        """Literal votes skip the .data source (initialised data, not code)."""
        s, e, d = self.region(RAM_LO)
        return s, e

    def branch_sites(self):
        """target -> [site] for every even position that decodes as BL or B.W (T4)."""
        if self._branches is None:
            idx = defaultdict(list)
            raw = self.raw
            for m in re.finditer(rb'(?=[\x00-\xff][\xf0-\xf7][\x00-\xff][\x90-\xbf\xd0-\xff])', raw, re.S):
                i = m.start()
                if i & 1:
                    continue
                b = branch(self, FLASH + i)
                if b:
                    idx[b[1]].append(FLASH + i)
            self._branches = idx
        return self._branches

    def word_sites(self, value):
        if self._words is None:
            self._words = defaultdict(list)
            ds, de = self.code_end()
            for i in range(0, len(self.raw) - 3, 4):
                if ds - FLASH <= i < de - FLASH:
                    continue
                v = struct.unpack_from('<I', self.raw, i)[0]
                if RAM_LO <= v < RAM_HI or FLASH <= v < self.end:
                    self._words[v].append(FLASH + i)
        return self._words.get(value, [])


def copy_tables(raw):
    """(src, src_end, dst) word triples of the start-up copy table, from the first 4 KiB."""
    out = []
    end = FLASH + len(raw)
    for i in range(0, 0x1000 - 8, 4):
        s, e, d = struct.unpack_from('<3I', raw, i)
        if FLASH <= s < e <= end and e - s >= 0x1000 and not (FLASH <= d < end) and d % 4 == 0 and \
                (d < FLASH or RAM_LO <= d < 0x40000000):
            out.append((s, e, d))
    return out


def is32(hw):
    return (hw >> 11) in (0x1d, 0x1e, 0x1f)


def branch(img, pc):
    """('bl'|'b.w', even target) for a 32-bit BL or B.W (T4) at pc, else None."""
    if not img.has(pc, 4):
        return None
    h1, h2 = img.h(pc), img.h(pc + 2)
    if (h1 >> 11) != 0x1e:
        return None
    if (h2 & 0xd000) == 0xd000:
        kind = 'bl'
    elif (h2 & 0xd000) == 0x9000:
        kind = 'b.w'
    else:
        return None
    s = (h1 >> 10) & 1
    i1 = 1 - (((h2 >> 13) & 1) ^ s)
    i2 = 1 - (((h2 >> 11) & 1) ^ s)
    imm = (s << 24) | (i1 << 23) | (i2 << 22) | ((h1 & 0x3ff) << 12) | ((h2 & 0x7ff) << 1)
    if s:
        imm -= 1 << 25
    return kind, pc + 4 + imm


def literal_ref(img, pc):
    """(target, size, instruction length) for a pc-relative load at pc, else None."""
    if not img.has(pc, 2):
        return None
    h1 = img.h(pc)
    base = (pc + 4) & ~3
    if (h1 & 0xf800) == 0x4800:
        return base + (h1 & 0xff) * 4, 4, 2
    if not is32(h1) or not img.has(pc, 4):
        return None
    h2 = img.h(pc + 2)
    up = (h1 >> 7) & 1
    if (h1 & 0xff7f) == 0xf85f:                           # LDR.W (literal)
        imm = h2 & 0xfff
        return base + (imm if up else -imm), 4, 4
    if (h1 & 0xfe7f) == 0xe85f and (h1 & 0x0100):          # LDRD (literal), P=1
        imm = (h2 & 0xff) * 4
        return base + (imm if up else -imm), 8, 4
    if (h1 & 0xff3f) == 0xed1f and (h2 & 0x0e00) == 0x0a00:  # VLDR (literal)
        imm = (h2 & 0xff) * 4
        return base + (imm if up else -imm), (8 if h2 & 0x100 else 4), 4
    return None


def masked_window(img, start, end):
    """(bytes, keep masks, edges[(offset, kind, target)], loads[offset]) for [start, end) decoded from start."""
    lits = set()
    for q in range(max(FLASH, start - 4096) & ~1, start, 2):    # pools after the window start, loaded from before it
        r = literal_ref(img, q)
        if r and start - 8 < r[0] < end:
            lits.update(range(r[0], r[0] + r[1]))
    data = img.raw[start - FLASH:end - FLASH]
    keep = bytearray(b'\xff' * len(data))
    edges, loads = [], []
    pc = start
    while pc < end:
        if pc in lits:
            for k in range(pc, min(pc + 4, end)):
                keep[k - start] = 0
            pc += 4
            continue
        h1 = img.h(pc)
        r = literal_ref(img, pc)
        if r:
            lits.update(range(r[0], r[0] + r[1]))
            loads.append(pc - start)
            if r[2] == 2:
                keep[pc - start] = 0                               # imm8
            elif pc + 3 < end:
                keep[pc + 2 - start] = 0                           # imm12 / imm8 low byte
                keep[pc + 3 - start] &= 0xf0 if (h1 & 0xff7f) == 0xf85f else 0xff
        if is32(h1):
            b = branch(img, pc)
            if b:
                edges.append((pc - start, b[0], b[1]))
                keep[pc - start] = 0
                if pc + 1 < end:
                    keep[pc + 1 - start] &= 0xf8
                if pc + 2 < end:
                    keep[pc + 2 - start] = 0
                if pc + 3 < end:
                    keep[pc + 3 - start] &= 0xd0
            pc += 4
        else:
            pc += 2
    for a in lits:
        if start <= a < end:
            keep[a - start] = 0
    return data, bytes(keep), edges, loads


def search(img, data, keep):
    """Even positions in img where data matches under keep."""
    runs, i = [], 0
    while i < len(data):
        if keep[i] == 0xff:
            j = i
            while j < len(data) and keep[j] == 0xff:
                j += 1
            runs.append((j - i, i))
            i = j
        else:
            i += 1
    if not runs:
        return None
    length, off = max(runs)
    if length < 4 or sum(bin(k).count('1') for k in keep) < 8 * min(16, len(data) // 2):
        return None
    anchor = data[off:off + length]
    raw, hits, at = img.raw, [], -1
    while True:
        at = raw.find(anchor, at + 1)
        if at < 0:
            break
        p = at - off
        if p < 0 or p & 1 or p + len(data) > len(raw):
            continue
        if all(((raw[p + k] ^ data[k]) & keep[k]) == 0 for k in range(len(data)) if keep[k]):
            hits.append(FLASH + p)
    return hits


def pair(old, new, at, windows):
    """Resolve the even old address `at` in the new image by masked windows. Returns (new or None, report)."""
    tried, unique, multi = [], {}, []
    for before, after in windows:
        s, e = at + before, at + after
        if not old.has(s, e - s) or e - s < 8:
            continue
        data, keep, edges, loads = masked_window(old, s, e)
        hits = search(new, data, keep)
        if hits is None:
            tried.append((before, after, None))
            continue
        tried.append((before, after, len(hits)))
        if len(hits) == 1:
            unique[(before, after)] = (hits[0] - before, edges)
        elif hits:
            multi.append((set(h - before for h in hits), (before, after)))
    # Windows holding at least 16 bytes at or after the address describe the address itself; backward-only windows
    # describe the code before it, which may be a different body that moved separately (the tgr_intercept trap).
    fwd = {k: v for k, v in unique.items() if k[1] >= 16}
    back = {k: v for k, v in unique.items() if k[1] < 16}
    rep = {'windows': tried, 'unique': len(unique)}
    use = fwd or back
    answers = {v[0] for v in use.values()}
    if len(answers) != 1:
        rep['why'] = 'no unique window' if not answers else 'windows disagree: ' + ', '.join(hex(a) for a in sorted(answers))
        return None, rep
    answer = answers.pop()
    other = {v[0] for v in back.values()} - {answer} if fwd else set()
    if other:
        rep['note'] = 'the bytes before it match elsewhere (%s): it follows a different body' % ','.join(map(hex, other))
    rep['unique'] = len(use)
    rep['short'] = not any(a - b >= 32 for (b, a) in use)
    if not fwd:
        rep['note'] = 'backward windows only'
        rep['short'] = True
    if any(answer not in m for m, w in multi if w[1] >= 16):
        rep['why'] = 'a multi-hit window excludes ' + hex(answer)
        return None, rep
    rep['edges'] = []
    for (before, after), (_, edges) in use.items():
        for off, kind, tgt in edges:
            nb = branch(new, answer + before + off)
            if nb:
                rep['edges'].append((tgt, nb[1], at + before + off))
    return answer, rep



# ---------------------------------------------------------------- methods

class Deriver:
    def __init__(self, old, new):
        self.old, self.new = old, new
        self.edge_pool = defaultdict(set)      # old even target -> {new even target}
        self.load_pairs = {}                   # old load site -> new load site
        self.cache = {}

    def sig(self, at):
        if at not in self.cache:
            ans, rep = pair(self.old, self.new, at, SIG_WINDOWS)
            for o, n, _ in rep.get('edges', []):
                self.edge_pool[o].add(n)
            self.cache[at] = (ans, rep)
        return self.cache[at]

    def site(self, at):
        ans, rep = pair(self.old, self.new, at, SITE_WINDOWS)
        for o, n, _ in rep.get('edges', []):
            self.edge_pool[o].add(n)
        return ans

    def callers(self, target, limit=12):
        votes = Counter()
        for s in self.old.branch_sites().get(target, [])[:limit]:
            ns = self.site(s)
            if ns is None:
                continue
            b = branch(self.new, ns)
            if b:
                votes[b[1]] += 1
        return votes

    def load_sites(self, lit):
        """Old pc-relative loads that read the literal at `lit`."""
        out = []
        for q in range(max(FLASH, lit - 4100) & ~1, lit, 2):
            r = literal_ref(self.old, q)
            if r and r[0] <= lit < r[0] + r[1] and (r[0] == lit or r[1] == 8):
                out.append((q, lit - r[0]))
        return out

    def lit_votes(self, value):
        votes = Counter()
        for lit in self.old.word_sites(value):
            for q, sub in self.load_sites(lit):
                nq = self.load_pairs.get(q) or self.site(q)
                if nq is None:
                    continue
                self.load_pairs[q] = nq
                r = literal_ref(self.new, nq)
                if r and self.new.has(r[0] + sub, 4):
                    votes[self.new.w(r[0] + sub)] += 1
        return votes

    def field(self, value, base_old, base_new):
        """ldr.w/str.w [Rn,#off] after a load of the base literal, paired; returns (old sites, agreeing new sites)."""
        off = value - base_old
        n_old = n_agree = 0
        for lit in self.old.word_sites(base_old):
            for q, sub in self.load_sites(lit):
                if sub:
                    continue
                rd = (self.old.h(q) >> 8) & 7 if (self.old.h(q) & 0xf800) == 0x4800 else self.old.h(q + 2) >> 12
                hit = self._field_use(self.old, q, rd, off)
                if hit is None:
                    continue
                n_old += 1
                nq = self.load_pairs.get(q) or self.site(q)
                if nq is None:
                    continue
                r = literal_ref(self.new, nq)
                if not r or self.new.w(r[0]) != base_new:
                    continue
                rd2 = (self.new.h(nq) >> 8) & 7 if (self.new.h(nq) & 0xf800) == 0x4800 else self.new.h(nq + 2) >> 12
                if self._field_use(self.new, nq, rd2, off) == hit:
                    n_agree += 1
        return n_old, n_agree

    @staticmethod
    def _field_use(img, q, rd, off):
        """Distance (in bytes) from q to the first ldr.w/str.w Rt,[rd,#off] within 40 bytes, else None."""
        pc = q + (2 if (img.h(q) & 0xf800) == 0x4800 else 4)
        while pc < q + 40 and img.has(pc, 4):
            h1 = img.h(pc)
            if is32(h1):
                h2 = img.h(pc + 2)
                if (h1 & 0xffe0) in (0xf8d0, 0xf8c0) and (h1 & 0xf) == rd and (h2 & 0xfff) == off:
                    return pc - q
                pc += 4
            else:
                pc += 2
        return None


def cstring(img, runtime):
    at = img.file_of(runtime)
    if at is None:
        return None
    end = img.raw.find(b'\0', at)
    return img.raw[at:end] if 0 <= end - at < 512 else None


# ---------------------------------------------------------------- trees

def hex_tokens(text):
    return re.findall(r'(?<![0-9A-Za-z_])0[xX][0-9a-fA-F]{6,8}(?![0-9A-Za-z_])', text)


def scanned(fw):
    for part in SCANNED:
        p = fw/part
        if not p.exists():
            continue
        for q in ([p] if p.is_file() else sorted(x for x in p.rglob('*') if x.is_file())):
            rel = q.relative_to(fw).as_posix()
            if rel == SELF or '__pycache__' in rel:
                continue
            try:
                yield rel, q.read_text()
            except UnicodeDecodeError:
                continue


LINK_SYMBOL = re.compile(r'^\s*(\w+)\s*=\s*(0x[0-9a-fA-F]+)\s*;', re.M)
MODULE_START = re.compile(r'^\s*\.\s*=\s*(0x[0-9a-fA-F]+)\s*;', re.M)
ABI_RANGE = re.compile(r'^\s*\((0x[0-9a-fA-F]+),(\d+),\'([0-9a-f]{64})\'\)', re.M)


def read_tree(fw, img):
    """The stock-address universe of one tree, from its files alone."""
    link = (fw/'link.ld').read_text()
    spec = json.loads((fw/'build-inputs.json').read_text())
    u = {'link': {m.group(1): int(m.group(2), 16) for m in LINK_SYMBOL.finditer(link)},
         'module': [int(x, 16) for x in MODULE_START.findall(link)],
         'moduleVA': int(spec['moduleVA'], 16),
         'edits': {e['role']: e for e in spec['edits']},
         'abi': [(int(a, 16), int(n), h) for a, n, h in ABI_RANGE.findall((fw/'tests/stock_abi_test.py').read_text())],
         'tramp_bytes': {m.group(1): bytes(int(x, 0) for x in m.group(2).split(',')) for m in re.finditer(
             r'^stock_(\w+):\n\.byte ([^\n]+)\n', (fw/'trampolines.S').read_text(), re.M)},
         'sites': defaultdict(Counter)}          # value -> {file: count}
    abi_text = set(hex(a) for a, _, _ in u['abi'])
    for rel, text in scanned(fw):
        for t in hex_tokens(text):
            v = int(t, 16)
            if t.lower() in NOT_STOCK:
                continue
            if rel == 'tests/stock_abi_test.py' and hex(v) in abi_text:
                continue
            if img.has(v) or RAM_LO <= v < RAM_HI:
                u['sites'][v][rel] += 1
    return u


def not_stock_seen(fw, img):
    seen = Counter()
    for rel, text in scanned(fw):
        for t in hex_tokens(text):
            v = int(t, 16)
            if (img.has(v) or RAM_LO <= v < RAM_HI) and t.lower() in NOT_STOCK:
                seen[t.lower()] += 1
    return seen


# ---------------------------------------------------------------- derivation

def derive(old_fw, old, new):
    """Rows: one per universe address, each with the derived new value and the evidence."""
    d = Deriver(old, new)
    u = read_tree(old_fw, old)
    rows = []

    def code_row(kind, name, value):
        at = value & ~1
        row = {'kind': kind, 'name': name, 'old': value, 'new': None, 'methods': {}, 'problems': []}
        rows.append(row)
        if not old.has(at):
            # Copy region: same runtime address, identical function bytes in both images.
            fo, fn = old.file_of(at), new.file_of(at)
            if fo is None or fn is None:
                row['problems'].append('outside the image and every copied region')
                return row
            same = old.raw[fo:fo + 32] == new.raw[fn:fn + 32]
            row['methods']['copy'] = 'file 0x%x / 0x%x, 32 bytes %s' % (fo, fn, 'identical' if same else 'DIFFER')
            if same and fo == fn:
                row['new'] = value
            else:
                row['problems'].append('copy-region bytes or offset differ')
            return row
        ans, rep = d.sig(at)
        row['sigrep'] = rep
        if ans is not None:
            row['methods']['sig'] = 'unique in %d window(s)%s: %s' % (
                rep['unique'], ' (weak: shorter than 32 bytes or backward only)' if rep['short'] else '', hex(ans))
            if rep.get('note'):
                row['methods']['sig'] += ' [%s]' % rep['note']
        else:
            row['methods']['sig'] = 'none (%s)' % rep.get('why')
        votes = d.callers(at)
        if votes:
            top, n = votes.most_common(1)[0]
            row['methods']['call'] = '%d/%d votes for %s' % (n, sum(votes.values()), hex(top))
            if n * 4 < sum(votes.values()) * 3:
                top = None
                row['methods']['call'] += ' (split)'
        else:
            top = None
        cand = {x for x in (ans, top) if x is not None}
        if len(cand) > 1:
            row['problems'].append('sig %s and call %s disagree' % (hex(ans), hex(top)))
        elif cand:
            row['new'] = cand.pop() | (value & 1)
            row['short'] = ans is not None and rep['short'] and top is None
        else:
            row['problems'].append('unresolved: ' + row['methods']['sig'])
        return row

    for name, v in u['link'].items():
        code_row('link', name, v)
    for role, e in u['edits'].items():
        r = code_row('edit', role, int(e['address'], 16))
        r['edit'] = e
    for a, n, h in u['abi']:
        r = code_row('abi', 'range %d bytes' % n, a)
        r['abi'] = (n, h)
    # module VA (struct)
    k = FLASH + len(old.raw) - u['moduleVA']
    row = {'kind': 'module', 'name': 'moduleVA', 'old': u['moduleVA'], 'new': None, 'methods': {}, 'problems': []}
    if u['module'] != [u['moduleVA']]:
        row['problems'].append('old link.ld module start != build-inputs moduleVA')
    if 0 < k <= 64 and old.raw[-k:] == new.raw[-k:]:
        row['new'] = FLASH + len(new.raw) - k
        row['methods']['struct'] = 'FLASH + AP bytes - %d (same %d-byte trailer in both images)' % (k, k)
    else:
        row['problems'].append('trailer differs or k=%d' % k)
    rows.append(row)
    # literal values found in the source files
    link_values = set(u['link'].values())
    pending = []
    for v, sites in sorted(u['sites'].items()):
        if old.has(v):
            r = code_row('value', 'code literal', v)
            votes = d.lit_votes(v)
            if votes:
                top, n = votes.most_common(1)[0]
                r['methods']['lit'] = '%d/%d votes for %s' % (n, sum(votes.values()), hex(top))
                if r['new'] is not None and top != r['new']:
                    r['problems'].append('lit %s disagrees with %s' % (hex(top), hex(r['new'])))
            r['sites'] = dict(sites)
        else:
            pending.append((v, sites))
    for v, sites in pending:
        row = {'kind': 'value', 'name': 'ram/.data', 'old': v, 'new': None, 'methods': {}, 'problems': [],
               'sites': dict(sites)}
        rows.append(row)
        votes = d.lit_votes(v)
        if votes:
            top, n = votes.most_common(1)[0]
            total = sum(votes.values())
            row['methods']['lit'] = '%d/%d votes for %s' % (n, total, hex(top))
            if n * 4 >= total * 3:
                row['new'] = top
            else:
                row['problems'].append('literal votes split: ' + str({hex(a): b for a, b in votes.most_common(4)}))
        s_old = cstring(old, v) if old.file_of(v) is not None and v < old.region(RAM_LO)[2] + 0x400000 else None
        if s_old and len(s_old) >= 4 and all(32 <= c < 127 for c in s_old):
            row['string'] = s_old.decode()
            if row['new'] is not None:
                ok = cstring(new, row['new']) == s_old
                row['methods']['str'] = '%r %s' % (s_old.decode()[:32], 'same at new address' if ok else 'DIFFERS')
                if not ok:
                    row['problems'].append('string differs at new address')
    # field method for RAM values without literals, from resolved RAM bases nearby
    resolved = {r['old']: r['new'] for r in rows if r['kind'] == 'value' and r['new'] is not None and
                RAM_LO <= r['old'] < RAM_HI}
    for row in rows:
        if row['kind'] != 'value' or row['new'] is not None or not (RAM_LO <= row['old'] < RAM_HI):
            continue
        bases = sorted((b for b in resolved if 0 < row['old'] - b < 0x400), key=lambda b: row['old'] - b)
        for b in bases:
            n_old, n_agree = d.field(row['old'], b, resolved[b])
            row['methods']['field'] = 'base %s+0x%x: %d old ldr/str sites, %d paired with the same offset on %s' % (
                hex(b), row['old'] - b, n_old, n_agree, hex(resolved[b]))
            if n_old and n_agree * 4 >= n_old * 3:
                row['new'] = resolved[b] + row['old'] - b
                row['problems'] = []
                break
        if row['new'] is None and not row['problems']:
            row['problems'].append('unresolved: no literal and no field evidence')
        elif row['new'] is None:
            row['problems'].append('unresolved')
    # pooled edge check over every universe code address
    derived = {r['old'] & ~1: r['new'] & ~1 for r in rows if r['new'] is not None and old.has(r['old'] & ~1)}
    for r in rows:
        if r['new'] is None or not old.has(r['old'] & ~1):
            continue
        seen = d.edge_pool.get(r['old'] & ~1, set())
        if seen:
            r['methods']['edge'] = '%d pooled edge(s) -> %s' % (len(seen), ','.join(hex(x) for x in sorted(seen)))
            if seen != {r['new'] & ~1}:
                r['problems'].append('edge pool disagrees')
    # a weak signature (only windows shorter than 32 bytes, or only backward windows) with no caller vote needs a
    # corroborating edge: a BL/B.W in the matched window whose old target is another universe code address and whose
    # new target is that address's derived value
    for r in rows:
        if not r.get('short'):
            continue
        good = [(o, n) for o, n, _ in r['sigrep'].get('edges', []) if o != r['old'] & ~1 and o in derived]
        if good and all(derived[o] == n for o, n in good):
            r['methods']['edge'] = (r['methods'].get('edge', '') + ' corroborates the short window: ' + ', '.join(
                '%s->%s' % (hex(o), hex(n)) for o, n in sorted(set(good)))).strip()
        else:
            r['problems'].append('weak signature without a corroborating edge or caller vote')
    for r in rows:
        if r['new'] is not None and r['kind'] in ('link', 'value') and old.has(r['old']) and \
                (r['old'] & 1) != (r['new'] & 1):
            r['problems'].append('Thumb bit changed')
    return u, rows, d, derived


# ---------------------------------------------------------------- comparisons

def compare_tree(old_u, rows, new_fw, new_img):
    """Problems: the new tree against the derived values."""
    out = []
    nu = read_tree(new_fw, new_img)
    by = {(r['kind'], r['name'], r['old']): r for r in rows}
    for r in rows:
        if r['new'] is None:
            continue
        if r['kind'] == 'link':
            got = nu['link'].get(r['name'])
            if got != r['new']:
                out.append('link.ld %s = %s, derived %s' % (r['name'], hex(got or 0), hex(r['new'])))
        elif r['kind'] == 'edit':
            e = nu['edits'].get(r['name'])
            if e is None:
                out.append('edit %r missing' % r['name'])
                continue
            want_off = hex(r['new'] - FLASH)
            if int(e['address'], 16) != r['new'] or int(e['offset'], 16) != r['new'] - FLASH:
                out.append('edit %r address %s offset %s, derived %s / %s' % (
                    r['name'], e['address'], e['offset'], hex(r['new']), want_off))
            before = bytes.fromhex(e['before'])
            actual = new_img.raw[r['new'] - FLASH:r['new'] - FLASH + len(before)]
            if actual != before:
                out.append('edit %r before %s, new image has %s' % (r['name'], e['before'], actual.hex()))
            if e['role'].startswith('Entry trampoline '):
                tb = nu['tramp_bytes'].get(e['role'].removeprefix('Entry trampoline '))
                if tb != before:
                    out.append('trampoline prologue %r != before' % e['role'])
            old_e = r['edit']
            if old_e['kind'] != e['kind'] or old_e.get('after') is None and e.get('after') is not None:
                out.append('edit %r kind changed' % r['name'])
        elif r['kind'] == 'module':
            if nu['moduleVA'] != r['new'] or nu['module'] != [r['new']]:
                out.append('moduleVA %s / link.ld %s, derived %s' % (hex(nu['moduleVA']), nu['module'], hex(r['new'])))
        elif r['kind'] == 'value':
            new_sites = nu['sites'].get(r['new'], Counter())
            for f, c in r['sites'].items():
                if new_sites.get(f, 0) != c:
                    out.append('%s: %d x %s, old tree had %d x %s' % (f, new_sites.get(f, 0), hex(r['new']), c,
                                                                      hex(r['old'])))
            if r['new'] != r['old'] and r['old'] in nu['sites']:
                out.append('old value %s still in %s' % (hex(r['old']), dict(nu['sites'][r['old']])))
    for f in sorted(set(nu['sites']) - {r['new'] for r in rows if r['new'] is not None}):
        out.append('new tree has a stock-range token %s no old address maps to (%s)' % (hex(f), dict(nu['sites'][f])))
    return out


def compare_table(rows, table, new_img=None):
    out = []
    checked = 0
    mine = {(r['kind'], r['name'] if r['kind'] in ('link', 'edit') else r['old']) for r in rows}
    for key in ([('link', r['symbol']) for r in table['linkld']] + [('edit', r['role']) for r in table['edits']] +
                [('abi', int(r['old'], 16)) for r in table['stockAbiRanges']] +
                [('value', int(v['old'], 16)) for v in table['values']]):
        if key not in mine and not (key[0] == 'abi' and any(r['kind'] == 'abi' and r['old'] == key[1] for r in rows)):
            out.append('table row %s %s is not an address of the old tree' % key)
    tl = {r['symbol']: r for r in table['linkld']}
    te = {r['role']: r for r in table['edits']}
    tv = {int(v['old'], 16): v for v in table['values']}
    ta = {(int(r['old'], 16), r['bytes']): r for r in table['stockAbiRanges']}
    for r in rows:
        if r['new'] is None:
            continue
        if r['kind'] == 'link':
            t = tl.get(r['name'])
            if not t:
                out.append('table has no link.ld row for ' + r['name'])
                continue
            checked += 1
            if int(t['old'], 16) != r['old'] or int(t['new'], 16) != r['new']:
                out.append('table link %s %s -> %s, derived %s -> %s' % (r['name'], t['old'], t['new'], hex(r['old']),
                                                                         hex(r['new'])))
        elif r['kind'] == 'edit':
            t = te.get(r['name'])
            if not t:
                out.append('table has no edit row ' + r['name'])
                continue
            checked += 1
            if (int(t['oldAddress'], 16), int(t['newAddress'], 16), int(t['newOffset'], 16)) != \
                    (r['old'], r['new'], r['new'] - FLASH):
                out.append('table edit %r %s -> %s, derived %s' % (r['name'], t['oldAddress'], t['newAddress'],
                                                                  hex(r['new'])))
            if t['oldBefore'] != r['edit']['before']:
                out.append('table edit %r oldBefore %s, old tree %s' % (r['name'], t['oldBefore'], r['edit']['before']))
            if new_img is not None:
                n = len(t['newBefore']) // 2
                got = new_img.raw[r['new'] - FLASH:r['new'] - FLASH + n].hex()
                if got != t['newBefore']:
                    out.append('table edit %r newBefore %s, new image %s' % (r['name'], t['newBefore'], got))
        elif r['kind'] == 'abi':
            t = ta.get((r['old'], r['abi'][0]))
            if not t:
                out.append('table has no ABI range %s' % hex(r['old']))
                continue
            checked += 1
            if int(t['new'], 16) != r['new']:
                out.append('table ABI range %s -> %s, derived %s' % (t['old'], t['new'], hex(r['new'])))
            if t['oldSHA256'] != r['abi'][1]:
                out.append('table ABI range %s old hash' % t['old'])
            r['abi_new_sha'] = t['newSHA256']
        elif r['kind'] == 'module':
            checked += 1
            if int(table['moduleVA']['new'], 16) != r['new'] or int(table['moduleVA']['old'], 16) != r['old']:
                out.append('table moduleVA %s, derived %s' % (table['moduleVA']['new'], hex(r['new'])))
        elif r['kind'] == 'value':
            t = tv.get(r['old'])
            if not t:
                out.append('table has no value row for %s (old tree sites %s; derived %s)' % (
                    hex(r['old']), r['sites'], hex(r['new'])))
                continue
            checked += 1
            if int(t['new'], 16) != r['new']:
                out.append('table value %s %s -> %s, derived %s' % (t['name'], t['old'], t['new'], hex(r['new'])))
            if dict(t['sites']) != r['sites']:
                out.append('table value %s sites %s, old tree %s' % (t['name'], t['sites'], r['sites']))
    return out, checked


# ---------------------------------------------------------------- main

def load_ap(path):
    with zipfile.ZipFile(path) as z:
        return z.read('nuttx_ap.bin')


def export_tmg9(dest):
    blob = subprocess.run(['git', '-C', str(ROOT), 'archive', 'fw/tmg9', 'firmware',
                           'firmware-research/strix-1.0.5.5/stock'], check=True, capture_output=True).stdout
    with tarfile.open(fileobj=io.BytesIO(blob)) as t:
        t.extractall(dest, filter='data')
    return Path(dest)


def fw_dir(p):
    p = Path(p)
    return p/'firmware' if (p/'firmware'/'link.ld').exists() else p


def run(old_fw, new_fw, table, old, new):
    u, rows, d, derived = derive(old_fw, old, new)
    problems = []
    for r in rows:
        problems += ['%s %s %s: %s' % (r['kind'], r['name'], hex(r['old']), p) for p in r['problems']]
        if r['new'] is None and not r['problems']:
            problems.append('%s %s %s: unresolved' % (r['kind'], r['name'], hex(r['old'])))
    tree_problems = compare_tree(u, rows, new_fw, new)
    table_problems, table_checked = compare_table(rows, table, new)
    for r in rows:
        if r['kind'] == 'abi' and r['new'] is not None and 'abi_new_sha' in r:
            n = r['abi'][0]
            got = hashlib.sha256(new.raw[r['new'] - FLASH:r['new'] - FLASH + n]).hexdigest()
            if got != r['abi_new_sha']:
                table_problems.append('ABI range %s: new image hash %s != table %s' % (hex(r['new']), got,
                                                                                       r['abi_new_sha']))
        if r['kind'] == 'edit':
            e = r['edit']
            if old.raw[r['old'] - FLASH:r['old'] - FLASH + len(e['before']) // 2].hex() != e['before']:
                problems.append('old edit %r before bytes do not match the old image' % r['name'])
    return u, rows, d, derived, problems, tree_problems, table_problems, table_checked


def report(rows):
    for r in rows:
        status = 'AGREE' if r['new'] is not None and not r['problems'] else 'FAIL'
        print('%-5s %-6s %-44s %-11s -> %-11s %s' % (
            status, r['kind'], r['name'][:44], hex(r['old']), hex(r['new']) if r['new'] is not None else '?',
            '; '.join('%s: %s' % kv for kv in r['methods'].items())))
        for p in r['problems']:
            print('      problem: ' + p)
    combos = Counter('+'.join(k for k in r['methods'] if not r['methods'][k].startswith('none')) for r in rows)
    print('methods per row: ' + ', '.join('%s %d' % kv for kv in sorted(combos.items(), key=lambda kv: -kv[1])))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--old-tree', type=Path, help='fw/tmg9 export (repo root or its firmware/); default: git archive')
    ap.add_argument('--new-tree', type=Path, default=FW)
    ap.add_argument('--stock-old', type=Path)
    ap.add_argument('--stock-new', type=Path, default=ROOT/NEW_STOCK_REL)
    ap.add_argument('--table', type=Path)
    ap.add_argument('--no-mutation', action='store_true', help='skip the mutation check')
    args = ap.parse_args()
    tmp = Path(tempfile.mkdtemp(prefix='rebase-independent-'))
    try:
        old_root = args.old_tree or export_tmg9(tmp/'tmg9')
        old_fw = fw_dir(old_root)
        stock_old = args.stock_old or (old_fw.parent/OLD_STOCK_REL)
        new_fw = fw_dir(args.new_tree)
        table_path = args.table or new_fw/TABLE_REL
        table = json.loads(table_path.read_text())
        old, new = Image(load_ap(stock_old), '1.0.5.5'), Image(load_ap(args.stock_new), '1.0.5.12')
        fails = []
        print('images: old %d bytes, new %d bytes; copy tables old %s new %s' % (
            len(old.raw), len(new.raw), [tuple(map(hex, t)) for t in old.tables], [tuple(map(hex, t)) for t in new.tables]))
        for dst in (0x100000, RAM_LO):
            try:
                so, sn = old.region(dst), new.region(dst)
            except StopIteration:
                fails.append('no copy table entry for dst %s' % hex(dst))
        u, rows, d, derived, problems, tree_problems, table_problems, table_checked = run(
            old_fw, new_fw, table, old, new)
        report(rows)
        fails += problems + tree_problems + table_problems
        # NOT_STOCK tokens: none may have a literal in either stock image (region bounds are checked by the table)
        for t, n in sorted(not_stock_seen(old_fw, old).items()):
            v = int(t, 16)
            if v in (FLASH, RAM_LO):
                ok = v == FLASH or old.region(RAM_LO)[2] == v
            else:
                ok = not old.word_sites(v) and not new.word_sites(v)
            print('not stock: %s x%d  %s%s' % (t, n, NOT_STOCK[t], '' if ok else '  <- HAS A STOCK LITERAL'))
            if not ok:
                fails.append('NOT_STOCK token %s has a stock literal' % t)
        # coverage
        universe = (len(u['link']) + len(u['edits']) + len(u['abi']) + 1 + len(u['sites']))
        code_refs = len(u['link']) + len(u['edits']) + 1
        print('coverage: old tree universe %d addresses (%d link.ld + %d edits + module = %d code references; '
              '%d ABI ranges; %d literal values at %d sites), rows checked %d, table rows compared %d' % (
                  universe, len(u['link']), len(u['edits']), code_refs, len(u['abi']), len(u['sites']),
                  sum(sum(c.values()) for c in u['sites'].values()), len(rows), table_checked))
        if len(rows) != universe:
            fails.append('coverage: %d rows for %d universe addresses' % (len(rows), universe))
        if table_checked != universe:
            fails.append('coverage: table compared on %d of %d addresses' % (table_checked, universe))
        # known bad
        byname = {r['name']: r for r in rows if r['kind'] == 'link'}
        for name, (bad, good) in KNOWN_BAD.items():
            r = byname.get(name)
            at = r['old'] & ~1
            fwd, back = [], []
            for before, after in SIG_WINDOWS:
                data, keep, _, _ = masked_window(old, at + before, at + after)
                p = (bad & ~1) + before - FLASH
                n = sum(1 for k in range(len(data)) if (new.raw[p + k] ^ data[k]) & keep[k])
                (fwd if after >= 16 else back).append('%d..%d:%d' % (before, after, n))
            fwd_ok = all(not x.endswith(':0') for x in fwd)
            votes = d.callers(at)
            ok = r['new'] == good and fwd_ok and votes.get(bad & ~1, 0) == 0 and votes.get(good & ~1, 0) > 0
            print('known bad: %s old %s; matcher value %s: masked mismatches in the windows over the address %s, '
                  'over the code before it %s; caller votes %s; derived %s (expected %s) -> %s' % (
                      name, hex(r['old']), hex(bad), ' '.join(fwd), ' '.join(back),
                      {hex(k): v for k, v in votes.items()}, hex(r['new'] or 0), hex(good),
                      'REJECTED/FOUND' if ok else 'FAIL'))
            if not ok:
                fails.append('known bad %s not rejected' % name)
        # copy region and the strcmp veneer
        for name in COPY_CALLEES:
            r = byname[name]
            ok = r['new'] == r['old'] and 'copy' in r['methods'] and not old.has(r['old'])
            print('copy region: %s %s -> %s (%s)' % (name, hex(r['old']), hex(r['new'] or 0), r['methods'].get('copy')))
            if not ok:
                fails.append('copy-region callee %s moved or unchecked' % name)
        vr = byname[STRCMP_VENEER]
        for img, va in ((old, vr['old']), (new, vr['new'] or 0)):
            r_ = literal_ref(img, va & ~1)
            h1 = img.h(va & ~1)
            tgt = img.w(r_[0]) if r_ else None
            ok = (h1 & 0xff7f) == 0xf85f and (img.h((va & ~1) + 2) >> 12) == 15 and tgt == byname['strcmp']['old']
            print('strcmp veneer on %s at %s: ldr.w pc,[pc] -> %s %s' % (img.name, hex(va), hex(tgt or 0),
                                                                       'OK' if ok else 'FAIL'))
            if not ok:
                fails.append('strcmp veneer on %s does not reach strcmp' % img.name)
        # resume_X (link.ld) is the trampoline edit X + 4 (+ Thumb bit): two independently derived rows must agree
        edits = {r['name'].removeprefix('Entry trampoline '): r for r in rows if r['kind'] == 'edit'}
        n_resume = 0
        for name, r in byname.items():
            if name.startswith('resume_') and name[7:] in edits:
                e = edits[name[7:]]
                n_resume += 1
                if r['old'] != e['old'] + 5 or r['new'] != (e['new'] or 0) + 5:
                    fails.append('%s %s is not trampoline edit %s + 5' % (name, hex(r['new'] or 0), hex(e['new'] or 0)))
        print('resume symbols: %d, each the derived trampoline edit + 5' % n_resume)
        # mutation check
        if not args.no_mutation:
            fails += mutation(old_fw, new_fw, table, old, new, rows)
        print()
        agree = sum(1 for r in rows if r['new'] is not None and not r['problems'])
        print('result: %d rows, %d agree, %d fail; %d tree problems, %d table problems' % (
            len(rows), agree, len(rows) - agree, len(tree_problems), len(table_problems)))
        for f in fails:
            print('FAIL ' + f)
        if fails:
            return 1
        print('PASS rebase independent: %d addresses re-derived, tree and table agree' % len(rows))
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def mutation(old_fw, new_fw, table, old, new, rows):
    """Swap one link.ld address and one table address for a neighbour's, in temp copies; both must fail."""
    out = []
    link = [r for r in rows if r['kind'] == 'link' and r['new'] is not None and r['new'] != r['old']]
    a, b = link[0], link[1]
    base_tree = set(compare_tree(None, rows, new_fw, new))
    base_table = set(compare_table(rows, table)[0])
    with tempfile.TemporaryDirectory(prefix='rebase-mutation-') as t:
        tree = Path(t)/'firmware'
        shutil.copytree(new_fw, tree, ignore=shutil.ignore_patterns('__pycache__'))
        p = tree/'link.ld'
        text = p.read_text()
        text2 = re.sub(r'^(%s\s*=\s*)0x[0-9a-fA-F]+;' % re.escape(a['name']), r'\g<1>%s;' % hex(b['new']), text,
                       flags=re.M)
        assert text2 != text
        p.write_text(text2)
        tp = [x for x in compare_tree(None, rows, tree, new) if x not in base_tree and a['name'] in x]
        print('mutation: link.ld %s set to its neighbour %s\'s %s -> %d new tree problem(s) %s%s' % (
            a['name'], b['name'], hex(b['new']), len(tp), 'DETECTED' if tp else 'MISSED', (': ' + tp[0]) if tp else ''))
        if not tp:
            out.append('mutation of link.ld not detected')
        p.write_text(text)
        v = max((r for r in rows if r['kind'] == 'value' and r['new'] is not None and RAM_LO <= r['old'] < RAM_HI),
                key=lambda r: sum(r['sites'].values()))
        f = sorted(v['sites'])[0]
        q = tree/f
        q.write_text(q.read_text().replace(hex(v['new']), hex(v['new'] + 4), 1))
        tp = [x for x in compare_tree(None, rows, tree, new) if x not in base_tree and f in x]
        print('mutation: %s %s set to its neighbour word %s -> %d new tree problem(s) %s%s' % (
            f, hex(v['new']), hex(v['new'] + 4), len(tp), 'DETECTED' if tp else 'MISSED', (': ' + tp[0]) if tp else ''))
        if not tp:
            out.append('mutation of a RAM value not detected')
        mt = json.loads(json.dumps(table))
        row = next(x for x in mt['linkld'] if x['symbol'] == a['name'])
        row['new'] = hex(b['new'])
        tb = [x for x in compare_table(rows, mt)[0] if x not in base_table and a['name'] in x]
        print('mutation: table %s new set to %s -> %d new table problem(s) %s%s' % (
            a['name'], hex(b['new']), len(tb), 'DETECTED' if tb else 'MISSED', (': ' + tb[0]) if tb else ''))
        if not tb:
            out.append('mutation of the table not detected')
        e = next(r for r in rows if r['kind'] == 'edit')
        mt = json.loads(json.dumps(table))
        row = next(x for x in mt['edits'] if x['role'] == e['name'])
        row['newAddress'] = hex(e['new'] + 2)
        tb = [x for x in compare_table(rows, mt)[0] if x not in base_table and e['name'] in x]
        print('mutation: table edit %r newAddress +2 -> %d new table problem(s) %s%s' % (
            e['name'], len(tb), 'DETECTED' if tb else 'MISSED', (': ' + tb[0]) if tb else ''))
        if not tb:
            out.append('mutation of a table edit not detected')
    return out


if __name__ == '__main__':
    sys.exit(main())
