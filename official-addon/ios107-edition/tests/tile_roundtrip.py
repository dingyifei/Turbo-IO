"""Real phone codec/link through the firmware controller and durable host IO."""
from pathlib import Path
import subprocess,sys
P=Path(__file__).resolve().parents[1]
FW=P.parents[1]/'firmware-research/strix-1.0.5.5-tmg5'
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
s=(FW/'src/global-remote-v1/remote_native.c').read_text()
for a,b in {
    '*(void(**)(void*))((uint8_t*)t+8)':'host_timer_callback(t)',
    '*(Control**)((uint8_t*)t+12)':'((Control *)host_timer_user(t))',
    '_Static_assert(sizeof event==28,"32-bit pinned event ABI");':'/* target ABI covered by ARM build */',
}.items():
    assert a in s;s=s.replace(a,b)
(out/'remote_native_host.inc').write_text(s)
c=['xcrun','clang','-O1','-g','-fsanitize=address,undefined']
subprocess.run(c+['-std=c11','-Wall','-Wextra','-Werror','-I',out,'-I',FW/'src','-I',FW/'src/global-remote-v1','-c',FW/'tests/tile_roundtrip_bridge.c','-o',out/'remote.o'],check=True)
files=['tests/TileRoundTripTests.m','MenuLayout.m','tile_config.c','TIOLanguage.m','TIOTextLanguage.m','Localization.m']
shared=['global-remote-v1/remote.c','global-remote-v1/lang_flag.c','global-remote-v1/lang_store.c','diagnostics-v1/knob_calibration.c','diagnostics-v1/diagnostics.c']
subprocess.run(c+['-fobjc-arc','-fblocks','-framework','Foundation','-framework','NaturalLanguage','-DTIO_TEST_UI_LANGUAGE_ZH=1','-I',P,*[P/f for f in files],out/'remote.o',*[FW/'src'/f for f in shared],'-o',out/'roundtrip'],check=True)
subprocess.run([out/'roundtrip'],check=True)
