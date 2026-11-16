/* Glasses test bench lyric fixtures against the firmware's own wrapping (src/music-runtime-v1/music_layout.h, the code the glasses run).
 * Each fixture of GlassesBenchLyrics.h, cut at 240 bytes like the phone cuts it, must land in the fit step and row count it is named for,
 * end in an ellipsis only where it says so, and hide or show the next lyric as the layout rule says. */
#include "../GlassesBenchLyrics.h"
#include "music-runtime-v1/music_layout.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

#define ELL "\xe2\x80\xa6"
typedef struct {const char *id,*lang;unsigned step,lines,ellipsis,nextEllipsis;const char *current,*next;} Fixture;
#define ROW(id,lang,step,lines,ell,nextEll,current,next) {#id,lang,step,lines,ell,nextEll,current,next},
static const Fixture Fixtures[]={TGB_LYRICS(ROW)};

/* The phone's clip: at most `max` bytes, never inside a UTF-8 sequence. */
static void clip(const char *in,size_t max,char *out){
 size_t n=strlen(in);if(n>max){n=max;while(n&&((unsigned char)in[n]&0xC0)==0x80)n--;}
 memcpy(out,in,n);out[n]=0;}

int main(void){
 assert(sizeof Fixtures/sizeof Fixtures[0]==8);
 for(unsigned i=0;i<sizeof Fixtures/sizeof Fixtures[0];i++){
  const Fixture *f=&Fixtures[i];
  char cut[TGB_LYRIC_CAP+1],buf[TM_CUR_RAW],out[TM_CUR_CAP];
  clip(f->current,TGB_LYRIC_CAP,cut);assert(strlen(cut)<=TGB_LYRIC_CAP&&strlen(cut)<TM_CUR_RAW);
  strcpy(buf,cut);tm_clean(buf);
  TMFit fit=tm_fit_current(buf,out,sizeof out);
  const bool ell=strstr(out,ELL)!=NULL;
  if(fit.step!=f->step||fit.lines!=f->lines||ell!=(bool)f->ellipsis||fit.next!=(f->lines<=2)){
   printf("%s: step %u lines %u ellipsis %d next %d, fixture says step %u lines %u ellipsis %u\n",f->id,fit.step,fit.lines,ell,fit.next,f->step,f->lines,f->ellipsis);
   return 1;}
  /* Nothing is lost short of the ellipsis: the wrapped rows hold exactly the clipped text. */
  if(!ell){char a[TM_CUR_RAW],b[TM_CUR_CAP];size_t o=0;for(const char *p=buf;*p;p++)if(*p!='\n'&&*p!=' ')a[o++]=*p;a[o]=0;o=0;for(const char *p=out;*p;p++)if(*p!='\n'&&*p!=' ')b[o++]=*p;b[o]=0;assert(!strcmp(a,b));}
  /* The next lyric keeps its one line; it ends in an ellipsis only where the fixture says so. */
  char nextCut[TGB_LYRIC_CAP+1],one[244];
  clip(f->next,TGB_LYRIC_CAP,nextCut);tm_one_line(nextCut,TIO_CORE_W,TM_NEXT_FONT,one,sizeof one);
  assert(!strchr(one,'\n')&&(strstr(one,ELL)!=NULL)==(bool)f->nextEllipsis);
  assert(tm_width(one,strlen(one),TM_NEXT_FONT)<=TIO_CORE_W);
  /* The language tag is honest: Chinese fixtures are Han text, English ones are ASCII. */
  bool ascii=true;for(const char *p=f->current;*p;p++)if((unsigned char)*p>=0x80)ascii=false;
  assert(ascii==!strcmp(f->lang,"en"));
 }
 /* The set covers the ladder the task asks for: 3, 4 and 5 lines, the type shrinking (step 3), the ellipsis, a long next line and Chinese at 3 and 4 lines. */
 unsigned lines[5]={0},zh3=0,zh4=0,ell=0,next=0;
 for(unsigned i=0;i<sizeof Fixtures/sizeof Fixtures[0];i++){const Fixture *f=&Fixtures[i];if(!strcmp(f->lang,"en")&&f->lines<5)lines[f->lines]++;if(!strcmp(f->lang,"zh")&&f->lines==3)zh3++;if(!strcmp(f->lang,"zh")&&f->lines==4)zh4++;if(f->ellipsis)ell++;if(f->nextEllipsis)next++;}
 assert(lines[3]==1&&lines[4]==2&&zh3==1&&zh4==1&&ell==1&&next==1);
 printf("PASS glasses test bench lyrics: %zu fixtures land in their fit step and row count under the firmware's own layout\n",sizeof Fixtures/sizeof Fixtures[0]);
 return 0;
}
