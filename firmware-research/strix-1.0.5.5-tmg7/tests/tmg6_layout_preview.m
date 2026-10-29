// Production view geometry/raster and lyric fit; macOS font is a preview surrogate.
#import <AppKit/AppKit.h>
#include "../src/navigation-runtime-v1/nav_view.h"
#include "../src/navigation-runtime-v1/nav_text.h"
#include "../src/music-runtime-v1/music.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
typedef struct {int x,y,w,h;unsigned font;bool shown,clip;const char *text;const uint8_t *pixels;} Widget;
typedef struct {Widget w[16];unsigned count;bool busy;} Host;
static unsigned language;
unsigned tio_lang(void){return language;}
static bool idle(void *p){return !((Host *)p)->busy;}
static void *create(void *p,void *parent){assert(parent);Host *h=p;assert(h->count<16);Widget *w=&h->w[h->count++];w->shown=true;return w;}
static void *label(void *p,void *parent,unsigned font){Widget *w=create(p,parent);w->font=font;return w;}
static void place(void *p,void *o,int x,int y,int w,int h){(void)p;assert(x>=0&&y>=0&&x+w<=540&&y+h<=180);Widget *v=o;v->x=x;v->y=y;v->w=w;v->h=h;}
static void buffer(void *p,void *o,const uint8_t *pixels,unsigned w,unsigned h){(void)p;Widget *v=o;assert(v->w==(int)w&&v->h==(int)h);v->pixels=pixels;}
static void text(void *p,void *o,const char *s){(void)p;((Widget *)o)->text=s;}
static void visible(void *p,void *o,bool show){(void)p;((Widget *)o)->shown=show;}
static void destroy(void *p,void *o){(void)p;((Widget *)o)->shown=false;}
static void cliptext(void *p,void *o){(void)p;((Widget *)o)->clip=true;}
static void Save(Host *host,NSString *path){
 NSImage *im=[[NSImage alloc]initWithSize:NSMakeSize(540,180)];[im lockFocusFlipped:YES];[NSColor.blackColor setFill];NSRectFill(NSMakeRect(0,0,540,180));
 for(unsigned i=1;i<host->count;i++){Widget *w=&host->w[i];if(!w->shown)continue;NSRect rect=NSMakeRect(w->x,w->y,w->w,w->h);
  [NSGraphicsContext saveGraphicsState];NSRectClip(rect);
  if(w->pixels){NSBitmapImageRep *b=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:w->w pixelsHigh:w->h bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w->w*3 bitsPerPixel:24];for(int y=0;y<w->h;y++)for(int x=0;x<w->w;x++){uint8_t *d=b.bitmapData+y*b.bytesPerRow+x*3;d[0]=d[2]=0;d[1]=w->pixels[y*w->w+x];}NSImage *tile=[[NSImage alloc]initWithSize:NSMakeSize(w->w,w->h)];[tile addRepresentation:b];[tile drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:nil];}
  if(w->text&&*w->text){NSString *s=[NSString stringWithUTF8String:w->text];assert(s);NSMutableParagraphStyle *ps=[NSMutableParagraphStyle new];ps.lineBreakMode=NSLineBreakByClipping;
   [s drawInRect:rect withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:w->font],NSForegroundColorAttributeName:[NSColor colorWithRed:0 green:1 blue:0 alpha:1],NSParagraphStyleAttributeName:ps}];}
  [NSGraphicsContext restoreGraphicsState];
 }
 [im unlockFocus];NSBitmapImageRep *rep=[NSBitmapImageRep imageRepWithData:im.TIFFRepresentation];assert([[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]);
}
static void Put16(uint8_t *p,int n){p[0]=n;p[1]=n>>8;}
static void Nav(NSString *dir,bool zh,bool longer){
 language=zh;Host host={0};TNWidgets api={&host,idle,create,create,label,place,buffer,text,visible,destroy,cliptext};TNView *v=calloc(1,sizeof *v);assert(v);TNScene semantic={.icon=TN_RIGHT,.distance_m=100,.remaining_m=1200,.remaining_s=600};strcpy(semantic.turn,zh?"前方右转":"Turn right");assert(tn_view_open(v,&api,&host,&semantic));
 uint8_t scene[104]={1,0,0,0};Put16(scene+4,320);scene[6]=4;scene[8]=11;unsigned counts[]={2,2,2,5},styles[]={0,1,4,6};for(unsigned i=0;i<4;i++){scene[16+8*i]=counts[i];scene[18+8*i]=styles[i];}
 int16_t pts[]={-600,240,600,240,300,-160,300,600,-300,200,300,600,0,0,0,160,160,160,160,320,320,320};for(unsigned i=0;i<22;i++)Put16(scene+48+i*2,pts[i]);scene[92]=1;
 assert(tn_view_map(v,TNR_SCENE2,scene,sizeof scene,0));uint8_t name[224]={1,0,0,0};const char *s=zh?"经过 南京西路与人民广场连接道路":"Passing Martin Luther King Junior Boulevard";if(longer)s=zh?"经过 南京西路人民广场世纪公园文化中心滨江国际会议展览中心连接道路历史文化保护区城市公共交通枢纽":"Passing Martin Luther King Junior Boulevard Near the International Conference and Exhibition Center";size_t len=strlen(s);name[4]=len;memcpy(name+8,s,len);
 uint8_t *breakBits=name+200;NSString *nativeName=[NSString stringWithUTF8String:s];[nativeName enumerateSubstringsInRange:NSMakeRange(0,nativeName.length) options:NSStringEnumerationByWords usingBlock:^(NSString *word,NSRange range,NSRange all,BOOL *stop){NSUInteger end=[[nativeName substringToIndex:NSMaxRange(range)] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];breakBits[end/8]|=1u<<(end%8);}];name[200+len/8]|=1u<<(len%8);
 assert(tn_view_map(v,TNR_PASSING,name,sizeof name,0));assert(tn_view_map_tick(v,0));assert(tn_view_clock(v,946684800+10*3600,946684800+10*3600+600,false));
 unsigned shown=0;for(unsigned i=0;i<3;i++){Widget *w=v->map_text[i];if(w->shown){shown++;assert(w->x==8&&w->y==2&&w->clip);assert(tn_text_width(w->text,strlen(w->text),w->font)<=524);}}assert(shown==1);
 Widget *scale=v->map_text[3];assert(scale->shown&&scale->font==16&&!strcmp(scale->text,"100 m"));
 unsigned before=host.count;for(unsigned heading=0;heading<360;heading++){uint8_t pose[14]={1,0,0,0};Put16(pose+8,heading);assert(tn_view_map(v,TNR_POSE2,pose,sizeof pose,heading+1));assert(tn_view_map_tick(v,heading+1));assert(host.count==before);const uint8_t *raster=((Widget *)v->map)->pixels;assert(raster[87*192+96]>=250&&raster[109*192+104]>=250);for(unsigned i=0;i<3;i++)assert(((Widget *)v->map_text[i])->y==2);}
 uint8_t pose[14]={1,0,0,0};assert(tn_view_map(v,TNR_POSE2,pose,sizeof pose,5000));assert(tn_view_map_tick(v,6000));
 const uint8_t *pixels=((Widget *)v->map)->pixels;unsigned road=0,route=0;for(unsigned i=0;i<192*144;i++){road+=pixels[i]==140;route+=pixels[i]==255;}assert(road&&route);double roadLight=pow((140.0/255+0.055)/1.055,2.4)*0.7152;double contrast=(0.7152+0.05)/(roadLight+0.05);assert(contrast>3.2);printf("route/brightest road green-channel contrast %.3f:1; route/black halo %.3f:1\n",contrast,(0.7152+0.05)/0.05);
 Save(&host,[dir stringByAppendingPathComponent:longer?(zh?@"nav-long-zh.png":@"nav-long-en.png"):(zh?@"nav-zh.png":@"nav-en.png")]);assert(tn_view_close(v));free(v);
}
static void Lyrics(NSString *dir,bool zh){Host host={0};create(&host,&host);char lines[3][244];const char *raw=zh?"沿着熟悉的街道慢慢走过每一个曾经相遇的地方在清晨再次回想起那些温暖的故事":"The morning light is falling on the streets we used to know";
 for(unsigned i=0;i<3;i++){TMLyricSlot slot=tm_lyric_slot(i);if(i)assert(tm_lyric_slot(i-1).top+tm_lyric_slot(i-1).height<=slot.top);assert(slot.top+slot.height<=154);
  tn_text_two_lines(raw,366,slot.font,lines[i],sizeof lines[i]);Widget *w=label(&host,&host,slot.font);place(&host,w,166,slot.top,366,slot.height);text(&host,w,lines[i]);cliptext(&host,w);unsigned count=1;char *start=lines[i];for(char *c=lines[i];;c++)if(*c=='\n'||!*c){assert(tn_text_width(start,c-start,slot.font)<=366);if(!*c)break;count++;start=c+1;}assert(count<=2);}
 Widget *control=label(&host,&host,14);place(&host,control,166,154,366,24);text(&host,control,zh?"滚轮：切歌 · 轻触：暂停":"Wheel: previous / next · Tap: pause");Save(&host,[dir stringByAppendingPathComponent:zh?@"lyrics-zh.png":@"lyrics-en.png"]);
}
int main(int argc,char **argv){@autoreleasepool{assert(argc==2);NSString *dir=[NSString stringWithUTF8String:argv[1]];assert([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]);Nav(dir,false,false);Nav(dir,true,false);Nav(dir,false,true);Nav(dir,true,true);Lyrics(dir,false);Lyrics(dir,true);puts("PASS production nav layout, fixed labels at 360 headings, scale font, EN/ZH two-line lyric slots; preview typography uses macOS surrogate fonts");}return 0;}
