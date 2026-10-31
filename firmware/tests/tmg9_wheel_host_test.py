"""TMG9 knob: run the REAL m8_hook_wheel body (sliced from menu10.c, not rewritten) and the real tio_menu_wheel_step against a stock model
faithful to the disassembly. The driver also proves the harness is not vacuous: the TMG8 body (writes the scroll position 0xb0, never the
selected index 0x88) and a body that still hands stock a doubled delta must both FAIL the same checks, and it checks the source for the
scaled-delta path directly."""
from pathlib import Path
import argparse,subprocess,tempfile
FW=Path(__file__).resolve().parents[1]
OLD='''  if(target>=0){*word(app,0x88)=(uint32_t)target;*word(app,0x90)=UINT32_MAX;native_snap(app);return;}'''
TMG8='''  if(target>=0){
    *(float *)((uint8_t *)app+TIO_MENU_SCROLL_POSITION_OFFSET)=(float)target;native_snap(app);
    m8_hook_label_index(app,target);(void)m8_hook_frame(app,tio_frame_start(target));return;
  }'''
FALLBACK='  if(target==FM_STEP_NO_CONTROL)stock_wheel(app,delta);'
SCALED='  stock_wheel(app,delta*2);'   # the TMG8 path: stock still gets a doubled delta for item movement
def build(out,name,body):
    (out/'wheel_hook.inc').write_text(body)
    exe=out/name
    subprocess.run(['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-Wno-unused-function','-DTIO_MENU_SCROLL_POSITION_OFFSET=0xb0u','-fsanitize=address,undefined','-I',str(out),'-I',str(FW/'src'),
        str(FW/'tests/tmg9_wheel_hook_test.c'),*[str(FW/p) for p in ('src/focus-v1/focus_menu.c','src/common-v1/tio_text.c','src/menu-grid-v2/tile_config.c')],'-o',str(exe)],check=True)
    return subprocess.run([str(exe)],capture_output=True,text=True)
def code(text):
    """Source without comments and strings, so the checks look at code only."""
    import re
    return re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"',' ',text,flags=re.S)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg9-wheel-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        menu=(FW/'src/music-runtime-v1/menu10.c').read_text()
        body=menu[menu.index('void m8_hook_wheel(void *app,int delta){'):menu.index('\nbool m8_hook_event(void *app,void *event)')].replace('m8_hook_wheel','wheel_hook')
        assert body.count('*word(app,0x88)=(uint32_t)target;*word(app,0x90)=UINT32_MAX;native_snap(app);return;')==1,'m8_hook_wheel must use the 0x88 + native_snap path'
        assert 'TIO_MENU_SCROLL_POSITION_OFFSET' not in body and 'm8_hook_label_index' not in body,'m8_hook_wheel must not write 0xb0 or call the label/frame hooks itself'
        # No 2x / scaled delta path anywhere: the helper is gone, the hook hands stock nothing but the unscaled delta, and only when there is no controller.
        wheel_h=code((FW/'src/common-v1/menu_wheel.h').read_text());hook=code(body)
        assert 'tio_menu_wheel_scaled' not in wheel_h and 'tio_menu_wheel_scaled' not in code(menu) and 'tio_menu_wheel_wrap' not in code(menu),'the scaled delta path must be gone'
        assert hook.count('stock_wheel(')==1 and FALLBACK in body,'stock_wheel may only see the unscaled delta, and only without a controller'
        assert 'fm_wheel_step(' in hook and 'delta*2' not in hook.replace(' ','') and '*2' not in hook.replace(' ',''),'no scaling of the delta in m8_hook_wheel'
        assert 'int64_t d=delta*2' not in wheel_h.replace(' ','') and 'delta*2' not in wheel_h.replace(' ',''),'no scaling of the delta in menu_wheel.h'
        native=code((FW/'src/focus-v1/focus_menu_native.c').read_text())
        assert 'tio_menu_wheel_step(&c->step,index,count,delta,now,tio_knob_detent())' in native.replace('\n',''),'fm_wheel_step must pass the live D'
        real=build(out,'wheel_hook_test',body+'\n')
        print(real.stdout+real.stderr,end='')
        assert real.returncode==0,'the real m8_hook_wheel body failed the stock model'
        # The harness must catch the old bodies: otherwise it proves nothing.
        assert OLD in body
        old=build(out,'wheel_hook_tmg8_test',body.replace(OLD,TMG8)+'\n')
        assert old.returncode!=0 and 'FAIL' in old.stderr,'the TMG8 body (0xb0 write) must fail the stock-model checks'
        scaled=build(out,'wheel_hook_scaled_test',body.replace(FALLBACK,SCALED)+'\n')
        assert scaled.returncode!=0 and 'FAIL' in scaled.stderr,'a body that still hands stock a doubled delta must fail the stock-model checks'
        print('PASS tmg9 wheel host: the TMG8 body fails this harness (%d lines of failures), a doubled-delta body fails it (%d), the real body passes'%(old.stderr.count('FAIL line'),scaled.stderr.count('FAIL line')))
if __name__=='__main__':main()
