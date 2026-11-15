"""Execute exact native UI function bodies with host-owned widget/ABI providers.

The production function slices are not rewritten. Full ARM compilation and the
stock-byte ABI audit independently cover the surrounding target layout.

The slices of focus_menu_native.c and menu10.c read stock fields through
stock_layout.h names, so the test models that include them are compiled with
the tree's base flags (tests/host_layout.py). The module tile files
(focus_menu.c, tio_text.c, tile_config.c) are compiled with the same flags, so
the model and the objects share one tile model (14 items on 1.0.6.11) and never
mix 13- and 14-item objects. UBSan reports fail the run
(-fno-sanitize-recover=undefined).

The slices reach the module tail through the test models' own tail() stubs, so
this driver also checks that both production files define tail() as the one
canary-checked accessor of menu9.h, and reach the tail no other way.
"""
from pathlib import Path
import argparse,importlib.util,subprocess,tempfile
FW=Path(__file__).resolve().parents[1]
CC=['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-sanitize-recover=undefined']
TAIL='static M8NativeTail *tail(void *app){return m8_tail(app);}'
MODULE=['src/focus-v1/focus_menu.c','src/common-v1/tio_text.c','src/menu-grid-v2/tile_config.c']
def host_layout():
    spec=importlib.util.spec_from_file_location('native_ui_host_layout',FW/'tests'/'host_layout.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg4-native-ui-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        base=host_layout().flags()
        focus=(FW/'src/focus-v1/focus_menu_native.c').read_text()
        control=next(line for line in focus.splitlines() if line.startswith('typedef struct {FMView view;'))
        sync=focus[focus.index('void fm_sync(void *app)'):focus.index('\nvoid fm_show(void *app)')]
        show=focus[focus.index('void fm_show(void *app)'):focus.index('\nvoid fm_hide(void *app)')]   # the real show path: back to the active timer rate
        live=focus[focus.index('static bool phone_linked(void)'):focus.index('\nvoid fm_relayout(unsigned rows)')]   # TMG8 live tile state: the production gatherers over stubbed services
        legacy=focus[focus.index('static void hide_legacy(void *app)'):focus.index('\nstatic void deleted(')]   # the real stock-row hiding fm_sync calls
        plain=focus[focus.index('static TNNavSlot *slot(void *a)'):focus.index('\n/* Hides stock')]   # the real slot(), detail() and fm_menu_plain(): an unarmed menu is busy, never plain
        assert plain.count('static bool detail(')==1 and plain.count('bool fm_menu_plain(')==1,'focus_menu_native.c: slot(), detail() and fm_menu_plain() must precede hide_legacy'
        (out/'focus_native_sync.inc').write_text('#include "common-v1/menu_wheel.h"\n#include "focus-v1/tile_state.h"\n'+control+'\n'+plain+'\n'+legacy+'\n'+live+'\n'+sync+'\n'+show+'\n')
        menu=(FW/'src/music-runtime-v1/menu10.c').read_text()
        for name,text in (('focus_menu_native.c',focus),('menu10.c',menu)):
            assert text.count(TAIL)==1 and text.count('M8NativeTail *tail(')==1,name+': tail() must be exactly '+TAIL
            assert 'TIO_STOCK_MENU_BYTES' not in text,name+': reaches the tail without the canary check of menu9.h'
        lifecycle=menu[menu.index('void m8_hook_hide(void *app)'):menu.index('\nvoid m8_hook_wheel(void *app')]
        event=menu[menu.index('bool m8_hook_event(void *app,void *event)'):menu.index('\nvoid tio_hook_file(')]
        (out/'menu_lifecycle.inc').write_text(lifecycle+'\n'+event+'\n')
        objects=[]
        for path in MODULE:   # the same base flags as the models: one tile model on both sides of the link
            obj=out/(Path(path).stem+'.o')
            subprocess.run([*CC,*base,'-I',str(out),'-I',str(FW/'src'),'-c',str(FW/path),'-o',str(obj)],check=True)
            objects.append(obj)
        for name,extra in [('native_ui_test',objects),('native_lifecycle_test',[])]:
            exe=out/name
            subprocess.run([*CC,*base,'-I',str(out),'-I',str(FW/'src'),str(FW/'tests'/(name+'.c')),*[str(o) for o in extra],'-o',str(exe)],check=True)
            subprocess.run([str(exe)],check=True)
if __name__=='__main__':main()
