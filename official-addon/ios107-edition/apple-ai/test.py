"""Host core tests and unsigned iOS shim checks; no device, microphone or network."""
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

def run(args):
    subprocess.run(list(map(str, args)), check=True)

def main():
    with tempfile.TemporaryDirectory(prefix='turbo-apple-ai-tests-') as folder:
        core = Path(folder) / 'core'
        run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
             HERE/'src/AppleAICore.swift', HERE/'src/AppleAICoreTests.swift', '-o', core])
        run([core])
        out=Path(folder)/'out'
        run(['python3',HERE/'build.py','--out',out])
        import json,re
        dylib=out/'TurboAppleAI.dylib'
        symbols=subprocess.check_output(['nm',str(dylib)],text=True)
        assert '_OBJC_CLASS_$_TIOAppleAIProbe' in symbols
        links=subprocess.check_output(['otool','-L',str(dylib)],text=True)
        info=json.loads((out/'build-info.json').read_text())
        for framework in ('FoundationModels','Speech','Translation'):
            if framework in info['sdkFrameworks']: assert framework+'.framework' in links
        assert '/usr/lib/swift/libswiftCore.dylib' in links
        commands=subprocess.check_output(['otool','-l',str(dylib)],text=True)
        assert re.search(r'minos\s+26\.0',commands)
        assert info['version']=='APPLE-AI-01'
        print('PASS apple-ai ios build')

if __name__ == '__main__':
    main()
