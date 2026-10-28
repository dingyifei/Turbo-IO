#include "../src/common-v1/tio_text.h"
#include "../src/music-runtime-v1/music.h"
#include "../src/navigation-runtime-v1/nav_runtime.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static bool utf8(const unsigned char *p){
 while(*p){unsigned a=*p++,c=a,n;if(a<128)continue;
  if(a>=0xc2&&a<=0xdf){n=1;c=a&31;}else if(a>=0xe0&&a<=0xef){n=2;c=a&15;}else if(a>=0xf0&&a<=0xf4){n=3;c=a&7;}else return false;
  unsigned min=n==1?128:n==2?2048:65536;
  for(unsigned j=0;j<n;j++){unsigned b=*p++;if((b&0xc0)!=0x80)return false;c=(c<<6)|(b&63);}
  if(c<min||c>0x10ffff||(c>=0xd800&&c<=0xdfff))return false;
 }return true;
}
int main(void){
 for(unsigned key=0;key<TT_COUNT;key++){
  const char *en=tio_text(key,0),*zh=tio_text(key,1);
  assert(*en||key==TT_NAV_ETA_SUFFIX);assert(*zh&&utf8((const unsigned char *)zh));
  for(const unsigned char *p=(const unsigned char *)en;*p;p++)assert((*p>=32&&*p<=126)||*p=='\n');
 }
 assert(!*tio_text(TT_COUNT,0)&&!*tio_text(~0u,1));assert(!strcmp(tio_text(TT_TILE_MUSIC,99),tio_text(TT_TILE_MUSIC,0)));
 for(unsigned lang=0;lang<2;lang++){
  assert(strlen(tio_text(TT_NAV_START,lang))<=TN_TURN_MAX);
  assert(strlen(tio_text(TT_MUSIC_TITLE,lang))<sizeof ((TMMusic *)0)->title);
  assert(strlen(tio_text(TT_MUSIC_PICK,lang))<sizeof ((TMMusic *)0)->title);
  assert(strlen(tio_text(TT_MUSIC_LYRICS,lang))<244);
  assert(strlen(tio_text(TT_MUSIC_PLAYING,lang))<80&&strlen(tio_text(TT_MUSIC_PAUSED,lang))<80);
  char clock[64],summary[48];
  int n=snprintf(clock,sizeof clock,"%s23:59%s%s+999%s23:59%s",tio_text(TT_NAV_NOW,lang),tio_text(TT_NAV_SEP,lang),tio_text(TT_NAV_ETA_PREFIX,lang),tio_text(TT_NAV_DAYS,lang),tio_text(TT_NAV_ETA_SUFFIX,lang));
  assert(n>0&&(unsigned)n<sizeof clock);
  n=snprintf(summary,sizeof summary,"%s999.9km - 99h59m",tio_text(TT_NAV_LEFT,lang));assert(n>0&&(unsigned)n<sizeof summary);
 }
 puts("PASS tio_text: ASCII English, UTF-8 Chinese and bounded composed text");
}
