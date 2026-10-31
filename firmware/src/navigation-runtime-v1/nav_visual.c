#include "../common-v1/tio_text.h"
#include "nav_visual.h"
#include "nav_glyph.h"
#include <string.h>
static char *decimal(char *p,uint32_t v){char tmp[10];unsigned n=0;do{tmp[n++]=(char)('0'+v%10);v/=10;}while(v);while(n)*p++=tmp[--n];*p=0;return p;}
static char *append(char *p,const char *s){while(*s)*p++=*s++;*p=0;return p;}
static char *distance(char *p,uint32_t m){
 if(m<1000){p=decimal(p,m);return append(p," m");}
 p=decimal(p,m/1000);*p++='.';*p++=(char)('0'+m%1000/100);return append(p," km");
}
/* Caller validates 2000..2100 plus <=7 days; 32-bit arithmetic avoids adding
 * a 64-bit division runtime to the freestanding AP payload. */
static char *clock_hm(char *p,int64_t epoch){unsigned min=((uint32_t)epoch%86400)/60;
 *p++=(char)('0'+min/60/10);*p++=(char)('0'+min/60%10);*p++=':';
 *p++=(char)('0'+min%60/10);*p++=(char)('0'+min%10);*p=0;return p;
}
/* ETA tail of the LensNav trip line ("1.2 km, 10 min, 10:10"): the arrival clock time, or why it is
 * missing. The wall clock itself is no longer shown (TMG6 footer removed); `now` only anchors the day. */
void tn_clock_text(char out[64],int64_t now,int64_t eta,bool stale){
 unsigned lang=tio_lang();memset(out,0,64);
 if(stale){append(out,tio_text(TT_NAV_STALE,lang));return;}
 if(now<946684800||now>4102444800LL||eta<now||eta-now>604800){append(out,tio_text(TT_NAV_ETA_PENDING,lang));return;}
 char *p=out;unsigned days=(uint32_t)eta/86400-(uint32_t)now/86400;
 if(days==1)p=append(p,tio_text(TT_NAV_TOMORROW,lang));else if(days){if(!lang)*p++='+';p=decimal(p,days);p=append(p,tio_text(TT_NAV_DAYS,lang));}
 clock_hm(p,eta);
}
static TNXY map(TNPoint p){return (TNXY){406+(int32_t)p.x*112/1023,10+(int32_t)p.y*112/1023};}
bool tn_visual(const TNScene *s,bool stale,TNVisual *v){
 unsigned lang=tio_lang();
 if(!s||!v||s->icon>=TN_ICON_COUNT||s->point_count>TN_POINTS_MAX||s->heading>=360||s->position.x>1023||s->position.y>1023)return false;
 memset(v,0,sizeof *v);v->stale=stale;v->icon_count=tn_glyph(s->icon,v->icon);
 v->route_count=s->point_count;for(unsigned i=0;i<s->point_count;i++){if(s->points[i].x>1023||s->points[i].y>1023)return false;v->route[i]=map(s->points[i]);}
 TNXY pos=map(s->position);
 /* Eight-way position arrow; no libm or per-frame heap allocation. */
 static const int8_t dirs[8][2]={{0,-1},{1,-1},{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1}};
 unsigned dir=((s->heading+22u)/45u)%8u;int dx=dirs[dir][0],dy=dirs[dir][1];
 v->position[0]=(TNXY){pos.x+dx*8,pos.y+dy*8};v->position[1]=(TNXY){pos.x-dx*5-dy*5,pos.y-dy*5+dx*5};
 v->position[2]=(TNXY){pos.x-dx*5+dy*5,pos.y-dy*5-dx*5};v->position[3]=v->position[0];
 char *p=v->distance;if(s->distance_m<1000){p=decimal(p,s->distance_m);append(p," m");}
 else {p=decimal(p,s->distance_m/1000);*p++='.';*p++=(char)('0'+s->distance_m%1000/100);append(p," km");}
 memcpy(v->turn,s->turn,sizeof v->turn);memcpy(v->road,s->road,sizeof v->road);v->turn[TN_TURN_MAX]=0;v->road[TN_ROAD_MAX]=0;
 /* Trip summary for band M, e.g. "1.2 km", middle dot, "10 min"; the arrival time follows from tn_clock_text. */
 p=distance(v->summary,s->remaining_m);p=append(p," \xc2\xb7 ");
 unsigned minutes=s->remaining_s/60+(s->remaining_s%60!=0);
 if(minutes>=60){p=decimal(p,minutes/60);p=append(p,tio_text(TT_NAV_HOUR,lang));minutes%=60;}
 p=decimal(p,minutes);append(p,tio_text(TT_NAV_MIN,lang));
 tn_clock_text(v->status,0,0,stale);return true;
}
