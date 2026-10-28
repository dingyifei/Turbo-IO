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
    build.HERE=FW;print('PASS identity: canonical paths, derived-pin/test exclusion, source/order/toolchain sensitivity and no HEAD/time dependency')
if __name__=='__main__':main()
