// Host test for the glasses lock screens (TMG16 layout, docs/lock-design.md §3): what each state shows, the hint and its
// fade, the drawn digit and its glyph table, dots and track bars (shapes, never text), the caret under the focused slot,
// EN and ZH text, no redundant redraws, and every canvas buffer 64-byte aligned (the stock draw rounds the pointer up to 64).
#include "../src/lock-v1/lock_view.h"
#include "../src/lock-v1/lock_glyphs.h"
#include "../src/common-v1/tio_text.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned lang_now;
unsigned tio_lang(void){return lang_now;}
enum {MAXO=32};
typedef struct {int made,destroyed,texts,places,buffers;void *objs[MAXO];const char *text[MAXO];uint32_t color[MAXO];unsigned font[MAXO];
 int x[MAXO],y[MAXO],w[MAXO],h[MAXO];bool shown[MAXO],canvas[MAXO];const uint8_t *px[MAXO];unsigned pw[MAXO],ph[MAXO];} Fake;
static Fake fk;
static int slot_of(void *o){for(int i=0;i<fk.made;i++)if(fk.objs[i]==o)return i;return -1;}
static bool idle(void *c){(void)c;return true;}
static char pool[MAXO];
static void *mk(void){assert(fk.made<MAXO);void *o=&pool[fk.made];fk.objs[fk.made++]=o;return o;}
static int fail_at=-1;   // make the n-th widget fail
static void *maybe(void){if(fail_at==fk.made)return NULL;return mk();}
static void *root(void *c,void *p){(void)c;(void)p;return maybe();}
static void *label(void *c,void *p,unsigned f){(void)c;(void)p;assert(f>=16&&f<=TIO_FONT_PRIMARY);void *o=maybe();if(o)fk.font[slot_of(o)]=f;return o;}
static void *canvas(void *c,void *p){(void)c;(void)p;void *o=maybe();if(o)fk.canvas[slot_of(o)]=true;return o;}
static void place(void *c,void *o,int x,int y,int w,int h){(void)c;assert(x>=0&&y>=0&&w>0&&h>0&&x+w<=540&&y+h<=180);int i=slot_of(o);fk.x[i]=x;fk.y[i]=y;fk.w[i]=w;fk.h[i]=h;fk.places++;}
static void buffer(void *c,void *o,const uint8_t *d,unsigned w,unsigned h){
 (void)c;int i=slot_of(o);assert(fk.canvas[i]&&d&&((uintptr_t)d&63)==0);   // every lock canvas buffer is 64-byte aligned
 fk.px[i]=d;fk.pw[i]=w;fk.ph[i]=h;fk.buffers++;}
static void visible(void *c,void *o,bool on){(void)c;fk.shown[slot_of(o)]=on;}
static void text(void *c,void *o,const char *s){(void)c;fk.text[slot_of(o)]=s;fk.texts++;}
static void color(void *c,void *o,uint32_t rgb){(void)c;fk.color[slot_of(o)]=rgb;}
static void destroy(void *c,void *o){(void)c;assert(slot_of(o)==0);fk.destroyed++;}
static const TNWidgets W={.idle=idle,.root=root,.canvas=canvas,.label=label,.place=place,.buffer=buffer,.text_static=text,.visible=visible,.destroy=destroy,.color=color};
static TLKView *v;
static int obj(void *o){return slot_of(o);}
#define LBL(i) (obj(v->labels[i]))
#define CNV(i) (obj(v->canvas[i]))
static const char *L(unsigned i){int k=LBL(i);return fk.shown[k]&&fk.text[k]?fk.text[k]:"";}
static bool on(unsigned i){return fk.shown[CNV(i)];}
// Nothing but the five labels is text, and only the shown ones carry any.
static void no_digit_text(void){for(int i=0;i<fk.made;i++)if(fk.shown[i]&&!fk.canvas[i]&&fk.text[i]){const char *t=fk.text[i];assert(!(t[0]>='0'&&t[0]<='9'&&!t[1]));}}
static void check_entry(const TLVScene *s){
 const unsigned slot=s->slot;
 for(unsigned i=0;i<TLK_PIN_LEN;i++){
  const int cx=tlv_slot_cx(i);
  assert(on(TLV_DOT0+i)==(i<slot)&&on(TLV_TRACK0+i)==(i>slot));
  if(i<slot){int k=CNV(TLV_DOT0+i);assert(fk.x[k]+fk.w[k]/2==cx&&fk.y[k]+fk.h[k]/2==TLV_DOT_CY&&fk.px[k]==v->dot_px&&fk.w[k]==TLV_DOT);}
  if(i>slot){int k=CNV(TLV_TRACK0+i);assert(fk.x[k]+fk.w[k]/2==cx&&fk.y[k]==TLV_CARET_Y&&fk.w[k]==TIO_CARET_W&&fk.h[k]==TIO_CARET_H&&fk.px[k]==v->track_px);}
 }
 int g=CNV(TLV_GLYPH),c=CNV(TLV_CARET);const int cx=tlv_slot_cx(slot);
 assert(on(TLV_GLYPH)&&on(TLV_CARET));
 assert(fk.x[g]==cx-TLV_GLYPH_W/2&&fk.y[g]==TLV_GLYPH_Y&&fk.w[g]==TLV_GLYPH_W&&fk.h[g]==TLV_GLYPH_H&&fk.px[g]==v->glyph&&fk.pw[g]==TLV_GLYPH_W&&fk.ph[g]==TLV_GLYPH_H);
 assert(fk.x[c]==cx-TIO_CARET_W/2&&fk.y[c]==TLV_GLYPH_Y+TLV_GLYPH_H+TIO_CARET_GAP&&fk.w[c]==TIO_CARET_W&&fk.h[c]==TIO_CARET_H&&fk.px[c]==v->caret_px);
 // band B holds the glyph, the dots, the bars and the caret
 for(unsigned i=0;i<TLV_CANVASES;i++)if(on(i)){int k=CNV(i);assert(fk.y[k]>=TIO_PAGE_M1&&fk.y[k]+fk.h[k]<=TIO_PAGE_B1);}
 // the glyph is the digit's table entry, expanded to 0..255
 const unsigned char *p=tlv_glyph4[s->digit%10];for(unsigned i=0;i<TLV_GLYPH_W*TLV_GLYPH_H;i++)assert(v->glyph[i]==((p[i/2]>>(i%2?0:4))&15)*17);
 assert(!*L(TLV_M)&&!*L(TLV_B));no_digit_text();
}
int main(void){
 v=aligned_alloc(64,sizeof *v);assert(v);
 // Alignment of every buffer (the struct and each member), and the open refuses a misaligned view or a table without canvases.
 assert(_Alignof(TLKView)==64);
 for(unsigned i=0;i<TLV_CANVASES;i++)assert(((uintptr_t)tlv_canvas_pixels(v,i)&63)==0);
 {static const TNWidgets nocanvas={.idle=idle,.root=root,.label=label,.place=place,.text_static=text,.destroy=destroy,.color=color,.visible=visible};assert(!tlv_open(v,&nocanvas,NULL,(void*)1));}
 {uint8_t *raw=aligned_alloc(64,sizeof *v+64),*mis=raw;assert(raw);mis+=sizeof(uint64_t);assert(!tlv_open((TLKView *)(void *)mis,&W,NULL,(void*)1));free(raw);}   // 8 bytes off the 64 boundary
 // A widget that cannot be made: the open fails cleanly at every point.
 for(int f=0;f<1+TLV_LABELS+TLV_CANVASES;f++){memset(&fk,0,sizeof fk);fail_at=f;assert(!tlv_open(v,&W,NULL,(void*)1)&&!v->open);assert(fk.destroyed==(f>0));}
 fail_at=-1;memset(&fk,0,sizeof fk);
 assert(tlv_open(v,&W,NULL,(void*)1)&&fk.made==1+TLV_LABELS+TLV_CANVASES);
 for(unsigned i=0;i<TLV_CANVASES;i++){int k=CNV(i);assert(fk.canvas[k]&&!fk.shown[k]);if(i!=TLV_GLYPH)assert(fk.px[k]==tlv_canvas_pixels(v,i));}
 for(unsigned i=0;i<sizeof v->caret_px;i++)assert(v->caret_px[i]==0xff&&v->track_px[i]==(TIO_LENS_TRACK>>8&255));
 {unsigned top=0,lit=0;for(unsigned i=0;i<sizeof v->dot_px;i++){if(v->dot_px[i]>top)top=v->dot_px[i];lit+=v->dot_px[i]>0;}assert(top==(TIO_LENS_HIGH>>8&255)&&v->dot_px[0]==0&&lit>60&&lit<100);}
 assert(fk.font[LBL(TLV_HINT)]==TIO_FONT_LABEL&&fk.font[LBL(TLV_TIME)]==TIO_FONT_LABEL&&fk.font[LBL(TLV_M)]==TIO_FONT_BODY&&fk.font[LBL(TLV_B)]==TIO_FONT_PRIMARY);
 // Band T: the hint and the time/battery boxes share the hint row.
 {int h=LBL(TLV_HINT),t=LBL(TLV_TIME),b=LBL(TLV_BATT);assert(fk.y[h]==fk.y[t]&&fk.y[t]==fk.y[b]&&fk.y[h]>=TIO_PAGE_T0&&fk.y[h]+fk.h[h]<=TIO_PAGE_T1&&fk.x[t]==TIO_CORE_X0&&fk.x[b]+fk.w[b]==TIO_CORE_X1);}
 // The PIN screen opens: hint in lens-high, no time or battery, slot 0 focused with the drawn 0.
 TLVScene s={.state=TLK_ENTRY,.slot=0,.digit=0,.now_ms=1000,.local=946684800+10*3600+24*60,.battery=82};
 assert(tlv_draw(v,&s,0));assert(!strcmp(L(TLV_HINT),"Wheel: digit / Press: next")&&fk.color[LBL(TLV_HINT)]==TIO_LENS_HIGH&&!*L(TLV_TIME)&&!*L(TLV_BATT));
 check_entry(&s);
 // Unchanged scene: no widget call at all.
 {int t=fk.texts,p=fk.places,b=fk.buffers;assert(tlv_draw(v,&s,0)&&fk.texts==t&&fk.places==p&&fk.buffers==b);}
 // The fade: the last TIO_HINT_FADE_MS dim the hint below lens-high, then it is gone and time + battery show in lens-mid.
 s.now_ms=1000+TIO_HINT_MS-TIO_HINT_FADE_MS/2;assert(tlv_draw(v,&s,0));{uint32_t c=fk.color[LBL(TLV_HINT)];assert(*L(TLV_HINT)&&c>0&&c<TIO_LENS_HIGH);}
 s.now_ms=1000+TIO_HINT_MS;assert(tlv_draw(v,&s,0));assert(!*L(TLV_HINT)&&!strcmp(L(TLV_TIME),"10:24")&&!strcmp(L(TLV_BATT),"82%")&&fk.color[LBL(TLV_TIME)]==TIO_LENS_MID&&fk.color[LBL(TLV_BATT)]==TIO_LENS_MID);
 // An input (a new digit) brings the hint back for another 3 s.
 s.now_ms=5000;s.digit=3;assert(tlv_draw(v,&s,0)&&*L(TLV_HINT)&&!*L(TLV_TIME));check_entry(&s);
 s.now_ms=8100;assert(tlv_draw(v,&s,0)&&!*L(TLV_HINT)&&*L(TLV_TIME));
 // Unknown time and battery.
 s.local=946684799;s.battery=101;tlv_draw(v,&s,0);assert(!strcmp(L(TLV_TIME),"--:--")&&!strcmp(L(TLV_BATT),"--%"));
 s.local=1800057600+3600*9+60*5;s.battery=100;tlv_draw(v,&s,0);assert(!strcmp(L(TLV_TIME),"09:05")&&!strcmp(L(TLV_BATT),"100%"));
 s.battery=-1;tlv_draw(v,&s,0);assert(!strcmp(L(TLV_BATT),"--%"));s.battery=7;tlv_draw(v,&s,0);assert(!strcmp(L(TLV_BATT),"7%"));
 // Every digit in every slot: dots before, bars after, the glyph and the caret over the slot, no digit as text.
 for(unsigned slot=0;slot<TLK_PIN_LEN;slot++)for(unsigned d=0;d<10;d++){s.slot=(uint8_t)slot;s.digit=(uint8_t)d;s.now_ms+=500;assert(tlv_draw(v,&s,0));check_entry(&s);}
 // The glyph buffer is decoded again only when the digit changes (a new slot with the same digit keeps it).
 {s.slot=1;s.digit=4;s.now_ms+=500;tlv_draw(v,&s,0);int b=fk.buffers;s.slot=2;s.now_ms+=500;tlv_draw(v,&s,0);assert(fk.buffers==b);check_entry(&s);s.digit=5;s.now_ms+=500;tlv_draw(v,&s,0);assert(fk.buffers==b+1);}
 // The glyph tables: each digit has ink, full-level strokes, a clear 1 px border, and no two digits are the same.
 for(unsigned d=0;d<10;d++){
  unsigned full=0,lit=0;const unsigned char *p=tlv_glyph4[d];
  for(unsigned y=0;y<TLV_GLYPH_H;y++)for(unsigned x=0;x<TLV_GLYPH_W;x++){unsigned i=y*TLV_GLYPH_W+x,n=(p[i/2]>>(i%2?0:4))&15;full+=n==15;lit+=n>0;if(x==0||y==0||x==TLV_GLYPH_W-1||y==TLV_GLYPH_H-1)assert(n<15);}
  assert(full>150&&lit<TLV_GLYPH_W*TLV_GLYPH_H/2);
  for(unsigned e=0;e<d;e++)assert(memcmp(tlv_glyph4[d],tlv_glyph4[e],sizeof tlv_glyph4[d]));
 }
 // Wrong PIN, waiting, use phone, notice: band M and band B text only, no slot, no glyph, no caret.
 s=(TLVScene){.state=TLK_WRONG,.now_ms=90000};tlv_draw(v,&s,0);assert(!strcmp(L(TLV_B),"Wrong PIN")&&!*L(TLV_M)&&!*L(TLV_HINT)&&!*L(TLV_TIME)&&fk.color[LBL(TLV_B)]==TIO_LENS_FULL);
 for(unsigned i=0;i<TLV_CANVASES;i++)assert(!on(i));
 s=(TLVScene){.state=TLK_WAITING,.wrong=3,.delay_left=30,.now_ms=91000};tlv_draw(v,&s,0);assert(!strcmp(L(TLV_M),"3 wrong tries")&&!strcmp(L(TLV_B),"Try again in 0:30")&&fk.color[LBL(TLV_M)]==TIO_LENS_HIGH);
 s.delay_left=900;tlv_draw(v,&s,0);assert(!strcmp(L(TLV_B),"Try again in 15:00"));
 s.delay_left=UINT32_MAX;tlv_draw(v,&s,0);assert(!strcmp(L(TLV_B),"Use phone"));   /* no valid clock: the delay cannot end on the glasses */
 s=(TLVScene){.state=TLK_USE_PHONE};tlv_draw(v,&s,0);assert(!strcmp(L(TLV_B),"Use phone")&&!*L(TLV_M)&&!*L(TLV_TIME)&&!*L(TLV_BATT));
 s=(TLVScene){.state=TLK_NOTICE,.notice=1};tlv_draw(v,&s,0);assert(!strcmp(L(TLV_M),"since last unlock")&&!strcmp(L(TLV_B),"1 wrong try"));
 s.notice=12;tlv_draw(v,&s,0);assert(!strcmp(L(TLV_B),"12 wrong tries"));
 {int t=fk.texts;tlv_draw(v,&s,0);assert(fk.texts==t);}
 // Message rows: band M and band B, across the core (centred by the native side).
 {int m=LBL(TLV_M),b=LBL(TLV_B);assert(fk.y[m]==TLV_MSG_M_Y&&fk.y[m]>=TIO_PAGE_T1&&fk.y[m]+fk.h[m]<=TIO_PAGE_M1&&fk.y[b]==TLV_MSG_B_Y&&fk.y[b]>=TIO_PAGE_M1&&fk.y[b]+fk.h[b]<=TIO_PAGE_B1&&fk.x[b]==TIO_CORE_X0&&fk.w[b]==TIO_CORE_W);}
 // Chinese.
 s=(TLVScene){.state=TLK_WAITING,.wrong=4,.delay_left=61};tlv_draw(v,&s,1);assert(!strcmp(L(TLV_B),"1:01 后重试")&&!strcmp(L(TLV_M),"4 次输入错误"));
 s=(TLVScene){.state=TLK_ENTRY,.now_ms=99000};tlv_draw(v,&s,1);assert(!strcmp(L(TLV_HINT),"转动：数字 · 按下：下一位"));check_entry(&s);
 // Back to the PIN screen after another state: the hint shows again from the new entry.
 s=(TLVScene){.state=TLK_WRONG,.now_ms=100000};tlv_draw(v,&s,0);s=(TLVScene){.state=TLK_ENTRY,.now_ms=100500};tlv_draw(v,&s,0);assert(*L(TLV_HINT));
 // Dark and unlocked states draw nothing.
 s=(TLVScene){.state=TLK_DARK};tlv_draw(v,&s,0);for(int i=0;i<TLV_LABELS;i++)assert(!*L((unsigned)i));for(unsigned i=0;i<TLV_CANVASES;i++)assert(!on(i));
 tlv_close(v);assert(fk.destroyed==1&&!v->open);
 // Snapshot from the core.
 TLK t;TLKRecord r;tlk_record_default(&r);r.enabled=true;r.wrong=3;r.delay_until=1000+30;tlk_boot(&t,TLK_LOAD_GOOD,&r);t.state=TLK_WAITING;
 tlv_snapshot(&s,&t,1000+10,77);assert(s.state==TLK_WAITING&&s.delay_left==20&&s.wrong==3&&s.now_ms==77&&s.local==0&&s.battery==-1);
 // "Unlocked" (phone unlock) in band B, EN and ZH.
 memset(&fk,0,sizeof fk);assert(tlv_open(v,&W,NULL,(void*)1));
 s=(TLVScene){.state=TLK_UNLOCKED_MSG,.now_ms=9000};assert(tlv_draw(v,&s,0)&&!strcmp(L(TLV_B),"Unlocked")&&!on(TLV_GLYPH));
 assert(tlv_draw(v,&s,1)&&!strcmp(L(TLV_B),"\xe5\xb7\xb2\xe8\xa7\xa3\xe9\x94\x81"));
 tlv_close(v);free(v);
 puts("PASS lock_view: every lock screen's text and colours, hint with fade and re-show on input, drawn digit 0-9 in every slot over the 24x3 caret, dots and track bars, EN and ZH, no redundant redraws, the phone's Unlocked, every canvas buffer 64-byte aligned");
}
