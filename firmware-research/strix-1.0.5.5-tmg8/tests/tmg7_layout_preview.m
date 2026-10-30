// TMG7 host preview and layout gate. Production geometry and raster for the native pages; macOS surrogate fonts.
// Extends tmg6_layout_preview.m: every page is rendered EN and ZH to PNG and checked against the design-system
// rules in docs/design-system (bands, reserved rows, 16 px text floor, no filled panels).
// Pages that still use the TMG6 layout are listed as PENDING and must report violations; the commit that re-lays a
// page flips its flag, after which it must report none.
#import <AppKit/AppKit.h>
#include "../src/navigation-runtime-v1/nav_view.h"
#include "../src/navigation-runtime-v1/nav_text.h"
#include "../src/music-runtime-v1/music.h"
#include "../src/music-runtime-v1/music_layout.h"
#include "../src/focus-v1/focus_view.h"
#include "../src/focus-v1/focus_menu.h"
#include "../src/focus-v1/tile_state.h"
#include "../src/focus-v1/nav_title.h"
#include "../src/common-v1/tio_text.h"
#include "../src/common-v1/tio_ui.h"
#include "../src/common-v1/tio_hint.h"
#include "../src/common-v1/tio_caret.h"
#include "../src/app-runtime-v1/app_view.h"
#include "../src/app-runtime-v1/app_shelf.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
enum {KText,KPixels,KRect};
typedef struct {int x,y,w,h;unsigned font;bool shown,clip,span,fading,art,ambient,ramp;int align;const char *text;const uint8_t *pixels;int kind,band;uint32_t color;} Widget;
typedef struct {Widget w[48];unsigned count;bool busy;} Host;
enum {VReserved=1,VBand=2,VFont=4,VPanel=8,VCore=16,VColor=32,VOverlap=64,VCanvas=128,VBox=256};
static unsigned language;
static TIOSurface gSurface=TIO_SURFACE_PAGE;   // surface the gate and the PNG writer use: 540x180 pages, 540x220 menu
unsigned tio_lang(void){return language;}
static bool idle(void *p){return !((Host *)p)->busy;}
static void *create(void *p,void *parent){assert(parent);Host *h=p;assert(h->count<48);Widget *w=&h->w[h->count++];w->shown=true;w->band=-1;return w;}
static void *label(void *p,void *parent,unsigned font){Widget *w=create(p,parent);w->font=font;return w;}
static void place(void *p,void *o,int x,int y,int w,int h){(void)p;assert(x>=0&&y>=0&&x+w<=540&&y+h<=220);Widget *v=o;v->x=x;v->y=y;v->w=w;v->h=h;}
static void buffer(void *p,void *o,const uint8_t *pixels,unsigned w,unsigned h){(void)p;Widget *v=o;assert(v->w==(int)w&&v->h==(int)h);v->pixels=pixels;v->kind=KPixels;}
static void text(void *p,void *o,const char *s){(void)p;((Widget *)o)->text=s;}
static void visible(void *p,void *o,bool show){(void)p;((Widget *)o)->shown=show;}
static void destroy(void *p,void *o){(void)p;((Widget *)o)->shown=false;}
static void cliptext(void *p,void *o){(void)p;((Widget *)o)->clip=true;}
static NSColor *Ink(uint32_t c){return [NSColor colorWithRed:0 green:((c>>8)&255)/255.0 blue:0 alpha:1];}
static void Save(Host *host,NSString *path){
 NSImage *im=[[NSImage alloc]initWithSize:NSMakeSize(540,tio_surface_h(gSurface))];[im lockFocusFlipped:YES];[NSColor.blackColor setFill];NSRectFill(NSMakeRect(0,0,540,tio_surface_h(gSurface)));
 for(unsigned i=1;i<host->count;i++){Widget *w=&host->w[i];if(!w->shown)continue;NSRect rect=NSMakeRect(w->x,w->y,w->w,w->h);
  [NSGraphicsContext saveGraphicsState];NSRectClip(rect);
  if(w->kind==KRect){[Ink(w->color) setFill];[[NSBezierPath bezierPathWithRoundedRect:rect xRadius:TIO_RADIUS_XS yRadius:TIO_RADIUS_XS] fill];}
  if(w->pixels){NSBitmapImageRep *b=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:w->w pixelsHigh:w->h bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w->w*3 bitsPerPixel:24];for(int y=0;y<w->h;y++)for(int x=0;x<w->w;x++){uint8_t *d=b.bitmapData+y*b.bytesPerRow+x*3;d[0]=d[2]=0;d[1]=w->pixels[y*w->w+x];}NSImage *tile=[[NSImage alloc]initWithSize:NSMakeSize(w->w,w->h)];[tile addRepresentation:b];[tile drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:nil];}
  if(w->text&&*w->text){NSString *s=[NSString stringWithUTF8String:w->text];assert(s);NSMutableParagraphStyle *ps=[NSMutableParagraphStyle new];ps.lineBreakMode=NSLineBreakByClipping;ps.alignment=w->align==1?NSTextAlignmentCenter:w->align==2?NSTextAlignmentRight:NSTextAlignmentLeft;
   [s drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:w->font],NSForegroundColorAttributeName:Ink(w->color?w->color:TIO_LENS_FULL),NSParagraphStyleAttributeName:ps}];}
  [NSGraphicsContext restoreGraphicsState];
 }
 [im unlockFocus];NSBitmapImageRep *rep=[NSBitmapImageRep imageRepWithData:im.TIFFRepresentation];assert([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
}

// ---- Layout gate -----------------------------------------------------------------------------------------------
static bool overlap(const Widget *a,const Widget *b){return a->x<b->x+b->w&&b->x<a->x+a->w&&a->y<b->y+b->h&&b->y<a->y+a->h;}
static bool textual(const Widget *w){return w->kind==KText&&w->text&&*w->text;}
// Returns a mask of violated rules for the shown widgets of a 540x180 page. `band` of a widget is its declared band, else the band its box lies in.
static unsigned Check(Host *host,const char *name,bool verbose){
 unsigned mask=0;const TIOSurface s=gSurface;
 for(unsigned i=1;i<host->count;i++){Widget *w=&host->w[i];if(!w->shown)continue;
  bool text=textual(w),pix=w->kind==KPixels,rect=w->kind==KRect;if(!text&&!pix&&!rect)continue;
  TIORect r={w->x,w->y,w->w,w->h};unsigned v=0;
  if(r.x<0||r.y<0||r.x+r.w>TIO_PAGE_W||r.y+r.h>tio_surface_h(s))v|=VCanvas;
  if(tio_rect_in_reserved(s,r))v|=VReserved;                                   // nothing drawn in y 0-12 or 172-180
  int band=w->band>=0?w->band:tio_band_of(s,r.y,r.h);
  if(!w->span&&(band<TIO_BAND_T||band>TIO_BAND_B||!tio_rect_in_band(s,(TIOBand)band,r)))v|=VBand;   // inside its band
  if(text){
   if(w->font<TIO_FONT_MIN||!tio_font_native(w->font))v|=VFont;                // 16 px floor, stock sizes only
   if(w->h<(int)w->font+TIO_TEXT_PAD)v|=VBox;                                  // box at least font + 4
   if(w->ambient?(r.x<TIO_INSET_X||r.x+r.w>TIO_PAGE_W-TIO_INSET_X):!tio_rect_in_core(r))v|=VCore;   // primary text inside lens-core-x; ambient menu names may use the side insets
   uint32_t c=w->color?w->color:TIO_LENS_FULL;
   if(c!=TIO_LENS_FULL&&c!=TIO_LENS_HIGH&&c!=TIO_LENS_MID&&!(w->fading&&c<TIO_LENS_HIGH))v|=VColor;   // track is never text; only a fading hint may sit between steps
   if(c==TIO_LENS_MID&&w->font<TIO_FONT_LABEL&&!w->ambient)v|=VColor;              // mid only at 18 px or larger (AmbientStatus: unfocused menu names are lens-min in lens-mid)
  }
  if(pix&&w->art){for(int k=0;k<r.w*r.h;k++)if(w->pixels[k]>TM_ART_LEVEL){v|=VColor;break;}}   // artwork stays under lens-mid
  if(pix&&!w->span&&(r.x<TIO_INSET_X||r.x+r.w>TIO_PAGE_W-TIO_INSET_X))v|=VCore;   // glyphs may use the side insets, not the edge
  if(rect&&!(r.h<=TIO_TRACK_H&&(w->color==TIO_LENS_FULL||w->color==TIO_LENS_TRACK)))v|=VPanel;   // only carets and tracks are filled
  bool track=pix&&!w->ramp&&r.h<=TIO_TRACK_H;if(track){for(int k=0;k<r.w*r.h;k++)if(w->pixels[k]!=TF_TRACK_LEVEL&&w->pixels[k]!=TF_FILL_LEVEL){v|=VColor;break;}}   // progress track: only track and full levels
  if(pix&&!w->art&&!w->ramp&&!track&&r.w*r.h>=32*32){   // ramp = the existing pictogram art, kept by the design system (README: menu icons), not a panel
  unsigned lit=0;for(int k=0;k<r.w*r.h;k++)lit+=w->pixels[k]>16;if(lit*2>(unsigned)(r.w*r.h))v|=VPanel;}  // no solid canvases
  for(unsigned j=1;j<i;j++){Widget *o=&host->w[j];if(o->shown&&(textual(o)||o->kind==KRect)&&(text||rect)&&overlap(w,o)&&!(rect&&o->kind==KRect))v|=VOverlap;}
  if(v&&verbose)printf("  %s widget %u (%d,%d %dx%d font %u): mask 0x%x\n",name,i,r.x,r.y,r.w,r.h,w->font,v);
  mask|=v;
 }
 return mask;
}
static void Gate(Host *host,const char *name,bool relaid){
 unsigned mask=Check(host,name,false);
 if(relaid){if(mask)Check(host,name,true);assert(mask==0);printf("PASS layout %s: bands, reserved rows, 16 px floor, no panels\n",name);}
 else{assert(mask!=0);printf("PENDING layout %s: TMG6 layout still in place (violations 0x%x), re-laid by a later tmg7 commit\n",name,mask);}
}
static Widget *Add(Host *h,int kind,int x,int y,int w,int ht,unsigned font,uint32_t color,int band,const char *s){
 Widget *v=create(h,h);v->kind=kind;v->x=x;v->y=y;v->w=w;v->h=ht;v->font=font;v->color=color;v->band=band;v->text=s;return v;
}
static void SelfTest(void){   // the gate must catch each defect
 Host h={0};create(&h,&h);
 Add(&h,KText,40,4,100,22,18,TIO_LENS_MID,TIO_BAND_T,"a");assert(Check(&h,"x",false)&VReserved);
 h=(Host){0};create(&h,&h);Add(&h,KText,40,120,100,18,14,TIO_LENS_FULL,TIO_BAND_B,"a");assert(Check(&h,"x",false)&(VFont|VBox));
 h=(Host){0};create(&h,&h);Add(&h,KRect,40,60,200,40,0,TIO_LENS_MID,TIO_BAND_M,NULL);assert(Check(&h,"x",false)&VPanel);
 h=(Host){0};create(&h,&h);Add(&h,KText,40,100,100,24,20,TIO_LENS_HIGH,TIO_BAND_M,"a");assert(Check(&h,"x",false)&VBand);       // straddles M/B
 h=(Host){0};create(&h,&h);Add(&h,KText,8,120,100,24,20,TIO_LENS_FULL,TIO_BAND_B,"a");assert(Check(&h,"x",false)&VCore);
 h=(Host){0};create(&h,&h);Add(&h,KText,40,120,100,24,20,TIO_LENS_TRACK,TIO_BAND_B,"a");assert(Check(&h,"x",false)&VColor);
 h=(Host){0};create(&h,&h);Add(&h,KText,40,60,100,24,16,TIO_LENS_MID,TIO_BAND_M,"a");assert(Check(&h,"x",false)&VColor);
 h=(Host){0};create(&h,&h);Add(&h,KText,40,120,100,24,20,TIO_LENS_FULL,TIO_BAND_B,"a");Add(&h,KText,60,130,100,24,20,TIO_LENS_FULL,TIO_BAND_B,"b");assert(Check(&h,"x",false)&VOverlap);
 {static uint8_t bright[36*36];memset(bright,255,sizeof bright);h=(Host){0};create(&h,&h);Widget *a=Add(&h,KPixels,40,16,36,36,0,0,TIO_BAND_T,NULL);a->pixels=bright;a->art=true;assert(Check(&h,"x",false)&VColor);a->art=false;assert(Check(&h,"x",false)&VPanel);}
 {static uint8_t bar[460*4];memset(bar,TF_TRACK_LEVEL,sizeof bar);h=(Host){0};create(&h,&h);Widget *t=Add(&h,KPixels,40,44,460,4,0,0,TIO_BAND_T,NULL);t->pixels=bar;assert(Check(&h,"x",false)==0);bar[7]=0x90;assert(Check(&h,"x",false)&VColor);}
 h=(Host){0};create(&h,&h);Add(&h,KText,40,120,100,24,20,TIO_LENS_FULL,TIO_BAND_B,"a");Add(&h,KRect,40,150,TIO_CARET_W,TIO_CARET_H,0,TIO_LENS_FULL,TIO_BAND_B,NULL);assert(Check(&h,"ok",false)==0);
}

// ---- Mini-app page composed from the design-system components (LensApp board, TAP1 kind 2 buttons as caret focus items) ----
// BuildApp is a design fixture that checks the board's proposed column and models the transient hint and the sliding caret the
// board shows. The TAP runtime itself has no hint and its caret snaps; the shipped gallery wire is checked in RunWire/AppRuntime.
typedef struct {const char *title,*items[3],*value,*unit,*detail,*hint;} AppCopy;
static const AppCopy App[2]={
 {"Commute · Line 2",{"Later trains","Alerts","Platform map"},"4 min","to Downtown","Platform 3 · then 12 min","Wheel: choose · Press: open · Hold: exit"},
 {"通勤 · 2 号线",{"稍后班次","提醒","站台图"},"4 分钟","往市中心","3 号站台 · 之后 12 分钟","滚轮：选择 · 按下：打开 · 长按：退出"}};
static const int ItemX[3]={40,200,300},ItemW[3]={150,90,160};
static void BuildApp(Host *h,bool zh,unsigned focus,uint32_t now,TIOHint *hint,TIOCaret *caret){
 const AppCopy *c=&App[zh];create(h,h);
 const TIOSpan T=tio_band(TIO_SURFACE_PAGE,TIO_BAND_T),M=tio_band(TIO_SURFACE_PAGE,TIO_BAND_M),B=tio_band(TIO_SURFACE_PAGE,TIO_BAND_B);
 // Band T: the title in lens-mid, replaced by the transient hint (lens-high) while it is shown.
 if(tio_hint_visible(hint,now)){TIORect r=tio_hint_rect(TIO_SURFACE_PAGE);Widget *w=Add(h,KText,r.x,r.y,r.w,r.h,TIO_HINT_FONT,tio_hint_color(hint,now),TIO_BAND_T,c->hint);w->fading=tio_hint_alpha(hint,now)<255;}
 else Add(h,KText,TIO_CORE_X0,T.y0+(T.y1-T.y0-TIO_LINE(TIO_FONT_LABEL))/2,TIO_CORE_W,TIO_LINE(TIO_FONT_LABEL),TIO_FONT_LABEL,TIO_LENS_MID,TIO_BAND_T,c->title);
 // Band M: the actions, one row, caret under the focused one. Bottom-aligned so the row sits next to band B.
 int row=M.y1-TIO_RESERVE_BOTTOM-(TIO_FONT_BODY+1+TIO_CARET_GAP+TIO_CARET_H);   // caret bottom keeps the bottom clearance
 for(unsigned i=0;i<3;i++)Add(h,KText,ItemX[i],row,ItemW[i],TIO_LINE(TIO_FONT_BODY),TIO_FONT_BODY,tio_focus_color(i==focus),TIO_BAND_M,c->items[i]);
 tio_caret_to(caret,tio_caret_left(ItemX[focus]),tio_caret_top(row,TIO_FONT_BODY),now,false);
 TIORect cr=tio_caret_rect(caret,now);Add(h,KRect,cr.x,cr.y,cr.w,cr.h,0,TIO_LENS_FULL,TIO_BAND_M,NULL);
 // Band B: the one thing the page is for, lowest and brightest; baselines of 32 and 24 px text share one line.
 int y=B.y0+TIO_TEXT_PAD,u=y+(int)(TIO_FONT_PRIMARY-TIO_FONT_TITLE);
 Add(h,KText,TIO_CORE_X0,y,100,TIO_LINE(TIO_FONT_PRIMARY),TIO_FONT_PRIMARY,TIO_LENS_FULL,TIO_BAND_B,c->value);
 Add(h,KText,150,u,350,TIO_LINE(TIO_FONT_TITLE),TIO_FONT_TITLE,TIO_LENS_FULL,TIO_BAND_B,c->unit);
 Add(h,KText,TIO_CORE_X0,B.y1-TIO_LINE(TIO_FONT_MIN),TIO_CORE_W,TIO_LINE(TIO_FONT_MIN),TIO_FONT_MIN,TIO_LENS_HIGH,TIO_BAND_B,c->detail);
}
// Compare the fixture with the board's proposed column (board is drawn at 2x). Same band, size, intensity and text; x within 1, y within 6.
static void CompareBoard(NSString *html,Host *host){
 NSString *s=[NSString stringWithContentsOfFile:html encoding:NSUTF8StringEncoding error:nil];assert(s);
 NSRange proposed=[s rangeOfString:@"Proposed"];assert(proposed.location!=NSNotFound);s=[s substringFromIndex:proposed.location];
 NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"left: (\\d+)px; top: (\\d+)px; font-size: (\\d+)px;[^\"]*?color: (#[0-9a-f]{6});\">([^<{]+)</div>" options:0 error:nil];
 unsigned matched=0;
 for(NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0,s.length)]){
  int x=[[s substringWithRange:[m rangeAtIndex:1]] intValue]/2,y=[[s substringWithRange:[m rangeAtIndex:2]] intValue]/2,font=[[s substringWithRange:[m rangeAtIndex:3]] intValue]/2;
  uint32_t color=(uint32_t)strtoul([[s substringWithRange:[m rangeAtIndex:4]] UTF8String]+1,NULL,16);NSString *t=[s substringWithRange:[m rangeAtIndex:5]];
  Widget *w=NULL;for(unsigned i=1;i<host->count;i++)if(host->w[i].text&&[t isEqualToString:[NSString stringWithUTF8String:host->w[i].text]])w=&host->w[i];
  if(!w||!w->shown){printf("board text without fixture widget: %s\n",t.UTF8String);assert(0);}
  matched++;assert(abs(w->x-x)<=1&&abs(w->y-y)<=6&&(int)w->font==font&&w->color==color);
  assert(w->band==tio_band_of(TIO_SURFACE_PAGE,y+font/2,1));
 }
 // Focus items are scripted in the board (xs/labels arrays) and the caret sits under the focused one.
 NSRegularExpression *xs=[NSRegularExpression regularExpressionWithPattern:@"const xs = \\[(\\d+), (\\d+), (\\d+)\\]" options:0 error:nil];NSTextCheckingResult *xm=[xs firstMatchInString:s options:0 range:NSMakeRange(0,s.length)];assert(xm);
 for(unsigned i=0;i<3;i++)assert([[s substringWithRange:[xm rangeAtIndex:i+1]] intValue]/2==ItemX[i]);
 assert(matched>=4);
 Widget *caret=NULL;for(unsigned i=1;i<host->count;i++)if(host->w[i].kind==KRect)caret=&host->w[i];assert(caret&&caret->x==ItemX[0]&&caret->w==48/2&&caret->h==6/2&&[s containsString:@"width: 48px; height: 6px"]);
 printf("PASS board LensApp (proposed, halved): %u text items, 3 focus items and caret match; band, size, intensity, x and y within tolerance\n",matched);
}
static void AppPages(NSString *dir,NSString *board){
 typedef struct {uint32_t now;const char *tag;unsigned focus;bool input,save;} Shot;
 // Page opens at t=1000 (hint shown); fade; hint gone, title back; wheel step at t=6000 re-shows the hint and slides the caret.
 const Shot shots[]={{1000,"hint",0,false,true},{3850,"hint-fade",0,false,true},{4000,"",0,false,true},{6000,"input-start",1,true,false},{6080,"input-slide",1,false,true},{6160,"input",1,false,true},{9300,"focus1",1,false,true}};
 for(unsigned z=0;z<2;z++){language=z;TIOHint hint;tio_hint_init(&hint);tio_hint_enter(&hint,1000);TIOCaret caret;tio_caret_init(&caret);
  for(unsigned i=0;i<sizeof shots/sizeof *shots;i++){const Shot *sh=&shots[i];if(sh->input)tio_hint_input(&hint,sh->now);
   Host *host=calloc(1,sizeof *host);assert(host);BuildApp(host,z,sh->focus,sh->now,&hint,&caret);
   bool shown=!strcmp(sh->tag,"hint")||!strcmp(sh->tag,"hint-fade")||!strncmp(sh->tag,"input",5);assert(tio_hint_visible(&hint,sh->now)==shown);
   char name[64];snprintf(name,sizeof name,"app%s%s-%s",*sh->tag?"-":"",sh->tag,z?"zh":"en");Gate(host,name,true);
   Widget *first=&host->w[1];
   if(!strcmp(sh->tag,"hint"))assert(first->color==TIO_LENS_HIGH&&first->font==18);                    // lens-label in lens-high in band T
   if(!strcmp(sh->tag,"hint-fade"))assert(first->color>0&&first->color<TIO_LENS_HIGH);                // fading toward see-through
   if(!*sh->tag){assert(first->color==TIO_LENS_MID&&!strcmp(first->text,App[z].title));if(!z)CompareBoard(board,host);}   // ambient title returns
   if(!strcmp(sh->tag,"input-slide")){Widget *c=&host->w[host->count-4];(void)c;int cx=0;for(unsigned k=1;k<host->count;k++)if(host->w[k].kind==KRect)cx=host->w[k].x;assert(cx>ItemX[0]&&cx<ItemX[1]);}   // caret mid-slide, not queued
   if(!strcmp(sh->tag,"input")||!strcmp(sh->tag,"focus1")){for(unsigned k=1;k<host->count;k++)if(host->w[k].kind==KRect)assert(host->w[k].x==ItemX[1]);}
   if(sh->save)Save(host,[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png",name]]);free(host);}
 }
 unsigned words=0;for(const char *p=App[0].hint;*p;p++)if(*p!=' '&&(p==App[0].hint||p[-1]==' ')&&strncmp(p,"·",2))words++;assert(words<=TIO_HINT_MAX_WORDS_EN);
}

static void Put16(uint8_t *p,int n){p[0]=n;p[1]=n>>8;}
// ---- Mini-app runtime (app-runtime-v1, tmg7(9)): the production app_view.c drawing real TAP1 wire through mock widgets ----
// TAP1 carries no intensity: plain text is lens-full, kind 2 buttons are focus items (focused lens-full, idle lens-mid, caret 24x3).
static void *rtRoot(void *p,void *parent){(void)parent;return create(p,p);}
static void *rtText(void *p,void *parent,const char *s,unsigned size){(void)parent;Widget *w=create(p,p);w->kind=KText;w->font=size;w->text=strdup(s);return w;}
static void *rtRect(void *p,void *parent,uint32_t c,bool outline){(void)parent;(void)outline;Widget *w=create(p,p);w->kind=KRect;w->color=c;return w;}
static void *rtImage(void *p,void *parent,const uint8_t *px,unsigned w,unsigned h){(void)parent;Widget *o=create(p,p);o->kind=KPixels;o->pixels=px;o->w=(int)w;o->h=(int)h;o->ramp=w==TAP_CARET_W&&h==TAP_CARET_H;return o;}
static void rtPlace(void *p,void *o,unsigned x,unsigned y,unsigned w,unsigned h){(void)p;Widget *v=o;v->x=(int)x;v->y=(int)y;v->w=(int)w;v->h=(int)h;}
static void rtTint(void *p,void *o,uint32_t c){(void)p;((Widget *)o)->color=c;}
static size_t Item(uint8_t *p,int kind,int font,int action,int x,int y,int w,int h,const char *s){
 size_t l=strlen(s);memset(p,0,16);p[0]=kind;p[1]=font;p[2]=action;Put16(p+4,x);Put16(p+6,y);Put16(p+8,w);Put16(p+10,h);Put16(p+14,(int)l);memcpy(p+16,s,l);return 16+l;}
// The LensApp board as TAP1: title, three actions in band M, the readout lowest in band B.
static size_t CommuteWire(uint8_t *wire,bool zh){
 const AppCopy *c=&App[zh];memset(wire,0,16);memcpy(wire,"TAP1",4);wire[4]=1;Put16(wire+6,7);Put16(wire+14,7);size_t n=16;
 n+=Item(wire+n,1,TIO_FONT_LABEL,0,TIO_CORE_X0,25,TIO_CORE_W,TIO_LINE(TIO_FONT_LABEL),c->title);
 for(unsigned i=0;i<3;i++)n+=Item(wire+n,2,TIO_FONT_BODY,3,ItemX[i],76,ItemW[i],TIO_LINE(TIO_FONT_BODY),c->items[i]);
 n+=Item(wire+n,1,TIO_FONT_TITLE,0,TIO_CORE_X0,122,100,TIO_LINE(TIO_FONT_TITLE),c->value);   // TAP1 has no 32 px size: 24 px readout
 n+=Item(wire+n,1,TIO_FONT_TITLE,0,150,122,350,TIO_LINE(TIO_FONT_TITLE),c->unit);
 n+=Item(wire+n,1,TIO_FONT_MIN,0,TIO_CORE_X0,152,TIO_CORE_W,TIO_LINE(TIO_FONT_MIN),c->detail);
 for(unsigned i=0;i<4;i++)wire[8+i]=(uint8_t)(n>>(8*i));return n;
}
// Open one page of `wire` for every focus position, gate it, save the PNGs. `strict` = the page follows the bands and the core.
static bool (*AfterOpen)(TAPView *);   // run on every opened page before it is gated and drawn (the shelf's lens-mid re-tint)
static void RunWire(NSString *dir,const char *tag,const uint8_t *wire,size_t n,bool strict,bool save_all){
 TAPDocument *d=calloc(1,sizeof *d);assert(tap_parse(wire,n,d));
 for(unsigned page=0;page<d->pages;page++){
  unsigned buttons=0;for(unsigned i=d->first[page];i<d->first[page]+d->size[page];i++)buttons+=d->items[i].kind==2;
  for(unsigned focus=0;focus<(buttons?buttons:1);focus++){
   Host *host=calloc(1,sizeof *host);TAPView *v=calloc(1,sizeof *v);create(host,host);
   TAPWidgets api={host,idle,rtRoot,rtText,rtRect,rtImage,rtPlace,visible,destroy,rtTint};
   assert(tap_view_open(v,&api,host,d,page));if(AfterOpen)assert(AfterOpen(v));assert(!buttons||tap_view_focus(v,focus));
   char name[96];snprintf(name,sizeof name,"%s-p%u%s%u",tag,page,buttons>1?"-f":"",focus);if(buttons<=1)snprintf(name,sizeof name,"%s-p%u",tag,page);
   unsigned mask=Check(host,name,false);
   if(!strict)mask&=~(VBand|VCore);   // gallery content keeps its 18 px margins and free vertical flow; reserved rows, 16 px floor, panels and overlap still apply
   if(mask){Check(host,name,true);printf("FAIL layout %s mask 0x%x\n",name,mask);assert(0);}
   unsigned carets=0;for(unsigned k=1;k<host->count;k++){Widget *w=&host->w[k];if(w->kind==KPixels&&w->ramp&&w->shown){carets++;assert(w->w==24&&w->h==3);}   // exactly one 24x3 caret, none when the page has no button
    assert(w->kind!=KRect||w->color==TIO_LENS_FULL||w->color==TIO_LENS_TRACK||!w->shown);}
   assert(carets==(buttons?1u:0u));
   printf("PASS layout %s: %u focus items, reserved rows empty, 16 px floor, no outlines or panels\n",name,buttons);
   if(save_all||focus==0)Save(host,[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png",name]]);
   if(strict&&buttons==3&&focus<3){   // board: actions at x 40/200/300, y 76, 20 px; focused full, others mid; caret top 101
    unsigned b=0;Widget *caret=NULL;for(unsigned k=1;k<host->count;k++){Widget *w=&host->w[k];if(w->kind==KPixels&&w->ramp)caret=w;
     if(w->kind==KText&&w->font==TIO_FONT_BODY){assert(w->x==ItemX[b]&&w->y==76);assert(w->color==(b==focus?TIO_LENS_FULL:TIO_LENS_MID));b++;}}
    assert(b==3&&caret&&caret->x==ItemX[focus]&&caret->y==101);}
   if(strict&&buttons==1&&page==0){   // the shipped gallery overview: one action on the board's action row in M, caret under it, readout lowest in B
    Widget *caret=NULL,*action=NULL,*readout=NULL;for(unsigned k=1;k<host->count;k++){Widget *w=&host->w[k];if(w->kind==KPixels&&w->ramp)caret=w;
     if(w->kind==KText&&w->font==TIO_FONT_BODY)action=w;if(w->kind==KText&&w->font>=TIO_FONT_BODY&&w->y>=TIO_PAGE_M1&&(!readout||w->y>readout->y))readout=w;}
    assert(action&&caret&&action->x==TIO_CORE_X0&&action->y==76&&action->color==TIO_LENS_FULL&&caret->x==TIO_CORE_X0&&caret->y==101);
    assert(readout&&readout->y>=TIO_PAGE_M1&&readout->font>=TIO_FONT_BODY);}
   assert(tap_view_close(v));
   for(unsigned k=1;k<host->count;k++)free((void *)(host->w[k].kind==KText?host->w[k].text:NULL));
   free(v);free(host);}
 }
 free(d);
}
// The firmware-built My Apps shelf (app_shelf.c), strict: title in band T, two caret focus items in band M and two in band B.
static void Shelf(NSString *dir){
 for(unsigned z=0;z<2;z++){language=z;
  for(unsigned installed=0;installed<=4;installed+=2){TAPStore *st=calloc(1,sizeof *st);assert(st);
   for(unsigned i=0;i<4;i++){TAPSlot *s=&st->slots[i];s->present=i<installed;snprintf(s->name,sizeof s->name,z?"%s":"%s",i==1?(z?"通勤助手 · 今日班次与换乘":"Commute · today's trains and transfers"):(z?"番茄时钟":"Focus"));}
   uint8_t wire[512];size_t n=tap_shelf_wire(wire,st,z);char tag[32];snprintf(tag,sizeof tag,"shelf%u-%s",installed,z?"zh":"en");
   AfterOpen=tap_shelf_style;RunWire(dir,tag,wire,n,true,true);AfterOpen=NULL;
   // Intensity and columns: the title and the empty slots are lens-mid (never above an unfocused app), the focused app is lens-full,
   // and the two columns are separated by a gutter of at least 16 px inside the core.
   TAPDocument *d=calloc(1,sizeof *d);assert(tap_parse(wire,n,d));Host *host=calloc(1,sizeof *host);TAPView *v=calloc(1,sizeof *v);create(host,host);
   TAPWidgets api={host,idle,rtRoot,rtText,rtRect,rtImage,rtPlace,visible,destroy,rtTint};
   assert(tap_view_open(v,&api,host,d,0));assert(tap_shelf_style(v));if(installed)assert(tap_view_focus(v,0));
   unsigned item=0,app=0,gaps=0;for(unsigned k=1;k<host->count;k++){Widget *w=&host->w[k];if(w->kind!=KText||!w->text)continue;   // not the root or the caret
    const TAPItem *q=&d->items[d->first[0]+item++];assert(q->kind==1||q->kind==2);
    if(q->kind==1)assert(w->color==TIO_LENS_MID);else assert(w->color==(app++==0?TIO_LENS_FULL:TIO_LENS_MID));
    if(item>1){unsigned slot=item-2;assert(q->w==222&&q->x==(unsigned)(TIO_CORE_X0+238*(slot%2)));if(slot%2){const TAPItem *left=q-1;assert(left->x+left->w+16<=q->x&&q->x+q->w<=(unsigned)TIO_CORE_X1);gaps++;}}}
   assert(item==5&&app==installed&&gaps==2);
   assert(tap_view_close(v));free(v);free(host);free(d);free(st);}
 }
}
static void AppRuntime(NSString *dir,NSString *board,int argc,char **argv){
 NSString *s=[NSString stringWithContentsOfFile:board encoding:NSUTF8StringEncoding error:nil];assert(s&&[s containsString:@"top: 202px; width: 48px; height: 6px"]&&[s containsString:@"const xs = [80, 400, 600]"]);   // caret 202/2 = 101 under actions at 152/2 = 76
 for(unsigned z=0;z<2;z++){language=z;uint8_t wire[512];size_t n=CommuteWire(wire,z);RunWire(dir,z?"app-rt-zh":"app-rt-en",wire,n,true,true);}
 for(int i=3;i<argc;i++){   // NAME=file.tap: current gallery and example packages from dashboard-service, as encoded by the SDK
  char *eq=strchr(argv[i],'=');assert(eq);char tag[48];snprintf(tag,sizeof tag,"app-%.*s",(int)(eq-argv[i]),argv[i]);
  FILE *f=fopen(eq+1,"rb");assert(f);uint8_t *wire=malloc(20480);size_t n=fread(wire,1,20480,f);fclose(f);
  RunWire(dir,tag,wire,n,!strncmp(argv[i],"gallery",7),false);free(wire);}   // the shipped gallery commute package is checked strictly: bands, core, caret rules
}

// ---- Navigation (LensNav, tmg7(2)) ---------------
#define W(p) ((Widget *)(p))
static void color(void *p,void *o,uint32_t rgb){(void)p;Widget *w=o;w->color=rgb;w->fading=rgb!=0&&rgb<TIO_LENS_HIGH&&rgb!=TIO_LENS_MID;}   // between steps = a fading hint
// Compare an EN page with its board's proposed column (board drawn at 2x): same text, size, intensity and band; x and y within 6 px.
static void CompareNavBoard(NSString *html,Host *host,TNView *v){
 NSString *s=[NSString stringWithContentsOfFile:html encoding:NSUTF8StringEncoding error:nil];assert(s);
 NSRange proposed=[s rangeOfString:@"Proposed"];assert(proposed.location!=NSNotFound);s=[s substringFromIndex:proposed.location];
 NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"left: (\\d+)px; top: (\\d+)px; font-size: (\\d+)px;[^\"]*?color: (#[0-9a-f]{6});\">([^<{]+)</div>" options:0 error:nil];
 unsigned matched=0;
 for(NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0,s.length)]){
  int x=[[s substringWithRange:[m rangeAtIndex:1]] intValue]/2,y=[[s substringWithRange:[m rangeAtIndex:2]] intValue]/2,font=[[s substringWithRange:[m rangeAtIndex:3]] intValue]/2;
  uint32_t color=(uint32_t)strtoul([[s substringWithRange:[m rangeAtIndex:4]] UTF8String]+1,NULL,16);NSString *t=[s substringWithRange:[m rangeAtIndex:5]];
  Widget *w=NULL;for(unsigned i=1;i<host->count&&!w;i++)if(host->w[i].shown&&host->w[i].text&&[t isEqualToString:[NSString stringWithUTF8String:host->w[i].text]])w=&host->w[i];   // first match: the distance, not the map scale
  if(!w){printf("board text without fixture widget: %s\n",t.UTF8String);assert(0);}
  matched++;
  if(!(abs(w->x-x)<=6&&abs(w->y-y)<=6&&(int)w->font==font&&w->color==color)){printf("board mismatch %s: board (%d,%d %d px %06x) fixture (%d,%d %u px %06x)\n",t.UTF8String,x,y,font,color,w->x,w->y,w->font,w->color);assert(0);}
  assert(tio_band_of(TIO_SURFACE_PAGE,w->y,w->h)==tio_band_of(TIO_SURFACE_PAGE,y+font/2,1));
 }
 // The map column is anchored to the bottom of band B and ends where the board's map ends (translate(372 28), 148 px wide).
 NSRegularExpression *mapre=[NSRegularExpression regularExpressionWithPattern:@"translate\\((\\d+) (\\d+)\\)" options:0 error:nil];NSTextCheckingResult *mm=[mapre firstMatchInString:s options:0 range:NSMakeRange(0,s.length)];assert(mm);
 int bx=[[s substringWithRange:[mm rangeAtIndex:1]] intValue],by=[[s substringWithRange:[mm rangeAtIndex:2]] intValue];
 // The canvas (192 px) is wider than the board's 148 px window: what counts is the lit columns, which must lie inside x bx..bx+148
 // (the scale bar too: it starts 3 px inside the window), and the car must sit within 3 px of the window centre.
 Widget *map=W(v->map);assert(map->y==by&&map->y+map->h==TIO_PAGE_B1&&map->x+map->w<=TIO_PAGE_W);
 {int lo=999,hi=-1;for(int y=0;y<map->h;y++)for(int x=0;x<map->w;x++)if(map->pixels[y*map->w+x]){int ax=map->x+x;if(ax<lo)lo=ax;if(ax>hi)hi=ax;}
  assert(hi>=0&&lo>=bx&&hi<bx+148);   // every lit column, the scale bar included, is inside the board's window
  assert(map->pixels[137*map->w+(bx+5-map->x)]>=200&&map->pixels[134*map->w+(bx+5-map->x)]>=200);   // the bar and its first tick start 5 px inside it
  assert(abs(map->x+96-(bx+74))<=3);}
 assert(matched==5);
 printf("PASS board LensNav (proposed, halved): %u text items match; band, size, intensity, x and y within tolerance, map column anchored to band B\n",matched);
}
static void Nav(NSString *dir,NSString *board,bool zh,bool longer){
 language=zh;Host host={0};TNWidgets api={&host,idle,create,create,label,place,buffer,text,visible,destroy,cliptext,color};TNView *v=calloc(1,sizeof *v);assert(v);TNScene semantic={.icon=TN_RIGHT,.distance_m=100,.remaining_m=1200,.remaining_s=600};
 strcpy(semantic.turn,zh?"前方右转":"Turn right");strcpy(semantic.road,zh?"进入 市场街":"onto Market St");assert(tn_view_open(v,&api,&host,&semantic));
 uint8_t scene[104]={1,0,0,0};Put16(scene+4,320);scene[6]=4;scene[8]=11;unsigned counts[]={2,2,2,5},styles[]={0,1,4,6};for(unsigned i=0;i<4;i++){scene[16+8*i]=counts[i];scene[18+8*i]=styles[i];}
 int16_t pts[]={-600,240,600,240,300,-160,300,600,-300,200,300,600,0,0,0,160,160,160,160,320,320,320};for(unsigned i=0;i<22;i++)Put16(scene+48+i*2,pts[i]);scene[92]=1;
 assert(tn_view_map(v,TNR_SCENE2,scene,sizeof scene,0));uint8_t name[224]={1,0,0,0};const char *s=zh?"经过 教会街":"Passing Mission St";if(longer)s=zh?"经过 南京西路人民广场世纪公园文化中心滨江国际会议展览中心连接道路历史文化保护区城市公共交通枢纽":"Passing Martin Luther King Junior Boulevard Near the International Conference and Exhibition Center";size_t len=strlen(s);name[4]=len;memcpy(name+8,s,len);
 uint8_t *breakBits=name+200;NSString *nativeName=[NSString stringWithUTF8String:s];[nativeName enumerateSubstringsInRange:NSMakeRange(0,nativeName.length) options:NSStringEnumerationByWords usingBlock:^(NSString *word,NSRange range,NSRange all,BOOL *stop){NSUInteger end=[[nativeName substringToIndex:NSMaxRange(range)] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];breakBits[end/8]|=1u<<(end%8);}];name[200+len/8]|=1u<<(len%8);
 assert(tn_view_map(v,TNR_PASSING,name,sizeof name,0));assert(tn_view_map_tick(v,0));assert(tn_view_clock(v,946684800+10*3600,946684800+10*3600+600,false));
 // TMG6 behaviour kept: one passing line, fixed (never moves with the map), whole words, 16 px floor, scale label, no draw churn at any heading.
 unsigned shown=0;for(unsigned i=0;i<TN_PASS_SIZES;i++){Widget *w=W(v->pass[i]);if(w->shown){shown++;assert(w->x==TIO_CORE_X0&&w->clip&&w->font>=TIO_FONT_MIN);assert(tn_text_width(w->text,strlen(w->text),w->font)<=(unsigned)w->w);
   assert(tio_band_of(TIO_SURFACE_PAGE,w->y,w->h)==TIO_BAND_T);if(!longer)assert(!strncmp(w->text,zh?"经过":"Passing",zh?6:7)&&w->font==TIO_FONT_LABEL&&w->color==TIO_LENS_MID);}}assert(shown==1);
 Widget *scale=W(v->scale);assert(scale->shown&&scale->font==TIO_FONT_MIN&&!strcmp(scale->text,"100 m")&&scale->color==TIO_LENS_HIGH);
 assert(scale->x>=372&&scale->x+scale->w<=520);   // the readout is inside the board's window, left-aligned with the bar
 Widget *trip=W(v->trip[0])->shown?W(v->trip[0]):W(v->trip[1]);assert(trip->shown&&!strcmp(trip->text,zh?"1.2 km \xc2\xb7 10分钟 \xc2\xb7 10:10":"1.2 km \xc2\xb7 10 min \xc2\xb7 10:10")&&trip->color==TIO_LENS_HIGH);
 Widget *dist=W(v->distance);assert(dist->shown&&dist->font==TIO_FONT_PRIMARY&&dist->color==TIO_LENS_FULL&&!strcmp(dist->text,"100 m"));
 unsigned turns=0;for(unsigned i=0;i<TN_TURN_SIZES;i++)if(W(v->turn[i])->shown){Widget *t=W(v->turn[i]);turns++;assert(t->color==TIO_LENS_FULL&&t->x>=dist->x+dist->w&&t->x+t->w<=W(v->map)->x);}assert(turns==1);
 assert(((Widget *)v->road)->shown&&((Widget *)v->road)->color==TIO_LENS_HIGH);
 unsigned before=host.count;for(unsigned heading=0;heading<360;heading++){uint8_t pose[14]={1,0,0,0};Put16(pose+8,heading);assert(tn_view_map(v,TNR_POSE2,pose,sizeof pose,heading+1));assert(tn_view_map_tick(v,heading+1));assert(host.count==before);const uint8_t *raster=((Widget *)v->map)->pixels;assert(raster[87*192+96]>=250&&raster[109*192+104]>=250);for(unsigned i=0;i<TN_PASS_SIZES;i++)assert(W(v->pass[i])->y==TIO_PAGE_T0+((TIO_PAGE_T1-TIO_PAGE_T0)-TIO_LINE(W(v->pass[i])->font))/2);}
 uint8_t pose[14]={1,0,0,0};assert(tn_view_map(v,TNR_POSE2,pose,sizeof pose,5000));assert(tn_view_map_tick(v,6000));
 const uint8_t *pixels=((Widget *)v->map)->pixels;unsigned road=0,route=0;for(unsigned i=0;i<192*144;i++){road+=pixels[i]==140;route+=pixels[i]==255;}assert(road&&route);double roadLight=pow((140.0/255+0.055)/1.055,2.4)*0.7152;double contrast=(0.7152+0.05)/(roadLight+0.05);assert(contrast>3.2);printf("route/brightest road green-channel contrast %.3f:1; route/black halo %.3f:1\n",contrast,(0.7152+0.05)/0.05);
 ((Widget *)v->map)->span=true;                                                  // the map is a spatial element anchored to the right column
 const char *tag=longer?(zh?"nav-long-zh":"nav-long-en"):(zh?"nav-zh":"nav-en");
 Gate(&host,tag,true);
 if(!zh&&!longer)CompareNavBoard(board,&host,v);
 Save(&host,[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png",tag]]);assert(tn_view_close(v));free(v);
}
// ---- Music (LensMusic, tmg7(3)): track in T, next lyric in M, current lyric in B -------------------------------------
static void CompareMusicBoard(NSString *html,Host *host){
 NSString *s=[NSString stringWithContentsOfFile:html encoding:NSUTF8StringEncoding error:nil];assert(s);
 NSRange proposed=[s rangeOfString:@"Proposed"];assert(proposed.location!=NSNotFound);s=[s substringFromIndex:proposed.location];
 NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"left: (\\d+)px; top: (\\d+)px; font-size: (\\d+)px;[^\"]*?color: (#[0-9a-f]{6});\">([^<{]+)</div>" options:0 error:nil];
 unsigned matched=0;
 for(NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0,s.length)]){
  int x=[[s substringWithRange:[m rangeAtIndex:1]] intValue]/2,y=[[s substringWithRange:[m rangeAtIndex:2]] intValue]/2,font=[[s substringWithRange:[m rangeAtIndex:3]] intValue]/2;
  uint32_t color=(uint32_t)strtoul([[s substringWithRange:[m rangeAtIndex:4]] UTF8String]+1,NULL,16);NSString *t=[s substringWithRange:[m rangeAtIndex:5]];
  Widget *w=NULL;NSString *joined=nil;
  for(unsigned i=1;i<host->count&&!w;i++)if(host->w[i].shown&&textual(&host->w[i])){joined=[[NSString stringWithUTF8String:host->w[i].text] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];if([joined containsString:t])w=&host->w[i];}
  if(!w){printf("board text without fixture widget: %s\n",t.UTF8String);assert(0);}
  matched++;bool first=[joined hasPrefix:t];
  // The board wraps its sample lyric onto two rows; a lyric that fits one line is bottom-aligned, so its only row sits where the board's second row is.
  bool oneLine=strchr(w->text,'\n')==NULL&&w->font==TM_CUR_FONT;if(oneLine&&first&&abs(w->y-(y+TIO_LINE(TM_CUR_FONT)))<=8)y+=TIO_LINE(TM_CUR_FONT);
  // The board's 24 px rows (123, 149) overrun band B by a pixel; the fixture keeps them inside it, so y may differ by up to 8.
  if(!(abs(w->x-x)<=8&&(int)w->font==font&&w->color==color&&(first?abs(w->y-y)<=8:(y>=w->y&&y<w->y+w->h+6)))){printf("board mismatch %s: board (%d,%d %d px %06x) fixture (%d,%d %u px %06x)\n",t.UTF8String,x,y,font,color,w->x,w->y,w->font,w->color);assert(0);}
 }
 Widget *art=NULL;for(unsigned i=1;i<host->count;i++)if(host->w[i].kind==KPixels)art=&host->w[i];
 assert(matched==4&&art&&art->art&&art->w==36&&art->h==36&&art->x==40&&[s containsString:@"width: 68px; height: 68px; box-shadow: inset 0 0 0 4px #007700"]);
 printf("PASS board LensMusic (proposed, halved): %u text rows and the 36 px tile match; band, size, intensity, x and y within tolerance\n",matched);
}
static void BuildMusic(Host *h,bool zh,uint32_t now,TIOHint *hint,const uint8_t *tile,bool longLine){
 create(h,h);
 const char *track=zh?"街头 · 灯笼乐队":"Streets \xc2\xb7 The Lanterns",*curRaw=zh?"沿着熟悉的街道慢慢走过每一个曾经相遇的地方":"The morning light is falling",*nextRaw=zh?"在清晨再次回想起那些温暖的故事":"on the streets we used to know";
 if(longLine){curRaw=zh?"沿着熟悉的街道慢慢走过每一个曾经相遇的地方然后在清晨的光里再次回想起那些温暖而漫长的故事直到夜幕降临":"The morning light is falling on the streets we used to know and every window glows with the stories of the city we have loved for years";nextRaw=zh?"在清晨再次回想起那些温暖的故事和我们一起走过的每一条安静的小路直到天亮":"Streets of gold and silver rivers running through the evening light of every city we have ever known";}
 static char cur[244],next[244];tm_two_lines(curRaw,TM_CUR_FONT,cur,sizeof cur);tm_one_line(nextRaw,TIO_CORE_W,TM_NEXT_FONT,next,sizeof next);
 TIORect a=tm_art_rect(),t=tm_track_rect(),n=tm_next_rect(),c=tm_cur_rect_for(cur);
 Widget *w=Add(h,KPixels,a.x,a.y,a.w,a.h,0,0,TIO_BAND_T,NULL);w->pixels=tile;w->art=true;
 bool hintOn=tio_hint_visible(hint,now);
 w=Add(h,KText,t.x,t.y,t.w,t.h,TM_TRACK_FONT,hintOn?tio_hint_color(hint,now):TIO_LENS_MID,TIO_BAND_T,hintOn?(zh?"滚轮：上/下首 · 单击：暂停":"Wheel: Prev / Next | Tap: Pause"):track);w->fading=hintOn&&tio_hint_alpha(hint,now)<255;w->clip=true;
 w=Add(h,KText,n.x,n.y,n.w,n.h,TM_NEXT_FONT,TIO_LENS_HIGH,TIO_BAND_M,next);w->clip=true;
 w=Add(h,KText,c.x,c.y,c.w,c.h,TM_CUR_FONT,TIO_LENS_FULL,TIO_BAND_B,cur);w->clip=true;
}
static void Lyrics(NSString *dir,NSString *board,bool zh){
 language=zh;static uint8_t cover[TM_COVER_BYTES],tile[TM_ART*TM_ART],blank[TM_ART*TM_ART];for(unsigned i=0;i<sizeof cover;i++)cover[i]=(uint8_t)((i%144)*2+i/144);   // full-range cover: the tile must still cap at lens-mid
 tm_art_tile(cover,tile);tm_art_tile(NULL,blank);
 for(unsigned i=0;i<sizeof tile;i++)assert(tile[i]<=TM_ART_LEVEL&&blank[i]<=TM_ART_LEVEL);assert(blank[18*TM_ART+18]==0&&blank[0]==TM_ART_LEVEL&&tile[0]==TM_ART_LEVEL);
 TIOHint hint;tio_hint_init(&hint);tio_hint_enter(&hint,1000);
 const struct {uint32_t now;const char *tag;const uint8_t *pix;} shots[]={{1000,"-hint",tile},{3850,"-hint-fade",tile},{4000,"",tile},{4500,"-nocover",blank}};
 for(unsigned i=0;i<sizeof shots/sizeof *shots;i++){Host *host=calloc(1,sizeof *host);assert(host);BuildMusic(host,zh,shots[i].now,&hint,shots[i].pix,false);
  char name[48];snprintf(name,sizeof name,"lyrics%s-%s",shots[i].tag,zh?"zh":"en");Gate(host,name,true);
  Widget *track=&host->w[2];if(!strcmp(shots[i].tag,"-hint"))assert(track->color==TIO_LENS_HIGH&&track->font==TIO_FONT_LABEL);if(!strcmp(shots[i].tag,"-hint-fade"))assert(track->color>0&&track->color<TIO_LENS_HIGH);
  if(!strcmp(shots[i].tag,"")){assert(track->color==TIO_LENS_MID&&host->w[3].color==TIO_LENS_HIGH&&host->w[4].color==TIO_LENS_FULL);if(!zh)CompareMusicBoard(board,host);}
  // Ordering: current lyric lowest, next above it, track on top; at most two lines of 24 px in the current-lyric box.
  assert(host->w[2].y<host->w[3].y&&host->w[3].y+host->w[3].h<=host->w[4].y&&host->w[4].y+host->w[4].h==TIO_PAGE_B1);
  unsigned lines=1;for(const char *p=host->w[4].text;*p;p++)lines+=*p=='\n';assert(lines<=2&&host->w[4].h==(int)lines*TIO_LINE(TM_CUR_FONT)&&tm_width(host->w[3].text,strlen(host->w[3].text),TM_NEXT_FONT)<=TIO_CORE_W);
  // The current-lyric label is the lens core wide, and no wrapped row is estimated wider than it.
  assert(host->w[4].w==TIO_CORE_W&&host->w[4].x==TIO_CORE_X0&&host->w[3].w==TIO_CORE_W);
  {const char *row=host->w[4].text;while(*row){const char *e=strchr(row,'\n');size_t n=e?(size_t)(e-row):strlen(row);assert(tm_width(row,n,TM_CUR_FONT)<=TIO_CORE_W);row+=n+(e?1:0);}}
  Save(host,[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png",name]]);free(host);}
 // Long lines: two-line cap with an ellipsis, rows within the core, label still TIO_CORE_W wide.
 for(unsigned z=0;z<2;z++){language=z;Host *host=calloc(1,sizeof *host);assert(host);BuildMusic(host,z,4000,&hint,tile,true);char name[48];snprintf(name,sizeof name,"lyrics-long-%s",z?"zh":"en");Gate(host,name,true);
  assert(host->w[4].w==TIO_CORE_W);unsigned lines=1;for(const char *p=host->w[4].text;*p;p++)lines+=*p=='\n';assert(lines==2&&host->w[4].h==2*TIO_LINE(TM_CUR_FONT)&&strstr(host->w[4].text,"\xe2\x80\xa6"));
  const char *row=host->w[4].text;while(*row){const char *e=strchr(row,'\n');size_t n=e?(size_t)(e-row):strlen(row);assert(tm_width(row,n,TM_CUR_FONT)<=TIO_CORE_W);row+=n+(e?1:0);}
  assert(!strchr(host->w[3].text,'\n')&&strstr(host->w[3].text,"\xe2\x80\xa6"));Save(host,[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png",name]]);free(host);}
 language=zh;
 // A next lyric too long for one line ends in an ellipsis and never wraps.
 char one[244];tm_one_line("Streets of gold and silver rivers running through the evening light of every city we have ever known",TIO_CORE_W,TM_NEXT_FONT,one,sizeof one);assert(!strchr(one,'\n')&&strstr(one,"\xe2\x80\xa6")&&tm_width(one,strlen(one),TM_NEXT_FONT)<=TIO_CORE_W);
 tm_one_line("short",TIO_CORE_W,TM_NEXT_FONT,one,sizeof one);assert(!strcmp(one,"short"));
 tm_one_line("",TIO_CORE_W,TM_NEXT_FONT,one,sizeof one);assert(!*one);
}
// ---- Focus timer (LensFocus, tmg7(4)): the real TFView on mock widgets ------------------------------------------------------
static void CompareFocusBoard(NSString *html,Host *host){
 NSString *s=[NSString stringWithContentsOfFile:html encoding:NSUTF8StringEncoding error:nil];assert(s);
 NSRange proposed=[s rangeOfString:@"Proposed"];assert(proposed.location!=NSNotFound);s=[s substringFromIndex:proposed.location];
 NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"left: (\\d+)px; top: (\\d+)px; font-size: (\\d+)px;[^\"]*?color: (#[0-9a-f]{6});[^\"]*\">([^<{]+)</div>" options:0 error:nil];
 unsigned matched=0;
 for(NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0,s.length)]){
  int x=[[s substringWithRange:[m rangeAtIndex:1]] intValue]/2,y=[[s substringWithRange:[m rangeAtIndex:2]] intValue]/2,font=[[s substringWithRange:[m rangeAtIndex:3]] intValue]/2;
  uint32_t color=(uint32_t)strtoul([[s substringWithRange:[m rangeAtIndex:4]] UTF8String]+1,NULL,16);NSString *t=[s substringWithRange:[m rangeAtIndex:5]];
  Widget *w=NULL;for(unsigned i=1;i<host->count&&!w;i++)if(host->w[i].shown&&textual(&host->w[i])&&(int)host->w[i].font==font&&host->w[i].color==color)w=&host->w[i];   // match by size and intensity: "Break at 10:35" needs a wall clock the glasses lack, so the M row shows what comes next
  if(!w){printf("board text without fixture widget: %s\n",t.UTF8String);assert(0);}
  matched++;
  bool exact=![t hasPrefix:@"Break"];if(exact)assert([t isEqualToString:[NSString stringWithUTF8String:w->text]]);
  if(!(abs(w->x-x)<=8&&abs(w->y-y)<=8)){printf("board mismatch %s: board (%d,%d %d px %06x) fixture (%d,%d %u px %06x)\n",t.UTF8String,x,y,font,color,w->x,w->y,w->font,w->color);assert(0);}
 }
 assert(matched==3);
 Widget *bar=NULL;for(unsigned i=1;i<host->count;i++)if(host->w[i].kind==KPixels)bar=&host->w[i];assert(bar&&bar->x==40&&bar->y==44&&bar->w==460&&bar->h==4&&[s containsString:@"left: 80px; top: 88px; width: 920px; height: 8px"]);
 unsigned fill=0;while(fill<460&&bar->pixels[fill]==TF_FILL_LEVEL)fill++;assert(abs((int)fill-236/2)<=4);   // board: 236 of 920 at 2x
 printf("PASS board LensFocus (proposed, halved): %u text rows and the progress track match; band, size, intensity, x and y within tolerance\n",matched);
}
static void Focus(NSString *dir,NSString *board,bool zh){
 language=zh;
 struct {const char *tag;uint32_t now;unsigned status,phase,completed,remaining_s,duration_s;bool compact,input;} shots[]={
  {"-hint",1000,TF_RUNNING,0,1,1122,1500,false,false},{"-hint-fade",3850,TF_RUNNING,0,1,1122,1500,false,false},{"",4000,TF_RUNNING,0,1,1122,1500,false,false},
  {"-compact",9000,TF_RUNNING,0,1,1122,1500,true,false},{"-paused",4000,TF_PAUSED,0,1,600,1500,false,false},{"-break",4000,TF_RUNNING,2,4,250,900,false,false},
  {"-done",4000,TF_DONE,0,4,0,1500,false,false},{"-ready",4000,TF_IDLE,0,0,1500,1500,false,false},{"-long",4000,TF_RUNNING,0,3,7200,7200,false,false}};
 for(unsigned i=0;i<sizeof shots/sizeof *shots;i++){typeof(shots[0]) *sh=&shots[i];Host *host=calloc(1,sizeof *host);assert(host);create(host,host);
  TNWidgets api={host,idle,create,create,label,place,buffer,text,visible,destroy,cliptext,color};TFView *v=calloc(1,sizeof *v);assert(v);assert(tf_view_open(v,&api,host,host));tf_view_enter(v,1000);
  if(i==0){   // the hint lifetime the service ticks on: entry, then every wheel step or press (also while the timer runs), gone at 3000 ms
   assert(tf_view_hint(v,1000)&&tf_view_hint(v,3999)&&!tf_view_hint(v,4000)&&!tf_view_hint(v,9000));
   tf_view_input(v,9000);assert(tf_view_hint(v,9000)&&tf_view_hint(v,11999)&&!tf_view_hint(v,12000));}
  if(i==0)tf_view_enter(v,1000);
  TFocus st;tf_init(&st,0);st.status=sh->status;st.phase=sh->phase;st.completed=sh->completed;st.remaining_ms=sh->remaining_s*1000;st.duration_s=sh->duration_s;
  assert(tf_view_draw(v,&st,sh->compact,sh->now));
  char name[48];snprintf(name,sizeof name,"focus%s-%s",sh->tag,zh?"zh":"en");Gate(host,name,true);
  Widget *title=W(v->labels[TF_L_TITLE]),*count=W(v->labels[TF_L_COUNT]),*status=W(v->labels[TF_L_STATUS]),*time=W(v->labels[TF_L_TIME]);
  assert(time->font==TIO_FONT_HERO&&time->color==TIO_LENS_FULL&&status->font==TIO_FONT_BODY&&status->color==TIO_LENS_HIGH&&title->font==TIO_FONT_LABEL);
  assert(time->y>status->y&&status->y>title->y);                                  // primary information lowest
  if(!strcmp(sh->tag,"-hint")){assert(title->color==TIO_LENS_HIGH&&!count->shown&&time->shown);}
  if(!strcmp(sh->tag,"-hint-fade"))assert(title->color>0&&title->color<TIO_LENS_HIGH&&!tf_view_due(v,3850,false)&&tf_view_due(v,4000,false));
  if(!strcmp(sh->tag,"")){assert(title->color==TIO_LENS_MID&&count->shown&&!strcmp(count->text,"2 / 4")&&!strcmp(time->text,"18:42"));if(!zh)CompareFocusBoard(board,host);}
  if(!strcmp(sh->tag,"-compact"))assert(title->shown&&!count->shown&&!status->shown&&!time->shown&&!W(v->bar)->shown);
  if(!strcmp(sh->tag,"-break"))assert(!strcmp(count->text,"4 / 4")&&!strcmp(status->text,tio_text(TT_FOCUS_NEXT_FOCUS,zh)));
  if(!strcmp(sh->tag,"-done")){assert(!strcmp(count->text,"4 / 4"));unsigned lit=0;for(int k=0;k<460*4;k++)lit+=W(v->bar)->pixels[k]==TF_FILL_LEVEL;assert(lit==460*4);}   // finished: track full
  if(!strcmp(sh->tag,"-ready")){for(int k=0;k<460*4;k++)assert(W(v->bar)->pixels[k]==TF_TRACK_LEVEL);}
  if(!strcmp(sh->tag,"-long")){assert(!strcmp(time->text,"120:00")&&!strcmp(status->text,tio_text(TT_FOCUS_NEXT_LONG,zh)));assert(tn_text_width(time->text,strlen(time->text),TIO_FONT_HERO)<=(unsigned)time->w);}
  assert(tn_text_width(title->text,strlen(title->text),TIO_FONT_LABEL)<=(unsigned)title->w&&tn_text_width(status->text,strlen(status->text),TIO_FONT_BODY)<=(unsigned)status->w);
  Save(host,[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png",name]]);assert(tf_view_close(v));free(v);free(host);}
}
// ---- Menu (LensMenu, tmg7(7)): the real FMView on mock widgets -------------------------------------------------------------
static bool attach_ok(void *o,void *owner){return o&&owner;}
// TMG8 live tile state fixtures: the board's three scenarios (LensMenuCarousel.dc.html / LensMenuGrid2.dc.html STATUS), through the production ts_state.
static const TSLive kLive={.phone=true,.pomodoro=true,.pomodoro_ms=18*60000+42000,.music_playing=true,.music_age_ms=1000,.music_title="Blinding Lights",.nav_active=true,.nav_remaining_m=1200};
static const TSLive kIdle={.phone=true};
static const TSLive kOffline={.phone=false,.pomodoro=true,.pomodoro_ms=18*60000+42000};
static const TSLive kCamera={.phone=true,.camera=true};
// TMG8 navigation title fixtures (OptionANavTitle.dc.html): the production nt_title over a stubbed nav_service turn. Same running state as kLive plus the next turn.
#define ROUTE_BASE .phone=true,.pomodoro=true,.pomodoro_ms=18*60000+42000,.music_playing=true,.music_age_ms=1000,.music_title="Blinding Lights",.nav_active=true,.nav_remaining_m=1200,.nav_turn=true
static const TSLive kRoute={ROUTE_BASE,.nav_icon=TN_RIGHT,.nav_turn_m=200,.nav_road="Market St"};                                                   // the board
static const TSLive kRouteLong={ROUTE_BASE,.nav_icon=TN_LEFT,.nav_turn_m=1500,.nav_road="Martin Luther King Jr. Boulevard South Extension"};       // cut at a word boundary
static const TSLive kRouteWord={ROUTE_BASE,.nav_icon=TN_UTURN,.nav_turn_m=80,.nav_road="Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch"};   // one long word: cut at a character
static const TSLive kRouteCjk={ROUTE_BASE,.nav_icon=TN_SLIGHT_RIGHT,.nav_turn_m=350,.nav_road="\xe4\xba\xba\xe6\xb0\x91\xe5\xa4\xa7\xe9\x81\x93\xe4\xb8\x8e\xe4\xb8\xad\xe5\xb1\xb1\xe4\xb8\x9c\xe8\xb7\xaf\xe4\xba\xa4\xe5\x8f\x89\xe5\x8f\xa3\xe5\x8d\x97\xe4\xbe\xa7\xe8\xbe\x85\xe8\xb7\xaf"};   // no spaces
static const TSLive kRouteRound={ROUTE_BASE,.nav_icon=TN_ROUNDABOUT,.nav_turn_m=950,.nav_road=""};                                                    // no road name: the distance alone
// What fm_sync does with the turn: the title and, for the carousel, the route flag that makes room for it.
static void ApplyTitle(FMView *v,const TSLive *live,uint32_t now){NTTitle t;nt_title(live,&t);assert(fm_view_route(v,t.on,now));assert(fm_view_title(v,&t,now));}
static unsigned LiveMask(const TTVisible *tiles,const TSLive *live){unsigned m=0;for(unsigned r=0;r<tiles->count;r++){TSState st;ts_state(tiles->ids[r],live,language,&st);if(st.active)m|=1u<<tiles->ids[r];}return m;}
// Fixture: the settled menu for `rows` x 3 cells, `hide` (0..31) hides stock tiles 7..11, `selected` is the compact index.
static void BuildMenu(Host *host,FMView *v,unsigned rows,unsigned hide,unsigned selected,const TSLive *live){
 create(host,host);TNWidgets api={host,idle,create,create,label,place,buffer,text,visible,destroy,cliptext,color};
 assert(fm_view_open(v,&api,host,attach_ok,host));
 TTConfig config;TTVisible tiles;assert(tt_unrank(0,hide<<7,&config)&&tt_compact(&config,&tiles));assert(fm_view_rows(v,rows)&&fm_view_tiles(v,&tiles));
 assert(fm_view_update(v,(int)selected,946684800+10*3600,82,1000));
 for(unsigned i=0;i<FM_CELLS;i++){W(v->labels[i])->ambient=true;W(v->icons[i])->ramp=true;W(v->dots[i])->ramp=true;}W(v->caret)->ramp=true;W(v->page)->ramp=true;
 for(unsigned i=0;i<FM_CELLS;i++)W(v->labels[i])->align=1;W(v->battery)->align=2;W(v->name)->align=1;   // mirrors fm_show: menu_text_align centre / right / centre
 if(live){assert(fm_view_active(v,LiveMask(&tiles,live)));(void)fm_view_step(v,1100);assert(!v->dirty);   // the 1 Hz refresh found running tiles: state dots
  ApplyTitle(v,live,1200);(void)fm_view_step(v,1300);assert(!v->dirty);}                                      // and a route: the next turn in band T
}
// Compare the fixture (EN, 8 tiles, two pages, second cell focused) with the board's proposed column (drawn at 2x).
static void CompareMenuBoard(NSString *html,Host *host,FMView *v){
 NSString *s=[NSString stringWithContentsOfFile:html encoding:NSUTF8StringEncoding error:nil];assert(s);
 NSRange proposed=[s rangeOfString:@"Proposed"];assert(proposed.location!=NSNotFound);s=[s substringFromIndex:proposed.location];
 NSRange guides=[s rangeOfString:@"<sc-if"];if(guides.location!=NSNotFound)s=[s substringToIndex:guides.location];   // the band guides are an editor overlay, not part of the design
 NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"(left|right): (\\d+)(?:px)?;(?: width: (\\d+)px;)? top: (\\d+)px;[^\"]*?font-size: (\\d+)px;[^\"]*?color: (#[0-9a-f]{6});\">([^<{]+)</div>" options:0 error:nil];
 unsigned grid=0,status=0,name=0;
 for(NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0,s.length)]){
  bool right=[[s substringWithRange:[m rangeAtIndex:1]] isEqualToString:@"right"];int edge=[[s substringWithRange:[m rangeAtIndex:2]] intValue]/2;
  int width=[m rangeAtIndex:3].location==NSNotFound?0:[[s substringWithRange:[m rangeAtIndex:3]] intValue]/2;int y=[[s substringWithRange:[m rangeAtIndex:4]] intValue]/2,font=[[s substringWithRange:[m rangeAtIndex:5]] intValue]/2;
  uint32_t color=(uint32_t)strtoul([[s substringWithRange:[m rangeAtIndex:6]] UTF8String]+1,NULL,16);
  if(font==18){   // status row: time left, battery right, lens-label in lens-mid
   Widget *w=right?W(v->battery):W(v->status);assert(w->font==18&&w->color==color&&color==TIO_LENS_MID&&abs(w->y-y)<=3);
   assert(right?w->x+w->w==TIO_PAGE_W-edge:w->x==edge);status++;
  }else if(font==16){   // grid names: centred on the icon column, lens-min in lens-mid, row within 6 px
   int cx=edge+width/2;Widget *w=NULL;for(unsigned i=0;i<FM_CELLS&&!w;i++){Widget *c=W(v->labels[i]);if(c->shown&&abs(c->x+c->w/2-cx)<=1&&abs(c->y-y)<=6)w=c;}
   if(!w){printf("board name at %d,%d without fixture label\n",cx,y);assert(0);}assert(w->font==16&&w->color==color&&color==TIO_LENS_MID);grid++;
  }else{   // focused name: lens-title in lens-full, centred in band B
   Widget *w=W(v->name);assert(font==24&&color==TIO_LENS_FULL&&w->font==24&&w->x+w->w/2==edge+width/2&&abs(w->y-y)<=6&&tio_band_of(TIO_SURFACE_MENU,w->y,w->h)==TIO_BAND_B);name++;
  }
 }
 assert(status==2&&grid==5&&name==1);   // five other cells show a name; the focused one shows it once, in band B
 // Caret 24x3 under the focused icon, page dots in band T (12 and 4 px wide, 6 px apart), both within a pixel of the board.
 NSRegularExpression *rr=[NSRegularExpression regularExpressionWithPattern:@"<rect x=\"(\\d+)\" y=\"(\\d+)\" width=\"(\\d+)\" height=\"(\\d+)\" rx=\"[\\d.]+\" fill=\"#([0-9a-f]{6})\"/>" options:0 error:nil];
 unsigned seen=0;
 for(NSTextCheckingResult *m in [rr matchesInString:s options:0 range:NSMakeRange(0,s.length)]){
  int x=[[s substringWithRange:[m rangeAtIndex:1]] intValue],y=[[s substringWithRange:[m rangeAtIndex:2]] intValue],w=[[s substringWithRange:[m rangeAtIndex:3]] intValue],h=[[s substringWithRange:[m rangeAtIndex:4]] intValue];
  if(w==24&&h==3){Widget *c=W(v->caret);assert(c->w==24&&c->h==3&&abs(c->x-x)<=1&&abs(c->y-y)<=4);seen|=1;}
  if(w==12&&h==4){Widget *d=W(v->page);int first=-1;for(int k=0;k<d->w&&first<0;k++)if(d->pixels[1*d->w+k]==176)first=k;assert(first>=0&&abs(d->x+first-x)<=1&&abs(d->y-y)<=1&&d->y>=TIO_MENU_T0&&d->y+d->h<=TIO_MENU_T1);seen|=2;}
  if(w==4&&h==4){Widget *d=W(v->page);int first=-1;for(int k=0;k<d->w;k++)if(d->pixels[1*d->w+k]==119){first=k;break;}assert(first>=0&&abs(d->x+first-x)<=1);seen|=4;}
 }
 assert(seen==7);
 printf("PASS board LensMenu (proposed, halved): status row, five grid names, focused name in band B, 24x3 caret and page dots match\n");(void)host;
}
static bool utf8_ok(const char *s){const unsigned char *p=(const unsigned char *)s;while(*p){unsigned a=*p++,n;if(a<128)continue;n=a>=0xc2&&a<=0xdf?1:a>=0xe0&&a<=0xef?2:a>=0xf0&&a<=0xf4?3:99;if(n==99)return false;for(unsigned j=0;j<n;j++)if((*p++&0xc0)!=0x80)return false;}return true;}
// The boards' STATUS table (EN) against the production strings: three scenarios x navigation, music, pomodoro. A dot only where something runs.
static void CheckStatusBoard(NSString *path){
 NSString *html=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];assert(html);
 NSRange r=[html rangeOfString:@"const STATUS = {"];assert(r.location!=NSNotFound);NSString *t=[html substringFromIndex:r.location];t=[t substringToIndex:[t rangeOfString:@"};"].location];
 const struct {NSString *key;const TSLive *live;} scen[]={{@"live",&kLive},{@"idle",&kIdle},{@"phoneoff",&kOffline}};
 const struct {NSString *key;unsigned id;} tiles[]={{@"navigation",TIO_TILE_NAVIGATION},{@"music",TIO_TILE_MUSIC},{@"pomodoro",TIO_TILE_FOCUS}};
 for(unsigned i=0;i<3;i++){
  NSRange sr=[t rangeOfString:[scen[i].key stringByAppendingString:@": {"]];assert(sr.location!=NSNotFound);NSString *body=[t substringFromIndex:NSMaxRange(sr)];body=[body substringToIndex:[body rangeOfString:@"}"].location];
  for(unsigned k=0;k<3;k++){
   NSTextCheckingResult *m=[[NSRegularExpression regularExpressionWithPattern:[tiles[k].key stringByAppendingString:@": '([^']*)'"] options:0 error:nil] firstMatchInString:body options:0 range:NSMakeRange(0,body.length)];
   NSString *want=m?[body substringWithRange:[m rangeAtIndex:1]]:@"";TSState st;ts_state(tiles[k].id,scen[i].live,0,&st);
   NSString *got=[NSString stringWithUTF8String:st.line];if(![got isEqualToString:want]){NSLog(@"board %@/%@: want '%@' got '%@'",scen[i].key,tiles[k].key,want,got);assert(0);}
   assert(st.active==(want.length&&![want isEqualToString:@"Phone not connected"]));
  }
 }
 if([html containsString:@"dx: t.cx"]){assert([html containsString:@"dx: t.cx + 17, dy: t.cy - 20"]&&[html containsString:@"width: 5px; height: 5px"]&&[html containsString:@"background: #007700"]);}   // the grid board's dot: 5 px, lens-mid, (cx+17, cy-20)
 printf("PASS board STATUS (%s): live, idle and phone-off strings and dots match the production tile state\n",path.lastPathComponent.UTF8String);
}
// The navigation title widgets against the production text and the slot rules (nav_title.h); hidden when no route.
static void CheckTitle(Host *host,FMView *v,const TSLive *live){
 NTTitle t;nt_title(live,&t);Widget *ar=W(v->title_arrow),*tx=W(v->title_text);assert(ar->shown==t.on&&tx->shown==t.on&&v->title_on==t.on&&v->route==t.on);
 if(!t.on)return;
 assert(tx->kind==KText&&tx->font==TIO_FONT_LABEL&&tx->color==TIO_LENS_HIGH&&tx->clip&&tx->align==0&&!strcmp(tx->text,t.text)&&utf8_ok(tx->text));   // 18 px, lens-high, centred in its box
 assert(ar->kind==KPixels&&ar->w==NT_ARROW&&ar->h==NT_ARROW);{uint8_t peak=0;for(int q=0;q<ar->w*ar->h;q++)if(ar->pixels[q]>peak)peak=ar->pixels[q];assert(peak==(TIO_LENS_HIGH>>8&255u));}
 assert(tio_band_of(TIO_SURFACE_MENU,tx->y,tx->h)==TIO_BAND_T&&tio_band_of(TIO_SURFACE_MENU,ar->y,ar->h)==TIO_BAND_T&&ar->y+ar->h/2==tx->y+tx->h/2);
 assert(ar->x>=NT_X0&&tx->x+tx->w<=NT_X1&&tx->w<=NT_TEXT_W&&tx->x-(ar->x+ar->w)==NT_GAP);                                                  // inside the slot, 6 px gap
 {int mid=(ar->x+tx->x+tx->w)/2;assert(abs(mid-270)<=tx->w/8+2);}                                                                                 // the group is centred on x 270
 {NSString *s=[NSString stringWithUTF8String:tx->text];int ink=(int)ceil([s sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:18]}].width);assert(ink<=tx->w);}   // the estimate errs wide: the real text fits its box
 Widget *clock=W(v->status),*battery=W(v->battery);assert(clock->x+clock->w<=ar->x&&tx->x+tx->w<=battery->x);                                 // clear of the clock and the battery boxes
 for(unsigned i=0;i<FM_CELLS;i++)if(W(v->icons[i])->shown){assert(!overlap(W(v->icons[i]),ar)&&!overlap(W(v->icons[i]),tx));}
 if(v->rows!=FM_CAROUSEL)assert(!W(v->page)->shown);                                                                                         // the page dots share band T
 (void)host;
}
// The board's title line (OptionANavTitle.dc.html): 18 px arrow, 6 px gap, 18 px lens-high text "200 m · Market St", centred, on the top row.
static void CheckTitleBoard(NSString *path,FMView *v){
 NSString *h=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];assert(h);
 assert([h containsString:@"top: 20px; display: flex; justify-content: center; align-items: center; gap: 6px; font-size: 18px; line-height: 1; color: #00b000;\"><svg width=\"18\" height=\"18\""]);
 assert([h containsString:@"<span>200 m \u00b7 Market St</span>"]);
 NTTitle t;nt_title(&kRoute,&t);assert(!strcmp(t.text,"200 m \xc2\xb7 Market St")&&NT_GAP==6&&NT_ARROW==18&&TIO_FONT_LABEL==18&&TIO_LENS_HIGH==0x00b000u);
 Widget *tx=W(v->title_text);assert(abs(tx->y-20)<=3);                                                                                          // same row as the clock (board 21), within the board tolerance
 printf("PASS board OptionANavTitle: 18 px arrow, 6 px gap, 18 px lens-high \"200 m \u00b7 Market St\", centred on the top row\n");
}
static void Menu(NSString *dir,NSString *board,bool zh){
 language=zh;gSurface=TIO_SURFACE_MENU;
 {Host h={0};create(&h,&h);Add(&h,KText,40,205,100,20,16,TIO_LENS_FULL,TIO_BAND_B,"a");assert(Check(&h,"x",false)&(VReserved|VBand));   // the gate guards the menu's bottom strip
  h=(Host){0};create(&h,&h);Add(&h,KText,40,200,100,28,24,TIO_LENS_FULL,TIO_BAND_B,"a");assert(Check(&h,"x",false)&VCanvas);}
 struct {const char *tag;unsigned rows,hide,selected;const TSLive *live;} shots[]={
  {"",2,31,1,NULL},             // board: 8 tiles, two pages, second icon focused
  {"-all",2,0,8,NULL},          // 13 tiles, Navigation focused on page 2
  {"-wide",2,0,7,NULL},         // "Do Not Disturb" in an outer column next to the focused icon
  {"-camera",2,0,12,NULL},      // Camera, alone on page 3
  {"-rows3",3,0,4,NULL},        // dense grid: icons only, name in band B
  {"-rows3-p2",3,0,11,NULL},
  {"-live",2,0,8,&kLive},       // LensMenuGrid2: a dot on navigation, music and pomodoro
  {"-live-offline",2,0,8,&kOffline},   // phone not connected: no dot for navigation and music, the local timer keeps its dot
  {"-live-camera",2,0,12,&kCamera},
  {"-live-rows3",3,0,8,&kLive},
  {"-route",2,0,8,&kRoute},         // OptionANavTitle: the next turn centred in band T above the grid, page dots gone
  {"-route-long",2,0,1,&kRouteLong},   // a long road: cut at a word boundary
  {"-route-word",2,0,9,&kRouteWord},   // one long word: cut at a character
  {"-route-cjk",2,0,12,&kRouteCjk},    // no spaces: cut after a character
  {"-route-nameless",2,0,10,&kRouteRound},   // no road name: the distance alone
  {"-route-rows3",3,0,8,&kRoute}};
 for(unsigned i=0;i<sizeof shots/sizeof *shots;i++){
  Host *host=calloc(1,sizeof *host);assert(host);FMView *v=calloc(1,sizeof *v);assert(v);const typeof(shots[0]) *sh=&shots[i];
  BuildMenu(host,v,sh->rows,sh->hide,sh->selected,sh->live);char name[48];snprintf(name,sizeof name,"menu%s-%s",sh->tag,zh?"zh":"en");Gate(host,name,true);
  CheckTitle(host,v,sh->live?sh->live:&kIdle);if(!zh&&!strcmp(sh->tag,"-route"))CheckTitleBoard([[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"OptionANavTitle.dc.html"],v);
  const unsigned cells=sh->rows*3,cell=sh->selected%cells;TTConfig config;TTVisible tiles;assert(tt_unrank(0,sh->hide<<7,&config)&&tt_compact(&config,&tiles));
  Widget *status=W(v->status),*battery=W(v->battery),*nm=W(v->name),*caret=W(v->caret),*dots=W(v->page);
  // Status row: time and battery in lens-mid, band T, no wordmark; focused name once in B in lens-full; nothing else carries it.
  assert(!strcmp(status->text,"10:00")&&!strcmp(battery->text,"82%")&&status->color==TIO_LENS_MID&&battery->color==TIO_LENS_MID&&status->font==TIO_FONT_LABEL);
  assert(nm->font==TIO_FONT_TITLE&&nm->color==0&&nm->x==TIO_CORE_X0&&nm->w==TIO_CORE_W&&strlen(nm->text)>0);
  for(unsigned k=1;k<host->count;k++)if(host->w[k].text&&!strcmp(host->w[k].text,"Turbo IO"))assert(0);
  unsigned namesShown=0;for(unsigned k=0;k<FM_CELLS;k++){Widget *l=W(v->labels[k]);if(l->shown){namesShown++;assert(l->font==TIO_FONT_MIN&&l->color==TIO_LENS_MID&&strcmp(l->text,nm->text)&&k!=cell);}}
  unsigned onPage=tiles.count-sh->selected/cells*cells;if(onPage>cells)onPage=cells;assert(namesShown==(sh->rows==2?onPage-1:0));
  // Focused icon in lens-full, the others no brighter than lens-mid; caret 24x3 lens-full, dots lens-high / lens-mid.
  for(unsigned k=0;k<FM_CELLS;k++){Widget *ic=W(v->icons[k]);if(!ic->shown)continue;uint8_t peak=0;for(int q=0;q<ic->w*ic->h;q++)if(ic->pixels[q]>peak)peak=ic->pixels[q];
   if(k==cell)assert(peak>=250);else assert(peak<=TIO_LENS_MID>>8&255u);}
  for(int q=0;q<caret->w*caret->h;q++)assert(caret->pixels[q]==0||caret->pixels[q]==255);
  {unsigned pages=(tiles.count+cells-1)/cells,hi=0,mid=0;for(int q=0;q<dots->w*dots->h;q++){uint8_t g=dots->pixels[q];assert(g==0||g==(TIO_LENS_HIGH>>8&255u)||g==(TIO_LENS_MID>>8&255u));hi+=g==(TIO_LENS_HIGH>>8&255u);mid+=g==(TIO_LENS_MID>>8&255u);}
   assert(hi==12*4-4&&mid==(pages-1)*(4*4-4));}
  assert(caret->y>=W(v->icons[cell])->y+W(v->icons[cell])->h&&caret->x+12==W(v->icons[cell])->x+W(v->icons[cell])->w/2);
  // State dots (LensMenuGrid2): a 5 px lens-mid disc 1 px right of and 4 px above the icon box ((cx+17, cy-20) for the 32 px icon), only where something runs.
  {const unsigned mask=sh->live?LiveMask(&tiles,sh->live):0;unsigned on=0;Widget *lines=W(v->line);assert(!lines->shown);
   for(unsigned k=0;k<FM_CELLS;k++){Widget *d=W(v->dots[k]);unsigned at=sh->selected/cells*cells+k;const bool want=k<cells&&at<tiles.count&&(mask>>tiles.ids[at]&1);assert(d->shown==want);if(!want)continue;on++;
    Widget *ic=W(v->icons[k]);unsigned lit=0;int x0=99,y0=99,x1=-1,y1=-1;
    for(int y=0;y<d->h;y++)for(int x=0;x<d->w;x++){uint8_t g=d->pixels[y*d->w+x];assert(g==0||g==(TIO_LENS_MID>>8&255u));if(g){lit++;if(x<x0)x0=x;if(x>x1)x1=x;if(y<y0)y0=y;if(y>y1)y1=y;}}
    assert(lit==21&&x0==0&&y0==0&&x1==4&&y1==4);                                                 // a 5x5 disc with its corners cut
    const int cx=ic->x+ic->w/2,cy=ic->y+ic->h/2,top=ic->y-4<TIO_MENU_T1?TIO_MENU_T1:ic->y-4;
    assert(d->x==cx+ic->w/2+1&&d->y==top);
    if(sh->rows==2){assert(ic->w==32&&d->x==cx+17&&d->y==(cy-20<TIO_MENU_T1?TIO_MENU_T1:cy-20));}
    assert(tio_band_of(TIO_SURFACE_MENU,d->y,5)==TIO_BAND_M&&d->x>=TIO_CORE_X0&&d->x+5<=TIO_CORE_X1);
    for(unsigned o=0;o<FM_CELLS;o++){Widget *oi=W(v->icons[o]),*ol=W(v->labels[o]);if(oi->shown)assert(!(d->x<oi->x+oi->w&&oi->x<d->x+5&&d->y<oi->y+oi->h&&oi->y<d->y+5));
     if(ol->shown)assert(!(d->x<ol->x+ol->w&&ol->x<d->x+5&&d->y<ol->y+ol->h-TIO_TEXT_PAD&&ol->y<d->y+5));}   // not on an icon, not on a name's 16 px glyph row
    assert(!(d->x<caret->x+caret->w&&caret->x<d->x+5&&d->y<caret->y+caret->h&&caret->y<d->y+5));}
   unsigned want_on=0;for(unsigned k=0;k<cells;k++){unsigned at=sh->selected/cells*cells+k;if(at<tiles.count&&(mask>>tiles.ids[at]&1))want_on++;}assert(on==want_on);
   if(!strcmp(sh->tag,"-live")){assert(on==3);}if(!strcmp(sh->tag,"-live-offline")){assert(on==1);}}
  if(!strcmp(sh->tag,"")&&!zh)CompareMenuBoard(board,host,v);
  if(!strcmp(sh->tag,"-wide")){Widget *l=W(v->labels[0]);assert(l->shown&&!strcmp(l->text,tio_text(TT_GRID_6,zh))&&l->x>=TIO_INSET_X);   // the longest name fits its column
   if(!zh){NSDictionary *a=@{NSFontAttributeName:[NSFont systemFontOfSize:16]};assert([[NSString stringWithUTF8String:l->text] sizeWithAttributes:a].width<=l->w);}}
  Save(host,[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png",name]]);assert(fm_view_close(v));free(v);free(host);}
 // Wheel step: the caret slides in lens-move-ms (cubic ease-out) and a newer target replaces it; the name changes at once.
 {Host *host=calloc(1,sizeof *host);FMView *v=calloc(1,sizeof *v);BuildMenu(host,v,2,0,1,NULL);
  Widget *caret=W(v->caret);int x1=caret->x,y1=caret->y;assert(fm_view_update(v,2,946684800+10*3600,82,2000));assert(!strcmp(W(v->name)->text,tio_text(TT_GRID_2,zh)));
  assert(fm_view_step(v,2080));int mid=caret->x;assert(mid>x1&&mid<x1+178&&caret->y==y1);
  assert(fm_view_update(v,0,946684800+10*3600,82,2090));assert(fm_view_step(v,2110)&&caret->x<x1+178);   // retargeted from where it is, never queued
  (void)fm_view_step(v,2400);assert(!v->moving&&caret->x==92-12);assert(fm_view_close(v));free(v);free(host);}
 gSurface=TIO_SURFACE_PAGE;
}
// ---- TMG8 carousel (LensMenuCarousel.dc.html): the real FMView with rows == FM_CAROUSEL on mock widgets --------------------
// Fixture: `selected` is the compact index, `route` slides the row down for the navigation title, `line` is the focused tile's status line.
// The status line is the production tile state (tile_state.h, EN and ZH) over the board's three scenarios.
static void BuildCarousel(Host *host,FMView *v,unsigned hide,unsigned selected,bool route,const TSLive *live,const char *line){
 create(host,host);TNWidgets api={host,idle,create,create,label,place,buffer,text,visible,destroy,cliptext,color};
 assert(fm_view_open(v,&api,host,attach_ok,host));
 TTConfig config;TTVisible tiles;assert(tt_unrank(0,hide<<7,&config)&&tt_compact(&config,&tiles));assert(fm_view_rows(v,FM_CAROUSEL)&&fm_view_tiles(v,&tiles));
 assert(fm_view_update(v,(int)selected,946684800+10*3600,82,1000));
 for(unsigned i=0;i<FM_CELLS;i++){W(v->labels[i])->ambient=true;W(v->icons[i])->ramp=true;W(v->icons[i])->span=true;}W(v->caret)->ramp=true;W(v->page)->ramp=true;   // span: the 80 px icon rises from band M into T (PriorityBands: carousel line)
 for(unsigned i=0;i<FM_CELLS;i++)W(v->labels[i])->align=1;W(v->battery)->align=2;W(v->name)->align=1;W(v->line)->align=1;   // mirrors fm_show: menu_text_align centre / right / centre
 if(live){ApplyTitle(v,live,1100);(void)fm_view_step(v,1400);}assert(v->route==route&&v->title_on==route);   // a live turn: the row moves down and the title shows
 if(line){assert(fm_view_line(v,line));(void)fm_view_step(v,1500);}
 (void)fm_view_step(v,1600);assert(!v->moving&&!v->dirty);
}
static NSDictionary *BoardGeometry(NSString *html,NSString *name){   // the board's `const BIG = {...}` / `const SMALL = {...}` geometry tables
 NSRange r=[html rangeOfString:[NSString stringWithFormat:@"const %@ = {",name]];assert(r.location!=NSNotFound);
 NSString *t=[html substringFromIndex:r.location];t=[t substringToIndex:[t rangeOfString:@"};"].location];
 NSMutableArray *sizes=[NSMutableArray array];
 for(NSTextCheckingResult *m in [[NSRegularExpression regularExpressionWithPattern:@"\\[(\\d+), '#" options:0 error:nil] matchesInString:t options:0 range:NSMakeRange(0,t.length)])[sizes addObject:@([[t substringWithRange:[m rangeAtIndex:1]] intValue])];
 NSTextCheckingResult *dx=[[NSRegularExpression regularExpressionWithPattern:@"dx: \\[(\\d+), (\\d+), (\\d+), (\\d+)\\]" options:0 error:nil] firstMatchInString:t options:0 range:NSMakeRange(0,t.length)];assert(dx&&sizes.count==3);
 NSMutableDictionary *d=[@{@"sizes":sizes,@"dx":@[@([[t substringWithRange:[dx rangeAtIndex:2]] intValue]),@([[t substringWithRange:[dx rangeAtIndex:3]] intValue])]} mutableCopy];
 for(NSString *key in @[@"cy",@"caret",@"status"]){NSTextCheckingResult *m=[[NSRegularExpression regularExpressionWithPattern:[key stringByAppendingString:@": (\\d+)"] options:0 error:nil] firstMatchInString:t options:0 range:NSMakeRange(0,t.length)];assert(m);d[key]=@([[t substringWithRange:[m rangeAtIndex:1]] intValue]);}
 return d;
}
// Settled carousel against the board: five icons at the board's sizes, offsets and row, the caret, the status line and the name.
static void CompareCarouselBoard(NSString *html,FMView *v,bool route){
 NSString *s=[NSString stringWithContentsOfFile:html encoding:NSUTF8StringEncoding error:nil];assert(s);
 NSDictionary *g=BoardGeometry(s,route?@"SMALL":@"BIG");NSArray *sz=g[@"sizes"],*dx=g[@"dx"];
 Widget *ic[5];unsigned n=0;for(unsigned i=0;i<FM_CELLS;i++)if(W(v->icons[i])->shown){assert(n<5);ic[n++]=W(v->icons[i]);}assert(n==5);
 for(unsigned a=0;a<5;a++)for(unsigned b=a+1;b<5;b++)if(ic[b]->x<ic[a]->x){Widget *t=ic[a];ic[a]=ic[b];ic[b]=t;}
 const int want_dx[5]={-[dx[1] intValue],-[dx[0] intValue],0,[dx[0] intValue],[dx[1] intValue]},want_size[5]={[sz[2] intValue],[sz[1] intValue],[sz[0] intValue],[sz[1] intValue],[sz[2] intValue]};
 for(unsigned i=0;i<5;i++){assert(ic[i]->w==want_size[i]&&ic[i]->h==want_size[i]&&ic[i]->x+ic[i]->w/2==270+want_dx[i]&&ic[i]->y+ic[i]->h/2==[g[@"cy"] intValue]);}
 Widget *caret=W(v->caret),*line=W(v->line),*name=W(v->name);
 assert(caret->x==258&&caret->w==24&&caret->h==3&&caret->y==[g[@"caret"] intValue]&&line->y==[g[@"status"] intValue]&&line->font==16&&line->color==TIO_LENS_HIGH);
 assert(name->font==24&&abs(name->y-180)<=6&&name->x+name->w/2==270&&tio_band_of(TIO_SURFACE_MENU,name->y,name->h)==TIO_BAND_B);
 printf("PASS board LensMenuCarousel (%s): icon sizes, offsets, row, caret, status line and name match\n",route?"route":"no route");
}
static void Carousel(NSString *dir,NSString *board,bool zh){
 language=zh;gSurface=TIO_SURFACE_MENU;
 if(!zh)CheckStatusBoard(board);
 struct {const char *tag;unsigned hide,selected;bool route;const TSLive *live;} shots[]={
  {"-carousel",0,9,false,&kLive},                                // board default scene: Music with a live track
  {"-carousel-route",0,8,true,&kRoute},                          // Navigation with a route: row down, the next turn in band T (OptionANavTitle)
  {"-carousel-route-music",0,9,true,&kRoute},                    // the title shows whichever tile is focused; the music line stays under the icon
  {"-carousel-route-long",0,9,true,&kRouteLong},                 // a long road: cut at a word boundary
  {"-carousel-route-word",0,10,true,&kRouteWord},                // one long word: cut at a character
  {"-carousel-route-cjk",0,3,true,&kRouteCjk},                   // no spaces: cut after a character
  {"-carousel-route-nameless",0,12,true,&kRouteRound},           // no road name: the distance alone
  {"-carousel-pomodoro",0,10,false,&kLive},                      // the timer
  {"-carousel-idle",0,9,false,&kIdle},                           // nothing running: name only
  {"-carousel-stock",0,3,false,&kLive},                          // a stock app: name only whatever runs
  {"-carousel-offline",0,8,false,&kOffline},                     // phone not connected (navigation)
  {"-carousel-offline-music",0,9,false,&kOffline},
  {"-carousel-offline-pomodoro",0,10,false,&kOffline},           // the timer is local: it keeps its line
  {"-carousel-first",0,0,false,NULL},                            // wraps: the last tiles sit to the left of the first
  {"-carousel-last",0,12,false,NULL},
  {"-carousel-8",31,4,false,NULL}};                              // eight tiles: the neighbours at +-3 are distinct from +-2
 for(unsigned i=0;i<sizeof shots/sizeof *shots;i++){
  Host *host=calloc(1,sizeof *host);assert(host);FMView *v=calloc(1,sizeof *v);assert(v);const typeof(shots[0]) *sh=&shots[i];
  TTConfig config;TTVisible tiles;assert(tt_unrank(0,sh->hide<<7,&config)&&tt_compact(&config,&tiles));
  TSState state;memset(&state,0,sizeof state);if(sh->live)ts_state(tiles.ids[sh->selected],sh->live,language,&state);
  const char *lineText=state.line[0]?state.line:NULL;                                                                       // what the glasses would write for the focused tile
  BuildCarousel(host,v,sh->hide,sh->selected,sh->route,sh->live,lineText);char name[48];snprintf(name,sizeof name,"menu%s-%s",sh->tag,zh?"zh":"en");Gate(host,name,true);
  CheckTitle(host,v,sh->live?sh->live:&kIdle);if(!zh&&!strcmp(sh->tag,"-carousel-route"))CheckTitleBoard([[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"OptionANavTitle.dc.html"],v);
  Widget *status=W(v->status),*battery=W(v->battery),*nm=W(v->name),*caret=W(v->caret),*line=W(v->line);
  assert(!strcmp(status->text,"10:00")&&!strcmp(battery->text,"82%")&&status->color==TIO_LENS_MID&&battery->color==TIO_LENS_MID&&status->font==TIO_FONT_LABEL);   // clock and battery in band T
  assert(tio_band_of(TIO_SURFACE_MENU,status->y,status->h)==TIO_BAND_T&&tio_band_of(TIO_SURFACE_MENU,battery->y,battery->h)==TIO_BAND_T);
  assert(nm->font==TIO_FONT_TITLE&&nm->color==0&&strlen(nm->text)>0&&!W(v->page)->shown);                                  // the name once, in B, full; no page dots
  assert(line->shown==(lineText!=NULL)&&(!lineText||(!strcmp(line->text,lineText)&&line->font==TIO_FONT_MIN&&line->color==TIO_LENS_HIGH&&tio_band_of(TIO_SURFACE_MENU,line->y,line->h)==TIO_BAND_M)));
  if(lineText)assert(utf8_ok(lineText)&&tm_width(lineText,strlen(lineText),TIO_FONT_MIN)<=TIO_CORE_W);                      // one line inside the 460 px core
  for(unsigned k=0;k<FM_CELLS;k++){assert(!W(v->labels[k])->shown&&!W(v->dots[k])->shown);}                                // ambient names and state dots are grid features
  // Icons: five, never above 80 px, in the glyph zone (side insets to the bottom of band M), none touching the clock, battery, status line or caret; focused full, the rest dimmer.
  unsigned shown=0;uint8_t peaks[FM_CELLS];Widget *centre=NULL;
  for(unsigned k=0;k<FM_CELLS;k++){Widget *ic=W(v->icons[k]);if(!ic->shown)continue;shown++;assert(ic->w==ic->h&&ic->w<=80&&ic->x>=TIO_INSET_X&&ic->x+ic->w<=TIO_PAGE_W-TIO_INSET_X&&ic->y>=TIO_RESERVE_TOP&&ic->y+ic->h<=TIO_MENU_M1);
   uint8_t peak=0;for(int q=0;q<ic->w*ic->h;q++)if(ic->pixels[q]>peak)peak=ic->pixels[q];peaks[k]=peak;if(ic->x+ic->w/2==270)centre=ic;
   for(Widget *o=host->w+1;o<host->w+host->count;o++){if(!o->shown||o==ic||o->kind!=KText||!o->text||!*o->text)continue;   // the drawn text, not its box (the clock box is 100 px, its ink about 45)
    int ink=(int)ceil([[NSString stringWithUTF8String:o->text] sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:o->font]}].width);if(ink>o->w)ink=o->w;
    Widget t=*o;t.w=ink;t.x=o->align==1?o->x+(o->w-ink)/2:o->align==2?o->x+o->w-ink:o->x;assert(!overlap(ic,&t));}
   assert(!overlap(ic,caret));
   if(ic->x+ic->w/2==270)assert(peak>=250);else if(abs(ic->x+ic->w/2-270)<=124)assert(peak<=(TIO_LENS_MID>>8&255u));else assert(peak<=(TIO_LENS_TRACK>>8&255u));}
  assert(shown==5&&centre&&caret->x+12==centre->x+centre->w/2&&caret->y>=centre->y+centre->h+3);
  if(!zh)CompareCarouselBoard(board,v,sh->route);
  Save(host,[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png",name]]);assert(fm_view_close(v));free(v);free(host);(void)tiles;(void)peaks;}
 gSurface=TIO_SURFACE_PAGE;
}
int main(int argc,char **argv){@autoreleasepool{assert(argc>=3);NSString *dir=[NSString stringWithUTF8String:argv[1]];assert([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]);
 NSString *board=[NSString stringWithUTF8String:argv[2]];SelfTest();AppPages(dir,board);AppRuntime(dir,board,argc,argv);Shelf(dir);NSString *navBoard=[[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"LensNav.dc.html"];Nav(dir,navBoard,false,false);Nav(dir,navBoard,true,false);Nav(dir,navBoard,false,true);Nav(dir,navBoard,true,true);NSString *musicBoard=[[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"LensMusic.dc.html"];Lyrics(dir,musicBoard,false);Lyrics(dir,musicBoard,true);NSString *focusBoard=[[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"LensFocus.dc.html"];Focus(dir,focusBoard,false);Focus(dir,focusBoard,true);NSString *menuBoard=[[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"LensMenu.dc.html"];Menu(dir,menuBoard,false);Menu(dir,menuBoard,true);NSString *carouselBoard=[[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"LensMenuCarousel.dc.html"];NSString *gridBoard=[[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"LensMenuGrid2.dc.html"];CheckStatusBoard(gridBoard);Carousel(dir,carouselBoard,false);Carousel(dir,carouselBoard,true);
 puts("PASS tmg7 layout gate and previews (EN/ZH); preview typography uses macOS surrogate fonts, app, nav, music, focus and menu are re-laid");}return 0;}
