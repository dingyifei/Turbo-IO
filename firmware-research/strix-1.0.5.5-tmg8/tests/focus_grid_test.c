#include "../src/focus-v1/focus_menu.h"
#include "../src/common-v1/tio_text.h"
#include "../src/common-v1/tio_ui.h"
#include "../src/focus-v1/focus_menu_icons.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {bool idle;unsigned made,fail,destroyed,text_calls;const char *texts[64];bool visible[64];int x[64],y[64],w[64],h[64];const uint8_t *buf[64];unsigned bw[64],bh[64];} Fake;
static bool idle(void *ctx){return ((Fake *)ctx)->idle;}
static void *create(void *ctx,void *parent){(void)parent;Fake *f=ctx;unsigned n=++f->made;return n==f->fail?NULL:(void *)(uintptr_t)n;}
static void *label(void *ctx,void *parent,unsigned font){assert(font==16||font==18||font==24);return create(ctx,parent);}   /* cell names and the carousel status line 16, status 18, focused name 24 */
static void place(void *ctx,void *obj,int x,int y,int w,int h){assert(x>=0&&y>=0&&w>0&&h>0&&x+w<=540&&y+h<=220);Fake *f=ctx;uintptr_t k=(uintptr_t)obj;f->x[k]=x;f->y[k]=y;f->w[k]=w;f->h[k]=h;}
static void buffer(void *ctx,void *obj,const uint8_t *p,unsigned w,unsigned h){Fake *f=ctx;assert(p);assert((w==32&&h==32)||(w==28&&h==28)||(w==FM_CARET_W&&h==FM_CARET_H)||(w==36&&h==4)||(w==FM_STATE_W&&h==FM_STATE_H)||(w==h&&w>=32&&w<=80));f->buf[(uintptr_t)obj]=p;f->bw[(uintptr_t)obj]=w;f->bh[(uintptr_t)obj]=h;}
static void text(void *ctx,void *obj,const char *s){Fake *f=ctx;assert(strlen(s)<FM_LINE_MAX);f->texts[(uintptr_t)obj]=s;f->text_calls++;}
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

/* ---- TMG8 carousel (LensMenuCarousel.dc.html) ---------------------------------------------------------------------------- */
static unsigned art_level(unsigned id,unsigned x,unsigned y){unsigned pos=y*48+x;return ((fm_icon4[id][pos/2]>>(pos%2?0:4))&15)*17;}
static unsigned art_sum(unsigned id){unsigned t=0;for(unsigned y=0;y<48;y++)for(unsigned x=0;x<48;x++)t+=art_level(id,x,y);return t;}
enum { FM_CAR_LEVEL_MID=0x77, FM_CAR_LEVEL_TRACK=0x38 };
typedef struct {int cx,cy;unsigned size,peak,sum;const uint8_t *buf;uintptr_t obj;} Slot;
/* The visible icon canvases of the current frame, left to right. Also proves each canvas lies inside one bank of retained carousel pixels, and no two overlap. */
static unsigned slots(Fake *f,FMView *v,Slot out[FM_CELLS]){
 unsigned n=0;const uint8_t *lo=(const uint8_t *)v->cpixels,*hi=lo+sizeof v->cpixels;
 for(unsigned i=0;i<FM_CELLS;i++){uintptr_t o=(uintptr_t)v->icons[i];if(!f->visible[o])continue;
  Slot s={f->x[o]+f->w[o]/2,f->y[o]+f->h[o]/2,(unsigned)f->w[o],0,0,f->buf[o],o};assert(f->w[o]==f->h[o]&&(unsigned)f->w[o]==f->bw[o]&&(unsigned)f->h[o]==f->bh[o]&&s.size<=80);
  assert(s.buf>=lo&&s.buf+s.size*s.size<=hi);
  const uint8_t *bank0=v->cpixels[0],*bank1=v->cpixels[1];assert((s.buf>=bank0&&s.buf+s.size*s.size<=bank0+FM_CAR_BANK)||(s.buf>=bank1&&s.buf+s.size*s.size<=bank1+FM_CAR_BANK));
  assert(((uintptr_t)s.buf&63)==0);
  for(unsigned q=0;q<s.size*s.size;q++){if(s.buf[q]>s.peak)s.peak=s.buf[q];s.sum+=s.buf[q];}
  for(unsigned j=0;j<n;j++)assert(s.buf+s.size*s.size<=out[j].buf||out[j].buf+out[j].size*out[j].size<=s.buf);
  unsigned at=n++;while(at&&out[at-1].cx>s.cx){out[at]=out[at-1];at--;}out[at]=s;
 }
 return n;
}
static void settle(FMView *v,int sel,uint32_t *clock){*clock+=1000;assert(fm_view_update(v,sel,946684800+10*3600,82,*clock));(void)fm_view_step(v,*clock+200);assert(!v->moving&&v->selected==sel);}
/* Geometry of a settled frame: per the board's renderVals (centre 80 px at 270,68; neighbours 48 at +-124; outer 36 at +-214; caret y114; line y146; name y180). */
static void car_geometry(Fake *f,FMView *v,bool route,unsigned selected){
 const int cy=route?92:68,dx1=route?118:124,dx2=route?206:214;const unsigned s0=route?64:80,s1=route?40:48,s2=route?32:36;
 Slot sl[FM_CELLS];assert(slots(f,v,sl)==5);
 const int cxs[5]={270-dx2,270-dx1,270,270+dx1,270+dx2};const unsigned sizes[5]={s2,s1,s0,s1,s2};
 const unsigned levels[5]={FM_CAR_LEVEL_TRACK,FM_CAR_LEVEL_MID,255,FM_CAR_LEVEL_MID,FM_CAR_LEVEL_TRACK};
 const unsigned n=v->tiles.count;
 for(unsigned i=0;i<5;i++){
  assert(sl[i].cx==cxs[i]&&sl[i].cy==cy&&sl[i].size==sizes[i]);
  assert(sl[i].peak<=levels[i]);   /* full / mid 0x77 / track 0x38 */
  if(i==2)assert(sl[i].peak>=250);
  if(sizes[i]==48){   /* 48 px is the art itself: the neighbours are exactly the art scaled by the mid gain, so the right items sit on the right sides */
   unsigned id=v->tiles.ids[(selected+n+(i==1?-1:1))%n];
   for(unsigned y=0;y<48;y++)for(unsigned x=0;x<48;x++)assert(sl[i].buf[y*48+x]==art_level(id,x,y)*FM_CAR_LEVEL_MID/255);
  }
  /* The scaler keeps the mean level of the art, whatever the size (bilinear, no prefilter): within 8 %. */
  unsigned id=v->tiles.ids[(selected+n+(unsigned)(i-2))%n];
  unsigned want=art_sum(id)*levels[i]/255,have=sl[i].sum*48*48/(sl[i].size*sl[i].size);assert(have+want/12+4>=want&&have<=want+want/12+4);
 }
 const uintptr_t caret=(uintptr_t)v->caret,line=(uintptr_t)v->line,name=(uintptr_t)v->name,page=(uintptr_t)v->page;
 assert(f->x[caret]==258&&f->w[caret]==24&&f->h[caret]==3&&f->y[caret]==(route?127:114)&&f->y[caret]>=sl[2].cy+(int)sl[2].size/2+3);   /* caret centred under the centre icon, below it */
 assert(f->y[caret]>=TIO_MENU_T1&&f->y[caret]+3<=TIO_MENU_M1);
 assert(f->x[line]==TIO_CORE_X0&&f->w[line]==TIO_CORE_W&&f->h[line]==20&&f->y[line]==(route?140:146)&&f->y[line]>=TIO_MENU_T1&&f->y[line]+f->h[line]<=TIO_MENU_M1);
 assert(f->y[line]>=f->y[caret]+3);   /* the line sits under the caret */
 assert(!f->visible[page]);for(unsigned i=0;i<FM_CELLS;i++)assert(!f->visible[(uintptr_t)v->labels[i]]);
 assert(f->x[name]==TIO_CORE_X0&&f->y[name]>=TIO_MENU_M1&&f->y[name]+f->h[name]<=TIO_MENU_B1&&!strcmp(f->texts[name],tio_text(menu_names[v->tiles.ids[selected]],g_lang)));
 /* Nothing the carousel draws touches the clock (x 40..140) or battery (x 400..500) rows, or the reserved strips. */
 for(unsigned i=0;i<5;i++){assert(sl[i].cy-(int)sl[i].size/2>=TIO_RESERVE_TOP&&sl[i].cy+(int)sl[i].size/2<=TIO_MENU_M1);}
}
static void carousel(Fake *f,FMView *v){
 TTConfig config;TTVisible tiles;uint32_t clock=100000;
 for(unsigned rank=0;rank<720;rank+=239)for(unsigned hide=0;hide<32;hide+=7){
  assert(tt_unrank(rank,hide<<7,&config)&&tt_compact(&config,&tiles));assert(fm_view_rows(v,FM_CAROUSEL)&&fm_view_tiles(v,&tiles));
  assert(v->rows==FM_CAROUSEL);fm_view_reduce_motion(v,false);
  for(unsigned route=0;route<2;route++){
   assert(fm_view_route(v,route,clock));
   for(unsigned sel=0;sel<tiles.count;sel++){settle(v,(int)sel,&clock);car_geometry(f,v,route,sel);}
  }
  assert(fm_view_route(v,false,clock));
 }
 /* A bank is 64 aligned and the grid arrays alias the carousel's: switching layouts redraws everything. */
 assert(tt_unrank(0,0,&config)&&tt_compact(&config,&tiles));assert(fm_view_tiles(v,&tiles));assert(fm_view_rows(v,2));settle(v,3,&clock);assert(!f->visible[(uintptr_t)v->line]&&f->visible[(uintptr_t)v->page]);
 assert(fm_view_rows(v,FM_CAROUSEL));settle(v,0,&clock);car_geometry(f,v,false,0);
 /* Wheel step forward: the old centre shrinks to the left, the new one grows from the right; at the midpoint both are 64 px at +-62. */
 const unsigned n=v->tiles.count;
 for(unsigned from=0;from<n;from++){
  settle(v,(int)from,&clock);unsigned to=(from+1)%n;   /* includes the wrap last -> first */
  clock+=1000;assert(fm_view_update(v,(int)to,0,0,clock)&&v->moving);
  Slot a[FM_CELLS];
  int centre_prev=-1;unsigned frames=0;
  for(unsigned t=16;t<=176;t+=16){
   (void)fm_view_step(v,clock+t);unsigned k=slots(f,v,a);assert(k>=4&&k<=6);frames++;
   unsigned best=0;for(unsigned i=1;i<k;i++)if(a[i].size>a[best].size)best=i;
   assert(a[best].size>=48&&a[best].size<=80);
   if(centre_prev>=0)assert(a[best].cx>=centre_prev-62&&a[best].cx<=centre_prev+62+124);   /* no teleport */
   centre_prev=a[best].cx;
   for(unsigned i=0;i<k;i++)assert(a[i].cy==68&&a[i].cx>=TIO_INSET_X+(int)a[i].size/2&&a[i].cx+(int)a[i].size/2<=540-TIO_INSET_X);
  }
  assert(frames==11&&!v->moving);car_geometry(f,v,false,to);
  /* midpoint, from a fresh move: cubic ease-out is past half way at 40 ms, so look at the exact halfway of the position instead: step so q is known */
  settle(v,(int)from,&clock);clock+=1000;assert(fm_view_update(v,(int)to,0,0,clock));
  (void)fm_view_step(v,clock+33);   /* cubic ease-out is half way (p = 127/256) at 33 ms */
  {assert(v->car_p-v->car_from_p>=120&&v->car_p-v->car_from_p<=136);
   Slot m[FM_CELLS];unsigned k=slots(f,v,m);assert(k==4);unsigned big=0,lo=0,hi=0;for(unsigned i=0;i<k;i++)if(m[i].size>=60){big++;if(!lo)lo=i+1;else hi=i+1;}assert(big==2&&m[lo-1].cx<270&&m[hi-1].cx>270);
   /* left big icon is the old focus, right big icon the new one: compare mean levels against the art of the two tiles */
   unsigned left_art=art_sum(v->tiles.ids[from]),right_art=art_sum(v->tiles.ids[to]);
   if(left_art>right_art+right_art/6||right_art>left_art+left_art/6){
    unsigned lm=m[lo-1].sum*48*48/(m[lo-1].size*m[lo-1].size),rm=m[hi-1].sum*48*48/(m[hi-1].size*m[hi-1].size);
    assert((left_art>right_art)==(lm>rm));}}
  (void)fm_view_step(v,clock+400);
 }
 /* Backwards step and wrap first -> last take the short way round. */
 settle(v,0,&clock);clock+=1000;assert(fm_view_update(v,(int)n-1,0,0,clock)&&v->moving&&v->car_to_p-v->car_from_p==-256);
 settle(v,(int)n-1,&clock);clock+=1000;assert(fm_view_update(v,0,0,0,clock)&&v->moving&&v->car_to_p-v->car_from_p==256);
 settle(v,0,&clock);clock+=1000;assert(fm_view_update(v,3,0,0,clock)&&v->car_to_p-v->car_from_p==3*256);
 settle(v,3,&clock);
 /* Sweep every fraction: canvases stay inside the bank, sizes never exceed 80, positions stay in the insets, the mean level follows the gain. */
 for(unsigned jump=1;jump<=6;jump++)for(unsigned from=0;from<n;from+=3){
  settle(v,(int)from,&clock);clock+=1000;unsigned to=(from+jump)%n;assert(fm_view_update(v,(int)to,0,0,clock));
  for(unsigned t=1;t<=170;t+=3){(void)fm_view_step(v,clock+t);Slot m[FM_CELLS];unsigned k=slots(f,v,m);assert(k>=4&&k<=6);for(unsigned i=0;i<k;i++)assert(m[i].peak<=255);}
 }
 /* A newer target replaces an interrupted move from where it is. */
 settle(v,0,&clock);clock+=1000;assert(fm_view_update(v,1,0,0,clock));(void)fm_view_step(v,clock+60);int mid=v->car_p;assert(mid>0&&mid<256);
 assert(fm_view_update(v,0,0,0,clock+70));assert(v->car_from_p>=mid&&v->car_to_p==0);(void)fm_view_step(v,clock+400);assert(!v->moving&&v->car_p==0);
 /* Reduce Motion snaps. */
 fm_view_reduce_motion(v,true);clock+=1000;assert(fm_view_update(v,4,0,0,clock)&&!v->moving&&v->car_p==4*256);car_geometry(f,v,false,4);
 assert(fm_view_route(v,true,clock+1)&&!v->moving&&v->dirty);assert(fm_view_step(v,clock+20));car_geometry(f,v,true,4);
 assert(fm_view_route(v,false,clock+30)&&fm_view_step(v,clock+50));car_geometry(f,v,false,4);
 fm_view_reduce_motion(v,false);
 /* Route on/off slides the row from 68 to 92 and back in 160 ms, with no selection change. */
 clock+=1000;assert(fm_view_route(v,true,clock)&&v->moving);(void)fm_view_step(v,clock+40);{Slot m[FM_CELLS];assert(slots(f,v,m)==5);int y=m[2].cy;assert(y>68&&y<=92);}
 (void)fm_view_step(v,clock+200);car_geometry(f,v,true,4);assert(fm_view_route(v,false,clock+300));(void)fm_view_step(v,clock+600);car_geometry(f,v,false,4);
 /* Status line: set, cut at a character boundary, hidden when empty, no rewrite when unchanged. */
 const uintptr_t line=(uintptr_t)v->line;
 assert(fm_view_line(v,"Playing \xc2\xb7 Blinding Lights"));(void)fm_view_step(v,clock+700);assert(f->visible[line]&&!strcmp(f->texts[line],"Playing \xc2\xb7 Blinding Lights"));
 {const char *kept=f->texts[line];assert(fm_view_line(v,"Playing \xc2\xb7 Blinding Lights")&&f->texts[line]==kept&&!v->dirty);}   /* unchanged: no rewrite */
 char cjk[400]="";for(unsigned i=0;i<100;i++)strcat(cjk,"\xe7\x95\x8c");assert(fm_view_line(v,cjk));(void)fm_view_step(v,clock+720);
 {size_t len=strlen(f->texts[line]);assert(len<FM_LINE_MAX&&len%3==0&&len==93);}
 char odd[400]="a";strcat(odd,cjk);assert(fm_view_line(v,odd));{size_t len=strlen(f->texts[line]);assert(len<FM_LINE_MAX&&len==1+3*31);}
 assert(fm_view_line(v,"")&&f->texts[line][0]==0);(void)fm_view_step(v,clock+740);assert(!f->visible[line]);
 f->idle=false;assert(!fm_view_line(v,"Busy"));f->idle=true;
 /* Another layout hides the line and the carousel hooks only record state. */
 assert(fm_view_line(v,"x"));assert(fm_view_rows(v,3));settle(v,2,&clock);assert(!f->visible[line]);assert(fm_view_route(v,true,clock));assert(v->route);assert(fm_view_route(v,false,clock));
 assert(!fm_view_rows(v,0)&&!fm_view_rows(v,4)&&fm_view_rows(v,1));
}
/* ---- TMG8 live tile state: the grid's state dots (LensMenuGrid2.dc.html: 5 px lens-mid disc at (cx+17, cy-20)) ------------------------------ */
static bool boxes_overlap(int ax,int ay,int aw,int ah,int bx,int by,int bw,int bh){return ax<bx+bw&&bx<ax+aw&&ay<by+bh&&by<ay+ah;}
static void state_dots(Fake *f,FMView *v){
 TTConfig config;TTVisible tiles;uint32_t clock=500000;
 /* The shared dot art: a 5 px disc (corners cut) at lens-mid inside an 8x5 buffer, nothing brighter, nothing outside the disc. */
 {unsigned lit=0;for(unsigned y=0;y<FM_STATE_H;y++)for(unsigned x=0;x<FM_STATE_W;x++){uint8_t p=v->state_px[y*FM_STATE_W+x];assert(p==0||p==0x77);if(p){lit++;assert(x<FM_STATE_DOT);}}assert(lit==21);
  assert(v->state_px[0]==0&&v->state_px[4]==0&&v->state_px[4*8]==0&&v->state_px[4*8+4]==0&&v->state_px[2*8+2]==0x77);}
 for(unsigned rows=2;rows<=3;rows++)for(unsigned rank=0;rank<720;rank+=239)for(unsigned hide=0;hide<32;hide+=9){
  assert(tt_unrank(rank,hide<<7,&config)&&tt_compact(&config,&tiles));assert(fm_view_rows(v,rows)&&fm_view_tiles(v,&tiles));
  for(unsigned pattern=0;pattern<4;pattern++){
   unsigned mask=pattern==0?0:pattern==1?(1u<<TIO_TILE_FOCUS):pattern==2?((1u<<TIO_TILE_MUSIC)|(1u<<TIO_TILE_NAVIGATION)|(1u<<TIO_TILE_FOCUS)):0x1fffu;
   assert(fm_view_active(v,mask));
   for(unsigned sel=0;sel<tiles.count;sel+=2){
    settle(v,(int)sel,&clock);const unsigned per=rows*3,size=rows==3?28:32;
    for(unsigned cell=0;cell<9;cell++){
     const uintptr_t d=(uintptr_t)v->dots[cell],o=(uintptr_t)v->icons[cell];unsigned at=sel/per*per+cell;bool show=cell<per&&at<tiles.count;
     assert(f->visible[d]==(show&&(mask>>tiles.ids[at]&1)));
     if(!f->visible[d])continue;
     assert(f->w[d]==8&&f->h[d]==5&&f->buf[d]==v->state_px&&f->bw[d]==8&&f->bh[d]==5);
     assert(f->x[d]==f->x[o]+(int)size+1);                              /* 1 px right of the icon box: cx+17 for the 32 px icon */
     assert(f->y[d]==(f->y[o]-4<TIO_MENU_T1?TIO_MENU_T1:f->y[o]-4));      /* 4 px above it (cy-20), never above band M */
     assert(f->y[d]>=TIO_MENU_T1&&f->y[d]+f->h[d]<=TIO_MENU_M1&&f->x[d]>=TIO_INSET_X&&f->x[d]+f->w[d]<=540-TIO_INSET_X);
     for(unsigned other=0;other<9;other++){
      const uintptr_t oo=(uintptr_t)v->icons[other],ol=(uintptr_t)v->labels[other];
      if(f->visible[oo])assert(!boxes_overlap(f->x[d],f->y[d],5,5,f->x[oo],f->y[oo],f->w[oo],f->h[oo]));   /* the lit disc touches no icon */
      if(f->visible[ol])assert(!boxes_overlap(f->x[d],f->y[d],5,5,f->x[ol],f->y[ol],f->w[ol],f->h[ol]-TIO_TEXT_PAD));   /* the 16 px glyph row; the 4 px pad below it is empty */
     }
     assert(!boxes_overlap(f->x[d],f->y[d],5,5,f->x[(uintptr_t)v->caret],f->y[(uintptr_t)v->caret],24,3));
    }
   }
  }
 }
 /* Exact board position for the 2-row grid: centres 92/270/448, first row top 58. */
 assert(tt_unrank(0,0,&config)&&tt_compact(&config,&tiles));assert(fm_view_tiles(v,&tiles)&&fm_view_rows(v,2)&&fm_view_active(v,0x1fffu));settle(v,0,&clock);
 for(unsigned cell=0;cell<6;cell++){const uintptr_t d=(uintptr_t)v->dots[cell];int cx=92+178*(int)(cell%3),cy=(cell<3?58:116)+16;assert(f->x[d]==cx+17);assert(f->y[d]==(cell<3?TIO_MENU_T1:cy-20));}
 /* Redraw only on a change. */
 settle(v,0,&clock);assert(fm_view_active(v,0x1fffu)&&!v->dirty);assert(fm_view_active(v,0)&&v->dirty);clock+=100;assert(fm_view_step(v,clock));assert(!v->dirty);
 for(unsigned cell=0;cell<9;cell++)assert(!f->visible[(uintptr_t)v->dots[cell]]);
 assert(fm_view_active(v,(1u<<13)|(1u<<TIO_TILE_FOCUS))&&v->live_mask==(1u<<TIO_TILE_FOCUS));   /* only the 13 tile bits count */
 /* A status line in the grid is recorded but does not redraw anything. */
 settle(v,1,&clock);assert(fm_view_line(v,"18:42 left")&&!v->dirty);assert(!f->visible[(uintptr_t)v->line]);assert(fm_view_line(v,""));
 /* The carousel draws no dots: it has the status line. */
 assert(fm_view_rows(v,FM_CAROUSEL));settle(v,2,&clock);for(unsigned cell=0;cell<9;cell++)assert(!f->visible[(uintptr_t)v->dots[cell]]);assert(fm_view_active(v,0)&&!v->dirty);
 assert(fm_view_rows(v,3));assert(fm_view_active(v,0));
 FMView closed;memset(&closed,0,sizeof closed);assert(!fm_view_active(&closed,1)&&!fm_view_active(NULL,1));
}
int main(void){
 Fake f={.idle=true};TNWidgets api={&f,idle,create,create,label,place,buffer,text,visible,destroy,NULL,NULL};
 assert(FM_ITEMS==13&&fm_view_open(&view,&api,&f,attach,&f));assert(f.made==34);   /* root, 6 widgets, and per cell an icon, a name and a state dot */
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
 carousel(&f,&view);
 state_dots(&f,&view);
 f.idle=false;assert(!fm_view_update(&view,0,0,0,5000)&&!fm_view_close(&view));f.idle=true;
 assert(fm_view_close(&view)&&f.destroyed==1);
 for(unsigned fail=1;fail<=34;fail++){f=(Fake){.idle=true,.fail=fail};assert(!fm_view_open(&view,&api,&f,attach,&f));assert(!view.root);assert(f.destroyed==(fail==1?0:1));}
 puts("PASS focus_grid: LensMenu bands, caret and single focused name, mapped rows/pages/labels, 16/120/160ms timer wrap, interrupted motion, bounds and allocation failures; TMG8 carousel geometry with and without a route, slide, wrap, canvas bounds, status line, Reduce Motion; TMG8 live tile state dots");
}
