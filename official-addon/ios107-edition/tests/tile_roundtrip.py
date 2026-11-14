"""Tile configuration round trip on the 1.0.6.11 firmware tree, as two executables that are never linked together.

1. Firmware (14 items): firmware/tests/tile_roundtrip_bridge.c with the real remote_native.c controller bodies, the
   firmware tile_config.c and native_remote_test.c's host stubs, compiled with the tree's base flags
   (firmware/tests/host_layout.py): TTL encode -> native handler -> durable mock A/B -> TTA decode, order [0..7, 13..8],
   every hideable module tile hidden, then a reboot reload.
2. Old phone (13 items): a small program written here and compiled with this folder's tile_config.c and no base define
   writes one version-1 TT_SET frame (rank 0, hide 0, a nonzero token), which the firmware must refuse with no reply and
   no write. The same frame with byte 4 set to 2 and bytes 28..31 resealed by the firmware object's tt_crc must then be
   accepted (one reply, one write), so the version byte is the only reason for the refusal.

The phone's own codec and link (tests/TileRoundTripTests.m, MenuLayout.m) are not run here: they stay with the
1.0.5.12-pair phone track.

  python3 -I official-addon/ios107-edition/tests/tile_roundtrip.py <fresh output folder>
"""
from pathlib import Path
import importlib.util,re,subprocess,sys
P=Path(__file__).resolve().parents[1]
FW=P.parents[1]/'firmware'
TOKEN,CLIENT=77,5   # the firmware host stub issues nonce 77; the frame must carry it to reach the version check alone
OLD_PHONE=r'''#include "tile_config.h"
#include <stdio.h>
#include <stdlib.h>
_Static_assert(TT_ITEMS==13&&TT_VERSION==1,"the old phone's tile model: 13 items, version 1");
int main(int argc,char **argv){
 if(argc!=4)return 2;
 TTCommand q={.op=TT_SET,.request=9,.token=(uint32_t)strtoul(argv[2],NULL,10),.generation=0,.client=(uint32_t)strtoul(argv[3],NULL,10),.rank=0,.hide=0};
 uint8_t raw[32];TTCommand back;tt_encode(raw,&q);
 if(!q.token||!tt_decode(raw,sizeof raw,&back)||back.op!=TT_SET||back.token!=q.token)return 1;
 FILE *f=fopen(argv[1],"wb");if(!f||fwrite(raw,1,sizeof raw,f)!=sizeof raw||fclose(f))return 1;return 0;
}
'''
def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
def run(cmd):
    p=subprocess.run([str(c) for c in cmd],capture_output=True,text=True)
    if p.returncode:
        sys.stderr.write(p.stdout+p.stderr)
        raise SystemExit('tile_roundtrip: %s exited %d'%(Path(str(cmd[0])).name if cmd[0]!='xcrun' else 'clang',p.returncode))
    return p.stdout
def main():
    if len(sys.argv)!=2:raise SystemExit('usage: tile_roundtrip.py <fresh output folder>')
    out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
    host_layout=load(FW/'tests/host_layout.py','tile_roundtrip_host_layout')
    shims=load(FW/'tests/native_host_test.py','tile_roundtrip_native_host').REPLACEMENTS
    s=(FW/'src/global-remote-v1/remote_native.c').read_text()
    for a,b in shims.items():
        assert a in s,'host ABI shim no longer matches production: '+a
        s=s.replace(a,b)
    (out/'remote_native_host.inc').write_text(s)
    cc=['xcrun','clang','-std=c11','-O1','-g','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-sanitize-recover=undefined']
    # 1. Firmware executable, 14 items.
    shared=['global-remote-v1/remote.c','global-remote-v1/lang_flag.c','global-remote-v1/lang_store.c','menu-grid-v2/tile_config.c',
            'diagnostics-v1/knob_calibration.c','diagnostics-v1/diagnostics.c']
    fw_exe=out/'tile-roundtrip'
    run(cc+[*host_layout.flags(),'-I',out,'-I',FW/'src/global-remote-v1','-I',FW/'src',FW/'tests/tile_roundtrip_bridge.c',
            *[FW/'src'/f for f in shared],'-o',fw_exe])
    got=run([fw_exe]).strip().split('\n')
    m=re.fullmatch(r'ROUNDTRIP items=(\d+) sends=(\d+) generation=(\d+) visible=(\d+) CameraRank=(\d+) reload=preserved',got[-1])
    assert m and len(got)==1,'firmware round trip printed %r'%got
    items,sends,generation,visible,camera=map(int,m.groups())
    assert (items,sends,generation,visible,camera)==(14,3,1,9,8),m.group(0)
    # 2. Old phone, 13 items, no base define: one version-1 TT_SET frame.
    (out/'old_phone.c').write_text(OLD_PHONE)
    phone_exe=out/'old-phone'
    run(cc+['-I',P,out/'old_phone.c',P/'tile_config.c','-o',phone_exe])
    v1=out/'frame-v1.bin';run([phone_exe,v1,TOKEN,CLIENT])
    frame=v1.read_bytes()
    assert len(frame)==32 and frame[:4]==b'TTL1' and frame[4]==1 and frame[5]==1,'old phone frame %s'%frame.hex()
    assert run([fw_exe,'--frame',v1,'refuse']).strip()=='FRAME refused: no reply, no write'
    # The same frame naming version 2, resealed with the firmware object's tt_crc: accepted.
    unsealed=out/'frame-v2-unsealed.bin';unsealed.write_bytes(frame[:4]+b'\x02'+frame[5:])
    v2=out/'frame-v2.bin';run([fw_exe,'--seal',unsealed,v2])
    second=v2.read_bytes()
    assert len(second)==32 and [i for i in range(32) if frame[i]!=second[i] and not 28<=i<32]==[4],'resealed frame differs beyond byte 4 and the CRC'
    assert run([fw_exe,'--frame',v2,'accept']).strip()=='FRAME accepted: one reply, one write'
    print('PASS firmware TTL codec/link -> native handler -> durable mock A/B -> TTA decoder (%d items): sends=%d generation=%d '
          'visible=%d CameraRank=%d; reboot reload preserved; a version-1 phone TT_SET frame is refused with no reply and no write'
          %(items,sends,generation,visible,camera))
if __name__=='__main__':main()
