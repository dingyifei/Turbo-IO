"""Build and run the idle-render graph test on the host, with the tree's stock base flags.

render_idle.c reads stock draw units, displays and layers through stock_layout.h names, so it compiles only with the
base defines and the firmware_profile.h force-include that tests/host_layout.py gives. The test model in
src/image-upload-test/render_idle_test.c places its fake objects with the same names. The values themselves are proven
by tests/stock_layout_test.py, not here.

  python3 -I firmware/tests/render_idle_host_test.py [--out DIR]
"""
from pathlib import Path
import argparse
import importlib.util
import subprocess
import tempfile

FW = Path(__file__).resolve().parents[1]
SRC = FW/'src'/'image-upload-test'
PASS = 'PASS conservative renderer graph: GPU/SW active, pending tasks, unknown units, failed reads and cycles reject'


def host_layout():
    spec = importlib.util.spec_from_file_location('render_idle_host_layout', FW/'tests'/'host_layout.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg12-render-idle-') as tmp:
        out = args.out or Path(tmp)
        out.mkdir(parents=True, exist_ok=True)
        exe = out/'render-idle-test'
        subprocess.run(['xcrun', 'clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-fsanitize=address,undefined',
                        *host_layout().flags(), '-I', str(SRC),
                        str(SRC/'render_idle_test.c'), str(SRC/'render_idle.c'), '-o', str(exe)], check=True)
        run = subprocess.run([str(exe)], check=True, capture_output=True, text=True)
        lines = run.stdout.splitlines()
        if run.stderr or lines != [PASS]:
            raise SystemExit('render_idle_host_test: expected exactly the PASS line, got stdout %r stderr %r'
                             % (run.stdout, run.stderr))
        print(lines[-1])


if __name__ == '__main__':
    main()
