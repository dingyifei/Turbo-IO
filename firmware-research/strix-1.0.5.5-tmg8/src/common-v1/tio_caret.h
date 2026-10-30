#ifndef TIO_CARET_HEADER
#define TIO_CARET_HEADER
/* FocusCaret (docs/design-system/components/FocusCaret): the focused item is drawn in lens-full
 * (unfocused lens-mid) with a 24x3 lens-full bar, radius 2, TIO_CARET_GAP (4 px) under its baseline.
 * No outlines or filled shapes. Wheel steps move focus by one and clamp at the ends. The caret slides
 * in TIO_MOVE_MS (cubic ease-out; TIO_PAGE_MOVE_MS on a page change) and snaps under Reduce Motion
 * (mirrored from the phone). A new target replaces a motion in flight from the current position. */
#include "tio_ui.h"
typedef struct {int x0,y0,x1,y1;uint32_t started;unsigned duration;bool placed,moving,reduce_motion;} TIOCaret;
static inline void tio_caret_init(TIOCaret *c){c->x0=c->y0=c->x1=c->y1=0;c->started=0;c->duration=TIO_MOVE_MS;c->placed=c->moving=c->reduce_motion=false;}
/* Cubic ease-out, 0..256, as the menu focus motion (focus_menu.c). */
static inline unsigned tio_ease(uint32_t elapsed,unsigned duration){
 if(elapsed>=duration)return 256;unsigned t=(unsigned)(elapsed*256u/duration),r=256u-t;return 256u-r*r*r/65536u;
}
/* Baseline of a text box (stock vector font box = font+4, ascent about font+1) and the caret top. */
static inline int tio_text_baseline(int box_y,unsigned font){return box_y+(int)font+1;}
static inline int tio_caret_top(int box_y,unsigned font){return tio_text_baseline(box_y,font)+TIO_CARET_GAP;}
/* Caret left edge: under the item's left edge (text) or centered under its icon. */
static inline int tio_caret_left(int item_x){return item_x;}
static inline int tio_caret_centered(int item_cx){return item_cx-TIO_CARET_W/2;}
static inline void tio_caret_pos(TIOCaret *c,uint32_t now,int *x,int *y){
 unsigned q=c->moving?tio_ease(now-c->started,c->duration):256u;
 if(q==256u){c->moving=false;c->x0=c->x1;c->y0=c->y1;}
 *x=c->x0+(c->x1-c->x0)*(int)q/256;*y=c->y0+(c->y1-c->y0)*(int)q/256;
}
static inline void tio_caret_to(TIOCaret *c,int x,int y,uint32_t now,bool page_change){
 if(!c->placed||c->reduce_motion){c->x0=c->x1=x;c->y0=c->y1=y;c->moving=false;c->placed=true;return;}
 if(c->x1==x&&c->y1==y)return; /* same target: keep the motion in flight */
 int cx,cy;tio_caret_pos(c,now,&cx,&cy);
 c->x0=cx;c->y0=cy;c->x1=x;c->y1=y;c->started=now;c->duration=page_change?TIO_PAGE_MOVE_MS:TIO_MOVE_MS;c->moving=c->x0!=x||c->y0!=y;
}
static inline TIORect tio_caret_rect(TIOCaret *c,uint32_t now){
 int x,y;tio_caret_pos(c,now,&x,&y);return (TIORect){x,y,TIO_CARET_W,TIO_CARET_H};
}
/* Wheel: dir>0 next, dir<0 previous, clamped (no wrap). count is capped at TIO_FOCUS_MAX. */
static inline unsigned tio_focus_step(unsigned count,unsigned index,int dir){
 if(count>TIO_FOCUS_MAX)count=TIO_FOCUS_MAX;if(!count)return 0;if(index>=count)index=count-1;
 if(dir>0&&index+1<count)return index+1;if(dir<0&&index>0)return index-1;return index;
}
static inline uint32_t tio_focus_color(bool focused){return focused?TIO_LENS_FULL:TIO_LENS_MID;}
#endif
