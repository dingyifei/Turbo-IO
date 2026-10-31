"""TMG9 bug 1: run the REAL m8_hook_wheel body (sliced from menu10.c, not rewritten) against a stock model faithful to the
disassembly. The driver also proves the harness is not vacuous: the TMG8 body (writes the scroll position 0xb0, never the
selected index 0x88) must FAIL the same checks."""
from pathlib import Path
import argparse,subprocess,tempfile
FW=Path(__file__).resolve().parents[1]
OLD='''  if(target>=0&&eligible(app)){
    /* Same path as remote_native.c: stock native_snap re-seats the carousel from the selected index (app+0x88), so that is
     * what must change, and 0x90 (the shown frame) is invalidated so the snap reruns the frame and label hooks itself. */
    *word(app,0x88)=(uint32_t)target;*word(app,0x90)=UINT32_MAX;native_snap(app);return;
  }'''
TMG8='''  if(target>=0){
    *(float *)((uint8_t *)app+TIO_MENU_SCROLL_POSITION_OFFSET)=(float)target;native_snap(app);
    m8_hook_label_index(app,target);(void)m8_hook_frame(app,tio_frame_start(target));return;
  }'''
def build(out,name,body):
    (out/'wheel_hook.inc').write_text(body)
    exe=out/name
    subprocess.run(['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-Wno-unused-function','-DTIO_MENU_SCROLL_POSITION_OFFSET=0xb0u','-fsanitize=address,undefined','-I',str(out),'-I',str(FW/'src'),
        str(FW/'tests/tmg9_wheel_hook_test.c'),*[str(FW/p) for p in ('src/focus-v1/focus_menu.c','src/common-v1/tio_text.c','src/menu-grid-v2/tile_config.c')],'-o',str(exe)],check=True)
    return subprocess.run([str(exe)],capture_output=True,text=True)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg9-wheel-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        menu=(FW/'src/music-runtime-v1/menu10.c').read_text()
        body=menu[menu.index('void m8_hook_wheel(void *app,int delta){'):menu.index('\nbool m8_hook_event(void *app,void *event)')].replace('m8_hook_wheel','wheel_hook')
        assert body.count('*word(app,0x88)=(uint32_t)target;*word(app,0x90)=UINT32_MAX;native_snap(app);return;')==1,'m8_hook_wheel must use the 0x88 + native_snap path'
        assert 'TIO_MENU_SCROLL_POSITION_OFFSET' not in body and 'm8_hook_label_index' not in body,'m8_hook_wheel must not write 0xb0 or call the label/frame hooks itself'
        assert 'tio_menu_wheel_scaled' not in body or body.count('stock_wheel(app,tio_menu_wheel_scaled(delta))')==1
        real=build(out,'wheel_hook_test',body+'\n')
        print(real.stdout+real.stderr,end='')
        assert real.returncode==0,'the real m8_hook_wheel body failed the stock model'
        # The harness must catch the TMG8 body: otherwise it proves nothing.
        assert OLD in body
        old=build(out,'wheel_hook_tmg8_test',body.replace(OLD,TMG8)+'\n')
        assert old.returncode!=0 and 'FAIL' in old.stderr,'the TMG8 body (0xb0 write) must fail the stock-model checks'
        print('PASS tmg9 wheel host: the TMG8 body fails this harness (%d lines of failures), the real body passes'%old.stderr.count('FAIL line'))
if __name__=='__main__':main()
