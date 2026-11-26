"""The live sources the native tests compile, and the test drivers that exercise them.

The glasses runtime is the firmware tree's copy (firmware/src/app-runtime-v1, the one the firmware build links);
the phone codec and the dashboard backend are the addon's copies (ios-addon/). The drivers in tests/native are
test code only and include the runtime headers by name, so every compile passes the include directories below.
"""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIRMWARE_SRC = ROOT/'firmware/src'
RUNTIME = FIRMWARE_SRC/'app-runtime-v1'
PHONE = ROOT/'ios-addon'
DRIVERS = Path(__file__).resolve().parent/'native'


def runtime_includes():
    """Include flags for a driver built against the glasses runtime."""
    return ['-I', str(RUNTIME), '-I', str(FIRMWARE_SRC)]


def stock_layout_flags():
    """The tree's stock base defines and the force-include of firmware_profile.h, from the firmware's own host-test
    helper (firmware/tests/host_layout.py): the sources that touch stock objects (app_lvgl.c) need them."""
    spec = importlib.util.spec_from_file_location('host_layout', ROOT/'firmware/tests/host_layout.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.flags()


def phone_includes():
    """Include flags for a driver built against the phone sources."""
    return ['-I', str(PHONE)]


def view_builds():
    """The two live copies of the TAP1 view, as (label, include flags, sources): the glasses runtime and the phone's
    own older copy (ios-addon/build.sh compiles it; ios-addon/test.py lists the pair as differing on purpose)."""
    return [('firmware', runtime_includes(), [RUNTIME/'app.c', RUNTIME/'app_view.c']),
            ('phone', phone_includes(), [PHONE/'app.c', PHONE/'app_view.c'])]


def phone_language():
    """The phone's string table, which every localized phone source links (TIOText), pinned to Chinese as the
    addon's own test.py does."""
    return ['-DTIO_TEST_UI_LANGUAGE_ZH=1', '-framework', 'NaturalLanguage',
            *(str(PHONE/name) for name in ('TIOLanguage.m', 'TIOTextLanguage.m', 'Localization.m'))]
