/* TMG7 design tokens, transient hint and focus caret (src/common-v1/tio_ui.h, tio_hint.h, tio_caret.h).
 * Built by tmg7_host_test.py at the default 24.8 px/deg and at other ppd values. */
#include "common-v1/tio_ui.h"
#include "common-v1/tio_hint.h"
#include "common-v1/tio_caret.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define EQ(a,b) do{if((a)!=(b)){printf("FAIL %s=%d expected %d (line %d)\n",#a,(int)(a),(int)(b),__LINE__);return 1;}}while(0)
static int dump(void){
 printf("lens-reserve-top=%d\nlens-band-t=%d,%d\nlens-band-m=%d,%d\nlens-band-b=%d,%d\nlens-reserve-bottom=%d\n",TIO_RESERVE_TOP,TIO_PAGE_T0,TIO_PAGE_T1,TIO_PAGE_T1,TIO_PAGE_M1,TIO_PAGE_M1,TIO_PAGE_B1,TIO_PAGE_H-TIO_PAGE_B1);
 printf("lens-inset-x=%d\nlens-core-x=%d,%d\nlens-caret=%d,%d\nlens-hint-ms=%u\nlens-move-ms=%u\n",TIO_INSET_X,TIO_CORE_X0,TIO_CORE_X1,TIO_CARET_W,TIO_CARET_H,TIO_HINT_MS,TIO_MOVE_MS);
 printf("lens-full=%06x\nlens-high=%06x\nlens-mid=%06x\nlens-track=%06x\n",TIO_LENS_FULL,TIO_LENS_HIGH,TIO_LENS_MID,TIO_LENS_TRACK);
 printf("lens-hero=%d\nlens-primary=%d\nlens-title=%d\nlens-body=%d\nlens-label=%d\nlens-min=%d\n",TIO_FONT_HERO,TIO_FONT_PRIMARY,TIO_FONT_TITLE,TIO_FONT_BODY,TIO_FONT_LABEL,TIO_FONT_MIN);
 printf("lens-page-h=%d\nlens-menu-h=%d\nlens-page-w=%d\nradius-xs=%d\n",TIO_PAGE_H,TIO_MENU_H,TIO_PAGE_W,TIO_RADIUS_XS);
 return 0;
}
static int geometry(void){
 for(int s=0;s<2;s++){TIOSurface surf=(TIOSurface)s;int h=tio_surface_h(surf),prev=0;
  for(int b=TIO_RESERVED_TOP;b<=TIO_RESERVED_BOTTOM;b++){TIOSpan p=tio_band(surf,(TIOBand)b);EQ(p.y0,prev);assert(p.y1>=p.y0);prev=p.y1;}
  EQ(prev,h);
  TIOSpan t=tio_band(surf,TIO_BAND_T),m=tio_band(surf,TIO_BAND_M),b=tio_band(surf,TIO_BAND_B);
  assert(t.y1>t.y0&&m.y1>m.y0&&b.y1>b.y0);
  /* Priority rises toward the bottom and the reserved rows are never part of a band. */
  assert(TIO_RESERVE_TOP>0&&tio_band(surf,TIO_RESERVED_BOTTOM).y1>tio_band(surf,TIO_RESERVED_BOTTOM).y0);
  assert(!tio_rect_in_band(surf,TIO_BAND_T,(TIORect){TIO_CORE_X0,0,100,TIO_LINE(TIO_FONT_LABEL)}));
  assert(tio_rect_in_reserved(surf,(TIORect){TIO_CORE_X0,0,100,20}));
  assert(tio_rect_in_reserved(surf,(TIORect){TIO_CORE_X0,b.y1-4,100,20}));
  assert(!tio_rect_in_reserved(surf,(TIORect){TIO_CORE_X0,t.y0,100,20}));
 }
 assert(TIO_CORE_X0>=TIO_INSET_X&&TIO_CORE_X1<=TIO_PAGE_W&&TIO_CORE_X0<TIO_CORE_X1);
 assert(TIO_FONT_MIN>=16);
 const int fonts[]={TIO_FONT_HERO,TIO_FONT_PRIMARY,TIO_FONT_TITLE,TIO_FONT_BODY,TIO_FONT_LABEL,TIO_FONT_MIN};
 for(unsigned i=0;i<6;i++){assert(tio_font_native((unsigned)fonts[i]));assert(i==0||fonts[i]<=fonts[i-1]);}
 assert(!tio_font_native(14)&&!tio_font_tap(14)&&!tio_font_tap(28));
 assert(TIO_CARET_W>=TIO_GLYPH_MIN&&TIO_CARET_H>0&&TIO_CARET_H<=TIO_TRACK_H);
 return 0;
}
#if TIO_PPD_X10==248
static int exact(void){
 EQ(TIO_RESERVE_BOTTOM,8);EQ(TIO_PAGE_T0,12);EQ(TIO_PAGE_T1,56);EQ(TIO_PAGE_M1,112);EQ(TIO_PAGE_B1,172);EQ(TIO_PAGE_H,180);
 EQ(TIO_MENU_T0,12);EQ(TIO_MENU_T1,56);EQ(TIO_MENU_M1,172);EQ(TIO_MENU_B1,212);EQ(TIO_MENU_H,220);
 EQ(TIO_CORE_X0,40);EQ(TIO_CORE_X1,500);EQ(TIO_CORE_W,460);EQ(TIO_INSET_X,16);
 EQ(TIO_CARET_W,24);EQ(TIO_CARET_H,3);EQ(TIO_CARET_GAP,4);EQ(TIO_RADIUS_XS,2);EQ(TIO_TRACK_H,4);EQ(TIO_GLYPH_MIN,24);
 EQ(TIO_FONT_HERO,48);EQ(TIO_FONT_PRIMARY,32);EQ(TIO_FONT_TITLE,24);EQ(TIO_FONT_BODY,20);EQ(TIO_FONT_LABEL,18);EQ(TIO_FONT_MIN,16);
 EQ(TIO_LINE(TIO_FONT_HERO),52);EQ(TIO_LINE(TIO_FONT_PRIMARY),36);EQ(TIO_LINE(TIO_FONT_LABEL),22);
 EQ(TIO_LENS_FULL,0x00ff00);EQ(TIO_LENS_HIGH,0x00b000);EQ(TIO_LENS_MID,0x007700);EQ(TIO_LENS_TRACK,0x003800);
 EQ(TIO_HINT_MS,3000);EQ(TIO_MOVE_MS,160);
 TIORect hint=tio_hint_rect(TIO_SURFACE_PAGE);EQ(hint.x,40);EQ(hint.y,23);EQ(hint.w,460);EQ(hint.h,22);
 assert(tio_rect_in_band(TIO_SURFACE_PAGE,TIO_BAND_T,hint)&&tio_rect_in_band(TIO_SURFACE_MENU,TIO_BAND_T,tio_hint_rect(TIO_SURFACE_MENU)));
 assert(tio_rect_in_core(hint)&&!tio_rect_in_reserved(TIO_SURFACE_PAGE,hint));
 EQ(tio_ui_scale(TIO_LENS_HIGH,255),0x00b000);EQ(tio_ui_scale(TIO_LENS_HIGH,0),0);
 return 0;
}
#endif
static int hint(void){
 TIOHint h;tio_hint_init(&h);uint32_t c=0;
 assert(!tio_hint_visible(&h,0)&&tio_hint_ambient(&h,0)&&!tio_hint_poll(&h,10,&c));
 tio_hint_enter(&h,1000);
 assert(tio_hint_visible(&h,1000)&&!tio_hint_ambient(&h,1000)&&tio_hint_poll(&h,1000,&c)&&c==TIO_LENS_HIGH&&!tio_hint_poll(&h,1001,&c));
 EQ(tio_hint_alpha(&h,1000+2699),255);
 unsigned last=255,changes=0;uint32_t t;
 for(t=1000+2700;t<1000+3000;t++){unsigned a=tio_hint_alpha(&h,t);assert(a<=last&&a>0);if(a!=last)changes++;last=a;}
 assert(changes==7&&last==255*1/8);
 EQ(tio_hint_alpha(&h,1000+2999)>0,1);EQ(tio_hint_alpha(&h,1000+3000),0);EQ(tio_hint_visible(&h,1000+3000),0);EQ(tio_hint_visible(&h,1000+60000),0);
 /* The label is touched only when its color changes: show + 7 fade steps + hide. */
 TIOHint p;tio_hint_init(&p);tio_hint_enter(&p,0);unsigned polls=0;for(t=0;t<4000;t++)if(tio_hint_poll(&p,t,&c))polls++;
 EQ(polls,9);EQ(p.color,0);assert(tio_hint_ambient(&p,4000));
 /* Wheel input re-shows and restarts the three seconds. */
 tio_hint_input(&h,5000);assert(tio_hint_visible(&h,5000)&&tio_hint_alpha(&h,5000+2600)==255&&!tio_hint_visible(&h,8000));
 tio_hint_input(&h,7000);assert(tio_hint_visible(&h,9999)&&!tio_hint_visible(&h,10000));
 /* Entry-only (seen three times, phone-side counter): input does not re-show, entry does. */
 TIOHint e;tio_hint_init(&e);e.entry_only=true;tio_hint_input(&e,100);assert(!tio_hint_visible(&e,100));
 tio_hint_enter(&e,200);assert(tio_hint_visible(&e,200));tio_hint_input(&e,2900);assert(!tio_hint_visible(&e,3200));
 /* Reduce Motion: no fade, full intensity until it hides. */
 TIOHint r;tio_hint_init(&r);r.reduce_motion=true;tio_hint_enter(&r,0);EQ(tio_hint_alpha(&r,2999),255);EQ(tio_hint_alpha(&r,3000),0);
 /* 32-bit millisecond wrap. */
 TIOHint w;tio_hint_init(&w);tio_hint_enter(&w,0xfffffe00u);assert(tio_hint_visible(&w,0xfffffe00u+2000)&&tio_hint_visible(&w,100)&&!tio_hint_visible(&w,0xfffffe00u+3000));
 return 0;
}
static int caret(void){
 TIOCaret c;tio_caret_init(&c);
 int x,y;
 /* Representative app row: 20 px items centered in band M (y 76 at 24.8, LensApp board), caret under the focused item. */
 TIOSpan band_m=tio_band(TIO_SURFACE_PAGE,TIO_BAND_M);
 int row=band_m.y0+(band_m.y1-band_m.y0-TIO_LINE(TIO_FONT_BODY)-TIO_CARET_GAP-TIO_CARET_H)/2;
 int top=tio_caret_top(row,TIO_FONT_BODY);
 TIORect r;
 tio_caret_to(&c,tio_caret_left(40),top,1000,false);r=tio_caret_rect(&c,1000);
 EQ(r.w,TIO_CARET_W);EQ(r.h,TIO_CARET_H);EQ(r.x,40);EQ(r.y,top);
 assert(tio_rect_in_band(TIO_SURFACE_PAGE,TIO_BAND_M,r)&&!tio_rect_in_reserved(TIO_SURFACE_PAGE,r));
 tio_caret_to(&c,200,top,2000,false);
 r=tio_caret_rect(&c,2000);EQ(r.x,40);
 r=tio_caret_rect(&c,2000+80);assert(r.x>40+160/2&&r.x<200);   /* ease-out: past halfway at half time */
 r=tio_caret_rect(&c,2000+159);assert(r.x<=200&&r.x>=199);
 r=tio_caret_rect(&c,2000+160);EQ(r.x,200);assert(!c.moving);
 /* Retarget mid-motion replaces it from the current position (never queues). */
 tio_caret_to(&c,300,top,3000,false);tio_caret_pos(&c,3080,&x,&y);int mid=x;assert(mid>200&&mid<300);
 tio_caret_to(&c,40,top,3080,false);tio_caret_pos(&c,3080,&x,&y);EQ(x,mid);r=tio_caret_rect(&c,3080+160);EQ(r.x,40);
 /* Page change is faster; Reduce Motion snaps. */
 tio_caret_to(&c,400,top,4000,true);r=tio_caret_rect(&c,4000+120);EQ(r.x,400);
 c.reduce_motion=true;tio_caret_to(&c,60,top,5000,false);r=tio_caret_rect(&c,5000);EQ(r.x,60);
 /* Wheel focus clamps at both ends and never exceeds five items. */
 EQ(tio_focus_step(3,0,-1),0);EQ(tio_focus_step(3,0,1),1);EQ(tio_focus_step(3,2,1),2);EQ(tio_focus_step(3,2,-1),1);EQ(tio_focus_step(9,4,1),4);EQ(tio_focus_step(0,0,1),0);
 EQ(tio_focus_color(true),TIO_LENS_FULL);EQ(tio_focus_color(false),TIO_LENS_MID);
 /* Menu: caret centered under a 40 px icon stays inside band M, label in band B. */
 TIOSpan menu_m=tio_band(TIO_SURFACE_MENU,TIO_BAND_M);
 TIORect mc={tio_caret_centered(270),menu_m.y0+(menu_m.y1-menu_m.y0)/4,TIO_CARET_W,TIO_CARET_H};
 assert(tio_rect_in_band(TIO_SURFACE_MENU,TIO_BAND_M,mc)&&mc.x==270-TIO_CARET_W/2);
 return 0;
}
int main(int argc,char **argv){
 if(argc>1&&!strcmp(argv[1],"--dump"))return dump();
 if(geometry())return 1;
#if TIO_PPD_X10==248
 if(exact())return 1;
#endif
 if(hint())return 1;
 if(caret())return 1;
 printf("PASS tmg7 tokens (ppd %d.%d), hint (3000 ms, fade inside), caret (24x3, 160 ms, clamped focus)\n",TIO_PPD_X10/10,TIO_PPD_X10%10);
 return 0;
}
