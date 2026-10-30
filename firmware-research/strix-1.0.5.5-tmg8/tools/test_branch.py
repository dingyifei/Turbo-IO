"""Independent proof against the 24 retained, already-pinned TMG2 edits."""
import importlib.util
import json
from pathlib import Path
import struct
import sys

fw = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('tmg3_build', fw/'build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)
old = {int(e['address'],16):e for e in json.loads(Path(sys.argv[1]).read_text())['edits']}
rows = json.loads((fw/'build-inputs.json').read_text())['edits']
count = 0
for row in rows:
    if row['kind'] == 'raw':
        continue
    site = int(row['address'],16)
    reference = old[site]
    encoded = bytes.fromhex(reference['after'])
    # Decode independently here rather than using the production inverse.
    a,b = struct.unpack('<HH',encoded[:4])
    s = (a>>10)&1
    bits = (s<<24)|((1^((b>>13)&1)^s)<<23)|((1^((b>>11)&1)^s)<<22)|((a&1023)<<12)|((b&2047)<<1)
    target = site+4+bits-(1<<25 if s else 0)
    kind = 'bl' if b&0x4000 else 'bw'
    assert kind == row['kind'] and reference['before'] == row['before']
    assert build.branch(site,target,kind=='bl')+bytes.fromhex('00bf')*row['pad'] == encoded
    assert build.decode(site,encoded[:4]) == (kind,target)
    count += 1
assert count == 24
# Boundary and backwards branches exercise sign extension and J-bit inversion.
for delta in (-(1<<24), -4096, -2, 0, 2, 4096, (1<<24)-2):
    for link in (False,True):
        site = 0x10800000; target = site+4+delta
        assert build.decode(site,build.branch(site,target,link)) == ('bl' if link else 'bw',target)
for invalid in (b'',bytes(4),bytes.fromhex('00f00080')):
    try:build.decode(0x1000,invalid)
    except ValueError:pass
    else:raise AssertionError('accepted non-branch')
print('24/24 branch edits re-encode identically')
