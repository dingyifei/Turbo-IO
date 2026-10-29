#include "nav_view.h"
#include "../common-v1/tio_ui.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
unsigned tio_lang(void){return 1;} /* Chinese: the strings below are the ZH table */
/* Mock widgets in allocation order: root, icon, map, distance, turn x3, road, trip x2, passing x2, scale. */
enum {Root,Icon,Map,Dist,Turn0,Turn1,Turn2,Road,Trip0,Trip1,Pass0,Pass1,Scale,Objects};
typedef struct {bool busy;unsigned alloc,fail_at,destroyed,buffers,texts,fonts[Objects];uintptr_t objects[Objects];bool shown[Objects];uint32_t color[Objects];int box[Objects][4];const uint8_t *pixels[2];const char *strings[Objects];} Mock;
static bool idle(void *p){return !((Mock *)p)->busy;}
static unsigned index_of(Mock *m,void *obj){return (unsigned)((uintptr_t *)obj-m->objects);}
static void *create(void *p,void *parent){assert(parent);Mock *m=p;unsigned n=++m->alloc;if(n==m->fail_at)return NULL;assert(n<=Objects);return &m->objects[n-1];}
static void *label(void *p,void *parent,unsigned size){assert(tio_font_native(size)&&size>=TIO_FONT_MIN);void *o=create(p,parent);if(o)((Mock *)p)->fonts[index_of(p,o)]=size;return o;}
static void place(void *p,void *obj,int x,int y,int w,int h){
 Mock *m=p;unsigned i=index_of(m,obj);assert(obj&&x>=0&&y>=0&&x+w<=TIO_PAGE_W&&y+h<=TIO_PAGE_H);
 if(i!=Root)assert(y>=TIO_PAGE_T0&&y+h<=TIO_PAGE_B1); /* nothing in the reserved rows */
 if(m->fonts[i])assert(h>=(int)m->fonts[i]+TIO_TEXT_PAD&&x>=TIO_CORE_X0&&x+w<=TIO_CORE_X1);
 m->box[i][0]=x;m->box[i][1]=y;m->box[i][2]=w;m->box[i][3]=h;
}
static unsigned map_px_checked;
static void buffer(void *p,void *obj,const uint8_t *bytes,unsigned w,unsigned h){assert(obj&&bytes);
 if(w==192){ /* no map pixel past the lens core: x = 328 + column must stay below TIO_CORE_X1 */
  for(unsigned y=0;y<h;y++)for(unsigned x=0;x<w;x++)if(bytes[y*w+x])assert(328+(int)x<TIO_CORE_X1);map_px_checked++;}
Mock *m=p;assert((w==TN_ICON_W&&h==TN_ICON_H)||(w==192&&h==144));m->pixels[m->buffers%2]=bytes;m->buffers++;}
static void text(void *p,void *obj,const char *s){assert(obj&&s);Mock *m=p;m->strings[index_of(m,obj)]=s;m->texts++;}
static void visible(void *p,void *obj,bool yes){assert(obj);Mock *m=p;m->shown[index_of(m,obj)]=yes;}
static void destroy(void *p,void *obj){assert(obj);((Mock *)p)->destroyed++;}
static void color(void *p,void *obj,uint32_t rgb){Mock *m=p;m->color[index_of(m,obj)]=rgb;}
static TNWidgets api(Mock *m){return (TNWidgets){m,idle,create,create,label,place,buffer,text,visible,destroy,NULL,color};}
static unsigned shown_of(Mock *m,unsigned first,unsigned count){unsigned n=0;for(unsigned i=first;i<first+count;i++)n+=m->shown[i];return n;}
int main(void){
 TNScene s={.icon=TN_RIGHT,.distance_m=80,.remaining_m=1200,.remaining_s=480,.point_count=3,.position={512,512},.heading=90};
 strcpy(s.road,"测试道路");strcpy(s.turn,"前方右转");s.points[0]=(TNPoint){512,1023};s.points[1]=(TNPoint){512,512};s.points[2]=(TNPoint){1023,512};
 for(unsigned fail=1;fail<=Objects;fail++){Mock m={.fail_at=fail};TNWidgets a=api(&m);TNView v={0};
  assert(!tn_view_open(&v,&a,&m,&s));assert(!v.open&&!v.root);assert(m.destroyed==(fail!=1));}
 Mock m={0};TNWidgets a=api(&m);TNView v={0};assert(tn_view_open(&v,&a,&m,&s));assert(m.alloc==Objects&&m.buffers==2);
 /* Layout: band T passing (hidden until the map names it), band M trip line, band B glyph, distance, turn, road. */
 assert(!strcmp(m.strings[Dist],"80 m")&&m.fonts[Dist]==TIO_FONT_PRIMARY&&m.shown[Dist]&&m.color[Dist]==TIO_LENS_FULL);
 assert(shown_of(&m,Turn0,3)==1&&!strcmp(m.strings[Turn0],"前方右转")&&m.color[Turn0]==TIO_LENS_FULL);
 assert(m.shown[Road]&&!strcmp(m.strings[Road],"测试道路")&&m.color[Road]==TIO_LENS_HIGH&&m.box[Road][1]==TIO_PAGE_B1-TIO_LINE(TIO_FONT_MIN));
 assert(shown_of(&m,Trip0,2)==1&&m.color[Trip0]==TIO_LENS_HIGH&&m.color[Trip1]==TIO_LENS_HIGH&&!strcmp(m.strings[Trip0],"1.2 km \xc2\xb7 8分钟 \xc2\xb7 到达时间待更新"));
 assert(m.box[Trip0][1]>=TIO_PAGE_T1&&m.box[Trip0][1]+m.box[Trip0][3]<=TIO_PAGE_M1);                    /* band M */
 assert(m.box[Dist][1]>=TIO_PAGE_M1&&m.box[Turn0][1]>=TIO_PAGE_M1&&m.box[Icon][1]>=TIO_PAGE_M1);            /* band B */
 assert(m.box[Icon][0]>=TIO_INSET_X&&m.box[Map][0]+m.box[Map][2]<=TIO_PAGE_W-TIO_INSET_X&&m.box[Map][1]+m.box[Map][3]==TIO_PAGE_B1);
 assert(m.box[Turn0][0]>=m.box[Dist][0]+m.box[Dist][2]&&m.box[Turn0][0]+m.box[Turn0][2]<=m.box[Map][0]); /* instruction follows the distance */
 assert(m.box[Turn0][1]+(int)m.fonts[Turn0]==m.box[Dist][1]+(int)TIO_FONT_PRIMARY);                      /* shared baseline */
 assert(shown_of(&m,Pass0,2)==0&&!m.shown[Scale]);
 const uint8_t *first=m.pixels[0];uint32_t original=tn_crc(first,TN_ICON_W*TN_ICON_H);
 assert(original!=tn_crc((const uint8_t[TN_ICON_W*TN_ICON_H]){0},TN_ICON_W*TN_ICON_H));
 m.busy=true;s.icon=TN_LEFT;s.distance_m=60;assert(!tn_view_update(&v,&s,false));assert(m.buffers==2&&tn_crc(first,TN_ICON_W*TN_ICON_H)==original);
 m.busy=false;assert(tn_view_update(&v,&s,false));assert(m.alloc==Objects&&m.pixels[0]!=first);assert(!strcmp(m.strings[Dist],"60 m"));
 assert(map_px_checked>=2);
 for(unsigned i=0;i<1000;i++){s.icon=(uint8_t)(i%TN_ICON_COUNT);s.heading=(uint16_t)(i%360);s.distance_m=i;assert(tn_view_update(&v,&s,i%2));
  assert(shown_of(&m,Turn0,3)==1&&shown_of(&m,Trip0,2)==1);}
 /* The turn text steps down through 24, 20, 16 px and the instruction never reaches the map. */
 strcpy(s.turn,"Continue straight and keep right at the fork");s.distance_m=100;assert(tn_view_update(&v,&s,false));
 assert(m.shown[Turn2]&&shown_of(&m,Turn0,3)==1&&m.fonts[Turn2]==TIO_FONT_MIN);
 strcpy(s.turn,"前方右转");assert(tn_view_update(&v,&s,false));assert(m.shown[Turn0]);
 s.turn[0]=0;assert(tn_view_update(&v,&s,false));assert(shown_of(&m,Turn0,3)==0);
 assert(m.alloc==Objects);m.busy=true;assert(!tn_view_close(&v));assert(v.retiring&&m.destroyed==0);assert(!tn_view_update(&v,&s,false));
 m.busy=false;assert(tn_view_close(&v)&&m.destroyed==1);assert(tn_view_close(&v)&&m.destroyed==1);
 /* Trip line: summary, middle dot, arrival time. The clock only changes the arrival time; semantic updates keep the pointer. */
 Mock cm={0};TNWidgets ca=api(&cm);TNView cv={0};s.turn[0]='x';s.turn[1]=0;s.distance_m=80;s.remaining_s=480;assert(tn_view_open(&cv,&ca,&cm,&s));
 int64_t epoch=946684800+23*3600+59*60;
 assert(tn_view_clock(&cv,epoch,epoch+120,false));assert(!strcmp(cm.strings[Trip0],"1.2 km \xc2\xb7 8分钟 \xc2\xb7 明日 00:01")&&cm.shown[Trip0]&&!cm.shown[Trip1]);
 const char *retained=cm.strings[Trip0];char retained_copy[128];memcpy(retained_copy,retained,sizeof retained_copy);
 unsigned texts=cm.texts,buffers=cm.buffers;
 assert(tn_view_clock(&cv,epoch+1,epoch+120,false));assert(cm.texts==texts);                                   /* same text: no repaint */
 cm.busy=true;assert(!tn_view_clock(&cv,epoch+60,epoch+180,false));assert(!memcmp(retained,retained_copy,sizeof retained_copy));
 cm.busy=false;assert(tn_view_clock(&cv,epoch+60,epoch+180,false));assert(cm.strings[Trip0]!=retained&&cm.buffers==buffers&&cm.alloc==Objects);
 assert(strstr(cm.strings[Trip0],"00:02")&&!strstr(cm.strings[Trip0],"明日"));
 assert(tn_view_clock(&cv,epoch,epoch+120,true));assert(!strcmp(cm.strings[Trip0],"导航数据已过期 \xc2\xb7 请查看手机"));
 assert(cm.shown[Trip0]&&!cm.shown[Trip1]);
 const char *footer=cm.strings[Trip0];char footer_copy[128];memcpy(footer_copy,footer,sizeof footer_copy);
 for(unsigned i=0;i<1000;i++){s.mode=i%2?TN_ALWAYS:TN_SMART;s.distance_m=i;assert(tn_view_update(&cv,&s,false));
  assert(cv.trip_shown&&cm.strings[Trip0]==footer&&!memcmp(footer,footer_copy,sizeof footer_copy));
  assert(!strstr(cm.strings[Trip0],"常亮")&&!strstr(cm.strings[Trip0],"无更新息屏"));}
 assert(tn_view_clock(&cv,epoch,epoch+120,false));assert(strstr(cm.strings[Trip0],"1.2 km")&&strstr(cm.strings[Trip0],"明日 00:01"));
 footer=cm.strings[Trip0];memcpy(footer_copy,footer,sizeof footer_copy);
 assert(tn_view_update(&cv,&s,true)&&cm.strings[Trip0]==footer&&!memcmp(footer,footer_copy,sizeof footer_copy));
 s.remaining_m=5400;assert(tn_view_update(&cv,&s,false));assert(strstr(cm.strings[Trip0],"5.4 km"));               /* a new summary re-composes the line */
 s.remaining_m=10000000;s.remaining_s=604800;assert(tn_view_update(&cv,&s,false));assert(cm.shown[Trip1]&&!cm.shown[Trip0]);   /* a long line steps down to 16 px, never below */
 assert(tn_view_close(&cv));assert(!tn_view_clock(&cv,epoch,epoch+120,false));
 printf("PASS bounded two-bank LVGL view facade, %u allocation failures, LensNav bands/baseline/intensity, trip line owner, immutable referenced points/text/pixels, 1000 updates no new objects, busy retirement; view=%zu bytes. Mock widgets only.\n",Objects,sizeof(TNView));
 return 0;
}
