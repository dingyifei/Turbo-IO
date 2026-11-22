"""The phone pin generator (tools/phone_pins.py): version strings, release validation, the stock-base and tree checks,
the two packages of a release (a TMG build first, the base's stock package second) and their label checks, the
emulator-only and superseded-ZIP refusals, rendering, and --check catching a changed or stale output.
Usage: phone_pins_test.py ZIP [ZIP ...] (release ZIPs in any order; a release ZIP not given is read from $TURBO_INPUTS
at its releases.json path). The ZIP the tree builds (build-inputs.json archive) must be one of them, either given or
pinned by a release: today it is C22's ZIP. $TURBO_INPUTS must be set: the stock 1.0.6.11 ZIP is read from there."""
from pathlib import Path
import contextlib,copy,hashlib,importlib.util,io,json,os,shutil,subprocess,sys,tempfile,zipfile
FW=Path(__file__).resolve().parents[1]
ED=FW.parent/'ios-addon'
CORES=('nuttx_ap.bin','nuttx_apc1.bin','nuttx_bth.bin')
def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def refused(call,why):
    try:call()
    except (ValueError,AssertionError,KeyError):return
    raise SystemExit('accepted: '+why)
def refused_with(call,why,text):
    try:call()
    except (ValueError,AssertionError,KeyError,OSError) as error:   # OSError: a call that read a file it should have refused first
        if text in str(error):return
        raise SystemExit('refused for the wrong reason: '+why+': '+str(error))
    raise SystemExit('accepted: '+why)
def rewrite_zip(src,replace,rename=None):
    """A copy of ZIP src (bytes) with some members replaced ({name: bytes}) or renamed ({old: new}), its manifest rows
    rewritten to match (Name, Size, Md5), so only the generator's stock-base checks can refuse it."""
    rename=rename or {};out=io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(src)) as z,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as dst:
        rows=json.loads(z.read('OtaFileInfo.json'))
        for r in rows:
            if r['Name'] in replace:r['Size']=len(replace[r['Name']]);r['Md5']=hashlib.md5(replace[r['Name']]).hexdigest()
            r['Name']=rename.get(r['Name'],r['Name'])
        dst.writestr('OtaFileInfo.json',json.dumps(rows))
        for n in z.namelist():
            if n!='OtaFileInfo.json':dst.writestr(rename.get(n,n),replace.get(n,z.read(n)))
    return out.getvalue()
# Each planted emulator-only condition, refused by every mode of a throwaway copy of the tool (emuOnly tree, label in
# its own RELEASE, releases.json and the release ZIP copied under its own inputs). --resolve must refuse it on its own,
# with no path printed; --write must leave no output folder.
EMU_PLANTS={
    'a release carrying the emuOnly tree label':('label',"label of an emuOnly tree"),
    'a release that is the emuOnly tree build record':('record',"ZIP of an emuOnly tree"),
    'a release ZIP with the -EMU-ONLY- name':('name',"an -EMU-ONLY- ZIP cannot be a phone release"),
    'a release on a stock base with no phone release':('base',"has no phone release"),
    # An older emulator-only ZIP after the tree is repinned: plain name, another label, not the tree record, listed
    # under the phone base 1.0.6.11. Only its own bytes give it away: another base's package shape (the stock
    # 1.0.5.12 ZIP itself), or another base's cores in the 1.0.6.11 shape (the C22 ZIP with the stock 1.0.5.12 cores).
    'an older emulator-only ZIP with the 1.0.5.12 shape':('shape',"the ZIP is not a build on stock 1.0.6.11"),
    'an older emulator-only ZIP with 1.0.5.12 cores':('cores',"the ZIP is not a build on stock 1.0.6.11"),
}
NO_PHONE_FROM="'container': 'canonical-members', 'phoneRelease': True,"
def no_phone_build_source():
    """build.py with stock 1.0.6.11 marked as a base with no phone release: the fixture for the emulator-only base mode,
    which the real tree no longer uses (1.0.6.11 became a phone release base with the TMG12 release build)."""
    text=(FW/'build.py').read_text()
    if text.count(NO_PHONE_FROM)!=1:raise SystemExit('build.py: the 1.0.6.11 shape line for the no-phone fixture is not found exactly once')
    return text.replace(NO_PHONE_FROM,NO_PHONE_FROM.replace('True','False'))
def no_phone_build(tmp):
    (Path(tmp)/'build.py').write_text(no_phone_build_source());module=load(Path(tmp)/'build.py','phone_pins_no_phone_build')
    assert not module.package_shape('1.0.6.11')['phoneRelease'];return module
def emu_stand_in(plant,release_zip,build):
    """The bytes of an emulator-only stand-in: the stock 1.0.5.12 ZIP itself, or the release ZIP with AP, APC1 and BTH
    replaced by the stock 1.0.5.12 cores."""
    stock=build.stock_zip_path('1.0.5.12').read_bytes()
    if plant=='shape':return stock
    with zipfile.ZipFile(io.BytesIO(stock)) as old:cores={n:old.read(n) for n in CORES}
    return rewrite_zip(Path(release_zip).read_bytes(),cores)
def emu_planted(tool,why,releases_file,zips,name,plant=None):
    with tempfile.TemporaryDirectory(prefix='phone-pins-plant-') as tmp:
        tmp=Path(tmp);fw=tmp/'fw';(fw/'tools').mkdir(parents=True)
        shutil.copy(tool,fw/'tools/phone_pins.py')
        if plant=='base':(fw/'build.py').write_text(no_phone_build_source())
        else:shutil.copy(FW/'build.py',fw/'build.py')
        # The copy's tree is emuOnly, with its own label and a build record that is no release's ZIP (the real record
        # is C22's ZIP), except where a plant makes the release that record or that label.
        tree=json.loads((FW/'build-inputs.json').read_text());tree['emuOnly']=True;tree['archive']={**tree['archive'],'sha256':'0'*64}
        (fw/'RELEASE').write_text('TMG99\n')
        # The copy's release keeps its first (TMG) package only; the plants change that package.
        data=json.loads(Path(releases_file).read_text());rel=data['releases'][name];rel['packages']=rel['packages'][:1];spec=rel['packages'][0]
        source=zips[spec['zip']['sha256']]
        if plant=='label':spec['label']='TMG99'
        if plant=='record':tree['archive']={**tree['archive'],'sha256':spec['zip']['sha256'],'bytes':spec['zip']['bytes']}
        if plant=='name':spec['zip']['input']='tmg99/StrixOS-1.0.6.11-TurboIO-TMG99-EMU-ONLY-NOT-FOR-DEVICE.zip'
        inputs=tmp/'inputs'
        if plant in ('shape','cores'):
            raw=emu_stand_in(plant,source,load(FW/'build.py','phone_pins_plant_build_'+plant))   # the real tree's stock ZIP paths
            spec['label']='TMG98';spec['zip']={'input':'tmg98/StrixOS-1.0.6.11-TurboIO-TMG98-CANDIDATE-NOT-APPROVED.zip',
                'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
            (inputs/'tmg98').mkdir(parents=True);(inputs/spec['zip']['input']).write_bytes(raw)
        data['releases']={name:rel}
        (fw/'build-inputs.json').write_text(json.dumps(tree));(tmp/'releases.json').write_text(json.dumps(data))
        target=inputs/spec['zip']['input']
        if not target.exists():target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
        copy_pp=load(fw/'tools/phone_pins.py','phone_pins_plant_'+(plant or 'none'))
        def run(*argv):
            out,err=io.StringIO(),io.StringIO()
            with contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):code=copy_pp.main(['--releases',str(tmp/'releases.json'),*argv])
            return code,out.getvalue(),err.getvalue()
        code,out,err=run('--resolve',name,'--inputs',str(inputs))
        if plant is None:
            if (code,out)!=(0,str(target)+'\n'):raise SystemExit('refused without a plant: '+err)
            return
        text=EMU_PLANTS[why][1]
        if code==0 or out or text not in err:raise SystemExit('--resolve accepted '+why+': exit %d, %r %r'%(code,out,err))
        code,out,err=run('--verify',name,'--zip',str(target),'--dir',str(ED))
        if code==0 or text not in err:raise SystemExit('--verify accepted '+why+': '+err)
        for mode in ('--write','--check'):
            dest=tmp/('out'+mode)
            code,out,err=run('--inputs',str(inputs),mode,str(dest))
            if code==0 or text not in err or dest.exists():raise SystemExit(mode+' accepted '+why+': '+err)
def preprocess(header,defines):
    """Run the C preprocessor over a FirmwarePins.h with the given -D flags: (exit code, TIO_FW_RELEASE line, stderr)."""
    with tempfile.TemporaryDirectory(prefix='phone-pins-cpp-') as tmp:
        (Path(tmp)/'FirmwarePins.h').write_bytes(header)
        (Path(tmp)/'probe.m').write_text('#include "FirmwarePins.h"\nRELEASE_IS TIO_FW_RELEASE\n')
        r=subprocess.run(['xcrun','clang','-E','-P','-x','objective-c',*defines,str(Path(tmp)/'probe.m')],capture_output=True,text=True)
        line=[l for l in r.stdout.splitlines() if l.startswith('RELEASE_IS ')]
        return r.returncode,(line[0] if line else None),r.stderr
def main():
    if not os.environ.get('TURBO_INPUTS'):raise SystemExit('TURBO_INPUTS is not set: the stock 1.0.6.11 ZIP is read from there')
    pp=load(FW/'tools/phone_pins.py','phone_pins_under_test')
    zips={hashlib.sha256(Path(p).read_bytes()).hexdigest():Path(p) for p in sys.argv[1:]}
    releases=pp.load_releases(ED/'releases.json')
    for release in releases.values():
        for spec in pp.packages(release):
            if spec['zip']['sha256'] not in zips:
                p=Path(os.environ['TURBO_INPUTS'])/spec['zip']['input']
                if p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==spec['zip']['sha256']:zips[spec['zip']['sha256']]=p
    def zip_of(spec):return zips[spec['zip']['sha256']]
    tree_inputs=json.loads((FW/'build-inputs.json').read_text());tree_label=pp.release_label()
    tree_zip=zips.get(tree_inputs['archive']['sha256'])
    if tree_zip is None:raise SystemExit('give the ZIP the tree builds (build-inputs.json archive) as an argument')
    build=pp.load_build()
    stock1611=build.stock_zip_path('1.0.6.11');stock10512=build.stock_zip_path('1.0.5.12');stock1055=build.stock_zip_path('1.0.5.5')
    # The one release, written out by hand: C22 on stock 1.0.6.11 for the 1.0.21 full host, with two packages: TMG13
    # (the tree's own ZIP, the default) and stock 1.0.6.11 (the canonical stock ZIP, the same file build.py names).
    assert list(releases)==['c22'],list(releases)
    release21=releases['c22'];c22=pp.package_spec(release21);stock21=pp.package_spec(release21,'STOCK-1.0.6.11');c21_zip=zip_of(c22)
    assert [p['label'] for p in release21['packages']]==['TMG13','STOCK-1.0.6.11'] and [p['kind'] for p in pp.packages(release21)]==['TMG','STOCK']
    assert (c22['firmware'],c22['stockBase'],release21['hosts'],c22['acceptCurrent'])==('TMG13','1.0.6.11',['1021-full'],['1.0.5.12','1.0.6.11'])
    assert (c22['zip']['bytes'],c22['zip']['sha256'])==(9557730,'81eb560d9fc9f1a0ed8ec120385d2d09c366cece4a325f684ca9e4cadd2b744e')
    assert (stock21['stockBase'],stock21['acceptCurrent'])==('1.0.6.11',['1.0.5.12','1.0.6.11'])
    assert (stock21['zip']['bytes'],stock21['zip']['sha256'])==(9447267,'5821506f720a43a9a3aea9c5722a1548463dcf1cbedcb2d97a242e2a64037d6e')
    stock21_zip=zip_of(stock21);assert stock21_zip.read_bytes()==stock1611.read_bytes()
    assert c21_zip==tree_zip and (tree_label,tree_inputs['stockBase'])==('TMG13','1.0.6.11')
    # Version strings, written out by hand.
    assert pp.query_code('1.0.5.12')=='01.00.05.0012' and pp.query_code('1.0.5.5')=='01.00.05.0005' and pp.query_code('1.0.6.11')=='01.00.06.0011'
    assert pp.feed_version_name('1.0.6.11')=='0100060011' and pp.feed_version_name('1.0.5.12')=='0100050012'
    assert pp.os_version('1.0.6.11')=='Strix OS 1.0.6.11'
    for bad in ('1.0.5','1.0.5.12.1','v1.0.5.5','1.0.5.x','',None):refused(lambda:pp.version_parts(bad),'version '+repr(bad))
    # C22's own ZIP passes and yields this policy, with 17 member pins (16 payloads and the manifest) and 16 manifest rows.
    pins,members,policy=pp.release_pins('c22',c22,c21_zip,build)
    assert (pins['name'],policy['release'],policy['stockBase'],policy['otaVersion'],policy['folder'],policy['feedVersionName'],policy['feedVersionCode'])==('TMG13','c22','1.0.6.11','Strix OS 1.0.6.11','Strix_OS_1.0.6.11','0100060011',100060011)
    assert policy['acceptOsVersions']==['Strix OS 1.0.5.12','Strix OS 1.0.6.11'] and policy['acceptQueryCodes']==['01.00.05.0012','01.00.06.0011']
    assert len(members)==17 and 'OtaFileInfo.json' in members and 'nuttx_ota.bin' in members and 'amap_rtos_sdk' in members and 'rives.bin' not in members
    with zipfile.ZipFile(c21_zip) as z:assert len(json.loads(z.read('OtaFileInfo.json')))==16 and len(z.namelist())==17
    assert members['nuttx_ap.bin']==[pins['apBytes'],pins['apSHA256']]==[tree_inputs['APBytes'],tree_inputs['APSHA256']]
    # The ZIP must be the pinned one: another file, a wrong size or a wrong SHA-256 is refused, in release_pins and in resolve.
    refused_with(lambda:pp.release_pins('c22',c22,stock1611,build),'c22 with the stock 1.0.6.11 ZIP','ZIP does not match releases.json')
    for key,value in (('bytes',c22['zip']['bytes']+1),('sha256','0'*64)):
        wrong=copy.deepcopy(c22);wrong['zip'][key]=value
        refused_with(lambda:pp.release_pins('c22',wrong,c21_zip,build),'c22 with a wrong '+key,'ZIP does not match releases.json')
        with tempfile.TemporaryDirectory(prefix='phone-pins-pin-') as tmp:
            target=Path(tmp)/c22['zip']['input'];target.parent.mkdir(parents=True);shutil.copyfile(c21_zip,target)
            refused_with(lambda:pp.resolve(wrong,tmp,'c22',build),'c22 with a wrong '+key+' (--resolve)','release ZIP does not match its pin')
    # Another stock base: the ZIP's own shape and cores are 1.0.6.11, so its bytes refuse it.
    for base in ('1.0.5.12','1.0.5.5'):
        wrong=copy.deepcopy(c22);wrong['stockBase']=base
        refused_with(lambda:pp.release_pins('c22',wrong,c21_zip,build),'c22 on stock '+base,'not a build on stock '+base)
    # The tree's label must be carried by the tree's own ZIP.
    tree={'archive':{'sha256':'0'*64},'stockBase':c22['stockBase']}
    refused_with(lambda:pp.release_pins('c22',c22,c21_zip,build,tree,c22['firmware']),'c22 named as the tree release with another ZIP','is the tree label but this is not the ZIP')
    # The stock package passes and yields the stock pins: every member, the AP and the manifest included, is the stock
    # 1.0.6.11 ZIP's; same policy as the TMG package (both accept 1.0.5.12 and 1.0.6.11, both target 1.0.6.11).
    spins,smembers,spolicy=pp.release_pins('c22',stock21,stock21_zip,build)
    with zipfile.ZipFile(stock1611) as z:stock_rows=z.read('OtaFileInfo.json');stock_ap=z.read('nuttx_ap.bin')
    assert spins['name']=='STOCK-1.0.6.11' and (spins['zipBytes'],spins['zipSHA256'])==(9447267,stock21['zip']['sha256'])
    assert spins['apSHA256']==hashlib.sha256(stock_ap).hexdigest()!=pins['apSHA256'] and spins['manifestSHA256']==hashlib.sha256(stock_rows).hexdigest()
    assert spolicy==policy and len(smembers)==17 and {n for n in members if n not in ('nuttx_ap.bin','OtaFileInfo.json')}=={n for n in smembers if smembers[n]==members[n]}
    # Package labels: a TMG build is TMGn and the stock package is STOCK-<base>; any other label is refused.
    assert pp.package_kind('TMG12','1.0.6.11')=='TMG' and pp.package_kind('STOCK-1.0.6.11','1.0.6.11')=='STOCK'
    for label in ('STOCK-1.0.5.12','stock-1.0.6.11','STOCK','STOCK-','TMG','tmg12','TMG12a','RELEASE','',None,12):
        refused_with(lambda:pp.package_kind(label,'1.0.6.11'),'package label '+repr(label),'unknown package label')
        refused_with(lambda:pp.release_pins('c22',{**stock21,'firmware':label},stock21_zip,build),'a package labelled '+repr(label),'unknown package label')
    # The stock package is the stock ZIP and nothing else: one changed member, a changed AP, or a reformatted manifest
    # (same payloads, rows rewritten) under the STOCK label is refused, each by the stock comparison (pins rewritten to match).
    with zipfile.ZipFile(stock21_zip) as z:simages=bytearray(z.read('images.bin'))
    with zipfile.ZipFile(c21_zip) as z:c21_ap=z.read('nuttx_ap.bin')
    simages[len(simages)//2]^=1
    for what,raw,text in (('a changed images.bin',rewrite_zip(stock21_zip.read_bytes(),{'images.bin':bytes(simages)}),'images.bin is not the stock 1.0.6.11 member'),
                          ('the TMG12 AP',rewrite_zip(stock21_zip.read_bytes(),{'nuttx_ap.bin':c21_ap}),'nuttx_ap.bin is not the stock 1.0.6.11 member'),
                          ('a rewritten manifest',rewrite_zip(stock21_zip.read_bytes(),{}),'OtaFileInfo.json is not the stock 1.0.6.11 manifest')):
        with tempfile.TemporaryDirectory(prefix='phone-pins-stock-') as tmp:
            path=Path(tmp)/'stock.zip';path.write_bytes(raw)
            changed={**stock21,'zip':{'input':'stock/x.zip','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}}
            refused_with(lambda:pp.release_pins('c22',changed,path,build),'a STOCK package with '+what,text)
    # The TMG ZIP under the STOCK label, and the stock ZIP under a TMG label, are refused.
    refused_with(lambda:pp.release_pins('c22',{**stock21,'zip':c22['zip']},c21_zip,build),'the TMG13 ZIP under STOCK-1.0.6.11','nuttx_ap.bin is not the stock 1.0.6.11 member')
    refused_with(lambda:pp.release_pins('c22',{**c22,'firmware':'TMG98','zip':stock21['zip']},stock21_zip,build),'the stock ZIP under a TMG label','carries the stock 1.0.6.11 AP')
    refused_with(lambda:pp.release_pins('c22',{**c22,'zip':stock21['zip']},stock21_zip,build),'the stock ZIP under TMG13','carries the stock 1.0.6.11 AP')
    # Every member but AP must be the stock 1.0.6.11 member: one changed byte in images.bin (manifest rewritten to match,
    # so only the stock comparison can refuse it), under another label so the tree check does not decide it.
    with zipfile.ZipFile(c21_zip) as z:images=bytearray(z.read('images.bin'))
    images[len(images)//2]^=1
    with tempfile.TemporaryDirectory(prefix='phone-pins-member-') as tmp:
        raw=rewrite_zip(c21_zip.read_bytes(),{'images.bin':bytes(images)});path=Path(tmp)/'member.zip';path.write_bytes(raw)
        changed=copy.deepcopy(c22);changed['firmware']='TMG98';changed['zip']={'input':'tmg98/x.zip','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
        refused_with(lambda:pp.release_pins('c22',changed,path,build),'a non-stock images.bin','images.bin is not the stock 1.0.6.11 member')
    # An emulator-only build is never a phone release. Each probe is refused with its own message, and the same inputs
    # without the emuOnly condition are accepted (the ZIP and label probes use c22, the real release).
    real_tree={'archive':{'sha256':'0'*64},'stockBase':c22['stockBase']}
    pp.release_pins('c22',c22,c21_zip,build,real_tree,'TMG99')
    with tempfile.TemporaryDirectory(prefix='phone-pins-no-phone-') as tmp:
        refused_with(lambda:pp.release_pins('c22',c22,c21_zip,no_phone_build(tmp)),'a stock base with no phone release','has no phone release')
    # A ZIP of another base listed under 1.0.6.11 is refused by its own bytes: the stock 1.0.5.12 package.
    old_shape=copy.deepcopy(c22);old_shape['firmware']='TMG98';raw=stock10512.read_bytes()
    old_shape['zip']={'input':'tmg98/x.zip','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
    refused_with(lambda:pp.release_pins('c22',old_shape,stock10512,build),'a 1.0.5.12 ZIP listed under 1.0.6.11','not a build on stock 1.0.6.11')
    emu_tree={'archive':{'sha256':c22['zip']['sha256']},'stockBase':c22['stockBase'],'emuOnly':True}
    refused_with(lambda:pp.release_pins('c22',c22,c21_zip,build,{**emu_tree,'archive':{'sha256':'0'*64}},c22['firmware']),'the label of an emuOnly tree','label of an emuOnly tree')
    refused_with(lambda:pp.release_pins('c22',c22,c21_zip,build,emu_tree,'TMG99'),'the ZIP of an emuOnly tree','ZIP of an emuOnly tree')
    refused_with(lambda:pp.release_pins('c22',c22,c21_zip,build,{**tree_inputs,'emuOnly':True}),'c22 under an emuOnly tree','label of an emuOnly tree')
    emu_name=copy.deepcopy(c22);emu_name['zip']['input']='tmg12/StrixOS-1.0.6.11-TurboIO-TMG12-EMU-ONLY-NOT-FOR-DEVICE.zip'
    refused_with(lambda:pp.release_pins('c22',emu_name,c21_zip,build),'an -EMU-ONLY- input name','-EMU-ONLY-')
    refused_with(lambda:pp.pins_for(stock1055,'TMG9','1.0.6.11'),'a 1.0.5.5 ZIP read with the 1.0.6.11 package shape','payload manifest rows')
    # Same row count, one payload renamed (in the ZIP and its manifest): only the payload-name check can refuse it.
    with tempfile.TemporaryDirectory(prefix='phone-pins-names-') as tmp:
        renamed=Path(tmp)/'renamed.zip';renamed.write_bytes(rewrite_zip(c21_zip.read_bytes(),{},{'amap_rtos_sdk':'amap_rtos_sdx'}))
        refused_with(lambda:pp.pins_for(renamed,'TMG12','1.0.6.11'),'a ZIP with a renamed payload, same row count','payload names are not the stock')
    # --tree-release on an emuOnly tree: refused before any release lookup (a throwaway copy of the tool and build.py
    # whose build-inputs.json says emuOnly; the releases file it is given does not exist, so a lookup would fail differently).
    with tempfile.TemporaryDirectory(prefix='phone-pins-emu-') as tmp:
        tmp=Path(tmp);(tmp/'tools').mkdir()
        shutil.copy(FW/'tools/phone_pins.py',tmp/'tools');shutil.copy(FW/'build.py',tmp)
        (tmp/'build-inputs.json').write_text(json.dumps({**tree_inputs,'emuOnly':True}))
        copy_pp=load(tmp/'tools/phone_pins.py','phone_pins_emu_copy');err=io.StringIO()
        with contextlib.redirect_stderr(err):code=copy_pp.main(['--tree-release','--releases',str(tmp/'missing.json')])
        assert code==1 and '--tree-release: emuOnly tree has no phone release' in err.getvalue(),err.getvalue()
    # On the real tree, --tree-release names C22.
    out=io.StringIO()
    with contextlib.redirect_stdout(out):assert pp.main(['--tree-release'])==0
    assert out.getvalue()=='c22\n',out.getvalue()
    # Every mode refuses each emulator-only condition on its own, --resolve included; the unplanted copy resolves c22.
    emu_planted(FW/'tools/phone_pins.py',None,ED/'releases.json',zips,'c22')
    for why,(plant,_text) in EMU_PLANTS.items():emu_planted(FW/'tools/phone_pins.py',why,ED/'releases.json',zips,'c22',plant)
    # The superseded TMG12 emulator-only candidates 1 to 3 (written out by hand): valid 1.0.6.11 builds, so neither the
    # base nor their bytes refuse them under another label. Each is refused by its pin before its ZIP is read (the
    # path given does not exist), in release_pins and in --resolve; C22 itself resolves.
    superseded=('eacb5dcabc513570978edc31a47d3304b2bc361036d5b171e15bd4c3c281e9b5',
                'a8b9de49f2d5dc45311c5b19d61f96d9cc1acb2ed81ab55fb14534c0b68ad849',
                '007f1dd77b5b93eba3451e4df2ca6ba18264cee1444d9b97b40355b60f103325')
    assert set(superseded)==set(pp.SUPERSEDED_ZIPS)
    for sha in superseded:
        old=copy.deepcopy(c22);old['firmware']='TMG13';old['zip']={'input':'tmg13/StrixOS-1.0.6.11-TurboIO-TMG13-CANDIDATE-NOT-APPROVED.zip','bytes':9549068,'sha256':sha}
        with tempfile.TemporaryDirectory(prefix='phone-pins-old-candidate-') as tmp:
            refused_with(lambda:pp.release_pins('c22',old,Path(tmp)/'missing.zip',build),'superseded candidate '+sha[:8],'this ZIP is superseded')
            refused_with(lambda:pp.resolve(old,tmp,'c22',build),'superseded candidate '+sha[:8]+' (--resolve)','this ZIP is superseded')
    assert tree_inputs['archive']['sha256'] not in pp.SUPERSEDED_ZIPS
    with tempfile.TemporaryDirectory(prefix='phone-pins-resolve-') as tmp:
        target=Path(tmp)/c22['zip']['input'];target.parent.mkdir(parents=True);shutil.copyfile(c21_zip,target)
        assert pp.resolve(c22,tmp,'c22',build)==target
    # releases.json validation.
    data=json.loads((ED/'releases.json').read_text())
    def bad_releases(mutate,why):
        d=copy.deepcopy(data);mutate(d)
        with tempfile.NamedTemporaryFile('w',suffix='.json',delete=False) as f:json.dump(d,f)
        try:refused(lambda:pp.load_releases(f.name),why)
        finally:Path(f.name).unlink()
    for i in (0,1):
        bad_releases(lambda d:d['releases']['c22']['packages'][i]['zip'].update(input='/abs/zip'),'absolute ZIP path')
        bad_releases(lambda d:d['releases']['c22']['packages'][i]['zip'].update(input='../zip'),'parent ZIP path')
        bad_releases(lambda d:d['releases']['c22']['packages'][i]['zip'].update(sha256='X'*64),'malformed SHA-256')
    # The packages: one TMG build first, then at most the base's stock package; labels as above; distinct ZIPs; the
    # single-package keys of the old schema are refused.
    P=lambda d:d['releases']['c22']['packages']
    bad_releases(lambda d:P(d).reverse(),'stock package first')
    bad_releases(lambda d:P(d).pop(0),'stock package only')
    bad_releases(lambda d:P(d).clear(),'no package')
    bad_releases(lambda d:P(d).append(copy.deepcopy(P(d)[1])),'three packages')
    bad_releases(lambda d:P(d).__setitem__(1,{**copy.deepcopy(P(d)[0]),'label':'TMG13'}),'two TMG packages')
    bad_releases(lambda d:P(d)[1].update(label='STOCK-1.0.5.12'),'a stock package of another base')
    bad_releases(lambda d:P(d)[1].update(label='RECOVERY'),'an unknown label')
    bad_releases(lambda d:P(d)[1].update(zip=copy.deepcopy(P(d)[0]['zip'])),'two packages with one ZIP')
    bad_releases(lambda d:d['releases']['c22'].update(packages=P(d)[0]),'packages not a list')
    for old,value in (('firmware','TMG12'),('zip',{'input':'x.zip','bytes':1,'sha256':'0'*64}),('acceptCurrent',['1.0.5.12'])):
        bad_releases(lambda d:d['releases']['c22'].update({old:value}),'the old top-level '+old)
    # One package (TMG only) is still valid input.
    one=copy.deepcopy(data);one['releases']['c22']['packages']=one['releases']['c22']['packages'][:1]
    with tempfile.NamedTemporaryFile('w',suffix='.json',delete=False) as f:json.dump(one,f)
    try:assert [p['firmware'] for p in pp.packages(pp.load_releases(f.name)['c22'])]==['TMG13']
    finally:Path(f.name).unlink()
    # The only host a release may list is the 1.0.21 full host.
    for hosts in (['107'],['1011-full'],['107','1011-full'],['1021'],['1021-full','1011-full'],['1021-full','1021-full'],['1031-full'],[],'1021-full'):
        bad_releases(lambda d:d['releases']['c22'].update(hosts=hosts),'hosts '+repr(hosts))
    # The only stock base a release may have is 1.0.6.11.
    for base in ('1.0.5.12','1.0.5.5','1.0.6.12'):bad_releases(lambda d:d['releases']['c22'].update(stockBase=base),'stock base '+base)
    for i in (0,1):
        bad_releases(lambda d:P(d)[i].update(acceptCurrent=['1.0.5.12','1.0.5.12']),'duplicate accepted version')
        bad_releases(lambda d:P(d)[i].update(acceptCurrent=[]),'no accepted version')
        bad_releases(lambda d:P(d)[i].update(acceptCurrent=['1.0.6']),'malformed accepted version')
    bad_releases(lambda d:P(d)[0].update(label='tmg12'),'malformed firmware label')
    bad_releases(lambda d:d.update(releases={}),'no release')
    bad_releases(lambda d:d.update(schema=2),'another schema')
    for name in ('default','C23','c','c22a','r22'):
        bad_releases(lambda d:d['releases'].update({name:d['releases']['c22']}),'release name '+name)
    # Two releases are valid input (each cN on 1.0.6.11 for 1021-full).
    two=copy.deepcopy(data);two['releases']['c23']=copy.deepcopy(two['releases']['c22'])
    with tempfile.NamedTemporaryFile('w',suffix='.json',delete=False) as f:json.dump(two,f)
    try:assert list(pp.load_releases(f.name))==['c22','c23']
    finally:Path(f.name).unlink()
    # Rendering. One release: one block, selected with no define (the header defines TIO_RELEASE_C22 itself). Its JSON is
    # the default package's pins plus the policy at the top level, as before, and "packages" with both entries; there is
    # no firmware-pins.json.
    computed={'c22':[(pins,members,policy),(spins,smembers,spolicy)]}
    out=pp.render(releases,computed);header=out['FirmwarePins.h']
    written=json.loads(out['firmware-pins-c22.json'])
    assert set(out)=={'FirmwarePins.h','firmware-pins-c22.json'} and {k:v for k,v in written.items() if k!='packages'}=={**pins,**policy}
    assert [e['name'] for e in written['packages']]==['TMG13','STOCK-1.0.6.11'] and [e['resource'] for e in written['packages']]==['TurboWeReadCandidate.zip','TurboStockFirmware.zip']
    assert written['packages'][0]=={**pins,'kind':'TMG','resource':'TurboWeReadCandidate.zip','otaVersion':policy['otaVersion'],'acceptOsVersions':policy['acceptOsVersions'],'acceptQueryCodes':policy['acceptQueryCodes']}
    assert written['packages'][1]=={**spins,'kind':'STOCK','resource':'TurboStockFirmware.zip','otaVersion':spolicy['otaVersion'],'acceptOsVersions':spolicy['acceptOsVersions'],'acceptQueryCodes':spolicy['acceptQueryCodes']}
    text=header.decode()
    assert text.count('#define TIO_FW_DEFAULT_ZIP_SHA256 @"'+pins['zipSHA256']+'"')==1 and '#define TIO_FW_ZIP_SHA256 ' not in text and '#define TIO_RELEASE_C22 1' in text and '#error' not in text
    assert '#if defined(TIO_RELEASE_C22)' in text and '#define TIO_FW_RELEASE @"c22"' in text and '#define TIO_FW_PACKAGE_COUNT 2u' in text
    assert '#define TIO_FW_OTA_VERSION @"Strix OS 1.0.6.11"' in text and '#define TIO_FW_OTA_FOLDER @"Strix_OS_1.0.6.11"' in text and '#define TIO_FW_DEFAULT_NAME @"TMG13"' in text
    assert '#define TIO_FW_RELEASE_MARKER "ota release=c22; firmware=TMG13; zip='+pins['zipSHA256']+'; accepts Strix OS 1.0.5.12, Strix OS 1.0.6.11; target Strix OS 1.0.6.11; package=STOCK-1.0.6.11; zip='+spins['zipSHA256']+'; accepts Strix OS 1.0.5.12, Strix OS 1.0.6.11; target Strix OS 1.0.6.11"' in text
    package_line=[line for line in text.splitlines() if line.startswith('#define TIO_FW_PACKAGES ')]
    assert len(package_line)==1 and package_line[0].count('@"memberPins":@{')==2 and package_line[0].index('@"name":@"TMG13"')<package_line[0].index('@"name":@"STOCK-1.0.6.11"')
    for entry_members in (members,smembers):
        for name,(size,digest) in entry_members.items():assert '@"%s":@[@%d,@"%s"]'%(name,size,digest) in package_line[0],name
    assert preprocess(header,[])[:2]==(0,'RELEASE_IS @"c22"') and preprocess(header,['-DTIO_RELEASE_C22=1'])[:2]==(0,'RELEASE_IS @"c22"')
    # Two releases: one block each in order, no define is a compile error, and so are two defines.
    two_releases={'c22':c22,'c23':{**copy.deepcopy(c22),'builds':'fixture'}}
    out2=pp.render(two_releases,{'c22':[(pins,members,{**policy,'release':'c22'})],'c23':[(pins,members,{**policy,'release':'c23'})]})
    text2=out2['FirmwarePins.h'].decode()
    assert set(out2)=={'FirmwarePins.h','firmware-pins-c22.json','firmware-pins-c23.json'}
    assert '#define TIO_RELEASE_' not in text2 and '#error "more than one TIO_RELEASE_<NAME> defined"' in text2 and '#error "several releases: define one TIO_RELEASE_<NAME>"' in text2
    assert text2.index('#if defined(TIO_RELEASE_C22)')<text2.index('#elif defined(TIO_RELEASE_C23)')
    assert preprocess(out2['FirmwarePins.h'],['-DTIO_RELEASE_C23=1'])[:2]==(0,'RELEASE_IS @"c23"')
    for defines,why in (([],'several releases'),(['-DTIO_RELEASE_C22=1','-DTIO_RELEASE_C23=1'],'more than one')):
        code,_line,err=preprocess(out2['FirmwarePins.h'],defines)
        if code==0 or why not in err:raise SystemExit('two releases with '+repr(defines)+' did not fail with '+why+': '+err)
    # --write, --resolve and --verify in a copy of the inputs; unknown release names and package labels are refused.
    with tempfile.TemporaryDirectory(prefix='phone-pins-c22-') as tmp:
        tmp=Path(tmp);inputs=tmp/'inputs'
        target=inputs/c22['zip']['input'];target.parent.mkdir(parents=True);shutil.copyfile(c21_zip,target)
        stock_target=inputs/stock21['zip']['input'];stock_target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(stock21_zip,stock_target)
        out_dir=tmp/'out'
        # --resolve prints the first package's path, and --package names the other one.
        for argv,want in ((['--resolve','c22'],target),(['--resolve','c22','--package','STOCK-1.0.6.11'],stock_target),(['--resolve','c22','--package','TMG13'],target)):
            printed=io.StringIO()
            with contextlib.redirect_stdout(printed),contextlib.redirect_stderr(io.StringIO()):assert pp.main(['--inputs',str(inputs),*argv])==0,argv
            assert printed.getvalue()==str(want)+'\n',(argv,printed.getvalue())
        with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
            assert pp.main(['--inputs',str(inputs),'--write',str(out_dir)])==0
            assert pp.main(['--verify','c22','--zip',str(target),'--dir',str(out_dir)])==0
            assert pp.main(['--verify','c22','--package','STOCK-1.0.6.11','--zip',str(stock_target),'--dir',str(out_dir)])==0
            # Each ZIP only as its own package; an unknown label, or --package without --resolve/--verify, is refused.
            assert pp.main(['--verify','c22','--zip',str(stock_target),'--dir',str(out_dir)])==1
            assert pp.main(['--verify','c22','--package','STOCK-1.0.6.11','--zip',str(target),'--dir',str(out_dir)])==1
            for label in ('STOCK-1.0.5.12','TMG11','stock',''):
                assert pp.main(['--inputs',str(inputs),'--resolve','c22','--package',label])==1,label
                assert pp.main(['--verify','c22','--package',label,'--zip',str(stock_target),'--dir',str(out_dir)])==1,label
            assert pp.main(['--inputs',str(inputs),'--package','STOCK-1.0.6.11','--write',str(tmp/'nowhere')])==1 and not (tmp/'nowhere').exists()
            for name in ('c99','c20','default','C22',''):
                assert pp.main(['--inputs',str(inputs),'--resolve',name])==1,name
                assert pp.main(['--verify',name,'--zip',str(target),'--dir',str(out_dir)])==1,name
            # --verify of a changed JSON is refused: a top-level value, or the stock package's entry.
            original=(out_dir/'firmware-pins-c22.json').read_text()
            changed=json.loads(original);changed['feedVersionCode']+=1
            (out_dir/'firmware-pins-c22.json').write_text(json.dumps(changed))
            assert pp.main(['--verify','c22','--zip',str(target),'--dir',str(out_dir)])==1
            changed=json.loads(original);changed['packages'][1]['apMD5']='0'*32
            (out_dir/'firmware-pins-c22.json').write_text(json.dumps(changed))
            assert pp.main(['--verify','c22','--zip',str(target),'--dir',str(out_dir)])==0
            assert pp.main(['--verify','c22','--package','STOCK-1.0.6.11','--zip',str(stock_target),'--dir',str(out_dir)])==1
        assert sorted(p.name for p in out_dir.iterdir())==['FirmwarePins.h','firmware-pins-c22.json']
    # --check: the committed files match; a changed byte or a stale release file (also the old firmware-pins.json) is caught.
    with tempfile.TemporaryDirectory(prefix='phone-pins-') as tmp:
        tmp=Path(tmp);inputs=tmp/'inputs'
        target=inputs/c22['zip']['input'];target.parent.mkdir(parents=True);shutil.copyfile(c21_zip,target)
        stock_target=inputs/stock21['zip']['input'];stock_target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(stock21_zip,stock_target)
        with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
            assert pp.main(['--inputs',str(inputs),'--check',str(ED)])==0
            work=tmp/'out';assert pp.main(['--inputs',str(inputs),'--write',str(work)])==0
            for name in out:assert (work/name).read_bytes()==(ED/name).read_bytes(),name
            changed=bytearray((work/'FirmwarePins.h').read_bytes());changed[-3]^=1;(work/'FirmwarePins.h').write_bytes(changed)
            assert pp.main(['--inputs',str(inputs),'--check',str(work)])==1
            assert pp.main(['--inputs',str(inputs),'--write',str(work)])==0 and pp.main(['--inputs',str(inputs),'--check',str(work)])==0
            for stale in ('firmware-pins-c99.json','firmware-pins.json'):
                (work/stale).write_text('{}');assert pp.main(['--inputs',str(inputs),'--check',str(work)])==1,stale;(work/stale).unlink()
            assert pp.main(['--inputs',str(inputs),'--check',str(work)])==0
            # A release ZIP whose bytes differ from its pin is refused before anything is read from it.
            sraw=stock_target.read_bytes();bad=bytearray(sraw);bad[100]^=1;stock_target.write_bytes(bad)
            assert pp.main(['--inputs',str(inputs),'--check',str(ED)])==1 and pp.main(['--inputs',str(inputs),'--resolve','c22','--package','STOCK-1.0.6.11'])==1
            assert pp.main(['--inputs',str(inputs),'--resolve','c22'])==0
            stock_target.write_bytes(sraw)
            raw=bytearray(target.read_bytes());raw[100]^=1;target.write_bytes(raw)
            assert pp.main(['--inputs',str(inputs),'--check',str(ED)])==1 and pp.main(['--inputs',str(inputs),'--resolve','c22'])==1
    print('PASS phone pins: version strings, C22 (TMG13 on 1.0.6.11, 1021-full) and its policy, its two packages (TMG13 default, STOCK-1.0.6.11 equal to the stock ZIP in every member and the manifest; a changed stock member, AP or manifest, the TMG ZIP under the STOCK label, the stock ZIP under a TMG label and unknown labels refused; --resolve/--verify --package), ZIP size/SHA-256/base/stock-member/tree checks, emulator-only refusals in every mode (base mode on a fixture build.py), superseded TMG13 candidates refused by pin, releases.json validation (cN names, 1021-full only, 1.0.6.11 only), one block per release with the single release chosen without a define and several releases needing one, --check catches changed and stale outputs')
if __name__=='__main__':main()
