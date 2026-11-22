// Host test for the glasses lock screens: what each state shows, the 3 s hint, no previous digit shown, EN and ZH text.
#include "../src/lock-v1/lock_view.h"
#include "../src/common-v1/tio_text.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned lang_now;
unsigned tio_lang(void){return lang_now;}
typedef struct {int made,destroyed,texts;const char *text[16];uint32_t color[16];void *objs[16];} Fake;
static Fake fk;
static int slot_of(void *o){for(int i=0;i<16;i++)if(fk.objs[i]==o)return i;return -1;}
static bool idle(void *c){(void)c;return true;}
static void *mk(void){static char pool[64];void *o=&pool[fk.made];fk.objs[fk.made++]=o;return o;}
static void *root(void *c,void *p){(void)c;(void)p;return mk();}
static void *label(void *c,void *p,unsigned f){(void)c;(void)p;assert(f>=16&&f<=48);return mk();}
static void place(void *c,void *o,int x,int y,int w,int h){(void)c;(void)o;assert(x>=0&&y>=0&&w>0&&h>0&&x+w<=540&&y+h<=180);}
static void text(void *c,void *o,const char *s){(void)c;fk.text[slot_of(o)]=s;fk.texts++;}
static void color(void *c,void *o,uint32_t rgb){(void)c;fk.color[slot_of(o)]=rgb;}
static void destroy(void *c,void *o){(void)c;assert(slot_of(o)==0);fk.destroyed++;}
static const TNWidgets W={.idle=idle,.root=root,.label=label,.place=place,.text_static=text,.destroy=destroy,.color=color};
#define L(i) (fk.text[1+(i)])
int main(void){
 TLKView v;assert(tlv_open(&v,&W,NULL,(void*)1)&&fk.made==1+TLV_LABELS);
 TLVScene s={.state=TLK_ENTRY,.slot=0,.digit=0,.now_ms=1000};
 assert(tlv_draw(&v,&s,0));assert(!strcmp(L(TLV_T),"Wheel: digit / Press: next")&&!strcmp(L(TLV_S0),"0")&&!strcmp(L(TLV_S1),"-")&&!strcmp(L(TLV_CARET),"^"));
 assert(fk.color[1+TLV_S0]==0x00ff00u&&fk.color[1+TLV_S1]==0x003800u);
 // Hint gone after 3 s; entered slots are dots, never the digit; the focused slot starts at 0.
 s.now_ms=4000;s.slot=2;s.digit=0;assert(tlv_draw(&v,&s,0));assert(!*L(TLV_T)&&!strcmp(L(TLV_S0),"\xc2\xb7")&&!strcmp(L(TLV_S1),"\xc2\xb7")&&!strcmp(L(TLV_S2),"0"));
 // Band T: time left and battery right, lens-mid, on the PIN screen; unknown (zero scene) shows --:-- and 0..100 only.
 assert(!strcmp(L(TLV_TIME),"--:--")&&!strcmp(L(TLV_BATT),"0%")&&fk.color[1+TLV_TIME]==fk.color[1+TLV_T]&&fk.color[1+TLV_BATT]==fk.color[1+TLV_T]);
 s.local=1800057600+3600*9+60*5;s.battery=100;assert(tlv_draw(&v,&s,0)&&!strcmp(L(TLV_TIME),"09:05")&&!strcmp(L(TLV_BATT),"100%"));
 s.local=946684799;s.battery=101;tlv_draw(&v,&s,0);assert(!strcmp(L(TLV_TIME),"--:--")&&!strcmp(L(TLV_BATT),"--%"));
 s.battery=-1;tlv_draw(&v,&s,0);assert(!strcmp(L(TLV_BATT),"--%"));s.battery=7;tlv_draw(&v,&s,0);assert(!strcmp(L(TLV_BATT),"7%"));
 s.local=0;s.battery=0;tlv_draw(&v,&s,0);
 int before=fk.texts;assert(tlv_draw(&v,&s,0)&&fk.texts==before);   // unchanged scene: no redraw
 s.digit=7;assert(tlv_draw(&v,&s,0)&&!strcmp(L(TLV_S2),"7"));
 // Wrong PIN, waiting, use phone, notice: only band M/B text, no slots.
 s=(TLVScene){.state=TLK_WRONG,.now_ms=5000};tlv_draw(&v,&s,0);assert(!strcmp(L(TLV_B),"Wrong PIN")&&!*L(TLV_S0)&&!*L(TLV_T));
 s=(TLVScene){.state=TLK_WAITING,.wrong=3,.delay_left=30,.now_ms=6000};tlv_draw(&v,&s,0);assert(!strcmp(L(TLV_M),"3 wrong tries")&&!strcmp(L(TLV_B),"Try again in 0:30"));
 s.delay_left=900;tlv_draw(&v,&s,0);assert(!strcmp(L(TLV_B),"Try again in 15:00"));
 s.delay_left=UINT32_MAX;tlv_draw(&v,&s,0);assert(!strcmp(L(TLV_B),"Use phone"));   /* no valid clock: the delay cannot end on the glasses */
 s=(TLVScene){.state=TLK_USE_PHONE};tlv_draw(&v,&s,0);assert(!strcmp(L(TLV_B),"Use phone")&&!*L(TLV_M)&&!*L(TLV_TIME)&&!*L(TLV_BATT));
 s=(TLVScene){.state=TLK_NOTICE,.notice=1};tlv_draw(&v,&s,0);assert(!strcmp(L(TLV_M),"since last unlock")&&!strcmp(L(TLV_B),"1 wrong try"));
 s.notice=12;tlv_draw(&v,&s,0);assert(!strcmp(L(TLV_B),"12 wrong tries"));
 // Chinese.
 s=(TLVScene){.state=TLK_WAITING,.wrong=4,.delay_left=61};tlv_draw(&v,&s,1);assert(!strcmp(L(TLV_B),"1:01 后重试")&&!strcmp(L(TLV_M),"4 次输入错误"));
 s=(TLVScene){.state=TLK_ENTRY,.now_ms=9000};tlv_draw(&v,&s,1);assert(!strcmp(L(TLV_T),"转动：数字 · 按下：下一位"));
 // Dark and unlocked states draw nothing.
 s=(TLVScene){.state=TLK_DARK};tlv_draw(&v,&s,0);for(int i=0;i<TLV_LABELS;i++)assert(!*L(i));
 tlv_close(&v);assert(fk.destroyed==1&&!v.open);
 // Snapshot from the core.
 TLK t;TLKRecord r;tlk_record_default(&r);r.enabled=true;r.wrong=3;r.delay_until=1000+30;tlk_boot(&t,TLK_LOAD_GOOD,&r);t.state=TLK_WAITING;
 tlv_snapshot(&s,&t,1000+10,77);assert(s.state==TLK_WAITING&&s.delay_left==20&&s.wrong==3&&s.now_ms==77&&s.local==0&&s.battery==-1);
 puts("PASS lock_view: every lock screen's text and colours, 3 s hint, dots not digits, EN and ZH, no redundant redraws");
}
