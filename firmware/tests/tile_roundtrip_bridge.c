/* The firmware half of ios-addon/tests/tile_roundtrip.py (14-item model, compiled with the tree's
 * base flags). It runs the real controller bodies of remote_native.c through native_remote_test.c's host stubs and the
 * firmware tile_config.c codec; it is never linked with the phone's tile_config.c (13 items).
 *   tile-roundtrip                         TTL encode -> native handler -> durable mock A/B -> TTA decode, then a reboot
 *   tile-roundtrip --frame F refuse|accept  one 32-byte TTL frame written elsewhere (the old-phone program), sent after
 *                                          a version-2 query from the frame's client: refuse = no reply and no write,
 *                                          accept = one TT_OK reply and one durable write
 *   tile-roundtrip --seal IN OUT           OUT = IN with bytes 28..31 set to this object's tt_crc of bytes 0..27 */
#define main native_remote_baseline_main
#include "native_remote_test.c"
#undef main
static unsigned sends;
static void boot(void){reset();assert(fm_menu_rows()==3);(void)fm_tiles_apply(app);}
static void reboot(void){free(timer.user);timer=(HostTimer){0};assert(fm_menu_rows()==3);(void)fm_tiles_apply(app);}
/* One TTL frame through the native handler; true when a TTA reply came back, decoded into *r. */
static bool send_raw(const uint8_t raw[32],TTReply *r){
 uint8_t wire[74],back[32];sends++;tt_carrier(wire,raw,false);TIONativeMessage m={.id=TIO_STOCK_MESSAGE_RNLINK,.bytes=74,.data=wire};
 memset(reply_wire,0,sizeof reply_wire);tgr_native_message(&m);
 for(unsigned i=0;i<sizeof reply_wire;i++)if(reply_wire[i]){assert(tt_uncarrier(reply_wire,74,back,true)&&tt_reply_decode(back,32,r));return true;}
 return false;
}
static TTReply send_command(TTCommand q){uint8_t raw[32];TTReply r;tt_encode(raw,&q);assert(send_raw(raw,&r));return r;}
static void read_frame(const char *path,uint8_t raw[32]){FILE *f=fopen(path,"rb");assert(f);size_t n=fread(raw,1,32,f);int extra=fgetc(f);assert(n==32&&extra==EOF&&!fclose(f));}
static uint32_t le32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static int roundtrip(void){
 boot();sends=0;
 TTReply r=send_command((TTCommand){.op=TT_QUERY,.request=1,.client=2});assert(r.result==TT_OK&&r.token==77&&r.generation==0&&sends==1);
 /* Stock ids 0..7 in place, the module tiles reversed (13..8), every hideable module tile hidden. */
 TTConfig want;tt_default(&want);for(unsigned i=0;i<TT_MODULE;i++)want.order[TT_STOCK+i]=(uint8_t)(TT_CAMERA-i);want.hide=TT_HIDEABLE;
 uint16_t rank;assert(tt_valid(&want)&&tt_rank(&want,&rank));
 r=send_command((TTCommand){.op=TT_SET,.request=2,.client=2,.token=77,.generation=0,.rank=rank,.hide=TT_HIDEABLE});
 assert(r.result==TT_OK&&r.generation==1&&r.rank==rank&&r.hide==TT_HIDEABLE&&r.count==TT_MIN_VISIBLE&&r.token==0&&sends==2&&writes==1);
 assert(fm_tile_count()==TT_MIN_VISIBLE&&fm_tile_rank(TT_CAMERA)==TT_STOCK);
 reboot();assert(fm_tile_count()==TT_MIN_VISIBLE&&fm_tile_rank(TT_CAMERA)==TT_STOCK);
 r=send_command((TTCommand){.op=TT_QUERY,.request=3,.client=2});assert(r.result==TT_OK&&r.generation==1&&r.rank==rank&&r.hide==TT_HIDEABLE&&r.count==TT_MIN_VISIBLE&&sends==3);
 printf("ROUNDTRIP items=%u sends=%u generation=%u visible=%u CameraRank=%u reload=preserved\n",(unsigned)TT_ITEMS,sends,(unsigned)r.generation,fm_tile_count(),fm_tile_rank(TT_CAMERA));
 reset();return 0;
}
static int frame(const char *path,const char *expect){
 bool accept=!strcmp(expect,"accept");assert(accept||!strcmp(expect,"refuse"));
 uint8_t raw[32];read_frame(path,raw);
 boot();sends=0;
 /* A session for the frame's client: the frame carries the token the stub nonce issues (77) and generation 0. */
 TTReply q=send_command((TTCommand){.op=TT_QUERY,.request=1,.client=le32(raw+20)});assert(q.result==TT_OK&&q.token==77&&q.generation==0&&le32(raw+12)==q.token);
 unsigned w=writes;TTReply r;bool replied=send_raw(raw,&r);
 if(accept){assert(replied&&r.result==TT_OK&&r.op==TT_SET&&r.generation==1&&writes==w+1);puts("FRAME accepted: one reply, one write");}
 else{assert(!replied&&writes==w);puts("FRAME refused: no reply, no write");}
 reset();return 0;
}
static int seal(const char *in,const char *out){
 uint8_t raw[32];read_frame(in,raw);uint32_t c=tt_crc(raw,28);for(unsigned i=0;i<4;i++)raw[28+i]=(uint8_t)(c>>(8*i));
 FILE *f=fopen(out,"wb");assert(f&&fwrite(raw,1,32,f)==32&&!fclose(f));return 0;
}
int main(int argc,char **argv){
 if(argc==1)return roundtrip();
 if(argc==4&&!strcmp(argv[1],"--frame"))return frame(argv[2],argv[3]);
 if(argc==4&&!strcmp(argv[1],"--seal"))return seal(argv[2],argv[3]);
 fprintf(stderr,"usage: tile-roundtrip [--frame FILE refuse|accept | --seal IN OUT]\n");return 2;
}
