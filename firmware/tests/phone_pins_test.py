"""The phone pin generator (tools/phone_pins.py): version strings, release validation, the stock-base and tree checks,
and --check catching a changed or stale output. Usage: phone_pins_test.py ZIP [ZIP ...] (release ZIPs in any order; a release ZIP not given is read from $TURBO_INPUTS at its releases.json path; the ZIP the tree builds must be one of the arguments unless a release in releases.json pins it)."""
from pathlib import Path
import contextlib,copy,hashlib,importlib.util,io,json,os,shutil,sys,tempfile,zipfile
FW=Path(__file__).resolve().parents[1]
ED=FW.parent/'official-addon'/'ios107-edition'
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
# Each planted emulator-only condition, refused by every mode of a throwaway copy of the tool (emuOnly tree, label in
# its own RELEASE, releases.json and the release ZIP copied under its own inputs). --resolve must refuse it on its own,
# with no path printed; --write must leave no output folder. tool is the phone_pins.py under test, zips maps SHA-256
# to release ZIP.
EMU_PLANTS={
    'a release carrying the emuOnly tree label':('label',"label of an emuOnly tree"),
    'a release that is the emuOnly tree build record':('record',"ZIP of an emuOnly tree"),
    'a release ZIP with the -EMU-ONLY- name':('name',"an -EMU-ONLY- ZIP cannot be a phone release"),
    'a release on a stock base with no phone release':('base',"has no phone release"),
    # An older emulator-only ZIP after the tree is repinned: plain name, another label, not the tree record, listed
    # under a phone base. Only its own bytes give it away: the 1.0.6.11 package shape, or 1.0.6.11 cores in the
    # 1.0.5.12 shape (stand-ins built from the stock 1.0.6.11 ZIP).
    'an older emulator-only ZIP with the 1.0.6.11 shape':('shape',"the ZIP is not a build on stock 1.0.5.12"),
    'an older emulator-only ZIP with 1.0.6.11 cores':('cores',"the ZIP is not a build on stock 1.0.5.12"),
}
NO_PHONE_FROM="'container': 'canonical-members', 'phoneRelease': True,"
def no_phone_build_source():
    """build.py with stock 1.0.6.11 marked as a base with no phone release: the fixture for the emulator-only mode, which
    the real tree no longer uses (1.0.6.11 became a phone release base with the TMG12 release build)."""
    text=(FW/'build.py').read_text()
    if text.count(NO_PHONE_FROM)!=1:raise SystemExit('build.py: the 1.0.6.11 shape line for the no-phone fixture is not found exactly once')
    return text.replace(NO_PHONE_FROM,NO_PHONE_FROM.replace('True','False'))
def no_phone_build(tmp):
    (Path(tmp)/'build.py').write_text(no_phone_build_source());module=load(Path(tmp)/'build.py','phone_pins_no_phone_build')
    assert not module.package_shape('1.0.6.11')['phoneRelease'];return module
def emu_stand_in(plant,c18_zip):
    """The bytes of an emulator-only stand-in: the stock 1.0.6.11 ZIP itself, or the c18 ZIP with AP, APC1 and BTH
    replaced by the stock 1.0.6.11 cores and its manifest rows rewritten to match."""
    if not os.environ.get('TURBO_INPUTS'):raise SystemExit('TURBO_INPUTS is not set: the emulator-only plants need the stock 1.0.6.11 ZIP')
    stock=load(FW/'build.py','phone_pins_test_build').stock_zip_path('1.0.6.11').read_bytes()
    if plant=='shape':return stock
    cores=('nuttx_ap.bin','nuttx_apc1.bin','nuttx_bth.bin');out=io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(stock)) as emu,zipfile.ZipFile(c18_zip) as src,zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as dst:
        rows=json.loads(src.read('OtaFileInfo.json'))
        for r in rows:
            if r['Name'] in cores:data=emu.read(r['Name']);r['Size']=len(data);r['Md5']=hashlib.md5(data).hexdigest()
        dst.writestr('OtaFileInfo.json',json.dumps(rows))
        for n in src.namelist():
            if n!='OtaFileInfo.json':dst.writestr(n,emu.read(n) if n in cores else src.read(n))
    return out.getvalue()
def emu_planted(tool,why,releases_file,zips,plant=None):
    with tempfile.TemporaryDirectory(prefix='phone-pins-plant-') as tmp:
        tmp=Path(tmp);fw=tmp/'fw';(fw/'tools').mkdir(parents=True)
        shutil.copy(tool,fw/'tools/phone_pins.py');(fw/'build.py').write_text(no_phone_build_source())
        tree=json.loads((FW/'build-inputs.json').read_text());tree['emuOnly']=True
        (fw/'RELEASE').write_text('TMG99\n')
        data=json.loads(Path(releases_file).read_text());spec=data['releases']['c18']
        if plant=='label':spec['firmware']='TMG99'
        if plant=='record':tree['archive']={**tree['archive'],'sha256':spec['zip']['sha256'],'bytes':spec['zip']['bytes']}
        if plant=='name':spec['zip']['input']='tmg99/StrixOS-1.0.5.12-TurboIO-TMG99-EMU-ONLY-NOT-FOR-DEVICE.zip'
        if plant=='base':spec['stockBase']='1.0.6.11';spec['hosts']=['1021-full']   # the one host a 1.0.6.11 release may list
        if plant in ('shape','cores'):
            raw=emu_stand_in(plant,zips[spec['zip']['sha256']])
            spec['firmware']='TMG98';spec['zip']={'input':'tmg98/StrixOS-1.0.5.12-TurboIO-TMG98-CANDIDATE-NOT-APPROVED.zip',
                'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}
            assert spec['zip']['sha256']!=tree['archive']['sha256']
            (tmp/'inputs'/'tmg98').mkdir(parents=True);(tmp/'inputs'/spec['zip']['input']).write_bytes(raw)
        data['releases']={'c18':spec,**data['releases']}  # c18 first, so --write and --check reach it before any stock ZIP
        (fw/'build-inputs.json').write_text(json.dumps(tree));(tmp/'releases.json').write_text(json.dumps(data))
        inputs=tmp/'inputs';target=inputs/spec['zip']['input']
        for other in data['releases'].values():
            t=inputs/other['zip']['input']
            if not t.exists():t.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(zips[other['zip']['sha256']],t)
        copy_pp=load(fw/'tools/phone_pins.py','phone_pins_plant_'+(plant or 'none'))
        def run(*argv):
            out,err=io.StringIO(),io.StringIO()
            with contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):code=copy_pp.main(['--releases',str(tmp/'releases.json'),*argv])
            return code,out.getvalue(),err.getvalue()
        code,out,err=run('--resolve','c18','--inputs',str(inputs))
        if plant is None:
            if (code,out)!=(0,str(target)+'\n'):raise SystemExit('refused without a plant: '+err)
            return
        text=EMU_PLANTS[why][1]
        if code==0 or out or text not in err:raise SystemExit('--resolve accepted '+why+': exit %d, %r %r'%(code,out,err))
        code,out,err=run('--verify','c18','--zip',str(target),'--dir',str(ED))
        if code==0 or text not in err:raise SystemExit('--verify accepted '+why+': '+err)
        for mode in ('--write','--check'):
            dest=tmp/('out'+mode)
            code,out,err=run('--inputs',str(inputs),mode,str(dest))
            if code==0 or text not in err or dest.exists():raise SystemExit(mode+' accepted '+why+': '+err)
def main():
    pp=load(FW/'tools/phone_pins.py','phone_pins_under_test')
    zips={hashlib.sha256(Path(p).read_bytes()).hexdigest():Path(p) for p in sys.argv[1:]}
    releases=pp.load_releases(ED/'releases.json')
    by_sha={s['zip']['sha256']:n for n,s in releases.items()}
    for spec in releases.values():
        if spec['zip']['sha256'] not in zips and os.environ.get('TURBO_INPUTS'):
            p=Path(os.environ['TURBO_INPUTS'])/spec['zip']['input']
            if p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==spec['zip']['sha256']:zips[spec['zip']['sha256']]=p
    def zip_of(spec):return zips[spec['zip']['sha256']]
    zip9=zips['def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd']
    zip10=zips['4a5973636329e8863a8ab7aaea4050a35d964916c3b125f63242b384e018cb6c']
    zip11=zips['edb73a6458b80e57e9bdcb0c1cd068c040b945702c1f096be4b187013cf334e1']
    tree_inputs=json.loads((FW/'build-inputs.json').read_text());tree_label=pp.release_label()
    tree_zip=zips.get(tree_inputs['archive']['sha256'])
    if tree_zip is None:raise SystemExit('give the ZIP the tree builds (build-inputs.json archive) as an argument: the c20 fixture needs it')
    assert set(by_sha.values())<=set(releases) and set(releases) in ({'default','c16','c17','c18'},{'default','c16','c17','c18','c20'})
    # Version strings, written out by hand.
    assert pp.query_code('1.0.5.12')=='01.00.05.0012' and pp.query_code('1.0.5.5')=='01.00.05.0005' and pp.query_code('1.0.4.12')=='01.00.04.0012'
    assert pp.feed_version_name('1.0.5.12')=='0100050012' and pp.feed_version_name('1.0.5.5')=='0100050005'
    assert pp.os_version('1.0.5.12')=='Strix OS 1.0.5.12'
    for bad in ('1.0.5','1.0.5.12.1','v1.0.5.5','1.0.5.x','',None):refused(lambda:pp.version_parts(bad),'version '+repr(bad))
    build=pp.load_build()
    # Each release: its own ZIP passes and yields the policy below; any other ZIP or base is refused.
    want={'default':('TMG9','Strix OS 1.0.5.5','Strix_OS_1.0.5.5',['01.00.04.0012','01.00.05.0005']),
          'c16':('TMG10','Strix OS 1.0.5.12','Strix_OS_1.0.5.12',['01.00.05.0005','01.00.05.0012']),
          'c17':('TMG9','Strix OS 1.0.5.5','Strix_OS_1.0.5.5',['01.00.05.0012']),
          'c18':('TMG11','Strix OS 1.0.5.12','Strix_OS_1.0.5.12',['01.00.05.0012']),
          }
    if 'c20' in releases:
        # TMG12 on 1.0.6.11. Its accepted versions are the owner's choice, so they are read from releases.json and
        # converted here by hand (the converter itself is checked above and by the other releases' rows).
        hand=lambda v:'%02d.%02d.%02d.%04d'%tuple(int(x) for x in v.split('.'))
        want['c20']=('TMG12','Strix OS 1.0.6.11','Strix_OS_1.0.6.11',[hand(v) for v in releases['c20']['acceptCurrent']])
    member_count={'1.0.5.5':16,'1.0.5.12':16,'1.0.6.11':17}   # payloads + OtaFileInfo.json, written out by hand
    for name,spec in releases.items():
        own=zip_of(spec);other=zip9 if own!=zip9 else zip10
        pins,members,policy=pp.release_pins(name,spec,own,build)
        assert (pins['name'],policy['otaVersion'],policy['folder'],policy['acceptQueryCodes'])==want[name],name
        assert len(members)==member_count[spec['stockBase']] and members['nuttx_ap.bin']==[pins['apBytes'],pins['apSHA256']]
        refused(lambda:pp.release_pins(name,spec,other,build),name+' with the other ZIP')
        wrong=copy.deepcopy(spec);wrong['stockBase']='1.0.5.5' if spec['stockBase']=='1.0.5.12' else '1.0.5.12'
        refused(lambda:pp.release_pins(name,wrong,own,build),name+' on the other stock base')
        # The tree's label must be carried by the tree's own ZIP.
        tree={'archive':{'sha256':'0'*64},'stockBase':spec['stockBase']}
        refused(lambda:pp.release_pins(name,spec,own,build,tree,spec['firmware']),name+' named as the tree release with another ZIP')
    # An emulator-only build is never a phone release. Each probe is refused with its own message, and the same
    # inputs without the emuOnly condition are accepted (the ZIP and label probes use c18, a real release).
    c18=releases['c18'];c18_zip=zip_of(c18);real_tree={'archive':{'sha256':c18['zip']['sha256']},'stockBase':c18['stockBase']}
    pp.release_pins('c18',c18,c18_zip,build,real_tree,'TMG99')
    shape_base=copy.deepcopy(c18);shape_base['stockBase']='1.0.6.11'
    with tempfile.TemporaryDirectory(prefix='phone-pins-no-phone-') as tmp:
        refused_with(lambda:pp.release_pins('c18',shape_base,c18_zip,no_phone_build(tmp)),'a stock base with no phone release','has no phone release')
    # On the real build 1.0.6.11 is a phone release base, and a 1.0.5.12 ZIP listed under it is still refused by its bytes.
    refused_with(lambda:pp.release_pins('c18',shape_base,c18_zip,build),'a 1.0.5.12 ZIP listed under 1.0.6.11','not a build on stock 1.0.6.11')
    emu_tree={**real_tree,'emuOnly':True}
    refused_with(lambda:pp.release_pins('c18',c18,c18_zip,build,{**emu_tree,'archive':{'sha256':'0'*64}},c18['firmware']),'the label of an emuOnly tree','label of an emuOnly tree')
    refused_with(lambda:pp.release_pins('c18',c18,c18_zip,build,emu_tree,'TMG99'),'the ZIP of an emuOnly tree','ZIP of an emuOnly tree')
    emu_name=copy.deepcopy(c18);emu_name['zip']['input']='tmg12/StrixOS-1.0.5.12-TurboIO-TMG12-EMU-ONLY-NOT-FOR-DEVICE.zip'
    refused_with(lambda:pp.release_pins('c18',emu_name,c18_zip,build),'an -EMU-ONLY- input name','-EMU-ONLY-')
    refused_with(lambda:pp.pins_for(zip9,'TMG9','1.0.6.11'),'a 1.0.5.5 ZIP read with the 1.0.6.11 package shape','payload manifest rows')
    # Same row count, one payload renamed (in the ZIP and its manifest): only the payload-name check can refuse it.
    with tempfile.TemporaryDirectory(prefix='phone-pins-names-') as tmp:
        renamed=Path(tmp)/'renamed.zip'
        with zipfile.ZipFile(zip11) as src,zipfile.ZipFile(renamed,'w',zipfile.ZIP_DEFLATED) as dst:
            rows=json.loads(src.read('OtaFileInfo.json'));assert any(r['Name']=='rives.bin' for r in rows)
            for r in rows:
                if r['Name']=='rives.bin':r['Name']='rivez.bin'
            dst.writestr('OtaFileInfo.json',json.dumps(rows))
            for n in src.namelist():
                if n!='OtaFileInfo.json':dst.writestr('rivez.bin' if n=='rives.bin' else n,src.read(n))
        refused_with(lambda:pp.pins_for(renamed,'TMG11','1.0.5.12'),'a ZIP with a renamed payload, same row count','payload names are not the stock')
    # --tree-release on an emuOnly tree: refused before any release lookup (a throwaway copy of the tool and build.py
    # whose build-inputs.json says emuOnly; the releases file it is given does not exist, so a lookup would fail differently).
    with tempfile.TemporaryDirectory(prefix='phone-pins-emu-') as tmp:
        tmp=Path(tmp);(tmp/'tools').mkdir()
        shutil.copy(FW/'tools/phone_pins.py',tmp/'tools');shutil.copy(FW/'build.py',tmp)
        (tmp/'build-inputs.json').write_text(json.dumps({**json.loads((FW/'build-inputs.json').read_text()),'emuOnly':True}))
        copy_pp=load(tmp/'tools/phone_pins.py','phone_pins_emu_copy');err=io.StringIO()
        with contextlib.redirect_stderr(err):code=copy_pp.main(['--tree-release','--releases',str(tmp/'missing.json')])
        assert code==1 and '--tree-release: emuOnly tree has no phone release' in err.getvalue(),err.getvalue()
    # Every mode refuses each emulator-only condition on its own, --resolve included; the unplanted copy resolves c18.
    emu_planted(FW/'tools/phone_pins.py',None,ED/'releases.json',zips)
    for why,(plant,_text) in EMU_PLANTS.items():emu_planted(FW/'tools/phone_pins.py',why,ED/'releases.json',zips,plant)
    # releases.json validation.
    data=json.loads((ED/'releases.json').read_text())
    def bad_releases(mutate,why):
        d=copy.deepcopy(data);mutate(d)
        with tempfile.NamedTemporaryFile('w',suffix='.json',delete=False) as f:json.dump(d,f)
        try:refused(lambda:pp.load_releases(f.name),why)
        finally:Path(f.name).unlink()
    bad_releases(lambda d:d['releases']['c16']['zip'].update(input='/abs/zip'),'absolute ZIP path')
    bad_releases(lambda d:d['releases']['c16']['zip'].update(input='../zip'),'parent ZIP path')
    bad_releases(lambda d:d['releases']['c16'].update(hosts=['107','1011-full']),'named release on 1.0.7')
    bad_releases(lambda d:d['releases']['c16'].update(hosts=['1011-full','1021-full']),'named release on two full hosts')
    bad_releases(lambda d:d['releases']['c16'].update(hosts=['1021']),'named release on the 1.0.21 download-only host')
    bad_releases(lambda d:d['releases']['c16'].update(hosts=['1031-full']),'named release on an unknown host')
    bad_releases(lambda d:d['releases']['default'].update(hosts=['107','1021-full']),'default release on the 1.0.21 host')
    # Only the 1.0.21 full host flashes a stock 1.0.6.11 package.
    bad_releases(lambda d:d['releases']['c16'].update(stockBase='1.0.6.11'),'a 1.0.6.11 release on the 1.0.11 full host')
    bad_releases(lambda d:d['releases']['default'].update(stockBase='1.0.6.11'),'the default release on 1.0.6.11')
    # A named release on the 1.0.21 full host is accepted (the name turbo-package.sh uses: --host 1021-full), on 1.0.5.12
    # and on 1.0.6.11.
    for base in ('1.0.5.12','1.0.6.11'):
        ok=copy.deepcopy(data);ok['releases']['c16'].update(hosts=['1021-full'],stockBase=base)
        with tempfile.NamedTemporaryFile('w',suffix='.json',delete=False) as f:json.dump(ok,f)
        try:assert pp.load_releases(f.name)['c16']['hosts']==['1021-full']
        finally:Path(f.name).unlink()
    bad_releases(lambda d:d['releases']['c16'].update(acceptCurrent=['1.0.5.5','1.0.5.5']),'duplicate accepted version')
    bad_releases(lambda d:d['releases']['c16'].update(acceptCurrent=[]),'no accepted version')
    bad_releases(lambda d:d['releases'].pop('default'),'no default release')
    bad_releases(lambda d:d['releases'].update(C18=d['releases']['c16']),'bad release name')
    # Rendering: one block per release, the guard against two defines, the default JSON unchanged in form.
    computed={n:pp.release_pins(n,s,zip_of(s),build) for n,s in releases.items()}
    out=pp.render(releases,computed)
    header=out['FirmwarePins.h'].decode()
    named=[n for n in releases if n!='default']
    assert header.count('#define TIO_FW_ZIP_SHA256 ')==len(releases) and '#error "more than one TIO_RELEASE_<NAME> defined"' in header
    marks=[header.index('#if defined(TIO_RELEASE_C16)')]+[header.index('#elif defined(TIO_RELEASE_%s)'%n.upper()) for n in named[1:]]+[header.index('#else')]
    assert named[:3]==['c16','c17','c18'] and marks==sorted(marks)
    assert json.loads(out['firmware-pins.json'])==pp.pins_for(zip9,'TMG9','1.0.5.5')
    assert set(out)=={'FirmwarePins.h','firmware-pins.json'}|{'firmware-pins-%s.json'%n for n in named}
    # A c20-style release in a copy of releases.json: TMG12, the ZIP the tree builds, on stock 1.0.6.11, for the 1.0.21
    # full host. Its pins name OtaVersion "Strix OS 1.0.6.11" and the folder Strix_OS_1.0.6.11, with 17 member pins
    # (16 payloads and the manifest) and 16 manifest rows; the tree check accepts it (the tree's label and ZIP).
    c20={'builds':'C20 fixture','hosts':['1021-full'],'firmware':tree_label,'stockBase':tree_inputs['stockBase'],
         'zip':{'input':'%s/%s'%(tree_label.lower(),build.archive_name()),'bytes':tree_inputs['archive']['bytes'],'sha256':tree_inputs['archive']['sha256']},
         'acceptCurrent':['1.0.5.12','1.0.6.11']}
    assert (c20['firmware'],c20['stockBase'],c20['zip']['input'])==('TMG12','1.0.6.11','tmg12/StrixOS-1.0.6.11-TurboIO-TMG12-CANDIDATE-NOT-APPROVED.zip')
    pins,members,policy=pp.release_pins('c20',c20,tree_zip,build)
    assert (pins['name'],policy['otaVersion'],policy['folder'],policy['feedVersionName'],policy['feedVersionCode'])==('TMG12','Strix OS 1.0.6.11','Strix_OS_1.0.6.11','0100060011',100060011)
    assert policy['acceptOsVersions']==['Strix OS 1.0.5.12','Strix OS 1.0.6.11'] and policy['acceptQueryCodes']==['01.00.05.0012','01.00.06.0011']
    assert len(members)==17 and 'OtaFileInfo.json' in members and 'nuttx_ota.bin' in members and 'amap_rtos_sdk' in members and 'rives.bin' not in members
    with zipfile.ZipFile(tree_zip) as z:assert len(json.loads(z.read('OtaFileInfo.json')))==16 and len(z.namelist())==17
    assert members['nuttx_ap.bin']==[pins['apBytes'],pins['apSHA256']]==[tree_inputs['APBytes'],tree_inputs['APSHA256']]
    refused(lambda:pp.release_pins('c20',c20,c18_zip,build),'c20 with the c18 ZIP')
    refused_with(lambda:pp.release_pins('c20',c20,tree_zip,build,{**tree_inputs,'emuOnly':True}),'c20 under an emuOnly tree','label of an emuOnly tree')
    renamed=copy.deepcopy(c20);renamed['zip']['input']='tmg12/StrixOS-1.0.6.11-TurboIO-TMG12-EMU-ONLY-NOT-FOR-DEVICE.zip'
    refused_with(lambda:pp.release_pins('c20',renamed,tree_zip,build),'c20 under the EMU name','-EMU-ONLY-')
    # The superseded TMG12 emulator-only candidates 1 to 3 (written out by hand): valid 1.0.6.11 builds, so neither the
    # base nor their bytes refuse them under another label. Each is refused by its pin before its ZIP is read (the
    # path given does not exist), in release_pins and in --resolve; the c20 fixture itself resolves.
    superseded=('eacb5dcabc513570978edc31a47d3304b2bc361036d5b171e15bd4c3c281e9b5',
                'a8b9de49f2d5dc45311c5b19d61f96d9cc1acb2ed81ab55fb14534c0b68ad849',
                '007f1dd77b5b93eba3451e4df2ca6ba18264cee1444d9b97b40355b60f103325')
    for sha in superseded:
        old=copy.deepcopy(c20);old['firmware']='TMG13';old['zip']={'input':'tmg13/StrixOS-1.0.6.11-TurboIO-TMG13-CANDIDATE-NOT-APPROVED.zip','bytes':9549068,'sha256':sha}
        with tempfile.TemporaryDirectory(prefix='phone-pins-old-candidate-') as tmp:
            refused_with(lambda:pp.release_pins('c20',old,Path(tmp)/'missing.zip',build),'superseded candidate '+sha[:8],'this ZIP is superseded')
            refused_with(lambda:pp.resolve(old,tmp,'c20',build),'superseded candidate '+sha[:8]+' (--resolve)','this ZIP is superseded')
    assert tree_inputs['archive']['sha256'] not in pp.SUPERSEDED_ZIPS
    with tempfile.TemporaryDirectory(prefix='phone-pins-c20-resolve-') as tmp:
        target=Path(tmp)/c20['zip']['input'];target.parent.mkdir(parents=True);shutil.copyfile(tree_zip,target)
        assert pp.resolve(c20,tmp,'c20',build)==target
    with tempfile.TemporaryDirectory(prefix='phone-pins-c20-') as tmp:
        tmp=Path(tmp);inputs=tmp/'inputs';d=copy.deepcopy(data);d['releases']={n:s for n,s in d['releases'].items() if n!='c20'};d['releases']['c20']=c20
        (tmp/'releases.json').write_text(json.dumps(d))
        for spec in d['releases'].values():
            target=inputs/spec['zip']['input'];target.parent.mkdir(parents=True,exist_ok=True)
            if not target.exists():shutil.copyfile(tree_zip if spec is c20 else zip_of(spec),target)
        out_dir=tmp/'out'
        with contextlib.redirect_stdout(io.StringIO()):
            assert pp.main(['--releases',str(tmp/'releases.json'),'--inputs',str(inputs),'--write',str(out_dir)])==0
            assert pp.main(['--releases',str(tmp/'releases.json'),'--inputs',str(inputs),'--resolve','c20'])==0
        assert json.loads((out_dir/'firmware-pins-c20.json').read_text())=={**pins,**policy}
        header=(out_dir/'FirmwarePins.h').read_text();block=header[header.index('#elif defined(TIO_RELEASE_C20)'):header.index('#else')]
        assert '#define TIO_FW_OTA_VERSION @"Strix OS 1.0.6.11"' in block and '#define TIO_FW_OTA_FOLDER @"Strix_OS_1.0.6.11"' in block
        member_line=[line for line in block.splitlines() if line.startswith('#define TIO_FW_MEMBER_PINS ')]
        assert len(member_line)==1 and member_line[0].count('@[@')==17 and '#define TIO_FW_NAME @"TMG12"' in block
    # --check: the committed files match; a changed byte or a stale release file is caught.
    with tempfile.TemporaryDirectory(prefix='phone-pins-') as tmp:
        tmp=Path(tmp);inputs=tmp/'inputs'
        for name,spec in releases.items():
            target=inputs/spec['zip']['input'];target.parent.mkdir(parents=True,exist_ok=True)
            if not target.exists():shutil.copyfile(zip_of(spec),target)
        assert pp.main(['--inputs',str(inputs),'--check',str(ED)])==0
        work=tmp/'out';assert pp.main(['--inputs',str(inputs),'--write',str(work)])==0
        for name in out:assert (work/name).read_bytes()==(ED/name).read_bytes(),name
        changed=bytearray((work/'FirmwarePins.h').read_bytes());changed[-3]^=1;(work/'FirmwarePins.h').write_bytes(changed)
        assert pp.main(['--inputs',str(inputs),'--check',str(work)])==1
        assert pp.main(['--inputs',str(inputs),'--write',str(work)])==0 and pp.main(['--inputs',str(inputs),'--check',str(work)])==0
        (work/'firmware-pins-c99.json').write_text('{}');assert pp.main(['--inputs',str(inputs),'--check',str(work)])==1
        # A release ZIP whose bytes differ from its pin is refused before anything is read from it.
        z=inputs/releases['c16']['zip']['input'];raw=bytearray(z.read_bytes());raw[100]^=1;z.write_bytes(raw)
        assert pp.main(['--inputs',str(inputs),'--check',str(ED)])==1 and pp.main(['--inputs',str(inputs),'--resolve','c16'])==1
    print('PASS phone pins: version strings, per-release ZIP/base/tree checks, emulator-only refusals in every mode (base mode on a fixture build.py), host names incl. 1021-full, a c20-style TMG12 release on 1.0.6.11, superseded TMG12 candidates refused by pin, 1.0.6.11 only on 1021-full, releases.json validation, one block per release, --check catches changed and stale outputs')
if __name__=='__main__':main()
