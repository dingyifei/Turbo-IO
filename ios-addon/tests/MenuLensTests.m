#import "MenuLens.h"
#include <assert.h>
static BOOL Near(CGFloat a,CGFloat b){return fabs(a-b)<0.01;}
static NSUInteger Count(TIOMenuLensLayout layout,NSUInteger visibleCount,NSUInteger focus,TIOMenuLensSlot *out){
 uint8_t visible[13];for(NSUInteger i=0;i<13;i++)visible[i]=(uint8_t)i;
 return TIOMenuLensSlots(layout,visible,visibleCount,focus,out);
}
int main(void){@autoreleasepool{
 /* Every icon outline parses and stays on the 48 x 48 grid with room for the 2.6 stroke. */
 NSMutableSet *names=[NSMutableSet set];
 for(NSUInteger t=0;t<TIOMenuLensIconCount;t++){
  CGPathRef path=TIOMenuLensIconPath(t);assert(path&&!CGPathIsEmpty(path)&&TIOMenuLensIconPath(t)==path);
  CGRect box=CGPathGetBoundingBox(path);assert(box.origin.x>=5&&box.origin.y>=4&&CGRectGetMaxX(box)<=43&&CGRectGetMaxY(box)<=43.01&&box.size.width>=20&&box.size.height>=20);
  assert(TIOMenuLensIconName(t).length);[names addObject:TIOMenuLensIconName(t)];
 }
 assert(names.count==13&&!TIOMenuLensIconPath(13)&&!TIOMenuLensIconName(13));
 assert([TIOMenuLensIconName(8)isEqual:@"navigation"]&&[TIOMenuLensIconName(9)isEqual:@"music"]&&[TIOMenuLensIconName(12)isEqual:@"camera"]);
 /* The parser: relative and absolute commands, arcs with touching flags, and refusal of malformed data. */
 CGPathRef p=TIOMenuLensCreatePath(@"M10 10h20v20H10z");assert(p&&CGRectEqualToRect(CGPathGetBoundingBox(p),CGRectMake(10,10,20,20)));CGPathRelease(p);
 p=TIOMenuLensCreatePath(@"M10 20a10 10 0 0 1 20 0");CGRect arc=CGPathGetBoundingBox(p);assert(p&&Near(arc.origin.x,10)&&Near(CGRectGetMaxX(arc),30)&&Near(arc.origin.y,10)&&Near(CGRectGetMaxY(arc),20));CGPathRelease(p);
 p=TIOMenuLensCreatePath(@"M10 20a10 10 0 0120 0");assert(p&&Near(CGPathGetBoundingBox(p).size.width,20));CGPathRelease(p); /* flags without separators */
 p=TIOMenuLensCreatePath(@"M10 10 20 10 20 20");assert(p);CGPathRelease(p); /* an extra pair after a move is a line */
 for(NSString *bad in @[@"",@"L10 10",@"M10",@"M10 10X5",@"M10 10 l",@"M1 1a5 5 0 2 0 4 4",@"10 10"])assert(!TIOMenuLensCreatePath(bad));
 /* Carousel, no route: 80 px at lens-full in the middle, 48 px at lens-mid at 270 +- 124, 36 px at lens-track at 270 +- 214, all at y 68. */
 TIOMenuLensSlot s[TIOMenuLensSlotMax];NSUInteger n=Count(TIOMenuLensCarousel,13,9,s);assert(n==5);
 TIOMenuLensSlot focus=s[n-1];assert(focus.tile==9&&Near(focus.cx,270)&&Near(focus.cy,68)&&Near(focus.size,80)&&focus.ink==TIOMenuLensInkFull);
 BOOL seen[13]={0};
 for(NSUInteger i=0;i<n;i++){
  assert(Near(s[i].cy,68));
  if(i<n-1)assert(s[i].size<80&&s[i].ink!=TIOMenuLensInkFull);
  seen[s[i].tile]=YES;
  if(s[i].tile==8||s[i].tile==10)assert(Near(s[i].size,48)&&s[i].ink==TIOMenuLensInkMid&&Near(fabs(s[i].cx-270),124)&&(s[i].tile==8)==(s[i].cx<270));
  if(s[i].tile==7||s[i].tile==11)assert(Near(s[i].size,36)&&s[i].ink==TIOMenuLensInkTrack&&Near(fabs(s[i].cx-270),214)&&(s[i].tile==7)==(s[i].cx<270));
 }
 assert(seen[7]&&seen[8]&&seen[9]&&seen[10]&&seen[11]);
 /* It wraps from the last app to the first, in both directions. */
 n=Count(TIOMenuLensCarousel,13,12,s);assert(n==5&&s[n-1].tile==12);BOOL has0=NO,has1=NO,has10=NO,has11=NO;for(NSUInteger i=0;i<n;i++){has0|=s[i].tile==0;has1|=s[i].tile==1;has10|=s[i].tile==10;has11|=s[i].tile==11;}assert(has0&&has1&&has10&&has11);
 n=Count(TIOMenuLensCarousel,13,0,s);has0=NO;BOOL has12=NO,has11b=NO;for(NSUInteger i=0;i<n;i++){has12|=s[i].tile==12;has11b|=s[i].tile==11;}assert(n==5&&has12&&has11b);
 /* A short list never repeats an icon. */
 n=Count(TIOMenuLensCarousel,3,0,s);assert(n==3&&s[n-1].tile==0);n=Count(TIOMenuLensCarousel,1,0,s);assert(n==1);
 /* Grids: the page holding the focus, 30 px (26 px) icons, the focused one 2 px larger. */
 n=Count(TIOMenuLensRows2,13,1,s);assert(n==6&&s[n-1].tile==1&&Near(s[n-1].size,32)&&s[n-1].ink==TIOMenuLensInkFull&&Near(s[n-1].cx,270)&&Near(s[n-1].cy,76));
 for(NSUInteger i=0;i<n-1;i++)assert(Near(s[i].size,30)&&s[i].ink==TIOMenuLensInkMid&&(Near(s[i].cy,76)||Near(s[i].cy,133)));
 n=Count(TIOMenuLensRows3,13,4,s);assert(n==9&&s[n-1].tile==4&&Near(s[n-1].size,28)&&Near(s[n-1].cx,270)&&Near(s[n-1].cy,112));
 n=Count(TIOMenuLensRows3,13,9,s);assert(n==4&&s[n-1].tile==9&&Near(s[n-1].cx,92)&&Near(s[n-1].cy,70)); /* second page */
 n=Count(TIOMenuLensRows2,13,12,s);assert(n==1&&s[n-1].tile==12&&Near(s[n-1].size,32)&&Near(s[n-1].cx,92)); /* six per page: tile 12 sits alone on page 3 */
 /* Out-of-range input draws nothing. */
 assert(!Count(TIOMenuLensCarousel,13,13,s)&&!Count(TIOMenuLensCarousel,0,0,s)&&!Count((TIOMenuLensLayout)4,13,0,s)&&!TIOMenuLensSlots(TIOMenuLensCarousel,NULL,13,0,s));
 assert(Near(TIOMenuLensNameBaseline(TIOMenuLensCarousel),202)&&Near(TIOMenuLensNameBaseline(TIOMenuLensRows3),204)&&Near(TIOMenuLensStatusBaseline(),159)&&Near(TIOMenuLensClockBaseline(),38));
 puts("MenuLens PASS: 13 icon outlines on the 48 grid, SVG path parser, carousel 80/48/36 at 270 +- 124/214, wrap, grid pages");
}}
