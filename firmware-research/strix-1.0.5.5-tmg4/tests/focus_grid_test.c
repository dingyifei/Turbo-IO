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
int main(void){
 Fake f={.idle=true};TNWidgets api={&f,idle,create,create,label,place,buffer,text,visible,destroy};
 assert(FM_ITEMS==13&&fm_view_open(&view,&api,&f,attach,&f));assert(f.made==23);
 assert(fm_view_update(&view,8,1704067200,75,0));assert(!strcmp(f.texts[(uintptr_t)view.labels[8]],tio_text(TT_TILE_NAVIGATION,0)));
 for(unsigned j=0;j<9;j++)assert(f.texts[(uintptr_t)view.labels[j]]&&f.visible[(uintptr_t)view.labels[j]]);
 const char *before=f.texts[(uintptr_t)view.labels[8]];unsigned calls=f.text_calls;g_lang=1;
 assert(fm_view_update(&view,8,1704067200,75,1));assert(f.text_calls==calls+1);assert(f.texts[(uintptr_t)view.labels[8]]==before);
 calls=f.text_calls;fm_view_suspend(&view);assert(fm_view_update(&view,8,1704067200,75,2));assert(f.text_calls==calls+10);assert(!strcmp(f.texts[(uintptr_t)view.labels[8]],tio_text(TT_TILE_NAVIGATION,1)));
 for(int i=0;i<13;i++){assert(fm_view_update(&view,i,1704067200,75,(unsigned)(1000+i*200)));assert(!strcmp(f.texts[(uintptr_t)view.status],"00:00   75%"));}
 assert(!fm_view_update(&view,-1,0,0,5000)&&!fm_view_update(&view,13,0,0,5000));
 f.idle=false;assert(!fm_view_update(&view,0,0,0,5000)&&!fm_view_close(&view));f.idle=true;
 assert(fm_view_close(&view)&&f.destroyed==1);
 for(unsigned fail=1;fail<=23;fail++){f=(Fake){.idle=true,.fail=fail};assert(!fm_view_open(&view,&api,&f,attach,&f));assert(!view.root);assert(f.destroyed==(fail==1?0:1));}
 puts("PASS focus_grid: 13 indices, nine labels, suspend rerender, bounds and allocation failures");
}
