"""The phone pin generator (tools/phone_pins.py): version strings, release validation, the stock-base and tree checks,
and --check catching a changed or stale output. Usage: phone_pins_test.py ZIP ZIP (ZIP9 and ZIP10, any order)."""
from pathlib import Path
import copy,hashlib,importlib.util,json,shutil,sys,tempfile
FW=Path(__file__).resolve().parents[1]
ED=FW.parent/'official-addon'/'ios107-edition'
def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def refused(call,why):
    try:call()
    except (ValueError,AssertionError,KeyError):return
    raise SystemExit('accepted: '+why)
def main():
    pp=load(FW/'tools/phone_pins.py','phone_pins_under_test')
    zips={hashlib.sha256(Path(p).read_bytes()).hexdigest():Path(p) for p in sys.argv[1:3]}
    releases=pp.load_releases(ED/'releases.json')
    by_sha={s['zip']['sha256']:n for n,s in releases.items()}
    zip9=zips['def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd']
    zip10=zips['4a5973636329e8863a8ab7aaea4050a35d964916c3b125f63242b384e018cb6c']
    assert set(by_sha.values())<=set(releases) and set(releases)=={'default','c16','c17'}
    # Version strings, written out by hand.
    assert pp.query_code('1.0.5.12')=='01.00.05.0012' and pp.query_code('1.0.5.5')=='01.00.05.0005' and pp.query_code('1.0.4.12')=='01.00.04.0012'
    assert pp.feed_version_name('1.0.5.12')=='0100050012' and pp.feed_version_name('1.0.5.5')=='0100050005'
    assert pp.os_version('1.0.5.12')=='Strix OS 1.0.5.12'
    for bad in ('1.0.5','1.0.5.12.1','v1.0.5.5','1.0.5.x','',None):refused(lambda:pp.version_parts(bad),'version '+repr(bad))
    build=pp.load_build()
    # Each release: its own ZIP passes and yields the policy below; any other ZIP or base is refused.
    want={'default':('TMG9','Strix OS 1.0.5.5','Strix_OS_1.0.5.5',['01.00.04.0012','01.00.05.0005']),
          'c16':('TMG10','Strix OS 1.0.5.12','Strix_OS_1.0.5.12',['01.00.05.0005','01.00.05.0012']),
          'c17':('TMG9','Strix OS 1.0.5.5','Strix_OS_1.0.5.5',['01.00.05.0012'])}
    for name,spec in releases.items():
        own=zip10 if spec['firmware']=='TMG10' else zip9;other=zip9 if own==zip10 else zip10
        pins,members,policy=pp.release_pins(name,spec,own,build)
        assert (pins['name'],policy['otaVersion'],policy['folder'],policy['acceptQueryCodes'])==want[name],name
        assert len(members)==16 and members['nuttx_ap.bin']==[pins['apBytes'],pins['apSHA256']]
        refused(lambda:pp.release_pins(name,spec,other,build),name+' with the other ZIP')
        wrong=copy.deepcopy(spec);wrong['stockBase']='1.0.5.5' if spec['stockBase']=='1.0.5.12' else '1.0.5.12'
        refused(lambda:pp.release_pins(name,wrong,own,build),name+' on the other stock base')
        # The tree's label must be carried by the tree's own ZIP.
        tree={'archive':{'sha256':'0'*64},'stockBase':spec['stockBase']}
        refused(lambda:pp.release_pins(name,spec,own,build,tree,spec['firmware']),name+' named as the tree release with another ZIP')
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
    bad_releases(lambda d:d['releases']['c16'].update(acceptCurrent=['1.0.5.5','1.0.5.5']),'duplicate accepted version')
    bad_releases(lambda d:d['releases']['c16'].update(acceptCurrent=[]),'no accepted version')
    bad_releases(lambda d:d['releases'].pop('default'),'no default release')
    bad_releases(lambda d:d['releases'].update(C18=d['releases']['c16']),'bad release name')
    # Rendering: one block per release, the guard against two defines, the default JSON unchanged in form.
    computed={n:pp.release_pins(n,s,zip10 if s['firmware']=='TMG10' else zip9,build) for n,s in releases.items()}
    out=pp.render(releases,computed)
    header=out['FirmwarePins.h'].decode()
    assert header.count('#define TIO_FW_ZIP_SHA256 ')==3 and '#error "more than one TIO_RELEASE_<NAME> defined"' in header
    assert header.index('#if defined(TIO_RELEASE_C16)')<header.index('#elif defined(TIO_RELEASE_C17)')<header.index('#else')
    assert json.loads(out['firmware-pins.json'])==pp.pins_for(zip9,'TMG9')
    assert set(out)=={'FirmwarePins.h','firmware-pins.json','firmware-pins-c16.json','firmware-pins-c17.json'}
    # --check: the committed files match; a changed byte or a stale release file is caught.
    with tempfile.TemporaryDirectory(prefix='phone-pins-') as tmp:
        tmp=Path(tmp);inputs=tmp/'inputs'
        for name,spec in releases.items():
            target=inputs/spec['zip']['input'];target.parent.mkdir(parents=True,exist_ok=True)
            if not target.exists():shutil.copyfile(zip10 if spec['firmware']=='TMG10' else zip9,target)
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
    print('PASS phone pins: version strings, per-release ZIP/base/tree checks, releases.json validation, one block per release, --check catches changed and stale outputs')
if __name__=='__main__':main()
