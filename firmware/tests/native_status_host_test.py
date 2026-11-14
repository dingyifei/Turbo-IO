"""Host the production dispatcher; adapt only pinned 32-bit pointer accesses.

diagnostics_service.c reads the launcher, view manager and timer through stock_layout.h names, so it is compiled with
the tree's base flags (tests/host_layout.py). It reaches the menu tail only through menu9.h's m8_tail, which the test
uses unchanged on an aligned menu buffer, so no tail access is rewritten here. UBSan reports fail the run.
"""
from pathlib import Path
import argparse,importlib.util,subprocess,tempfile
FW=Path(__file__).resolve().parents[1]
def host_layout():
    spec=importlib.util.spec_from_file_location('native_status_host_layout',FW/'tests'/'host_layout.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg4-native-status-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        source=(FW/'src/diagnostics-v1/diagnostics_service.c').read_text()
        assert 'TIO_STOCK_MENU_BYTES' not in source,'diagnostics_service.c reaches the menu tail without m8_tail'
        replacements={
            'return p?*(void **)((uint8_t *)p+off):NULL;':'return host_ptr(p,off);',
            'tio_launcher_global':'host_launcher()',
            '*(Control **)((uint8_t *)timer+TIO_STOCK_TIMER_USER)':'((Control *)host_timer_user(timer))',
        }
        for old,new in replacements.items():
            assert old in source,'host ABI shim no longer matches production: '+old
            source=source.replace(old,new)
        (out/'diagnostics_service_host.inc').write_text(source)
        exe=out/'native-status-test'
        subprocess.run(['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-sanitize-recover=undefined','-DTD_DIAGNOSTICS_RUNTIME=1','-DTIO_MUSIC_RUNTIME=1',
            *host_layout().flags(),
            '-I',str(out),'-I',str(FW/'src/diagnostics-v1'),'-I',str(FW/'src'),str(FW/'tests/native_status_test.c'),
            str(FW/'src/diagnostics-v1/diagnostics.c'),str(FW/'src/diagnostics-v1/command.c'),str(FW/'src/diagnostics-v1/knob_calibration.c'),'-o',str(exe)],check=True)
        subprocess.run([str(exe)],check=True)
if __name__=='__main__':main()
