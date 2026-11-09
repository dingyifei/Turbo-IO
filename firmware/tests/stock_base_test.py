"""The stock base is selectable and never mixed: build.py derives every version label from stockBase, refuses a
stock set whose AP, APC1 and BTH come from different builds, and refuses a tree whose addresses are on another base."""
from pathlib import Path
import importlib.util,json,shutil,tempfile,zipfile
FW=Path(__file__).resolve().parents[1]
ROOT=FW.parent
STOCK={'1.0.5.5':ROOT/'firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip',
       '1.0.5.12':ROOT/'firmware-research/strix-1.0.5.12/stock/Strix-OS-1.0.5.12-original.zip'}
def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def refused(call,why):
    try:call()
    except (AssertionError,SystemExit):return
    raise SystemExit('accepted: '+why)
def main():
    build=load(FW/'build.py','stock_base_build');rebase=load(FW/'tools/rebase_apply.py','stock_base_rebase')
    table=rebase.load_table()
    assert build.STOCK_BASES==(table['from'],table['to'])
    spec=json.loads((FW/'build-inputs.json').read_text());base=build.stock_base(spec)
    assert build.stock_versions('1.0.5.12')=={'SW_VER':'Strix OS 1.0.5','BUILD_VER':'12'}
    assert build.stock_versions('1.0.5.5')=={'SW_VER':'Strix OS 1.0.5','BUILD_VER':'5'}
    for b in build.STOCK_BASES:
        flags=build.stock_defines(b)
        assert flags.count('-DTD_STOCK_%s=1'%b.replace('.',''))==1 and sum(f.endswith('=1') for f in flags)==1
    refused(lambda:build.stock_base({'stockBase':'1.0.5.6'}),'unknown stock base')
    refused(lambda:build.stock_base({}),'missing stock base')
    files={}
    for b,path in STOCK.items():
        with zipfile.ZipFile(path) as z:files[b]={n:z.read(n) for n in z.namelist()}
        cores=build.core_identity(files[b],b)
        assert cores['buildVer']==b.rsplit('.',1)[1]
        # The pinned members of each base are exactly that stock ZIP's members.
        build.check_stock_members(files[b],{'stockMembers':table['bases'][b]['stockMembers']})
    assert build.core_identity(files['1.0.5.12'],'1.0.5.12')['revInfo']!=build.core_identity(files['1.0.5.5'],'1.0.5.5')['revInfo']
    new,old=files['1.0.5.12'],files['1.0.5.5']
    for core in ('nuttx_ap.bin','nuttx_apc1.bin','nuttx_bth.bin'):
        refused(lambda:build.core_identity({**new,core:old[core]},'1.0.5.12'),'1.0.5.12 set with a 1.0.5.5 '+core)
        refused(lambda:build.core_identity({**old,core:new[core]},'1.0.5.5'),'1.0.5.5 set with a 1.0.5.12 '+core)
    refused(lambda:build.core_identity(old,'1.0.5.12'),'1.0.5.5 stock read as 1.0.5.12')
    # A REV_INFO from another build with the right version strings is still a mix.
    forged=new['nuttx_bth.bin'].replace(b'REV_INFO=55bc20b0-dirty:',b'REV_INFO=55bc20b1-dirty:')
    assert forged!=new['nuttx_bth.bin']
    refused(lambda:build.core_identity({**new,'nuttx_bth.bin':forged},'1.0.5.12'),'BTH from another REV_INFO')
    refused(lambda:build.check_stock_members({**new,'nuttx_bth.bin':forged},spec),'unpinned member')
    # The tree is wholly on its base, and a single stale address makes it neither.
    assert rebase.tree_state(FW)==base
    with tempfile.TemporaryDirectory(prefix='stock-base-') as tmp:
        tree=Path(tmp)/'firmware';shutil.copytree(FW,tree,ignore=shutil.ignore_patterns('build','__pycache__'))
        col=rebase.column(table,base);v=next(x for x in table['values'] if x['name']=='launcher_global')
        path=tree/sorted(v['sites'])[0];path.write_text(path.read_text().replace(v[col],v[rebase.other(col)],1))
        refused(lambda:rebase.tree_state(tree,table),'mixed tree')
        assert any('stale' in p for p in rebase.problems(tree,table,base))
        path.write_text(path.read_text().replace(v[rebase.other(col)],v[col],1));assert rebase.tree_state(tree,table)==base
        # A stock address the table does not know (here 1.0.5.5 lv_timer_create, as the native_page.c comment had it
        # before tmg10(6), and an arbitrary flash word) also makes the tree on neither base.
        for unknown in ['0x'+t for t in ('105f6170','10600000','184d0000')]:   # split so this file holds no stock-window token
            extra=tree/'src/common-v1/unknown_address_probe.h';extra.write_text('/* stock address %s */\n'%unknown)
            refused(lambda:rebase.tree_state(tree,table),'unknown stock-window token '+unknown)
            assert any(unknown in p for p in rebase.problems(tree,table,base)),unknown
            extra.unlink()
        assert rebase.tree_state(tree,table)==base
    print('PASS stock base: labels and defines from stockBase, mixed cores refused (AP/APC1/BTH, REV_INFO), members pinned, stale and unknown stock-window addresses refused, tree wholly on %s'%base)
if __name__=='__main__':main()
