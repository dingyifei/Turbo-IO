#include "../src/focus-v1/focus_menu.h"
#include "../src/common-v1/tio_text.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {bool idle;unsigned made,fail,destroyed,text_calls;const char *texts[64];bool visible[64];} Fake;
static bool idle(void *ctx){return ((Fake *)ctx)->idle;}
static void *create(void *ctx,void *parent){(void)parent;Fake *f=ctx;unsigned n=++f->made;return n==f->fail?NULL:(void *)(uintptr_t)n;}
static void *label(void *ctx,void *parent,unsigned font){assert(font==18);return create(ctx,parent);}
static void place(void *ctx,void *obj,int x,int y,int w,int h){(void)ctx;(void)obj;assert(x>=0&&y>=0&&w>0&&h>0&&x+w<=540&&y+h<=220);}
static void buffer(void *ctx,void *obj,const uint8_t *p,unsigned w,unsigned h){(void)ctx;(void)obj;assert(p);assert((w==32&&h==32)||(w==40&&h==40)||(w==FM_FRAME_W&&(h==38||h==46))||(w==36&&h==4));}
static void text(void *ctx,void *obj,const char *s){Fake *f=ctx;assert(strlen(s)<64);f->texts[(uintptr_t)obj]=s;f->text_calls++;}
static void visible(void *ctx,void *obj,bool show){((Fake *)ctx)->visible[(uintptr_t)obj]=show;}
static void destroy(void *ctx,void *obj){assert(obj);((Fake *)ctx)->destroyed++;}
static bool attach(void *obj,void *owner){return obj&&owner;}
static unsigned g_lang;
unsigned tio_lang(void){return g_lang;}
static FMView view;
typedef struct {int x,y;unsigned weights[9];bool moving,page;} Motion;
static void wrap_motion(FMView *v){
 const unsigned offsets[]={0,15,16,32,119,120,159,160,176};Motion expected[9];
 for(unsigned rows=2;rows<=3;rows++)for(unsigned page=0;page<2;page++)for(unsigned pass=0;pass<2;pass++){
  assert(fm_view_rows(v,rows));fm_view_suspend(v);uint32_t start=pass?UINT32_MAX-7:10000;int from=page?(int)(rows*3-1):0,to=from+1;
  assert(fm_view_update(v,from,0,0,start-200)&&fm_view_update(v,to,0,0,start));
  for(unsigned j=0;j<9;j++){bool drew=fm_view_step(v,start+offsets[j]);if(j<2)assert(!drew);if(j==2)assert(drew);Motion actual={.x=v->frame_x,.y=v->frame_y,.moving=v->moving,.page=v->page_motion};memcpy(actual.weights,v->weights,sizeof actual.weights);
   if(!pass)expected[j]=actual;else{assert(actual.x==expected[j].x&&actual.y==expected[j].y&&actual.moving==expected[j].moving&&actual.page==expected[j].page&&!memcmp(actual.weights,expected[j].weights,sizeof actual.weights));}
  }assert(!v->moving&&!v->page_motion&&!fm_view_step(v,start+1000));
  // Latest selection replaces an interrupted animation; it never queues input.
  for(unsigned j=0;j<400;j++){uint32_t now=start+2000+7*j;assert(fm_view_update(v,(int)(j%v->tiles.count),0,0,now));(void)fm_view_step(v,now+16);}
  assert(fm_view_update(v,v->tiles.count-1,0,0,start+6000));(void)fm_view_step(v,start+6160);assert(v->selected==v->tiles.count-1&&!v->moving);
 }
}
int main(void){
 Fake f={.idle=true};TNWidgets api={&f,idle,create,create,label,place,buffer,text,visible,destroy,NULL,NULL};
 assert(FM_ITEMS==13&&fm_view_open(&view,&api,&f,attach,&f));assert(f.made==23);
 assert(fm_view_update(&view,8,1704067200,75,0));assert(!strcmp(f.texts[(uintptr_t)view.labels[8]],tio_text(TT_TILE_NAVIGATION,0)));
 for(unsigned j=0;j<9;j++)assert(f.texts[(uintptr_t)view.labels[j]]&&f.visible[(uintptr_t)view.labels[j]]);
 const char *before=f.texts[(uintptr_t)view.labels[8]];unsigned calls=f.text_calls;g_lang=1;
 assert(fm_view_update(&view,8,1704067200,75,1));assert(f.text_calls==calls+1);assert(f.texts[(uintptr_t)view.labels[8]]==before);
 calls=f.text_calls;fm_view_suspend(&view);assert(fm_view_update(&view,8,1704067200,75,2));assert(f.text_calls==calls+10);assert(!strcmp(f.texts[(uintptr_t)view.labels[8]],tio_text(TT_TILE_NAVIGATION,1)));
 for(int i=0;i<13;i++){assert(fm_view_update(&view,i,1704067200,75,(unsigned)(1000+i*200)));assert(!strcmp(f.texts[(uintptr_t)view.status],"00:00   75%"));}
 const unsigned names[]={TT_GRID_0,TT_GRID_1,TT_GRID_2,TT_GRID_3,TT_GRID_4,TT_GRID_5,TT_GRID_6,TT_GRID_DISPLAY,TT_TILE_NAVIGATION,TT_TILE_MUSIC,TT_TILE_FOCUS,TT_TILE_APPS,TT_TILE_CAMERA};
 for(unsigned rows=2;rows<=3;rows++)for(unsigned rank=0;rank<720;rank+=119)for(unsigned hide=0;hide<32;hide++){
  TTConfig config;TTVisible tiles;assert(tt_unrank(rank,hide<<7,&config)&&tt_compact(&config,&tiles));assert(fm_view_rows(&view,rows)&&fm_view_tiles(&view,&tiles));
  for(unsigned selected=0;selected<tiles.count;selected++){
   assert(fm_view_update(&view,(int)selected,1704067200,75,10000+selected*200));unsigned per=rows*3;
   for(unsigned cell=0;cell<9;cell++){unsigned at=selected/per*per+cell;bool show=cell<per&&at<tiles.count;assert(f.visible[(uintptr_t)view.labels[cell]]==show);if(show)assert(!strcmp(f.texts[(uintptr_t)view.labels[cell]],tio_text(names[tiles.ids[at]],g_lang)));}
  }
  assert(!fm_view_update(&view,tiles.count,0,0,20000));
 }
 TTConfig defaults;TTVisible defaults_map;tt_default(&defaults);tt_compact(&defaults,&defaults_map);assert(fm_view_tiles(&view,&defaults_map));
 assert(!fm_view_update(&view,-1,0,0,5000)&&!fm_view_update(&view,13,0,0,5000));
 wrap_motion(&view);
 f.idle=false;assert(!fm_view_update(&view,0,0,0,5000)&&!fm_view_close(&view));f.idle=true;
 assert(fm_view_close(&view)&&f.destroyed==1);
 for(unsigned fail=1;fail<=23;fail++){f=(Fake){.idle=true,.fail=fail};assert(!fm_view_open(&view,&api,&f,attach,&f));assert(!view.root);assert(f.destroyed==(fail==1?0:1));}
 puts("PASS focus_grid: mapped rows/pages/labels, 16/120/160ms timer wrap, interrupted motion, bounds and allocation failures");
}
