"""Host the production dispatcher; adapt only pinned 32-bit pointer accesses."""
from pathlib import Path
import argparse,subprocess,tempfile
FW=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg4-native-status-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        source=(FW/'src/diagnostics-v1/diagnostics_service.c').read_text()
        replacements={
            'return p?*(void **)((uint8_t *)p+off):NULL;':'return host_ptr(p,off);',
            'return ptr(*(void **)(uintptr_t)0x19971594,0x3c);':'return host_manager();',
            '((M8NativeTail *)((uint8_t *)app+TIO_STOCK_MENU_BYTES))->navigation':'host_slot(app)',
            '*(Control **)((uint8_t *)timer+12)':'((Control *)host_timer_user(timer))',
        }
        for old,new in replacements.items():
            assert old in source,'host ABI shim no longer matches production: '+old
            source=source.replace(old,new)
        (out/'diagnostics_service_host.inc').write_text(source)
        exe=out/'native-status-test'
        subprocess.run(['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-DTD_DIAGNOSTICS_RUNTIME=1','-DTIO_MUSIC_RUNTIME=1',
            '-I',str(out),'-I',str(FW/'src/diagnostics-v1'),'-I',str(FW/'src'),str(FW/'tests/native_status_test.c'),
            str(FW/'src/diagnostics-v1/diagnostics.c'),str(FW/'src/diagnostics-v1/command.c'),str(FW/'src/diagnostics-v1/knob_calibration.c'),'-o',str(exe)],check=True)
        subprocess.run([str(exe)],check=True)
if __name__=='__main__':main()
