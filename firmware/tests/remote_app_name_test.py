#!/usr/bin/env python3
"""The app name the remote admits inside stock Navigation (remote_native.c input_allowed) is the name stock's launcher
table gives its Navigation entry, read from the stock AP itself (owner decision of 2026-11-14; phase F4).

Chain, every step decoded from the image: stock launch-by-index is the one place in the AP flash where
`cmp r0,#7; [one halfword]; bhi; ldr r3,[pc,#imm]; lsls r0,r0,#4; ldr r0,[r3,r0]` occurs (a halfword scan that must
find exactly one hit; it cannot see a differently scheduled copy of the same code, and then fails rather than passes),
so the table has 8 entries of 16 bytes at the literal; entry 4 word 0 is a .data
address, mapped to a file offset by rebase_apply.data_offset (the .data copy descriptor, checked against
KNOWN_DATA_DELTA); the bytes there, up to the NUL, must equal the one string literal in input_allowed(). Every other
entry's word 0 must map to a NUL-preceded, NUL-terminated printable string too, so a moved table fails here.
An AP without exactly one such sequence is refused (1.0.5.12's launcher has 7 entries). Prints the name as SHA-256
and length only. The source holds no stock address, so rebase_apply's leftover scan of tests/ stays clean.

  python3 -I firmware/tests/remote_app_name_test.py --stock <1.0.6.11 members ZIP> [--remote <remote_native.c>]
"""
from pathlib import Path
import argparse, hashlib, importlib.util, re, struct, zipfile

FW = Path(__file__).resolve().parents[1]
NAVIGATION_ENTRY = 4


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    ap_ = argparse.ArgumentParser()
    ap_.add_argument('--stock', type=Path, required=True)
    ap_.add_argument('--remote', type=Path, default=FW/'src/global-remote-v1/remote_native.c')
    a = ap_.parse_args()
    rebase = load(FW/'tools/rebase_apply.py', 'remote_app_name_rebase')
    with zipfile.ZipFile(a.stock) as z:
        ap = z.read('nuttx_ap.bin')
    h = struct.unpack_from('<%dH' % (len(ap) // 2), ap)
    hits = [i for i in range(len(h) - 6) if h[i] == 0x2807 and h[i + 2] & 0xff00 == 0xd800 and h[i + 3] & 0xff00 == 0x4b00
            and h[i + 4] == 0x0100 and h[i + 5] == 0x5818]
    assert len(hits) == 1, 'launch-by-index: %d candidate sequences, want exactly 1' % len(hits)
    f = rebase.FLASH + 2 * hits[0] - 2   # the function starts one halfword (its push) before the cmp
    ldr = h[hits[0] + 3]
    at = rebase.FLASH + 2 * (hits[0] + 3)   # the ldr r3,[pc,#imm]
    table = struct.unpack_from('<I', ap, ((at + 4) & ~3) + 4 * (ldr & 0xff) - rebase.FLASH)[0]
    names = []
    for i in range(8):
        word = struct.unpack_from('<I', ap, rebase.data_offset(ap, table + 16 * i))[0]
        off = rebase.data_offset(ap, word)
        end = ap.index(b'\0', off)
        s = ap[off:end]
        assert ap[off - 1] == 0 and 0 < len(s) < 64 and all(0x20 < c < 0x7f for c in s), 'entry %d word 0 is not a string' % i
        names.append(s)
    text = a.remote.read_text()
    head = re.search(r'\bbool\s+input_allowed\s*\(\s*void\s*\)\s*\{', text)
    assert head, 'no definition of input_allowed(void) in %s' % a.remote
    depth, i = 1, head.end()
    while depth:   # the body, by brace depth (the function holds no brace inside a string)
        depth += {'{': 1, '}': -1}.get(text[i], 0); i += 1
    literals = re.findall(r'"((?:\\.|[^"\\])*)"', text[head.end():i - 1])
    assert len(literals) == 1, 'input_allowed must hold exactly one string literal, found %d' % len(literals)
    want = literals[0].encode()
    nav = names[NAVIGATION_ENTRY]
    assert want == nav, 'input_allowed admits sha256=%s,len=%d; stock entry %d is sha256=%s,len=%d' % (
        hashlib.sha256(want).hexdigest(), len(want), NAVIGATION_ENTRY, hashlib.sha256(nav).hexdigest(), len(nav))
    assert names.count(nav) == 1, 'the Navigation name must name one entry only'
    print('PASS remote app name: stock launcher table %#x (8 entries, read through the launch-by-index sequence at %#x) entry %d names the '
          'app input_allowed admits (sha256=%s,len=%d)' % (table, f, NAVIGATION_ENTRY, hashlib.sha256(nav).hexdigest(), len(nav)))


if __name__ == '__main__':
    main()
