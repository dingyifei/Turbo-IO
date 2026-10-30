#include "../src/music-runtime-v1/music_layout.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* TMG8 LyricStack (components/LyricStack/README.md): the current lyric is never truncated. Fit order, bottom-aligned on band B's edge:
 * 1) at most 2 lines of 24 px, next lyric shown; 2) at most 4 lines of 24 px growing up into band M, next hidden; 3) 4 lines of 20 px;
 * 4) 5 lines of 16 px; only text beyond step 4 may end in an ellipsis. Pure layout: music.c and the wire are not involved. */
#define ELL "\xe2\x80\xa6"
static const unsigned kRows[5]={0,2,4,4,5};
static const unsigned kFont[5]={0,TIO_FONT_TITLE,TIO_FONT_TITLE,TIO_FONT_BODY,TIO_FONT_MIN};
static void strip(const char *in,char *out){   /* the text without row breaks and spaces: what must survive a wrap */
 size_t o=0;for(;*in;in++)if(*in!='\n'&&*in!=' ')out[o++]=*in;out[o]=0;}
static unsigned rows_ok(const char *out,unsigned font){   /* every row fits the 460 px core by the firmware's own estimate; returns the row count */
 unsigned rows=0;const char *row=out;for(;;){const char *e=strchr(row,'\n');size_t n=e?(size_t)(e-row):strlen(row);
  assert(n>0&&row[0]!=' '&&row[n-1]!=' ');assert(tm_width(row,n,font)<=TIO_CORE_W);rows++;if(!e)break;row=e+1;}
 return rows;}
/* One case: every invariant of the contract. `expect` is the step the caller knows it lands in, or 0 to only check the contract. */
#define A(c) do{if(!(c)){printf("line %d: %s\n",line,#c);assert(0);}}while(0)
static TMFit check_at(int line,const char *raw,unsigned expect,bool over){
 char buf[TM_CUR_RAW];A(strlen(raw)<sizeof buf);strcpy(buf,raw);tm_clean(buf);
 char out[TM_CUR_CAP];memset(out,0x5a,sizeof out);TMFit f=tm_fit_current(buf,out,sizeof out);A(memchr(out,0,sizeof out));
 A(f.step>=1&&f.step<=4&&f.font==kFont[f.step]);
 const bool ell=strstr(out,ELL)!=NULL;
 A(ell==over&&(!ell||f.step==4));                                    /* an ellipsis only beyond step 4 */
 A(out[0]&&out[strlen(out)-1]!='\n');
 unsigned rows=rows_ok(out,f.font);A(rows==f.lines&&rows<=kRows[f.step]);
 /* The step is the first that holds the text: every earlier step wrapped to more rows than it allows. */
 for(unsigned s=1;s<f.step;s++){char t[TM_CUR_CAP];A(!tm_rows_with(buf,TIO_CORE_W,kFont[s],kRows[s],false,t,sizeof t,tm_advance));}
 if(!ell){char a[TM_CUR_RAW],b[TM_CUR_CAP];strip(buf,a);strip(out,b);A(!strcmp(a,b));}   /* nothing lost, nothing added */
 else {char a[TM_CUR_RAW],b[TM_CUR_CAP];strip(buf,a);strip(out,b);size_t n=strlen(b)-3;A(!strcmp(b+n,ELL)&&!strncmp(a,b,n));}   /* a clean prefix */
 /* The next row is hidden exactly when the lyric needs more than two lines. */
 A(f.next==(f.lines<=2)&&f.next==(f.step==1));
 TIORect r=tm_cur_rect_for(&f);TIOSpan m=tio_band(TIO_SURFACE_PAGE,TIO_BAND_M),b=tio_band(TIO_SURFACE_PAGE,TIO_BAND_B);
 A(r.y+r.h==b.y1&&r.h==(int)f.lines*(int)TIO_LINE(f.font)&&r.x==TIO_CORE_X0&&r.w==TIO_CORE_W);   /* bottom-aligned on y 172, core wide */
 A(r.y>=m.y0&&r.y>=60&&r.y+r.h<=172);                                                      /* inside bands M and B, top no higher than y 60 */
 A(f.next?r.y>=b.y0:(r.y<b.y0||f.lines>2));
 const TIORect nx=tm_next_rect();A(nx.y+nx.h<=m.y1&&nx.y>=m.y0);                         /* the next row lives in M */
 if(f.next)A(nx.y+nx.h<=r.y);                                                              /* and never touches the lyric while shown */
 const TIORect tr=tm_track_rect();A(tr.y+tr.h<=m.y0&&r.y>=m.y0);                           /* the track in T stays clear */
 if(expect&&f.step!=expect){printf("line %d: step %u lines %u, want step %u\n",line,f.step,f.lines,expect);assert(0);}
 return f;
}
#define check(...) check_at(__LINE__,__VA_ARGS__)
/* Text builders. */
static void latin(char *out,unsigned chars,unsigned word){   /* words of `word` letters separated by single spaces, uppercase-free */
 size_t o=0;for(unsigned i=0;i<chars;i++){out[o++]=(i%(word+1))==word?' ':(char)('a'+(i*7+3)%26);}out[o]=0;while(o&&out[o-1]==' ')out[--o]=0;}
static void cjk(char *out,unsigned chars){size_t o=0;for(unsigned i=0;i<chars;i++){unsigned c=0x4e00+(i*37+11)%2000;out[o++]=(char)(0xe0|(c>>12));out[o++]=(char)(0x80|((c>>6)&63));out[o++]=(char)(0x80|(c&63));}out[o]=0;}
static void wide4(char *out,unsigned chars){size_t o=0;for(unsigned i=0;i<chars;i++){unsigned c=0x20000+(i*13)%500;out[o++]=(char)(0xf0|(c>>18));out[o++]=(char)(0x80|((c>>12)&63));out[o++]=(char)(0x80|((c>>6)&63));out[o++]=(char)(0x80|(c&63));}out[o]=0;}
static unsigned lines_of(const char *raw){char buf[TM_CUR_RAW],out[TM_CUR_CAP];strcpy(buf,raw);tm_clean(buf);return tm_fit_current(buf,out,sizeof out).lines;}
int main(void){
 char t[1024];
 /* Geometry the rule rests on. */
 assert(TIO_FONT_TITLE==24&&TIO_FONT_BODY==20&&TIO_FONT_MIN==16&&TIO_LINE(24)==28&&TIO_LINE(20)==24&&TIO_LINE(16)==20);
 assert(tio_band(TIO_SURFACE_PAGE,TIO_BAND_B).y1==172&&tio_band(TIO_SURFACE_PAGE,TIO_BAND_B).y0==112&&tio_band(TIO_SURFACE_PAGE,TIO_BAND_M).y0==56);
 {TMFit f={1,24,4,false};assert(tm_cur_rect_for(&f).y==60);}   /* four 24 px lines reach y 60 */
 for(unsigned s=0;s<TM_CUR_SLOTS;s++){TIORect r=tm_cur_rect(s);assert(r.y+r.h==172&&r.y>=60&&r.w==460&&tm_cur_slot(tm_cur_slot_font(s))==s);}
 /* Chinese: 19 characters per 24 px row, 23 per 20 px row, 28 per 16 px row (the firmware's estimate is one em per glyph). */
 for(unsigned n=1;n<=140;n++){cjk(t,n);bool over=false;unsigned step=n<=38?1:n<=76?2:n<=92?3:n<=140?4:0;(void)over;check(t,step,false);}
 /* Chinese and the 575 byte source bound: 81 characters were all the old 243 byte buffer could hold, 140 is the step 4 limit. */
 cjk(t,140);assert(strlen(t)==420);check(t,4,false);
 cjk(t,141);check(t,4,true);cjk(t,180);check(t,4,true);
 /* Four-byte glyphs reach the 560 byte worst case of step 4: 140 fit, 141 end in an ellipsis. */
 wide4(t,140);assert(strlen(t)==560);check(t,4,false);wide4(t,141);check(t,4,true);
 /* Latin, several word lengths: every length lands somewhere with the whole contract intact; the first ellipsis is at 5 full 16 px rows. */
 for(unsigned word=1;word<=14;word+=(word<6?1:4)){bool seen=false;
  for(unsigned n=1;n<=330;n++){latin(t,n,word);if(!t[0])continue;char b[TM_CUR_RAW],o[TM_CUR_CAP];strcpy(b,t);tm_clean(b);
   (void)tm_fit_current(b,o,sizeof o);bool over=strstr(o,ELL)!=NULL;check(t,0,over);if(over)seen=true;else assert(!seen||word>1);}   /* once it overflows it keeps overflowing */
  assert(seen);}
 /* Latin, hand-picked: one line, two lines (step 1), three and four lines (step 2), five+ (step 3, 4). */
 check("The morning light",1,false);assert(lines_of("The morning light")==1);
 {const char *three="The morning light is falling on the streets we used to know and every window glows";
  TMFit f=check(three,2,false);assert(f.lines==3&&!f.next);}
 {const char *four="The morning light is falling on the streets we used to know and every window glows with the stories of the city";
  TMFit f=check(four,2,false);assert(f.lines==4&&f.font==24);}
 check("The morning light is falling on the streets we used to know and every window glows with the stories of the city we have loved for years",3,false);
 check("The morning light is falling on the streets we used to know and every window glows with the stories of the city we have loved for years and all the nights we sang along until the sun came up over the harbour",4,false);
 {char big[TM_CUR_RAW];size_t o=0;while(o<180)o+=(size_t)snprintf(big+o,sizeof big-o,"%s","walking home ");big[o]=0;TMFit f=check(big,4,false);assert(f.lines<=5);}   /* 180 letters: five 16 px rows, whole */
 {char big[TM_CUR_RAW];size_t o=0;while(o<400)o+=(size_t)snprintf(big+o,sizeof big-o,"%s","walking home ");big[o]=0;check(big,4,true);}
 {char big[TM_CUR_RAW];memset(big,'w',500);big[500]=0;TMFit f=check(big,4,true);assert(f.lines==5);}   /* one 500 letter word: cut at a character, ellipsis */
 {char big[TM_CUR_RAW];size_t o=0;while(o<574)o+=(size_t)snprintf(big+o,sizeof big-o,"%s","no more words ");big[574]=0;check(big,4,true);}   /* past the buffer */
 /* Bad bytes never swallow the tail: CRLF, tabs, zero width spaces, stray continuation bytes. */
 check("hello world\r",1,false);check("a\tb\nc",1,false);check("one\xe2\x80\x8b""two three",1,false);check("bad \x80 byte \xff here",1,false);
 {char b[64]="a\xe2\x80\x8b\r\tb\n c";tm_clean(b);assert(!strcmp(b,"a b  c"));char c2[16]="";tm_clean(c2);assert(!*c2);}
 /* Trailing and repeated spaces: no phantom row. */
 check("The morning light   ",1,false);assert(lines_of("The morning light      ")==1);check("   leading",1,false);
 {char sp[300];memset(sp,'a',40);memset(sp+40,' ',60);memcpy(sp+100,"tail",5);check(sp,0,false);}
 /* Empty and tiny input: one empty row, next shown, nothing breaks. */
 {char out[TM_CUR_CAP];TMFit f=tm_fit_current("",out,sizeof out);assert(!*out&&f.step==1&&f.lines==1&&f.next);f=tm_fit_current("   ",out,sizeof out);assert(!*out&&f.step==1&&f.lines==1);}
 /* Step boundaries: one more character moves a line to the next step; the first character past a step never leaves an ellipsis. */
 {unsigned last=0;for(unsigned n=1;n<=140;n++){cjk(t,n);char o[TM_CUR_CAP];TMFit f=tm_fit_current(t,o,sizeof o);assert(f.step>=last&&!strstr(o,ELL));last=f.step;}}
 /* A mixed Latin and Chinese line, and a capital and wide-letter heavy line. */
 check("I love you \xe6\x88\x91\xe7\x88\xb1\xe4\xbd\xa0 more than \xe4\xb8\x96\xe7\x95\x8c\xe4\xb8\x8a\xe4\xbb\xbb\xe4\xbd\x95\xe4\xba\x8b\xe7\x89\xa9",0,false);
 {char w[300];memset(w,'M',80);w[80]=0;check(w,0,false);memset(w,'W',200);w[200]=0;check(w,4,true);}
 /* Fuzz: random UTF-8 mixes at every length keep the contract (no crash, no overrun, nothing lost below the last step). */
 srand(7);
 for(unsigned it=0;it<4000;it++){size_t o=0,target=(size_t)(rand()%520);
  while(o<target){unsigned k=(unsigned)(rand()%10);
   if(k<5){t[o++]=(char)('a'+rand()%26);}else if(k<7){t[o++]=' ';}else if(k==7){t[o++]=(char)('A'+rand()%26);}
   else if(k==8){unsigned c=0x4e00+(unsigned)(rand()%2000);t[o++]=(char)(0xe0|(c>>12));t[o++]=(char)(0x80|((c>>6)&63));t[o++]=(char)(0x80|(c&63));}
   else {unsigned c=0xe0+(unsigned)(rand()%30);t[o++]=(char)(0xc0|(c>>6));t[o++]=(char)(0x80|(c&63));}}
  t[o]=0;if(o>TM_CUR_RAW-1)t[TM_CUR_RAW-1]=0;
  char b[TM_CUR_RAW],out[TM_CUR_CAP];strcpy(b,t);tm_clean(b);if(!b[0])continue;
  TMFit f=tm_fit_current(b,out,sizeof out);bool over=strstr(out,ELL)!=NULL;
  /* skip lines made only of spaces: no row to count */
  bool any=false;for(char *p=b;*p;p++)if(*p!=' ')any=true;if(!any)continue;
  check(b,0,over);(void)f;}
 /* The next lyric keeps its one line ellipsis. */
 {char one[244];tm_one_line("Streets of gold and silver rivers running through the evening light of every city we have ever known",TIO_CORE_W,TM_NEXT_FONT,one,sizeof one);
  assert(!strchr(one,'\n')&&strstr(one,ELL)&&tm_width(one,strlen(one),TM_NEXT_FONT)<=TIO_CORE_W);
  tm_one_line("short",TIO_CORE_W,TM_NEXT_FONT,one,sizeof one);assert(!strcmp(one,"short"));tm_one_line("",TIO_CORE_W,TM_NEXT_FONT,one,sizeof one);assert(!*one);
  cjk(t,60);tm_one_line(t,TIO_CORE_W,TM_NEXT_FONT,one,sizeof one);assert(!strchr(one,'\n')&&strstr(one,ELL)&&tm_width(one,strlen(one),TM_NEXT_FONT)<=TIO_CORE_W);
  /* A two row 24 px lyric still shows the next lyric, a three row lyric does not (the service hides the row on fit.next). */
  assert(check("The morning light is falling on the streets we used to know",1,false).next);
  assert(!check("The morning light is falling on the streets we used to know and every window glows",2,false).next);}
 printf("PASS tmg8 lyrics: 4 fit steps, Latin and Chinese, ellipsis only beyond step 4, next row hidden past 2 lines, inside bands M and B\n");
 return 0;
}
