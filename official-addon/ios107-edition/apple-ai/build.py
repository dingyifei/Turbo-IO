"""Build the unsigned on-device Swift shim using only the installed Apple SDK."""
import argparse
import json
import subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
UNITS=['AppleAICore','AppleAIProbe','AppleLLM','AppleSpeechFile','AppleSpeechInput','AppleCaptionPanel']
SHARED=['RealtimeText','CaptionAudioPipeline','MicrophoneInput','LocalTranslation']
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
    out=a.out.resolve()
    if out.exists(): raise ValueError('Use a new output directory; existing output is preserved')
    sdk=Path(subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip())
    frameworks=['FoundationModels','Speech','Translation','AVFoundation']
    present=[f for f in frameworks if (sdk/'System/Library/Frameworks'/(f+'.framework')).exists()]
    out.mkdir(parents=True)
    sources=[HERE/'src'/(u+'.swift') for u in UNITS]+[HERE.parent/'local-translation'/'src'/(u+'.swift') for u in SHARED]
    command=['xcrun','--sdk','iphoneos','swiftc','-swift-version','5','-O','-parse-as-library','-target','arm64-apple-ios26.0','-sdk',sdk,'-emit-library','-module-name','TurboAppleAI',*sources]
    for framework in present: command+=['-framework',framework]
    command+=['-Xlinker','-install_name','-Xlinker','@rpath/TurboAppleAI.dylib','-o',out/'TurboAppleAI.dylib']
    subprocess.run(list(map(str,command)),check=True)
    (out/'build-info.json').write_text(json.dumps({'version':'APPLE-AI-01','minimumIOS':'26.0','deviceValidated':False,'signed':False,'units':UNITS,'shared':SHARED,'sdkFrameworks':present},indent=2)+'\n')
    print('Built unsigned TurboAppleAI; no device operations')
if __name__=='__main__':main()
