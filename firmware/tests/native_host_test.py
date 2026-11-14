"""Run native controller bodies with only the 32-bit timer ABI adapted for host.

No algorithms, storage policies, or application count/selection accesses change.
The model is compiled with the tree's base flags (tests/host_layout.py), so remote_native.c, tile_config.c and the test
see the same stock layout names and the same tile model as the ARM build. Any UBSan report fails the run.
The real ARM translation units and pinned stock-byte ABI remain separate gates.
"""
from pathlib import Path
import argparse,importlib.util,subprocess,tempfile
FW=Path(__file__).resolve().parents[1]
def host_layout():
    spec=importlib.util.spec_from_file_location('native_host_layout',FW/'tests'/'host_layout.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
# Exact production text -> host text. Each key must be present, so a changed production line fails here.
REPLACEMENTS={
    '*(void(**)(void*))((uint8_t*)t+TIO_STOCK_TIMER_CB)':'host_timer_callback(t)',
    '*(Control**)((uint8_t*)t+TIO_STOCK_TIMER_USER)':'((Control *)host_timer_user(t))',
    '_Static_assert(sizeof event==28&&offsetof(struct key_event,code)==TIO_STOCK_EVENT_CODE&&offsetof(struct key_event,parameter)==TIO_STOCK_EVENT_PARAM,"32-bit pinned event ABI");':
        '/* Target-only event ABI assertion covered by real ARM compile. */',
}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg4-native-host-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        source=(FW/'src/global-remote-v1/remote_native.c').read_text()
        for old,new in REPLACEMENTS.items():
            assert old in source, 'host ABI shim no longer matches production: '+old
            source=source.replace(old,new)
        (out/'remote_native_host.inc').write_text(source)
        exe=out/'native-remote-test'
        subprocess.run(['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',
            '-fno-sanitize-recover=undefined',*host_layout().flags(),
            '-I',str(out),'-I',str(FW/'src/global-remote-v1'),'-I',str(FW/'src'),
            str(FW/'tests/native_remote_test.c'),str(FW/'src/global-remote-v1/remote.c'),str(FW/'src/global-remote-v1/lang_flag.c'),str(FW/'src/global-remote-v1/lang_store.c'),str(FW/'src/menu-grid-v2/tile_config.c'),str(FW/'src/diagnostics-v1/knob_calibration.c'),str(FW/'src/diagnostics-v1/diagnostics.c'),'-o',str(exe)],check=True)
        subprocess.run([str(exe)],check=True)
if __name__=='__main__':main()
