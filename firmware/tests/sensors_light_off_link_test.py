"""ARM link of the module with the Sensors page's Light line compiled out (TIO_SENSORS_LIGHT=0, F5).

build.py has no switch for the flag, and its --compile-only mode returns before ld.lld runs, so a compile-only build
shows only that every source compiles. This test runs build.py's own compile path twice, through build.build(...,
compile_only=True): the same stock ZIP checks, source list, extras and flags. The first run is as it is; the second adds
-DTIO_SENSORS_LIGHT=0 to every clang compile. Each object set is then linked the way build.py's full build links it
(ld.lld -T link.ld --entry=m8_hook_ctor, objects in build.py's order) and must:
  - link, with no undefined symbol (llvm-nm -u, as build.py asserts);
  - pass build.py's checks after the link that need no pin: __module_start is moduleVA, __module_end is moduleVA plus
    the module's length, the module fits below the AP cap and inside the AP partition, and every stock edit's branch
    target and entry trampoline is defined;
  - define td_light_bucket in the default module and not in the light-off one, and reference stock's latest-light
    getter (tio_light_latest) from some default object and from no light-off object, so the flag reached the build.
No pins are checked (compile-only skips them), no ZIP is written, and nothing touches a device.

  python3 -I firmware/tests/sensors_light_off_link_test.py --stock <stock ZIP> --llvm-bin <llvm bin dir> [--out NEW_DIR]
"""
from pathlib import Path
import argparse,hashlib,importlib.util,tempfile
FW=Path(__file__).resolve().parents[1]
FLAG='-DTIO_SENSORS_LIGHT=0'
def load_build():
    spec=importlib.util.spec_from_file_location('light_off_build',FW/'build.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def compile_and_link(build,stock,llvm,out,light_off):
    plain=build.run
    def run(arguments):
        args=[str(a) for a in arguments]
        if light_off and Path(args[0]).name=='clang' and '-c' in args:
            args=[args[0],FLAG,*args[1:]]
        return plain(args)
    build.run=run
    try:
        result=build.build(stock,llvm,out,compile_only=True)
    finally:
        build.run=plain
    spec=build.load_spec()
    objects=[out/(str(i)+'-'+(build.HERE/'src'/row['source']).parent.name+'-'+Path(row['source']).stem+'.o') for i,row in enumerate(spec['sources'])]
    objects+=[out/('extra-'+str(i)+'-'+Path(row['path']).stem+'.o') for i,row in enumerate(spec['extras'])]
    objects.append(out/'animation-asset.o')
    assert all(o.is_file() for o in objects) and len(objects)==result['compiled'],'object set differs from build.py compile-only output'
    elf=out/'module.elf'
    build.run([llvm/'ld.lld','-T',FW/'link.ld','--entry=m8_hook_ctor',*objects,'-o',elf])
    undefined=build.run([llvm/'llvm-nm','-u',elf]).split()
    assert not undefined,'%s: undefined module symbols: %s'%('light off' if light_off else 'default',' '.join(undefined))
    symbols={}
    for line in build.run([llvm/'llvm-nm','--defined-only','--format=posix',elf]).splitlines():
        fields=line.split()
        if len(fields)>=3:symbols[fields[0]]=int(fields[2],16)
    defined=set(symbols)
    getter_users=[o.name for o in objects if 'tio_light_latest' in build.run([llvm/'llvm-nm','-u',o]).split()]
    build.run([llvm/'llvm-objcopy','-O','binary',elf,out/'module.bin'])
    module=(out/'module.bin').read_bytes()
    post_link_checks(build,spec,stock,symbols,module,'light off' if light_off else 'default')
    return defined,getter_users,module
def post_link_checks(build,spec,stock,symbols,module,label):
    """build.py's checks after its link that need no pin: the module starts at moduleVA and ends at its own length,
    it fits in the AP cap and the partition, and every stock edit's branch target (and trampoline) is defined."""
    module_va=int(spec['moduleVA'],16)
    assert symbols.get('__module_start')==module_va,label+': __module_start is not moduleVA'
    assert symbols.get('__module_end',-1)-module_va==len(module),label+': __module_end - __module_start is not the module length'
    base=build.safe_zip(stock,spec['stockZIP'],build.stock_base(spec))[0]['nuttx_ap.bin']
    assert module_va-build.FLASH==len(base)-8,label+': moduleVA is not the stock AP end minus its trailer'
    room=build.module_room(len(base),len(base)+len(module)+(-(len(base)+len(module))%4),module_va,len(module))
    assert room['moduleHeadroom']>0,label+': module does not fit below the AP cap'
    assert room['partitionHeadroom']>0,label+': module overruns the AP partition'
    for e in spec['edits']:
        if e['kind']=='raw':continue
        assert e['target'] in symbols,label+': edit target %s is not defined'%e['target']
        if e['role'].startswith('Entry trampoline '):
            assert 'stock_'+e['role'].removeprefix('Entry trampoline ') in symbols,label+': trampoline for %s is not defined'%e['role']
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--stock',type=Path,required=True);parser.add_argument('--llvm-bin',type=Path,required=True);parser.add_argument('--out',type=Path)
    args=parser.parse_args()
    build=load_build()
    with tempfile.TemporaryDirectory(prefix='tmg12-light-off-') as tmp:
        root=args.out.resolve() if args.out else Path(tmp)/'run'
        assert not root.exists(),'Choose a fresh output directory'
        root.mkdir(parents=True)
        on_defined,on_users,on_module=compile_and_link(build,args.stock.resolve(),args.llvm_bin.resolve(),root/'default',False)
        off_defined,off_users,off_module=compile_and_link(build,args.stock.resolve(),args.llvm_bin.resolve(),root/'light-off',True)
        assert 'td_light_bucket' in on_defined and on_users,'default build: the Light line is not compiled in'
        assert 'td_light_bucket' not in off_defined,'light-off build still defines td_light_bucket'
        assert not off_users,'light-off build still references the latest-light getter: '+' '.join(off_users)
        assert len(off_module)<len(on_module),'light-off module is not smaller than the default one'
        print('PASS light-off ARM link: default module %d bytes sha256 %s, TIO_SENSORS_LIGHT=0 module %d bytes sha256 %s; both link with no undefined symbol, at moduleVA with the right end, inside the AP cap and partition, with every edit target defined; '
              'td_light_bucket and the getter reference only in the default build'%(len(on_module),hashlib.sha256(on_module).hexdigest(),len(off_module),hashlib.sha256(off_module).hexdigest()))
if __name__=='__main__':main()
