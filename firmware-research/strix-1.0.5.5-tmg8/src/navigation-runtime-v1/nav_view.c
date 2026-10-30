#include "nav_view.h"
#include "nav_text.h"
#include "../common-v1/tio_ui.h"
#include <string.h>
TIO_PAGES_CHECK;
static int mag(int v){return v<0?-v:v;}
static void pixel(uint8_t *p,int w,int h,int x,int y,int radius,uint8_t gray){
 for(int yy=y-radius;yy<=y+radius;yy++)for(int xx=x-radius;xx<=x+radius;xx++)
 if(xx>=0&&xx<w&&yy>=0&&yy<h)p[(unsigned)yy*(unsigned)w+(unsigned)xx]=gray;
}
static void line(uint8_t *p,int w,int h,TNXY a,TNXY b,int radius,uint8_t gray){
 int dx=mag(b.x-a.x),dy=-mag(b.y-a.y),sx=a.x<b.x?1:-1,sy=a.y<b.y?1:-1,e=dx+dy;
 /* Input coordinates are generated from bounded normalized points, never
  * caller pixel coordinates. Bound iterations anyway against adapter errors. */
 for(unsigned n=0;n<1024;n++){pixel(p,w,h,a.x,a.y,radius,gray);if(a.x==b.x&&a.y==b.y)break;
  int e2=e*2;if(e2>=dy){e+=dy;a.x+=sx;}if(e2<=dx){e+=dx;a.y+=sy;}}
}
/* ---- LensNav layout (docs/design-system/screens/LensNav.dc.html, proposed column, halved) ---------------------
 * Priority rises toward the bottom (tio_ui.h bands): band T the road being passed (lens-mid), band M the trip line
 * (lens-high), band B the turn glyph, distance and instruction (lens-full) with the road to take under it. The map
 * keeps the right column, anchored to the bottom of band B. The TMG6 clock footer is gone: the arrival time joins the
 * trip line. Nothing is drawn in the reserved rows; no label is below 16 px. */
#define NV_ICON_X TIO_INSET_X                                    /* 16: glyph column */
#define NV_ICON_Y (TIO_PAGE_M1+2)                                /* 114: inside band B */
#define NV_TEXT_X (NV_ICON_X+(int)TN_ICON_W+4)                   /* 84 */
/* Map: the board's right column is x 372..520 (148 px, bottom-anchored at y 28..172). The shared nav_map.c renderer
 * draws a fixed 192 px canvas with the car at canvas x 96, so the canvas sits at x 348 (ending at the page edge): the
 * car is then at x 444, 3 px from the window centre (446). Columns outside the window are blanked before every
 * hand-off (map_buffer); the canvas, its size and the draw code are unchanged. */
#define NV_VIS_X 372                                             /* map window: board translate(372 28) */
#define NV_VIS_R 520
#define NV_MAP_X (TIO_PAGE_W-(int)TN_MAP_W)                      /* 348 */
#define NV_MAP_Y (TIO_PAGE_B1-(int)TN_MAP_H)                     /* 28: bottom of band B */
#define NV_VIS_L (NV_VIS_X-NV_MAP_X)                             /* 24: first visible canvas column */
#define NV_VIS_E (NV_VIS_R-NV_MAP_X)                             /* 172: first blanked column on the right */
#define NV_SCALE_Y0 117u                                         /* scale readout rows of the canvas (nav_map.c scale_draw) */
#define NV_SCALE_Y1 142u
#define NV_SCALE_X0 3u                                           /* first canvas column of the scale block (nav_map.c clears columns 3..68 first) */
#define NV_SCALE_X1 69u
#define NV_TEXT_R (NV_VIS_X-8)                                   /* 364: band T and M text stops short of the map window */
#define NV_B_R NV_MAP_X                                          /* 348: band B text stops at the canvas; the scale readout is inside the window, 29 px further right */
#define NV_DIST_Y (TIO_PAGE_B1-TIO_LINE(TIO_FONT_MIN)-TIO_LINE(TIO_FONT_PRIMARY))   /* 116 */
#define NV_ROAD_Y (TIO_PAGE_B1-TIO_LINE(TIO_FONT_MIN))           /* 152 */
#define NV_TRIP_Y (TIO_PAGE_T1+20)                               /* 76 */
#define NV_TRIP_W (NV_TEXT_R-TIO_CORE_X0)                        /* 324 */
#define NV_PASS_W (NV_TEXT_R-TIO_CORE_X0)                        /* 324 */
/* Fixed slots (TurnCard: "Updates at 1 Hz change text only, never positions"): the distance owns x 84..196, wide enough
 * for "9.9 km" at 32 px; the instruction starts at 196 (board: 192) and ends at the canvas. Neither slot moves or
 * changes size with the digit count; only the instruction's font step depends on its own text. */
#define NV_DIST_W 112
#define NV_TURN_X (NV_TEXT_X+NV_DIST_W)                          /* 196 */
#define NV_TURN_W (NV_B_R-NV_TURN_X)                             /* 152 */
static const unsigned turn_fonts[TN_TURN_SIZES]={TIO_FONT_TITLE,TIO_FONT_BODY,TIO_FONT_MIN};
static const unsigned trip_fonts[TN_TRIP_SIZES]={TIO_FONT_BODY,TIO_FONT_MIN};
static const unsigned pass_fonts[TN_PASS_SIZES]={TIO_FONT_LABEL,TIO_FONT_MIN};
/* Layout estimate of a line's width in px, from hundredths of an em per character. It only chooses between the
 * stock font sizes and where the instruction starts; every label box is fixed and clips, so a wrong estimate
 * clips a line and never moves anything into another band or onto the map. Unverified against the stock font. */
static unsigned est_px(const char *s,unsigned font){
 unsigned u=0;
 for(const unsigned char *p=(const unsigned char *)s;*p;p++){
  unsigned c=*p;
  if(c>=0xc0){u+=(c==0xc2&&p[1]==0xb7)?34:100;continue;}
  if(c>=0x80)continue;
  if(c>='0'&&c<='9')u+=56;
  else if(c==' '||c=='.'||c==','||c==':'||c==';'||c=='\'')u+=28;
  else if(c=='i'||c=='l'||c=='j'||c=='!'||c=='|')u+=26;
  else if(c=='f'||c=='t'||c=='r'||c=='I'||c=='-'||c=='('||c==')')u+=36;
  else if(c=='m')u+=88;
  else if(c=='w'||c=='M'||c=='W')u+=90;
  else if(c>='A'&&c<='Z')u+=68;
  else u+=56;
 }
 return (u*font+99)/100;
}
static unsigned pick(const unsigned *fonts,unsigned count,const char *s,unsigned width){
 for(unsigned i=0;i+1<count;i++)if(est_px(s,fonts[i])<=width)return i;
 return count-1;
}
static void *make(TNView *v,unsigned font,uint32_t rgb,int x,int y,int w){
 TNWidgets *a=&v->api;void *o=a->label(a->ctx,v->root,font);if(!o)return NULL;
 if(a->color)a->color(a->ctx,o,rgb);if(a->clip_text)a->clip_text(a->ctx,o);
 a->place(a->ctx,o,x,y,w,TIO_LINE(font));a->visible(a->ctx,o,false);return o;
}
static void forget(TNView *v){
 v->root=v->icon=v->map=v->distance=v->road=v->scale=NULL;
 for(unsigned i=0;i<TN_TURN_SIZES;i++)v->turn[i]=NULL;
 for(unsigned i=0;i<TN_TRIP_SIZES;i++)v->trip[i]=NULL;
 for(unsigned i=0;i<TN_PASS_SIZES;i++)v->pass[i]=NULL;
}
static bool built(const TNView *v){
 bool ok=v->icon&&v->map&&v->distance&&v->road&&v->scale;
 for(unsigned i=0;i<TN_TURN_SIZES;i++)ok=ok&&v->turn[i];
 for(unsigned i=0;i<TN_TRIP_SIZES;i++)ok=ok&&v->trip[i];
 for(unsigned i=0;i<TN_PASS_SIZES;i++)ok=ok&&v->pass[i];
 return ok;
}
static int glyph_axis(int v,int from,int to){int d=(v-from)*13;return to+(d>=0?(d+10)/20:-((-d+10)/20));}
static TNXY glyph(TNXY p){return (TNXY){glyph_axis(p.x,56,TN_ICON_W/2),glyph_axis(p.y,60,TN_ICON_H/2)};}
static void draw(TNViewFrame *f){
 memset(f->names,0,sizeof f->names);
 memset(f->icon,0,sizeof f->icon);memset(f->map,0,sizeof f->map);
 TNVisual *v=&f->visual;uint8_t gray=v->stale?100:255;
 /* The glyph tables are authored in a 96x84 box centred at (56,60); the 64x56 canvas takes them at 0.65 with a
 * 7 px stroke (brush radius 3; the board draws 8 px), so the ink spans about 52x47 and keeps a margin off the edge. */
 for(unsigned i=1;i<v->icon_count;i++){
  TNXY a=v->icon[i-1],b=v->icon[i];
  a=glyph(a);b=glyph(b);
  line(f->icon,TN_ICON_W,TN_ICON_H,a,b,3,gray);
 }
 for(unsigned i=1;i<v->route_count;i++){
  TNXY a=v->route[i-1],b=v->route[i];a.x=NV_VIS_L+(a.x-400)*148/128;a.y=(a.y-4)*144/128;b.x=NV_VIS_L+(b.x-400)*148/128;b.y=(b.y-4)*144/128;
  line(f->map,TN_MAP_W,TN_MAP_H,a,b,1,v->stale?60:160);
 }
 if(v->route_count)for(unsigned i=1;i<4;i++){
  TNXY a=v->position[i-1],b=v->position[i];a.x=NV_VIS_L+(a.x-400)*148/128;a.y=(a.y-4)*144/128;b.x=NV_VIS_L+(b.x-400)*148/128;b.y=(b.y-4)*144/128;
  line(f->map,TN_MAP_W,TN_MAP_H,a,b,1,gray);
 }
}
/* Same fit as tn_text_fit (nav_text.h, shared with the phone) but the smallest step is 16 px, the lens floor. */
static unsigned fit_passing(const char *s,size_t n,const uint8_t *breaks,unsigned width,char *out,size_t cap){
 if(!out||cap<4||n>191||tn_text_width(s,n,16)==UINT32_MAX)return 0;
 unsigned font=tn_text_width(s,n,TIO_FONT_LABEL)<=width?TIO_FONT_LABEL:TIO_FONT_MIN;
 if(tn_text_width(s,n,font)<=width&&n<cap){memcpy(out,s,n);out[n]=0;return font;}
 size_t best=0;for(size_t i=1;i<=n;i++)if(breaks&&(breaks[i/8]&(1u<<(i%8)))&&i+4<=cap&&tn_text_width(s,i,font)+font<=width)best=i;
 while(best&&s[best-1]==' ')best--;memcpy(out,s,best);memcpy(out+best,"\xe2\x80\xa6",4);return font;
}
/* The canvas is wider than the board's map window (x 372..520). Blank every column outside the window in the frame just
 * before every hand-off, with no exception. The scale readout (bar and tick marks) is drawn by nav_map.c in the canvas
 * corner, columns 3.., which is left of the window; while a scale is shown that block (rows NV_SCALE_Y0..Y1, which
 * nav_map.c cleared first, so only the bar is in it) is moved right by NV_VIS_L so the bar starts 3 px inside the window. */
static void map_buffer(TNView *v,TNViewFrame *f){
 unsigned metres,pixels;bool scale=v->map_state.valid&&tnr_scale(v->map_state.scenes[v->map_state.bank].range,&metres,&pixels);
 unsigned last=0;   /* last canvas column of the bar */
 if(scale)for(unsigned y=NV_SCALE_Y0;y<NV_SCALE_Y1;y++)for(unsigned x=NV_SCALE_X0;x<NV_SCALE_X1;x++)if(f->map[y*TN_MAP_W+x]&&x>last)last=x;
 for(unsigned y=0;y<TN_MAP_H;y++){uint8_t *row=f->map+y*TN_MAP_W;
  if(scale&&last&&y>=NV_SCALE_Y0&&y<NV_SCALE_Y1&&last+NV_VIS_L<NV_VIS_E){
   for(unsigned x=last+1;x-->NV_SCALE_X0;)row[x+NV_VIS_L]=row[x];   /* high to low: source and target overlap */
   memset(row,0,NV_SCALE_X0+NV_VIS_L);}
  else memset(row,0,(unsigned)NV_VIS_L);
  memset(row+NV_VIS_E,0,TN_MAP_W-NV_VIS_E);}
 v->api.buffer(v->api.ctx,v->map,f->map,TN_MAP_W,TN_MAP_H);
}
static void publish_names(TNView *v,TNViewFrame *f){
 TNWidgets *a=&v->api;size_t n=0;while(n<191&&v->map_state.passing[n])n++;
 unsigned font=fit_passing(v->map_state.passing,n,v->map_state.passing_breaks,NV_PASS_W,f->passing,sizeof f->passing);
 for(unsigned i=0;i<TN_PASS_SIZES;i++){bool show=n&&font==pass_fonts[i];a->text_static(a->ctx,v->pass[i],f->passing);a->visible(a->ctx,v->pass[i],show);}
 unsigned metres,pixels;f->scale[0]=0;bool scale=v->map_state.valid&&tnr_scale(v->map_state.scenes[v->map_state.bank].range,&metres,&pixels);
 if(scale){unsigned at=0;if(metres>=100)f->scale[at++]=(char)('0'+metres/100);f->scale[at++]=(char)('0'+(metres/10)%10);f->scale[at++]=(char)('0'+metres%10);f->scale[at++]=' ';f->scale[at++]='m';f->scale[at]=0;}
 a->text_static(a->ctx,v->scale,f->scale);a->visible(a->ctx,v->scale,scale);
}
/* Trip line: summary, middle dot, arrival time; only the stale warning when the data is stale. It has a single
 * writer pair (publish and tn_view_clock). The label keeps a pointer, so a change goes to the other bank. */
static void trip_update(TNView *v,const TNVisual *vis){
 TNWidgets *a=&v->api;char line[sizeof v->trip_text[0]];size_t at=0;line[0]=0;
 if(!v->eta_stale){for(const char *s=vis->summary;*s&&at+1<sizeof line;)line[at++]=*s++;
  for(const char *s=" \xc2\xb7 ";*s&&at+1<sizeof line;)line[at++]=*s++;}
 for(const char *s=v->eta;*s&&at+1<sizeof line;)line[at++]=*s++;line[at]=0;
 if(v->trip_shown&&!strcmp(line,v->trip_text[v->trip_bank]))return;
 unsigned next=v->trip_shown?v->trip_bank^1u:0u;memcpy(v->trip_text[next],line,sizeof line);
 unsigned size=pick(trip_fonts,TN_TRIP_SIZES,line,NV_TRIP_W);
 for(unsigned i=0;i<TN_TRIP_SIZES;i++){a->text_static(a->ctx,v->trip[i],v->trip_text[next]);a->visible(a->ctx,v->trip[i],i==size);}
 v->trip_bank=next;v->trip_shown=true;
}
/* The distance slot is fixed. A reading too wide for it ("10.0 km" and up, estimated at 118 px against 112) drops its
 * tenths and rounds to the nearest kilometre: "10.9 km" -> "11 km", "45.4 km" -> "45 km", "99.9 km" -> "100 km". The
 * tenths digit is already the floor of the true tenths, so >=5 rounds up exactly as the true value would. The reading
 * is capped at three digits ("999.9 km" -> "999 km"), which is the widest the slot holds. */
static void fit_distance(char *d){
 if(est_px(d,TIO_FONT_PRIMARY)<=NV_DIST_W)return;
 char *dot=d;while(*dot&&*dot!='.')dot++;
 if(!*dot||dot[1]<'0'||dot[1]>'9')return;
 bool up=dot[1]>='5';size_t digits=(size_t)(dot-d);bool nines=true;
 for(const char *c=d;c<dot;c++)nines&=*c=='9';
 const char *rest=dot+2;char *w=dot;while((*w++=*rest++)){}
 if(!up||(nines&&digits>=3))return;
 if(nines){size_t n=strlen(d);for(size_t k=n+1;k>0;k--)d[k]=d[k-1];d[0]='1';for(size_t k=1;k<=digits;k++)d[k]='0';return;}
 for(char *c=dot;c>d;){c--;if(*c<'9'){(*c)++;return;}*c='0';}
}
static void publish(TNView *v,TNViewFrame *f){
 TNWidgets *a=&v->api;
 a->buffer(a->ctx,v->icon,f->icon,TN_ICON_W,TN_ICON_H);
 map_buffer(v,f);
 /* Distance is the primary line; the instruction follows it on the same baseline. Both slots were placed once, at open:
 * an update changes text and which font step is visible, never a position or a size. */
 fit_distance(f->visual.distance);
 a->text_static(a->ctx,v->distance,f->visual.distance);a->visible(a->ctx,v->distance,true);
 unsigned size=pick(turn_fonts,TN_TURN_SIZES,f->visual.turn,NV_TURN_W);
 for(unsigned i=0;i<TN_TURN_SIZES;i++){
  a->text_static(a->ctx,v->turn[i],f->visual.turn);a->visible(a->ctx,v->turn[i],i==size&&f->visual.turn[0]);
 }
 a->text_static(a->ctx,v->road,f->visual.road);a->visible(a->ctx,v->road,f->visual.road[0]!=0);
 /* The trip line has a single owner pair: semantic updates re-compose it, tn_view_clock changes its arrival time.
  * A power-mode hint never replaces it. Identical text keeps the retained pointer. */
 trip_update(v,&f->visual);
 publish_names(v,f);
 /* Call on the single UI executor: no yields between mutations. Native LVGL
  * refresh occurs after this function; no ACK claims physical PRESENTED. */
}
bool tn_view_open(TNView *v,const TNWidgets *a,void *parent,const TNScene *s){
 if(!v||!a||!parent||!a->idle||!a->root||!a->canvas||!a->label||!a->place||!a->buffer||!a->text_static||!a->visible||!a->destroy||!a->idle(a->ctx))return false;
 if(v->root||v->open||v->retiring)return false;
 if(!tn_visual(s,false,&v->frames[0].visual))return false;v->api=*a;v->active=0;v->trip_shown=false;v->trip_bank=0;v->eta_stale=false;
 tn_clock_text(v->eta,0,0,false);
 v->root=a->root(a->ctx,parent);if(!v->root)return false;a->visible(a->ctx,v->root,false);a->place(a->ctx,v->root,0,0,TIO_PAGE_W,TIO_PAGE_H);
 v->icon=a->canvas(a->ctx,v->root);v->map=a->canvas(a->ctx,v->root);
 if(!v->icon||!v->map)goto fail;
 a->place(a->ctx,v->icon,NV_ICON_X,NV_ICON_Y,TN_ICON_W,TN_ICON_H);a->place(a->ctx,v->map,NV_MAP_X,NV_MAP_Y,TN_MAP_W,TN_MAP_H);
 /* Intensity: B lens-full, M and the road to take lens-high, T lens-mid (18 px) or lens-high (16 px fallback). */
 v->distance=make(v,TIO_FONT_PRIMARY,TIO_LENS_FULL,NV_TEXT_X,NV_DIST_Y,NV_DIST_W);if(!v->distance)goto fail;
 for(unsigned i=0;i<TN_TURN_SIZES;i++){v->turn[i]=make(v,turn_fonts[i],TIO_LENS_FULL,NV_TURN_X,NV_DIST_Y+(int)TIO_FONT_PRIMARY-(int)turn_fonts[i],NV_TURN_W);if(!v->turn[i])goto fail;}
 v->road=make(v,TIO_FONT_MIN,TIO_LENS_HIGH,NV_TEXT_X,NV_ROAD_Y,NV_B_R-NV_TEXT_X);if(!v->road)goto fail;
 for(unsigned i=0;i<TN_TRIP_SIZES;i++){
  v->trip[i]=make(v,trip_fonts[i],TIO_LENS_HIGH,TIO_CORE_X0,NV_TRIP_Y+(int)(TIO_FONT_BODY-trip_fonts[i]),NV_TRIP_W);if(!v->trip[i])goto fail;}
 for(unsigned i=0;i<TN_PASS_SIZES;i++){
  v->pass[i]=make(v,pass_fonts[i],i?TIO_LENS_HIGH:TIO_LENS_MID,TIO_CORE_X0,TIO_PAGE_T0+((TIO_PAGE_T1-TIO_PAGE_T0)-TIO_LINE(pass_fonts[i]))/2,NV_PASS_W);if(!v->pass[i])goto fail;}
 v->scale=make(v,TIO_FONT_MIN,TIO_LENS_HIGH,NV_MAP_X+5+NV_VIS_L,NV_MAP_Y+117,68);if(!v->scale)goto fail;
 if(!built(v))goto fail;
 draw(&v->frames[0]);publish(v,&v->frames[0]);v->open=true;a->visible(a->ctx,v->root,true);return true;
 fail:a->destroy(a->ctx,v->root);forget(v);return false;
}
bool tn_view_update(TNView *v,const TNScene *s,bool stale){
 if(!v||!v->open||v->retiring||!v->api.idle(v->api.ctx))return false;
 unsigned next=v->active^1u;TNViewFrame *f=&v->frames[next];
 if(!tn_visual(s,stale,&f->visual))return false;draw(f);if(v->map_state.valid)tnr_draw(&v->map_state,v->map_now,f->map);publish(v,f);v->active=next;return true;
}
bool tn_view_close(TNView *v){
 if(!v)return false;if(!v->root)return true;
 v->retiring=true;v->open=false;v->api.visible(v->api.ctx,v->root,false);
 if(!v->api.idle(v->api.ctx))return false;v->api.destroy(v->api.ctx,v->root);
 forget(v);v->retiring=false;return true;
}
bool tn_view_clock(TNView *v,int64_t local_epoch,int64_t eta_epoch,bool stale){
 if(!v||!v->open||v->retiring)return false;
 char tail[64];tn_clock_text(tail,local_epoch,eta_epoch,stale);
 if(v->trip_shown&&stale==v->eta_stale&&!memcmp(tail,v->eta,64))return true;
 if(!v->api.idle(v->api.ctx))return false;
 memcpy(v->eta,tail,64);v->eta_stale=stale;
 trip_update(v,&v->frames[v->active].visual);return true;
}

bool tn_view_map(TNView *v,unsigned op,const uint8_t *body,size_t n,uint32_t now){
 if(!v||!v->open||v->retiring)return false;
 v->map_state.smooth=true;return tnr_receive(&v->map_state,op,body,n,now);
}
bool tn_view_map_save(const TNView *v,TNRState *out){
 if(!v||!out||!v->open||v->retiring)return false;memcpy(out,&v->map_state,sizeof *out);return true;
}
bool tn_view_map_restore(TNView *v,const TNRState *in){
 if(!v||!in||!v->open||v->retiring)return false;memcpy(&v->map_state,in,sizeof *in);v->map_state.dirty=true;return true;   /* drawn by the next map tick */
}
bool tn_view_map_tick(TNView *v,uint32_t now){
 if(!v||!v->open||v->retiring)return false;v->map_now=now;
 if(!tnr_needs_draw(&v->map_state,now))return true;
 if(!v->api.idle(v->api.ctx))return false;
 unsigned next=v->active^1u;TNViewFrame *f=&v->frames[next];
 /* Map ticks do not need to copy/repaint the 16 KiB arrow or semantic text.
  * Retained text pointers stay valid until a full semantic publish. */
 f->visual=v->frames[v->active].visual;
 if(v->map_state.valid)tnr_draw(&v->map_state,now,f->map);else draw(f);map_buffer(v,f);publish_names(v,f);v->active=next;tnr_presented(&v->map_state,now);return true;
}
