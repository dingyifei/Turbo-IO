"""The tree's stock base flags for host compiles: build.py's TD_STOCK_* defines for the stockBase in build-inputs.json,
then a force-include of src/firmware_profile.h, which brings stock_layout.h. Host tests take their stock layout from
these flags, never from a base or a value typed by hand.

  python3 -I firmware/tests/host_layout.py --flags   prints the flags on one line, the path relative to the repository
"""
from pathlib import Path
import importlib.util
import json
import sys

FW = Path(__file__).resolve().parents[1]
ROOT = FW.parent
PROFILE = FW/'src'/'firmware_profile.h'


def _build():
    spec = importlib.util.spec_from_file_location('host_layout_build', FW/'build.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def defines():
    """build.stock_defines(build.stock_base(build-inputs.json)): exactly one TD_STOCK_* define is 1."""
    build = _build()
    return build.stock_defines(build.stock_base(json.loads((FW/'build-inputs.json').read_text())))


def flags():
    """The base defines followed by -include <absolute path of firmware/src/firmware_profile.h>."""
    assert PROFILE.is_file(), 'missing %s' % PROFILE
    return defines() + ['-include', str(PROFILE)]


def main(argv):
    if argv != ['--flags']:
        raise SystemExit('usage: python3 -I firmware/tests/host_layout.py --flags')
    out = flags()
    assert out[-1] == str(PROFILE)
    print(' '.join(out[:-1] + [PROFILE.relative_to(ROOT).as_posix()]))


if __name__ == '__main__':
    main(sys.argv[1:])
