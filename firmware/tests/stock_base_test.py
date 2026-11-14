"""The stock base is selectable and never mixed: build.py derives every version label from stockBase, refuses a
stock set whose AP, APC1 and BTH come from different builds, refuses a stock ZIP whose package shape is not its
base's, and refuses a tree whose addresses are on another base. The three stock ZIPs are read for real: 1.0.5.5 and
1.0.5.12 from the repository, 1.0.6.11 (the canonical members ZIP) from $TURBO_INPUTS, which must be exported.
It also covers stock_zip.py's refusals and a format-2 rebase round trip, both in temp dirs only."""
from pathlib import Path
import contextlib,copy,hashlib,importlib.util,io,json,os,shutil,struct,tempfile,zipfile
FW=Path(__file__).resolve().parents[1]
ROOT=FW.parent
BASES=('1.0.5.5','1.0.5.12','1.0.6.11')
# The repository stock ZIPs, written here on their own; build.stock_zip_path must agree. 1.0.6.11 is under $TURBO_INPUTS.
STOCK={'1.0.5.5':ROOT/'firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip',
       '1.0.5.12':ROOT/'firmware-research/strix-1.0.5.12/stock/Strix-OS-1.0.5.12-original.zip'}
CANONICAL='tmg12-emu/stock/Strix-OS-1.0.6.11-members-canonical.zip'
MAKE='create it with: python3 -I firmware/tools/stock_zip.py build --base 1.0.6.11 --members DIR --out "$TURBO_INPUTS/%s"'%CANONICAL
def sha(data):return hashlib.sha256(data).hexdigest()
def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def refused(call,why,prefix=None):
    """call must refuse; with a prefix, only by an AssertionError whose message starts with it."""
    try:call()
    except AssertionError as e:
        assert prefix is None or str(e).startswith(prefix),'refused for another reason (%r): %s'%(str(e),why);return
    except SystemExit as e:
        assert prefix is None,'exited (%r) instead of an AssertionError %r: %s'%(e.code,prefix,why);return
    raise SystemExit('accepted: '+why)
def stock_path(build,b):
    """The stock ZIP of a base through build.stock_zip_path. Never skipped: a missing file or $TURBO_INPUTS fails."""
    try:path=Path(build.stock_zip_path(b))
    except AssertionError as e:raise SystemExit('stock ZIP of %s: %s; then %s'%(b,e,MAKE))
    if not path.is_file():raise SystemExit('stock ZIP of %s not found at %s'%(b,path)+('; '+MAKE if b=='1.0.6.11' else ''))
    return path
def repack(path,files,rename={},drop=(),add={},prefix=''):
    """A stored ZIP of `files` with consistent manifest rows, with payloads renamed, dropped or added and names prefixed."""
    rows=[dict(r,Name=rename.get(r['Name'],r['Name'])) for r in json.loads(files['OtaFileInfo.json']) if r['Name'] not in drop]
    data={rename.get(n,n):b for n,b in files.items() if n!='OtaFileInfo.json' and n not in drop}
    for n,b in add.items():
        data[n]=b;rows.append(dict(rows[0],Name=n,Size=len(b),Md5=hashlib.md5(b).hexdigest()))
    data['OtaFileInfo.json']=json.dumps(rows,indent=1).encode()
    with zipfile.ZipFile(path,'w',zipfile.ZIP_STORED) as z:
        for n,b in sorted(data.items()):z.writestr(prefix+n,b)
    return path
def tool(sz,*argv):
    """stock_zip.main(argv) in-process: (exit code, stdout)."""
    out=io.StringIO()
    with contextlib.redirect_stdout(out),contextlib.redirect_stderr(io.StringIO()):
        try:rc=sz.main([str(a) for a in argv])
        except SystemExit as e:rc=e.code
    return (0 if rc is None else rc if isinstance(rc,int) else 1),out.getvalue()
def synthetic(rebase,old,spec,six,aps,taken):
    """A format-2 table 1.0.5.12 to 1.0.6.11 made from the old table's new column: every address moved by one even
    offset (Thumb bits kept) that collides with no token of the tree and no address of the old table, one 4-byte bw
    edit made 6 bytes (newPad 1), the raw edit's newBefore given another immediate with newAfter = oldAfter."""
    addresses=[r['new'] for r in old['linkld']+old['values']+old['stockAbiRanges']]+[e['newAddress'] for e in old['edits']]+[old['moduleVA']['new']]
    d=0x2f0010
    while {int(a,16)+d for a in addresses}&taken:d+=0x10
    move=lambda s:'0x%0*x'%(len(s)-2,int(s,16)+d)
    row=lambda r,**k:{**r,**k,'verdict':'shift','checks':['sig'],'proof':{'synthetic':'stock_base_test round trip'}}
    by_role={e['role']:e for e in spec['edits']}
    longer=next(e['role'] for e in old['edits'] if by_role[e['role']]['kind']=='bw' and len(e['newBefore'])==8 and by_role[e['role']]['pad']==0)
    edits=[]
    for e in old['edits']:
        s=by_role[e['role']];r=row({'role':e['role'],'kind':s['kind']},oldAddress=e['newAddress'],newAddress=move(e['newAddress']),
            oldOffset=e['newOffset'],newOffset=move(e['newOffset']),delta=d,oldBefore=e['newBefore'],newBefore=e['newBefore'],oldPad=s['pad'],newPad=s['pad'])
        if e['role']==longer:r.update(newBefore=e['newBefore']+'00bf',newPad=1)
        if s['kind']=='raw':r.update(newBefore='%02x'%(int(e['newBefore'][:2],16)^1)+e['newBefore'][2:],oldAfter=s['after'],newAfter=s['after'])
        edits.append(r)
    values=[]
    for v in old['values']:
        r=row({'name':v['name'],'kind':v['kind'],'sites':rebase.sites(v)},old=v['new'],new=move(v['new']))
        if v['kind']=='data':r.update(oldString=v['string'],newString=v['string'])
        values.append(r)
    module=move(old['moduleVA']['new'])
    return {'format':'turboio-rebase-2','from':'1.0.5.12','to':'1.0.6.11','note':'synthetic, temp dir only','thumbConvention':old['thumbConvention'],
        'provenance':{'generator':'tests/stock_base_test.py','inputs':[],'tree':'temp copy','stock':{}},
        'bases':{'1.0.5.12':{**old['bases']['1.0.5.12'],'stockZIPKind':'official','dataFileDelta':hex(rebase.data_file_delta(aps[0]))},
                 '1.0.6.11':{'stockZIPFile':'$TURBO_INPUTS/'+CANONICAL,'stockZIPKind':'canonical-members','stockZIP':six['container']['sha256'],
                    'stockZIPBytes':six['container']['bytes'],'stockAP':six['members']['nuttx_ap.bin'],'stockAPBytes':len(aps[1]),
                    'stockMembers':{n:h for n,h in six['members'].items() if n!='OtaFileInfo.json'},'stockManifestSHA256':six['members']['OtaFileInfo.json'],
                    'moduleVA':module,'dataFileDelta':hex(rebase.data_file_delta(aps[1]))}},
        'moduleVA':{'old':old['moduleVA']['new'],'new':module,'derivation':'synthetic'},
        'linkld':[row({'symbol':r['symbol']},old=r['new'],new=move(r['new']),delta=d) for r in old['linkld']],'edits':edits,'values':values,
        'stockAbiRanges':[row({'bytes':r['bytes']},old=r['new'],new=move(r['new']),oldSHA256=r['newSHA256'],newSHA256=r['newSHA256']) for r in old['stockAbiRanges']],
        'notStock':old['notStock'],'scanExempt':old['scanExempt'],'rejected':[]}
def snapshot(tree):return {p.relative_to(tree).as_posix():p.read_bytes() for p in sorted(tree.rglob('*')) if p.is_file() and '__pycache__' not in p.parts}
def main():
    build=load(FW/'build.py','stock_base_build');rebase=load(FW/'tools/rebase_apply.py','stock_base_rebase')
    sz=load(FW/'tools/stock_zip.py','stock_base_stock_zip');independent=load(FW/'tests/rebase_independent_test.py','stock_base_independent')
    # Three bases, the endpoints of the table chain, and the independent test's pairs are the same list.
    pairs=[(t[0],t[1]) for t in rebase.TABLES]
    assert build.STOCK_BASES==BASES==(pairs[0][0],)+tuple(p[1] for p in pairs),build.STOCK_BASES
    assert all(a[1]==b[0] for a,b in zip(pairs,pairs[1:])) and list(independent.PAIRS)==pairs,list(independent.PAIRS)
    chain=rebase.table_chain();table=rebase.load_table();old=chain[0];six=sz.pinned('1.0.6.11')
    assert (old['from'],old['to'])==pairs[0]
    spec=json.loads((FW/'build-inputs.json').read_text());base=build.stock_base(spec)
    assert build.stock_versions('1.0.6.11')=={'SW_VER':'Strix OS 1.0.6','BUILD_VER':'11'}
    assert build.stock_versions('1.0.5.12')=={'SW_VER':'Strix OS 1.0.5','BUILD_VER':'12'}
    assert build.stock_versions('1.0.5.5')=={'SW_VER':'Strix OS 1.0.5','BUILD_VER':'5'}
    for b in BASES:
        flags=build.stock_defines(b)
        assert flags.count('-DTD_STOCK_%s=1'%b.replace('.',''))==1 and sum(f.endswith('=1') for f in flags)==1
        assert sorted(flags)==sorted(['-DTD_STOCK_10412=0']+['-DTD_STOCK_%s=%d'%(x.replace('.',''),x==b) for x in BASES]),flags
    refused(lambda:build.stock_base({'stockBase':'1.0.5.6'}),'unknown stock base')
    refused(lambda:build.stock_base({}),'missing stock base')
    # emuOnly: a 1.0.6.11 tree must say so; the tree's own value is read as written.
    refused(lambda:build.emu_only({'stockBase':'1.0.6.11'}),'1.0.6.11 tree that is not emuOnly','emuOnly:')
    assert build.emu_only({'stockBase':'1.0.6.11','emuOnly':True}) is True and build.emu_only(spec) is spec.get('emuOnly',False)
    # stockZIPProvenance: on the real tree, present exactly when the base's stock container is canonical-members, and
    # then exactly stock_zip.py's pinned provenance record for that base (no extra keys). rebase_apply --write keeps it.
    canonical=build.package_shape(base)['container']=='canonical-members'
    assert ('stockZIPProvenance' in spec)==canonical,'build-inputs.json stockZIPProvenance %s on a %s base'%(
        'present' if 'stockZIPProvenance' in spec else 'missing',build.package_shape(base)['container'])
    if canonical:assert spec['stockZIPProvenance']==sz.pinned(base)['provenance'],'build-inputs.json stockZIPProvenance is not the pinned record'
    # Stock ZIP paths: the repository files for 1.0.5.x, $TURBO_INPUTS (or --inputs) for 1.0.6.11, no fallback.
    for b,path in STOCK.items():assert Path(build.stock_zip_path(b)).resolve()==path.resolve(),b
    with tempfile.TemporaryDirectory(prefix='stock-base-inputs-') as tmp:
        assert Path(build.stock_zip_path('1.0.6.11',Path(tmp)))==Path(tmp)/CANONICAL
    saved=os.environ.pop('TURBO_INPUTS',None)
    try:refused(lambda:build.stock_zip_path('1.0.6.11'),'1.0.6.11 stock with no TURBO_INPUTS','TURBO_INPUTS is not set')
    finally:
        if saved is not None:os.environ['TURBO_INPUTS']=saved
    paths={b:stock_path(build,b) for b in BASES}
    # Each stock ZIP through safe_zip with its pin (old table bases for 1.0.5.x, stock_zip.pinned for 1.0.6.11),
    # then its shape, cores, members and (1.0.6.11) manifest hash.
    pins={b:old['bases'][b]['stockZIP'] for b in BASES[:2]};pins['1.0.6.11']=six['container']['sha256']
    names={b:sorted(old['bases'][b]['stockMembers']) for b in BASES[:2]};names['1.0.6.11']=sorted(n for n in six['members'] if n!='OtaFileInfo.json')
    files,revs={},set()
    for b in BASES:
        raw=paths[b].read_bytes();assert sha(raw)==pins[b],b
        if b=='1.0.6.11':assert len(raw)==six['container']['bytes']
        files[b],rows=build.safe_zip(paths[b],pins[b],b)
        shape=build.package_shape(b);n=len(names[b])
        assert shape['base']==b and sorted(shape['payloads'])==names[b] and (shape['manifestRows'],shape['archiveEntries'],shape['unchangedPayloads'])==(n,n+1,n-1),(b,shape)
        assert (shape['container'],shape['phoneRelease'])==(('canonical-members',False) if b=='1.0.6.11' else ('official',True)),(b,shape)
        assert sorted(files[b])==sorted(names[b]+['OtaFileInfo.json']) and sorted(r['Name'] for r in rows)==names[b],b
        cores=build.core_identity(files[b],b)
        assert cores['buildVer']==b.rsplit('.',1)[1];revs.add(cores['revInfo'])
    assert names['1.0.5.5']==names['1.0.5.12'] and set(names['1.0.6.11'])^set(names['1.0.5.12'])=={'rives.bin','amap_rtos_sdk','nuttx_ota.bin'}
    assert len(revs)==3,revs
    # The pinned members of each base are exactly that stock ZIP's members (the no-base call form only fits 1.0.5.x).
    for b in BASES[:2]:
        build.check_stock_members(files[b],{'stockMembers':old['bases'][b]['stockMembers']},b)
        build.check_stock_members(files[b],{'stockMembers':old['bases'][b]['stockMembers']})
    six_files=files['1.0.6.11'];assert {n:sha(d) for n,d in six_files.items()}==six['members']
    m6={'stockMembers':{n:h for n,h in six['members'].items() if n!='OtaFileInfo.json'},'stockManifestSHA256':six['members']['OtaFileInfo.json']}
    build.check_stock_members(six_files,m6,'1.0.6.11');build.check_stock_members(six_files,{**m6,'stockBase':'1.0.6.11'})
    refused(lambda:build.check_stock_members(six_files,m6),'1.0.6.11 members with no base (manifest rule skipped)')
    refused(lambda:build.check_stock_members(six_files,{'stockMembers':m6['stockMembers']},'1.0.6.11'),'1.0.6.11 members with no manifest pin')
    refused(lambda:build.check_stock_members(six_files,{**m6,'stockManifestSHA256':'0'*64},'1.0.6.11'),'1.0.6.11 manifest of another hash')
    refused(lambda:build.check_stock_members({**six_files,'OtaFileInfo.json':six_files['OtaFileInfo.json']+b' '},m6,'1.0.6.11'),'1.0.6.11 manifest changed')
    # The three copies of the 1.0.6.11 pins agree: stock_zip.PINS, the new table's base, a 1.0.6.11 build-inputs.json.
    for info in [t['bases']['1.0.6.11'] for t in chain if '1.0.6.11' in t['bases']]+([spec] if base=='1.0.6.11' else []):
        assert (info['stockMembers'],info['stockManifestSHA256'],info['stockZIP'],info['stockAP'])==(m6['stockMembers'],m6['stockManifestSHA256'],pins['1.0.6.11'],six['members']['nuttx_ap.bin'])
    for t in chain:
        if '1.0.6.11' in t['bases']:
            info=t['bases']['1.0.6.11']
            assert (info['stockZIPKind'],info['stockZIPBytes'])==('canonical-members',six['container']['bytes']),(t['from'],t['to'],info.get('stockZIPKind'),info.get('stockZIPBytes'))
    if base=='1.0.6.11':assert spec.get('stockZIPBytes',six['container']['bytes'])==six['container']['bytes']
    # Mixed cores are refused for every ordered pair of bases and every core, and a whole other stock is not the base.
    for b in BASES:
        for o in BASES:
            if o==b:continue
            for core in build.CORES:
                refused(lambda:build.core_identity({**files[b],core:files[o][core]},b),'%s set with a %s %s'%(b,o,core))
            refused(lambda:build.core_identity(files[o],b),'%s stock read as %s'%(o,b))
    new=files['1.0.5.12']
    # A REV_INFO from another build with the right version strings is still a mix.
    forged=new['nuttx_bth.bin'].replace(b'REV_INFO=55bc20b0-dirty:',b'REV_INFO=55bc20b1-dirty:')
    assert forged!=new['nuttx_bth.bin']
    refused(lambda:build.core_identity({**new,'nuttx_bth.bin':forged},'1.0.5.12'),'BTH from another REV_INFO')
    refused(lambda:build.check_stock_members({**new,'nuttx_bth.bin':forged},{'stockMembers':old['bases']['1.0.5.12']['stockMembers']},'1.0.5.12'),'unpinned member')
    if base!='1.0.6.11':refused(lambda:build.check_stock_members({**new,'nuttx_bth.bin':forged},spec),'unpinned member')
    # .data copy: the file offset delta is read from each AP's descriptor, and a descriptor with dst changed is refused.
    deltas={}
    for b in BASES:
        ap=files[b]['nuttx_ap.bin'];src,end,dst=struct.unpack_from('<3I',ap,0x674)
        deltas[b]=rebase.data_file_delta(ap);assert deltas[b]==dst-(src-build.FLASH),b
        bad=bytearray(ap);bad[0x674+8]^=1;refused(lambda:rebase.data_file_delta(bytes(bad)),'data copy descriptor with dst changed, '+b)
    assert deltas==dict(zip(BASES,(0x17fbfe44,0x17fbfe44,0x17fbf49c))),deltas
    with tempfile.TemporaryDirectory(prefix='stock-base-shape-') as tmp:
        tmp=Path(tmp)
        # Package shape: same-count renames and drop+add, another base's real ZIP and folder-prefixed names are refused
        # by name (each ZIP passed with its own SHA-256, so the shape check is what refuses). An unchanged repack passes.
        for b in BASES:
            f=files[b];own=lambda p:build.safe_zip(p,sha(p.read_bytes()),b)
            own(repack(tmp/(b+'-same.zip'),f))
            moved='nuttx_ota.bin' if b=='1.0.6.11' else 'rives.bin'
            refused(lambda:own(repack(tmp/(b+'-rename.zip'),f,rename={moved:moved.replace('.bin','2.bin')})),b+' payload renamed','package shape:')
            refused(lambda:own(repack(tmp/(b+'-swap.zip'),f,drop=('lotties.bin',),add={'unknown_payload.bin':b'\0'*64})),b+' row dropped and unknown added','package shape:')
            for o in BASES:
                if o==b:continue
                if names[o]!=names[b]:refused(lambda:own(paths[o]),'%s ZIP read as %s'%(o,b),'package shape:')
                else:own(paths[o]);refused(lambda:build.core_identity(files[o],b),'%s ZIP (same shape) read as %s'%(o,b))
        prefixed=repack(tmp/'prefix.zip',files['1.0.6.11'],prefix='Strix_OS_1.0.6.11/')
        refused(lambda:build.safe_zip(prefixed,sha(prefixed.read_bytes()),'1.0.6.11'),'canonical members under a folder prefix','package shape:')
        # stock_zip.py: refusals on a temp copy of the canonical members; each exits 1 and leaves no output file.
        members=tmp/'members';members.mkdir()
        with zipfile.ZipFile(paths['1.0.6.11']) as z:z.extractall(members)
        assert sorted(p.name for p in members.iterdir())==sorted(six['members'])
        (members/'SHA256SUMS').write_text('0'*64+'  smf.json\n');(members/'PROVENANCE.md').write_text('ignored\n')   # both ignored
        out=tmp/'out';out.mkdir();count=[0]
        def probe(why,change=None,target=None,argv=None):
            count[0]+=1;work=tmp/('m%d'%count[0]);shutil.copytree(members,work,symlinks=True)
            if change:change(work)
            dest=target or out/('probe%d.zip'%count[0]);existed=dest.read_bytes() if dest.exists() else None
            try:rc,_=tool(sz,'build','--base','1.0.6.11','--members',work,'--out',dest)
            finally:
                if target is not None and existed is None and dest.exists():dest.unlink();raise SystemExit('stock_zip.py wrote %s: %s'%(dest,why))
            assert rc==1,'stock_zip.py build exit %r: %s'%(rc,why)
            assert (dest.read_bytes() if dest.exists() else None)==existed,'stock_zip.py left or changed %s: %s'%(dest.name,why)
        def symlinked(w):
            real=tmp/'real-smf.json';shutil.copy(w/'smf.json',real);(w/'smf.json').unlink();(w/'smf.json').symlink_to(real)
        def flipped(w):
            p=w/'images.bin';d=bytearray(p.read_bytes());d[len(d)//2]^=1;p.write_bytes(bytes(d))
        probe('missing member',lambda w:(w/'nuttx_ota.bin').unlink())
        probe('symlinked member',symlinked)
        probe('changed byte',flipped)
        probe('extra file',lambda w:(w/'extra.bin').write_bytes(b'x'))
        (out/'exists.zip').write_bytes(b'not a zip');probe('existing --out',target=out/'exists.zip')
        probe('--out inside the repository',target=ROOT/'stock-zip-probe-in-repo.zip')
        # The same refusal for an in-repository --out spelled in other letter case: the repository folder's own name
        # (so no string prefix of the repository path matches) and an upper-case firmware/. stock_zip.inside_repo
        # compares by file identity. On a case-sensitive disk the variant is another (missing) folder: skip, said so.
        case_ran=[]
        for variant,real in ((ROOT.parent/ROOT.name.swapcase(),ROOT),(ROOT/FW.name.upper(),FW)):
            if variant.name==real.name or not variant.is_dir() or not os.path.samefile(variant,real):
                print('SKIP case-variant --out probe: %s is not the folder %s on this disk (case-sensitive, or a name '
                      'with no letters)'%(variant,real.name));continue
            dest=variant/'stock-zip-case-probe.zip'
            assert not dest.exists(),'leftover %s: remove it first'%dest
            assert sz.inside_repo(dest),'stock_zip.inside_repo misses %s'%dest
            work=tmp/'case-members';shutil.rmtree(work,ignore_errors=True);shutil.copytree(members,work,symlinks=True)
            try:refused(lambda:sz.build_zip('1.0.6.11',work,dest),'case-variant --out '+str(dest),'output must not lie inside the repository')
            finally:
                if dest.exists():dest.unlink();raise SystemExit('stock_zip.py wrote %s'%dest)
            probe('--out inside the repository, spelled in other letter case',target=dest)
            case_ran.append(variant.name)
        probe('--out named original',target=out/'Strix-OS-1.0.6.11-original.zip')
        saved=copy.deepcopy(sz.PINS)
        try:
            sz.PINS['1.0.6.11']['container']['sha256']='0'*64;probe('container pin changed in memory')
        finally:sz.PINS.clear();sz.PINS.update(saved)
        assert sz.pinned('1.0.6.11')['container']['sha256']==pins['1.0.6.11']
        clean=out/'clean.zip';rc,printed=tool(sz,'build','--base','1.0.6.11','--members',members,'--out',clean)
        assert rc==0 and clean.read_bytes()==paths['1.0.6.11'].read_bytes(),'stock_zip.py build is not the canonical ZIP (exit %r)'%rc
        report=json.loads(printed)
        assert (report['base'],report['bytes'],report['sha256'],report['members'],report['container'],report['deviceIO'])==('1.0.6.11',six['container']['bytes'],pins['1.0.6.11'],17,'canonical-members',False),report
        assert tool(sz,'check','--base','1.0.6.11','--zip',paths['1.0.6.11'])[0]==0
        assert tool(sz,'check','--base','1.0.6.11','--zip',tmp/'1.0.6.11-same.zip')[0]==1
    # The tree is wholly on its base, and a single stale address makes it neither.
    assert rebase.tree_state(FW)==base
    with tempfile.TemporaryDirectory(prefix='stock-base-') as tmp:
        tree=Path(tmp)/'firmware';shutil.copytree(FW,tree,ignore=shutil.ignore_patterns('build','__pycache__'))
        col=rebase.column(table,base);v=next(x for x in table['values'] if x['name']=='display_unit')
        path=tree/sorted(rebase.sites(v))[0];path.write_text(path.read_text().replace(v[col],v[rebase.other(col)],1))
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
        # Format-2 round trip. Before the 1.0.6.11 table is committed, a synthetic one made from the old table;
        # after, the committed one. The second table is active, the tree moves there and back byte for byte, and a
        # wrong pad or raw after in the table is reported.
        target=tree/'baseline'/rebase.TABLES[1][2];kind='committed'
        if len(chain)==1:
            kind='synthetic';taken={int(m.group(1),16) for _,text in rebase.scanned_files(tree) for m in rebase.HEX.finditer(text)}
            taken|={int(r[c],16) for r in old['linkld']+old['values']+old['stockAbiRanges'] for c in ('old','new')}
            taken|={int(e[c+'Address'],16) for e in old['edits'] for c in ('old','new')}|{int(t,16) for t in old['notStock']}
            target.write_text(json.dumps(synthetic(rebase,old,spec,six,(new['nuttx_ap.bin'],six_files['nuttx_ap.bin']),taken),indent=1)+'\n')
        assert rebase.active_table_path(tree)==target and len(rebase.table_chain(tree))==2
        two=rebase.load_table(fw=tree);assert two['format']=='turboio-rebase-2' and rebase.tree_state(tree)==base
        before=snapshot(tree);there='1.0.6.11' if base=='1.0.5.12' else '1.0.5.12'
        rebase.write(tree,two,there);assert rebase.problems(tree,two,there)==[] and rebase.tree_state(tree)==there
        rebase.write(tree,two,base);after=snapshot(tree)
        assert after==before,'round trip changed: '+', '.join(p for p in sorted(set(before)|set(after)) if before.get(p)!=after.get(p))
        if base!='1.0.6.11':rebase.write(tree,two,'1.0.6.11')
        moved=json.loads((tree/'build-inputs.json').read_text())
        assert moved['stockBase']=='1.0.6.11' and moved['stockManifestSHA256']==m6['stockManifestSHA256'] and rebase.tree_state(tree)=='1.0.6.11'
        if kind=='synthetic':
            longer=[e for e in two['edits'] if len(e['newBefore'])!=len(e['oldBefore'])];assert len(longer)==1 and longer[0]['newPad']==1
            assert [(e['pad'],e['before']) for e in moved['edits'] if e['role']==longer[0]['role']]==[(1,longer[0]['newBefore'])]
            assert [e['after'] for e in moved['edits'] if e['kind']=='raw']==[e['after'] for e in spec['edits'] if e['kind']=='raw']
        padded=next((e for e in two['edits'] if e['newPad']!=e['oldPad']),two['edits'][0]);raw=next(e for e in two['edits'] if 'newAfter' in e)
        for role,key,value in ((padded['role'],'newPad',padded['newPad']+1),(raw['role'],'newAfter','%02x'%(int(raw['newAfter'][:2],16)^2)+raw['newAfter'][2:])):
            bad=copy.deepcopy(two);next(e for e in bad['edits'] if e['role']==role)[key]=value
            assert any(repr(role) in p for p in rebase.problems(tree,bad,'1.0.6.11')),'%s %s not reported'%(role,key)
        # A placeholder table with a wrong format, or with rejected rows, is refused.
        good=target.read_text()
        for key,value in (('format','turboio-rebase-1'),('rejected',[{'row':'placeholder'}])):
            target.write_text(json.dumps({**json.loads(good),key:value}))
            refused(lambda:rebase.load_table(fw=tree),'table with %s %r'%(key,value));refused(lambda:rebase.table_chain(tree),'chain with %s %r'%(key,value))
        target.write_text(good)
    print('PASS stock base: three bases (labels, defines, stock ZIP paths), package shapes by name (rename, drop+add, other base, folder prefix), '
          'mixed cores refused (AP/APC1/BTH, REV_INFO, every base pair), members and 1.0.6.11 manifest pinned, data copy deltas, '
          'stock_zip.py refusals (case-variant --out: %s) and byte-identical build, %s format-2 round trip, stale and unknown stock-window addresses refused, tree wholly on %s'%(
          ', '.join(case_ran) or 'skipped, case-sensitive disk',kind,base))
if __name__=='__main__':main()
