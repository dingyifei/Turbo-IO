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

if __name__ == '__main__':
    main()
