#ifndef TURBO_NAV_TEXT_H
#define TURBO_NAV_TEXT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
/* Bounded Unicode decoding; stock font advances are conservatively bounded,
 * never inferred from an unverified lv_font_t ABI. Callers clip final labels. */
static inline unsigned tn_text_unit(const char *s,size_t n,uint32_t *cp){
 if(!n)return 0;unsigned a=(uint8_t)s[0],k=a<128?1:a>=0xc2&&a<=0xdf?2:a>=0xe0&&a<=0xef?3:a>=0xf0&&a<=0xf4?4:0;
 if(!k||k>n)return 0;uint32_t c=a&(k==1?127:k==2?31:k==3?15:7);
 for(unsigned i=1;i<k;i++){unsigned b=(uint8_t)s[i];if((b&192)!=128)return 0;c=(c<<6)|(b&63);}
 if(c<(k==1?0u:k==2?128u:k==3?2048u:65536u)||c>0x10ffff||(c>=0xd800&&c<=0xdfff)||c<32||(c>=127&&c<=159)||(c>=0x200b&&c<=0x200f)||(c>=0x202a&&c<=0x202e)||(c>=0x2060&&c<=0x206f)||(c>=0xfff0&&c<=0xffff))return 0;
 *cp=c;return k;
}
static inline unsigned tn_text_advance(uint32_t c,unsigned font){
 if(c>=128||c=='W'||c=='M'||c=='w'||c=='m'||c=='@')return font;
 return (font*3+3)/4; /* generous Latin bound, including punctuation/spacing */
}
static inline unsigned tn_text_width(const char *s,size_t n,unsigned font){
 unsigned w=0;for(size_t i=0;i<n;){uint32_t c;unsigned k=tn_text_unit(s+i,n-i,&c);if(!k)return UINT32_MAX;w+=tn_text_advance(c,font);i+=k;}return w;
}
/* break bits identify byte offsets after complete words, supplied by the phone's
 * Unicode word segmentation. No truncation at a guessed CJK character boundary. */
static inline unsigned tn_text_fit(const char *s,size_t n,const uint8_t *breaks,unsigned width,char *out,size_t cap){
 if(!out||cap<4||n>191||tn_text_width(s,n,14)==UINT32_MAX)return 0;
 unsigned font=18;while(font>14&&tn_text_width(s,n,font)>width)font-=2;
 if(tn_text_width(s,n,font)<=width&&n<cap){memcpy(out,s,n);out[n]=0;return font;}
 size_t best=0;for(size_t i=1;i<=n;i++)if(breaks&&(breaks[i/8]&(1u<<(i%8)))&&i+4<=cap&&tn_text_width(s,i,font)+font<=width)best=i;
 while(best&&s[best-1]==' ')best--;memcpy(out,s,best);memcpy(out+best,"\xe2\x80\xa6",4);return font;
}
/* Lyrics have at most two explicit lines. UTF-8 characters may wrap when a
 * single lyric token is wider than a line; excess text ends with an ellipsis. */
static inline void tn_text_two_lines(const char *s,unsigned width,unsigned font,char *out,size_t cap){
 size_t n=0;while(n<243&&s[n])n++;size_t at=0,used=0;if(!cap)return;out[0]=0;
 for(unsigned row=0;row<2&&at<n;row++){
  while(at<n&&s[at]==' ')at++;size_t end=at,last=at;unsigned w=0;
  while(end<n){uint32_t c;unsigned k=tn_text_unit(s+end,n-end,&c);if(!k)break;unsigned a=tn_text_advance(c,font);if(w+a>width)break;w+=a;end+=k;if(c==' '||c>=0x2e80)last=end;}
  bool more=end<n;if(more&&last>at)end=last;
  if(row==1&&more){while(end>at&&tn_text_width(s+at,end-at,font)+font>width){size_t prev=end-1;while(prev>at&&((uint8_t)s[prev]&192)==128)prev--;end=prev;}}
  while(end>at&&s[end-1]==' ')end--;size_t count=end-at;if(!count)break;
  if(used+count+5>cap)break;memcpy(out+used,s+at,count);used+=count;at=end;
  if(row==1&&more){memcpy(out+used,"\xe2\x80\xa6",3);used+=3;break;}
  if(at<n&&row==0)out[used++]='\n';
 }
 out[used]=0;
}
#endif
