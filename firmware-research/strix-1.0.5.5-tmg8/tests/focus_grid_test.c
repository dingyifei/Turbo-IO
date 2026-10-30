#include "../src/focus-v1/focus_menu.h"
#include "../src/common-v1/tio_text.h"
#include "../src/common-v1/tio_ui.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {bool idle;unsigned made,fail,destroyed,text_calls;const char *texts[64];bool visible[64];int x[64],y[64],w[64],h[64];} Fake;
static bool idle(void *ctx){return ((Fake *)ctx)->idle;}
static void *create(void *ctx,void *parent){(void)parent;Fake *f=ctx;unsigned n=++f->made;return n==f->fail?NULL:(void *)(uintptr_t)n;}
static void *label(void *ctx,void *parent,unsigned font){assert(font==16||font==18||font==24);return create(ctx,parent);}   /* cell names 16, status 18, focused name 24 */
static void place(void *ctx,void *obj,int x,int y,int w,int h){assert(x>=0&&y>=0&&w>0&&h>0&&x+w<=540&&y+h<=220);Fake *f=ctx;uintptr_t k=(uintptr_t)obj;f->x[k]=x;f->y[k]=y;f->w[k]=w;f->h[k]=h;}
static void buffer(void *ctx,void *obj,const uint8_t *p,unsigned w,unsigned h){(void)ctx;(void)obj;assert(p);assert((w==32&&h==32)||(w==28&&h==28)||(w==FM_CARET_W&&h==FM_CARET_H)||(w==36&&h==4));}
static void text(void *ctx,void *obj,const char *s){Fake *f=ctx;assert(strlen(s)<64);f->texts[(uintptr_t)obj]=s;f->text_calls++;}
static void visible(void *ctx,void *obj,bool show){((Fake *)ctx)->visible[(uintptr_t)obj]=show;}
static void destroy(void *ctx,void *obj){assert(obj);((Fake *)ctx)->destroyed++;}
static bool attach(void *obj,void *owner){return obj&&owner;}
static unsigned g_lang;
unsigned tio_lang(void){return g_lang;}
static FMView view;
static const unsigned menu_names[]={TT_GRID_0,TT_GRID_1,TT_GRID_2,TT_GRID_3,TT_GRID_4,TT_GRID_5,TT_GRID_6,TT_GRID_DISPLAY,TT_TILE_NAVIGATION,TT_TILE_MUSIC,TT_TILE_FOCUS,TT_TILE_APPS,TT_TILE_CAMERA};
typedef struct {int x,y;unsigned weights[9];bool moving,page;} Motion;
static void wrap_motion(FMView *v){
 const unsigned offsets[]={0,15,16,32,119,120,159,160,176};Motion expected[9];
 for(unsigned rows=2;rows<=3;rows++)for(unsigned page=0;page<2;page++)for(unsigned pass=0;pass<2;pass++){
  assert(fm_view_rows(v,rows));fm_view_suspend(v);uint32_t start=pass?UINT32_MAX-7:10000;int from=page?(int)(rows*3-1):0,to=from+1;
  assert(fm_view_update(v,from,0,0,start-200)&&fm_view_update(v,to,0,0,start));
  for(unsigned j=0;j<9;j++){bool drew=fm_view_step(v,start+offsets[j]);if(j<2)assert(!drew);if(j==2)assert(drew);Motion actual={.x=v->caret_x,.y=v->caret_y,.moving=v->moving,.page=v->page_motion};memcpy(actual.weights,v->weights,sizeof actual.weights);
   if(!pass)expected[j]=actual;else{assert(actual.x==expected[j].x&&actual.y==expected[j].y&&actual.moving==expected[j].moving&&actual.page==expected[j].page&&!memcmp(actual.weights,expected[j].weights,sizeof actual.weights));}
  }assert(!v->moving&&!v->page_motion&&!fm_view_step(v,start+1000));
  // Latest selection replaces an interrupted animation; it never queues input.
  for(unsigned j=0;j<400;j++){uint32_t now=start+2000+7*j;assert(fm_view_update(v,(int)(j%v->tiles.count),0,0,now));(void)fm_view_step(v,now+16);}
  assert(fm_view_update(v,v->tiles.count-1,0,0,start+6000));(void)fm_view_step(v,start+6160);assert(v->selected==v->tiles.count-1&&!v->moving);
 }
}
/* LensMenu geometry on the settled frame: status and dots in band T, grid in band M, caret under the focused icon where its name would be, the name once in band B. */
static void Geometry(Fake *f,FMView *v,unsigned rows,unsigned selected,unsigned id){
 const unsigned cells=rows*3,cell=selected%cells;uintptr_t status=(uintptr_t)v->status,battery=(uintptr_t)v->battery,name=(uintptr_t)v->name,page=(uintptr_t)v->page,caret=(uintptr_t)v->caret;
 assert(v->selected==(int)selected&&!v->moving);
 assert(f->y[status]>=TIO_MENU_T0&&f->y[status]+f->h[status]<=TIO_MENU_T1&&f->y[battery]==f->y[status]&&f->x[status]==TIO_CORE_X0&&f->x[battery]+f->w[battery]==TIO_CORE_X1);
 assert(f->y[page]>=TIO_MENU_T0&&f->y[page]+f->h[page]<=TIO_MENU_T1&&f->x[page]+f->w[page]/2==270);                 /* dots: band T, centred between time and battery */
 assert(f->x[name]==TIO_CORE_X0&&f->w[name]==TIO_CORE_W&&f->y[name]>=TIO_MENU_M1&&f->y[name]+f->h[name]<=TIO_MENU_B1&&f->h[name]==28);   /* band B, 24 px */
 assert(!strcmp(f->texts[name],tio_text(menu_names[id],g_lang)));                                 /* the focused name appears once, in B */
 assert(f->w[caret]==24&&f->h[caret]==3&&f->y[caret]>=TIO_MENU_T1&&f->y[caret]+3<=TIO_MENU_M1);                    /* 24x3 caret in band M, no 52 px ring */
 const uintptr_t icon=(uintptr_t)v->icons[cell];
 assert(f->x[caret]+12==f->x[icon]+f->w[icon]/2&&f->y[caret]>f->y[icon]+f->h[icon]);                                /* centred under the focused icon */
 for(unsigned i=0;i<9;i++){uintptr_t o=(uintptr_t)v->icons[i],l=(uintptr_t)v->labels[i];if(!f->visible[o])continue;
  assert(f->y[o]>=TIO_MENU_T1&&f->y[o]+f->h[o]<=TIO_MENU_M1&&f->x[o]>=16&&f->x[o]+f->w[o]<=524);
  if(f->visible[l]){assert(i!=cell&&rows==2&&f->w[l]==144&&f->h[l]==20&&f->y[l]>=f->y[o]+f->h[o]&&f->y[l]+f->h[l]<=TIO_MENU_M1&&f->x[l]>=16&&f->x[l]+f->w[l]<=524);   /* 16 px names, ambient inset zone */
   assert(!(f->x[caret]<f->x[l]+f->w[l]&&f->x[l]<f->x[caret]+24&&f->y[caret]<f->y[l]+f->h[l]&&f->y[l]<f->y[caret]+3));}}                     /* the caret never sits on a name */
}
int main(void){
 Fake f={.idle=true};TNWidgets api={&f,idle,create,create,label,place,buffer,text,visible,destroy,NULL,NULL};
 assert(FM_ITEMS==13&&fm_view_open(&view,&api,&f,attach,&f));assert(f.made==24);
 assert(fm_view_update(&view,8,1704067200,75,0));assert(!strcmp(f.texts[(uintptr_t)view.labels[8]],tio_text(TT_TILE_NAVIGATION,0)));
 for(unsigned j=0;j<9;j++)assert(f.texts[(uintptr_t)view.labels[j]]&&f.visible[(uintptr_t)view.icons[j]]&&!f.visible[(uintptr_t)view.labels[j]]);   /* three rows: icons only, names live in band B */
 const char *before=f.texts[(uintptr_t)view.labels[8]];unsigned calls=f.text_calls;g_lang=1;
 assert(fm_view_update(&view,8,1704067200,75,1));assert(f.text_calls==calls+2);   /* time and battery */assert(f.texts[(uintptr_t)view.labels[8]]==before);
 calls=f.text_calls;fm_view_suspend(&view);assert(fm_view_update(&view,8,1704067200,75,2));assert(f.text_calls==calls+12);   /* nine names, the focused name, time, battery */assert(!strcmp(f.texts[(uintptr_t)view.labels[8]],tio_text(TT_TILE_NAVIGATION,1)));
 for(int i=0;i<13;i++){assert(fm_view_update(&view,i,1704067200,75,(unsigned)(1000+i*200)));assert(!strcmp(f.texts[(uintptr_t)view.status],"00:00")&&!strcmp(f.texts[(uintptr_t)view.battery],"75%"));}
 const unsigned names[]={TT_GRID_0,TT_GRID_1,TT_GRID_2,TT_GRID_3,TT_GRID_4,TT_GRID_5,TT_GRID_6,TT_GRID_DISPLAY,TT_TILE_NAVIGATION,TT_TILE_MUSIC,TT_TILE_FOCUS,TT_TILE_APPS,TT_TILE_CAMERA};
 for(unsigned rows=2;rows<=3;rows++)for(unsigned rank=0;rank<720;rank+=119)for(unsigned hide=0;hide<32;hide++){
  TTConfig config;TTVisible tiles;assert(tt_unrank(rank,hide<<7,&config)&&tt_compact(&config,&tiles));assert(fm_view_rows(&view,rows)&&fm_view_tiles(&view,&tiles));
  for(unsigned selected=0;selected<tiles.count;selected++){
   assert(fm_view_update(&view,(int)selected,1704067200,75,10000+selected*200));unsigned per=rows*3;
   (void)fm_view_step(&view,10000+selected*200+200);   /* settle the move */
   Geometry(&f,&view,rows,selected,tiles.ids[selected]);
   for(unsigned cell=0;cell<9;cell++){unsigned at=selected/per*per+cell;bool show=cell<per&&at<tiles.count;assert(f.visible[(uintptr_t)view.icons[cell]]==show);assert(f.visible[(uintptr_t)view.labels[cell]]==(show&&rows==2&&cell!=selected%per));if(show)assert(!strcmp(f.texts[(uintptr_t)view.labels[cell]],tio_text(names[tiles.ids[at]],g_lang)));}
  }
  assert(!fm_view_update(&view,tiles.count,0,0,20000));
 }
 TTConfig defaults;TTVisible defaults_map;tt_default(&defaults);tt_compact(&defaults,&defaults_map);assert(fm_view_tiles(&view,&defaults_map));
 assert(!fm_view_update(&view,-1,0,0,5000)&&!fm_view_update(&view,13,0,0,5000));
 wrap_motion(&view);
 f.idle=false;assert(!fm_view_update(&view,0,0,0,5000)&&!fm_view_close(&view));f.idle=true;
 assert(fm_view_close(&view)&&f.destroyed==1);
 for(unsigned fail=1;fail<=24;fail++){f=(Fake){.idle=true,.fail=fail};assert(!fm_view_open(&view,&api,&f,attach,&f));assert(!view.root);assert(f.destroyed==(fail==1?0:1));}
 puts("PASS focus_grid: LensMenu bands, caret and single focused name, mapped rows/pages/labels, 16/120/160ms timer wrap, interrupted motion, bounds and allocation failures");
}
