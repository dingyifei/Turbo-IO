#import <Foundation/Foundation.h>
#include "TIODesign.inc"
/* Host test (no UIKit): the token tables compiled into TIODesign.h/.m, which
 * are expanded from TIODesign.inc, must equal docs/design-system/tokens.json
 * row for row and in both directions. argv[1] is the path to tokens.json. */

static int failures=0;
#define CHECK(cond,...) do{if(!(cond)){failures++;fprintf(stderr,"FAIL line %d: ",__LINE__);fprintf(stderr,__VA_ARGS__);fputc('\n',stderr);}}while(0)

static uint32_t Hex(NSString *s){
 CHECK([s hasPrefix:@"#"]&&s.length==7,"bad hex %s",s.UTF8String);
 unsigned v=0;[[NSScanner scannerWithString:[s substringFromIndex:1]] scanHexInt:&v];return v;
}
static NSArray<NSNumber *> *Numbers(NSString *value){
 NSMutableArray *out=[NSMutableArray new];
 for(NSString *part in [value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]){
  if(!part.length)continue;
  NSString *t=[part hasSuffix:@"px"]?[part substringToIndex:part.length-2]:part;
  [out addObject:@(t.doubleValue)];
 }
 return out;
}
static BOOL Near(double a,double b){return fabs(a-b)<1e-9;}
/* WCAG relative luminance and contrast of sRGB hex colors; `over` blends a color at `alpha` onto an opaque background. */
static double Lin(double c){return c<=0.04045?c/12.92:pow((c+0.055)/1.055,2.4);}
static double Lum(uint32_t h){return 0.2126*Lin(((h>>16)&255)/255.0)+0.7152*Lin(((h>>8)&255)/255.0)+0.0722*Lin((h&255)/255.0);}
static double Ratio(uint32_t a,uint32_t b){double x=Lum(a),y=Lum(b);if(x<y){double t=x;x=y;y=t;}return (x+0.05)/(y+0.05);}
static uint32_t Over(uint32_t fg,double alpha,uint32_t bg){uint32_t out=0;for(int s=16;s>=0;s-=8){double f=(fg>>s)&255,b=(bg>>s)&255;out|=(uint32_t)lround(f*alpha+b*(1-alpha))<<s;}return out;}

#define COLOR_ROW(Id,name,light,dark) {name,light,dark},
static const struct {const char *name;uint32_t light,dark;} Colors[]={TIO_DESIGN_COLORS(COLOR_ROW)};
#define TYPE_ROW(Id,name,size,line,weight,tracking) {name,size,line,weight,tracking},
static const struct {const char *name;double size,line;int weight;double tracking;} Types[]={TIO_DESIGN_TYPES(TYPE_ROW)};
#define N1_ROW(Id,name,value) {name,(value),0,0},
#define N2_ROW(name,A,a,B,b) {name,(a),(b),1},
static const struct {const char *name;double a,b;int pair;} Numbers_[]={TIO_DESIGN_NUMBERS_1(N1_ROW) TIO_DESIGN_NUMBERS_2(N2_ROW)};

int main(int argc,char **argv){
 @autoreleasepool{
  if(argc<2){fprintf(stderr,"usage: TIODesignTests tokens.json\n");return 2;}
  NSData *data=[NSData dataWithContentsOfFile:@(argv[1])];
  NSDictionary *json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
  if(!json){fprintf(stderr,"cannot read tokens.json\n");return 2;}

  /* Colors */
  NSArray *colors=json[@"color"][@"tokens"];
  CHECK(colors.count==sizeof Colors/sizeof *Colors,"color count json=%lu compiled=%zu",(unsigned long)colors.count,sizeof Colors/sizeof *Colors);
  NSMutableSet *seen=[NSMutableSet new];
  for(NSDictionary *token in colors){
   NSString *name=token[@"name"];BOOL found=NO;
   for(size_t i=0;i<sizeof Colors/sizeof *Colors;i++){
    if(strcmp(Colors[i].name,name.UTF8String))continue;
    found=YES;[seen addObject:name];
    id value=token[@"value"];
    uint32_t light=[value isKindOfClass:NSDictionary.class]?Hex(value[@"light"]):Hex(value);
    uint32_t dark=[value isKindOfClass:NSDictionary.class]?Hex(value[@"dark"]):light;
    CHECK(Colors[i].light==light,"%s light %06x != %06x",Colors[i].name,Colors[i].light,light);
    CHECK(Colors[i].dark==dark,"%s dark %06x != %06x",Colors[i].name,Colors[i].dark,dark);
    if(![value isKindOfClass:NSDictionary.class])CHECK(Colors[i].light==Colors[i].dark,"%s must be fixed",Colors[i].name);
   }
   CHECK(found,"color %s missing from compiled table",name.UTF8String);
  }
  CHECK(seen.count==sizeof Colors/sizeof *Colors,"compiled colors not all in tokens.json");

  /* Contrast of the pairings TIODesign.m builds, in both themes: status pills (label over the 15% tint or bg-sunken, 4.5:1 for the
   * 13 pt word; the status symbol 3:1 for graphics) and the filled destructive button (on-accent over status-danger, 4.5:1 for the
   * 17 pt semibold title). The pill sits on bg-raised (hub card) and on bg (OTA summary, sheets). */
  {
   uint32_t lo[2],hi[2];
   #define PAIR(want,ix) for(size_t i=0;i<sizeof Colors/sizeof *Colors;i++)if(!strcmp(Colors[i].name,want)){lo[ix]=Colors[i].light;hi[ix]=Colors[i].dark;}
   enum {Bg,Raised,Sunken,Label,Secondary,Ok,Warn,Danger,OnAccent,Count};
   uint32_t tl[Count],td[Count];
   const char *names[Count]={"bg","bg-raised","bg-sunken","label","label-secondary","status-ok","status-warn","status-danger","on-accent"};
   for(int k=0;k<Count;k++){PAIR(names[k],0);tl[k]=lo[0];td[k]=hi[0];}
   for(int theme=0;theme<2;theme++){
    const uint32_t *t=theme?td:tl;const char *tn=theme?"dark":"light";
    for(int status=Ok;status<=Danger;status++)for(int surface=0;surface<2;surface++){
     uint32_t base=t[surface?Raised:Bg],tint=Over(t[status],0.15,base);
     CHECK(Ratio(t[Label],tint)>=4.5,"pill word: label on %s tint over %s (%s) %.2f:1",names[status],surface?"bg-raised":"bg",tn,Ratio(t[Label],tint));
     CHECK(Ratio(t[status],tint)>=3.0,"pill symbol: %s on its tint over %s (%s) %.2f:1",names[status],surface?"bg-raised":"bg",tn,Ratio(t[status],tint));
    }
    CHECK(Ratio(t[Label],t[Sunken])>=4.5,"neutral pill word: label on bg-sunken (%s) %.2f:1",tn,Ratio(t[Label],t[Sunken]));
    CHECK(Ratio(t[Secondary],t[Sunken])>=3.0,"neutral pill symbol: label-secondary on bg-sunken (%s) %.2f:1",tn,Ratio(t[Secondary],t[Sunken]));
    CHECK(Ratio(t[OnAccent],t[Danger])>=4.5,"filled destructive button: on-accent on status-danger (%s) %.2f:1",tn,Ratio(t[OnAccent],t[Danger]));
   }
  }

  /* Phone text styles */
  NSArray *styles=json[@"type"][@"groups"][0][@"styles"];
  CHECK(styles.count==sizeof Types/sizeof *Types,"type count json=%lu compiled=%zu",(unsigned long)styles.count,sizeof Types/sizeof *Types);
  for(NSDictionary *style in styles){
   NSString *name=style[@"name"];BOOL found=NO;
   for(size_t i=0;i<sizeof Types/sizeof *Types;i++){
    if(strcmp(Types[i].name,name.UTF8String))continue;
    found=YES;
    CHECK(Near(Types[i].size,[Numbers(style[@"fontSize"]).firstObject doubleValue]),"%s size",Types[i].name);
    CHECK(Near(Types[i].line,[Numbers(style[@"lineHeight"]).firstObject doubleValue]),"%s line height",Types[i].name);
    CHECK(Types[i].weight==[style[@"fontWeight"] intValue],"%s weight",Types[i].name);
    CHECK(Near(Types[i].tracking,[Numbers(style[@"letterSpacing"]).firstObject doubleValue]),"%s tracking",Types[i].name);
   }
   CHECK(found,"text style %s missing",name.UTF8String);
  }

  /* Numbers: spacing, radius, size, lens geometry and the glasses type ramp. */
  NSMutableDictionary<NSString *,NSArray<NSNumber *> *> *expected=[NSMutableDictionary new];
  for(NSString *group in @[@"spacing",@"radius",@"size",@"lens"])
   for(NSDictionary *token in json[group][@"tokens"])expected[token[@"name"]]=Numbers(token[@"value"]);
  for(NSDictionary *style in json[@"type"][@"groups"][1][@"styles"])
   expected[style[@"name"]]=@[Numbers(style[@"fontSize"]).firstObject,Numbers(style[@"lineHeight"]).firstObject];
  CHECK(expected.count==sizeof Numbers_/sizeof *Numbers_,"number count json=%lu compiled=%zu",(unsigned long)expected.count,sizeof Numbers_/sizeof *Numbers_);
  for(size_t i=0;i<sizeof Numbers_/sizeof *Numbers_;i++){
   NSString *name=@(Numbers_[i].name);NSArray<NSNumber *> *want=expected[name];
   CHECK(want!=nil,"compiled number %s not in tokens.json",Numbers_[i].name);
   if(!want)continue;
   CHECK(want.count==(Numbers_[i].pair?2u:1u),"%s arity",Numbers_[i].name);
   CHECK(Near(Numbers_[i].a,want[0].doubleValue),"%s first %g != %g",Numbers_[i].name,Numbers_[i].a,want[0].doubleValue);
   if(Numbers_[i].pair&&want.count==2)CHECK(Near(Numbers_[i].b,want[1].doubleValue),"%s second %g != %g",Numbers_[i].name,Numbers_[i].b,want[1].doubleValue);
  }
 }
 if(failures){fprintf(stderr,"%d failure(s)\n",failures);return 1;}
 puts("PASS");return 0;
}
