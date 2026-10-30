#include "../src/focus-v1/tile_state.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
/* TMG8 live tile state: the text and the decisions behind the carousel status line and the grid state dots
 * (LensMenuCarousel.dc.html / LensMenuGrid2.dc.html STATUS fixtures), over a stubbed TSLive snapshot. */
static bool utf8(const char *s){const unsigned char *p=(const unsigned char *)s;
 while(*p){unsigned a=*p++,n;if(a<128)continue;if(a>=0xc2&&a<=0xdf)n=1;else if(a>=0xe0&&a<=0xef)n=2;else if(a>=0xf0&&a<=0xf4)n=3;else return false;
  for(unsigned j=0;j<n;j++)if((*p++&0xc0)!=0x80)return false;}return true;}
static TSState st(unsigned tile,const TSLive *in,unsigned lang){TSState s;memset(&s,0x5a,sizeof s);ts_state(tile,in,lang,&s);assert(memchr(s.line,0,sizeof s.line));return s;}
static void expect(unsigned tile,const TSLive *in,unsigned lang,const char *line,bool active,bool off){
 TSState s=st(tile,in,lang);if(strcmp(s.line,line)||s.active!=active||s.phone_off!=off){printf("tile %u lang %u: got '%s' active=%d off=%d, want '%s' active=%d off=%d\n",tile,lang,s.line,s.active,s.phone_off,line,active,off);assert(0);}
 assert(utf8(s.line)&&strlen(s.line)<TS_LINE_MAX);assert(tm_width(s.line,strlen(s.line),TIO_FONT_MIN)<=TIO_CORE_W);   /* fits the 460 px core at 16 px */
}
int main(void){
 /* The three board scenarios. */
 static const char title[]="Blinding Lights";
 const TSLive live={.phone=true,.pomodoro=true,.pomodoro_ms=18*60000+42000,.music_playing=true,.music_age_ms=2000,.music_title=title,.nav_active=true,.nav_remaining_m=1200};
 const TSLive idle={.phone=true};
 const TSLive off={.phone=false,.pomodoro=true,.pomodoro_ms=18*60000+42000};
 expect(TIO_TILE_NAVIGATION,&live,0,"1.2 km to go",true,false);
 expect(TIO_TILE_MUSIC,&live,0,"Playing \xc2\xb7 Blinding Lights",true,false);
 expect(TIO_TILE_FOCUS,&live,0,"18:42 left",true,false);
 expect(TIO_TILE_NAVIGATION,&idle,0,"",false,false);expect(TIO_TILE_MUSIC,&idle,0,"",false,false);expect(TIO_TILE_FOCUS,&idle,0,"",false,false);
 expect(TIO_TILE_NAVIGATION,&off,0,"Phone not connected",false,true);          /* a line, but no dot */
 expect(TIO_TILE_MUSIC,&off,0,"Phone not connected",false,true);
 expect(TIO_TILE_FOCUS,&off,0,"18:42 left",true,false);                          /* the timer is local: it needs no phone */
 /* Chinese. */
 expect(TIO_TILE_NAVIGATION,&live,1,"\xe5\x89\xa9\xe4\xbd\x99 1.2 \xe5\x85\xac\xe9\x87\x8c",true,false);
 expect(TIO_TILE_MUSIC,&live,1,"\xe6\xad\xa3\xe5\x9c\xa8\xe6\x92\xad\xe6\x94\xbe \xc2\xb7 Blinding Lights",true,false);
 expect(TIO_TILE_FOCUS,&live,1,"\xe5\x89\xa9\xe4\xbd\x99 18:42",true,false);
 expect(TIO_TILE_NAVIGATION,&off,1,"\xe6\x89\x8b\xe6\x9c\xba\xe6\x9c\xaa\xe8\xbf\x9e\xe6\x8e\xa5",false,true);
 /* Stock apps, My Apps and unknown ids: name only, whatever is running. */
 for(unsigned lang=0;lang<2;lang++)for(unsigned id=0;id<32;id++){if(id==TIO_TILE_NAVIGATION||id==TIO_TILE_MUSIC||id==TIO_TILE_FOCUS||id==TIO_TILE_CAMERA)continue;
  TSLive busy=live;busy.camera=true;expect(id,&busy,lang,"",false,false);expect(id,&off,lang,"",false,false);}
 /* Camera: a live phone camera session; no board string, so the page's own "Live view" text. */
 {TSLive cam={.phone=true,.camera=true};expect(TIO_TILE_CAMERA,&cam,0,"Live view",true,false);expect(TIO_TILE_CAMERA,&cam,1,"\xe5\xae\x9e\xe6\x97\xb6\xe5\x8f\x96\xe6\x99\xaf",true,false);
  expect(TIO_TILE_CAMERA,&idle,0,"",false,false);TSLive nophone={.camera=true};expect(TIO_TILE_CAMERA,&nophone,0,"Live view",true,false);expect(TIO_TILE_CAMERA,&off,0,"",false,false);}
 /* Pomodoro: seconds round up, two digit minutes, past an hour, zero. */
 {const struct {uint32_t ms;const char *text;} t[]={{1,"00:01 left"},{999,"00:01 left"},{1000,"00:01 left"},{1001,"00:02 left"},{59000,"00:59 left"},{60000,"01:00 left"},{299500,"05:00 left"},{1499001,"25:00 left"},{3600000,"60:00 left"},{7200000,"120:00 left"},{0,"00:00 left"}};
  for(unsigned i=0;i<sizeof t/sizeof *t;i++){TSLive l={.pomodoro=true,.pomodoro_ms=t[i].ms};expect(TIO_TILE_FOCUS,&l,0,t[i].text,true,false);}
  TSLive none={.pomodoro_ms=5000};expect(TIO_TILE_FOCUS,&none,0,"",false,false);}   /* the figure alone means nothing without the flag (stopped, done, idle) */
 /* Navigation: kilometres with one decimal, whole kilometres from 100 km, metres under 950 m; stale, ended and arrived show nothing. */
 {const struct {uint32_t m;const char *en,*zh;} t[]={
   {1,"10 m to go","\xe5\x89\xa9\xe4\xbd\x99 10 \xe7\xb1\xb3"},{14,"10 m to go",0},{15,"20 m to go",0},{640,"640 m to go",0},{949,"950 m to go",0},
   {950,"1.0 km to go","\xe5\x89\xa9\xe4\xbd\x99 1.0 \xe5\x85\xac\xe9\x87\x8c"},{1049,"1.0 km to go",0},{1050,"1.1 km to go",0},{1200,"1.2 km to go",0},{1250,"1.3 km to go",0},
   {9949,"9.9 km to go",0},{9950,"10.0 km to go",0},{99949,"99.9 km to go",0},{99950,"100 km to go",0},{123456,"123 km to go",0},{4000000000u,"4000000 km to go",0}};
  for(unsigned i=0;i<sizeof t/sizeof *t;i++){TSLive l={.phone=true,.nav_active=true,.nav_remaining_m=t[i].m};expect(TIO_TILE_NAVIGATION,&l,0,t[i].en,true,false);if(t[i].zh)expect(TIO_TILE_NAVIGATION,&l,1,t[i].zh,true,false);}
  TSLive stale={.phone=true,.nav_active=true,.nav_stale=true,.nav_remaining_m=1200},ended={.phone=true,.nav_remaining_m=1200},arrived={.phone=true,.nav_active=true};
  expect(TIO_TILE_NAVIGATION,&stale,0,"",false,false);expect(TIO_TILE_NAVIGATION,&ended,0,"",false,false);expect(TIO_TILE_NAVIGATION,&arrived,0,"",false,false);}
 /* Music: playing and the phone spoke within 30 s (the tm_expired window); paused, silent or stale shows nothing; the link down beats everything. */
 {TSLive l={.phone=true,.music_playing=true,.music_title=title};
  l.music_age_ms=0;expect(TIO_TILE_MUSIC,&l,0,"Playing \xc2\xb7 Blinding Lights",true,false);l.music_age_ms=30000;expect(TIO_TILE_MUSIC,&l,0,"Playing \xc2\xb7 Blinding Lights",true,false);
  l.music_age_ms=30001;expect(TIO_TILE_MUSIC,&l,0,"",false,false);l.music_age_ms=UINT32_MAX;expect(TIO_TILE_MUSIC,&l,0,"",false,false);
  l.music_age_ms=1;l.music_playing=false;expect(TIO_TILE_MUSIC,&l,0,"",false,false);
  l.music_playing=true;l.phone=false;expect(TIO_TILE_MUSIC,&l,0,"Phone not connected",false,true);
  l.phone=true;l.music_title="";expect(TIO_TILE_MUSIC,&l,0,"Playing",true,false);expect(TIO_TILE_MUSIC,&l,1,"\xe6\xad\xa3\xe5\x9c\xa8\xe6\x92\xad\xe6\x94\xbe",true,false);
  l.music_title=NULL;expect(TIO_TILE_MUSIC,&l,0,"Playing",true,false);}
 /* Long titles: one line inside 460 px at 16 px, cut at a character with an ellipsis; a 96 byte field with no terminator is never read past. */
 {char buf[96];memset(buf,'a',sizeof buf);TSLive l={.phone=true,.music_playing=true,.music_title=buf};
  TSState s=st(TIO_TILE_MUSIC,&l,0);assert(s.active&&utf8(s.line)&&!strchr(s.line,'\n')&&tm_width(s.line,strlen(s.line),TIO_FONT_MIN)<=TIO_CORE_W);
  assert(!memcmp(s.line+strlen(s.line)-3,"\xe2\x80\xa6",3)&&!memcmp(s.line,"Playing \xc2\xb7 aaaa",15));
  char cjk[96]="";for(unsigned i=0;i<31;i++)strcat(cjk,"\xe7\x95\x8c");l.music_title=cjk;   /* 93 bytes */
  for(unsigned lang=0;lang<2;lang++){s=st(TIO_TILE_MUSIC,&l,lang);assert(s.active&&utf8(s.line)&&tm_width(s.line,strlen(s.line),TIO_FONT_MIN)<=TIO_CORE_W&&!memcmp(s.line+strlen(s.line)-3,"\xe2\x80\xa6",3));}
  /* The 95 byte limit falls inside a 3 byte character (a 4 byte field of it starts at byte 93): the character must not be split. */
  char over[100];memset(over,'c',93);over[93]=(char)0xe7;over[94]=(char)0x95;over[95]=(char)0x8c;over[96]=0;l.music_title=over;s=st(TIO_TILE_MUSIC,&l,0);assert(utf8(s.line));
  char tiny[96];memset(tiny,'i',95);tiny[95]=0;l.music_title=tiny;s=st(TIO_TILE_MUSIC,&l,0);assert(utf8(s.line)&&tm_width(s.line,strlen(s.line),TIO_FONT_MIN)<=TIO_CORE_W);
  /* Wide capitals and mixed text. */
  l.music_title="WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW";s=st(TIO_TILE_MUSIC,&l,0);assert(tm_width(s.line,strlen(s.line),TIO_FONT_MIN)<=TIO_CORE_W);
  l.music_title="Short";s=st(TIO_TILE_MUSIC,&l,0);assert(!strcmp(s.line,"Playing \xc2\xb7 Short"));}
 /* Pattern helper: first {} only, bounded, and a capacity of 1 yields an empty string. */
 {char o[8];ts_pattern(o,sizeof o,"{} left","12:34");assert(!strcmp(o,"12:34 l"));ts_pattern(o,sizeof o,"a{}b{}","1");assert(!strcmp(o,"a1b{}"));ts_pattern(o,1,"x","y");assert(!o[0]);}
 /* The strings: English ASCII, Chinese UTF-8, every pattern has its figure slot. */
 for(unsigned lang=0;lang<2;lang++){const unsigned keys[]={TT_STATE_TIME_LEFT,TT_STATE_KM_TO_GO,TT_STATE_M_TO_GO};
  for(unsigned i=0;i<3;i++){const char *p=tio_text(keys[i],lang);assert(strstr(p,"{}")&&strstr(p,"{}")==strchr(p,'{')&&utf8(p));}
  assert(*tio_text(TT_STATE_PLAYING,lang)&&*tio_text(TT_STATE_PHONE_OFF,lang));}
 /* No null deref. */
 {TSState s;ts_state(TIO_TILE_MUSIC,NULL,0,&s);assert(!s.active&&!s.phone_off&&!s.line[0]);}
 puts("PASS tmg8 tile state: board scenarios EN/ZH, phone-off lines without dots, boundaries, truncation inside 460 px, stock apps name only");
}
