#import "MenuLens.h"
#include <math.h>
#include <ctype.h>
#include <stdlib.h>
const CGFloat TIOMenuLensIconGrid=48,TIOMenuLensIconStroke=2.6;
/* docs/design-system icons-proposed/paths.json: the 13 icons as one path each, index = tile id. */
static NSString *const Icons[TIOMenuLensIconCount][2]={
 {@"recorder",@"M24 6h0a6 6 0 0 1 6 6v10a6 6 0 0 1 -6 6h-0a6 6 0 0 1 -6 -6v-10a6 6 0 0 1 6 -6zM11 22a13 13 0 0 0 26 0M24 35v6M17 41h14"},
 {@"live-captions",@"M12 9h24a6 6 0 0 1 6 6v12a6 6 0 0 1-6 6H22l-8 7v-7h-2a6 6 0 0 1-6-6V15a6 6 0 0 1 6-6zM14 18h20M14 25h12"},
 {@"live-assist",@"M24 6c1.6 10.4 7.6 16.4 18 18-10.4 1.6-16.4 7.6-18 18-1.6-10.4-7.6-16.4-18-18 10.4-1.6 16.4-7.6 18-18z"},
 {@"todo",@"M15 9h18a4 4 0 0 1 4 4v25a4 4 0 0 1 -4 4h-18a4 4 0 0 1 -4 -4v-25a4 4 0 0 1 4 -4zM20 5h8a2 2 0 0 1 2 2v3a2 2 0 0 1 -2 2h-8a2 2 0 0 1 -2 -2v-3a2 2 0 0 1 2 -2zM17 27l5 5 9-10"},
 {@"teleprompter",@"M11 7h26a4 4 0 0 1 4 4v26a4 4 0 0 1 -4 4h-26a4 4 0 0 1 -4 -4v-26a4 4 0 0 1 4 -4zM14 30h20M14 37h12M24 23V12M19 17l5-5 5 5"},
 {@"lifelog",@"M15 6h21a3 3 0 0 1 3 3v30a3 3 0 0 1 -3 3h-21a3 3 0 0 1 -3 -3v-30a3 3 0 0 1 3 -3zM8 13h6M8 21h6M8 29h6M8 37h6M21 20v8M25.5 16v16M30 19v10M34.5 22v4"},
 {@"do-not-disturb",@"M30 7a17 17 0 1 0 11 25 13.5 13.5 0 0 1-11-25z"},
 {@"display-test",@"M9 9h30a3 3 0 0 1 3 3v24a3 3 0 0 1 -3 3h-30a3 3 0 0 1 -3 -3v-24a3 3 0 0 1 3 -3zM16 24a8 8 0 1 0 16 0a8 8 0 1 0 -16 0M24 9v6M24 33v6M6 24h6M36 24h6"},
 {@"navigation",@"M41 7L8 21.5l14 4.5 4.5 14z"},
 {@"music",@"M10 35a5 5 0 1 0 10 0a5 5 0 1 0 -10 0M28 31a5 5 0 1 0 10 0a5 5 0 1 0 -10 0M20 35V11l18-4v24"},
 {@"pomodoro",@"M10 28a14 14 0 1 0 28 0a14 14 0 1 0 -28 0M24 14c-2-4-6-6-10-5 1 4 5 6 10 5zM24 14c2-4 6-6 10-5-1 4-5 6-10 5zM24 14V8M24 28v-6M24 28l4 3"},
 {@"my-apps",@"M11.5 8h6a3.5 3.5 0 0 1 3.5 3.5v6a3.5 3.5 0 0 1 -3.5 3.5h-6a3.5 3.5 0 0 1 -3.5 -3.5v-6a3.5 3.5 0 0 1 3.5 -3.5zM30.5 8h6a3.5 3.5 0 0 1 3.5 3.5v6a3.5 3.5 0 0 1 -3.5 3.5h-6a3.5 3.5 0 0 1 -3.5 -3.5v-6a3.5 3.5 0 0 1 3.5 -3.5zM11.5 27h6a3.5 3.5 0 0 1 3.5 3.5v6a3.5 3.5 0 0 1 -3.5 3.5h-6a3.5 3.5 0 0 1 -3.5 -3.5v-6a3.5 3.5 0 0 1 3.5 -3.5zM30.5 27h6a3.5 3.5 0 0 1 3.5 3.5v6a3.5 3.5 0 0 1 -3.5 3.5h-6a3.5 3.5 0 0 1 -3.5 -3.5v-6a3.5 3.5 0 0 1 3.5 -3.5z"},
 {@"camera",@"M11 14h6l3-5h8l3 5h6a5 5 0 0 1 5 5v17a5 5 0 0 1-5 5H11a5 5 0 0 1-5-5V19a5 5 0 0 1 5-5zM17 27a7 7 0 1 0 14 0a7 7 0 1 0 -14 0"}
};

typedef struct {const char *s;const char *end;BOOL bad;} Cursor;
static void Skip(Cursor *c){while(c->s<c->end&&(*c->s==' '||*c->s==','||*c->s=='\n'||*c->s=='\t'||*c->s=='\r'))c->s++;}
static BOOL Number(Cursor *c,CGFloat *out){
 Skip(c);if(c->s>=c->end)return NO;char *stop=NULL;double v=strtod(c->s,&stop);if(stop==c->s||stop>c->end||!isfinite(v)){c->bad=YES;return NO;}
 c->s=stop;*out=(CGFloat)v;return YES;
}
/* An arc flag is one digit, and may touch the next number ("0 01-6"). */
static BOOL Flag(Cursor *c,BOOL *out){Skip(c);if(c->s>=c->end||(*c->s!='0'&&*c->s!='1')){c->bad=YES;return NO;}*out=*c->s=='1';c->s++;return YES;}
/* SVG endpoint arc to cubic Beziers of at most 90 degrees each (SVG 1.1 implementation notes F.6). */
static void Arc(CGMutablePathRef p,CGPoint from,CGFloat rx,CGFloat ry,CGFloat degrees,BOOL large,BOOL sweep,CGPoint to){
 if(from.x==to.x&&from.y==to.y)return;
 rx=fabs(rx);ry=fabs(ry);if(rx==0||ry==0){CGPathAddLineToPoint(p,NULL,to.x,to.y);return;}
 CGFloat phi=degrees*M_PI/180,cp=cos(phi),sp=sin(phi);
 CGFloat dx=(from.x-to.x)/2,dy=(from.y-to.y)/2,x1=cp*dx+sp*dy,y1=-sp*dx+cp*dy;
 CGFloat lambda=x1*x1/(rx*rx)+y1*y1/(ry*ry);if(lambda>1){CGFloat r=sqrt(lambda);rx*=r;ry*=r;}
 CGFloat num=rx*rx*ry*ry-rx*rx*y1*y1-ry*ry*x1*x1,den=rx*rx*y1*y1+ry*ry*x1*x1;
 CGFloat k=den==0?0:sqrt(MAX(0,num/den));if(large==sweep)k=-k;
 CGFloat cx1=k*rx*y1/ry,cy1=-k*ry*x1/rx;
 CGFloat cx=cp*cx1-sp*cy1+(from.x+to.x)/2,cy=sp*cx1+cp*cy1+(from.y+to.y)/2;
 CGFloat t1=atan2((y1-cy1)/ry,(x1-cx1)/rx),t2=atan2((-y1-cy1)/ry,(-x1-cx1)/rx),dt=t2-t1;
 if(sweep&&dt<0)dt+=2*M_PI;else if(!sweep&&dt>0)dt-=2*M_PI;
 int steps=(int)ceil(fabs(dt)/(M_PI/2)-1e-9);if(steps<1)steps=1;CGFloat step=dt/steps,alpha=4.0/3.0*tan(step/4);
 CGFloat t=t1;
 for(int i=0;i<steps;i++){
  CGFloat a=t,b=t+step;
  CGFloat ca=cos(a),sa=sin(a),cb=cos(b),sb=sin(b);
  CGPoint c1={ca-alpha*sa,sa+alpha*ca},c2={cb+alpha*sb,sb-alpha*cb},e={cb,sb};
  CGPoint pts[3]={c1,c2,e};
  for(int j=0;j<3;j++){CGFloat ex=rx*pts[j].x,ey=ry*pts[j].y;pts[j]=CGPointMake(cp*ex-sp*ey+cx,sp*ex+cp*ey+cy);}
  CGPathAddCurveToPoint(p,NULL,pts[0].x,pts[0].y,pts[1].x,pts[1].y,pts[2].x,pts[2].y);
  t=b;
 }
 CGPathAddLineToPoint(p,NULL,to.x,to.y); /* lands exactly on the endpoint */
}
CGPathRef TIOMenuLensCreatePath(NSString *svg){
 if(![svg isKindOfClass:NSString.class])return NULL;
 const char *text=svg.UTF8String;if(!text)return NULL;
 Cursor c={text,text+strlen(text),NO};CGMutablePathRef p=CGPathCreateMutable();
 CGPoint cur=CGPointZero,start=CGPointZero,lastC=CGPointZero,lastQ=CGPointZero;char cmd=0,prev=0;BOOL open=NO;
 for(;;){
  Skip(&c);if(c.s>=c.end)break;
  if(isalpha((unsigned char)*c.s)){cmd=*c.s++;}
  else if(!cmd||cmd=='Z'||cmd=='z'){c.bad=YES;break;}
  else if(cmd=='M')cmd='L';else if(cmd=='m')cmd='l'; /* extra pairs after a move are lines */
  BOOL rel=islower((unsigned char)cmd);char up=(char)toupper(cmd);CGFloat v[7];BOOL fa=NO,fs=NO;
  if(up=='Z'){if(open)CGPathCloseSubpath(p);cur=start;open=NO;prev='Z';continue;}
  int need=up=='M'||up=='L'||up=='T'?2:up=='H'||up=='V'?1:up=='C'?6:up=='S'||up=='Q'?4:up=='A'?7:-1;
  if(need<0){c.bad=YES;break;}
  BOOL ok=YES;
  for(int i=0;i<need&&ok;i++){
   if(up=='A'&&(i==3||i==4)){ok=Flag(&c,i==3?&fa:&fs);v[i]=0;}else ok=Number(&c,&v[i]);
  }
  if(!ok){c.bad=YES;break;}
  CGFloat ox=rel?cur.x:0,oy=rel?cur.y:0;
  switch(up){
   case 'M':cur=CGPointMake(ox+v[0],oy+v[1]);start=cur;CGPathMoveToPoint(p,NULL,cur.x,cur.y);open=YES;break;
   case 'L':if(!open){c.bad=YES;break;}cur=CGPointMake(ox+v[0],oy+v[1]);CGPathAddLineToPoint(p,NULL,cur.x,cur.y);break;
   case 'H':if(!open){c.bad=YES;break;}cur.x=ox+v[0];CGPathAddLineToPoint(p,NULL,cur.x,cur.y);break;
   case 'V':if(!open){c.bad=YES;break;}cur.y=oy+v[0];CGPathAddLineToPoint(p,NULL,cur.x,cur.y);break;
   case 'C':{if(!open){c.bad=YES;break;}CGPoint a={ox+v[0],oy+v[1]},b={ox+v[2],oy+v[3]},e={ox+v[4],oy+v[5]};CGPathAddCurveToPoint(p,NULL,a.x,a.y,b.x,b.y,e.x,e.y);lastC=b;cur=e;break;}
   case 'S':{if(!open){c.bad=YES;break;}CGPoint a=(prev=='C'||prev=='S')?CGPointMake(2*cur.x-lastC.x,2*cur.y-lastC.y):cur,b={ox+v[0],oy+v[1]},e={ox+v[2],oy+v[3]};CGPathAddCurveToPoint(p,NULL,a.x,a.y,b.x,b.y,e.x,e.y);lastC=b;cur=e;break;}
   case 'Q':{if(!open){c.bad=YES;break;}CGPoint a={ox+v[0],oy+v[1]},e={ox+v[2],oy+v[3]};CGPathAddQuadCurveToPoint(p,NULL,a.x,a.y,e.x,e.y);lastQ=a;cur=e;break;}
   case 'T':{if(!open){c.bad=YES;break;}CGPoint a=(prev=='Q'||prev=='T')?CGPointMake(2*cur.x-lastQ.x,2*cur.y-lastQ.y):cur,e={ox+v[0],oy+v[1]};CGPathAddQuadCurveToPoint(p,NULL,a.x,a.y,e.x,e.y);lastQ=a;cur=e;break;}
   case 'A':{if(!open){c.bad=YES;break;}CGPoint e={ox+v[5],oy+v[6]};Arc(p,cur,v[0],v[1],v[2],fa,fs,e);cur=e;break;}
  }
  if(c.bad)break;
  prev=up;
 }
 if(c.bad||CGPathIsEmpty(p)){CGPathRelease(p);return NULL;}
 return p;
}
CGPathRef TIOMenuLensIconPath(NSUInteger tile){
 static CGPathRef paths[TIOMenuLensIconCount];static dispatch_once_t once;
 dispatch_once(&once,^{for(NSUInteger i=0;i<TIOMenuLensIconCount;i++)paths[i]=TIOMenuLensCreatePath(Icons[i][1]);});
 return tile<TIOMenuLensIconCount?paths[tile]:NULL;
}
NSString *TIOMenuLensIconName(NSUInteger tile){return tile<TIOMenuLensIconCount?Icons[tile][0]:nil;}

/* LensMenuCarousel.dc.html: no route, slot sizes 80 / 48 / 36 at lens-full / lens-mid / lens-track, centre y 68, dx 0 / 124 / 214. */
static const CGFloat CarouselSize[3]={80,48,36},CarouselDx[3]={0,124,214},CarouselY=68;
static const TIOMenuLensInk CarouselInk[3]={TIOMenuLensInkFull,TIOMenuLensInkMid,TIOMenuLensInkTrack};
/* PhoneMenuLayout.dc.html: 2 rows 30 px at y 76 / 133, 3 rows 26 px at y 70 / 112 / 154, columns 92 / 270 / 448; the focused icon is 2 px larger. */
NSUInteger TIOMenuLensSlots(TIOMenuLensLayout layout,const uint8_t *visible,NSUInteger count,NSUInteger focus,TIOMenuLensSlot out[TIOMenuLensSlotMax]){
 if(!visible||!count||count>TIOMenuLensSlotMax||focus>=count)return 0;
 NSUInteger n=0;
 if(layout==TIOMenuLensCarousel){
  /* Nearest first from the outside in, so the focused icon is drawn last. Distances wrap, as the menu does. */
  for(int ad=2;ad>=0;ad--)for(int side=-1;side<=1;side+=2){
   if(ad==0&&side>0)continue;
   NSInteger d=side*ad;NSInteger idx=((NSInteger)focus+d)%(NSInteger)count;if(idx<0)idx+=(NSInteger)count;
   BOOL duplicate=NO;for(NSUInteger k=0;k<n;k++)if(out[k].tile==visible[idx])duplicate=YES;if(duplicate)continue; /* a short list does not repeat an icon */
   out[n++]=(TIOMenuLensSlot){visible[idx],270+(CGFloat)side*CarouselDx[ad],CarouselY,CarouselSize[ad],CarouselInk[ad]};
  }
  return n;
 }
 if(layout!=TIOMenuLensRows2&&layout!=TIOMenuLensRows3)return 0;
 NSUInteger rows=layout,perPage=rows*3,page=focus/perPage;
 static const CGFloat cols[3]={92,270,448},ys2[2]={76,133},ys3[3]={70,112,154};
 CGFloat size=rows==2?30:26;NSUInteger focusSlot=NSNotFound;
 for(NSUInteger i=page*perPage;i<count&&i<(page+1)*perPage;i++){
  NSUInteger j=i-page*perPage,col=j%3,row=j/3;BOOL on=i==focus;
  if(on)focusSlot=n;
  out[n++]=(TIOMenuLensSlot){visible[i],cols[col],rows==2?ys2[row]:ys3[row],on?size+2:size,on?TIOMenuLensInkFull:TIOMenuLensInkMid};
 }
 if(focusSlot!=NSNotFound&&focusSlot!=n-1){TIOMenuLensSlot t=out[focusSlot];out[focusSlot]=out[n-1];out[n-1]=t;}
 return n;
}
CGFloat TIOMenuLensNameBaseline(TIOMenuLensLayout layout){return layout==TIOMenuLensCarousel?202:204;}
CGFloat TIOMenuLensStatusBaseline(void){return 159;}
CGFloat TIOMenuLensClockBaseline(void){return 38;}
