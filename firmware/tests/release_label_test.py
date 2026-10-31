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
    if label is not None:(tree/'RELEASE').write_text(label)
    return tree
def main():
    release=(FW/'RELEASE').read_text()
    assert re.fullmatch(r'TMG[0-9]+\n',release),'RELEASE is exactly one label and a newline'
    label=release.strip()
    # The real tree: both readers agree with the file, and the pinned archive name has no stored copy.
    build=load(FW/'build.py','release_label_build');pins=load(FW/'tools/phone_pins.py','release_label_pins')
    assert build.release_label()==pins.release_label()==label
    assert build.archive_name()=='StrixOS-1.0.5.5-TurboIO-%s-CANDIDATE-NOT-APPROVED.zip'%label
    assert 'name' not in json.loads((FW/'build-inputs.json').read_text())['archive'],'the archive name has one source: RELEASE'
    with tempfile.TemporaryDirectory(prefix='release-label-') as tmp:
        tmp=Path(tmp)
        # A folder called like an old release must not change the label: it is the file that decides.
        for folder,value in (('release-tmg2','TMG9\n'),('firmware','TMG11\n'),('release-tmg7','TMG7\n')):
            tree=stage(tmp/folder.replace('.','_'),value,folder)
            b=load(tree/'build.py','b_'+folder.replace('-','_').replace('.','_'));p=load(tree/'tools/phone_pins.py','p_'+folder.replace('-','_').replace('.','_'))
            want=value.strip()
            assert b.release_label()==p.release_label()==want,(folder,b.release_label(),p.release_label())
            assert b.archive_name()=='StrixOS-1.0.5.5-TurboIO-%s-CANDIDATE-NOT-APPROVED.zip'%want
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
    print('PASS release label: one source (RELEASE), folder-name independent, fails closed; build.py archive name and phone_pins.py agree')
if __name__=='__main__':main()
