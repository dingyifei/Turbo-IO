"""The phone pin generator (tools/phone_pins.py): version strings, release validation, the stock-base and tree checks,
the emulator-only and superseded-ZIP refusals, rendering, and --check catching a changed or stale output.
Usage: phone_pins_test.py ZIP [ZIP ...] (release ZIPs in any order; a release ZIP not given is read from $TURBO_INPUTS
at its releases.json path). The ZIP the tree builds (build-inputs.json archive) must be one of them, either given or
pinned by a release: today it is C21's ZIP. $TURBO_INPUTS must be set: the stock 1.0.6.11 ZIP is read from there."""
from pathlib import Path
import contextlib,copy,hashlib,importlib.util,io,json,os,shutil,subprocess,sys,tempfile,zipfile
FW=Path(__file__).resolve().parents[1]
ED=FW.parent/'official-addon'/'ios107-edition'
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
    # 1.0.5.12 ZIP itself), or another base's cores in the 1.0.6.11 shape (the C21 ZIP with the stock 1.0.5.12 cores).
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
        # is C21's ZIP), except where a plant makes the release that record or that label.
        tree=json.loads((FW/'build-inputs.json').read_text());tree['emuOnly']=True;tree['archive']={**tree['archive'],'sha256':'0'*64}
        (fw/'RELEASE').write_text('TMG99\n')
        data=json.loads(Path(releases_file).read_text());spec=data['releases'][name]
        source=zips[spec['zip']['sha256']]
        if plant=='label':spec['firmware']='TMG99'
        if plant=='record':tree['archive']={**tree['archive'],'sha256':spec['zip']['sha256'],'bytes':spec['zip']['bytes']}
        if plant=='name':spec['zip']['input']='tmg99/StrixOS-1.0.6.11-TurboIO-TMG99-EMU-ONLY-NOT-FOR-DEVICE.zip'
        inputs=tmp/'inputs'
        if plant in ('shape','cores'):
            raw=emu_stand_in(plant,source,load(FW/'build.py','phone_pins_plant_build_'+plant))   # the real tree's stock ZIP paths
            spec['firmware']='TMG98';spec['zip']={'input':'tmg98/StrixOS-1.0.6.11-TurboIO-TMG98-CANDIDATE-NOT-APPROVED.zip',
                'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
            (inputs/'tmg98').mkdir(parents=True);(inputs/spec['zip']['input']).write_bytes(raw)
        data['releases']={name:spec}
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
    for spec in releases.values():
        if spec['zip']['sha256'] not in zips:
            p=Path(os.environ['TURBO_INPUTS'])/spec['zip']['input']
            if p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==spec['zip']['sha256']:zips[spec['zip']['sha256']]=p
    def zip_of(spec):return zips[spec['zip']['sha256']]
    tree_inputs=json.loads((FW/'build-inputs.json').read_text());tree_label=pp.release_label()
    tree_zip=zips.get(tree_inputs['archive']['sha256'])
    if tree_zip is None:raise SystemExit('give the ZIP the tree builds (build-inputs.json archive) as an argument')
    build=pp.load_build()
    stock1611=build.stock_zip_path('1.0.6.11');stock10512=build.stock_zip_path('1.0.5.12');stock1055=build.stock_zip_path('1.0.5.5')
    # The one release, written out by hand: C21, TMG12 on stock 1.0.6.11 (the tree's own ZIP), for the 1.0.21 full host.
    assert list(releases)==['c21'],list(releases)
    c21=releases['c21'];c21_zip=zip_of(c21)
    assert (c21['firmware'],c21['stockBase'],c21['hosts'],c21['acceptCurrent'])==('TMG12','1.0.6.11',['1021-full'],['1.0.5.12','1.0.6.11'])
    assert (c21['zip']['bytes'],c21['zip']['sha256'])==(9549211,'3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373')
    assert c21_zip==tree_zip and (tree_label,tree_inputs['stockBase'])==('TMG12','1.0.6.11')
    # Version strings, written out by hand.
    assert pp.query_code('1.0.5.12')=='01.00.05.0012' and pp.query_code('1.0.5.5')=='01.00.05.0005' and pp.query_code('1.0.6.11')=='01.00.06.0011'
    assert pp.feed_version_name('1.0.6.11')=='0100060011' and pp.feed_version_name('1.0.5.12')=='0100050012'
    assert pp.os_version('1.0.6.11')=='Strix OS 1.0.6.11'
    for bad in ('1.0.5','1.0.5.12.1','v1.0.5.5','1.0.5.x','',None):refused(lambda:pp.version_parts(bad),'version '+repr(bad))
    # C21's own ZIP passes and yields this policy, with 17 member pins (16 payloads and the manifest) and 16 manifest rows.
    pins,members,policy=pp.release_pins('c21',c21,c21_zip,build)
    assert (pins['name'],policy['release'],policy['stockBase'],policy['otaVersion'],policy['folder'],policy['feedVersionName'],policy['feedVersionCode'])==('TMG12','c21','1.0.6.11','Strix OS 1.0.6.11','Strix_OS_1.0.6.11','0100060011',100060011)
    assert policy['acceptOsVersions']==['Strix OS 1.0.5.12','Strix OS 1.0.6.11'] and policy['acceptQueryCodes']==['01.00.05.0012','01.00.06.0011']
    assert len(members)==17 and 'OtaFileInfo.json' in members and 'nuttx_ota.bin' in members and 'amap_rtos_sdk' in members and 'rives.bin' not in members
    with zipfile.ZipFile(c21_zip) as z:assert len(json.loads(z.read('OtaFileInfo.json')))==16 and len(z.namelist())==17
    assert members['nuttx_ap.bin']==[pins['apBytes'],pins['apSHA256']]==[tree_inputs['APBytes'],tree_inputs['APSHA256']]
    # The ZIP must be the pinned one: another file, a wrong size or a wrong SHA-256 is refused, in release_pins and in resolve.
    refused_with(lambda:pp.release_pins('c21',c21,stock1611,build),'c21 with the stock 1.0.6.11 ZIP','ZIP does not match releases.json')
    for key,value in (('bytes',c21['zip']['bytes']+1),('sha256','0'*64)):
        wrong=copy.deepcopy(c21);wrong['zip'][key]=value
        refused_with(lambda:pp.release_pins('c21',wrong,c21_zip,build),'c21 with a wrong '+key,'ZIP does not match releases.json')
        with tempfile.TemporaryDirectory(prefix='phone-pins-pin-') as tmp:
            target=Path(tmp)/c21['zip']['input'];target.parent.mkdir(parents=True);shutil.copyfile(c21_zip,target)
            refused_with(lambda:pp.resolve(wrong,tmp,'c21',build),'c21 with a wrong '+key+' (--resolve)','release ZIP does not match its pin')
    # Another stock base: the ZIP's own shape and cores are 1.0.6.11, so its bytes refuse it.
    for base in ('1.0.5.12','1.0.5.5'):
        wrong=copy.deepcopy(c21);wrong['stockBase']=base
        refused_with(lambda:pp.release_pins('c21',wrong,c21_zip,build),'c21 on stock '+base,'not a build on stock '+base)
    # The tree's label must be carried by the tree's own ZIP.
    tree={'archive':{'sha256':'0'*64},'stockBase':c21['stockBase']}
    refused_with(lambda:pp.release_pins('c21',c21,c21_zip,build,tree,c21['firmware']),'c21 named as the tree release with another ZIP','is the tree label but this is not the ZIP')
    # Every member but AP must be the stock 1.0.6.11 member: one changed byte in images.bin (manifest rewritten to match,
    # so only the stock comparison can refuse it), under another label so the tree check does not decide it.
    with zipfile.ZipFile(c21_zip) as z:images=bytearray(z.read('images.bin'))
    images[len(images)//2]^=1
    with tempfile.TemporaryDirectory(prefix='phone-pins-member-') as tmp:
        raw=rewrite_zip(c21_zip.read_bytes(),{'images.bin':bytes(images)});path=Path(tmp)/'member.zip';path.write_bytes(raw)
        changed=copy.deepcopy(c21);changed['firmware']='TMG98';changed['zip']={'input':'tmg98/x.zip','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
        refused_with(lambda:pp.release_pins('c21',changed,path,build),'a non-stock images.bin','images.bin is not the stock 1.0.6.11 member')
    # An emulator-only build is never a phone release. Each probe is refused with its own message, and the same inputs
    # without the emuOnly condition are accepted (the ZIP and label probes use c21, the real release).
    real_tree={'archive':{'sha256':'0'*64},'stockBase':c21['stockBase']}
    pp.release_pins('c21',c21,c21_zip,build,real_tree,'TMG99')
    with tempfile.TemporaryDirectory(prefix='phone-pins-no-phone-') as tmp:
        refused_with(lambda:pp.release_pins('c21',c21,c21_zip,no_phone_build(tmp)),'a stock base with no phone release','has no phone release')
    # A ZIP of another base listed under 1.0.6.11 is refused by its own bytes: the stock 1.0.5.12 package.
    old_shape=copy.deepcopy(c21);old_shape['firmware']='TMG98';raw=stock10512.read_bytes()
    old_shape['zip']={'input':'tmg98/x.zip','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
    refused_with(lambda:pp.release_pins('c21',old_shape,stock10512,build),'a 1.0.5.12 ZIP listed under 1.0.6.11','not a build on stock 1.0.6.11')
    emu_tree={'archive':{'sha256':c21['zip']['sha256']},'stockBase':c21['stockBase'],'emuOnly':True}
    refused_with(lambda:pp.release_pins('c21',c21,c21_zip,build,{**emu_tree,'archive':{'sha256':'0'*64}},c21['firmware']),'the label of an emuOnly tree','label of an emuOnly tree')
    refused_with(lambda:pp.release_pins('c21',c21,c21_zip,build,emu_tree,'TMG99'),'the ZIP of an emuOnly tree','ZIP of an emuOnly tree')
    refused_with(lambda:pp.release_pins('c21',c21,c21_zip,build,{**tree_inputs,'emuOnly':True}),'c21 under an emuOnly tree','label of an emuOnly tree')
    emu_name=copy.deepcopy(c21);emu_name['zip']['input']='tmg12/StrixOS-1.0.6.11-TurboIO-TMG12-EMU-ONLY-NOT-FOR-DEVICE.zip'
    refused_with(lambda:pp.release_pins('c21',emu_name,c21_zip,build),'an -EMU-ONLY- input name','-EMU-ONLY-')
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
    # On the real tree, --tree-release names C21.
    out=io.StringIO()
    with contextlib.redirect_stdout(out):assert pp.main(['--tree-release'])==0
    assert out.getvalue()=='c21\n',out.getvalue()
    # Every mode refuses each emulator-only condition on its own, --resolve included; the unplanted copy resolves c21.
    emu_planted(FW/'tools/phone_pins.py',None,ED/'releases.json',zips,'c21')
    for why,(plant,_text) in EMU_PLANTS.items():emu_planted(FW/'tools/phone_pins.py',why,ED/'releases.json',zips,'c21',plant)
    # The superseded TMG12 emulator-only candidates 1 to 3 (written out by hand): valid 1.0.6.11 builds, so neither the
    # base nor their bytes refuse them under another label. Each is refused by its pin before its ZIP is read (the
    # path given does not exist), in release_pins and in --resolve; C21 itself resolves.
    superseded=('eacb5dcabc513570978edc31a47d3304b2bc361036d5b171e15bd4c3c281e9b5',
                'a8b9de49f2d5dc45311c5b19d61f96d9cc1acb2ed81ab55fb14534c0b68ad849',
                '007f1dd77b5b93eba3451e4df2ca6ba18264cee1444d9b97b40355b60f103325')
    assert set(superseded)==set(pp.SUPERSEDED_ZIPS)
    for sha in superseded:
        old=copy.deepcopy(c21);old['firmware']='TMG13';old['zip']={'input':'tmg13/StrixOS-1.0.6.11-TurboIO-TMG13-CANDIDATE-NOT-APPROVED.zip','bytes':9549068,'sha256':sha}
        with tempfile.TemporaryDirectory(prefix='phone-pins-old-candidate-') as tmp:
            refused_with(lambda:pp.release_pins('c21',old,Path(tmp)/'missing.zip',build),'superseded candidate '+sha[:8],'this ZIP is superseded')
            refused_with(lambda:pp.resolve(old,tmp,'c21',build),'superseded candidate '+sha[:8]+' (--resolve)','this ZIP is superseded')
    assert tree_inputs['archive']['sha256'] not in pp.SUPERSEDED_ZIPS
    with tempfile.TemporaryDirectory(prefix='phone-pins-resolve-') as tmp:
        target=Path(tmp)/c21['zip']['input'];target.parent.mkdir(parents=True);shutil.copyfile(c21_zip,target)
        assert pp.resolve(c21,tmp,'c21',build)==target
    # releases.json validation.
    data=json.loads((ED/'releases.json').read_text())
    def bad_releases(mutate,why):
        d=copy.deepcopy(data);mutate(d)
        with tempfile.NamedTemporaryFile('w',suffix='.json',delete=False) as f:json.dump(d,f)
        try:refused(lambda:pp.load_releases(f.name),why)
        finally:Path(f.name).unlink()
    bad_releases(lambda d:d['releases']['c21']['zip'].update(input='/abs/zip'),'absolute ZIP path')
    bad_releases(lambda d:d['releases']['c21']['zip'].update(input='../zip'),'parent ZIP path')
    bad_releases(lambda d:d['releases']['c21']['zip'].update(sha256='X'*64),'malformed SHA-256')
    # The only host a release may list is the 1.0.21 full host.
    for hosts in (['107'],['1011-full'],['107','1011-full'],['1021'],['1021-full','1011-full'],['1021-full','1021-full'],['1031-full'],[],'1021-full'):
        bad_releases(lambda d:d['releases']['c21'].update(hosts=hosts),'hosts '+repr(hosts))
    # The only stock base a release may have is 1.0.6.11.
    for base in ('1.0.5.12','1.0.5.5','1.0.6.12'):bad_releases(lambda d:d['releases']['c21'].update(stockBase=base),'stock base '+base)
    bad_releases(lambda d:d['releases']['c21'].update(acceptCurrent=['1.0.5.12','1.0.5.12']),'duplicate accepted version')
    bad_releases(lambda d:d['releases']['c21'].update(acceptCurrent=[]),'no accepted version')
    bad_releases(lambda d:d['releases']['c21'].update(acceptCurrent=['1.0.6']),'malformed accepted version')
    bad_releases(lambda d:d['releases']['c21'].update(firmware='tmg12'),'malformed firmware label')
    bad_releases(lambda d:d.update(releases={}),'no release')
    bad_releases(lambda d:d.update(schema=2),'another schema')
    for name in ('default','C22','c','c22a','r22'):
        bad_releases(lambda d:d['releases'].update({name:d['releases']['c21']}),'release name '+name)
    # Two releases are valid input (each cN on 1.0.6.11 for 1021-full).
    two=copy.deepcopy(data);two['releases']['c22']=copy.deepcopy(two['releases']['c21'])
    with tempfile.NamedTemporaryFile('w',suffix='.json',delete=False) as f:json.dump(two,f)
    try:assert list(pp.load_releases(f.name))==['c21','c22']
    finally:Path(f.name).unlink()
    # Rendering. One release: one block, selected with no define (the header defines TIO_RELEASE_C21 itself), and its
    # JSON is pins plus policy; there is no firmware-pins.json.
    computed={'c21':(pins,members,policy)}
    out=pp.render(releases,computed);header=out['FirmwarePins.h']
    assert set(out)=={'FirmwarePins.h','firmware-pins-c21.json'} and json.loads(out['firmware-pins-c21.json'])=={**pins,**policy}
    text=header.decode()
    assert text.count('#define TIO_FW_ZIP_SHA256 ')==1 and '#define TIO_RELEASE_C21 1' in text and '#error' not in text
    assert '#if defined(TIO_RELEASE_C21)' in text and '#define TIO_FW_RELEASE @"c21"' in text
    assert '#define TIO_FW_OTA_VERSION @"Strix OS 1.0.6.11"' in text and '#define TIO_FW_OTA_FOLDER @"Strix_OS_1.0.6.11"' in text and '#define TIO_FW_NAME @"TMG12"' in text
    assert '#define TIO_FW_RELEASE_MARKER "ota release=c21; firmware=TMG12; zip='+pins['zipSHA256']+'; accepts Strix OS 1.0.5.12, Strix OS 1.0.6.11; target Strix OS 1.0.6.11"' in text
    member_line=[line for line in text.splitlines() if line.startswith('#define TIO_FW_MEMBER_PINS ')]
    assert len(member_line)==1 and member_line[0].count('@[@')==17
    assert preprocess(header,[])[:2]==(0,'RELEASE_IS @"c21"') and preprocess(header,['-DTIO_RELEASE_C21=1'])[:2]==(0,'RELEASE_IS @"c21"')
    # Two releases: one block each in order, no define is a compile error, and so are two defines.
    two_releases={'c21':c21,'c22':{**copy.deepcopy(c21),'builds':'fixture'}}
    out2=pp.render(two_releases,{'c21':(pins,members,{**policy,'release':'c21'}),'c22':(pins,members,{**policy,'release':'c22'})})
    text2=out2['FirmwarePins.h'].decode()
    assert set(out2)=={'FirmwarePins.h','firmware-pins-c21.json','firmware-pins-c22.json'}
    assert '#define TIO_RELEASE_' not in text2 and '#error "more than one TIO_RELEASE_<NAME> defined"' in text2 and '#error "several releases: define one TIO_RELEASE_<NAME>"' in text2
    assert text2.index('#if defined(TIO_RELEASE_C21)')<text2.index('#elif defined(TIO_RELEASE_C22)')
    assert preprocess(out2['FirmwarePins.h'],['-DTIO_RELEASE_C22=1'])[:2]==(0,'RELEASE_IS @"c22"')
    for defines,why in (([],'several releases'),(['-DTIO_RELEASE_C21=1','-DTIO_RELEASE_C22=1'],'more than one')):
        code,_line,err=preprocess(out2['FirmwarePins.h'],defines)
        if code==0 or why not in err:raise SystemExit('two releases with '+repr(defines)+' did not fail with '+why+': '+err)
    # --write, --resolve and --verify in a copy of the inputs; unknown release names are refused.
    with tempfile.TemporaryDirectory(prefix='phone-pins-c21-') as tmp:
        tmp=Path(tmp);inputs=tmp/'inputs'
        target=inputs/c21['zip']['input'];target.parent.mkdir(parents=True);shutil.copyfile(c21_zip,target)
        out_dir=tmp/'out'
        with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
            assert pp.main(['--inputs',str(inputs),'--write',str(out_dir)])==0
            assert pp.main(['--inputs',str(inputs),'--resolve','c21'])==0
            assert pp.main(['--verify','c21','--zip',str(target),'--dir',str(out_dir)])==0
            for name in ('c99','c20','default','C21',''):
                assert pp.main(['--inputs',str(inputs),'--resolve',name])==1,name
                assert pp.main(['--verify',name,'--zip',str(target),'--dir',str(out_dir)])==1,name
            # --verify of a changed JSON is refused.
            changed=json.loads((out_dir/'firmware-pins-c21.json').read_text());changed['feedVersionCode']+=1
            (out_dir/'firmware-pins-c21.json').write_text(json.dumps(changed))
            assert pp.main(['--verify','c21','--zip',str(target),'--dir',str(out_dir)])==1
        assert sorted(p.name for p in out_dir.iterdir())==['FirmwarePins.h','firmware-pins-c21.json']
    # --check: the committed files match; a changed byte or a stale release file (also the old firmware-pins.json) is caught.
    with tempfile.TemporaryDirectory(prefix='phone-pins-') as tmp:
        tmp=Path(tmp);inputs=tmp/'inputs'
        target=inputs/c21['zip']['input'];target.parent.mkdir(parents=True);shutil.copyfile(c21_zip,target)
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
            raw=bytearray(target.read_bytes());raw[100]^=1;target.write_bytes(raw)
            assert pp.main(['--inputs',str(inputs),'--check',str(ED)])==1 and pp.main(['--inputs',str(inputs),'--resolve','c21'])==1
    print('PASS phone pins: version strings, C21 (TMG12 on 1.0.6.11, 1021-full) and its policy, ZIP size/SHA-256/base/stock-member/tree checks, emulator-only refusals in every mode (base mode on a fixture build.py), superseded TMG12 candidates refused by pin, releases.json validation (cN names, 1021-full only, 1.0.6.11 only), one block per release with the single release chosen without a define and several releases needing one, --check catches changed and stale outputs')
if __name__=='__main__':main()
