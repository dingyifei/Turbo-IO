"""Runtime size check and tail canary: run tests/menu_tail_test.c against the whole of menu10.c and port_allocate.c.

Host only, no device and no stock bytes. The model is compiled with the tree's base flags (tests/host_layout.py), the
firmware build's runtime defines, and -fsanitize=address,undefined -fno-sanitize-recover=undefined, so an
AddressSanitizer or UBSan report fails the run.

The model's motion count is not typed in the test: this driver reads the carousel count edit from
firmware/build-inputs.json (role "Carousel item count 7 to 13", a historical key), requires its after bytes to be one
Thumb halfword movs r1,#imm, and passes imm as MENU_TAIL_COUNT_EDIT. The test asserts at compile time that it equals
the module's item count, so a tile model and a count edit that disagree fail here instead of leaving the device menu
unarmed.

One host ABI shim, the way native_status_host_test.py adapts its pinned pointer reads: menu10.c's ptr() reads a 32-bit
target pointer field with a plain load, and on a 64-bit host most of those fields (TIO_STOCK_MENU_ROOT at 0x4, the row
and dot arrays at 4-byte strides) are not 8-byte aligned, which UBSan reports. The driver replaces only that body with
an unaligned copy of the same bytes; every other line of menu10.c is compiled as it is.

  python3 -I firmware/tests/menu_tail_host_test.py [--out DIR]
"""
from pathlib import Path
import argparse,importlib.util,json,subprocess,tempfile
FW=Path(__file__).resolve().parents[1]
ROLE='Carousel item count 7 to 13'
PTR='static void *ptr(void *app,unsigned off){return *(void **)((uint8_t *)app+off);}'
HOST_PTR='static void *ptr(void *app,unsigned off){void *v;__builtin_memcpy(&v,(uint8_t *)app+off,sizeof v);return v;}'
CC=['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-sanitize-recover=undefined']
RUNTIME=['-DTIO_MUSIC_RUNTIME=1','-DTD_DIAGNOSTICS_RUNTIME=1','-DTIO_DISPLAY_RUNTIME=1','-DTDP_FREESTANDING']   # build.py's runtime defines that change these files
def host_layout():
    spec=importlib.util.spec_from_file_location('menu_tail_host_layout',FW/'tests'/'host_layout.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def count_edit():
    """The immediate of the carousel count edit: exactly one edit with ROLE, 2 after bytes, movs r1,#imm."""
    edits=[e for e in json.loads((FW/'build-inputs.json').read_text())['edits'] if e['role']==ROLE]
    assert len(edits)==1,'build-inputs.json: want exactly one edit with role %r, found %d'%(ROLE,len(edits))
    after=bytes.fromhex(edits[0]['after'])
    assert len(after)==2,'carousel count edit: after must be one halfword, got %d bytes'%len(after)
    h=after[0]|after[1]<<8
    assert h>>11==0b00100 and (h>>8)&7==1,'carousel count edit: after %s is not movs r1,#imm'%edits[0]['after']
    return h&0xff
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg12-menu-tail-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        menu=(FW/'src/music-runtime-v1/menu10.c').read_text()
        assert menu.count(PTR)==1,'host ABI shim no longer matches production: '+PTR
        (out/'menu10_host.c').write_text('/* host test copy of menu10.c: ptr() reads unaligned on a 64-bit host (menu_tail_host_test.py) */\n#line 1 "menu10.c"\n'+menu.replace(PTR,HOST_PTR))
        imm=count_edit()
        exe=out/'menu-tail-test'
        subprocess.run([*CC,*RUNTIME,*host_layout().flags(),'-DMENU_TAIL_COUNT_EDIT=%d'%imm,
            '-I',str(FW/'src/music-runtime-v1'),'-I',str(FW/'src'),str(FW/'tests/menu_tail_test.c'),str(out/'menu10_host.c'),
            str(FW/'src/port_allocate.c'),'-o',str(exe)],check=True)
        subprocess.run([str(exe)],check=True)
if __name__=='__main__':main()
