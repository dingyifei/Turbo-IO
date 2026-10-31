"""Execute exact native UI function bodies with host-owned widget/ABI providers.

The production function slices are not rewritten. Full ARM compilation and the
stock-byte ABI audit independently cover the surrounding target layout.
"""
from pathlib import Path
import argparse,subprocess,tempfile
FW=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg4-native-ui-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        focus=(FW/'src/focus-v1/focus_menu_native.c').read_text()
        control=next(line for line in focus.splitlines() if line.startswith('typedef struct {FMView view;'))
        sync=focus[focus.index('void fm_sync(void *app)'):focus.index('\nvoid fm_show(void *app)')]
        live=focus[focus.index('static bool phone_linked(void)'):focus.index('\nvoid fm_relayout(unsigned rows)')]   # TMG8 live tile state: the production gatherers over stubbed services
        (out/'focus_native_sync.inc').write_text('#include "common-v1/menu_wheel.h"\n#include "focus-v1/tile_state.h"\n'+control+'\n'+live+'\n'+sync+'\n')
        menu=(FW/'src/music-runtime-v1/menu10.c').read_text()
        lifecycle=menu[menu.index('void m8_hook_hide(void *app)'):menu.index('\nvoid m8_hook_wheel(void *app')]
        event=menu[menu.index('bool m8_hook_event(void *app,void *event)'):menu.index('\nvoid tio_hook_file(')]
        (out/'menu_lifecycle.inc').write_text(lifecycle+'\n'+event+'\n')
        for name,extra in [('native_ui_test',['src/focus-v1/focus_menu.c','src/common-v1/tio_text.c','src/menu-grid-v2/tile_config.c']),('native_lifecycle_test',[])]:
            exe=out/name
            subprocess.run(['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-I',str(out),'-I',str(FW/'src'),str(FW/'tests'/(name+'.c')),*[str(FW/p) for p in extra],'-o',str(exe)],check=True)
            subprocess.run([str(exe)],check=True)
if __name__=='__main__':main()
