"""Host the production navigation service: run tests/nav_service_test.c against the whole of nav_service.c.

Host only, no device and no stock bytes. nav_service.c is compiled as it is, with the real nav_runtime.c (which
includes nav_map.c), nav_view.c, nav_visual.c, nav_lvgl.c and common-v1/tio_text.c; the test stubs only stock
functions, the other services' hooks and tio_lang. The model uses the tree's base flags (tests/host_layout.py) and the
firmware build's runtime defines, with -Werror and -fsanitize=address,undefined -fno-sanitize-recover=undefined, so an
AddressSanitizer or UBSan report fails the run.

Two host ABI shims, the way native_status_host_test.py adapts its pinned pointer reads. Each production text below
must occur exactly once, so a changed production line fails here instead of being skipped:
  - the timer's user word (a 32-bit target field) is read through host_timer_user();
  - ptr() reads a 32-bit target pointer field with a plain load; on a 64-bit host most of those fields (the menu root
    at TIO_STOCK_MENU_ROOT, the launcher's manager at TIO_STOCK_LAUNCHER_MANAGER) are not 8-byte aligned, which UBSan
    reports, so its body becomes an unaligned copy of the same bytes.

The app names are not typed in the test: this driver reads remote_native.c's app list (the launcher first) and the one
literal in input_allowed (stock Navigation, which tests/remote_app_name_test.py checks against the stock image) and
passes them as defines, so a changed Navigation literal in nav_service.c fails here as well as in that test.

  python3 -I firmware/tests/nav_service_host_test.py [--out DIR]
"""
from pathlib import Path
import argparse, importlib.util, re, subprocess, tempfile
FW = Path(__file__).resolve().parents[1]
NAV = FW/'src'/'navigation-runtime-v1'
REMOTE = FW/'src'/'global-remote-v1'/'remote_native.c'
# Exact production text -> host text.
REPLACEMENTS = {
    '*(Control **)((uint8_t *)timer+TIO_STOCK_TIMER_USER)': '((Control *)host_timer_user(timer))',
    'static void *ptr(void *p,unsigned off){return p?*(void **)((uint8_t *)p+off):NULL;}':
        'static void *ptr(void *p,unsigned off){return host_ptr(p,off);}',
}
CC = ['xcrun', 'clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
      '-fno-sanitize-recover=undefined']
RUNTIME = ['-DTIO_MUSIC_RUNTIME=1', '-DTD_DIAGNOSTICS_RUNTIME=1', '-DTIO_DISPLAY_RUNTIME=1', '-DTDP_FREESTANDING']   # build.py's runtime defines that change these files


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def app_names():
    """remote_native.c: the initializer of the one names[] list, and input_allowed's one literal."""
    text = REMOTE.read_text()
    lists = re.findall(r'static const char \*const names\[\]=\{([^}]*)\};', text)
    assert len(lists) == 1, 'remote_native.c: want one names[] list, found %d' % len(lists)
    entries = re.findall(r'"((?:\\.|[^"\\])*)"', lists[0])
    assert len(entries) >= 6 and re.fullmatch(r'\s*"[^"]*"(\s*,\s*"[^"]*")*\s*', lists[0]), 'remote_native.c: names[] is not a list of literals'
    navigation = load(FW/'tests'/'remote_app_name_test.py', 'nav_service_app_name').one_literal(REMOTE, 'input_allowed').decode()
    assert navigation not in entries, 'the Navigation name must not be in the remote list itself'
    return lists[0].strip(), navigation


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--out', type=Path); args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg12-nav-service-') as tmp:
        out = args.out or Path(tmp); out.mkdir(parents=True, exist_ok=True)
        source = (NAV/'nav_service.c').read_text()
        for old, new in REPLACEMENTS.items():
            assert source.count(old) == 1, 'host ABI shim no longer matches production: ' + old
            source = source.replace(old, new)
        (out/'nav_service_host.inc').write_text(source)
        apps, navigation = app_names()
        layout = load(FW/'tests'/'host_layout.py', 'nav_service_host_layout')
        exe = out/'nav-service-test'
        subprocess.run([*CC, *RUNTIME, *layout.flags(), '-DTN_TEST_APPS=' + apps, '-DTN_TEST_NAVIGATION="%s"' % navigation,
                        '-I', str(out), '-I', str(NAV), '-I', str(FW/'src'), str(FW/'tests/nav_service_test.c'),
                        *[str(NAV/f) for f in ('nav_runtime.c', 'nav_view.c', 'nav_visual.c', 'nav_lvgl.c')],
                        str(FW/'src/common-v1/tio_text.c'), '-o', str(exe)], check=True)
        r = subprocess.run([str(exe)], capture_output=True, text=True)
        print(r.stdout + r.stderr, end='')
        if r.returncode or 'PASS nav_service host' not in r.stdout:
            raise SystemExit('nav_service host test failed')


if __name__ == '__main__':
    main()
