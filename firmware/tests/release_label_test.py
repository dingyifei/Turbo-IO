"""The release label comes from RELEASE, never from the folder name (build.py archive name and phone_pins.py)."""
from pathlib import Path
import importlib.util,json,re,shutil,subprocess,sys,tempfile
FW=Path(__file__).resolve().parents[1]
def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def stage(root,label,folder):
    """A copy of the two label readers inside a folder with a deliberately misleading name."""
    tree=root/folder;(tree/'tools').mkdir(parents=True)
    shutil.copyfile(FW/'build.py',tree/'build.py');shutil.copyfile(FW/'tools/phone_pins.py',tree/'tools/phone_pins.py')
    shutil.copyfile(FW/'build-inputs.json',tree/'build-inputs.json')
    if label is not None:(tree/'RELEASE').write_text(label)
    return tree
def want_name(base,label,emu):
    return 'StrixOS-%s-TurboIO-%s-%s.zip'%(base,label,'EMU-ONLY-NOT-FOR-DEVICE' if emu else 'CANDIDATE-NOT-APPROVED')
def refused(f,why):
    """Refusals of the emuOnly rules are AssertionErrors whose message starts with emuOnly:."""
    try:f()
    except AssertionError as e:
        assert str(e).startswith('emuOnly:'),(why,str(e));return
    raise SystemExit('accepted: '+why)
def main():
    release=(FW/'RELEASE').read_text()
    assert re.fullmatch(r'TMG[0-9]+\n',release),'RELEASE is exactly one label and a newline'
    label=release.strip()
    # The real tree: both readers agree with the file, and the pinned archive name has no stored copy.
    build=load(FW/'build.py','release_label_build');pins=load(FW/'tools/phone_pins.py','release_label_pins')
    assert build.release_label()==pins.release_label()==label
    inputs=json.loads((FW/'build-inputs.json').read_text());base=inputs['stockBase']
    assert base in build.STOCK_BASES
    assert build.archive_name()==want_name(base,label,build.emu_only(inputs))
    # The stock base in the name comes from build-inputs.json stockBase too, never from a folder name. A base that can
    # never be a phone release (phoneRelease False) gets the EMU name, and asking for the candidate name is refused.
    for other in build.STOCK_BASES:
        phone=build.package_shape(other)['phoneRelease']
        assert build.archive_name(base=other)==want_name(other,label,not phone)
        assert build.archive_name(base=other,emu_only=True)==want_name(other,label,True)
        if phone:assert build.archive_name(base=other,emu_only=False)==want_name(other,label,False)
        else:refused(lambda:build.archive_name(base=other,emu_only=False),'candidate name for %s'%other)
    assert not build.package_shape('1.0.6.11')['phoneRelease']
    refused(lambda:build.archive_name(base='1.0.6.11',emu_only=False),'candidate name for 1.0.6.11')
    refused(lambda:build.emu_only({'stockBase':'1.0.6.11'}),'1.0.6.11 tree that is not emuOnly')
    refused(lambda:build.emu_only({'stockBase':base,'emuOnly':'true'}),'emuOnly that is not a bool')
    assert 'name' not in json.loads((FW/'build-inputs.json').read_text())['archive'],'the archive name has one source: RELEASE'
    with tempfile.TemporaryDirectory(prefix='release-label-') as tmp:
        tmp=Path(tmp)
        # A folder called like an old release must not change the label: it is the file that decides.
        for folder,value in (('release-tmg2','TMG9\n'),('firmware','TMG11\n'),('release-tmg7','TMG7\n')):
            tree=stage(tmp/folder.replace('.','_'),value,folder)
            b=load(tree/'build.py','b_'+folder.replace('-','_').replace('.','_'));p=load(tree/'tools/phone_pins.py','p_'+folder.replace('-','_').replace('.','_'))
            want=value.strip()
            assert b.release_label()==p.release_label()==want,(folder,b.release_label(),p.release_label())
            assert b.archive_name()==want_name(base,want,b.emu_only(json.loads((tree/'build-inputs.json').read_text())))
        # The name follows emuOnly of the copied build-inputs.json: the same copy with emuOnly true gets the EMU name.
        tree=stage(tmp/'emu','TMG12\n','release-tmg12');(tree/'build-inputs.json').write_text(json.dumps(dict(inputs,emuOnly=True)))
        b=load(tree/'build.py','b_emu')
        assert b.emu_only(json.loads((tree/'build-inputs.json').read_text())) is True
        assert b.archive_name()==want_name(base,'TMG12',True) and b.archive_name().endswith('-EMU-ONLY-NOT-FOR-DEVICE.zip')
        refused(lambda:b.archive_name(emu_only=False),'candidate name for an emuOnly tree')
        # Changing only the file changes the label, with the folder name constant.
        tree=stage(tmp/'same','TMG8\n','release-tmg8')
        first=load(tree/'tools/phone_pins.py','p_same_1').release_label();(tree/'RELEASE').write_text('TMG9\n')
        assert first=='TMG8' and load(tree/'tools/phone_pins.py','p_same_2').release_label()=='TMG9'
        # A missing or malformed RELEASE fails closed; nothing falls back to the folder name.
        for bad in (None,'','tmg8\n','TMG8 TMG9\n','TMG\n','release-tmg8\n'):
            tree=stage(tmp/('bad%d'%abs(hash(bad))),bad,'release-tmg5')
            for reader,name in ((load(tree/'build.py','bb'),'release_label'),(load(tree/'tools/phone_pins.py','pp'),'release_label')):
                try:getattr(reader,name)()
                except (AssertionError,ValueError,OSError):continue
                raise SystemExit('malformed RELEASE accepted: %r'%(bad,))
    print('PASS release label: one source (RELEASE), folder-name independent, fails closed; build.py archive name and phone_pins.py agree; EMU name for emuOnly trees and bases with no phone release')
if __name__=='__main__':main()
