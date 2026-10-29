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
