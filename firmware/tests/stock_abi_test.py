"""Offline byte pins for the existing carousel RAM ABI and raw input call path, on the tree's stock base."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,struct,zipfile
FW=Path(__file__).resolve().parents[1]
# The 11 ranges as pinned on stock 1.0.5.5 (TMG3..TMG9). On another base each range is mapped through the rebase
# table chain (tools/rebase_apply.py TABLES: 1.0.5.5 to 1.0.5.12, then 1.0.5.12 to 1.0.6.11 once that file exists),
# each table's stockAbiRanges partner (equal bytes except moved branch targets), with that base's hash.
RANGES=[
 (0x10669be6,36,'1112e6219badce0aad1978cc1809d4dcad97603f85465818616cc6a8bb49112d'),
 (0x1071e648,16,'f3cc17451ec4e8ed124d7d08c8c1d4534bc5e83da7843347bf82f6ae658d2af6'),
 (0x1071e5f4,68,'6a8dd2fa23a77707ec33105aefeb4e09b1d7046c10b1f35b46ee45fc3e165648'),
 (0x1066a820,74,'4e80f580596e4fafcc6c018e3c203115e437c1bee02f1c6e2f269c4370e86bf7'),
 (0x10669b8c,24,'c1cdae9d2d6b25b3ff14c10df123f86f6f56105dbb5784d7ec2edb88bb1f938f'),
 (0x105ebc3c,32,'376277e584a942c2db2f865978737d7e4ad7f76c00ad69c3bac9d7c3f63c2273'),
 (0x10568dac,24,'f8215195eb9c84cf913c179b3a05d6ed89deadd7d2dae27eebda2ae300e20f37'),
 (0x10568d4e,28,'ac7476097f2ba2bce8427130eff0a7705a7860cd551134860d11e17ede188d73'),
 (0x1066a712,18,'77ae3ae8ee8475e1f9525e348b6f8304daa4e0e81d6ca9b5366c1cea1ff908e5'),
 (0x106fb1d0,54,'10f510dff1985bfa38bc7d5166e19d20674c94294857102b183274bb70f000b3'),
 (0x10566aa4,112,'53bb9c1c48fff0408f3107a3029b2909c8fcd7e9b50872e82b3d83532dffafc4'),
]
KEYS=('offset','address','before','kind','target','pad')
# A range a table marks "changed" (format 2 verdict) must be listed here with the table's newSHA256: {(to, new): (newSHA256, reason)}.
# Each hash is the sha256 of the new range's bytes in the 1.0.6.11 AP (main() re-hashes every range from the stock ZIP).
# The 18-byte range at new 0x106a4fd6 has the same bytes as before, so its verdict is shift and it is not listed.
REVIEWED_ABI_CHANGES={
 ('1.0.6.11','0x106a44aa'):('755509019f74cc45d6b956024ed6e79ffd0e69085e23441ad69593edf84dc845','menu ctor: count movs r1,#7 became #8, and the strd/str/strb fields moved by +0x10'),
 ('1.0.6.11','0x106a50e0'):('dfe8def906c2a6575bdf8549503c5baafadef808cf58b63c41fa539def28e64b','native_snap: fields 0xab/0xac/0x90/0x88 moved by +0x10'),
 ('1.0.6.11','0x106a4450'):('23a5c4565dd9c124e612bf70b677aa32e26d8e3bbf2141bc0be98e5fde25913d','field 0x88 became 0x98, and adds r0,#0xa0 became #0xb0'),
 ('1.0.6.11','0x105a4bc4'):('1767276c38151d69283d70e4a1fbe87a5a30e3dc6cf1cdf49851d0ff5369d150','the pool word at +108 is the code pointer of the 24-byte range at old 0x1058_280c (new 0x105a_6eb0): 0x1058_280d became 0x105a_6eb1'),
}
# An edit whose before changed other than in BL/B.W immediates must be listed with exactly this new before:
# {(to, role): newBefore}. Typed from the bytes of the 1.0.6.11 AP
# (sha256 9bbf7be31ebb7f8600e6ea4bf51831a151e2af6d4eb8e6ccfcf55d67f2e71260) at the readiness addresses.
REVIEWED_BEFORE_CHANGES={
 ('1.0.6.11','Menu replacement frame_start'):'1e2380b5',   # clamp to 6 replaced by usat 0..7; b.w covers two instructions
 ('1.0.6.11','Menu replacement label_index'):'90b581f3',   # clamp to 6 replaced by usat 0..7; full replacement
 ('1.0.6.11','284-byte menu allocation'):'4ff4867050f07cfc',   # mov.w r0,#0x10c + bl, 8 bytes (pad 2)
 ('1.0.6.11','Carousel item count 7 to 13'):'0821',   # stock count 8
 ('1.0.6.11','File callback registration'):'00242048214b84610360',   # the two ldr literal offsets moved by 4 bytes
}
# A format-2 raw edit keeps newAfter == oldAfter (the patched bytes stay the TMG3 ones) unless listed here with exactly
# this new after: {(to, role): (newAfter, reason)}. Ships empty; filling it is an owner decision in a reviewed commit.
REVIEWED_AFTER_CHANGES={}
FORMATS=('turboio-rebase-1','turboio-rebase-2')
VERDICTS=('shift','changed')
def load(path,name):
 spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def branch_free(raw):
 """Thumb instruction units of `raw`, with the immediate of every BL/B.W masked out (the T4 type bits stay)."""
 out,i=[],0
 while i<len(raw):
  h=struct.unpack_from('<H',raw,i)[0]
  if h>>11 in (0x1d,0x1e,0x1f) and i+4<=len(raw):
   g=struct.unpack_from('<H',raw,i+2)[0]
   out.append(('branch',g&0xd000) if h>>11==0x1e and g&0xd000 in (0xd000,0x9000) else ('w',raw[i:i+4]));i+=4
  else:out.append(('h',raw[i:i+2]));i+=2
 return out
def expected(spec):
 """(ranges, the audited TMG3 patch set) on the tree's stock base, walked through the table chain from 1.0.5.5."""
 chain=load(FW/'tools/rebase_apply.py','stock_abi_rebase').table_chain(FW)
 original=json.loads((FW/'baseline/tmg3-build-inputs.json').read_text())
 base=spec['stockBase']
 assert chain and chain[0]['from']=='1.0.5.5','the table chain does not start at 1.0.5.5'
 assert [(int(r['old'],16),r['bytes'],r['oldSHA256']) for r in chain[0]['stockAbiRanges']]==RANGES,'rebase table ranges are not these 11'
 # Every review must be in use: for each format-2 table, the reviewed keys for its `to` are exactly its changed
 # ranges, and no review names a base that no format-2 table in the chain leads to.
 two_to=set()
 for t in chain:
  if t.get('format')!='turboio-rebase-2':continue
  two_to.add(t['to'])
  reviewed={k for k in REVIEWED_ABI_CHANGES if k[0]==t['to']}
  changed={(t['to'],r['new']) for r in t['stockAbiRanges'] if r.get('verdict')=='changed'}
  assert reviewed==changed,'%s to %s: reviewed ABI changes %s are not the changed ranges %s'%(t['from'],t['to'],sorted(reviewed),sorted(changed))
 assert all(k[0] in two_to for k in REVIEWED_ABI_CHANGES),'reviewed ABI changes for a base with no format-2 table: %s'%sorted(k for k in REVIEWED_ABI_CHANGES if k[0] not in two_to)
 ranges,edits,at=RANGES,original['edits'],'1.0.5.5'
 for t in chain:
  if at==base:break
  assert t['from']==at,'table chain gap at %s'%at
  assert t.get('format') in FORMATS,'%s to %s: unknown table format %r'%(t['from'],t['to'],t.get('format'))
  two=t['format']=='turboio-rebase-2'
  if two:
   for r in t['stockAbiRanges']+t['edits']:assert r.get('verdict') in VERDICTS,'%s to %s: row verdict %r is not shift or changed'%(t['from'],t['to'],r.get('verdict'))
  for (to,role) in REVIEWED_AFTER_CHANGES:
   assert to!=t['to'] or two,'reviewed after for a format-1 table: %r'%role
  # Ranges: the old column must be the previous result; a changed range must be reviewed with its new hash.
  assert [(int(r['old'],16),r['bytes'],r['oldSHA256']) for r in t['stockAbiRanges']]==ranges,'%s to %s ranges are not the previous ones'%(t['from'],t['to'])
  for r in t['stockAbiRanges']:
   if two and r['verdict']=='changed':
    listed=REVIEWED_ABI_CHANGES.get((t['to'],r['new']))
    assert listed and listed[0]==r['newSHA256'],'unreviewed changed ABI range %s on %s'%(r['new'],t['to'])
  ranges=[(int(r['new'],16),r['bytes'],r['newSHA256']) for r in t['stockAbiRanges']]
  rows={r['role']:r for r in t['edits']};assert len(rows)==len(edits)==25,'%s to %s edits'%(t['from'],t['to'])
  for (to,role),value in REVIEWED_BEFORE_CHANGES.items():
   assert to!=t['to'] or role in rows,'reviewed before for unknown role %r'%role
  for (to,role) in REVIEWED_AFTER_CHANGES:
   assert to!=t['to'] or (role in rows and rows[role].get('oldAfter') is not None),'reviewed after for unknown raw role %r'%role
  mapped=[]
  for e in edits:
   r=rows[e['role']];assert (r['oldOffset'],r['oldAddress'],r['oldBefore'])==(e['offset'],e['address'],e['before']),e['role']
   if 'oldPad' in r:assert r['oldPad']==e['pad'],e['role']
   if two and e['kind']=='raw':
    # Both after columns are required: the old one ties to the previous after (TMG3 at the start), the new one must
    # equal it unless reviewed.
    assert 'oldAfter' in r and 'newAfter' in r,'%s: format-2 raw edit without oldAfter/newAfter'%e['role']
    assert r['oldAfter']==e['after'],'%s: oldAfter is not the previous after'%e['role']
    listed=REVIEWED_AFTER_CHANGES.get((t['to'],e['role']))
    if listed is not None:assert r['newAfter']==listed[0],'%s: newAfter %s is not the reviewed %s'%(e['role'],r['newAfter'],listed[0])
    else:assert r['newAfter']==r['oldAfter'],'%s: unreviewed after change %s -> %s'%(e['role'],r['oldAfter'],r['newAfter'])
   else:assert 'oldAfter' not in r and 'newAfter' not in r,'%s: after columns on a %s row of a %s table'%(e['role'],e['kind'],t['format'])
   listed=REVIEWED_BEFORE_CHANGES.get((t['to'],e['role']))
   if listed is not None:assert r['newBefore']==listed,'%s: newBefore %s is not the reviewed %s'%(e['role'],r['newBefore'],listed)
   else:assert branch_free(bytes.fromhex(r['oldBefore']))==branch_free(bytes.fromhex(r['newBefore'])),'unreviewed before change: '+e['role']
   n={**e,'offset':r['newOffset'],'address':r['newAddress'],'before':r['newBefore']}
   if two:assert r.get('newPad')==((len(r['newBefore'])//2-4)//2 if e['kind']!='raw' else 0),'%s: newPad %r does not fit newBefore'%(e['role'],r.get('newPad'))
   if 'newPad' in r:n['pad']=r['newPad']
   if two and e['kind']=='raw':n['after']=r['newAfter']
   mapped.append(n)
  edits,at=mapped,t['to']
 assert at==base,'stock base %r has no rebase column'%base
 return ranges,edits
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--stock',type=Path,required=True);args=parser.parse_args()
 with zipfile.ZipFile(args.stock) as z:raw=z.read('nuttx_ap.bin')
 spec=json.loads((FW/'build-inputs.json').read_text());assert hashlib.sha256(raw).hexdigest()==spec['stockAP']
 ranges,original=expected(spec)
 for address,n,sha in ranges:assert hashlib.sha256(raw[address-0x10190000:address-0x10190000+n]).hexdigest()==sha,hex(address)
 assert len(spec['edits'])==25 and [{k:e.get(k) for k in KEYS} for e in spec['edits']]==[{k:e.get(k) for k in KEYS} for e in original]
 assert [e for e in spec['edits'] if e['kind']=='raw']==[e for e in original if e['kind']=='raw']
 for e in original:at=int(e['offset'],16);assert raw[at:at+len(e['before'])//2].hex()==e['before'],'stock bytes at '+e['role']
 print('PASS stock ABI (%s): 11 exact ranges (%d reviewed changes on this base), synchronous raw listener route and 25 unchanged patch sites/raw bytes'%(
  spec['stockBase'],sum(1 for k in REVIEWED_ABI_CHANGES if k[0]==spec['stockBase'])))
if __name__=='__main__':main()
