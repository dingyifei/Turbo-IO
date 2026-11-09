"""Derive firmware/baseline/rebase-1.0.5.5-to-1.0.5.12.json from the decomp's static rebase study.

Offline and read-only on every input. Never connects to a device. Usage (paths are examples):

  python3 -I firmware/tools/rebase_derive.py \
    --lookup  "$TURBO_INPUTS/decomp/dirty/wf-2/delta1012/tools/tmg-lookup.json" \
    --matches "$TURBO_INPUTS/decomp/dirty/wf-2/delta1012/ap/matches.json" \
    --study   "$TURBO_INPUTS/decomp/dirty/wf-2/delta1012/review-w1/TMG-REBASE.corrected.md" \
    --out firmware/baseline/rebase-1.0.5.5-to-1.0.5.12.json

The tree read must be on stock 1.0.5.5 with the TMG9 pins: the TMG9 tree. Since the tree moved to 1.0.5.12, run it
on an export of the tag (`git archive fw/tmg9 firmware | tar -x -C DIR`, then `--tree DIR/firmware`); the output is
byte-identical to the committed table (checked when the table was committed). The decomp lookup supplies the proposed 1.0.5.12 address of every code reference
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
"""
import argparse
import bisect
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import zipfile

FW = Path(__file__).resolve().parents[1]
ROOT = FW.parent
FLASH = 0x10190000
DATA_RUNTIME = 0x18000000
DATA_FILE = 0x401bc  # file offset of the .data copy source (copy descriptor +0x674); same in both images
OLD_BASE, NEW_BASE = '1.0.5.5', '1.0.5.12'
STOCK = {OLD_BASE: ROOT/'firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip',
         NEW_BASE: ROOT/'firmware-research/strix-1.0.5.12/stock/Strix-OS-1.0.5.12-original.zip'}
# The study's manual correction (TMG-REBASE.corrected.md section 2): the matcher's extrapolated value was wrong.
CORRECTIONS = {'tgr_intercept': 0x1062c439}
# Copy +0x408 region (memcpy, memset, strcmp, strlen): copied to the same address in both images.
COPY_REGION = range(0x100000, 0x101000)
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lookup', type=Path, required=True)
    parser.add_argument('--matches', type=Path, required=True)
    parser.add_argument('--study', type=Path, required=True)
    parser.add_argument('--tree', type=Path, default=FW, help='a firmware tree on stock 1.0.5.5 (TMG9)')
    parser.add_argument('--inputs-root', type=Path, default=os.environ.get('TURBO_INPUTS'))
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
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
        so = old[DATA_FILE + o - DATA_RUNTIME:].split(b'\0', 1)[0]
        sn = new[DATA_FILE + nv - DATA_RUNTIME:].split(b'\0', 1)[0]
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
        'stockAbiRanges': ranges,
    }
    args.out.write_text(json.dumps(table, indent=1) + '\n')
    counts = {'linkld': len(rows), 'moved': sum(r['new'] != r['old'] for r in rows), 'edits': len(edits),
              'reencoded': sum('reencodedBranches' in e for e in edits), 'values': len(values),
              'sites': sum(sum(v['sites'].values()) for v in values), 'ranges': len(ranges)}
    print(json.dumps(counts))


if __name__ == '__main__':
    main()
