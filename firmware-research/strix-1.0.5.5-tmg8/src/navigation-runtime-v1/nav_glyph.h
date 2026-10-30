#ifndef TURBO_NAV_GLYPH_H
#define TURBO_NAV_GLYPH_H
#include "nav_visual.h"
/* The turn glyph polylines, authored in a 96x84 box centred at (56,60). The navigation page (nav_view.c, 64x56 canvas, 7 px stroke) and the menu's
 * navigation title (focus-v1/nav_title.h, 18x18 canvas, 2 px stroke) draw the same set. Header-only so host tests need no extra object. */
static const TNXY straight[]={{48,84},{48,12},{20,40},{48,12},{76,40}};
static const TNXY right[]={{18,84},{18,36},{76,36},{52,12},{76,36},{52,60}};
static const TNXY slight[]={{22,84},{22,55},{72,15},{36,15},{72,15},{72,50}};
static const TNXY sharp[]={{18,84},{18,16},{74,66},{38,66},{74,66},{74,30}};
static const TNXY uturn[]={{18,84},{18,30},{30,16},{58,16},{72,30},{72,78},{52,58},{72,78},{88,58}};
static const TNXY roundabout[]={{48,84},{48,65},{24,48},{24,30},{44,15},{64,30},{64,48},{48,65},{48,15},{32,30},{48,15},{64,30}};
static const TNXY arrive[]={{22,84},{22,12},{76,12},{76,50},{22,50}};
static const TNXY unknown[]={{28,25},{38,15},{58,15},{70,26},{70,38},{48,54},{48,66},{48,75},{48,82}};
/* Polyline of `id` (offset to the box at (8,12), mirrored for the left turns) in out[16]; returns the point count (at most 12).
 * An id out of range gets the "unknown" mark. */
static inline unsigned tn_glyph(unsigned id,TNXY out[16]){
 const TNXY *icon=unknown;size_t n=sizeof unknown/sizeof *unknown;bool flip=false;
 switch(id){
 #define GLYPH(name) icon=name;n=sizeof name/sizeof *name;break
 case TN_STRAIGHT:GLYPH(straight);
 case TN_LEFT:flip=true; /* fall through */
 case TN_RIGHT:GLYPH(right);
 case TN_SLIGHT_LEFT:flip=true; /* fall through */
 case TN_SLIGHT_RIGHT:GLYPH(slight);
 case TN_SHARP_LEFT:flip=true; /* fall through */
 case TN_SHARP_RIGHT:GLYPH(sharp);
 case TN_UTURN:GLYPH(uturn);
 case TN_ROUNDABOUT:GLYPH(roundabout);
 case TN_ARRIVE:GLYPH(arrive);
 default:break;
 #undef GLYPH
 }
 for(unsigned i=0;i<n;i++)out[i]=(TNXY){8+(flip?96-icon[i].x:icon[i].x),12+icon[i].y};
 return (unsigned)n;
}
#endif
