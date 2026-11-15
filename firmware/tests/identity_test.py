"""Build-input identity is path/HEAD/pin independent and input sensitive."""
from pathlib import Path
import copy,importlib.util,json,shutil,tempfile
FW=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('tmg4_build_identity',FW/'build.py');build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
def flags(root):return ['-Os','-I',str(root/'src'),'-include',str(root/'src/firmware_profile.h')]
def main():
    inputs=json.loads((FW/'build-inputs.json').read_text());versions=inputs['toolchain'];asset='f758dd6e3cdf5fc6550238df26e46111e9d45d098b9d95f649626ea58210ee1d'
    original=build.build_input_identity(inputs,versions,flags(FW),asset)[1]
    with tempfile.TemporaryDirectory(prefix='tmg4-identity-') as tmp:
        target=Path(tmp)/'different-checkout';target.mkdir()
        for name in ('src','include'):shutil.copytree(FW/name,target/name)
        for name in ('build.py','link.ld','trampolines.S','ImageWireFormat.h'):shutil.copyfile(FW/name,target/name)
        build.HERE=target
        assert build.build_input_identity(inputs,versions,flags(target),asset)[1]==original
        changed=copy.deepcopy(inputs);changed['APSHA256']='0'*64;changed['archive']['sha256']='1'*64
        for edit in changed['edits']:
            if edit['kind']!='raw':edit['after']='abcd'
        assert build.build_input_identity(changed,versions,flags(target),asset)[1]==original
        changed=copy.deepcopy(inputs);changed['sources'].reverse();assert build.build_input_identity(changed,versions,flags(target),asset)[1]!=original
        modified=target/'src/firmware_profile.h';old=modified.read_bytes();modified.write_bytes(old+b'\n/* changed source input */\n');assert build.build_input_identity(inputs,versions,flags(target),asset)[1]!=original;modified.write_bytes(old)
        root_header=target/'ImageWireFormat.h';old_header=root_header.read_bytes();root_header.write_bytes(old_header+b'\n/* changed consumed header */\n');assert build.build_input_identity(inputs,versions,flags(target),asset)[1]!=original;root_header.write_bytes(old_header)
        (target/'src/identity_test.c').write_text('test fixture must not affect firmware identity\n');assert build.build_input_identity(inputs,versions,flags(target),asset)[1]==original
        changed=copy.deepcopy(versions);changed['clang']+=' changed';assert build.build_input_identity(inputs,changed,flags(target),asset)[1]!=original
        assert build.build_input_identity(inputs,versions,flags(target),asset)[1]==original
        # build.py is a build input; identityCarryOver freezes only its contribution (restructure carry-over), is bound to one
        # exact build.py ('live') so it fails closed for any other file, and --repin drops it.
        script=target/'build.py';old_script=script.read_bytes();live=copy.deepcopy(inputs);live.pop('identityCarryOver',None)
        live_before=build.build_input_identity(live,versions,flags(target),asset)[1]
        carried=copy.deepcopy(live);carried['identityCarryOver']={'build.py':{'carried':'f'*64,'live':build.sha(old_script)}}
        carried_before=build.build_input_identity(carried,versions,flags(target),asset)[1]
        assert carried_before!=live_before
        script.write_bytes(old_script+b'\n# changed build script\n')
        assert build.build_input_identity(live,versions,flags(target),asset)[1]!=live_before
        try:build.build_input_identity(carried,versions,flags(target),asset);raise SystemExit('stale carry-over accepted after build.py changed')
        except AssertionError as error:assert 'identityCarryOver stale' in str(error),error
        script.write_bytes(old_script)
        assert build.build_input_identity(carried,versions,flags(target),asset)[1]==carried_before
        modified.write_bytes(modified.read_bytes()+b'\n/* changed source input */\n');assert build.build_input_identity(carried,versions,flags(target),asset)[1]!=carried_before;modified.write_bytes(old)
        extra=copy.deepcopy(carried);extra['identityCarryOver']['link.ld']='e'*64
        try:build.build_input_identity(extra,versions,flags(target),asset);raise SystemExit('carry-over of a non build.py input was accepted')
        except AssertionError:pass
        bare=copy.deepcopy(live);bare['identityCarryOver']={'build.py':'f'*64}
        try:build.build_input_identity(bare,versions,flags(target),asset);raise SystemExit('unbound carry-over (no live pin) was accepted')
        except AssertionError:pass
        script.write_bytes(old_script)
    # The shipped carry-over is bound to the shipped build.py and to one recorded ZIP, with the build.py hash that ZIP was
    # built from; --repin must drop it. ZIP8: the single-tree restructure. TMG12: the release build, whose AP is
    # candidate 4's (candidate 4 was built from the build.py hashed below, which marked 1.0.6.11 emulator only).
    build.HERE=FW
    carry_overs={'effb10b86ef7064c02512b3f3671284ea40de6349c556383eacf70f09791fbd6':'e21a4556a2bd2be5740c0229b589f76f9e1a46a14d8793ab6a2efaa135d362f3',
                 '3abc73ffff78d890a49a0c148c64eef6a8577458bb0d759fca1b032bc031e373':'45b9ffc44e6cec3794fe8941a6dfdaa4ec22120ed1e79c271e5ca6eb9fd674eb'}
    if 'identityCarryOver' in inputs:
        assert inputs['archive']['sha256'] in carry_overs,'identityCarryOver outlived its ZIP: remove it and repin'
        assert inputs['identityCarryOver']['build.py']['carried']==carry_overs[inputs['archive']['sha256']],'identityCarryOver carries another build.py than its ZIP was built from'
        assert inputs['identityCarryOver']['build.py']['live']==build.sha((FW/'build.py').read_bytes())
        assert 'identityCarryOver' not in build.load_spec(True) and 'identityCarryOver' in build.load_spec(False)
    print('PASS identity: canonical paths, derived-pin/test exclusion, source/order/toolchain sensitivity, build.py carry-over fail-closed scope, repin drop and no HEAD/time dependency')
if __name__=='__main__':main()
