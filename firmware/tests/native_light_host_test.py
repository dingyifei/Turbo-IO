"""Host the production native_light.c: the UI heap provider and the light bucket, with stock's getter stubbed.

native_light.c reads the two LVGL memory counters at fixed stock RAM addresses. This driver replaces exactly those two
pointer casts (in their order: in use, then peak) with host words and fails if the production text no longer has
them. The addresses are matched by shape, not written here: rebase_apply.py counts every value token under tests/.
It compiles tests/native_light_test.c twice, with the Light line on (TIO_SENSORS_LIGHT=1, the default) and off (0).

The bucket edges that native_light.c keeps in rodata are checked against stock's own bucket table, read from the stock
AP image on every run (ruling T2). The table is found without a stock address: the light driver's control function is
the one that loads the string S_CTL (the str: locator and load pin that tests/stock_layout_witnesses.json already
holds), and its BL at CALL_AT calls stock's bucket lookup. In that lookup the row count is a movs, the table's runtime
address is a 16-bit literal load, each row's low and high edge are vldr loads and the row stride is an add.w, all at
fixed offsets. The comparison direction is pinned too: each edge is compared with the value by a VCMPE whose operand
order and following condition (skip the row when lo > lux, return it when hi > lux) give lo <= lux < hi, and both
branches go where that reading says. The driver decodes those instructions with stock_layout_test.py's decoder, reads the rows from the
.data copy, requires the edges to chain (each high edge is the next low edge, the first low edge is 0, the last high
edge is FLT_MAX, then a row with no name), and requires native_light.c's edges, TD_LIGHT_BUCKETS and its upper bound
to be those values bit for bit. The C test then runs the compiled td_light_bucket at each stock edge and just below.

  python3 -I firmware/tests/native_light_host_test.py --stock <stock ZIP> [--out DIR]
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, re, struct, subprocess, tempfile, zipfile
FW = Path(__file__).resolve().parents[1]
CAST = re.compile(r'\(const volatile uint32_t \*\)\(uintptr_t\)0x[0-9a-f]{8};')
# The light driver's control function loads this string once; the witness JSON pins the load total.
S_CTL = 'str:sha256=9dda0735e0a99d4f15d547a39586883f175ce81c0a865b0afe04d04f94e80143,len=17#0'
CALL_AT = 0x30        # the control function's BL to the bucket lookup, counted from the string load
# Inside the lookup, counted from its first instruction: (offset, shape, registers, what the field is).
LOOKUP = (
    (0x12, 'movs-imm8', {'rd': 2}, 'rows'),        # the loop's row count
    (0x16, 'ldr-lit', {'rt': 3}, 'table'),         # the address of the literal word that holds the table address
    (0x1a, 'vldr-s', {'sd': 15, 'rn': 3}, 'lo'),   # a row's low edge
    (0x28, 'vldr-s', {'sd': 15, 'rn': 3}, 'hi'),   # a row's high edge
    (0x3c, 'add.w-imm', {'rd': 3, 'rn': 3}, 'stride'),
    (0x26, 'bcc', {}, 'skip'),                     # after comparing the low edge: the condition that skips the row
    (0x34, 'bcc', {}, 'hit'),                      # after comparing the high edge: the condition that returns the row
)
# The comparison direction (T2 pins the edges; this pins which side of each edge a value lands on). Each edge is
# compared with the light value (s0) by VCMPE.F32 s15, s0, and VMRS APSR_nzcv, FPSCR moves the flags, at these
# offsets in the lookup. A row is skipped when lo > lux (HI) and returned when hi > lux (GT), so a row holds
# lo <= lux < hi, which is what native_light.c's td_light_bucket does. The skip goes to the loop's row step and the
# hit to the return, which keeps the row index.
COMPARES = ((0x1e, 'low'), (0x2c, 'high'))
COND_HI, COND_GT = 8, 12
SKIP_TO, HIT_TO = 0x36, 0x44
VCMPE_F32 = (0xffbf, 0xeeb4, 0x0fd0, 0x0ac0)   # (mask, value) of the first halfword, then of the second
VMRS_APSR = (0xeef1, 0xfa10)


def vcmpe_regs(img, a):
    """(Sd, Sm) of a VCMPE.F32 Sd, Sm at a, or None."""
    h1, h2 = img.hw(a), img.hw(a + 2)
    if h1 & VCMPE_F32[0] != VCMPE_F32[1] or h2 & VCMPE_F32[2] != VCMPE_F32[3]:
        return None
    return (h2 >> 12) << 1 | (h1 >> 6) & 1, (h2 & 0xf) << 1 | (h2 >> 5) & 1
FLT_MAX_BITS = 0x7f7fffff
EDGES = re.compile(r'static const float edges\[TD_LIGHT_BUCKETS\]=\{([^}]*)\};')
UPPER = re.compile(r'lux>([0-9.e+]+)f\)return -1;')


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def float_bits(text):
    return struct.unpack('<I', struct.pack('<f', float(text)))[0]


def stock_edges(stock):
    """(low edges as float bits, last high edge bits) of stock's light bucket table, read as the docstring says."""
    layout = load(FW/'tests'/'stock_layout_test.py', 'native_light_stock_layout')
    rebase = load(FW/'tools'/'rebase_apply.py', 'native_light_rebase_apply')
    spec = json.loads((FW/'build-inputs.json').read_text())
    with zipfile.ZipFile(stock) as z:
        raw = z.read('nuttx_ap.bin')
    if hashlib.sha256(raw).hexdigest() != spec['stockAP']:
        raise SystemExit('FAIL native light: the stock AP is not build-inputs.json stockAP')
    img = layout.Image(raw)
    world = layout.World(img, layout.read_link(), spec['edits'], layout.active_table(spec),
                         json.loads((FW/'tests'/'stock_layout_witnesses.json').read_text())['loads'])
    try:
        world.check_load(S_CTL, set())
        fn = world.resolve('call:%s@0x%x' % (S_CTL, CALL_AT))
    except layout.Fail as e:
        raise SystemExit('FAIL native light: stock bucket lookup not found: %s' % e)
    got = {}
    for off, shape, regs, what in LOOKUP:
        d = layout.decode(img, fn + off, shape)
        if d is None or d.regs != regs:
            raise SystemExit('FAIL native light: the bucket lookup has no %s %s at +0x%x' % (shape, regs, off))
        got[what] = d.field
    if (got['lo'], got['hi'], got['stride']) != (4, 8, 12):
        raise SystemExit('FAIL native light: bucket row layout (low, high, stride) is %s' % ((got['lo'], got['hi'], got['stride']),))
    for off, what in COMPARES:
        if vcmpe_regs(img, fn + off) != (15, 0) or (img.hw(fn + off + 4), img.hw(fn + off + 6)) != VMRS_APSR:
            raise SystemExit('FAIL native light: the bucket lookup does not compare the %s edge (s15) with the value (s0) '
                             'and move the flags at +0x%x' % (what, off))
    if (got['skip'], got['hit']) != (COND_HI, COND_GT):
        raise SystemExit('FAIL native light: the bucket lookup\'s conditions are %s, not lo <= lux < hi (HI, GT)' % ((got['skip'], got['hit']),))
    at = {what: off for off, shape, regs, what in LOOKUP}
    for what, to in (('skip', SKIP_TO), ('hit', HIT_TO)):
        if layout.classify(img.hw(fn + at[what]), None, fn + at[what]) != ('cbranch', fn + to):
            raise SystemExit('FAIL native light: the bucket lookup\'s %s branch at +0x%x does not go to +0x%x' % (what, at[what], to))
    src, end, dst, _ = rebase.data_copy(raw)
    table = img.word(got['table'])
    rows = []
    for k in range(got['rows'] + 1):
        try:
            o = rebase.data_offset(raw, table + got['stride'] * k)
        except AssertionError as e:
            raise SystemExit('FAIL native light: bucket table row %d: %s' % (k, e))
        rows.append(struct.unpack_from('<III', raw, o))
    body, after = rows[:-1], rows[-1]
    if not all(dst <= r[0] < dst + (end - src) for r in body) or after[0] != 0:
        raise SystemExit('FAIL native light: the bucket table is not %d named rows followed by a row with no name' % len(body))
    lo = [r[got['lo'] // 4] for r in body]
    hi = [r[got['hi'] // 4] for r in body]
    if lo[0] != 0 or hi[-1] != FLT_MAX_BITS or hi[:-1] != lo[1:]:
        raise SystemExit('FAIL native light: stock bucket edges do not chain from 0 to FLT_MAX')
    return lo, hi[-1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stock', type=Path, required=True)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg12-native-light-') as tmp:
        out = args.out or Path(tmp)
        out.mkdir(parents=True, exist_ok=True)
        source = (FW/'src/diagnostics-v1/native_light.c').read_text()
        assert 'not ported to 1.0.6.11 yet' not in source, 'native_light.c still carries a 1.0.6.11 guard'
        # Ruling T2: the module's edges are stock's, bit for bit.
        lo, top = stock_edges(args.stock)
        count = re.findall(r'^#define TD_LIGHT_BUCKETS (\d+)$', (FW/'src/diagnostics-v1/native_light.h').read_text(), re.M)
        if count != [str(len(lo))]:
            raise SystemExit('FAIL native light: TD_LIGHT_BUCKETS is %s, stock has %d rows' % (count, len(lo)))
        mine = EDGES.findall(source)
        if len(mine) != 1:
            raise SystemExit('FAIL native light: native_light.c should define its edges once, found %d' % len(mine))
        mine = [float_bits(t.strip().rstrip('f')) for t in mine[0].split(',')]
        if mine != lo:
            raise SystemExit('FAIL native light: native_light.c edges %s are not stock\'s %s' % (
                [hex(x) for x in mine], [hex(x) for x in lo]))
        upper = UPPER.findall(source)
        if len(upper) != 1 or float_bits(upper[0]) != top:
            raise SystemExit('FAIL native light: native_light.c\'s upper bound is not stock\'s last edge')
        (out/'native_light_stock_edges.inc').write_text(
            '/* Written by native_light_host_test.py from the stock AP image: the low edge of each bucket row. */\n'
            'static const uint32_t stock_edge_bits[%d]={%s};\n' % (len(lo), ','.join('0x%08xu' % x for x in lo)))
        casts = CAST.findall(source)
        assert len(casts) == 2, 'native_light.c should cast exactly two stock RAM words, found %d' % len(casts)
        names = iter(('host_lv_used;', 'host_lv_peak;'))
        source = CAST.sub(lambda m: '(const volatile uint32_t *)&' + next(names), source)
        (out/'native_light_host.inc').write_text(source)
        flags = load(FW/'tests'/'host_layout.py', 'native_light_host_layout').flags()
        for light in ('1', '0'):
            exe = out/('native-light-test-%s' % light)
            subprocess.run(['xcrun', 'clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror',
                            '-fsanitize=address,undefined', '-fno-sanitize-recover=undefined',
                            '-DTIO_SENSORS_LIGHT=' + light, *flags,
                            '-I', str(out), '-I', str(FW/'src/diagnostics-v1'), '-I', str(FW/'src'),
                            str(FW/'tests/native_light_test.c'), str(FW/'src/diagnostics-v1/diagnostics.c'),
                            '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)
        print('PASS native light edges: %d stock bucket rows read from the AP image through the light control '
              'function, chained from 0 to FLT_MAX, equal to native_light.c bit for bit' % len(lo))


if __name__ == '__main__':
    main()
