#!/usr/bin/env python3
"""The Chinese grid label of each of the 8 stock apps is the name stock's own carousel shows for it in simplified
Chinese, read from the stock AP itself (review finding F6 of the candidate 3 batch: stock 1.0.6.11 renamed the app at
rank 2 and nothing in the tree noticed).

Chain, every step decoded from the image:
1. The label key by rank. Stock's carousel label function (the one m8_hook_refresh_label replaces) gets the text key
   of a rank from one small function and hands it to the language manager (decoded by hand when this test was written;
   the test does not re-check that caller). That function is the one place in the AP flash where `cmp r0,#7;
   [two halfwords, one of them mov r4,r0]; bhi; cmp r0,#6; beq; ldr r3,[pc,#imm]; add.w r3,r3,r4,lsl #4;
   ldr r0,[r3,#imm5*4]` occurs (a halfword scan that must find exactly one hit; a differently scheduled copy makes it
   fail, not pass), and the scan
   requires at least one bl to the halfword before it (its push). So the key of rank r is word imm5 of entry r of a
   16-byte-entry table, for r 0..7. That table must be the one stock's launch-by-index uses (the sequence
   remote_app_name_test.py reads). Every key and every table pointer below is a .data address, mapped to a file offset
   by rebase_apply's .data copy descriptor (data_copy, read once; the same mapping as data_offset).
   Rank 6 has a second key: the beq goes to `bl; cmp r0,#0; beq back; ldr r0,[pc,#imm]`, a key stock uses instead when
   that call returns nonzero. The test decodes it, requires it to be a key of the simplified-Chinese table and prints
   its value as length and SHA-256, but does not compare it: the module's grid shows one fixed name per app.
2. The language tables. Stock registers each of its language tables by a call `register(r0, tag, table, count)`, each
   one compiled as `movw r3,#count` followed by `ldr r2,[pc,#imm]` (the table), `ldr r1,[pc,#imm]` (the language tag)
   and `mov r0,r4` in any order, then a `bl`. The scan collects every such sequence in the AP flash and groups them by
   the bl target. Among the targets called this way two or more times, exactly one may have every call name a short
   ASCII tag in .data and a table of `count` pairs of {key pointer, value pointer}, both NUL-terminated strings in
   .data, with no key twice; its calls are the language tables (on 1.0.6.11 one other target is called this way, with
   arguments that are not such tables). Every bl in the AP that reaches that function must be one of these calls, so a
   table registered by a call compiled another way cannot drop out unseen.
3. Which table is simplified Chinese. The structural reason is the tag the table is registered under: the test takes
   the table registered with the tag "zh-CN" (the BCP 47 tag for Chinese as written in mainland China, in simplified
   characters; a standard identifier, not a string taken from the image). Exactly one table may carry it. As a second,
   independent check, the test compares the module's 8 labels with every registered table and requires that exactly
   one table matches all of them, and that it is the zh-CN one. It prints how many tables exist.

The module's side is parsed from the sources, not typed here: the rank-to-text-key mapping is the first 8 entries of
names[] in the 1.0.6.11 branch of focus-v1/focus_menu.c (tile ids 0..7 are stock's 8 apps in stock order), and each
label is that key's entry in zh[] of common-v1/tio_text.c. English labels are the module's own wording by design and
are not compared.

RULED_EXCEPTIONS lists ranks whose label the lead has ruled may differ from stock, each with its reason; a listed rank
must still differ (a stale entry fails). It is empty: all 8 labels matched stock 1.0.6.11 when the test was written.

The test holds no stock address and no stock string; it prints only lengths and SHA-256.

  python3 -I firmware/tests/grid_label_stock_test.py --stock <1.0.6.11 members ZIP> [--text <tio_text.c>] [--menu <focus_menu.c>]
"""
from pathlib import Path
import argparse, hashlib, importlib.util, re, struct, zipfile

FW = Path(__file__).resolve().parents[1]
STOCK_RANKS = 8
SIMPLIFIED_CHINESE_TAG = b'zh-CN'   # BCP 47: language zh, region CN (simplified script); a standard tag, see step 3
RULED_EXCEPTIONS = {}               # rank -> reason, only by a lead ruling


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(b):
    return 'sha256=%s,len=%d' % (hashlib.sha256(b).hexdigest(), len(b))


def bl_target(at, h1, h2):
    """Target of a Thumb-2 bl at address `at`, or None when the two halfwords are not a bl."""
    if h1 >> 11 != 0x1e or h2 & 0xd000 != 0xd000:
        return None
    s = (h1 >> 10) & 1
    i1, i2 = 1 - (((h2 >> 13) & 1) ^ s), 1 - (((h2 >> 11) & 1) ^ s)
    off = (s << 24) | (i1 << 23) | (i2 << 22) | ((h1 & 0x3ff) << 12) | ((h2 & 0x7ff) << 1)
    return at + 4 + (off - (1 << 25) if s else off)


def at(ap, first):
    """Halfword indices of every aligned place where the halfword matching the bytes regex `first` (two bytes, little
    endian) starts; the regex engine only narrows the candidates, every caller tests the full sequence itself."""
    return [m.start() // 2 for m in re.finditer(b'(?=' + first + b')', ap, re.S) if not m.start() & 1]


def pc_word(ap, flash, addr, imm8):
    """The literal of a 16-bit ldr Rt,[pc,#imm8*4] at address `addr`."""
    return struct.unpack_from('<I', ap, ((addr + 4) & ~3) + 4 * imm8 - flash)[0]


def cstring(ap, rebase, va):
    off = data_offset(ap, rebase, va)
    end = ap.index(b'\0', off)
    return ap[off:end]


def c_body(text, head_re, what):
    head = re.search(head_re, text)
    assert head, 'no %s' % what
    end = text.index('};', head.end())
    return text[head.end():end]


def module_labels(text_path, menu_path):
    """rank -> (text key name, UTF-8 bytes of zh[key]) for the 8 stock ranks, parsed from the sources."""
    menu = menu_path.read_text()
    branch = re.search(r'#if\s+defined\(TD_STOCK_10611\)\s*&&\s*TD_STOCK_10611\s*\n(.*?)\n#else', menu, re.S)
    assert branch, 'focus_menu.c: no TD_STOCK_10611 branch'
    names = c_body(branch.group(1), r'static\s+const\s+unsigned\s+names\[\]\s*=\s*\{', 'names[] in the 1.0.6.11 branch')
    keys = [k.strip() for k in names.split(',') if k.strip()]
    assert len(keys) >= STOCK_RANKS and all(re.fullmatch(r'TT_\w+', k) for k in keys), 'names[] is not a list of TT_ keys'
    text = text_path.read_text(encoding='utf-8')
    zh_body = c_body(text, r'static\s+const\s+char\s*\*\s*const\s+zh\[TT_COUNT\]\s*=\s*\{', 'zh[] in tio_text.c')
    zh = {}
    for key, lit in re.findall(r'\[(TT_\w+)\]\s*=\s*"((?:\\.|[^"\\])*)"', zh_body):
        assert key not in zh, 'zh[%s] given twice' % key
        zh[key] = lit
    out = {}
    for rank in range(STOCK_RANKS):
        assert keys[rank] in zh, 'zh[] has no entry for %s (rank %d)' % (keys[rank], rank)
        assert '\\' not in zh[keys[rank]], 'zh[%s] holds an escape; this test compares plain UTF-8 literals only' % keys[rank]
        out[rank] = (keys[rank], zh[keys[rank]].encode('utf-8'))
    return out


def label_keys(ap, rebase, h):
    """(table address, word index, rank -> key bytes, rank-6 alternative key bytes) from the key-by-rank function."""
    flash = rebase.FLASH
    hits = [i for i in at(ap, rb'\x07\x28') if i < len(h) - 10 and 0x4604 in (h[i + 1], h[i + 2]) and h[i + 3] & 0xff00 == 0xd800 and h[i + 4] == 0x2806
            and h[i + 5] & 0xff00 == 0xd000 and h[i + 6] & 0xff00 == 0x4b00 and h[i + 7] == 0xeb03 and h[i + 8] == 0x1304
            and h[i + 9] & 0xf83f == 0x6818]
    assert len(hits) == 1, 'label key by rank: %d candidate sequences, want exactly 1' % len(hits)
    i = hits[0]
    start = flash + 2 * (i - 1)
    assert h[i - 1] & 0xfe00 == 0xb400, 'label key by rank: no push right before the cmp'
    callers = sum(1 for j in at(ap, rb'.[\xf0-\xf7]') if j < len(h) - 1 and bl_target(flash + 2 * j, h[j], h[j + 1]) == start)
    assert callers >= 1, 'label key by rank: no bl reaches the function'
    table = pc_word(ap, flash, flash + 2 * (i + 6), h[i + 6] & 0xff)
    word = (h[i + 9] >> 6) & 0x1f
    keys = {}
    for rank in range(STOCK_RANKS):
        keys[rank] = cstring(ap, rebase, struct.unpack_from('<I', ap, data_offset(ap, rebase, table + 16 * rank + 4 * word))[0])
    # the rank-6 branch: beq forward to bl; cmp r0,#0; beq back; ldr r0,[pc,#imm]
    beq = h[i + 5]
    j = i + 5 + 2 + (beq & 0xff if not beq & 0x80 else (beq & 0xff) - 256)
    assert bl_target(flash + 2 * j, h[j], h[j + 1]) is not None and h[j + 2] == 0x2800 and h[j + 3] & 0xff00 == 0xd000 \
        and h[j + 4] & 0xf800 == 0x4800 and (h[j + 4] >> 8) & 7 == 0, 'rank 6 branch is not bl; cmp r0,#0; beq; ldr r0,[pc]'
    alt = cstring(ap, rebase, pc_word(ap, flash, flash + 2 * (j + 4), h[j + 4] & 0xff))
    return table, word, keys, alt


def launch_table(ap, rebase, h):
    """The launcher table of stock launch-by-index (the same scan as remote_app_name_test.py)."""
    hits = [i for i in at(ap, rb'\x07\x28') if i < len(h) - 6 and h[i + 2] & 0xff00 == 0xd800 and h[i + 3] & 0xff00 == 0x4b00
            and h[i + 4] == 0x0100 and h[i + 5] == 0x5818]
    assert len(hits) == 1, 'launch-by-index: %d candidate sequences, want exactly 1' % len(hits)
    return pc_word(ap, rebase.FLASH, rebase.FLASH + 2 * (hits[0] + 3), h[hits[0] + 3] & 0xff)


_COPY = {}


def copied(ap, rebase):
    """rebase_apply.data_copy of the image, read once (it hashes the whole image on every call)."""
    if id(ap) not in _COPY:
        _COPY[id(ap)] = rebase.data_copy(ap)
    return _COPY[id(ap)]


def data_offset(ap, rebase, va):
    """rebase_apply.data_offset with the descriptor read once: the file offset of the copied .data byte at `va`."""
    src, end, dst, delta = copied(ap, rebase)
    assert dst <= va < dst + (end - src), 'an address is not in the copied data range'
    return va - delta


def in_data(ap, rebase, va, size=1):
    src, end, dst, _ = copied(ap, rebase)
    return dst <= va and va + size <= dst + (end - src)


def read_table(ap, rebase, tag_va, table, count):
    """(tag bytes, {key: value}) of one registration call, or None when its tag is not a short ASCII string in .data or
    its table is not `count` pairs of .data string pointers with no key twice."""
    def string(va):
        if not in_data(ap, rebase, va):
            return None
        off = data_offset(ap, rebase, va)
        end = ap.find(b'\0', off, off + 4096)
        return ap[off:end] if end >= 0 else None
    tag = string(tag_va)
    if not tag or len(tag) >= 16 or not all(0x20 < c < 0x7f for c in tag) or not 0 < count < 4096 \
            or not in_data(ap, rebase, table, 8 * count):
        return None
    pairs = {}
    for n in range(count):
        k, v = struct.unpack_from('<II', ap, data_offset(ap, rebase, table + 8 * n))
        key, value = string(k), string(v)
        if not key or value is None or key in pairs:
            return None
        pairs[key] = value
    return tag, pairs


def language_tables(ap, rebase, h):
    """[(tag bytes, {key: value})] of every table registered through the one registration function."""
    flash = rebase.FLASH
    groups = {}
    for i in at(ap, rb'[\x40-\x4f][\xf2\xf6]'):
        if i >= len(h) - 6 or h[i] & 0xfbf0 != 0xf240 or (h[i + 1] >> 8) & 0xf != 3 or h[i + 1] & 0x8000:
            continue
        count = (h[i] & 0xf) << 12 | ((h[i] >> 10) & 1) << 11 | ((h[i + 1] >> 12) & 7) << 8 | (h[i + 1] & 0xff)
        mid = h[i + 2:i + 5]
        r2 = [k for k in range(3) if mid[k] & 0xff00 == 0x4a00]
        r1 = [k for k in range(3) if mid[k] & 0xff00 == 0x4900]
        if len(r2) != 1 or len(r1) != 1 or sorted(mid) != sorted([mid[r2[0]], mid[r1[0]], 0x4620]):
            continue
        target = bl_target(flash + 2 * (i + 5), h[i + 5], h[i + 6])
        if target is None:
            continue
        a2, a1 = i + 2 + r2[0], i + 2 + r1[0]
        groups.setdefault(target, []).append((pc_word(ap, flash, flash + 2 * a1, mid[r1[0]] & 0xff),
                                               pc_word(ap, flash, flash + 2 * a2, mid[r2[0]] & 0xff), count))
    readable = {t: [read_table(ap, rebase, *call) for call in calls] for t, calls in groups.items() if len(calls) >= 2}
    many = [t for t, tables in readable.items() if all(tables)]
    assert len(many) == 1, 'language table registration: %d functions called two or more times with movw r3 / ldr r2 / ' \
        'ldr r1 / mov r0,r4 where every call names a short ASCII tag and a table of string pairs, want exactly 1 ' \
        '(%d called that way at all)' % (len(many), len(readable))
    tables = readable[many[0]]
    calls = sum(1 for j in at(ap, rb'.[\xf0-\xf7]') if j < len(h) - 1 and bl_target(flash + 2 * j, h[j], h[j + 1]) == many[0])
    assert calls == len(tables), 'language table registration: %d bl reach the function but %d match the call pattern; ' \
        'a call compiled another way would drop its table unseen' % (calls, len(tables))
    tags = [t for t, _ in tables]
    assert len(set(tags)) == len(tags), 'two language tables share a tag'
    return tables


def main():
    ap_ = argparse.ArgumentParser()
    ap_.add_argument('--stock', type=Path, required=True)
    ap_.add_argument('--text', type=Path, default=FW/'src/common-v1/tio_text.c')
    ap_.add_argument('--menu', type=Path, default=FW/'src/focus-v1/focus_menu.c')
    a = ap_.parse_args()
    rebase = load(FW/'tools/rebase_apply.py', 'grid_label_rebase')
    with zipfile.ZipFile(a.stock) as z:
        ap = z.read('nuttx_ap.bin')
    h = struct.unpack_from('<%dH' % (len(ap) // 2), ap)
    mine = module_labels(a.text, a.menu)
    table, word, keys, alt = label_keys(ap, rebase, h)
    assert table == launch_table(ap, rebase, h), 'the label keys do not come from the launch-by-index table'
    assert len(set(keys.values())) == STOCK_RANKS, 'two ranks share a label key'
    tables = language_tables(ap, rebase, h)
    zh = [p for t, p in tables if t == SIMPLIFIED_CHINESE_TAG]
    assert len(zh) == 1, '%d tables registered with the simplified-Chinese tag, want exactly 1' % len(zh)
    zh = zh[0]
    for rank in range(STOCK_RANKS):
        assert keys[rank] in zh, 'rank %d: its label key is not in the simplified-Chinese table' % rank
    assert alt in zh and alt not in keys.values(), 'rank 6 alternative key: not a separate key of the simplified-Chinese table'
    compared = [r for r in range(STOCK_RANKS) if r not in RULED_EXCEPTIONS]
    bad = []
    for rank in range(STOCK_RANKS):
        name, want = mine[rank]
        stock = zh[keys[rank]]
        if rank in RULED_EXCEPTIONS:
            assert want != stock, 'rank %d (%s) is a ruled exception but now matches stock; remove it' % (rank, name)
        elif want != stock:
            bad.append('rank %d zh[%s] %s, stock %s' % (rank, name, digest(want), digest(stock)))
    assert not bad, 'grid labels differ from stock simplified Chinese: ' + '; '.join(bad)
    matching = [t for t, p in tables if all(keys[r] in p and p[keys[r]] == mine[r][1] for r in compared)]
    assert matching == [SIMPLIFIED_CHINESE_TAG], '%d of %d language tables match all %d compared labels, want exactly the ' \
        'simplified-Chinese one' % (len(matching), len(tables), len(compared))
    print('PASS grid labels: %d language tables registered; the simplified-Chinese one (by its tag, and the only table '
          'matching all %d compared ranks) gives each of the %d stock ranks the zh[] label the grid shows (keys from word %d '
          'of the launch table entries; ruled exceptions: %s); rank 6 also has a state-dependent stock name (%s), not compared'
          % (len(tables), len(compared), STOCK_RANKS, word, sorted(RULED_EXCEPTIONS) or 'none', digest(zh[alt])))
    for rank in range(STOCK_RANKS):
        print('  rank %d %s %s' % (rank, mine[rank][0], digest(mine[rank][1])))


if __name__ == '__main__':
    main()
