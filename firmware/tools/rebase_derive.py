"""Derive a rebase table for firmware/baseline/ (tools/rebase_apply.py TABLES). Two modes, mutually exclusive.

Offline and read-only on every input. Never connects to a device. Both modes refuse an --out or --report path inside
the repository (resolved, symlinks followed): a table file in firmware/baseline/ activates itself, so committing one is
a deliberate copy by a person, in its own reviewed commit. main(argv) is callable in-process.

Legacy mode (--lookup): the 1.0.5.5 to 1.0.5.12 table from the decomp's static rebase study. Usage (paths are examples):

  python3 -I firmware/tools/rebase_derive.py \
    --lookup  "$TURBO_INPUTS/decomp/dirty/wf-2/delta1012/tools/tmg-lookup.json" \
    --matches "$TURBO_INPUTS/decomp/dirty/wf-2/delta1012/ap/matches.json" \
    --study   "$TURBO_INPUTS/decomp/dirty/wf-2/delta1012/review-w1/TMG-REBASE.corrected.md" \
    --tree "$A"/tmg9/firmware --inputs-root "$TURBO_INPUTS" --out "$A"/legacy.json

Propose mode (--propose): a turboio-rebase-2 table from a readiness TSV of proposed addresses (see the end of this
docstring). Usage:

  python3 -I firmware/tools/rebase_derive.py --propose TSV --old-tree firmware --stock-old ZIP --stock-new ZIP \
    --from 1.0.5.12 --to 1.0.6.11 --out "$A"/table.json --report "$A"/report.json [--inputs-root DIR]

Acceptance only: `--disable-method NAME` (repeatable; body, align, start, edge2, entry, veneer, grow, edge-lit, fixed,
reviewed-site) runs propose with that method as none; it needs --report, refuses --out (a mutated run never writes a
table) and is named in the report's `disabledMethods`. `--self-test --stock-old ZIP --stock-new ZIP` runs the G and
twin fixtures (SELF_TEST_*) on the two AP images and exits 0 only when each gives its pinned outcome.

The tree read in legacy mode must be on stock 1.0.5.5 with the TMG9 pins: the TMG9 tree. Since the tree moved to
1.0.5.12, run it on an export of the tag (`git archive fw/tmg9 firmware | tar -x -C "$A"/tmg9`, then
`--tree "$A"/tmg9/firmware`); the output is byte-identical to the committed table minus its hand-added
tio_imu_family row. The decomp lookup supplies the proposed 1.0.5.12 address of every code reference
(matcher pair + offset, checked by window compare, masked signature search and call edges; see the study,
section 2). This script takes those values, applies the study's one manual correction (tgr_intercept), and
re-checks every value it writes against the two stock images by its own means (below). It refuses to write
the table if any check fails. Nothing here is typed by hand except the names of the four copy-region
functions and the correction, each of which is checked against the images.

Checks done here (each row records which ones it passed):
  window    the first 16 bytes at the old and new address are equal once every Thumb-2 T4 branch (B.W/BL) is
            masked (a moved callee changes only the branch displacement);
  sig       that masked pattern (24 bytes) occurs exactly once in the new image, at the new address;
  edges     every T4 branch in the window targets, in the new image, the matcher partner of its old target;
  literal   a PC-relative literal loaded at a rebased site holds the rebased value (shim, file callback);
  votes     the decomp's literal votes (aligned old literal sites in matcher-paired equal-size functions);
  field     a RAM address is base+offset: the same field offsets are read and written from the old base
            literal in the old image and from the new base literal at the matcher-partner sites in the new one;
  string    a .data string has the same bytes at the new address of the data copy.
The .data copy (file offset = VA - delta, and its length) is read from each image's copy descriptor at +0x674
(rebase_apply.data_copy).

Propose mode. The TSV (columns kind, name, addr_1012, final_verdict, new_address_1611, source) must hold exactly one row
per item of the old tree: its link.ld symbols, its edits by role, and the old table's 15 values and 11 stock ABI
ranges (their column of --from); anything else is fatal. The old table is the TABLES entry ending at --from, loaded by
path from the old tree. Both stock ZIPs go through build.safe_zip, check_stock_members and core_identity (the new one
against stock_zip.pinned(--to)), and the old tree must be wholly on --from. Every method below is computed from the two
stock images and from rows already accepted in this run; none reads the proposal, which is only compared with each
method's single answer. Any method that gives another answer rejects the row. Counting methods (the only names that
go in a row's `checks`):
  sig       masked_pattern(OLD image, old address, 24 bytes; an ABI range: its whole length) has exactly one even
            hit in the new image;
  call      old BL/B.W sites that target the old address (address order; up to 48 tried, up to 12 paired), each
            paired to the new image by its own masked 16-byte window (starting at the site) found exactly once there;
            the new branch target is a vote (at least one vote, and 75 % of the votes name one address); call
            locates only with at least two paired votes;
  edge      the T4 branches in the equal masked prefix of the 64-byte window at (old address, proposal) whose old
            target is a row already accepted in this run: each lands on that row's new address, at least one;
  lit       old PC-relative loads (LDR literal, 16- or 32-bit) of a word equal to the old value, tried and paired
            the same way; the word the paired new load reads is a vote (75 % rule); for an ABI range the word is the
            range address with bit 0 set (a code pointer is stored with its Thumb bit), and the votes name proposal | 1;
  field     native_light: [Rn,#value-R] at old sites whose Rn holds the accepted display unit R, paired the same way;
            the base word loaded at the new sites, plus the offset, is a vote (at least two paired sites);
  str       the NUL-terminated old string (or exactly its reviewed change) occurs once in the new data copy;
  copy      copy-region callees: identical bytes at the same runtime address (copy descriptor +0x408) in both images;
  body      the bounded body from x (to the first unconditional return outside an IT block, at most 0x200 bytes, at
            least 12) at T1, or T2 when T1 has no new hit: old hits exactly [x] and one new hit; otherwise an edge filter
            keeps the new hits with x's BL/B.W edges to anchors and must rule out every old twin by an edge to a
            different anchor with a different new value (one survivor, every twin ruled out);
  align     x starts a token inside an equal block (difflib, T2 tokens) of at least 8 tokens that occurs once in each
            span between the nearest anchors a < x and b >= x + max(n, 2), each within 0x4000 and in step (a' < b',
            spans within 0x400); an ABI range must lie wholly inside the block;
  start     s, the greatest accepted row 2..0x40 bytes below x with x inside its bounded body: the T2 tokens of [s, x)
            equal those at s' on an instruction boundary; the answer is s' + (x - s); s may be a row accepted through
            REVIEWED_SITES (start is the only method that anchors on one), and its proof then names it as reviewed;
            reviewed or not, the nearest row below x is s, so a nearer reviewed row is taken over a farther one;
  edge2     a T2 walk from (x, proposal) over max(64, n) bytes in step: BL/B.W pairs to anchors and LDR-literal pairs
            of accepted value rows' old words (edge-lit) must land on their new values, at least one;
  entry     x (an old BL/B.W target or aligned code pointer) starts a changed run in align's alignment, right after a
            unique equal block that ends in an unconditional return, with a unique next block of 8 tokens within 16
            tokens on each side; the answer is the first new token after the first block (never a row's only method);
  veneer    a 4-aligned ldr.w pc,[pc,#0] veneer whose literal maps through an anchor (or is identical copy-region code)
            and which occurs once in each image.
Masks: T0 masks BL/B.W displacements (masked_pattern); T1 also the offset and U bit of LDR literal and ADR and every pool
word an LDR in the window reads; T2 also immediates and local branch offsets. Anchors are accepted rows (link.ld code,
code values, edits, ABI ranges; never a row with a REVIEWED_SITES entry, except as start's s) and fixed functions: old BL/B.W targets whose
T1 bounded body (at least 24 bytes) occurs once in each image. A fixed function is never a row and decides nothing alone.
lit and field sites whose masked 16-byte window does not pair are tried with G, grown T1 windows (forward 12..64 bytes,
backward 4..48 bytes plus 16) that must pair one old hit with one new hit and be confirmed by the next window.
Never counting (proof only): the proposal, a signature built from the new image, the masked window at the proposal on
its own, a 4-byte prologue match, any `before` read from the new image, a string that merely differs.
A row is "shift" when its kind's primary method agrees (sig for code, copy for copy-region callees, lit with two
paired votes for RAM, field for native_light, str with identical bytes plus lit for data) and none disagrees;
"changed" when the primary does not hold and two other counting methods agree, with edge and edge2 counting as one,
and at least one of them is a locating method. A data row is instead "changed" when str holds with a reviewed change
plus lit. Locating methods find the
address from elsewhere in the images: lit, field, veneer, body, call when it has at least two paired votes, and start
when its anchor row is itself accepted without relying on start and not through REVIEWED_SITES. call with one paired
vote, and start on such an anchor, still agree or disagree but do not locate. Positional methods judge the code at or
around the proposal: align, entry, edge and edge2.
Two positional methods can be wrong together next to a near-identical neighbour, so they never decide a row alone;
the final re-check applies the same rule. A row listed in REVIEWED_SITES needs its old value and proposal, its pinned bytes hash, its named method agreeing
with exactly its pinned report string and no method disagreeing, or it is rejected; anything else is rejected with
every failed rule. Rows accepted in one pass vouch for others in the next (fixpoint); every accepted row is checked
again once all are known. An edit's new `before` must be the old one with each BL/B.W re-encoded to its
target's accepted row, or the pinned REVIEWED_BEFORE_CHANGES value. Exit 0 with no rejections, 3 otherwise (both
files are written; the table's `rejected` is filled in, so rebase_apply refuses to load it).
"""
import argparse
import bisect
import collections
import csv
import difflib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import struct
import sys
import zipfile

FW = Path(__file__).resolve().parents[1]
ROOT = FW.parent
FLASH = 0x10190000
DATA_RUNTIME = 0x18000000
OLD_BASE, NEW_BASE = '1.0.5.5', '1.0.5.12'
STOCK = {OLD_BASE: ROOT/'firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip',
         NEW_BASE: ROOT/'firmware-research/strix-1.0.5.12/stock/Strix-OS-1.0.5.12-original.zip'}
# The study's manual correction (TMG-REBASE.corrected.md section 2): the matcher's extrapolated value was wrong.
CORRECTIONS = {'tgr_intercept': 0x1062c439}
# Copy +0x408 region (memcpy, memset, strcmp, strlen): copied to the same address in both images.
COPY_REGION = range(0x100000, 0x101000)
# Stock code addresses in the TMG9 tree that the decomp study did not collect (it skipped files outside
# build-inputs.json). Each is derived here from the matcher pair + offset and must pass window and unique signature.
# Found by the independent check (tests/rebase_independent_test.py, tmg10(5)).
EXTRA_CODE = (
    (0x105f6170, 'lv_timer_create_comment', 'native_page.c comment: stock lv_timer_create (native_page.c is not in build-inputs.json)'),
)
# Sites written after TMG9, so not in the TMG9 tree the table is derived from: {value name: {file: (count, reason)}}.
ADDED_SITES = {
    'display_unit': {'src/image-upload-test/render_idle_test.c': (1,
        'tmg10(6): the fixture key was 0x18617cb0, the 1.0.4.12 display unit 0x18617b8c + 0x124, never moved to 1.0.5.5, '
        'so the test failed on TMG9 too; it is now written as display unit + 0x124 like render_idle.c')},
}
# Hex tokens inside the stock windows (AP flash of either base, RAM 0x18000000-0x1a000000, copy region) that are not
# stock addresses. Each must have no literal in either stock image (checked here). rebase_apply.py --check fails on
# any other such token that is not a value of the tree's base.
NOT_STOCK = {
    '0x10190000': 'FLASH base of the AP image (a region bound)',
    '0x18000000': 'RAM base, .data copy destination (a region bound)',
    '0x18001000': 'fake display unit in native_display_test.c', '0x18002000': 'fake display in native_display_test.c',
    '0x19000000': 'fake unit in render_idle_test.c', '0x1900000c': 'fake unit field', '0x19000018': 'fake unit field',
    '0x19000100': 'fake unit in render_idle_test.c', '0x1900010c': 'fake unit field', '0x19000118': 'fake unit field',
    '0x19100000': 'fake display in render_idle_test.c', '0x191002a0': 'fake display field',
    '0x19200000': 'fake layer in render_idle_test.c', '0x19200038': 'fake layer field', '0x19200040': 'fake layer field',
}
# Files that quote addresses of both bases on purpose; the leftover scan skips them (their values are checked by
# the tests themselves).
SCAN_EXEMPT = {
    'tests/stock_abi_test.py': 'pins the 11 ranges at their 1.0.5.5 addresses and maps them through this table',
    'tests/rebase_independent_test.py': 'the independent verifier quotes known-bad and reference values',
}
THUMB_CONVENTION = ('Every value is written exactly as the tree uses it. Function addresses that are called or '
    'stored as code pointers (link.ld symbols, the shim pointer, the render dispatch values, the align_pointer_cb '
    'comment) carry the Thumb bit (odd). Patch sites (edits offset/address) are even byte addresses. RAM and .data '
    'addresses are plain byte addresses (a string may start at an odd address; that is not a Thumb bit). For every '
    'code value the bit is preserved: new & 1 == old & 1.')


def sha(data, algorithm='sha256'):
    return hashlib.new(algorithm, data).hexdigest()


def H(x):
    return int(x, 16)


def stock_info(path):
    raw = path.read_bytes()
    with zipfile.ZipFile(path) as z:
        files = {n: z.read(n) for n in z.namelist()}
    ap = files['nuttx_ap.bin']
    return raw, files, ap


def version_block(member):
    out = {}
    for key in ('SW_VER', 'BUILD_VER', 'REV_INFO'):
        found = re.findall(rb'\n?' + key.encode() + rb'=([^\n\x00]*)', member)
        assert len(found) == 1, key
        out[key] = found[0].decode().strip('"')
    return out


def is32(h):
    return (h & 0xf800) in (0xe800, 0xf000, 0xf800)


def t4(h1, h2):
    return (h1 & 0xf800) == 0xf000 and (h2 & 0xd000) in (0x9000, 0xd000)


def t4_target(site, h1, h2):
    s = (h1 >> 10) & 1
    i1 = 1 ^ (((h2 >> 13) & 1) ^ s)
    i2 = 1 ^ (((h2 >> 11) & 1) ^ s)
    d = (s << 24) | (i1 << 23) | (i2 << 22) | ((h1 & 0x3ff) << 12) | ((h2 & 0x7ff) << 1)
    if s:
        d -= 1 << 25
    return site + 4 + d


def t4_encode(site, target, link):
    d = (target & ~1) - (site + 4)
    assert d % 2 == 0 and -(1 << 24) <= d < (1 << 24)
    bits = d & 0x1ffffff
    s = (bits >> 24) & 1
    i1 = (bits >> 23) & 1
    i2 = (bits >> 22) & 1
    j1 = 1 ^ (i1 ^ s)
    j2 = 1 ^ (i2 ^ s)
    return struct.pack('<HH', 0xf000 | (s << 10) | ((bits >> 12) & 0x3ff),
                       (0xd000 if link else 0x9000) | (j1 << 13) | (j2 << 11) | ((bits >> 1) & 0x7ff))


def instructions(image, address, length):
    """(offset, size, is_t4, halfwords) for each instruction in [address, address+length)."""
    at = address - FLASH
    i = 0
    while i < length:
        h1 = struct.unpack_from('<H', image, at + i)[0]
        if is32(h1):
            h2 = struct.unpack_from('<H', image, at + i + 2)[0]
            yield i, 4, t4(h1, h2), (h1, h2)
            i += 4
        else:
            yield i, 2, False, (h1,)
            i += 2


def movw(hw):
    """(Rd, imm16) of a Thumb-2 T3 MOVW, else None."""
    if len(hw) != 2 or (hw[0] & 0xfbf0) != 0xf240 or hw[1] & 0x8000:
        return None
    h1, h2 = hw
    return (h2 >> 8) & 0xf, ((h1 & 0xf) << 12) | (((h1 >> 10) & 1) << 11) | (((h2 >> 12) & 7) << 8) | (h2 & 0xff)


def masked_window(old, oa, new, na, length, event_ids=None):
    """Equal except T4 branch displacements? Returns (equal, [(old_target, new_target)]).

    With a list for event_ids, a MOVW whose immediate is an ap-01 event ID (>= 0x700) that grew by exactly 0x100
    with the same destination register is also accepted, and recorded in that list."""
    branches = []
    for i, size, branch, hw in instructions(old, oa, length):
        if i + size > length:
            break
        o = old[oa - FLASH + i: oa - FLASH + i + size]
        n = new[na - FLASH + i: na - FLASH + i + size]
        if event_ids is not None and o != n and movw(hw) and size == 4:
            mo, mn = movw(hw), movw(struct.unpack('<HH', n))
            if mn and mo[0] == mn[0] and mo[1] >= 0x700 and mn[1] == mo[1] + 0x100:
                event_ids.append({'at': hex(oa + i), 'old': hex(mo[1]), 'new': hex(mn[1])})
                continue
        if branch:
            n1, n2 = struct.unpack('<HH', n)
            if not t4(n1, n2) or (hw[1] & 0x4000) != (n2 & 0x4000):
                return False, branches
            branches.append((t4_target(oa + i, *hw), t4_target(na + i, n1, n2)))
        elif o != n:
            return False, branches
    return True, branches


def masked_pattern(image, address, length):
    parts = []
    for i, size, branch, hw in instructions(image, address, length):
        if i + size > length:
            break
        b = image[address - FLASH + i: address - FLASH + i + size]
        parts.append(b'(?:.{4})' if branch else re.escape(b))
    return re.compile(b''.join(parts), re.S)


def unique_at(image, address, length):
    pattern = masked_pattern(image, address, length)
    hits = [m.start() + FLASH for m in pattern.finditer(image) if m.start() % 2 == 0]
    # finditer does not report overlapping matches; enough for uniqueness of non-periodic code.
    return hits


class Matcher:
    def __init__(self, matches):
        self.old = sorted(matches['old'], key=lambda f: H(f['addr']))
        self.starts = [H(f['addr']) for f in self.old]
        self.new = {H(f['addr']): f for f in matches['new']}

    def containing(self, a):
        i = bisect.bisect_right(self.starts, a) - 1
        if i < 0:
            return None, False
        f = self.old[i]
        return f, a < H(f['addr']) + f['size']

    def map(self, a, extrapolate=False):
        f, inside = self.containing(a & ~1)
        if f is None or not f.get('match') or f['class'] == 'removed' or (not inside and not extrapolate):
            return None
        return H(f['match']) + (a & ~1) - H(f['addr']) | (a & 1)


def checks_code(old, new, matcher, oa, na, length=16, event_ids=False):
    """Run window/sig/edges at an even code address pair; return a list of passed check names and notes.

    event_ids: the function is matcher-changed in ap-01 (event IDs +0x100); accept exactly that difference."""
    passed, notes = [], []
    equal, branches = masked_window(old, oa, new, na, length)
    moved = []
    if not equal and event_ids:
        equal, branches = masked_window(old, oa, new, na, length, moved)
    if equal:
        passed.append('window' if not moved else 'window(event IDs +0x100: %s)' %
                      ', '.join('%s %s->%s' % (m['at'], m['old'], m['new']) for m in moved))
        hits = unique_at(new, na, 24)
        if hits == [na]:
            passed.append('sig')
        else:
            notes.append('masked 24-byte signature hits: %d' % len(hits))
        mapped = [matcher.map(t) for t, _ in branches]
        if branches and all(m is not None and m == n for m, (_, n) in zip(mapped, branches)):
            passed.append('edges')
        elif branches:
            notes.append('branch targets: ' + ', '.join('%s->%s (matcher %s)' % (hex(t), hex(n), hex(m) if m else 'none')
                                                        for (t, n), m in zip(branches, mapped)))
    else:
        prefix = max([k for k in range(2, length + 1, 2) if masked_window(old, oa, new, na, k)[0]] or [0])
        notes.append('%d-byte masked window differs after byte %d (literal pool or immediate change)' % (length, prefix))
    return passed, notes


def tree_values(fw):
    """link.ld symbols as written in the tree."""
    out = {}
    for line in (fw/'link.ld').read_text().splitlines():
        m = re.match(r'\s*(\w+)\s*=\s*(0x[0-9a-fA-F]+);', line)
        if m:
            out[m.group(1)] = H(m.group(2))
    return out


SCANNED = ('src', 'include', 'tests', 'link.ld', 'trampolines.S', 'ImageWireFormat.h')


def scan_sites(fw, token):
    """Every file under the scanned parts of the tree that writes the exact hex token (case-insensitive)."""
    found = {}
    pattern = re.compile(r'(?<![0-9A-Za-z_])' + re.escape(token) + r'(?![0-9A-Za-z_])', re.I)
    for part in SCANNED:
        p = fw/part
        paths = [p] if p.is_file() else sorted(q for q in p.rglob('*') if q.is_file())
        for q in paths:
            try:
                text = q.read_text()
            except UnicodeDecodeError:
                continue
            n = len(pattern.findall(text))
            if n:
                found[q.relative_to(fw).as_posix()] = n
    return found


def field_sites(image, base, offsets):
    """ldr/str [Rn,#off] where Rn was loaded from a PC-relative literal equal to base within 48 bytes before."""
    hits = []
    for i in range(0, len(image) - 4, 2):
        h1, h2 = struct.unpack_from('<HH', image, i)
        if (h1 & 0xfff0) in (0xf8d0, 0xf8c0) and (h2 & 0xfff) in offsets:
            rn, off, kind = h1 & 0xf, h2 & 0xfff, 'ldr' if (h1 & 0xfff0) == 0xf8d0 else 'str'
        elif (h1 & 0xf000) == 0x6000 and ((h1 >> 6) & 0x1f) * 4 in offsets:
            rn, off, kind = (h1 >> 3) & 7, ((h1 >> 6) & 0x1f) * 4, 'ldr' if h1 & 0x800 else 'str'
        else:
            continue
        for j in range(i - 2, max(0, i - 48), -2):
            g = struct.unpack_from('<H', image, j)[0]
            literal = None
            if (g & 0xf800) == 0x4800 and ((g >> 8) & 7) == rn:
                literal = ((j + 4) & ~3) + (g & 0xff) * 4
            elif j >= 2 and struct.unpack_from('<H', image, j - 2)[0] == 0xf8df and (g >> 12) == rn:
                literal = ((j - 2 + 4) & ~3) + (g & 0xfff)
            if literal is not None:
                if literal + 4 <= len(image) and struct.unpack_from('<I', image, literal)[0] == base:
                    hits.append((FLASH + i, kind, off))
                break
    return hits


def pc_literal(image, site):
    """Value loaded by a 16-bit `ldr rX, [pc, #imm]` at site."""
    g = struct.unpack_from('<H', image, site - FLASH)[0]
    assert (g & 0xf800) == 0x4800, hex(site)
    at = ((site + 4) & ~3) + (g & 0xff) * 4
    return (g >> 8) & 7, struct.unpack_from('<I', image, at - FLASH)[0]


def described(path, inputs_root):
    """Provenance path without a home directory: relative to $TURBO_INPUTS or to the repository."""
    path = Path(path).resolve()
    for root, label in ((ROOT, ''), (inputs_root, '$TURBO_INPUTS/')):
        if root:
            try:
                return label + path.relative_to(Path(root).resolve()).as_posix()
            except ValueError:
                pass
    raise SystemExit('input outside the repository and $TURBO_INPUTS: pass --inputs-root')


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rebase_apply():
    """tools/rebase_apply.py beside this file (data_copy, data_file_delta, TABLES, load_table, problems)."""
    return load_module(FW/'tools'/'rebase_apply.py', 'rebase_derive_apply')


def refuse_inside(paths, trees=()):
    """Refuse an output inside the repository, inside a tree read, or inside that tree's checkout (resolved, symlinks
    followed): a table file in firmware/baseline/ would activate itself (rebase_apply TABLES)."""
    roots = [ROOT.resolve()]
    for t in trees:
        t = Path(t).resolve()
        roots += [t] + ([t.parent] if (t.parent/'.git').exists() else [])
    def inside(r, root):
        # By spelling and by file identity: on a case-insensitive volume a differently cased spelling of the repository
        # resolves to a different string but to the same directory (same st_dev and st_ino).
        if r == root or root in r.parents:
            return True
        if not root.exists():
            return False
        return any(a.exists() and os.path.samefile(a, root) for a in (r,) + tuple(r.parents))
    for p in paths:
        r = Path(p).resolve()
        for root in roots:
            if inside(r, root):
                raise SystemExit('refused: %s lies inside the repository or a tree read (%s); write it elsewhere and '
                                 'copy a table into firmware/baseline/ by hand, in its own reviewed commit' % (p, root))


def same_file(a, b):
    """True when two paths name one file: equal once resolved (compared case-insensitively, which can only refuse more),
    or both existing with the same st_dev and st_ino."""
    a, b = Path(a), Path(b)
    if str(a.resolve()).casefold() == str(b.resolve()).casefold():
        return True
    return a.exists() and b.exists() and os.path.samefile(a, b)


def refuse_overwrite(outputs, inputs):
    """Refuse (exit 1, before any work) an output that names an input file of the run, or two outputs naming one file."""
    outputs = [(n, p) for n, p in outputs if p is not None]
    for i, (n, p) in enumerate(outputs):
        for m, q in outputs[i + 1:] + [(m, q) for m, q in inputs if q is not None]:
            if same_file(p, q):
                raise SystemExit('refused: %s %s is the same file as %s %s; it would be overwritten' % (n, p, m, q))


def legacy(args):
    rebase = rebase_apply()
    lookup = json.loads(args.lookup.read_text())
    matcher = Matcher(json.loads(args.matches.read_text()))
    raw_old, files_old, old = stock_info(STOCK[OLD_BASE])
    raw_new, files_new, new = stock_info(STOCK[NEW_BASE])
    tree = args.tree.resolve()
    spec = json.loads((tree/'build-inputs.json').read_text())
    assert sha(raw_old) == spec['stockZIP'] and sha(old) == spec['stockAP'], 'the tree must be on stock 1.0.5.5 (TMG9)'
    failures = []

    def require(ok, message):
        if not ok:
            failures.append(message)

    # ---- link.ld callees -------------------------------------------------------------------------
    linkld = tree_values(tree)
    rows = []
    rows_by_old = {}
    assert [r['sym'] for r in lookup['linkld']] == [s for s in linkld if s not in ()], 'lookup and link.ld disagree on symbols'
    for r in lookup['linkld']:
        sym, oa = r['sym'], H(r['old'])
        require(linkld[sym] == oa, sym + ': lookup old value is not the tree value')
        na = CORRECTIONS.get(sym, H(r['new']))
        row = {'symbol': sym, 'old': hex(oa), 'new': hex(na), 'delta': (na & ~1) - (oa & ~1),
               'oldFunction': r.get('func'), 'insideGhidraBody': r.get('inside_body'), 'class': r.get('cls'),
               'decomp': {k: r.get(k) for k in ('window32', 'sig_n', 'edge_check') if r.get(k) is not None}}
        require(na & 1 == oa & 1 == 1, sym + ': Thumb bit')
        if sym in CORRECTIONS:
            row['correction'] = ('decomp lookup proposed %s (matcher offset extrapolated past the Ghidra body of %s); '
                                 'the study (section 2) found the unique signature at %s' % (r['new'], r.get('func'), hex(na)))
        if (oa & ~1) in COPY_REGION:
            fo, _ = matcher.containing(oa & ~1)
            fn = matcher.new[H(fo['match'])]
            so = H(fo['fileoff']) + (oa & ~1) - H(fo['addr'])
            sn = H(fn['fileoff']) + (na & ~1) - H(fn['addr'])
            require(na == oa and old[so:so + 24] == new[sn:sn + 24], sym + ': copy region')
            row['checks'] = ['copy-region (24 bytes equal, same address)']
        else:
            passed, notes = checks_code(old, new, matcher, oa & ~1, na & ~1, event_ids=r.get('cls') == 'changed')
            veneer = lambda image, a: (struct.unpack_from('<HH', image, a - FLASH), struct.unpack_from('<I', image, a - FLASH + 4)[0])
            if veneer(old, oa & ~1)[0] == (0xf85f, 0xf000):
                # `ldr.w pc, [pc, #-0]` veneer: same instruction and the same literal target (the callee did not move).
                require(veneer(old, oa & ~1) == veneer(new, na & ~1), sym + ': veneer target')
                passed.append('veneer(target %s unchanged)' % hex(veneer(new, na & ~1)[1]))
            if not any(c.startswith('window') for c in passed):
                # Literal-pool words inside the first 16 bytes: compare 4 bytes (the prologue) instead.
                if old[(oa & ~1) - FLASH:(oa & ~1) - FLASH + 4] == new[(na & ~1) - FLASH:(na & ~1) - FLASH + 4]:
                    passed.append('prologue4')
            require(passed, sym + ': no check passed')
            if r.get('inside_body') is False or sym in CORRECTIONS:
                # Extrapolated rows: the masked window and a unique signature are both required.
                require(any(c.startswith('window') for c in passed) and 'sig' in passed, sym + ': extrapolated row lacks window+sig')
            row['checks'] = passed
            if notes:
                row['notes'] = notes
        rows.append(row)
        rows_by_old[oa] = na
    # ---- the 25 edits ------------------------------------------------------------------------------
    edits = []
    by_role = {e['role']: e for e in spec['edits']}
    assert [e['role'] for e in lookup['edits']] == [e['role'] for e in spec['edits']]
    for r in lookup['edits']:
        e = by_role[r['role']]
        oa, na = H(e['address']), H(r['new'])
        assert H(r['old']) == oa and oa % 2 == 0 and na % 2 == 0
        before = bytes.fromhex(e['before'])
        expect = bytearray(before)
        reencoded = []
        for i, size, branch, hw in instructions(old, oa, len(before)):
            if branch:
                target = t4_target(oa + i, *hw)
                mapped = rows_by_old.get(target | 1)
                require(mapped is not None, r['role'] + ': branch target %s is not a link.ld callee' % hex(target))
                if mapped is not None:
                    expect[i:i + 4] = t4_encode(na + i, mapped, bool(hw[1] & 0x4000))
                    reencoded.append({'at': i, 'oldTarget': hex(target | 1), 'newTarget': hex(mapped)})
        actual = new[na - FLASH: na - FLASH + len(before)]
        require(bytes(expect) == actual, r['role'] + ': re-recorded before pattern is not the new stock bytes')
        passed, notes = checks_code(old, new, matcher, oa, na, 32 if len(before) <= 32 else len(before),
                                    event_ids=r.get('cls') == 'changed')
        row = {'role': r['role'], 'oldAddress': hex(oa), 'newAddress': hex(na), 'oldOffset': hex(oa - FLASH),
               'newOffset': hex(na - FLASH), 'delta': na - oa, 'oldBefore': e['before'], 'newBefore': actual.hex(),
               'oldFunction': r.get('func'), 'insideGhidraBody': r.get('inside_body'), 'class': r.get('cls'),
               'checks': passed + ['before'], 'decomp': {k: r.get(k) for k in ('window32', 'sig_n') if r.get(k) is not None}}
        if reencoded:
            row['reencodedBranches'] = reencoded
        if notes:
            row['notes'] = notes
        if r.get('inside_body') is False:
            require(any(c.startswith('window') for c in passed) and 'sig' in passed,
                    r['role'] + ': extrapolated edit lacks window+sig')
        edits.append(row)
    # ---- literal values in sources -----------------------------------------------------------------
    shim_fn = next(r for r in lookup['shim'] if r['old'] == '0x10569ba5')
    shim_struct = next(r for r in lookup['shim'] if r['old'] == '0x196aea48')
    src = {r['old']: r for r in lookup['sources']}
    top = lambda r: max(r['votes'].items(), key=lambda kv: kv[1])
    values = []

    def value(name, kind, old_value, new_value, evidence, checks, **extra):
        token = hex(old_value)
        sites = scan_sites(tree, token)
        require(sites, name + ': not found in the tree')
        values.append({'name': name, 'kind': kind, 'old': token, 'new': hex(new_value), 'sites': sites,
                       'evidence': evidence, 'checks': checks, **extra})

    # File-callback registration (edit 25): `movs r4,#0; ldr r0,[pc]; ldr r3,[pc]; str r4,[r0,#0x18]; str r3,[r0]`.
    reg = next(x for x in edits if x['role'] == 'File callback registration')
    lit_old = [pc_literal(old, H(reg['oldAddress']) + k) for k in (2, 4)]
    lit_new = [pc_literal(new, H(reg['newAddress']) + k) for k in (2, 4)]
    v_struct, n_struct = top(shim_struct)
    require(lit_old == [(0, 0x196aea48), (3, 0x10569ba5)], 'file callback: old literals')
    require(lit_new == [(0, H(v_struct)), (3, H(shim_fn['new']))], 'file callback: new literals')
    value('file_callback_struct', 'ram', 0x196aea48, H(v_struct),
          'decomp votes %s (%d of %d literal sites); the stock registration at the new edit site loads it as r0' %
          (v_struct, n_struct, shim_struct['old_literal_sites']), ['votes', 'literal'])
    p, _ = checks_code(old, new, matcher, 0x10569ba4, H(shim_fn['new']) & ~1)
    value('stream_register_target', 'code', 0x10569ba5, H(shim_fn['new']),
          'decomp matcher pair FUN_10569ba4 (identical, unique signature); the stock registration at the new edit site '
          'loads it as r3', p + ['literal'])
    g = src['0x19971594']
    v, n = top(g)
    require(n == g['old_literal_sites'] == 3, 'launcher global votes')
    value('launcher_global', 'ram', 0x19971594, H(v), 'decomp votes %s (%d of %d literal sites)' % (v, n, g['old_literal_sites']), ['votes'])
    d = src['0x184d4440']
    v, n = top(d)
    unit_old, unit_new = 0x184d4440, H(v)
    offsets = {0x124, 0x1bc, 0x1c0}
    f_old = field_sites(old, unit_old, offsets)
    f_new = field_sites(new, unit_new, offsets)
    mapped = [(matcher.map(a, extrapolate=True), k, o) for a, k, o in f_old]
    require(None not in [m[0] for m in mapped] and sorted(mapped, key=str) == sorted(f_new, key=str),
            'display unit: field sites do not pair: %s vs %s' % ([(hex(a or 0), k, o) for a, k, o in mapped], [(hex(a), k, o) for a, k, o in f_new]))
    field_note = ('%d ldr/str sites at +0x124/+0x1bc/+0x1c0 from the base literal in the old image; their matcher partners '
                  'are exactly the %d sites that use the new base literal in the new image' % (len(f_old), len(f_new)))
    value('display_unit', 'ram', unit_old, unit_new, 'decomp votes %s (%d of %d literal sites); %s' %
          (v, n, d['old_literal_sites'], field_note), ['votes', 'field'])
    for name, old_value, off in (('native_light_current', 0x184d45fc, 0x1bc), ('native_light_peak', 0x184d4600, 0x1c0)):
        require(old_value == unit_old + off, name + ': not base+offset')
        require(any(o == off and k == 'ldr' for _, k, o in f_old) and any(o == off and k == 'str' for _, k, o in f_old), name)
        guess = old_value + 0x17f44  # the study's neighbour shift (INF), kept as a cross-check only
        require(unit_new + off == guess, name + ': field method and neighbour shift disagree')
        value(name, 'ram', old_value, unit_new + off,
              'display unit + %s (field method: %s); agrees with the study\'s neighbour shift +0x17f44' % (hex(off), field_note),
              ['field'])
    for token in ('0x18052201', '0x1805240d', '0x18177273', '0x1804300a'):
        r = src[token]
        require(r['n_hits'] == 1, token + ': string not unique')
        o, nv = H(token), H(r['new_hits'][0])
        so = old[o - rebase.data_file_delta(old):].split(b'\0', 1)[0]
        sn = new[nv - rebase.data_file_delta(new):].split(b'\0', 1)[0]
        require(so == sn and so.decode('latin-1').startswith(r['old_string']), token + ': string bytes')
        v, n = top(r)
        require(H(v) == nv, token + ': votes disagree with the string search')
        value('coexist_string_' + so.decode()[:24].replace(' ', '_').strip('[]'), 'data', o, nv,
              'string %r found once in the new data copy; decomp votes %s (%d of %d literal sites)' %
              (so.decode(), v, n, r['old_literal_sites']), ['string', 'votes'], string=so.decode())
    for token, name in (('0x10428d89', 'render_dispatch_gpu'), ('0x105335ff', 'render_dispatch_sw'),
                        ('0x10427cd1', 'align_pointer_cb_comment'), ('0x10721750', 'recorder_helper_comment')):
        r = src[token]
        o, nv = H(token), H(r['new'])
        require(nv & 1 == o & 1, name + ': Thumb bit')
        p, notes = checks_code(old, new, matcher, o & ~1, nv & ~1)
        if r['votes']:
            v, n = top(r)
            require(H(v) == nv and n == r['old_literal_sites'], name + ': votes disagree with the matcher')
            p.append('votes')
        require('window' in p and 'sig' in p, name + ': window+sig')
        value(name, 'code', o, nv, 'decomp matcher %s+%s (%s body); literal votes %s' %
              (r['func'], hex(r['offset']), 'inside' if r['inside_body'] else 'outside', r['votes'] or 'none'), p)
    for o, name, why in EXTRA_CODE:
        na = matcher.map(o)
        require(na is not None and na & 1 == o & 1, name + ': no matcher partner inside a body')
        p, notes = checks_code(old, new, matcher, o & ~1, na & ~1)
        require('window' in p and 'sig' in p, name + ': window+sig')
        f, _ = matcher.containing(o)
        value(name, 'code', o, na, '%s; matcher %s+%s (inside body, %s)' % (why, f['addr'], hex(o - H(f['addr'])), f['class']), p)
    for x in values:
        if x['name'] in ADDED_SITES:
            x['addedSites'] = {f: c for f, (c, _) in ADDED_SITES[x['name']].items()}
            x['addedSitesReason'] = {f: r for f, (_, r) in ADDED_SITES[x['name']].items()}
    for t, why in NOT_STOCK.items():
        word = struct.pack('<I', H(t))
        bound = t in ('0x10190000', '0x18000000')
        # An aligned word outside the .data copy source (initialised data, not code literals).
        aligned = lambda image, copy: any(i % 4 == 0 and not copy[0] - FLASH <= i < copy[1] - FLASH
                                          for i in (m.start() for m in re.finditer(re.escape(word), image)))
        require(bound or not (aligned(old, rebase.data_copy(old)) or aligned(new, rebase.data_copy(new))),
                t + ': listed as not stock but is an aligned code literal in a stock image')
    news = {x['new'].lower() for x in values}
    olds = {x['old'].lower() for x in values}
    require(not news & olds, 'a new value equals an old value: rewriting would be ambiguous')
    # ---- the 11 stock ABI ranges (tests/stock_abi_test.py) -----------------------------------------
    ns = {'__file__': str(tree/'tests/stock_abi_test.py')}
    exec(compile((tree/'tests/stock_abi_test.py').read_text().split('def main')[0], 'stock_abi_test', 'exec'), ns)
    ranges = []
    for address, length, digest in ns['RANGES']:
        require(sha(old[address - FLASH: address - FLASH + length]) == digest, hex(address) + ': old range hash')
        f, inside = matcher.containing(address)
        na = matcher.map(address, extrapolate=True)
        equal, branches = masked_window(old, address, new, na, length)
        literals = []
        if not equal:
            # A trailing literal-pool word that is a code pointer may differ only by the rebase of its target.
            for cut in range(length - 4, 0, -4):
                if (address + cut) % 4 == 0 and masked_window(old, address, new, na, cut)[0]:
                    words = [(struct.unpack_from('<I', old, address - FLASH + k)[0], struct.unpack_from('<I', new, na - FLASH + k)[0])
                             for k in range(cut, length, 4)]
                    if all(matcher.map(o, extrapolate=True) == n for o, n in words):
                        equal, branches = masked_window(old, address, new, na, cut)
                        literals = [{'at': hex(address + cut + 4 * k), 'old': hex(o), 'new': hex(n)} for k, (o, n) in enumerate(words)]
                    break
        hits = unique_at(new, na, length - 4 * len(literals))
        mapped = [matcher.map(t) for t, _ in branches]
        edges = all(m == n for m, (_, n) in zip(mapped, branches))
        require(equal and edges and (hits == [na] or (inside and na in hits)), hex(address) + ': range does not pair')
        ranges.append({'old': hex(address), 'new': hex(na), 'bytes': length, 'oldSHA256': digest,
                       'newSHA256': sha(new[na - FLASH: na - FLASH + length]), 'oldFunction': f['addr'],
                       'insideGhidraBody': inside, 'branches': len(branches),
                       'checks': ['window(full range)'] + (['sig(full range)'] if hits == [na] else ['sig(%d hits, inside a matcher-identical body)' % len(hits)])
                                 + (['edges'] if branches else []) + (['mapped literal'] if literals else []),
                       **({'mappedLiterals': literals} if literals else {})})
    # ---- stock bases --------------------------------------------------------------------------------
    bases = {}
    for base, raw, files in ((OLD_BASE, raw_old, files_old), (NEW_BASE, raw_new, files_new)):
        cores = {n: version_block(files[n]) for n in ('nuttx_ap.bin', 'nuttx_apc1.bin', 'nuttx_bth.bin')}
        bases[base] = {'stockZIPFile': STOCK[base].relative_to(ROOT).as_posix(), 'stockZIP': sha(raw), 'stockZIPBytes': len(raw),
                       'stockAP': sha(files['nuttx_ap.bin']), 'stockAPBytes': len(files['nuttx_ap.bin']),
                       'stockMembers': {n: sha(b) for n, b in sorted(files.items()) if n != 'OtaFileInfo.json'},
                       'cores': cores, 'moduleVA': hex(FLASH + len(files['nuttx_ap.bin']) - 8)}
    require(bases[OLD_BASE]['moduleVA'] == spec['moduleVA'], 'old module VA')
    if failures:
        raise SystemExit('rebase table NOT written:\n  ' + '\n  '.join(failures))
    table = {
        'format': 'turboio-rebase-1',
        'from': OLD_BASE, 'to': NEW_BASE,
        'note': 'Generated by firmware/tools/rebase_derive.py; do not edit by hand. Applied by firmware/tools/rebase_apply.py.',
        'thumbConvention': THUMB_CONVENTION,
        'provenance': {
            'inputs': [{'role': role, 'path': described(p, args.inputs_root), 'sha256': sha(Path(p).read_bytes())}
                       for role, p in (('decomp lookup (proposed addresses, checks)', args.lookup),
                                       ('decomp matcher pairs (stock ABI ranges, branch edges)', args.matches),
                                       ('decomp study, corrected copy (tgr_intercept correction, method)', args.study))],
            'stock': {b: bases[b]['stockZIPFile'] for b in bases},
            'tree': 'TMG9 tree (fw/tmg9, stock 1.0.5.5 addresses)',
            'corrections': {k: hex(v) for k, v in CORRECTIONS.items()},
        },
        'bases': bases,
        'moduleVA': {'old': bases[OLD_BASE]['moduleVA'], 'new': bases[NEW_BASE]['moduleVA'],
                     'derivation': 'FLASH 0x10190000 + stock AP bytes - 8 (the module is appended before the 8-byte trailer)'},
        'linkld': rows,
        'edits': edits,
        'values': values,
        'notStock': NOT_STOCK,
        'scanExempt': SCAN_EXEMPT,
        'stockAbiRanges': ranges,
    }
    args.out.write_text(json.dumps(table, indent=1) + '\n')
    counts = {'linkld': len(rows), 'moved': sum(r['new'] != r['old'] for r in rows), 'edits': len(edits),
              'reencoded': sum('reencodedBranches' in e for e in edits), 'values': len(values),
              'sites': sum(sum(v['sites'].values()) for v in values), 'ranges': len(ranges)}
    print(json.dumps(counts))


# ---- propose mode (turboio-rebase-2) ---------------------------------------------------------------------------
# Reviewed exceptions, keyed by the new base (`to`). Literals, each checked against the images on every run; never
# filled in from a run. REVIEWED_SITES (below) pins each entry's evidence: bytes and one method's exact report string.
REVIEWED_BEFORE_CHANGES = {  # {(to, role): new before}; typed from the 1.0.6.11 AP (sha256 9bbf7be3...) at the readiness addresses
    ('1.0.6.11', 'Menu replacement frame_start'): '1e2380b5',  # clamp to 6 replaced by usat 0..7; the b.w covers two whole instructions
    ('1.0.6.11', 'Menu replacement label_index'): '90b581f3',  # clamp to 6 replaced by usat 0..7; full replacement, never returns
    ('1.0.6.11', '284-byte menu allocation'): '4ff4867050f07cfc',  # mov.w r0,#0x10c + bl, 8 bytes (pad 2)
    ('1.0.6.11', 'Carousel item count 7 to 13'): '0821',  # stock count 8; phase F4 sets the after value (REVIEWED_AFTER_CHANGES)
    ('1.0.6.11', 'File callback registration'): '00242048214b84610360',  # the two ldr literal offsets moved by 4 bytes
}
# {(to, role): new after} of a raw edit, decided in phase F4: the carousel count follows the 8 stock + 6 module tile model.
REVIEWED_AFTER_CHANGES = {('1.0.6.11', 'Carousel item count 7 to 13'): '0e21'}  # movs r1,#14
REVIEWED_STRING_CHANGES = {('1.0.6.11', 'coexist_string_APP_INFO]_[Service.h:58'): (':58]', ':62]', 'line number moved in stock')}
# {(to, TSV kind, TSV name): {'old', 'new', 'bytes': (n, sha256 of new[new&~1 : +n]), 'votes': (method, exact report
# string), 'reason'}}, one entry per line. An entry applies only when the row's old value and proposal are `old` and
# `new`, the bytes hash matches, the named method agrees with exactly that string, and no method disagrees; otherwise
# the row is rejected and the reason names the entry. A row accepted through an entry never vouches for another row,
# except as start's anchor s: start then agrees or disagrees, but it does not locate (see the pair rule below).
_SPLIT = 'stock split old 0x1057cfc4: the 22-byte 0x106f4b58 calls the head 0x106f4b24 and then the old name lookup, so it returns the top app name (const char *) as the callers need; the signature names a bool-returning decoy'
REVIEWED_SITES = {
    ('1.0.6.11', 'linkld', 'nav_top_app'): {'old': 0x1057cfc5, 'new': 0x106f4b59, 'bytes': (22, 'baf4fbe59c5c921aae141bfaf4afdb32228345a3b798b00d049eb29414c53726'), 'votes': ('call', '12 of 12 paired votes for 0x106f4b58'), 'reason': _SPLIT},
    ('1.0.6.11', 'linkld', 'ce_ext_106d3310'): {'old': 0x1057cfc5, 'new': 0x106f4b59, 'bytes': (22, 'baf4fbe59c5c921aae141bfaf4afdb32228345a3b798b00d049eb29414c53726'), 'votes': ('call', '12 of 12 paired votes for 0x106f4b58'), 'reason': _SPLIT},
    ('1.0.6.11', 'edit', 'Menu replacement label_index'): {'old': 0x10686d18, 'new': 0x106a5044, 'bytes': (50, '7e80e9d52858a45823ca5113b1a6cfdeca7e506fcf0fabb2e0d76b125485c772'), 'votes': ('entry', 'tail block 79 tokens (once in each span) ends in a return; next block 19 tokens (once in each span); gaps 5 old, 2 new'), 'reason': 'head rewritten in stock (clamp to 6 became usat 0..7); its one caller does not pair, so only entry places it'},
    ('1.0.6.11', 'edit', '284-byte menu allocation'): {'old': 0x10683278, 'new': 0x106a139c, 'bytes': (76, 'f6eb6fe3bd8202834f9fbbbc116650c4b5f524653f0a6485fb5d34a73d39593f'), 'votes': ('start', 's linkld nav_ensure_menu (reviewed entry) 0x10683240->0x106a1364, 56-byte T2 prefix equal'), 'reason': 'movs r0,#0xfc (2 bytes) became mov.w r0,#0x10c (4 bytes), which breaks every token alignment at the site'},
    ('1.0.6.11', 'value-code', 'stream_register_target'): {'old': 0x10583605, 'new': 0x105a7d39, 'bytes': (80, '48e2464129687b8e8f7cbdb38526ae3b9f0d56ad32887703c6549a3faa1ad32b'), 'votes': ('lit', '1 of 1 paired votes for 0x105a7d39 (1 by G)'), 'reason': 'head changed in stock (push.w {r4-r8,lr} became push {r4-r7,lr}) and it has no callers; its one pool word, paired by G, names it'},
    # Rows that no agreeing pair with a locating method decides (the pair rule for `changed`).
    ('1.0.6.11', 'edit', 'Menu replacement frame_start'): {'old': 0x10685de2, 'new': 0x106a4116, 'bytes': (16, 'c1940a5fbe9307fe7ec7fbe158271a99d35d3f82b0e0e4045afb8100cf19043c'), 'votes': ('call', '2 of 2 paired votes for 0x106a4116'), 'reason': 'head rewritten in stock (clamp to 6 became usat 0..7), as for label_index; the edit replaces the whole function, so its bytes match nothing old and only the paired callers place it'},
    ('1.0.6.11', 'linkld', 'native_wake_overlay'): {'old': 0x10683721, 'new': 0x106a1845, 'bytes': (10, '8c1a495b34f55f550876cff50f36565c46f614a10603c08d1acd8f0d2fb99ae1'), 'votes': ('align', 'equal block of 78 tokens (62 before x, 15 after), once in each span; anchors 0x10683688->0x106a17ac (fixed), 0x10683748->0x106a186c (fixed)'), 'reason': 'a 10-byte thunk (push, bl, pop) with no paired caller and no pool word; body is under 12 bytes, so only the positional align and edge2 place it'},
    ('1.0.6.11', 'edit', 'File callback registration'): {'old': 0x10583be6, 'new': 0x105a8482, 'bytes': (126, '2bf5c9c25ac7b0a0363d24dd9e41fc64c872e92faf4c351d7ec5585066e79d35'), 'votes': ('align', 'equal block of 75 tokens (58 before x, 16 after), once in each span; anchors 0x10583b60->0x105a83fc (fixed), 0x10583c94->0x105a8538 (fixed)'), 'reason': 'a patch site inside a function, not a call target; stock added a store to the struct\'s new +0x20 slot after the site, so body finds no new hit and only the positional align and edge2 (literal edge to file_callback_struct) place it'},
    # Rows whose one locating method was a single paired caller (call locates only with two paired votes).
    ('1.0.6.11', 'linkld', 'dots_stock_notify'): {'old': 0x10584425, 'new': 0x105a8ced, 'bytes': (248, 'd941bbe769f8e34b59da51d2afd17413771f944ba22c50cf13d29f9cd92f9094'), 'votes': ('call', '1 of 1 paired votes for 0x105a8cec'), 'reason': 'its one caller pairs and names it; its bounded body (228 bytes old, 248 new) has no T2 hit in the new image and no pool word or anchor row within 0x40 below names it, so besides that caller only the positional align places it'},
    ('1.0.6.11', 'linkld', 'nav_ensure_menu'): {'old': 0x10683241, 'new': 0x106a1365, 'bytes': (132, '1020fb1e2ba5a386a1bc954fa537781146be77e37b57a4ea8ff9f76b1192263e'), 'votes': ('call', '1 of 1 paired votes for 0x106a1364'), 'reason': 'one of its two callers pairs and names it (the other does not pair); its bounded body (130 bytes old, 132 new) has no T2 hit in the new image and no pool word or anchor row within 0x40 below names it, so besides that caller only the positional align and edge2 place it'},
    # TMG13 additions (REVIEWED_UNIVERSE_CHANGES addLinkld, addEdits) that no agreeing pair with a locating method decides.
    ('1.0.6.11', 'linkld', 'kws_enable'): {'old': 0x10559b75, 'new': 0x1057e77d, 'bytes': (102, '41177a62f189592b4b1be9863e929a91b8c9f6e3e830fabccf28a51e041236f9'), 'votes': ('call', '1 of 1 paired votes for 0x1057e77c'), 'reason': 'identical-code twin of kws_disable (the two differ in their log string pool words and the enable flag, which the masks hide), so sig has two hits; one of its three callers pairs and names it, and align, edge and edge2 agree'},
    ('1.0.6.11', 'linkld', 'kws_disable'): {'old': 0x10559be9, 'new': 0x1057e7f1, 'bytes': (100, 'b893eafaf9611353a4303e69e18019421556e6e2226e0cf5d1d9fd053c36b332'), 'votes': ('call', '1 of 1 paired votes for 0x1057e7f0'), 'reason': 'identical-code twin of kws_enable, as above; one of its two callers pairs and names it, and align, edge and edge2 agree'},
    ('1.0.6.11', 'edit', 'Entry trampoline wheel_read'): {'old': 0x1071caf0, 'new': 0x1078e644, 'bytes': (120, '2b41e7338293c71b8bbb507a168074f9786376fa8d5c224448cbf4981609bcd5'), 'votes': ('lit', '1 of 1 paired votes for 0x1078e645'), 'reason': 'the RayNeo wheel read callback, rewritten in stock 1.0.6.11 (it gained the step accumulator), so neither sig nor body finds it; it has no BL caller, and its one stored pointer, loaded into r1 and passed to the indev slot setter at the paired wheel-create site, names it (the addEdits pointer rule checks that site)'},
    ('1.0.6.11', 'linkld', 'resume_wheel_read'): {'old': 0x1071caf5, 'new': 0x1078e649, 'bytes': (116, '933d8461b21d8ae3704e9d094c306a3eb079ac8f97480be304e849fc6befe5ea'), 'votes': ('start', 's edit Entry trampoline wheel_read (reviewed entry) 0x1071caf0->0x1078e644, 4-byte T2 prefix equal'), 'reason': 'the instruction after the push (sub sp) changed with the rewrite, so sig finds nothing; start places it from its own edit, and the fixpoint requires it to be that edit + 4 + 1'},
    ('1.0.6.11', 'linkld', 'resume_screen_state'): {'old': 0x10645d4d, 'new': 0x10655a61, 'bytes': (96, '34130bcfa8699bc7428682dfe555ece90c24e6b0efa4fa140b75716502020642'), 'votes': ('start', 's edit Entry trampoline screen_state 0x10645d48->0x10655a5c, 4-byte T2 prefix equal'), 'reason': 'the instruction after the push is a pc-relative load whose offset moved (0xf8 became 0x108), so sig finds nothing; start places it from its own edit, and the fixpoint requires it to be that edit + 4 + 1'},
    ('1.0.6.11', 'abi-range', '0x10686caa'): {'old': 0x10686caa, 'new': 0x106a4fd6, 'bytes': (18, '77ae3ae8ee8475e1f9525e348b6f8304daa4e0e81d6ca9b5366c1cea1ff908e5'), 'votes': ('align', 'equal block of 79 tokens (36 before x, 35 after), once in each span; anchors 0x10686c4a->0x106a4f76 (linkld resume_wheel), 0x10686db8->0x106a50e0 (linkld native_snap)'), 'reason': 'an 18-byte function with six old twins and no paired caller or pool word (its two pointer loads do not pair); body leaves one twin not ruled out, so only the positional align, edge and edge2 place it'},
}
# Reviewed departures of the NEW tree from the old tree's universe, keyed by `to` (decided in phase F4). Every row is still
# derived and checked from the old tree exactly as before, so no other row's evidence and no REVIEWED_SITES entry
# changes; only the table written differs. pruneLinkld: link.ld rows left out of the table (the new tree no longer
# defines them). valueToLinkld: a value row written as a link.ld row of the given symbol, with the same old and new
# address and evidence, and no value row (the new tree names the address once, in link.ld).
REVIEWED_UNIVERSE_CHANGES = {
    '1.0.6.11': {
        'pruneLinkld': ('dots_getrandom', 'dots_stock_notify', 'ce_utc_time', 'ce_focus_manager', 'ce_focus_enabled',
                        'ce_head_mode', 'ce_stock_head_notify_resume', 'ce_stock_head_start_resume',
                        'ce_stock_head_stop_resume', 'ce_stock_sys_destroy_resume'),
        'valueToLinkld': {'launcher_global': 'tio_launcher_global'},
        'addLinkld': {'tio_light_latest': {'old': '0x1062c3d5', 'new': '0x1061bea9'},
                      # TMG13 PIN lock (SYMBOLS.md, HOOKS.md of the lock RE; old values found by a masked-prologue
                      # search of the new entry over the old image and by the paired callers, then derived here)
                      'pmu_rtc_epoch': {'old': '0x10586a49', 'new': '0x105ab2b9'},
                      'kws_enable': {'old': '0x10559b75', 'new': '0x1057e77d'},
                      'kws_disable': {'old': '0x10559be9', 'new': '0x1057e7f1'},
                      'key_queue_flush': {'old': '0x1062c5f1', 'new': '0x1061c5b1'},
                      'ots_topic_read': {'old': '0x10620fcd', 'new': '0x1064d47d'},
                      'tio_key_interceptors': {'old': '0x197546e4', 'new': '0x197656dc'}},
        # addEdits (TMG13 PIN lock): entry trampolines the old tree does not have. Each is derived and checked from its
        # old address like any edit row (rule 1 before: the old before, which has no BL/B.W, must be the new image's
        # bytes); its old address must be an old BL/B.W target with at least one paired caller naming the proposal
        # (by a 16-byte window or by G), so it is a function entry in both images. Each also adds the link.ld row
        # resume_<name> = address + len(before) | 1, derived like any code row and required to equal its edit's
        # accepted address + len(before) | 1. entry 'pointer' (the two input read callbacks, which stock reaches only
        # through a stored function pointer and never by BL/B.W): instead of a paired caller, lit on the Thumb pointer
        # (old address | 1) must agree with at least one paired vote, and every paired load site must be an LDR into the
        # argument register `arg` (default r1) followed directly by a BL whose old target's 24-byte masked pattern occurs
        # once in each image, the new hit being the new BL's target (one consumer in both images: the indev slot setter for
        # the read callbacks, the LVGL timer constructor for the factory-reset worker; SETTER_BYTES).
        'addEdits': {
            'Entry trampoline can_wakeup': {'old': '0x1055a488', 'new': '0x1057f034', 'before': '2de9f041', 'kind': 'bw',
                                            'target': 'lock_hook_can_wakeup'},
            'Entry trampoline open_remote_audio': {'old': '0x1055dbcc', 'new': '0x10582878', 'before': '2de9f047', 'kind': 'bw',
                                                   'target': 'lock_hook_open_remote_audio'},
            'Entry trampoline open_recorder': {'old': '0x1055ccfc', 'new': '0x105819d8', 'before': 'f0b583b0', 'kind': 'bw',
                                               'target': 'lock_hook_open_recorder'},
            'Entry trampoline screen_state': {'old': '0x10645d48', 'new': '0x10655a5c', 'before': '2de9f041', 'kind': 'bw',
                                              'target': 'lock_hook_screen_state'},
            # the factory-reset worker timer callback (SysStateMonitor.cpp 'start rnlink factory_reset'): handleResetFactoryResult
            # creates its timer only when the ERPC reset reports success, after every refusal check
            'Entry trampoline factory_reset': {'old': '0x10586098', 'new': '0x105aa8e8', 'before': 'b0b582b0', 'kind': 'bw',
                                               'target': 'lock_hook_factory_reset', 'entry': 'pointer', 'arg': 0},
            'Entry trampoline key_read': {'old': '0x1080a918', 'new': '0x1088f67c', 'before': '002390b5', 'kind': 'bw',
                                          'target': 'lock_hook_key_read', 'entry': 'pointer'},
            'Entry trampoline wheel_read': {'old': '0x1071caf0', 'new': '0x1078e644', 'before': '2de9f04f', 'kind': 'bw',
                                            'target': 'lock_hook_wheel_read', 'entry': 'pointer'},
        },
        'reason': 'referenced by no built file, header or edit target (tools/check_layout.py pin); the launcher '
                  'global is named once, in link.ld, instead of at eleven source sites; phase F5 adds the light getter '
                  '(addLinkld: a symbol the old tree does not have, derived and checked from its old address like any row); '
                  'TMG13 adds the PIN lock\'s stock calls, the key interceptor list head (RAM) and seven entry trampolines '
                  '(addEdits)',
        # correctComment (phase F7 candidate 3): a code-comment value row whose old address was never the function the
        # comment names. The row is derived and checked from the old tree exactly as before and must still give
        # `derived`; only the table written takes `new`, which must hold the pinned bytes, start a function by its bytes
        # (a pool word that a pc-relative load reads right before it, and a push {..., lr} at it) and, when `linkld`
        # is given, be that accepted link.ld row's address. The row records the derived address as derivedNew.
        'correctComment': {
            'lv_timer_create_comment': {
                'derived': '0x10631b44', 'new': '0x104db610', 'bytes': (114, 'a2abd86a112ebaad6ff81c2c80090378d5018cc1f5ded25ae6d40210728a5d26'),
                'linkld': 'stream_timer_create',
                'reason': 'the derived address lies inside an unrelated function; the comment names the LVGL timer '
                          'constructor (stores the period at +0, the callback at +8 and the user data at +0xc), which is '
                          'link.ld stream_timer_create'},
            'recorder_helper_comment': {
                'derived': '0x107c6cc0', 'new': '0x105f9460', 'bytes': (86, '4503e72442837d4f93999c6345fff93a54dd87dc70438e6b337fb31bb865caa4'),
                'reason': 'the derived address lies inside an unrelated sort routine; the comment names the helper that '
                          'clears a 64-byte statfs buffer, calls statfs and returns the word at +8 times the 64-bit '
                          'word at +32'},
        },
    },
}
FIELD_BASES = {'native_light_current': 'display_unit', 'native_light_peak': 'display_unit'}  # field method: value -> RAM base value
NEW_COUNTING = ('body', 'align', 'start', 'edge2', 'entry', 'veneer')
COUNTING = ('sig', 'copy', 'call', 'edge', 'lit', 'field', 'str') + NEW_COUNTING
# The pair rule for `changed`: at least one of the two agreeing methods must locate the address from elsewhere in the
# images. LOCATING always locates when it agrees. LOCATING_IF locates only under a condition checked per row and pass:
# call with at least CALL_LOCATING_VOTES paired votes (one mispaired caller can name a near-identical sibling), start
# when its anchor row is accepted without relying on start and not through REVIEWED_SITES. Otherwise they still agree
# or disagree, but do not locate.
LOCATING = ('lit', 'field', 'veneer', 'body')
LOCATING_IF = ('call', 'start')
CALL_LOCATING_VOTES = 2
POSITIONAL = ('align', 'entry', 'edge', 'edge2')  # the rule reads only LOCATING and LOCATING_IF, so the split is checked below
PRIMARY_ONLY = ('sig', 'copy', 'str')  # primaries that are neither locating nor positional (lit and field locate)
if sorted(LOCATING + LOCATING_IF + POSITIONAL + PRIMARY_ONLY) != sorted(COUNTING):
    raise SystemExit('rebase_derive: LOCATING, LOCATING_IF, POSITIONAL and PRIMARY_ONLY must split COUNTING exactly once each')
if LOCATING_IF != ('call', 'start'):  # evaluate() codes a condition for exactly these two; a new member needs its own
    raise SystemExit('rebase_derive: LOCATING_IF has a method whose locating condition is not coded in evaluate()')
LOCATING_TEXT = ('lit, field, veneer, body, call with at least %d paired votes, or start on an anchor row accepted without '
                 'start and not through a reviewed entry' % CALL_LOCATING_VOTES)
DISABLE_METHODS = NEW_COUNTING + ('grow', 'edge-lit', 'fixed', 'reviewed-site')  # --disable-method (acceptance only)
SIG_BYTES, SITE_BYTES, EDGE_BYTES, WINDOW_BYTES, COPY_BYTES = 24, 16, 64, 32, 32
SETTER_BYTES = 24  # addEdits entry 'pointer': masked pattern that must pair the pointer's consumer across the images
MAX_VOTES, MAX_TRIES = 12, 48  # paired votes per method, old sites tried per method
COPY_DESCRIPTOR = 0x408  # <3I src, end, dst> of the copy to 0x100000 (memcpy, memset, strcmp, strlen)
TSV_COLUMNS = ('kind', 'name', 'addr_1012', 'final_verdict', 'new_address_1611', 'source')
MODULE_DERIVATION = 'FLASH 0x10190000 + stock AP bytes - 8 (the module is appended before the 8-byte trailer)'


def find_all(data, needle, start=0, end=None):
    """Every offset of needle in data[start:end], overlapping occurrences included."""
    end = len(data) if end is None else end
    out, at = [], data.find(needle, start, end)
    while at >= 0:
        out.append(at)
        at = data.find(needle, at + 1, end)
    return out


def masked_hits(image, source, address, length):
    """Every even VA of `image` where masked_pattern(source, address, length) matches, overlapping hits included.
    Anchored on the pattern's longest unmasked run for speed; each candidate is confirmed by the pattern itself."""
    pattern = masked_pattern(source, address, length)
    runs, start, run = [], 0, b''
    for i, size, branch, hw in instructions(source, address, length):
        if i + size > length:
            break
        if branch:
            runs, run = runs + ([(start, run)] if run else []), b''
        else:
            start, run = (start if run else i), run + source[address - FLASH + i: address - FLASH + i + size]
    runs += [(start, run)] if run else []
    if not runs or max(len(r) for _, r in runs) < 4:
        return [m.start() + FLASH for m in re.finditer(b'(?=' + pattern.pattern + b')', image, re.S) if m.start() % 2 == 0]
    off, anchor = max(runs, key=lambda r: len(r[1]))
    return [at - off + FLASH for at in find_all(image, anchor)
            if at >= off and (at - off) % 2 == 0 and pattern.match(image, at - off)]


def masked_prefix(old, oa, new, na, length):
    """Bytes from the start, in whole instructions, over which the masked window at (oa, na) is equal."""
    done = 0
    for i, size, branch, hw in instructions(old, oa, length):
        if i + size > length or not masked_window(old, oa + i, new, na + i, size)[0]:
            break
        done = i + size
    return done


def masked_differences(old, oa, new, na, length):
    """Offsets of the instructions that differ once T4 branch displacements are masked."""
    return [i for i, size, branch, hw in instructions(old, oa, length)
            if i + size <= length and not masked_window(old, oa + i, new, na + i, size)[0]]


def branch_index(image):
    """{even target VA: [site VA, ...]} of every halfword pair that decodes as a T4 BL/B.W, in address order."""
    index = {}
    for m in re.finditer(rb'(?=.[\xf0-\xf7].[\x90-\x9f\xb0-\xbf\xd0-\xdf\xf0-\xff])', image, re.S):
        i = m.start()
        if i % 2 == 0:
            h1, h2 = struct.unpack_from('<HH', image, i)
            assert t4(h1, h2)
            index.setdefault(t4_target(FLASH + i, h1, h2), []).append(FLASH + i)
    return index


def load_literal(image, site):
    """(size, Rt, literal VA, word) of the PC-relative LDR (16-bit T1 or LDR.W literal) at site, else None."""
    at = site - FLASH
    if not 0 <= at <= len(image) - 4:
        return None
    h, h2 = struct.unpack_from('<HH', image, at)
    base = (site + 4) & ~3
    if (h & 0xf800) == 0x4800:
        size, rt, lit = 2, (h >> 8) & 7, base + (h & 0xff) * 4
    elif h in (0xf8df, 0xf85f):
        size, rt, lit = 4, h2 >> 12, base + (h2 & 0xfff) if h & 0x80 else base - (h2 & 0xfff)
    else:
        return None
    if not FLASH <= lit <= FLASH + len(image) - 4:
        return None
    return size, rt, lit, struct.unpack_from('<I', image, lit - FLASH)[0]


def literal_index(image):
    """{literal VA: [site VA, ...]} of every PC-relative LDR in the image, in address order."""
    index = {}
    for pattern in (rb'(?=.[\x48-\x4f])', rb'(?=[\xdf\x5f]\xf8)'):
        for m in re.finditer(pattern, image, re.S):
            got = load_literal(image, FLASH + m.start()) if m.start() % 2 == 0 else None
            if got:
                index.setdefault(got[2], []).append(FLASH + m.start())
    return {k: sorted(v) for k, v in index.items()}


def field_base(image, site):
    """The literal word that Rn of the ldr/str [Rn,#imm] at site was loaded from (field_sites' backward search)."""
    i = site - FLASH
    h1 = struct.unpack_from('<H', image, i)[0]
    if (h1 & 0xfff0) in (0xf8d0, 0xf8c0):
        rn = h1 & 0xf
    elif (h1 & 0xf000) == 0x6000:
        rn = (h1 >> 3) & 7
    else:
        return None
    for j in range(i - 2, max(0, i - 48), -2):
        g = struct.unpack_from('<H', image, j)[0]
        literal = None
        if (g & 0xf800) == 0x4800 and ((g >> 8) & 7) == rn:
            literal = ((j + 4) & ~3) + (g & 0xff) * 4
        elif j >= 2 and struct.unpack_from('<H', image, j - 2)[0] == 0xf8df and (g >> 12) == rn:
            literal = ((j - 2 + 4) & ~3) + (g & 0xfff)
        if literal is not None:
            return struct.unpack_from('<I', image, literal)[0] if literal + 4 <= len(image) else None
    return None


def tally(votes, minimum=1):
    """(answer, n, m): the one value that at least 75 % of the m votes name (n of them), or None."""
    if len(votes) < minimum:
        return None, 0, len(votes)
    top, n = collections.Counter(votes).most_common(1)[0]
    return (top if 4 * n >= 3 * len(votes) else None), n, len(votes)


def copy_bytes(image, address):
    """COPY_BYTES of the copy-region code at runtime `address` (copy descriptor +0x408), else None."""
    src, end, dst = struct.unpack_from('<3I', image, COPY_DESCRIPTOR)
    assert dst == 0x100000 and FLASH <= src < end <= FLASH + len(image), 'copy descriptor +0x408 is out of range'
    off = (address & ~1) - dst
    return image[src - FLASH + off: src - FLASH + off + COPY_BYTES] if 0 <= off and off + COPY_BYTES <= end - src else None


# ---- propose mode, F2 methods: bounded bodies, T1/T2 masks, anchors, grown site windows --------------------------
BL_KEEP = b'\x00\xf8\x00\xd0'  # BL/B.W: opcode and link bit kept, displacement masked


def half(image, va):
    return struct.unpack_from('<H', image, va - FLASH)[0]


def it_count(h):
    """Instructions an IT instruction covers (1 to 4), or 0 when h is not an IT."""
    if (h & 0xff00) != 0xbf00 or not h & 0xf:
        return 0
    return 5 - (h & 0xf & -(h & 0xf)).bit_length()


def is_return(h1, h2):
    """An unconditional-return encoding: pop {..,pc}, bx lr, pop.w/ldm sp! with pc, ldr pc,[sp],#4 (IT is checked apart)."""
    return ((h1 & 0xff00) == 0xbd00 or h1 == 0x4770 or (h1 == 0xe8bd and h2 is not None and bool(h2 & 0x8000))
            or (h1, h2) == (0xf85d, 0xfb04))


def is_literal_load(h1):
    """LDR literal, 16-bit or .W (U bit either way)."""
    return (h1 & 0xf800) == 0x4800 or h1 in (0xf8df, 0xf85f)


def t1_keep(h1, h2):
    """T1 keep mask of an LDR literal or ADR (offset field and U bit masked), else None."""
    if h2 is None:
        return b'\x00\xff' if (h1 & 0xf800) in (0x4800, 0xa000) else None
    if h1 in (0xf8df, 0xf85f):
        return b'\x7f\xff\x00\xf0'
    if (h1 & 0xfbff) in (0xf20f, 0xf2af) and not h2 & 0x8000:   # ADR.W: add or sub form, i:imm3:imm8
        return b'\x5f\xfb\x00\x8f'
    return None


def bits(word, high, low):
    """The bit field word[high:low] (inclusive), as the ARM ARM writes encodings."""
    return (word >> low) & ((1 << (high - low + 1)) - 1)


def clear(width, *fields):
    """An all-ones keep mask of `width` bits with each (high, low) bit field cleared."""
    keep = (1 << width) - 1
    for high, low in fields:
        keep &= ~(((1 << (high - low + 1)) - 1) << low)
    return keep


def t2_keep(h1, h2):
    """T2 keep mask of an instruction with an immediate field or a local branch offset (spec B, T2), else None.
    Written field by field from the ARM ARM Thumb encoding tables: each test names the opcode bits of one encoding,
    and the mask clears that encoding's immediate (or branch offset) fields."""
    if h2 is None:
        fields = None
        if bits(h1, 15, 13) == 0b000 and bits(h1, 12, 11) != 0b11:
            if bits(h1, 12, 11) or bits(h1, 10, 6):                # LSL/LSR/ASR #imm5 (LSL #0 is MOVS register)
                fields = ((10, 6),)
        elif bits(h1, 15, 10) == 0b000111:                         # ADDS/SUBS #imm3
            fields = ((8, 6),)
        elif bits(h1, 15, 13) == 0b001:                            # MOVS/CMP/ADDS/SUBS #imm8
            fields = ((7, 0),)
        elif bits(h1, 15, 12) in (0b0110, 0b0111, 0b1000):         # LDR/STR, LDRB/STRB, LDRH/STRH #imm5
            fields = ((10, 6),)
        elif bits(h1, 15, 12) in (0b1001, 0b1010):                 # LDR/STR [sp,#imm8], ADR, ADD Rd,sp,#imm8
            fields = ((7, 0),)
        elif bits(h1, 15, 8) == 0b10110000:                        # ADD/SUB sp,#imm7
            fields = ((6, 0),)
        elif bits(h1, 15, 12) == 0b1011 and bits(h1, 10, 10) == 0 and bits(h1, 8, 8) == 1:
            fields = ((9, 9), (7, 3))                              # CBZ/CBNZ: i and imm5
        elif bits(h1, 15, 12) == 0b1101 and bits(h1, 11, 9) != 0b111:
            fields = ((7, 0),)                                     # B<cond> (cond 1110 is UDF, 1111 is SVC)
        elif bits(h1, 15, 11) == 0b11100:                          # B #imm11
            fields = ((10, 0),)
        return None if fields is None else struct.pack('<H', clear(16, *fields))
    f1 = f2 = None
    rn = bits(h1, 3, 0)
    if bits(h1, 15, 9) == 0b1111100 and rn != 15:
        # load/store single: S h1[8], size h1[6:5], L h1[4]; signed forms are loads of bytes or halfwords only
        s, size, load = bits(h1, 8, 8), bits(h1, 6, 5), bits(h1, 4, 4)
        if size != 0b11 and (not s or (load and size != 0b10)):
            if bits(h1, 7, 7):                                     # #imm12
                f1, f2 = (), ((11, 0),)
            elif bits(h2, 11, 11):                                 # #imm8 (1PUW forms)
                f1, f2 = (), ((7, 0),)
    elif bits(h1, 15, 9) == 0b1110100 and bits(h1, 6, 6) and (bits(h1, 8, 8) or bits(h1, 5, 5)) and rn != 15:
        f1, f2 = (), ((7, 0),)                                     # LDRD/STRD #imm8 (P or W set)
    elif bits(h1, 15, 11) == 0b11110 and not bits(h2, 15, 15):
        if not bits(h1, 9, 9):                                     # data processing, modified immediate: i, imm3, imm8
            f1, f2 = ((10, 10),), ((14, 12), (7, 0))
        elif bits(h1, 8, 4) in (0b00100, 0b01100):                 # MOVW/MOVT: i, imm4, imm3, imm8
            f1, f2 = ((10, 10), (3, 0)), ((14, 12), (7, 0))
        elif bits(h1, 8, 4) in (0b00000, 0b01010):                 # ADDW/SUBW: i, imm3, imm8
            f1, f2 = ((10, 10),), ((14, 12), (7, 0))
    elif bits(h1, 15, 8) == 0b11101101 and not bits(h1, 5, 5) and bits(h2, 11, 9) == 0b101:
        f1, f2 = (), ((7, 0),)                                     # VLDR/VSTR #imm8
    elif bits(h1, 15, 7) == 0b111011101 and bits(h1, 5, 4) == 0b11 and bits(h2, 11, 9) == 0b101 and not bits(h2, 7, 4):
        f1, f2 = ((3, 0),), ((3, 0),)                              # VMOV.F32 #imm: imm4H, imm4L
    if f1 is None and bits(h1, 15, 11) == 0b11110 and bits(h2, 15, 14) == 0b10 and not bits(h2, 12, 12) and bits(h1, 9, 7) != 0b111:
        f1, f2 = ((10, 10), (5, 0)), ((13, 13), (11, 11), (10, 0))  # B<cond>.W: S, imm6, J1, J2, imm11
    return None if f1 is None else struct.pack('<HH', clear(16, *f1), clear(16, *f2))


def is_pool(tok):
    return not any(tok[3])


class Anchors:
    """The evidence align, start, edge2, entry, veneer and body's edge filter build on: accepted rows that were not
    accepted through REVIEWED_SITES ({even old VA: (even new VA, row name)}), accepted value rows for literal edges
    ({old word: (new word, row name)}), and, unless disabled, fixed functions (Methods.fixed). `reviewed` holds the
    code rows accepted through REVIEWED_SITES ({even old VA: (even new VA, row name)}); only start reads it
    (nearest(..., reviewed=True)). Such a source ends in REVIEWED_ANCHOR, which start keeps in its evidence string
    (so a reviewed entry pinned on that string stops applying when the anchor stops being reviewed) and strips from
    its `row` field (always a plain row label)."""
    REVIEWED_ANCHOR = ' (reviewed entry)'

    def __init__(self, methods, rows, values, reviewed=None):
        self.m, self.rows, self.values = methods, rows, values
        self.reviewed = {t: (v, src + self.REVIEWED_ANCHOR) for t, (v, src) in (reviewed or {}).items() if t not in rows}
        self.row_list, self.reviewed_list = sorted(rows), sorted(self.reviewed)

    def at(self, t, rows_only=False, reviewed=False):
        """(new, source) for the even old code address t: an accepted row, else (reviewed: a row accepted through
        REVIEWED_SITES), else a fixed function, else (None, None)."""
        if t in self.rows:
            return self.rows[t]
        if reviewed and t in self.reviewed:
            return self.reviewed[t]
        f = None if rows_only else self.m.fixed(t)
        return (f, 'fixed') if f is not None else (None, None)

    def nearest(self, x, lo, hi, down, rows_only=False, reviewed=False):
        """(t, t', source) of the anchor in [lo, hi] nearest to x (down: from hi towards lo), else (None, None, None).
        A fixed function whose bounded body contains x is skipped: it would repeat body's evidence. reviewed: rows
        accepted through REVIEWED_SITES are candidates too (start only)."""
        cands = set(self.row_list[bisect.bisect_left(self.row_list, lo):bisect.bisect_right(self.row_list, hi)])
        if reviewed:
            rl = self.reviewed_list
            cands.update(rl[bisect.bisect_left(rl, lo):bisect.bisect_right(rl, hi)])
        if not rows_only:
            tl = self.m.target_list
            cands.update(tl[bisect.bisect_left(tl, lo):bisect.bisect_right(tl, hi)])
        for t in sorted(cands, reverse=down):
            v, src = self.at(t, rows_only, reviewed)
            if v is not None and not (src == 'fixed' and t < x < self.m.func_end(self.m.old, t)):
                return t, v, src
        return None, None, None


class Methods:
    """The F2 propose methods on one pair of AP images. Nothing here reads a TSV or a proposal: a method returns its own
    answer (or none), and the caller compares it with the proposal. Per-run caches hold what does not depend on
    accepted rows (bounded ends, tokens, searches, fixed functions, grown windows, body hits)."""
    FUNC_CAP, BODY_MIN, FIXED_MIN, BODY_MAX_HITS = 0x200, 12, 24, 64
    SPAN, STEP, BLOCK, START_MAX, ENTRY_GAP = 0x4000, 0x400, 8, 0x40, 16
    GROW_FWD, GROW_BACK, GROW_BACK_TAIL = tuple(range(12, 65, 4)), tuple(range(4, 49, 4)), 16

    def __init__(self, old, new, targets, disabled=()):
        self.old, self.new, self.disabled = old, new, set(disabled)
        self.targets, self.target_list = targets, sorted(targets)
        self.ends, self.fixed_cache, self.grow_cache, self.found, self.spans, self.body_cache, self.ids = {}, {}, {}, {}, {}, {}, {}

    def off(self, name):
        return name in self.disabled

    # ---- primitives ----
    def func_end(self, image, x):
        """End of the bounded body from x: past the first unconditional return outside an IT block, capped at 0x200."""
        key = (image is self.new, x)
        if key not in self.ends:
            a, it, limit, end = x, 0, min(x + self.FUNC_CAP, FLASH + len(image)), x + self.FUNC_CAP
            while a + 2 <= limit:
                h1 = half(image, a)
                size = 4 if is32(h1) else 2
                h2 = half(image, a + 2) if size == 4 and a + 4 <= FLASH + len(image) else None
                if it == 0 and is_return(h1, h2):
                    end = a + size
                    break
                it = it - 1 if it else it_count(h1)
                a += size
            self.ends[key] = end
        return self.ends[key]

    def tokens(self, image, start, end, tier):
        """[(va, size, data, keep)] decoded from start over [start, end). T0 masks BL/B.W displacements; T1 also the offset
        field and U bit of LDR literal and ADR, and every pool word an LDR in the window reads (also the part the window
        cuts); T2 also immediates and local branch offsets. An instruction that would cross end is left out."""
        out, masked, a, limit = [], set(), start, min(end, FLASH + len(image))
        while a < limit:
            if a in masked:
                n = 0
                while n < 4 and a + n < limit and a + n in masked:
                    n += 1
                n -= n % 2
                if n:
                    out.append((a, n, image[a - FLASH:a - FLASH + n], b'\0' * n))
                    a += n
                    continue
            if a + 2 > limit:
                break
            h1 = half(image, a)
            size = 4 if is32(h1) else 2
            if a + size > limit:
                break
            h2 = half(image, a + 2) if size == 4 else None
            keep = b'\xff' * size
            if size == 4 and t4(h1, h2):
                keep = BL_KEEP
            elif tier != 'T0':
                k = t1_keep(h1, h2)
                if k is not None:
                    keep = k
                    got = load_literal(image, a) if is_literal_load(h1) else None
                    if got:
                        masked.update(v for v in range(got[2], got[2] + 4) if start <= v < limit)
                elif tier == 'T2':
                    keep = t2_keep(h1, h2) or keep
            out.append((a, size, image[a - FLASH:a - FLASH + size], keep))
            a += size
        if masked:   # an LDR.W with a negative offset can read a word decoded earlier in the window
            out = [(va, n, d, bytes(0 if va + i in masked else k for i, k in enumerate(kp))) if not is_pool((va, n, d, kp)) else (va, n, d, kp)
                   for va, n, d, kp in out]
        return out

    def key(self, tok):
        """A small int per distinct masked token (size, masked bytes, keep): equal ints mean equal under the token's tier."""
        k = (tok[1], bytes(x & y for x, y in zip(tok[2], tok[3])), tok[3])
        return self.ids.setdefault(k, len(self.ids))

    def search(self, image, toks, limit=None):
        """Every even VA of image where the tokens' bytes match under their keep mask (overlapping hits included); with a
        limit, stop once more than `limit` hits are found."""
        data, keep = b''.join(t[2] for t in toks), b''.join(t[3] for t in toks)
        ck = (image is self.new, data, keep, limit)
        if ck in self.found:
            return self.found[ck]
        n, hits = len(data), []
        want = int.from_bytes(bytes(x & y for x, y in zip(data, keep)), 'little')
        mask = int.from_bytes(keep, 'little')
        runs = [(m.start(), m.end()) for m in re.finditer(b'\xff+', keep)]
        best = max(runs, key=lambda r: r[1] - r[0]) if runs else (0, 0)
        if n and best[1] - best[0] >= 2:
            off = best[0]
            run = data[off:best[1]]
            at = image.find(run)
            while at >= 0:
                s = at - off
                if s >= 0 and s % 2 == 0 and s + n <= len(image) and int.from_bytes(image[s:s + n], 'little') & mask == want:
                    hits.append(s + FLASH)
                    if limit is not None and len(hits) > limit:
                        break
                at = image.find(run, at + 1)
        elif n:
            parts = []
            for d, k in zip(data, keep):
                if k == 0xff:
                    parts.append(re.escape(bytes((d,))))
                elif k == 0:
                    parts.append(b'.')
                else:
                    parts.append(b'[' + b''.join(re.escape(bytes((v,))) for v in range(256) if (v ^ d) & k == 0) + b']')
            for m in re.finditer(b'(?=' + b''.join(parts) + b')', image, re.S):
                if m.start() % 2 == 0 and m.start() + n <= len(image):
                    hits.append(m.start() + FLASH)
                    if limit is not None and len(hits) > limit:
                        break
        self.found[ck] = hits
        return hits

    def branch_at(self, image, va):
        """(even target, link) of a BL/B.W at va, else None."""
        if not FLASH <= va <= FLASH + len(image) - 4:
            return None
        h1, h2 = struct.unpack_from('<HH', image, va - FLASH)
        return (t4_target(va, h1, h2) & ~1, bool(h2 & 0x4000)) if t4(h1, h2) else None

    def fixed(self, t):
        """A fixed function: an old BL/B.W target t whose T1 bounded body (at least 24 bytes) occurs exactly once in the old
        image (at t) and once in the new. Returns the new address, else None. It is never a row and decides nothing alone."""
        if self.off('fixed') or t not in self.targets or not FLASH <= t < FLASH + len(self.old) - 2:
            return None
        if t not in self.fixed_cache:
            e, ans = self.func_end(self.old, t), None
            if e - t >= self.FIXED_MIN:
                toks = self.tokens(self.old, t, e, 'T1')
                if self.search(self.old, toks, 1) == [t]:
                    hn = self.search(self.new, toks, 1)
                    ans = hn[0] if len(hn) == 1 else None
            self.fixed_cache[t] = ans
        return self.fixed_cache[t]

    # ---- G: grown site windows for lit and field sites ----
    def grow(self, site):
        """(new site or None, proof). Windows at T1: forward [s, s+n) for n = 12..64, backward [s-m, s+16) for m = 4..48
        where decoding from s-m lands on s. Per direction, grow while the old window has more than one hit; the first
        window with one old hit (its own start) must have one new hit, and the next window in that direction must give
        one old hit and the same single new hit; anything else refuses that direction. Both directions paired must agree."""
        if site in self.grow_cache:
            return self.grow_cache[site]
        old, results, proof = self.old, {}, []
        for direction in ('fwd', 'back'):
            if direction == 'fwd':
                spans = [(site, site + n) for n in self.GROW_FWD]
            else:
                spans = []
                for m in self.GROW_BACK:
                    a = site - m
                    while a < site:
                        a += 4 if is32(half(old, a)) else 2
                    if a == site:
                        spans.append((site - m, site + self.GROW_BACK_TAIL))
            cand = None
            for a, b in spans:
                toks = self.tokens(old, a, b, 'T1')
                if not toks or toks[0][0] != a:
                    continue
                ho, hn = self.search(old, toks, 1), self.search(self.new, toks, 1)
                if cand is None:
                    if len(ho) > 1:
                        continue
                    if ho != [a] or len(hn) != 1:
                        proof.append('%s %d: old %d new %d, refused' % (direction, b - a, len(ho), len(hn)))
                        break
                    cand = (hn[0] + (site - a), b - a)
                    continue
                if ho == [a] and len(hn) == 1 and hn[0] + (site - a) == cand[0]:
                    results[direction] = cand[0]
                    proof.append('grown: %s %d, old 1 new 1 at %s, confirmed by %d' % (direction, cand[1], hex(cand[0]), b - a))
                else:
                    proof.append('%s %d: old 1 new 1 at %s, not confirmed by %d (old %d new %d%s), refused' % (
                        direction, cand[1], hex(cand[0]), b - a, len(ho), len(hn), ' at %s' % hex(hn[0] + (site - a)) if len(hn) == 1 else ''))
                break
            else:
                proof.append('%s: %s' % (direction, 'no window with one old hit' if cand is None else
                                         'old 1 new 1 at %s by %d, no next window to confirm it, refused' % (hex(cand[0]), cand[1])))
        news = set(results.values())
        if len(news) > 1:
            proof.append('directions name different new sites, refused')
        self.grow_cache[site] = (news.pop() if len(news) == 1 else None, proof)
        return self.grow_cache[site]

    # ---- span alignment shared by align and entry ----
    def span(self, a, b, a2, b2):
        """T2 tokens of [a, b) and [a', b'), their ids, and difflib's matching blocks (autojunk off)."""
        k = (a, b, a2, b2)
        if k not in self.spans:
            to, tn = self.tokens(self.old, a, b, 'T2'), self.tokens(self.new, a2, b2, 'T2')
            ko, kn = [self.key(t) for t in to], [self.key(t) for t in tn]
            blocks = [bl for bl in difflib.SequenceMatcher(None, ko, kn, autojunk=False).get_matching_blocks() if bl.size]
            pos_o, pos_n = {}, {}
            for i, v in enumerate(ko):
                pos_o.setdefault(v, []).append(i)
            for i, v in enumerate(kn):
                pos_n.setdefault(v, []).append(i)
            self.spans[k] = {'to': to, 'tn': tn, 'ko': ko, 'kn': kn, 'blocks': blocks, 'pos': (pos_o, pos_n),
                             'idx': {t[0]: i for i, t in enumerate(to)}}
        return self.spans[k]

    @staticmethod
    def occurrences(seq, pos, sub):
        return sum(1 for s in pos.get(sub[0], ()) if seq[s:s + len(sub)] == sub)

    def in_step(self, x, n, anchors):
        """align's anchors: the nearest a < x and b >= x + max(n, 2), each within 0x4000, with a' < b' and the spans within
        0x400 of each other. Returns (detail, span or None)."""
        a, a2, sa = anchors.nearest(x, x - self.SPAN, x - 2, True)
        b, b2, sb = anchors.nearest(x, x + max(n, 2), x + self.SPAN, False)
        det = {'anchors': '%s->%s (%s), %s->%s (%s)' % (hex(a) if a else None, hex(a2) if a2 else None, sa,
                                                      hex(b) if b else None, hex(b2) if b2 else None, sb)}
        if a is None or b is None:
            det['how'] = 'no anchor within 0x4000 on the %s side' % ('lower' if a is None else 'upper')
            return det, None
        if not a2 < b2 or abs((b2 - a2) - (b - a)) > self.STEP:
            det['how'] = 'anchors not in step (old span %s, new span %s)' % (hex(b - a), hex(b2 - a2))
            return det, None
        return det, self.span(a, b, a2, b2)

    # ---- the six counting methods ----
    def body(self, x, anchors):
        """Bounded whole-function match from x (at least 12 bytes), T1, then T2 only when T1 has no new hit."""
        if self.off('body'):
            return {'note': 'disabled'}
        if x not in self.body_cache:
            e = self.func_end(self.old, x)
            got = {'note': 'bounded body %d bytes, under %d' % (e - x, self.BODY_MIN)}
            if e - x >= self.BODY_MIN:
                for tier in ('T1', 'T2'):
                    toks = self.tokens(self.old, x, e, tier)
                    ho, hn = self.search(self.old, toks, self.BODY_MAX_HITS), self.search(self.new, toks, self.BODY_MAX_HITS)
                    got = {'tier': tier, 'length': e - x, 'toks': toks, 'ho': ho, 'hn': hn}
                    if hn:
                        break
            self.body_cache[x] = got
        got = self.body_cache[x]
        if 'toks' not in got:
            return dict(got)
        ho, hn, toks = got['ho'], got['hn'], got['toks']
        det = {'tier': got['tier'], 'length': got['length'], 'oldHits': '%d%s: %s' % (min(len(ho), self.BODY_MAX_HITS),
               '+' if len(ho) > self.BODY_MAX_HITS else '', ', '.join(hex(h) for h in ho[:8])),
               'newHits': '%d%s: %s' % (min(len(hn), self.BODY_MAX_HITS), '+' if len(hn) > self.BODY_MAX_HITS else '', ', '.join(hex(h) for h in hn[:8]))}
        if ho == [x] and len(hn) == 1:
            return dict(det, answer=hn[0], evidence='%s %d bytes, old 1 new 1' % (got['tier'], got['length']))
        if x not in ho or not hn or len(ho) > self.BODY_MAX_HITS or len(hn) > self.BODY_MAX_HITS:
            return dict(det, how='no single answer')
        edges = []
        for va, size, data, keep in toks:
            if keep == BL_KEEP:
                t = self.branch_at(self.old, va)[0]
                v, src = anchors.at(t)
                if t != x and v is not None:
                    edges.append((va - x, t, v, src))
        det['edges'] = ['+%d %s->%s (%s)' % (k, hex(t), hex(v), src) for k, t, v, src in edges]
        if not edges:
            return dict(det, how='edge filter: no BL/B.W of x goes to an anchor')
        survivors = [c for c in hn if all((self.branch_at(self.new, c + k) or (None,))[0] == v for k, t, v, src in edges)]
        twins = [y for y in ho if y != x]
        ruled = 0
        for y in twins:
            for k, t, v, src in edges:
                b = self.branch_at(self.old, y + k)
                if b and b[0] != t:
                    vy = anchors.at(b[0])[0]
                    if vy is not None and vy != v:
                        ruled += 1
                        break
        det.update(survivors=[hex(c) for c in survivors], twinsRuledOut='%d of %d' % (ruled, len(twins)))
        if len(survivors) == 1 and ruled == len(twins):
            return dict(det, answer=survivors[0], evidence='%s %d bytes, old %d new %d, edges %s, survivors 1, twins ruled out %d of %d' % (
                got['tier'], got['length'], len(ho), len(hn), '; '.join(det['edges']), ruled, len(twins)))
        return dict(det, how='edge filter: no single survivor with every twin ruled out')

    def align(self, x, n, anchors):
        """Anchored T2 token alignment: x starts a token inside an equal block of at least 8 tokens that occurs once in
        each span (an ABI range must lie wholly inside it)."""
        if self.off('align'):
            return {'note': 'disabled'}
        det, sp = self.in_step(x, n, anchors)
        if sp is None:
            return det
        if x not in sp['idx']:
            return dict(det, how='x is not an instruction start in the old span')
        i, to = sp['idx'][x], sp['to']
        last = max(k for k in range(i, len(to)) if to[k][0] <= x + max(n, 1) - 1)
        for bl in sp['blocks']:
            if bl.a <= i and last < bl.a + bl.size:
                sub = sp['ko'][bl.a:bl.a + bl.size]
                co, cn = self.occurrences(sp['ko'], sp['pos'][0], sub), self.occurrences(sp['kn'], sp['pos'][1], sub)
                det.update(block=bl.size, before=i - bl.a, after=bl.a + bl.size - 1 - last, occurrences='%d old, %d new' % (co, cn))
                if bl.size >= self.BLOCK and co == 1 and cn == 1:
                    return dict(det, answer=sp['tn'][bl.b + i - bl.a][0], evidence='equal block of %d tokens (%d before x, %d after), once in each span; anchors %s' % (
                        bl.size, i - bl.a, det['after'], det['anchors']))
                return dict(det, how='block shorter than %d tokens or not unique' % self.BLOCK)
        if any(bl.a <= i < bl.a + bl.size for bl in sp['blocks']):
            return dict(det, how='the range runs past its equal block')
        return dict(det, how='x is in a changed run')

    def start(self, x, anchors):
        """An address inside a function: s, the greatest accepted row with 2 <= x - s <= 0x40 and x before the end of s's
        bounded body; the T2 tokens of [s, x) equal those at s', ending on an instruction boundary in both. s may be a
        row accepted through REVIEWED_SITES; then `reviewedAnchor` is set, `row` is still the plain row label, and the
        evidence string names the row followed by Anchors.REVIEWED_ANCHOR. Reviewed and other rows are one candidate
        set: the nearest row below x is s, so a reviewed row nearer to x is taken even when a row further down that is
        not reviewed would have given a locating start (start can then only lose its locating role, never gain one)."""
        if self.off('start'):
            return {'note': 'disabled'}
        s, s2, src = anchors.nearest(x, x - self.START_MAX, x - 2, True, rows_only=True, reviewed=True)
        if s is None:
            return {'how': 'no accepted row in [x-0x40, x-2]'}
        reviewed = src.endswith(Anchors.REVIEWED_ANCHOR)
        det = {'s': hex(s), "s'": hex(s2), 'row': src[:-len(Anchors.REVIEWED_ANCHOR)] if reviewed else src, 'prefix': x - s}
        if reviewed:
            det['reviewedAnchor'] = True
        if self.func_end(self.old, s) <= x:
            return dict(det, how='x is past the bounded body of s')
        to, tn = self.tokens(self.old, s, x, 'T2'), self.tokens(self.new, s2, s2 + (x - s), 'T2')
        if not to or to[-1][0] + to[-1][1] != x:
            return dict(det, how='x is not an instruction boundary from s')
        if len(to) != len(tn) or [self.key(t) for t in to] != [self.key(t) for t in tn]:
            return dict(det, how='the T2 prefix differs')
        return dict(det, answer=s2 + (x - s), evidence='s %s %s->%s, %d-byte T2 prefix equal' % (src, hex(s), hex(s2), x - s))

    def edge2(self, x, p, n, anchors):
        """T2 edge walk from (x, p) over max(64, n) bytes in step, stopping at the first T2 difference or size change:
        BL/B.W pairs to anchors and (edge-lit) LDR-literal pairs of accepted value rows' old words are good or bad."""
        if self.off('edge2'):
            return {'state': 'none', 'note': 'disabled'}
        length = max(EDGE_BYTES, n)
        to, tn = self.tokens(self.old, x, x + length, 'T2'), self.tokens(self.new, p, p + length, 'T2')
        good, bad, walked, blame = [], [], 0, []
        for o, q in zip(to, tn):
            if o[1] != q[1] or self.key(o) != self.key(q):
                break
            if o[3] == BL_KEEP:
                t, tq = self.branch_at(self.old, o[0])[0], self.branch_at(self.new, q[0])[0]
                v, src = anchors.at(t)
                if t != x and v is not None:
                    (good if v == tq else bad).append('%s->%s (%s)' % (hex(t), hex(tq), src))
                    if v != tq and src != 'fixed':
                        blame.append(('code', t))
            elif not self.off('edge-lit') and not is_pool(o) and is_literal_load(struct.unpack_from('<H', o[2])[0]):
                lo, ln = load_literal(self.old, o[0]), load_literal(self.new, q[0])
                if lo and ln and lo[:2] == ln[:2] and lo[3] in anchors.values:
                    v, src = anchors.values[lo[3]]
                    (good if v == ln[3] else bad).append('literal %s->%s (%s)' % (hex(lo[3]), hex(ln[3]), src))
                    if v != ln[3]:
                        blame.append(('value', lo[3]))
            walked += o[1]
        return {'state': 'disagree' if bad else 'agree' if good else 'none', 'walked': '%d of %d bytes' % (walked, length),
                'good': good, 'bad': bad, 'blame': blame,
                **({'evidence': 'walked %d bytes; good %s' % (walked, ', '.join(good))} if good and not bad else {})}

    def entry(self, x, n, anchors):
        """A function head that stock rewrote: x (an old BL/B.W target or aligned code pointer) starts a changed run in
        align's alignment; the equal block ending at x is unique and ends in an unconditional return; the next equal
        block of at least 8 tokens is unique and starts within 16 tokens on each side. Answer: the first new token after
        the first block."""
        if self.off('entry'):
            return {'note': 'disabled'}
        ck = ('pointer', x)
        if ck not in self.found:
            self.found[ck] = any(i % 4 == 0 for i in find_all(self.old, struct.pack('<I', x | 1)))
        if x not in self.targets and not self.found[ck]:
            return {'how': 'x is neither an old BL/B.W target nor an aligned code pointer'}
        det, sp = self.in_step(x, n, anchors)
        if sp is None:
            return det
        if x not in sp['idx']:
            return dict(det, how='x is not an instruction start in the old span')
        i, blocks, to, ko, kn = sp['idx'][x], sp['blocks'], sp['to'], sp['ko'], sp['kn']
        if any(bl.a <= i < bl.a + bl.size for bl in blocks):
            return dict(det, how='x is inside an equal block')
        prev = [bl for bl in blocks if bl.a + bl.size == i]
        nxt = [bl for bl in blocks if bl.a > i and bl.size >= self.BLOCK]
        if not prev or not nxt:
            return dict(det, how='no equal block ends at x' if not prev else 'no equal block of %d tokens after x' % self.BLOCK)
        b1, b2 = prev[0], nxt[0]
        j = b1.b + b1.size
        s1, s2 = ko[b1.a:b1.a + b1.size], ko[b2.a:b2.a + b2.size]
        occ1 = (self.occurrences(ko, sp['pos'][0], s1), self.occurrences(kn, sp['pos'][1], s1))
        occ2 = (self.occurrences(ko, sp['pos'][0], s2), self.occurrences(kn, sp['pos'][1], s2))
        # the first block ends in an unconditional return outside an IT block, then only pool tokens or one 0000 halfword
        k, zeros = b1.a + b1.size - 1, 0
        while k >= b1.a and (is_pool(to[k]) or to[k][2] == b'\0\0'):
            zeros += to[k][2] == b'\0\0' and not is_pool(to[k])
            k -= 1
        tail = False
        if k >= b1.a and zeros <= 1:
            h1 = struct.unpack_from('<H', to[k][2])[0]
            h2 = struct.unpack_from('<H', to[k][2], 2)[0] if to[k][1] == 4 else None
            inside_it = any(to[g][1] == 2 and k - g <= it_count(struct.unpack_from('<H', to[g][2])[0]) for g in range(max(0, k - 4), k))
            tail = is_return(h1, h2) and not inside_it
        det.update(tailBlock='%d tokens, %d old, %d new, ends in a return: %s' % (b1.size, occ1[0], occ1[1], tail),
                   nextBlock='%d tokens, %d old, %d new' % (b2.size, occ2[0], occ2[1]), gaps='%d old, %d new' % (b2.a - i, b2.b - j))
        if (b1.size >= self.BLOCK and occ1 == (1, 1) and tail and occ2 == (1, 1) and b2.a - i <= self.ENTRY_GAP
                and 0 <= b2.b - j <= self.ENTRY_GAP and j < len(sp['tn'])):
            return dict(det, answer=sp['tn'][j][0], evidence='tail block %d tokens (once in each span) ends in a return; next block %d tokens (once in each span); gaps %d old, %d new' % (
                b1.size, b2.size, b2.a - i, b2.b - j))
        return dict(det, how='entry conditions not met')

    def veneer(self, x, anchors):
        """x is 4-aligned and holds ldr.w pc,[pc,#0] then a literal w; w' comes from an anchor (or w' = w for identical
        copy-region code); exactly one veneer holds w in the old image (at x) and one holds w' in the new."""
        if self.off('veneer'):
            return {'note': 'disabled'}
        at = x - FLASH
        if x % 4 or not 0 <= at <= len(self.old) - 8 or self.old[at:at + 4] not in (b'\xdf\xf8\x00\xf0', b'\x5f\xf8\x00\xf0'):
            return {'how': 'not a veneer'}
        w = struct.unpack_from('<I', self.old, at + 4)[0]
        if (w & ~1) in COPY_REGION:
            a, b = copy_bytes(self.old, w), copy_bytes(self.new, w)
            w2, src = (w, 'copy region, %d bytes identical' % COPY_BYTES) if a is not None and a == b else (None, 'copy region, not identical')
        else:
            v, src = anchors.at(w & ~1)
            w2 = None if v is None else v | (w & 1)
        det = {'w': hex(w), "w'": hex(w2) if w2 is not None else None, 'source': src}
        if w2 is None:
            return dict(det, how='the veneer literal is not an anchor')
        def found(image, word):
            ck = ('veneer', image is self.new, word)
            if ck not in self.found:
                self.found[ck] = sorted(i + FLASH for pre in (b'\xdf\xf8\x00\xf0', b'\x5f\xf8\x00\xf0')
                                        for i in find_all(image, pre + struct.pack('<I', word)) if i % 4 == 0)
            return self.found[ck]
        ho, hn = found(self.old, w), found(self.new, w2)
        det['hits'] = '%d old, %d new' % (len(ho), len(hn))
        if ho == [x] and len(hn) == 1:
            return dict(det, answer=hn[0], evidence='w %s -> %s (%s), one veneer in each image' % (hex(w), hex(w2), src))
        return dict(det, how='not exactly one veneer in each image')


def stock_record(base, raw, files, build, rebase, pin=None):
    """bases[base] of a format-2 table: pins, cores, module VA and the .data copy, read from the stock ZIP itself."""
    kind, rel = build.STOCK_SHAPES[base]['stockZIPPath']
    ap = files['nuttx_ap.bin']
    src, end, dst, delta = rebase.data_copy(ap)
    out = {'stockZIPFile': rel if kind == 'repo' else '$TURBO_INPUTS/' + rel, 'stockZIPKind': build.STOCK_SHAPES[base]['container'],
           'stockZIP': sha(raw), 'stockZIPBytes': len(raw), 'stockAP': sha(ap), 'stockAPBytes': len(ap),
           'stockMembers': {n: sha(b) for n, b in sorted(files.items()) if n != 'OtaFileInfo.json'}}
    if out['stockZIPKind'] == 'canonical-members':
        out['stockManifestSHA256'] = sha(files['OtaFileInfo.json'])
    out.update(cores={n: version_block(files[n]) for n in ('nuttx_ap.bin', 'nuttx_apc1.bin', 'nuttx_bth.bin')},
               moduleVA=hex(FLASH + len(ap) - 8), dataFileDelta=hex(delta),
               dataCopy={'descriptor': hex(0x674), 'src': hex(src), 'end': hex(end), 'dst': hex(dst)})
    if pin is not None:
        assert (out['stockZIP'], out['stockZIPBytes']) == (pin['container']['sha256'], pin['container']['bytes']), base + ': container pin'
        assert out['stockMembers'] == {n: h for n, h in pin['members'].items() if n != 'OtaFileInfo.json'}, base + ': member pins'
        assert out.get('stockManifestSHA256') == pin['members']['OtaFileInfo.json'], base + ': manifest pin'
    return out


def comment_corrections(fixes, keyed, acc, new):
    """REVIEWED_UNIVERSE_CHANGES correctComment, each checked against the accepted rows and the new image. Returns
    {row name: {'new', 'reason'}}; any failed check stops the run before a table is written."""
    out, olds = {}, {it['old'] for it in keyed.values() if it['family'] == 'value'}
    for name, fix in fixes.items():
        it, x = keyed.get(('value', name)), H(fix['new'])
        why = []
        if it is None or it['type'] != 'code' or not name.endswith('_comment'):
            why.append('not a code-comment value row of the old table')
        elif acc.get(('value', name)) != H(fix['derived']):
            why.append('derived %s, the entry says %s' % (hex(acc[('value', name)]) if ('value', name) in acc else 'nothing', fix['derived']))
        else:
            n, digest = fix['bytes']
            at = (x & ~1) - FLASH
            if x & 1 != it['old'] & 1:
                why.append('the Thumb bit differs from the old value')
            if not 4 <= at <= len(new) - n or sha(new[at:at + n]) != digest:
                why.append('the %d bytes at %s are not the pinned ones' % (n, fix['new']))
            else:
                h1, h2 = struct.unpack_from('<HH', new, at)
                if not (h1 & 0xff00 == 0xb500 or (h1 == 0xe92d and h2 & 0x4000)):
                    why.append('the code at %s is not a push {..., lr}' % fix['new'])
                pool = (x & ~1) - 4
                if pool & 3 or not any(load_literal(new, s) and load_literal(new, s)[2] == pool for s in range(max(FLASH, pool - 4096), pool, 2)):
                    why.append('no pc-relative load reads the word right before %s' % fix['new'])
            if 'linkld' in fix and (acc.get(('linkld', fix['linkld'])) or 0) & ~1 != x & ~1:
                why.append('not the accepted link.ld %s address' % fix['linkld'])
            if x in olds:
                why.append('equals an old value: rewriting would be ambiguous')
        if why:
            raise SystemExit('rebase table NOT written: correctComment %s: %s' % (name, '; '.join(why)))
        out[name] = {'new': fix['new'], 'reason': fix['reason']}
    return out


def propose(args):
    """--propose: verify each TSV proposal by this tool's own methods (docstring) and write --out and --report."""
    rebase, build = rebase_apply(), load_module(FW/'build.py', 'rebase_derive_build')
    stock_zip = load_module(FW/'tools'/'stock_zip.py', 'rebase_derive_stock_zip')
    frm, to, tree = args.frm, args.to, args.old_tree.resolve()
    try:
        prev = next((t for t in rebase.TABLES if t[1] == frm), None)
        entry = next((t for t in rebase.TABLES if (t[0], t[1]) == (frm, to)), None)
        assert prev and entry and entry[3] == 'turboio-rebase-2', 'TABLES has no format-2 table %s to %s after a table ending at %s' % (frm, to, frm)
        spec = json.loads((tree/'build-inputs.json').read_text())
        assert spec.get('stockBase') == frm, 'the old tree is on stock %r, not --from %s' % (spec.get('stockBase'), frm)
        old_table = rebase.load_table(tree/'baseline'/prev[2])
        col = rebase.column(old_table, frm)
        files_old, _ = build.safe_zip(args.stock_old, spec['stockZIP'], frm)
        build.check_stock_members(files_old, spec, frm)
        build.core_identity(files_old, frm)
        pin = stock_zip.pinned(to)
        files_new, _ = build.safe_zip(args.stock_new, pin['container']['sha256'], to)
        build.check_stock_members(files_new, {'stockMembers': {n: h for n, h in pin['members'].items() if n != 'OtaFileInfo.json'},
                                              'stockManifestSHA256': pin['members']['OtaFileInfo.json']}, to)
        build.core_identity(files_new, to)
        old, new = files_old['nuttx_ap.bin'], files_new['nuttx_ap.bin']
        bases = {frm: stock_record(frm, args.stock_old.read_bytes(), files_old, build, rebase),
                 to: stock_record(to, args.stock_new.read_bytes(), files_new, build, rebase, pin)}
        known = old_table['bases'][frm]
        assert all(bases[frm][k] == known[k] for k in known), '%s: the stock ZIP is not the old table\'s (%s)' % (
            frm, ', '.join(k for k in known if bases[frm][k] != known[k]))
        assert bases[frm]['stockAP'] == spec['stockAP'] and bases[frm]['moduleVA'] == spec['moduleVA'] == old_table['moduleVA'][col], 'old AP and module VA'
        left = rebase.problems(tree, old_table, frm)
        assert not left, 'the old tree is not wholly on %s: %s' % (frm, '; '.join(left[:5]))
        for t in old_table['notStock']:
            word = struct.pack('<I', H(t))
            for image in (old, new):
                src, end, _, _ = rebase.data_copy(image)
                assert t in ('0x10190000', '0x18000000') or not [i for i in find_all(image, word) if i % 4 == 0 and not src - FLASH <= i < end - FLASH], \
                    t + ': listed as not stock but is an aligned word outside the data copy of a stock image'
        # ---- universe: the old tree's link.ld symbols and edits, the old table's values and ABI ranges ----
        items, keyed = [], {}

        def item(key, **it):
            assert key not in keyed, 'duplicate item %r' % (key,)
            it['key'] = key
            items.append(it)
            keyed[key] = it

        linkld = {r['symbol']: r for r in old_table['linkld']}
        for sym, v in tree_values(tree).items():
            assert H(linkld[sym][col]) == v, sym
            item(('linkld', sym), family='linkld', old=v, text=linkld[sym][col],   # a RAM symbol (tio_imu_family) is checked as RAM
                 type='copy' if (v & ~1) in COPY_REGION else 'ram' if DATA_RUNTIME <= v < 0x1a000000 else 'code')
        for e in spec['edits']:
            oa, before = H(e['address']), bytes.fromhex(e['before'])
            assert old[oa - FLASH: oa - FLASH + len(before)] == before and H(e['offset']) == oa - FLASH, e['role'] + ': old before'
            assert e['pad'] == ((len(before) - 4) // 2 if e['kind'] in ('bw', 'bl') else 0), e['role'] + ': old pad'
            item(('edit', e['role']), family='edit', type='edit', old=oa, text=e['address'], edit=e)
        for v in old_table['values']:
            sites = scan_sites(tree, v[col])
            assert sites == rebase.sites(v), v['name'] + ': sites in the old tree are not the old table\'s'
            item(('value', v['name']), family='value', type=v['kind'], old=H(v[col]), text=v[col], value=v, sites=sites)
        for r in old_table['stockAbiRanges']:
            oa = H(r[col])
            assert sha(old[oa - FLASH: oa - FLASH + r['bytes']]) == r[col + 'SHA256'], r[col] + ': old range hash'
            item(('abi-range', oa), family='abi-range', type='abi', old=oa, text=r[col], bytes=r['bytes'], range=r)
        # ---- reviewed additions (REVIEWED_UNIVERSE_CHANGES addLinkld, addEdits): new-tree rows with an old address ----
        added = REVIEWED_UNIVERSE_CHANGES.get(to, {}).get('addLinkld', {})
        for sym, e in added.items():
            assert sym not in linkld, sym + ': addLinkld names a symbol the old tree already defines'
            v, nv = H(e['old']), H(e['new'])
            if DATA_RUNTIME <= v < 0x1a000000 or DATA_RUNTIME <= nv < 0x1a000000:
                # a RAM symbol: both addresses word-aligned RAM; checked like any RAM row (lit, two paired votes)
                assert DATA_RUNTIME <= v < 0x1a000000 and DATA_RUNTIME <= nv < 0x1a000000 and not v % 4 and not nv % 4, \
                    sym + ': addLinkld RAM symbol needs word-aligned RAM addresses in both columns'
                item(('linkld', sym), family='linkld', old=v, text=e['old'], type='ram', added=e)
                continue
            assert v & 1 and nv & 1, sym + ': addLinkld needs Thumb code addresses'
            assert FLASH <= (v & ~1) and (v & ~1) + 2 <= FLASH + len(old), sym + ': addLinkld old address is outside the old AP image'
            assert FLASH <= (nv & ~1) and (nv & ~1) + 2 <= FLASH + len(new), sym + ': addLinkld new address is outside the new AP image'
            item(('linkld', sym), family='linkld', old=v, text=e['old'], type='code', added=e)
        old_roles = {e['role'] for e in spec['edits']}
        for role, e in REVIEWED_UNIVERSE_CHANGES.get(to, {}).get('addEdits', {}).items():
            assert role not in old_roles, role + ': addEdits names an edit the old tree already has'
            assert role.startswith('Entry trampoline ') and e['kind'] == 'bw', role + ': addEdits takes entry trampolines (bw) only'
            assert e.get('entry', 'call') in ('call', 'pointer'), role + ': addEdits entry proof must be call or pointer'
            assert e.get('arg', 1) in (0, 1) and ('arg' not in e or e.get('entry') == 'pointer'), role + ': arg is r0 or r1, pointer entries only'
            oa, na, before = H(e['old']), H(e['new']), bytes.fromhex(e['before'])
            assert not oa & 1 and not na & 1 and len(before) == 4, role + ': addEdits needs even addresses and a 4-byte before'
            assert old[oa - FLASH: oa - FLASH + 4] == before, role + ': addEdits before is not the old image\'s bytes'
            assert not any(br for i, size, br, hw in instructions(old, oa, 4)) and \
                sum(size for i, size, br, hw in instructions(old, oa, 4) if i + size <= 4) == 4, \
                role + ': addEdits before must be whole instructions with no BL/B.W'
            edit = {'role': role, 'offset': hex(oa - FLASH), 'address': e['old'], 'before': e['before'], 'kind': 'bw',
                    'target': e['target'], 'pad': 0}
            item(('edit', role), family='edit', type='edit', old=oa, text=e['old'], edit=edit, added=dict(e, source='addEdits'))
            name = 'resume_' + role.removeprefix('Entry trampoline ')
            assert name not in linkld and name not in added, name + ': already a link.ld symbol'
            item(('linkld', name), family='linkld', old=oa + 5, text=hex(oa + 5), type='code',
                 added={'old': hex(oa + 5), 'new': hex(na + 5), 'resumeOf': role})
        # ---- the TSV: exactly one row per item ----
        with open(args.propose, newline='') as f:
            reader = csv.DictReader(f, delimiter='\t')
            tsv = list(reader)
        assert set(TSV_COLUMNS) <= set(reader.fieldnames or ()), 'TSV columns: need ' + ', '.join(TSV_COLUMNS)
        rows, errors = [], []
        for n, r in enumerate(tsv):
            line, kind, name = n + 2, r['kind'], r['name']
            try:
                at = int(r['addr_1012'], 16)
            except (TypeError, ValueError):
                errors.append('line %d: addr_1012 %r' % (line, r['addr_1012']))
                continue
            family = 'value' if kind in ('value-code', 'value-data', 'value-ram') else kind
            it = keyed.get((family, at if family == 'abi-range' else name))
            if it is None or family not in ('linkld', 'edit', 'value', 'abi-range'):
                errors.append('line %d: %s %r is not an item of the old tree' % (line, kind, name))
            elif any(x['it'] is it for x in rows):
                errors.append('line %d: a second row for %s %r' % (line, kind, name))
            elif family == 'value' and kind != 'value-' + it['type']:
                errors.append('line %d: %s %r is a %s value in the old table' % (line, kind, name, it['type']))
            elif at != it['old']:
                errors.append('line %d: %s %r addr_1012 %s is not the tree value %s' % (line, kind, name, r['addr_1012'], it['text']))
            else:
                text = (r['new_address_1611'] or '').strip()
                rows.append({'it': it, 'kind': kind, 'name': name, 'line': line, 'text': text,
                             'proposal': int(text, 16) if re.fullmatch(r'0x[0-9a-fA-F]{1,8}', text) else None,
                             'info': {'verdict': r['final_verdict'], 'source': r['source'], 'row': line}})
        errors += ['no TSV row for %s %r' % (k[0], k[1] if k[0] != 'abi-range' else hex(k[1])) for k in keyed
                   if not keyed[k].get('added') and not any(x['it']['key'] == k for x in rows)]
        errors += ['line %d: %s %r is a reviewed addition and takes no TSV row' % (x['line'], x['kind'], x['name']) for x in rows if x['it'].get('added')]
        for k, it in keyed.items():
            if it.get('added'):
                source = 'reviewed:addEdits' if k[0] == 'edit' else 'reviewed:addEdits resume' if 'resumeOf' in it['added'] else 'reviewed:addLinkld'
                rows.append({'it': it, 'kind': k[0], 'name': k[1], 'line': 0, 'text': it['added']['new'], 'proposal': H(it['added']['new']),
                             'info': {'verdict': 'ADDED', 'source': source, 'row': 0}})
        assert not errors and len(rows) == len(items), 'the TSV does not cover the old tree one row per item:\n  ' + '\n  '.join(errors)
    except AssertionError as error:
        raise SystemExit('rebase table NOT written (%s to %s): %s' % (frm, to, error))
    # ---- methods that do not depend on accepted rows: computed once per row ----
    branches, loads, paired = branch_index(old), literal_index(old), {}
    data_new = rebase.data_copy(new)
    disabled = sorted(set(args.disable_method or ()))
    methods = Methods(old, new, branches, disabled)

    def pair(site):
        """The one even VA where the masked 16-byte window at an old site occurs in the new image, else None."""
        if site not in paired:
            hits = masked_hits(new, old, site, SITE_BYTES) if site - FLASH + SITE_BYTES + 2 <= len(old) else []
            paired[site] = hits[0] if len(hits) == 1 else None
        return paired[site]

    def votes(sites, vote, grown=False):
        """Votes of the paired sites. grown (lit and field only): a site that pair() leaves unpaired is tried with G."""
        got, tried, by_g, proofs = [], 0, 0, []
        for site in sites:
            if len(got) == MAX_VOTES or tried == MAX_TRIES:
                break
            tried += 1
            p, g = pair(site), False
            if p is None and grown and not methods.off('grow'):
                p, proof = methods.grow(site)
                g = p is not None
                proofs.append('site %s: %s' % (hex(site), '; '.join(proof)))
            v = None if p is None else vote(site, p)
            if v is not None:
                got.append(v)
                by_g += g
        return {'sites': len(sites), 'tried': tried, 'votes': got, 'byG': by_g, **({'grown': proofs} if proofs else {})}

    def call_vote(site, p):
        o2, (h1, h2) = struct.unpack_from('<HH', old, site - FLASH)[1], struct.unpack_from('<HH', new, p - FLASH)
        return t4_target(p, h1, h2) if t4(h1, h2) and (h2 & 0x4000) == (o2 & 0x4000) else None

    def lit_vote(site, p):
        a, b = load_literal(old, site), load_literal(new, p)
        return b[3] if a and b and a[:2] == b[:2] else None

    def setter_check(sites, arg):
        """addEdits entry 'pointer': each old load site of the pointer, paired (16-byte window, else G), must be an LDR into r<arg>
        followed directly by a BL in both images whose old target's SETTER_BYTES masked pattern has exactly one hit in
        each image, the new hit being the new BL's target. Returns {'ok', 'sites': [...]}."""
        out, ok = [], bool(sites)
        for site in sites:
            q = pair(site)
            if q is None and not methods.off('grow'):
                q = methods.grow(site)[0]
            a, b = load_literal(old, site), (load_literal(new, q) if q is not None else None)
            why = None
            if q is None or not a or not b:
                why = 'load site does not pair'
            elif a[1] != arg or b[1] != arg:
                why = 'the load is not into r%d' % arg
            else:
                bo, bn = site + a[0], q + b[0]
                h1, h2 = struct.unpack_from('<HH', old, bo - FLASH)
                g1, g2 = struct.unpack_from('<HH', new, bn - FLASH)
                if not (t4(h1, h2) and h2 & 0x4000 and t4(g1, g2) and g2 & 0x4000):
                    why = 'no BL right after the load'
                else:
                    to_old, to_new = t4_target(bo, h1, h2), t4_target(bn, g1, g2)
                    if masked_hits(old, old, to_old, SETTER_BYTES) != [to_old] or masked_hits(new, old, to_old, SETTER_BYTES) != [to_new]:
                        why = 'the BL targets %s and %s are not one setter by a unique %d-byte pattern' % (hex(to_old), hex(to_new), SETTER_BYTES)
                    else:
                        out.append('%s->%s ldr r%d then bl %s->%s' % (hex(site), hex(q), arg, hex(to_old), hex(to_new)))
                        continue
            ok = False
            out.append('%s: %s' % (hex(site), why))
        return {'ok': ok, 'sites': out}

    field_cache = {}

    def static(row):
        it, p, s = row['it'], row['proposal'], {}
        oa, typ = it['old'], it['type']
        if typ in ('code', 'edit', 'abi'):
            n = it['bytes'] if typ == 'abi' else SIG_BYTES
            # The old pattern must also be unique in the old image: an identical twin there could be the one hit in the
            # new image, and sig would then name the twin's new address (stricter than spec 2h, which checks the new image only).
            s['sig'] = {'hits': masked_hits(new, old, oa & ~1, n), 'oldHits': masked_hits(old, old, oa & ~1, n)}
        if typ in ('code', 'edit', 'abi', 'copy'):
            # A reviewed addition (addLinkld code, addEdits) has no old-tree row behind it, so its callers are also tried
            # with G: its old address must be shown to be a call target with a paired caller (see evaluate)
            grown_call = bool(it.get('added')) and 'resumeOf' not in it['added']
            s['call'] = votes(branches.get(oa & ~1, []), call_vote, grown=grown_call)
        # An ABI range is a code address stored as a pointer with its Thumb bit, so lit searches the range address | 1;
        # so does an added edit whose entry proof is a stored pointer (addEdits entry 'pointer').
        pointer = (it.get('added') or {}).get('entry') == 'pointer'
        word = oa | 1 if typ == 'abi' or pointer else oa
        lit_sites = sorted({site for at in find_all(old, struct.pack('<I', word)) for site in loads.get(FLASH + at, [])})
        s['lit'] = votes(lit_sites, lit_vote, grown=True)
        if pointer:
            s['setter'] = setter_check(lit_sites, it['added'].get('arg', 1))
        if typ == 'copy':
            a, b = copy_bytes(old, oa), copy_bytes(new, oa)
            s['copy'] = {'answer': oa if a is not None and a == b else None,
                         'note': '%d bytes at %s %s in both images' % (COPY_BYTES, hex(oa & ~1), 'identical' if a is not None and a == b else 'not identical')}
        if typ == 'data':
            so = old[rebase.data_offset(old, oa):].split(b'\0', 1)[0]
            change = REVIEWED_STRING_CHANGES.get((to, it['key'][1]))
            found = {}
            for mode, text in (('identical', so),) + ((('reviewed', so.replace(change[0].encode(), change[1].encode())),)
                                                      if change and so.count(change[0].encode()) == 1 else ()):
                hits = find_all(new, text + b'\0', data_new[0] - FLASH, data_new[1] - FLASH)
                found[mode] = (hits, text)
            unique = [(mode, hits[0], text) for mode, (hits, text) in found.items() if len(hits) == 1]
            s['str'] = {'answer': unique[0][1] + data_new[3] if len(unique) == 1 else None, 'mode': unique[0][0] if len(unique) == 1 else None,
                        'old': so, 'new': unique[0][2] if len(unique) == 1 else None,
                        'note': '; '.join('the %s string %r occurs %d times in the new data copy' % ('old' if mode == 'identical' else 'reviewed change of the old',
                                          text.decode('latin-1'), len(hits)) for mode, (hits, text) in found.items())
                                + ('' if change else '; no reviewed string change listed')}
        if typ == 'ram' and it['key'][1] in FIELD_BASES:
            base = keyed[('value', FIELD_BASES[it['key'][1]])]
            off = oa - base['old']
            assert 0 < off < 0x1000, it['key'][1] + ': not a field of ' + base['key'][1]
            if base['old'] not in field_cache:
                field_cache[base['old']] = field_sites(old, base['old'], {x['old'] - base['old'] for x in items if x['key'][1] in FIELD_BASES})
            sites = [a for a, k, o in field_cache[base['old']] if o == off]
            s['field'] = dict(votes(sites, lambda site, q: field_base(new, q), grown=True), base=base['key'], offset=off)
        if typ in ('code', 'edit', 'abi') and p is not None and FLASH <= (p & ~1) and (p & ~1) - FLASH + max(EDGE_BYTES, it.get('bytes', 0)) + 2 <= len(new):
            s['window'] = masked_prefix(old, oa & ~1, new, p & ~1, WINDOW_BYTES)
            s['prologue'] = old[(oa & ~1) - FLASH:(oa & ~1) - FLASH + 4] == new[(p & ~1) - FLASH:(p & ~1) - FLASH + 4]
            s['new-sig'] = len(masked_hits(new, new, p & ~1, SIG_BYTES))
        row['static'] = it['static'] = s

    try:
        for row in rows:
            static(row)
    except AssertionError as error:
        raise SystemExit('rebase table NOT written (%s to %s): %s' % (frm, to, error))

    # ---- evaluation against a set of accepted rows ----
    def code_map(acc):
        """{even old VA: {even new VA: [keys]}} of the accepted code rows (link.ld, code values, edits, ABI ranges)."""
        out = {}
        for k, v in acc.items():
            if keyed[k]['type'] in ('code', 'copy', 'edit', 'abi'):
                out.setdefault(keyed[k]['old'] & ~1, {}).setdefault(v & ~1, []).append(k)
        return out

    label = lambda k: '%s %s' % (k[0], k[1] if isinstance(k[1], str) else hex(k[1]))
    listed_keys = set() if methods.off('reviewed-site') else {
        r['it']['key'] for r in rows if (to, r['kind'], r['name']) in REVIEWED_SITES}

    def context(acc):
        """What one pass evaluates against. Rows with a REVIEWED_SITES entry never vouch for another row: they are left
        out of the accepted set the methods read (edge, field, before and the anchors). The one exception is start,
        which may anchor on such a row (Anchors.reviewed); it then does not locate."""
        vouch = {k: v for k, v in acc.items() if k not in listed_keys}
        cm, code_rows, values, value_keys, anchor_keys = code_map(vouch), {}, {}, {}, {}
        for even, news in cm.items():
            ks = [k for ks in news.values() for k in ks if keyed[k]['type'] in ('code', 'edit', 'abi')]
            if len(news) == 1 and ks:
                code_rows[even] = (next(iter(news)), label(ks[0]))
                anchor_keys[even] = ks[0]   # the row an anchor's proof names
        reviewed_rows, reviewed_keys = {}, {}
        for even, news in code_map({k: v for k, v in acc.items() if k in listed_keys}).items():
            ks = [k for ks in news.values() for k in ks if keyed[k]['type'] in ('code', 'edit', 'abi')]
            if len(news) == 1 and ks and even not in code_rows:
                reviewed_rows[even] = (next(iter(news)), label(ks[0]))
                reviewed_keys[even] = ks[0]
        for k, v in vouch.items():
            if keyed[k]['family'] == 'value' and keyed[k]['type'] in ('ram', 'code'):
                values[keyed[k]['old']] = (v, label(k))
                value_keys.setdefault(keyed[k]['old'], []).append(k)
        return {'acc': vouch, 'cm': cm, 'anchors': Anchors(methods, code_rows, values, reviewed_rows), 'valueKeys': value_keys,
                'anchorKeys': anchor_keys, 'reviewedAnchorKeys': reviewed_keys, 'withoutStart': {}}

    by_key = {r['it']['key']: r for r in rows}

    def accepted_without_start(key, ctx):
        """Is the accepted row `key` accepted in this context with start left out of its own rule? Evaluating with
        start left out never asks this question again, so there is no recursion."""
        if key not in ctx['withoutStart']:
            ctx['withoutStart'][key] = key in ctx['acc'] and evaluate(by_key[key], ctx, without_start=True)['status'] == 'accepted'
        return ctx['withoutStart'][key]

    def reviewed_failures(entry, it, p, m, disagree):
        """Every condition of a REVIEWED_SITES entry that does not hold (empty when it applies)."""
        out = []
        if it['old'] != entry['old'] or p != entry['new']:
            out.append('the row is old %s with proposal %s, the entry names old %s and new %s' % (it['text'], hex(p), hex(entry['old']), hex(entry['new'])))
        n, digest = entry['bytes']
        at = (entry['new'] & ~1) - FLASH
        got = sha(new[at:at + n]) if 0 <= at and at + n <= len(new) else None
        if got != digest:
            out.append('the %d bytes at %s hash to %s, not the pinned %s' % (n, hex(entry['new'] & ~1), got, digest))
        method, text = entry['votes']
        d = m.get(method, {})
        said = d.get('votes', d.get('evidence'))
        if d.get('state') != 'agree' or said != text:
            out.append('%s is %s with %r, not agreeing with exactly %r' % (method, d.get('state', 'not run'), said, text))
        if disagree:
            out.append('%s disagree%s' % (', '.join(disagree), 's' if len(disagree) == 1 else ''))
        return out

    def mapped(cm, target, skip):
        news = cm.get(target & ~1) if target & ~1 != skip else None
        return next(iter(news)) if news and len(news) == 1 else None

    def judge(answer, want, detail):
        detail['state'] = 'none' if answer is None else 'agree' if answer == want else 'disagree'
        if answer is not None:
            detail['answer'] = hex(answer)
        return detail

    def by_g(v):
        """The suffix naming the votes that G paired (empty when none did)."""
        return ' (%d by G)' % v['byG'] if v.get('byG') else ''

    def counted(v, want, minimum=1):
        a, n, m = tally(v['votes'], minimum)
        return judge(a, want, {'votes': '%d of %d paired votes for %s%s' % (n, m, hex(a) if a is not None else 'no single address', by_g(v)),
                               'paired': m, 'sites': v['sites'], 'tried': v['tried'], **({'grown': v['grown']} if 'grown' in v else {})})

    def before(row, p, cm):
        """The new before of an edit by rule 1 (BL/B.W re-encoded) or 2 (REVIEWED_BEFORE_CHANGES); reasons otherwise."""
        it, e = row['it'], row['it']['edit']
        oa, ob, reasons, proof = it['old'], bytes.fromhex(e['before']), [], {}
        inside = lambda image, a, n: [(i, t4_target(a + i, *hw), hw[1] & 0x4000) for i, size, br, hw in instructions(image, a, n) if br and i + size <= n]
        olds = [(i, t, link, mapped(cm, t, oa & ~1)) for i, t, link in inside(old, oa, len(ob))]
        missing = [hex(t) for i, t, link, m in olds if m is None]
        expect = bytearray(ob)
        for i, t, link, m in olds:
            if m is not None:
                expect[i:i + 4] = t4_encode(p + i, m, link)
        actual, nb = new[p - FLASH: p - FLASH + len(ob)], None
        listed = REVIEWED_BEFORE_CHANGES.get((to, e['role']))
        if not missing and bytes(expect) == actual:
            nb, proof['before'] = actual, 'rule 1: the old before%s' % (' with %d BL/B.W re-encoded' % len(olds) if olds else '')
        elif listed is not None:
            rb = bytes.fromhex(listed)
            got, news = new[p - FLASH: p - FLASH + len(rb)], inside(new, p, len(rb))
            ok = len(news) == len(olds) and all(m is not None and nt & ~1 == m & ~1 and nl == link for (i, t, link, m), (j, nt, nl) in zip(olds, news))
            if got == rb and ok:
                nb, proof['before'] = got, 'rule 2: reviewed before change %s (%d bytes)' % (listed, len(rb))
            else:
                reasons.append('before: the new image holds %s at the proposal, not the reviewed before change %s%s' % (
                    got.hex(), listed, '' if ok else ' with its BL/B.W re-encoded to accepted rows'))
        else:
            reasons.append('before: the new image holds %s at the proposal, not the old before %s%s, and no reviewed before change is listed' % (
                actual.hex(), ob.hex(), ' with its BL/B.W re-encoded (targets %s are not accepted rows)' % ', '.join(missing) if missing
                else ' with its BL/B.W re-encoded' if olds else ''))
        if nb is None:
            return reasons, proof, None
        split = any(i + size > len(nb) for i, size, br, hw in instructions(new, p, len(nb)))
        trampoline = e['role'].startswith('Entry trampoline ')
        if trampoline and split:
            reasons.append('before: the trampoline edit splits an instruction in the new image')
        elif not trampoline:
            proof['splitsInstruction'] = split
        if trampoline and nb != ob:
            proof['trampolinePrologueChanged'] = '%s -> %s (trampolines.S needs a hand edit)' % (ob.hex(), nb.hex())
        out = {'newBefore': nb.hex(), 'newPad': (len(nb) - 4) // 2 if e['kind'] in ('bw', 'bl') else 0}
        if e['kind'] == 'raw':
            after = bytes.fromhex(e['after'])
            if len(ob) == len(nb) == len(after) == 2 and ob[1] == nb[1] == after[1] and (ob[1] & 0xe0) == 0x20:
                na = REVIEWED_AFTER_CHANGES.get((to, e['role']), e['after'])
                ok = len(bytes.fromhex(na)) == 2 and bytes.fromhex(na)[1] == after[1]
                if ok:
                    out.update(oldAfter=e['after'], newAfter=na)
                else:
                    reasons.append('raw after: reviewed new after %s does not keep the instruction' % na)
            else:
                reasons.append('raw after: before %s, new before %s and after %s do not differ in the immediate byte alone' % (ob.hex(), nb.hex(), after.hex()))
        return reasons, proof, out

    def evaluate(row, ctx, without_start=False):
        """{'status', 'verdict', 'checks', 'proof', 'reasons', 'blame' (accepted keys an edge or field contradicts), ...}
        without_start: start is left out of the shift/changed rule (it still runs, and its disagreement still counts);
        used only to ask whether an anchor row stands without start."""
        acc, cm = ctx['acc'], ctx['cm']
        it, p, s = row['it'], row['proposal'], row['static']
        typ, oa, name = it['type'], it['old'], it['key'][1]
        proof, reasons, blame, m = {'proposal': row['info']}, [], set(), {}
        out = {'status': 'rejected', 'verdict': None, 'checks': [], 'proof': proof, 'reasons': reasons, 'blame': blame}
        if p is None:
            reasons.append('proposal: %r is not an address' % row['text'])
            return out
        if typ in ('code', 'edit', 'abi'):
            if 'window' not in s:
                reasons.append('proposal: %s is outside the new AP image' % hex(p))
                return out
            if typ == 'code' and p & 1 != oa & 1:
                reasons.append('thumb: %s does not keep the Thumb bit of %s' % (hex(p), it['text']))
            if typ != 'code' and p & 1:
                reasons.append('thumb: a patch site or range start must be even, not %s' % hex(p))
            hits, old_hits = s['sig']['hits'], s['sig']['oldHits']
            unique_old = old_hits == [oa & ~1]
            detail = {'hits': len(hits), 'at': [hex(h) for h in hits[:6]]}
            if not unique_old:
                detail['note'] = 'old pattern not unique (%d hits in the old image: %s)' % (len(old_hits), ', '.join(hex(h) for h in old_hits[:6]))
            m['sig'] = judge(hits[0] if len(hits) == 1 and unique_old else None, p & ~1, detail)
            length = max(EDGE_BYTES, it.get('bytes', 0))
            equal, pairs = masked_window(old, oa & ~1, new, p & ~1, length) if (oa & ~1) - FLASH + length + 2 <= len(old) else (False, [])
            good, bad = [], []
            for t_old, t_new in pairs:
                news = cm.get(t_old & ~1) if t_old & ~1 != oa & ~1 else None
                if news:
                    (good if list(news) == [t_new & ~1] else bad).append('%s->%s' % (hex(t_old), hex(t_new)))
                    if list(news) != [t_new & ~1]:
                        blame.update(k for ks in news.values() for k in ks)
            m['edge'] = {'state': 'disagree' if bad else 'agree' if good else 'none', 'good': good, 'bad': bad,
                         'branches': len(pairs), 'window': '%d bytes%s' % (length, ', equal' if equal else '')}
            proof.update({'window': '%d of %d masked bytes equal at the proposal' % (s['window'], WINDOW_BYTES),
                          'prologue': s['prologue'], 'new-sig': '%d hits of the 24-byte pattern built from the new image' % s['new-sig']})
            # F2 methods: each gives its own answer (or none), compared with the proposal like every other method
            anchors, x, n = ctx['anchors'], oa & ~1, it.get('bytes', 0)
            for method, got in (('body', methods.body(x, anchors)), ('align', methods.align(x, n, anchors)),
                                ('start', methods.start(x, anchors)), ('entry', methods.entry(x, n, anchors)),
                                ('veneer', methods.veneer(x, anchors))):
                answer = got.pop('answer', None)
                m[method] = judge(answer, p & ~1, got)
            m['edge2'] = methods.edge2(x, p & ~1, n, anchors)
            for kind, at in m['edge2'].pop('blame', []):
                blame.update(k for ks in (cm.get(at, {}).values() if kind == 'code' else [ctx['valueKeys'].get(at, [])]) for k in ks)
            if typ == 'abi':
                proof['rawDifferences'] = ['+%d' % i for i in range(it['bytes']) if old[oa - FLASH + i] != new[(p & ~1) - FLASH + i]]
        if 'call' in s:
            m['call'] = counted(s['call'], p & ~1)
        pointer = (it.get('added') or {}).get('entry') == 'pointer'
        m['lit'] = counted(s['lit'], p | 1 if typ == 'abi' or pointer else p)
        if 'setter' in s:
            proof['setter'] = s['setter']
        if 'copy' in s:
            m['copy'] = judge(s['copy']['answer'], p, {'note': s['copy']['note']})
        if 'str' in s:
            m['str'] = judge(s['str']['answer'], p, {'mode': s['str']['mode'], 'note': s['str']['note']})
            at = p - data_new[3]
            if data_new[0] - FLASH <= at < data_new[1] - FLASH:
                proof['stringAtProposal'] = new[at:].split(b'\0', 1)[0].decode('latin-1')
        if 'field' in s:
            f = s['field']
            base = acc.get(f['base'])
            a, n, k = tally(f['votes'], 2)
            detail = {'votes': '%d of %d paired sites load base %s%s' % (n, k, hex(a) if a is not None else 'none', by_g(f)), 'paired': k,
                      'sites': f['sites'], 'tried': f['tried'], 'offset': hex(f['offset']), 'base': f['base'][1],
                      **({'grown': f['grown']} if 'grown' in f else {})}
            if base is None:
                m['field'] = dict(detail, state='none', note='the base row %s is not accepted' % f['base'][1])
            elif a is not None and a != base:
                m['field'] = dict(detail, state='disagree', note='the sites load %s, the accepted base is %s' % (hex(a), hex(base)))
                blame.add(f['base'])
            else:
                m['field'] = judge(None if a is None else a + f['offset'], p, detail)
        agree = [k for k in COUNTING if k in m and m[k]['state'] == 'agree']
        disagree = [k for k in COUNTING if k in m and m[k]['state'] == 'disagree']
        primary = {'code': 'sig', 'edit': 'sig', 'abi': 'sig', 'copy': 'copy', 'data': 'str'}.get(typ) or ('field' if name in FIELD_BASES else 'lit')
        locating = []
        if typ == 'data':
            shift = 'str' in agree and m['str']['mode'] == 'identical' and 'lit' in agree
            changed = 'str' in agree and m['str']['mode'] == 'reviewed' and 'lit' in agree
            primary_text = 'str with identical bytes plus lit'
        else:
            shift = primary in agree and (typ != 'ram' or m[primary]['paired'] >= 2)
            others = [k for k in agree if k != primary and not (without_start and k == 'start')]
            # LOCATING_IF methods locate only where their condition is shown to hold here (locates_if[k] is True); a
            # method without a coded condition never locates. not_locating says why an agreeing one does not.
            locates_if, not_locating = {}, {}
            if 'call' in others:
                # one mispaired caller can name a near-identical sibling, so call locates only with two paired votes
                locates_if['call'] = m['call']['paired'] >= CALL_LOCATING_VOTES
                if not locates_if['call']:
                    not_locating['call'] = '%s: call locates only with at least %d paired votes' % (m['call']['votes'], CALL_LOCATING_VOTES)
            if 'start' in others:
                # start locates only through its anchor row, so it counts as locating only when that row stands without
                # start and not through a reviewed entry
                s_even = int(m['start']['s'], 16)
                if m['start'].get('reviewedAnchor'):
                    key = ctx['reviewedAnchorKeys'].get(s_even)
                    m['start']['anchorReviewed'] = '%s is accepted through a reviewed entry' % (label(key) if key is not None else 'no anchor row')
                    locates_if['start'] = False
                    not_locating['start'] = 'its anchor row %s' % m['start']['anchorReviewed']
                else:
                    key = ctx['anchorKeys'].get(s_even)
                    free = key is not None and accepted_without_start(key, ctx)
                    m['start']['anchorWithoutStart'] = '%s %s' % (label(key) if key is not None else 'no anchor row',
                                                                 'is accepted without start' if free else 'is not accepted without start')
                    locates_if['start'] = free
                    if not free:
                        not_locating['start'] = 'its anchor row %s' % m['start']['anchorWithoutStart']
            locating = [k for k in others if k in LOCATING or (k in LOCATING_IF and locates_if.get(k) is True)]
            # edge and edge2 walk the same BL/B.W edges from the proposal (edge2 under the wider T2 mask), so for
            # `changed` they count as one method; both stay listed in the row's checks. At least one of the two must be
            # locating: two positional methods can agree on a near-identical neighbour.
            changed = not shift and len({'edge' if k == 'edge2' else k for k in others}) >= 2 and bool(locating)
            primary_text = primary + (' with two paired votes' if typ == 'ram' else '')
            if not shift:
                proof['pairRule'] = {'agreeing': others, 'locating': locating, 'holds': changed,
                                     **({'notLocating': not_locating} if not_locating else {})}
        verdict = None
        # Disagreements and the primary/changed rules are reported independently, so a rejected row names every rule that failed.
        reasons += ['%s disagrees: %s' % (k, json.dumps({x: y for x, y in m[k].items() if x != 'state'})) for k in disagree]
        listed = None if methods.off('reviewed-site') else REVIEWED_SITES.get((to, row['kind'], row['name']))
        failed = reviewed_failures(listed, it, p, m, disagree) if listed is not None else None
        if listed is not None:
            proof['reviewedSite'] = {'entry': '%s %s' % (row['kind'], row['name']), 'old': hex(listed['old']), 'new': hex(listed['new']),
                                     'bytes': list(listed['bytes']), 'votes': list(listed['votes']), 'reason': listed['reason'],
                                     'applies': not failed}
        if shift or changed:
            verdict = None if disagree else 'shift' if shift else 'changed'
            if listed is not None and not failed:
                agree = agree + ['reviewed-site']
        elif listed is not None and not failed:
            verdict, agree = 'changed', agree + ['reviewed-site']
        else:
            reasons.append('primary method %s does not hold: %s' % (primary_text, json.dumps(
                {k: {x: y for x, y in m[k].items() if x not in ('good', 'bad')} for k in (('str', 'lit') if typ == 'data' else (primary,)) if k in m})))
            reasons.append('changed needs two other counting methods to agree; agreeing: %s%s' % (
                ', '.join(k for k in agree if k != primary) or 'none', ' (edge and edge2 count as one)' if {'edge', 'edge2'} <= set(agree) else '')
                + ('' if typ == 'data' else '; at least one must be locating (%s); locating: %s%s' % (
                    LOCATING_TEXT, ', '.join(locating) or 'none',
                    ''.join('; %s does not locate (%s)' % (k, v) for k, v in proof.get('pairRule', {}).get('notLocating', {}).items()))))
        if failed:
            reasons.append('reviewed site %s %s does not apply: %s' % (row['kind'], row['name'], '; '.join(failed)))
        if it.get('added') and typ == 'ram':
            # A reviewed RAM addition: lit with at least two paired votes must name the proposal (the RAM primary).
            if not ('lit' in m and m['lit']['state'] == 'agree' and m['lit']['paired'] >= 2):
                reasons.append('reviewed RAM addition %s needs lit with at least two paired votes for the proposal: %s' % (
                    name, json.dumps({x: y for x, y in m.get('lit', {'state': 'none'}).items() if x not in ('good', 'bad')})))
        elif it.get('added') and 'resumeOf' in it['added']:
            # A resume row of an added trampoline: checked against its edit once every row is known (the fixpoint)
            pass
        elif pointer:
            # addEdits entry 'pointer': no BL caller; the stored Thumb pointer, loaded and passed to the slot setter in both
            # images, must name the proposal
            if not ('lit' in m and m['lit']['state'] == 'agree' and m['lit']['paired'] >= 1 and s['setter']['ok']):
                reasons.append('reviewed pointer-entry addition %s needs lit with a paired vote for the proposal | 1 and every '
                               'load site passing the pointer to the slot setter: %s; setter %s' % (
                                   name, json.dumps({x: y for x, y in m.get('lit', {'state': 'none'}).items() if x not in ('good', 'bad')}),
                                   json.dumps(s['setter'])))
        elif it.get('added') and not ('call' in m and m['call']['state'] == 'agree' and m['call']['paired'] >= 1):
            # A reviewed addition (addLinkld, addEdits) has no old-tree row to vouch that its old address is a function
            # start, so its old address must be an old BL/B.W target and at least one paired old caller must name the proposal.
            reasons.append('reviewed addition %s needs at least one paired call vote for the proposal (the old address must '
                           'be an old BL/B.W target): %s' % (name, json.dumps({x: y for x, y in m.get('call', {'state': 'none'}).items()
                                                                               if x not in ('good', 'bad')})))
        proof.update({k: v for k, v in m.items()})
        if typ == 'abi':   # an ABI range is "changed" exactly when its masked bytes differ (stock_abi_test then needs a review),
            # whichever way its address was accepted, a reviewed entry included
            proof['differences'] = ['+%d' % d for d in masked_differences(old, oa, new, p & ~1, it['bytes'])]
            if verdict:
                verdict = 'changed' if proof['differences'] else 'shift'
        if typ == 'edit':
            more, extra, fields = before(row, p, cm)
            reasons += more
            proof.update(extra)
            out['edit'] = fields
        if verdict and not reasons:
            out.update(status='accepted', verdict=verdict, checks=agree)
        return out

    # ---- fixpoint: rows accepted in one pass vouch (edge, field, before) in the next; contradictions are barred ----
    barred = {}
    while True:
        acc = {}
        while True:
            ctx = context(acc)
            add = {r['it']['key']: r['proposal'] for r in rows if r['it']['key'] not in acc and r['it']['key'] not in barred
                   and evaluate(r, ctx)['status'] == 'accepted'}
            if not add:
                break
            acc.update(add)
        ctx, cm, bad = context(acc), code_map(acc), {}
        for r in rows:
            k = r['it']['key']
            if k in acc:
                res = evaluate(r, ctx)
                if res['status'] != 'accepted':
                    bad[k] = 'no longer holds once every accepted row is known: ' + '; '.join(res['reasons'])
                    bad.update({b: 'contradicted by %s %r' % (r['kind'], r['name']) for b in res['blame'] if b in acc and b not in bad})
        for even, news in cm.items():
            if len(news) > 1:
                bad.update({k: 'accepted rows at old %s name different new addresses: %s' % (hex(even), ', '.join(hex(n) for n in news))
                            for ks in news.values() for k in ks if k not in bad})
        for k in acc:
            role = (keyed[k].get('added') or {}).get('resumeOf')
            if role is not None and acc.get(('edit', role)) is None:
                bad.setdefault(k, 'resume row of %r, whose edit is not accepted' % role)
            elif role is not None and acc[k] != acc[('edit', role)] + len(bytes.fromhex(keyed[('edit', role)]['edit']['before'])) + 1:
                bad.setdefault(k, 'resume row %s is not its edit %r + %d + 1 (%s)' % (hex(acc[k]), role,
                               len(bytes.fromhex(keyed[('edit', role)]['edit']['before'])), hex(acc[('edit', role)])))
        olds = {keyed[k]['old']: k for k in acc if keyed[k]['family'] == 'value'}
        for k, v in acc.items():
            if keyed[k]['family'] == 'value' and v in olds and olds[v] != k:
                bad.setdefault(k, 'new value %s equals the old value of %s: rewriting would be ambiguous' % (hex(v), olds[v][1]))
        if not bad:
            break
        barred.update(bad)
    # ---- outputs ----
    ctx, results, report_rows, rejected, prologues = context(acc), {}, [], [], []
    for r in rows:
        k, res = r['it']['key'], evaluate(r, ctx)
        if k in barred:
            res.update(status='rejected', verdict=None, checks=[])
            res['reasons'].insert(0, 'barred: ' + barred[k])
        assert (res['status'] == 'accepted') == (k in acc), k
        results[k] = res
        reason = '; '.join(res['reasons']) or None
        if 'trampolinePrologueChanged' in res['proof']:
            prologues.append({'role': r['name'], 'change': res['proof']['trampolinePrologueChanged']})
        accepted = res['status'] == 'accepted'
        report_rows.append({'kind': r['kind'], 'name': r['name'], 'old': r['it']['text'], 'proposal': hex(r['proposal']) if r['proposal'] is not None else r['text'],
                            'status': res['status'], 'verdict': res['verdict'], 'new': hex(r['proposal']) if accepted else None,
                            'checks': res['checks'], 'proof': res['proof'], 'reason': None if accepted else reason})
        if not accepted:
            rejected.append({'kind': r['kind'], 'name': r['name'], 'old': r['it']['text'], 'proposal': report_rows[-1]['proposal'], 'reason': reason})
    table_rows = {'linkld': [], 'edit': [], 'value': [], 'abi-range': []}
    universe = REVIEWED_UNIVERSE_CHANGES.get(to, {'pruneLinkld': (), 'valueToLinkld': {}})
    prune, to_link = set(universe['pruneLinkld']), dict(universe['valueToLinkld'])
    if not rejected:
        missing = sorted(prune - {k[1] for k in acc if k[0] == 'linkld'}) + sorted(set(to_link) - {k[1] for k in acc if k[0] == 'value'}) \
            + sorted(set(universe.get('addLinkld', {})) - {k[1] for k in acc if k[0] == 'linkld'}) \
            + sorted(set(universe.get('addEdits', {})) - {k[1] for k in acc if k[0] == 'edit'}) \
            + sorted({'resume_' + r.removeprefix('Entry trampoline ') for r in universe.get('addEdits', {})} - {k[1] for k in acc if k[0] == 'linkld'})
        if missing:
            raise SystemExit('rebase table NOT written: REVIEWED_UNIVERSE_CHANGES names rows that are not accepted rows: ' + ', '.join(missing))
    corrections = comment_corrections(universe.get('correctComment', {}), keyed, acc, new) if not rejected else {}
    converted = []
    for it in items:
        if it['key'] not in acc:
            continue
        p, res = acc[it['key']], results[it['key']]
        tail = {'verdict': res['verdict'], 'checks': res['checks'], 'proof': res['proof']}
        oa = it['old']
        if it['family'] == 'linkld' and it['key'][1] in prune:
            continue
        if it['family'] == 'value' and it['key'][1] in to_link:
            assert it['type'] == 'ram', it['key'][1] + ': only a RAM value becomes a link.ld row'
            converted.append(dict({'symbol': to_link[it['key'][1]], 'old': it['text'], 'new': hex(p), 'delta': p - oa,
                                   'fromValue': it['key'][1]}, **tail))
            continue
        if it['family'] == 'linkld':
            row = {'symbol': it['key'][1], 'old': it['text'], 'new': hex(p), 'delta': (p & ~1) - (oa & ~1)}
        elif it['family'] == 'edit':
            e, x = it['edit'], res['edit']
            row = {'role': e['role'], 'kind': e['kind'], 'oldAddress': e['address'], 'newAddress': hex(p), 'oldOffset': e['offset'],
                   'newOffset': hex(p - FLASH), 'delta': (p & ~1) - (oa & ~1), 'oldBefore': e['before'], 'newBefore': x['newBefore'],
                   'oldPad': e['pad'], 'newPad': x['newPad'], **{k: x[k] for k in ('oldAfter', 'newAfter') if k in x}}
        elif it['family'] == 'value':
            row = {'name': it['key'][1], 'kind': it['type'], 'old': it['text'], 'new': hex(p), 'sites': it['sites']}
            if it['key'][1] in corrections:
                row.update(new=corrections[it['key'][1]]['new'], derivedNew=hex(p), correction=corrections[it['key'][1]]['reason'])
            if it['type'] == 'data':
                row.update(oldString=it['static']['str']['old'].decode(), newString=it['static']['str']['new'].decode())
        else:
            row = {'old': it['text'], 'new': hex(p), 'bytes': it['bytes'], 'oldSHA256': it['range'][col + 'SHA256'],
                   'newSHA256': sha(new[p - FLASH: p - FLASH + it['bytes']])}
        table_rows[it['family']].append(dict(row, **tail))
    table_rows['linkld'] += converted
    module = bases[to]['moduleVA']
    described_inputs = [(role, Path(path)) for role, path in (
        ('readiness proposals (TSV; compared with, never used to derive)', args.propose),
        ('old table %s to %s' % (prev[0], prev[1]), tree/'baseline'/prev[2]),
        ('stock ZIP %s' % frm, args.stock_old), ('stock ZIP %s' % to, args.stock_new))]
    table = {
        'format': 'turboio-rebase-2', 'from': frm, 'to': to,
        'note': 'Generated by firmware/tools/rebase_derive.py --propose; do not edit by hand. Applied by firmware/tools/rebase_apply.py.',
        'thumbConvention': THUMB_CONVENTION,
        'provenance': {'generator': 'firmware/tools/rebase_derive.py --propose',
                       'inputs': [{'role': role, 'path': described(p, args.inputs_root), 'sha256': sha(p.read_bytes())} for role, p in described_inputs],
                       'tree': 'firmware tree on stock %s (%s)' % (frm, described(tree, args.inputs_root)),
                       'stock': {b: bases[b]['stockZIPFile'] for b in (frm, to)},
                       'reviewed': {'beforeChanges': {r: v for (t, r), v in REVIEWED_BEFORE_CHANGES.items() if t == to},
                                    'afterChanges': {r: v for (t, r), v in REVIEWED_AFTER_CHANGES.items() if t == to},
                                    'stringChanges': {n: list(v) for (t, n), v in REVIEWED_STRING_CHANGES.items() if t == to},
                                    'sites': {'%s %s' % (k, n): {'old': hex(v['old']), 'new': hex(v['new']), 'bytes': list(v['bytes']),
                                                                 'votes': list(v['votes']), 'reason': v['reason']}
                                              for (t, k, n), v in REVIEWED_SITES.items() if t == to},
                                    **({'universe': {'pruneLinkld': list(universe['pruneLinkld']),
                                                     'valueToLinkld': dict(universe['valueToLinkld']),
                                                     'addLinkld': {k: dict(v) for k, v in universe.get('addLinkld', {}).items()},
                                                     **({'addEdits': {k: dict(v) for k, v in universe['addEdits'].items()}}
                                                        if 'addEdits' in universe else {}),
                                                     **({'correctComment': {k: dict(v, bytes=list(v['bytes'])) for k, v in universe['correctComment'].items()}}
                                                        if 'correctComment' in universe else {}),
                                                     'reason': universe['reason']}} if to in REVIEWED_UNIVERSE_CHANGES else {})}},
        'bases': bases,
        'moduleVA': {'old': old_table['moduleVA'][col], 'new': module, 'derivation': MODULE_DERIVATION},
        'linkld': table_rows['linkld'], 'edits': table_rows['edit'], 'values': table_rows['value'],
        'stockAbiRanges': table_rows['abi-range'],
        'notStock': old_table['notStock'], 'scanExempt': old_table['scanExempt'],
        'rejected': rejected,
    }
    counts = {'rows': len(rows), 'accepted': len(acc), 'rejected': len(rejected),
              'byFamily': {f: {'accepted': sum(1 for r in report_rows if r['status'] == 'accepted' and (r['kind'].split('-')[0] if f == 'value' else r['kind']) == f),
                               'rejected': sum(1 for r in report_rows if r['status'] == 'rejected' and (r['kind'].split('-')[0] if f == 'value' else r['kind']) == f)}
                           for f in ('linkld', 'edit', 'value', 'abi-range')},
              'byVerdict': dict(collections.Counter(r['verdict'] for r in report_rows if r['verdict']))}
    report = {'pair': '%s:%s' % (frm, to), 'tsv': {'path': described(args.propose, args.inputs_root), 'sha256': sha(Path(args.propose).read_bytes())},
              'disabledMethods': disabled, 'moduleVA': module, 'counts': counts, 'trampolinePrologueChanges': prologues, 'rows': report_rows}
    if args.out is not None:   # never with --disable-method (main refuses --out there)
        args.out.write_text(json.dumps(table, indent=1) + '\n')
    args.report.write_text(json.dumps(report, indent=1) + '\n')
    print(json.dumps(dict(counts, moduleVA=module)))
    if rejected:
        raise SystemExit(3)
    return 0


# --self-test fixtures on the 1.0.5.12 and 1.0.6.11 AP images (pinned by sha256). G: seven call sites that a looser
# grow rule mispaired; G must refuse six and pair the seventh inside the local shift (G runs on lit and field sites, and on
# the call sites of reviewed additions only, which must also agree with every other method). body: eight groups of old twin functions; the twin guard must leave 15 without an answer and decide
# 0x105c8fd0 only through the distinguishing edge at +16 between two fixed functions.
SELF_TEST_AP = {'old': 'af701a6525fbf703854b3d63e757734546c20bdb5d50e246867dc6a0565713ae',
                'new': '9bbf7be31ebb7f8600e6ea4bf51831a151e2af6d4eb8e6ccfcf55d67f2e71260'}
SELF_TEST_GROW = ((0x106ad278, None), (0x106aee0c, None), (0x10692fb4, None), (0x10691a90, None), (0x10688e06, None),
                  (0x10830574, None), (0x1068811a, 0x106a6d24))
SELF_TEST_TWINS = ((0x105732fc, 0x1059f1a4), (0x10583e6e, 0x1085bf02), (0x1059f15c, 0x106abfb0), (0x1059f4e8, 0x1059f8e4),
                   (0x105c8f98, 0x105c8fd0), (0x106485e8, 0x10657520), (0x106ab6dc, 0x106b74e8), (0x1082e5a4, 0x1084e210))
SELF_TEST_TWIN_ANSWER = (0x105c8fd0, 0x105dd92c, '+16 0x105d4c08->0x105ec748 (fixed)')


def self_test(args):
    """--self-test: the G and twin fixtures, with fixed functions as the only anchors (no rows). Exit 0 when every
    fixture gives its pinned outcome, else exit 1 naming each one that did not."""
    images = {}
    for side, path in (('old', args.stock_old), ('new', args.stock_new)):
        with zipfile.ZipFile(path) as z:
            images[side] = z.read('nuttx_ap.bin')
        if sha(images[side]) != SELF_TEST_AP[side]:
            raise SystemExit('self-test: %s AP sha256 %s is not the pinned %s' % (side, sha(images[side]), SELF_TEST_AP[side]))
    methods = Methods(images['old'], images['new'], branch_index(images['old']))
    anchors, failures = Anchors(methods, {}, {}), []
    for site, want in SELF_TEST_GROW:
        got, proof = methods.grow(site)
        print('G %s: %s; %s' % (hex(site), hex(got) if got is not None else 'refused', ' | '.join(proof)))
        if got != want:
            failures.append('G %s: %s, pinned %s' % (hex(site), hex(got) if got is not None else 'refused', hex(want) if want else 'refused'))
    x_answer, new_answer, edge = SELF_TEST_TWIN_ANSWER
    for x in [x for group in SELF_TEST_TWINS for x in group]:
        got = methods.body(x, anchors)
        print('body %s: %s; %s' % (hex(x), hex(got['answer']) if 'answer' in got else 'none',
                                    json.dumps({k: v for k, v in got.items() if k != 'answer'})))
        if x == x_answer:
            if got.get('answer') != new_answer or edge not in got.get('edges', []) or got.get('survivors') != [hex(new_answer)] \
                    or got.get('twinsRuledOut') != '1 of 1':
                failures.append('body %s: %s, pinned %s through %s with one survivor and the twin ruled out' % (
                    hex(x), json.dumps(got, default=str), hex(new_answer), edge))
        elif 'answer' in got:
            failures.append('body %s: answered %s, pinned none' % (hex(x), hex(got['answer'])))
    if failures:
        raise SystemExit('self-test FAILED:\n  ' + '\n  '.join(failures))
    print('self-test PASS: G refuses 6 of 7 sites and pairs %s -> %s; body answers 1 of 16 twins (%s -> %s)' % (
        hex(SELF_TEST_GROW[-1][0]), hex(SELF_TEST_GROW[-1][1]), hex(x_answer), hex(new_answer)))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description='Derive a rebase table (no device I/O). Legacy mode: --lookup; '
                                     'propose mode: --propose (see the module docstring); --self-test: the method fixtures.')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--lookup', type=Path, help='legacy: decomp lookup (proposed 1.0.5.12 addresses)')
    mode.add_argument('--propose', type=Path, metavar='TSV', help='propose: readiness TSV of proposed addresses')
    mode.add_argument('--self-test', action='store_true', help='the G and twin fixtures (needs --stock-old and --stock-new)')
    parser.add_argument('--matches', type=Path, help='legacy: decomp matcher pairs')
    parser.add_argument('--study', type=Path, help='legacy: decomp study, corrected copy')
    parser.add_argument('--tree', type=Path, help='legacy: a firmware tree on stock 1.0.5.5 (TMG9); default this tree')
    parser.add_argument('--old-tree', type=Path, help='propose: the firmware tree on stock --from')
    parser.add_argument('--stock-old', type=Path, help='propose: stock ZIP of --from')
    parser.add_argument('--stock-new', type=Path, help='propose: stock ZIP of --to')
    parser.add_argument('--from', dest='frm', help='propose: old stock base')
    parser.add_argument('--to', help='propose: new stock base')
    parser.add_argument('--report', type=Path, help='propose: per-row report (JSON)')
    parser.add_argument('--inputs-root', type=Path, default=os.environ.get('TURBO_INPUTS'))
    parser.add_argument('--disable-method', action='append', choices=DISABLE_METHODS, metavar='NAME',
                        help='propose, acceptance only (repeatable): run with this method as none; needs --report and '
                             'refuses --out, so a mutated run never writes a table. One of: ' + ', '.join(DISABLE_METHODS))
    parser.add_argument('--out', type=Path, help='the table (legacy and propose; refused with --disable-method)')
    args = parser.parse_args(argv)
    if args.self_test:
        given = [n for n in ('matches', 'study', 'tree', 'old_tree', 'frm', 'to', 'report', 'out', 'disable_method') if getattr(args, n)]
        if given or not (args.stock_old and args.stock_new):
            parser.error('--self-test needs --stock-old and --stock-new and takes no other option')
        return self_test(args)
    if args.lookup:
        given = [n for n in ('old_tree', 'stock_old', 'stock_new', 'frm', 'to', 'report', 'disable_method') if getattr(args, n) is not None]
        if given or not (args.matches and args.study and args.out):
            parser.error('legacy mode (--lookup) needs --matches, --study and --out and takes none of the propose options')
        args.tree = args.tree or FW
        refuse_inside([args.out], [args.tree])
        refuse_overwrite([('--out', args.out)], [('--lookup', args.lookup), ('--matches', args.matches), ('--study', args.study)])
        return legacy(args)
    missing = [n for n in ('old_tree', 'stock_old', 'stock_new', 'frm', 'to', 'report') if getattr(args, n) is None]
    if missing or args.matches or args.study or args.tree:
        parser.error('propose mode needs --old-tree, --stock-old, --stock-new, --from, --to, --out and --report, '
                     'and takes none of --matches, --study, --tree')
    if args.disable_method and args.out is not None:
        parser.error('--disable-method refuses --out: a run with a disabled method never writes a table')
    if not args.disable_method and args.out is None:
        parser.error('propose mode needs --out (it is optional only with --disable-method, which refuses it)')
    if args.out is not None and args.out.resolve() == args.report.resolve():
        parser.error('--out and --report must be different files')
    refuse_inside([p for p in (args.out, args.report) if p is not None], [args.old_tree])
    refuse_overwrite([('--out', args.out), ('--report', args.report)],
                     [('--propose', args.propose), ('--stock-old', args.stock_old), ('--stock-new', args.stock_new)])
    return propose(args)


if __name__ == '__main__':
    sys.exit(main())
