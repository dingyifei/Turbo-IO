"""Offline byte pins for the existing carousel RAM ABI and raw input call path."""
from pathlib import Path
import argparse,hashlib,json,zipfile
FW=Path(__file__).resolve().parents[1]
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
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--stock',type=Path,required=True);args=parser.parse_args()
 with zipfile.ZipFile(args.stock) as z:raw=z.read('nuttx_ap.bin')
 spec=json.loads((FW/'build-inputs.json').read_text());assert hashlib.sha256(raw).hexdigest()==spec['stockAP']
 for address,n,sha in RANGES:assert hashlib.sha256(raw[address-0x10190000:address-0x10190000+n]).hexdigest()==sha,hex(address)
 original=json.loads((FW/'baseline/tmg3-build-inputs.json').read_text())
 keys=('offset','address','before','kind','target','pad')
 assert len(spec['edits'])==25 and [{k:e.get(k) for k in keys} for e in spec['edits']]==[{k:e.get(k) for k in keys} for e in original['edits']]
 assert [e for e in spec['edits'] if e['kind']=='raw']==[e for e in original['edits'] if e['kind']=='raw']
 print('PASS stock ABI: 11 exact ranges, synchronous raw listener route and 25 unchanged patch sites/raw bytes')
if __name__=='__main__':main()
