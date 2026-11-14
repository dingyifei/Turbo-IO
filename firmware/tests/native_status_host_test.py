"""Host the production dispatcher; adapt only pinned 32-bit pointer accesses.

diagnostics_service.c reads the launcher, view manager, timer and menu tail through stock_layout.h names, so it is
compiled with the tree's base flags (tests/host_layout.py). Its 1.0.6.11 guard names F4 behaviour, not layout, so this
driver checks that the first three lines are exactly that guard and replaces them with a comment.
"""
from pathlib import Path
import argparse,importlib.util,subprocess,tempfile
FW=Path(__file__).resolve().parents[1]
GUARD=['#if defined(TD_STOCK_10611) && TD_STOCK_10611','#error not ported to 1.0.6.11 yet: message hook and statfs layout (F4)','#endif']
def host_layout():
    spec=importlib.util.spec_from_file_location('native_status_host_layout',FW/'tests'/'host_layout.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def strip_guard(source):
    lines=source.split('\n')
    assert lines[:3]==GUARD,'diagnostics_service.c no longer starts with its exact 1.0.6.11 guard'
    return '\n'.join(['/* host test: the 1.0.6.11 guard (F4 behaviour, not layout) is stripped here */']+lines[3:])
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg4-native-status-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        source=strip_guard((FW/'src/diagnostics-v1/diagnostics_service.c').read_text())
        replacements={
            'return p?*(void **)((uint8_t *)p+off):NULL;':'return host_ptr(p,off);',
            '*(void **)(uintptr_t)0x199595d4':'host_launcher()',
            '((M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES))->navigation':'host_slot(app)',
            '*(Control **)((uint8_t *)timer+TIO_STOCK_TIMER_USER)':'((Control *)host_timer_user(timer))',
        }
        for old,new in replacements.items():
            assert old in source,'host ABI shim no longer matches production: '+old
            source=source.replace(old,new)
        (out/'diagnostics_service_host.inc').write_text(source)
        exe=out/'native-status-test'
        subprocess.run(['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-DTD_DIAGNOSTICS_RUNTIME=1','-DTIO_MUSIC_RUNTIME=1',
            *host_layout().flags(),
            '-I',str(out),'-I',str(FW/'src/diagnostics-v1'),'-I',str(FW/'src'),str(FW/'tests/native_status_test.c'),
            str(FW/'src/diagnostics-v1/diagnostics.c'),str(FW/'src/diagnostics-v1/command.c'),str(FW/'src/diagnostics-v1/knob_calibration.c'),'-o',str(exe)],check=True)
        subprocess.run([str(exe)],check=True)
if __name__=='__main__':main()
