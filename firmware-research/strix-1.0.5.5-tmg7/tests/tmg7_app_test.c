// TMG7 mini-app runtime (app-runtime-v1) host test: FocusCaret rendering of TAP1 kind 2 buttons, 14 px retired,
// TAP1 wire compatibility. Mock widgets, ASan/UBSan, no LVGL, no device I/O.
//   usage: tmg7_app_test LEGACY.tap [MORE.tap ...]
// LEGACY.tap is the unchanged wire of a TMG6-era gallery package (dashboard-service/tests/fixtures/gallery_commute_legacy.tap,
// encoded from the committed Gallery_commute.zip before the design-system update). It must decode with the unchanged parser
// and then draw with caret focus items and no 14 px text. Each MORE.tap (current gallery wire) must satisfy the same rules.
#include "../src/app-runtime-v1/app_view.h"
#include "../src/app-runtime-v1/app_runner.h"
#include "../src/common-v1/tio_caret.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {int kind,x,y,w,h;unsigned font;uint32_t color;bool shown,outline,deleted;char text[100];unsigned recolors;} W;
enum {WRoot=1,WText,WRect,WImage};
typedef struct {W w[80];unsigned n,outlines,images,rects;bool busy;} H;
static bool idle(void *c){return !((H *)c)->busy;}
static W *mk(H *h,int kind){assert(h->n<80);W *w=&h->w[h->n++];memset(w,0,sizeof *w);w->kind=kind;w->shown=true;return w;}
static void *root(void *c,void *parent){(void)parent;return mk(c,WRoot);}
static void *text(void *c,void *parent,const char *s,unsigned size){(void)parent;W *w=mk(c,WText);w->font=size;w->color=TIO_LENS_FULL;assert(strlen(s)<sizeof w->text);strcpy(w->text,s);return w;}
static void *rect(void *c,void *parent,uint32_t color,bool outline){(void)parent;H *h=c;W *w=mk(h,WRect);w->color=color;w->outline=outline;h->rects++;if(outline)h->outlines++;return w;}
static void *image(void *c,void *parent,const uint8_t *px,unsigned w,unsigned h){(void)parent;assert(px&&!((uintptr_t)px&63)&&w&&h&&w<=128&&h<=128&&!(w&7));W *o=mk(c,WImage);((H *)c)->images++;o->w=(int)w;o->h=(int)h;o->color=px[1*w+w/2];return o;}
static void place(void *c,void *o,unsigned x,unsigned y,unsigned w,unsigned h){(void)c;W *v=o;assert(x+w<=540&&y+h<=180);v->x=(int)x;v->y=(int)y;v->w=(int)w;v->h=(int)h;}
static void visible(void *c,void *o,bool s){(void)c;((W *)o)->shown=s;}
static void destroy(void *c,void *o){H *h=c;(void)o;for(unsigned i=0;i<h->n;i++){h->w[i].shown=false;h->w[i].deleted=true;}}
static void tint(void *c,void *o,uint32_t color){(void)c;W *w=o;assert(w->kind==WText);w->color=color;w->recolors++;}
static TAPWidgets api(H *h){return (TAPWidgets){h,idle,root,text,rect,image,place,visible,destroy,tint};}

static W *caret(H *h){W *c=NULL;for(unsigned i=0;i<h->n;i++)if(h->w[i].kind==WImage&&h->w[i].w==TAP_CARET_W&&h->w[i].h==TAP_CARET_H)c=&h->w[i];assert(c);return c;}
static uint8_t *file(const char *path,size_t *n){FILE *f=fopen(path,"rb");assert(f);fseek(f,0,SEEK_END);long l=ftell(f);assert(l>0);rewind(f);uint8_t *b=malloc((size_t)l);assert(b&&fread(b,1,(size_t)l,f)==(size_t)l);fclose(f);*n=(size_t)l;return b;}

static unsigned buttons(const TAPDocument *d,unsigned page,const TAPItem **list){
 unsigned n=0;for(unsigned i=d->first[page];i<d->first[page]+d->size[page];i++)if(d->items[i].kind==2)list[n++]=&d->items[i];return n;}

// The rules every page must follow, whatever the package.
static void CheckPage(const TAPDocument *d,unsigned page,const char *name){
 H *h=calloc(1,sizeof *h);assert(h);TAPView *v=calloc(1,sizeof *v);assert(v);TAPWidgets a=api(h);
 assert(tap_view_open(v,&a,h,d,page));
 // No 14 px text anywhere, no outline widget (focus ring) on a page without authored frames.
 unsigned frames=0,texts=0;for(unsigned i=d->first[page];i<d->first[page]+d->size[page];i++){frames+=d->items[i].kind==5;texts+=d->items[i].kind==1||d->items[i].kind==2;}
 unsigned seen=0;for(unsigned i=0;i<h->n;i++)if(h->w[i].kind==WText){seen++;assert(h->w[i].font>=TIO_FONT_MIN&&tio_font_tap(h->w[i].font));assert(h->w[i].h>=(int)h->w[i].font+TIO_TEXT_PAD);}
 assert(seen==texts);assert(h->outlines==frames);
 const TAPItem *b[12];unsigned count=buttons(d,page,b);W *c=caret(h);
 if(!count){assert(!c->shown);assert(!tap_view_focus(v,0));}
 for(unsigned sel=0;sel<count;sel++){
  assert(tap_view_focus(v,sel));assert(c->shown);assert(c->w==TIO_CARET_W&&c->h==TIO_CARET_H);
  // Focused label lens-full, the rest idle (lens-mid from 18 px, lens-high below); plain text stays lens-full.
  W *labels[48];unsigned nl=0;for(unsigned i=0;i<h->n;i++)if(h->w[i].kind==WText)labels[nl++]=&h->w[i];
  unsigned li=0,bi=0;for(unsigned j=d->first[page];j<d->first[page]+d->size[page];j++){const TAPItem *it=&d->items[j];if(it->kind!=1&&it->kind!=2)continue;W *l=labels[li++];
   if(it->kind==1){assert(l->color==TIO_LENS_FULL);continue;}
   assert(l->color==(bi++==sel?TIO_LENS_FULL:(l->font>=TIO_FONT_LABEL?TIO_LENS_MID:TIO_LENS_HIGH)));}
  assert(li==nl);
  const TAPItem *q=b[sel];int y=tio_caret_top(q->y,tap_view_font(q->font));if(y>TIO_PAGE_H-TIO_CARET_H)y=TIO_PAGE_H-TIO_CARET_H;
  assert(c->x==q->x&&c->y==y);assert(c->x>=0&&c->x+c->w<=TIO_PAGE_W&&c->y+c->h<=TIO_PAGE_H);
 }
 if(count){assert(!tap_view_focus(v,count));assert(!c->shown);}   // past the last button: no focus, caret hidden
 // Close destroys everything and clears the retained handles; reopening works.
 assert(tap_view_close(v));assert(!v->root&&!v->focus&&!v->buttons[0]);
 assert(tap_view_open(v,&a,h,d,page));assert(tap_view_close(v));
 printf("PASS %s page %u: %u labels (>=16 px), %u focus items, caret 24x3, no focus outline\n",name,page,texts,count);
 free(v);free(h);
}

// FocusCaret: a long press goes back. Off the entry page it returns to the entry page with focus 0; only the entry page exits.
// Drives the real TAPRunner (event, view reopen) and the bare tap_event state machine over every page-switch button of the wire.
static void CheckBack(const TAPDocument *d,const char *name){
 unsigned entry=d->entry,tested=0;
 for(unsigned j=d->first[entry];j<d->first[entry]+d->size[entry];j++){
  const TAPItem *go=&d->items[j];if(go->kind!=2||go->action!=1)continue;
  unsigned index=0;for(unsigned k=d->first[entry];k<j;k++)index+=d->items[k].kind==2;
  // The bare state machine.
  TAPState s;assert(tap_start(&s,d));s.focus=(uint8_t)index;
  TAPEvent e=tap_event(&s,TAP_PRESS,1000);assert(e.type==TAP_PAGE_CHANGED&&s.page==go->target&&s.focus==0);
  e=tap_event(&s,TAP_LONG_PRESS,2000);assert(e.type==TAP_PAGE_CHANGED&&s.page==entry&&s.focus==0&&s.active);
  e=tap_event(&s,TAP_LONG_PRESS,3000);assert(e.type==TAP_EXIT&&!s.active);
  // The runner: the view is rebuilt for each page and the second long press closes the app.
  H *h=calloc(1,sizeof *h);TAPRunner *r=calloc(1,sizeof *r);TAPStore *st=calloc(1,sizeof *st);assert(h&&r&&st);TAPWidgets a=api(h);
  tap_runner_init(r,st,&a,h);r->document=*d;assert(tap_view_open(&r->view,&r->widgets,h,&r->document,entry));r->slot=0;assert(tap_start(&r->state,&r->document));
  r->state.focus=(uint8_t)index;assert(tap_view_focus(&r->view,index));
  e=tap_runner_event(r,TAP_PRESS,1000);assert(e.type==TAP_PAGE_CHANGED&&r->state.page==go->target&&r->view.root&&r->state.active);
  unsigned detail_buttons=buttons(d,go->target,(const TAPItem *[12]){0});
  e=tap_runner_event(r,TAP_LONG_PRESS,2000);assert(e.type==TAP_PAGE_CHANGED&&r->state.page==entry&&r->state.focus==0&&r->view.root&&r->state.active&&r->slot==0);
  if(buttons(d,entry,(const TAPItem *[12]){0}))assert(caret(h)->shown);
  e=tap_runner_event(r,TAP_LONG_PRESS,3000);assert(e.type==TAP_EXIT&&!r->state.active&&r->slot==-1&&!r->view.root&&!r->closing);
  // A long press is always accepted on the entry page, also while the renderer is busy; it never leaves a half-open tree.
  r->document=*d;assert(tap_start(&r->state,&r->document)&&tap_view_open(&r->view,&r->widgets,h,&r->document,entry));r->slot=0;h->busy=true;
  e=tap_runner_event(r,TAP_LONG_PRESS,4000);assert(e.type==TAP_EXIT&&!r->state.active);
  h->busy=false;(void)tap_runner_poll(r);assert(!r->view.root);
  free(st);free(r);free(h);tested++;
  printf("PASS %s back: long press on page %u (%u buttons) returns to the overview, then exits\n",name,go->target,detail_buttons);
 }
 if(d->pages>1)assert(tested||!buttons(d,entry,(const TAPItem *[12]){0}));
}

static void CheckWire(const char *path,bool legacy){
 size_t n;uint8_t *wire=file(path,&n);TAPDocument *d=calloc(1,sizeof *d);assert(d&&tap_parse(wire,n,d));
 bool has14=false,button=false;for(unsigned i=0;i<d->count;i++){has14|=d->items[i].font==14;button|=d->items[i].kind==2;}
 assert(button);
 if(legacy){   // the decoder still accepts the retired size and every field is exactly what the old package carried
  assert(has14&&d->pages==2&&d->entry==0&&d->count==15&&d->first[1]==8&&d->size[0]==8&&d->size[1]==7);
  assert(d->items[6].kind==2&&d->items[6].action==1&&d->items[6].target==1&&d->items[7].kind==2&&d->items[7].action==3);
  assert(tap_view_font(14)==16&&tap_view_font(16)==16&&tap_view_font(24)==24&&tap_view_font(28)==28);
 }else assert(!has14);
 for(unsigned p=0;p<d->pages;p++)CheckPage(d,p,path);
 // Event and focus semantics are untouched by the view change.
 TAPState s;assert(tap_start(&s,d));
 {   // Wheel focus is clamped at both ends (FocusCaret: no wrap); a step that cannot move reports no change.
  unsigned buttons=0;for(unsigned i=d->first[0];i<d->first[0]+d->size[0];i++)buttons+=d->items[i].kind==2;
  uint32_t t=1000;TAPEvent e;
  if(buttons<2){t+=200;e=tap_event(&s,TAP_NEXT,t);assert(e.type==TAP_NO_EVENT&&s.focus==0);t+=200;e=tap_event(&s,TAP_PREVIOUS,t);assert(e.type==TAP_NO_EVENT&&s.focus==0);}
  else{
   for(unsigned i=0;i+1<buttons;i++){t+=200;e=tap_event(&s,TAP_NEXT,t);assert(e.type==TAP_FOCUS_CHANGED&&s.focus==i+1);}
   t+=200;e=tap_event(&s,TAP_NEXT,t);assert(e.type==TAP_NO_EVENT&&s.focus==buttons-1);   // last item: stays, no wrap to the first
   for(unsigned i=buttons-1;i>0;i--){t+=200;e=tap_event(&s,TAP_PREVIOUS,t);assert(e.type==TAP_FOCUS_CHANGED&&s.focus==i-1);}
   t+=200;e=tap_event(&s,TAP_PREVIOUS,t);assert(e.type==TAP_NO_EVENT&&s.focus==0);}       // first item: stays, no wrap to the last
 }
 if(!legacy)CheckBack(d,path);
 free(d);free(wire);
}

// Hand-built page: retired 14/28 px text, a frame, two buttons low on the canvas.
static size_t put(uint8_t *p,int kind,int font,int action,int x,int y,int w,int h,const char *s){
 size_t l=s?strlen(s):0;memset(p,0,16);p[0]=(uint8_t)kind;p[1]=(uint8_t)font;p[2]=(uint8_t)action;p[4]=(uint8_t)x;p[5]=(uint8_t)(x>>8);p[6]=(uint8_t)y;p[7]=(uint8_t)(y>>8);p[8]=(uint8_t)w;p[9]=(uint8_t)(w>>8);p[10]=(uint8_t)h;p[11]=(uint8_t)(h>>8);p[14]=(uint8_t)l;if(l)memcpy(p+16,s,l);return 16+l;}
static void Synthetic(void){
 uint8_t wire[400];memset(wire,0,sizeof wire);memcpy(wire,"TAP1",4);wire[4]=1;wire[6]=5;wire[12]=0;wire[14]=5;size_t n=16;
 n+=put(wire+n,1,14,0,40,20,200,18,"fourteen");      // retired size, 18 px box: drawn at 16, box grows to 20
 n+=put(wire+n,1,28,0,40,50,300,32,"twenty-eight");   // accepted wire size above the floor: unchanged
 n+=put(wire+n,5,0,0,40,80,200,40,NULL);              // authored frame: the only outline widget
 n+=put(wire+n,2,16,3,40,100,150,20,"Later");          // 16 px button: idle lens-high
 n+=put(wire+n,2,20,3,300,156,150,24,"Alerts");        // caret top would be 156+21+4 = 181: clamped inside the canvas
 for(unsigned i=0;i<4;i++)wire[8+i]=(uint8_t)(n>>(8*i));
 TAPDocument *d=calloc(1,sizeof *d);assert(tap_parse(wire,n,d));
 H *h=calloc(1,sizeof *h);TAPView *v=calloc(1,sizeof *v);TAPWidgets a=api(h);assert(tap_view_open(v,&a,h,d,0));
 W *t14=NULL,*t28=NULL,*b0=NULL,*b1=NULL;for(unsigned i=0;i<h->n;i++)if(h->w[i].kind==WText){W *w=&h->w[i];if(!strcmp(w->text,"fourteen"))t14=w;if(!strcmp(w->text,"twenty-eight"))t28=w;if(!strcmp(w->text,"Later"))b0=w;if(!strcmp(w->text,"Alerts"))b1=w;}
 assert(t14&&t28&&b0&&b1);assert(t14->font==16&&t14->h==20&&t28->font==28&&t28->h==32);
 assert(h->outlines==1);W *c=caret(h);
 assert(b0->color==TIO_LENS_FULL&&b1->color==TIO_LENS_MID&&c->x==40&&c->y==100+16+1+TIO_CARET_GAP);
 assert(tap_view_tint_plain(v,0,TIO_LENS_MID)&&t14->color==TIO_LENS_MID&&tap_view_tint_plain(v,1,TIO_LENS_HIGH)&&t28->color==TIO_LENS_HIGH);   // plain labels can be re-tinted (the shelf's title)
 assert(!tap_view_tint_plain(v,2,TIO_LENS_MID));   // only two plain labels on this page; the buttons are not plain
 assert(tap_view_focus(v,1));assert(b0->color==TIO_LENS_HIGH&&b1->color==TIO_LENS_FULL&&c->x==300&&c->y==TIO_PAGE_H-TIO_CARET_H);   // 16 px idle label is lens-high, not lens-mid
 h->busy=true;assert(!tap_view_focus(v,0));h->busy=false;assert(c->x==300);   // renderer busy: nothing changes
 assert(tap_view_close(v));free(d);free(v);free(h);
 printf("PASS synthetic page: 14 px drawn at 16 with a grown box, 28 px unchanged, one authored frame outline, 16 px idle lens-high, caret clamped to the canvas\n");
}

int main(int argc,char **argv){
 assert(argc>=2);Synthetic();CheckWire(argv[1],true);for(int i=2;i<argc;i++)CheckWire(argv[i],false);
 printf("PASS tmg7 app runtime: TAP1 wire decoded unchanged, kind 2 buttons are caret focus items, 14 px retired\n");return 0;
}
