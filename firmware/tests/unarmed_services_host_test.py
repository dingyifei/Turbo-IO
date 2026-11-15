"""Unarmed-menu path of the app, camera, focus and music services: run tests/unarmed_services_test.c against the whole
of app_service.c, camera_native.c, focus_service.c and music_service.c.

Host only, no device and no stock bytes. The services are compiled with the tree's base flags (tests/host_layout.py),
the firmware build's runtime defines, and -fsanitize=address,undefined -fno-sanitize-recover=undefined, so an
AddressSanitizer or UBSan report fails the run. Their protocol units (app_command.c, camera.c, focus.c, music.c,
tio_text.c) are linked as they are; the stock natives, LVGL, the app store and runner, and the focus view are stubs in
the test.

Host ABI shims, the way native_host_test.py and native_status_host_test.py adapt pinned pointer reads. On the 32-bit
target a stock timer keeps its callback at TIO_STOCK_TIMER_CB and its user word at TIO_STOCK_TIMER_USER, four bytes
apart; a 64-bit host pointer does not fit there, so those reads become calls to the test's host_timer_cb and
host_timer_user. Each service's ptr() reads a 32-bit target pointer field with a plain load, which is not 8-byte aligned
on a 64-bit host for most fields; its body becomes an unaligned copy of the same bytes. Every replaced text must be
present, so a changed production line fails here. Every other line of the four files is compiled as it is. The tail is
reached only through menu9.h's m8_tail and m8_tail_busy, which this driver checks too.

  python3 -I firmware/tests/unarmed_services_host_test.py [--out DIR]
"""
from pathlib import Path
import argparse,importlib.util,subprocess,sys,tempfile
FW=Path(__file__).resolve().parents[1]
CC=['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-sanitize-recover=undefined']
RUNTIME=['-DTIO_MUSIC_RUNTIME=1','-DTD_DIAGNOSTICS_RUNTIME=1','-DTIO_DISPLAY_RUNTIME=1','-DTDP_FREESTANDING']   # build.py's runtime defines that change these files
PTR_O='static void *ptr(void *p,unsigned o){return p?*(void **)((uint8_t *)p+o):NULL;}'
PTR_OFF='static void *ptr(void *p,unsigned off){return p?*(void **)((uint8_t *)p+off):NULL;}'
HOST_PTR='static void *ptr(void *p,unsigned off){void *v=NULL;if(p)__builtin_memcpy(&v,(uint8_t *)p+off,sizeof v);return v;}'
TIMER_CB='*(void (**)(void *))((uint8_t *)t+TIO_STOCK_TIMER_CB)'
TIMER_USER='ptr(t,TIO_STOCK_TIMER_USER)'
# file -> [(production text, host text, how many times it must occur)]
SERVICES={
    'app-runtime-v1/app_service.c':[(TIMER_CB,'host_timer_cb(t)',1),(TIMER_USER,'host_timer_user(t)',2),(PTR_O,HOST_PTR,1)],
    'focus-v1/focus_service.c':[(TIMER_CB,'host_timer_cb(t)',1),(TIMER_USER,'host_timer_user(t)',2),(PTR_O,HOST_PTR,1)],
    'camera-v1/camera_native.c':[(TIMER_USER,'host_timer_user(t)',1),(PTR_OFF,HOST_PTR,1)],
    'music-runtime-v1/music_service.c':[('*(Control **)((uint8_t *)timer+TIO_STOCK_TIMER_USER)','((Control *)host_timer_user(timer))',1),(PTR_OFF,HOST_PTR,1)],
}
UNITS=['app-runtime-v1/app_command.c','camera-v1/camera.c','focus-v1/focus.c','music-runtime-v1/music.c','common-v1/tio_text.c']
PREFIX='void *host_timer_user(void *);void (*host_timer_cb(void *))(void *);   /* unarmed_services_host_test.py */\n'
def host_layout():
    spec=importlib.util.spec_from_file_location('unarmed_services_host_layout',FW/'tests'/'host_layout.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--out',type=Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg12-unarmed-services-') as tmp:
        out=args.out or Path(tmp);out.mkdir(parents=True,exist_ok=True)
        flags=[*CC,*RUNTIME,*host_layout().flags(),'-I',str(FW/'src')]
        sources=[]
        for rel,shims in SERVICES.items():
            text=(FW/'src'/rel).read_text()
            assert 'TIO_STOCK_MENU_BYTES' not in text and 'm8_tail_at(' not in text,rel+': reaches the menu tail without the canary check of menu9.h'
            assert 'm8_tail(' in text,rel+': no longer reads the tail through m8_tail'
            for old,new,count in shims:
                assert text.count(old)==count,'%s: host ABI shim no longer matches production (want %d of %s, found %d)'%(rel,count,old,text.count(old))
                text=text.replace(old,new)
            name=Path(rel).name
            copy=out/(Path(rel).stem+'_host.c')
            copy.write_text(PREFIX+'#line 1 "%s"\n'%name+text)
            sources.append((copy,FW/'src'/Path(rel).parent))
        objects=[]
        for copy,folder in sources:   # each copy keeps its own folder for its relative includes
            obj=out/(copy.stem+'.o');subprocess.run([*flags,'-I',str(folder),'-c',str(copy),'-o',str(obj)],check=True);objects.append(obj)
        for rel in UNITS:
            obj=out/(Path(rel).stem+'.o');subprocess.run([*flags,'-c',str(FW/'src'/rel),'-o',str(obj)],check=True);objects.append(obj)
        exe=out/'unarmed-services-test'
        subprocess.run([*flags,str(FW/'tests/unarmed_services_test.c'),*[str(o) for o in objects],'-o',str(exe)],check=True)
        r=subprocess.run([str(exe)],capture_output=True,text=True);print(r.stdout,end='');sys.stderr.write(r.stderr)
        if r.returncode or 'PASS unarmed services' not in r.stdout:sys.exit('unarmed services host test failed')
if __name__=='__main__':main()
