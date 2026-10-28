"""Run native controller bodies with only the 32-bit timer ABI adapted for host.

No algorithms, storage policies, or application count/selection accesses change.
The real ARM translation units and pinned stock-byte ABI remain separate gates.
"""
from pathlib import Path
import argparse,subprocess,tempfile
FW=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg4-native-host-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        source=(FW/'src/global-remote-v1/remote_native.c').read_text()
        replacements={
            '*(void(**)(void*))((uint8_t*)t+8)':'host_timer_callback(t)',
            '*(Control**)((uint8_t*)t+12)':'((Control *)host_timer_user(t))',
            '_Static_assert(sizeof event==28,"32-bit pinned event ABI");':'/* Target-only event ABI assertion covered by real ARM compile. */',
        }
        for old,new in replacements.items():
            assert old in source, 'host ABI shim no longer matches production: '+old
            source=source.replace(old,new)
        (out/'remote_native_host.inc').write_text(source)
        exe=out/'native-remote-test'
        subprocess.run(['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined',
            '-I',str(out),'-I',str(FW/'src/global-remote-v1'),'-I',str(FW/'src'),
            str(FW/'tests/native_remote_test.c'),str(FW/'src/global-remote-v1/remote.c'),str(FW/'src/global-remote-v1/lang_flag.c'),str(FW/'src/menu-grid-v2/tile_config.c'),'-o',str(exe)],check=True)
        subprocess.run([str(exe)],check=True)
if __name__=='__main__':main()
