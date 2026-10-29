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
#include "../src/common-v1/tio_text.h"
#include "../src/common-v1/tio_ui.h"
#include "../src/common-v1/tio_hint.h"
#include "../src/common-v1/tio_caret.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
enum {KText,KPixels,KRect};
typedef struct {int x,y,w,h;unsigned font;bool shown,clip,span,fading,art;const char *text;const uint8_t *pixels;int kind,band;uint32_t color;} Widget;
typedef struct {Widget w[24];unsigned count;bool busy;} Host;
enum {VReserved=1,VBand=2,VFont=4,VPanel=8,VCore=16,VColor=32,VOverlap=64,VCanvas=128,VBox=256};
static unsigned language;
unsigned tio_lang(void){return language;}
static bool idle(void *p){return !((Host *)p)->busy;}
static void *create(void *p,void *parent){assert(parent);Host *h=p;assert(h->count<24);Widget *w=&h->w[h->count++];w->shown=true;w->band=-1;return w;}
static void *label(void *p,void *parent,unsigned font){Widget *w=create(p,parent);w->font=font;return w;}
static void place(void *p,void *o,int x,int y,int w,int h){(void)p;assert(x>=0&&y>=0&&x+w<=540&&y+h<=180);Widget *v=o;v->x=x;v->y=y;v->w=w;v->h=h;}
static void buffer(void *p,void *o,const uint8_t *pixels,unsigned w,unsigned h){(void)p;Widget *v=o;assert(v->w==(int)w&&v->h==(int)h);v->pixels=pixels;v->kind=KPixels;}
static void text(void *p,void *o,const char *s){(void)p;((Widget *)o)->text=s;}
static void visible(void *p,void *o,bool show){(void)p;((Widget *)o)->shown=show;}
static void destroy(void *p,void *o){(void)p;((Widget *)o)->shown=false;}
static void cliptext(void *p,void *o){(void)p;((Widget *)o)->clip=true;}
static NSColor *Ink(uint32_t c){return [NSColor colorWithRed:0 green:((c>>8)&255)/255.0 blue:0 alpha:1];}
static void Save(Host *host,NSString *path){
 NSImage *im=[[NSImage alloc]initWithSize:NSMakeSize(540,180)];[im lockFocusFlipped:YES];[NSColor.blackColor setFill];NSRectFill(NSMakeRect(0,0,540,180));
 for(unsigned i=1;i<host->count;i++){Widget *w=&host->w[i];if(!w->shown)continue;NSRect rect=NSMakeRect(w->x,w->y,w->w,w->h);
  [NSGraphicsContext saveGraphicsState];NSRectClip(rect);
  if(w->kind==KRect){[Ink(w->color) setFill];[[NSBezierPath bezierPathWithRoundedRect:rect xRadius:TIO_RADIUS_XS yRadius:TIO_RADIUS_XS] fill];}
  if(w->pixels){NSBitmapImageRep *b=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:w->w pixelsHigh:w->h bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w->w*3 bitsPerPixel:24];for(int y=0;y<w->h;y++)for(int x=0;x<w->w;x++){uint8_t *d=b.bitmapData+y*b.bytesPerRow+x*3;d[0]=d[2]=0;d[1]=w->pixels[y*w->w+x];}NSImage *tile=[[NSImage alloc]initWithSize:NSMakeSize(w->w,w->h)];[tile addRepresentation:b];[tile drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:nil];}
  if(w->text&&*w->text){NSString *s=[NSString stringWithUTF8String:w->text];assert(s);NSMutableParagraphStyle *ps=[NSMutableParagraphStyle new];ps.lineBreakMode=NSLineBreakByClipping;
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
 unsigned mask=0;const TIOSurface s=TIO_SURFACE_PAGE;
 for(unsigned i=1;i<host->count;i++){Widget *w=&host->w[i];if(!w->shown)continue;
  bool text=textual(w),pix=w->kind==KPixels,rect=w->kind==KRect;if(!text&&!pix&&!rect)continue;
  TIORect r={w->x,w->y,w->w,w->h};unsigned v=0;
  if(r.x<0||r.y<0||r.x+r.w>TIO_PAGE_W||r.y+r.h>TIO_PAGE_H)v|=VCanvas;
  if(tio_rect_in_reserved(s,r))v|=VReserved;                                   // nothing drawn in y 0-12 or 172-180
  int band=w->band>=0?w->band:tio_band_of(s,r.y,r.h);
  if(!w->span&&(band<TIO_BAND_T||band>TIO_BAND_B||!tio_rect_in_band(s,(TIOBand)band,r)))v|=VBand;   // inside its band
  if(text){
   if(w->font<TIO_FONT_MIN||!tio_font_native(w->font))v|=VFont;                // 16 px floor, stock sizes only
   if(w->h<(int)w->font+TIO_TEXT_PAD)v|=VBox;                                  // box at least font + 4
   if(!tio_rect_in_core(r))v|=VCore;                                           // primary text inside lens-core-x
   uint32_t c=w->color?w->color:TIO_LENS_FULL;
   if(c!=TIO_LENS_FULL&&c!=TIO_LENS_HIGH&&c!=TIO_LENS_MID&&!(w->fading&&c<TIO_LENS_HIGH))v|=VColor;   // track is never text; only a fading hint may sit between steps
   if(c==TIO_LENS_MID&&w->font<TIO_FONT_LABEL)v|=VColor;                       // mid only at 18 px or larger
  }
  if(pix&&w->art){for(int k=0;k<r.w*r.h;k++)if(w->pixels[k]>TM_ART_LEVEL){v|=VColor;break;}}   // artwork stays under lens-mid
  if(pix&&!w->span&&(r.x<TIO_INSET_X||r.x+r.w>TIO_PAGE_W-TIO_INSET_X))v|=VCore;   // glyphs may use the side insets, not the edge
  if(rect&&!(r.h<=TIO_TRACK_H&&(w->color==TIO_LENS_FULL||w->color==TIO_LENS_TRACK)))v|=VPanel;   // only carets and tracks are filled
  bool track=pix&&r.h<=TIO_TRACK_H;if(track){for(int k=0;k<r.w*r.h;k++)if(w->pixels[k]!=TF_TRACK_LEVEL&&w->pixels[k]!=TF_FILL_LEVEL){v|=VColor;break;}}   // progress track: only track and full levels
  if(pix&&!w->art&&!track&&r.w*r.h>=32*32){unsigned lit=0;for(int k=0;k<r.w*r.h;k++)lit+=w->pixels[k]>16;if(lit*2>(unsigned)(r.w*r.h))v|=VPanel;}  // no solid canvases
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

// ---- Navigation (LensNav, tmg7(2)) ---------------
static void Put16(uint8_t *p,int n){p[0]=n;p[1]=n>>8;}
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
 Widget *map=W(v->map);assert(map->y==by&&map->y+map->h==TIO_PAGE_B1&&map->x+map->w==bx+148&&map->x<=bx);
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
 TIORect a=tm_art_rect(),t=tm_track_rect(),n=tm_next_rect(),c=tm_cur_rect();
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
  unsigned lines=1;for(const char *p=host->w[4].text;*p;p++)lines+=*p=='\n';assert(lines<=2&&tm_width(host->w[3].text,strlen(host->w[3].text),TM_NEXT_FONT)<=TIO_CORE_W);
  // The current-lyric label is the lens core wide, and no wrapped row is estimated wider than it.
  assert(host->w[4].w==TIO_CORE_W&&host->w[4].x==TIO_CORE_X0&&host->w[3].w==TIO_CORE_W);
  {const char *row=host->w[4].text;while(*row){const char *e=strchr(row,'\n');size_t n=e?(size_t)(e-row):strlen(row);assert(tm_width(row,n,TM_CUR_FONT)<=TIO_CORE_W);row+=n+(e?1:0);}}
  Save(host,[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%s.png",name]]);free(host);}
 // Long lines: two-line cap with an ellipsis, rows within the core, label still TIO_CORE_W wide.
 for(unsigned z=0;z<2;z++){language=z;Host *host=calloc(1,sizeof *host);assert(host);BuildMusic(host,z,4000,&hint,tile,true);char name[48];snprintf(name,sizeof name,"lyrics-long-%s",z?"zh":"en");Gate(host,name,true);
  assert(host->w[4].w==TIO_CORE_W);unsigned lines=1;for(const char *p=host->w[4].text;*p;p++)lines+=*p=='\n';assert(lines==2&&strstr(host->w[4].text,"\xe2\x80\xa6"));
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
int main(int argc,char **argv){@autoreleasepool{assert(argc==3);NSString *dir=[NSString stringWithUTF8String:argv[1]];assert([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]);
 NSString *board=[NSString stringWithUTF8String:argv[2]];SelfTest();AppPages(dir,board);NSString *navBoard=[[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"LensNav.dc.html"];Nav(dir,navBoard,false,false);Nav(dir,navBoard,true,false);Nav(dir,navBoard,false,true);Nav(dir,navBoard,true,true);NSString *musicBoard=[[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"LensMusic.dc.html"];Lyrics(dir,musicBoard,false);Lyrics(dir,musicBoard,true);NSString *focusBoard=[[board stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"LensFocus.dc.html"];Focus(dir,focusBoard,false);Focus(dir,focusBoard,true);
 puts("PASS tmg7 layout gate and previews (EN/ZH); preview typography uses macOS surrogate fonts, app, nav, music and focus are re-laid");}return 0;}
