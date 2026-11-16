#import "GlassesBench.h"
#import "TIOLanguage.h"

#pragma mark Lyrics

NSArray<NSDictionary *> *TGBLyricFixtures(void){
 static NSArray *fixtures;static dispatch_once_t once;
 dispatch_once(&once,^{
  NSMutableArray *list=[NSMutableArray new];
#define TGB_FIXTURE(id_,lang,step,lines,ell,nextEll,current,next) \
  [list addObject:@{@"id":@#id_,@"lang":@lang,@"step":@(step),@"lines":@(lines),@"ellipsis":@(ell),@"nextEllipsis":@(nextEll), \
                    @"current":[NSString stringWithUTF8String:current],@"next":[NSString stringWithUTF8String:next]}];
  TGB_LYRICS(TGB_FIXTURE)
#undef TGB_FIXTURE
  fixtures=[list copy];
 });
 return fixtures;
}

NSString *TGBClipText(NSString *text,NSUInteger maxBytes){
 if(![text isKindOfClass:NSString.class])return @"";
 text=[[text componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet]componentsJoinedByString:@" "];
 NSMutableString *clipped=[NSMutableString new];__block NSUInteger used=0;
 [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *piece,NSRange r,NSRange all,BOOL *stop){
  NSUInteger n=[piece lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  if(used+n>maxBytes){*stop=YES;return;}
  [clipped appendString:piece];used+=n;
 }];
 return clipped;
}

NSArray<NSDictionary *> *TGBLyricRows(NSDictionary *fixture){
 return @[@{@"ms":@0,@"text":TGBClipText(fixture[@"current"],TGB_LYRIC_CAP)},
          @{@"ms":@(TGB_LYRIC_NEXT_MS),@"text":TGBClipText(fixture[@"next"],TGB_LYRIC_CAP)}];
}

NSArray<NSDictionary *> *TGBDemoSongRows(void){
 NSArray *keys=@[@"bench.music.line1",@"bench.music.line2",@"bench.music.line3"];NSMutableArray *rows=[NSMutableArray new];
 for(NSUInteger i=0;i<keys.count;i++)[rows addObject:@{@"ms":@(i*60000u),@"text":TGBClipText(TIOText(keys[i]),TGB_LYRIC_CAP)}];
 return rows;
}

#pragma mark Dashboard card

typedef struct{__unsafe_unretained NSString *ident;unsigned min,max,step;} TGBCardRule;
/* Steps and ranges of the editor. The wire allows more (percent 0...100, totals up to 99999); these cover real Macs and keep the text short. */
static const TGBCardRule CardRules[TGBCardFieldCount]={
 {@"weekly",0,100,5},{@"claude5h",0,100,5},{@"claudeWeek",0,100,5},
 {@"ramFree",0,2560,10},{@"ramTotal",160,2560,160},{@"diskFree",0,8000,100},{@"diskTotal",500,8000,500},
 {@"icon1",0,2,1},{@"icon2",0,2,1},{@"icon3",0,2,1}};

static unsigned *Slot(DCValues *v,TGBCardField f){
 switch(f){
  case TGBCardFieldWeekly:return &v->weekly;case TGBCardFieldClaude5h:return &v->claude5h;case TGBCardFieldClaudeWeek:return &v->claudeWeek;
  case TGBCardFieldRamFree:return &v->ramFree;case TGBCardFieldRamTotal:return &v->ramTotal;
  case TGBCardFieldDiskFree:return &v->diskFree;case TGBCardFieldDiskTotal:return &v->diskTotal;
  case TGBCardFieldIcon1:return &v->icons[0];case TGBCardFieldIcon2:return &v->icons[1];case TGBCardFieldIcon3:return &v->icons[2];
  case TGBCardFieldCount:break;
 }
 return NULL;
}

NSArray<NSString *> *TGBCardPresetIDs(void){return @[@"typical",@"three100",@"empty"];}
BOOL TGBCardPreset(NSString *preset,DCValues *out){
 if(!out)return NO;
 /* typical: the Developer dashboard demo. three100: every percent at 100 (the widest numbers). empty: zeros everywhere a zero is legal. */
 if([preset isEqual:@"typical"])*out=(DCValues){99,90,85,375,1280,1400,2000,{0,1,2}};
 else if([preset isEqual:@"three100"])*out=(DCValues){100,100,100,375,1280,1400,2000,{0,1,2}};
 else if([preset isEqual:@"empty"])*out=(DCValues){0,0,0,0,1280,0,2000,{0,0,0}};
 else return NO;
 return YES;
}

NSString *TGBCardText(const DCValues *v){
 if(!v)return nil;
 NSString *text=[NSString stringWithFormat:@"TDC1;%u;%u;%u;%u;%u;%u;%u;%u;%u;%u",v->weekly,v->claude5h,v->claudeWeek,v->ramFree,v->ramTotal,v->diskFree,v->diskTotal,v->icons[0],v->icons[1],v->icons[2]];
 NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];DCValues check;
 return data.length<=TGB_CARD_BYTES_MAX&&dc_parse(data.bytes,data.length,&check)?text:nil;
}

unsigned TGBCardGet(const DCValues *v,TGBCardField f){if(!v)return 0;DCValues copy=*v;unsigned *slot=Slot(&copy,f);return slot?*slot:0;}

BOOL TGBCardStep(DCValues *v,TGBCardField f,int direction){
 if(!v||!direction||f>=TGBCardFieldCount)return NO;
 unsigned *slot=Slot(v,f);if(!slot)return NO;
 const TGBCardRule rule=CardRules[f];unsigned value=*slot,low=rule.min,high=rule.max;
 if(f==TGBCardFieldRamFree)high=MIN(high,v->ramTotal);
 if(f==TGBCardFieldDiskFree)high=MIN(high,v->diskTotal);
 if(f==TGBCardFieldRamTotal)low=MAX(low,v->ramFree);
 if(f==TGBCardFieldDiskTotal)low=MAX(low,v->diskFree);
 unsigned next;
 if(direction>0){if(value>=high)return NO;next=MIN(high,value+rule.step);}
 else{if(value<=low)return NO;next=value>rule.step&&value-rule.step>low?value-rule.step:low;}
 *slot=next;return YES;
}

NSString *TGBCardFieldID(TGBCardField f){return f<TGBCardFieldCount?CardRules[f].ident:@"";}
NSString *TGBCardFieldTitleKey(TGBCardField f){return [@"bench.card.field." stringByAppendingString:TGBCardFieldID(f)];}

static NSString *Tenths(unsigned n){return n%10?[NSString stringWithFormat:@"%u.%u",n/10,n%10]:[NSString stringWithFormat:@"%u",n/10];}
NSString *TGBCardFieldText(const DCValues *v,TGBCardField f){
 unsigned n=TGBCardGet(v,f);
 switch(f){
  case TGBCardFieldWeekly:case TGBCardFieldClaude5h:case TGBCardFieldClaudeWeek:return [NSString stringWithFormat:@"%u%%",n];
  case TGBCardFieldRamFree:case TGBCardFieldRamTotal:return [Tenths(n) stringByAppendingString:@" GB"];
  case TGBCardFieldDiskFree:case TGBCardFieldDiskTotal:return [Tenths(n/100) stringByAppendingString:@" TB"];
  default:return [NSString stringWithFormat:@"%u",n];
 }
}

#pragma mark Pomodoro and position

NSString *TGBClockText(uint32_t ms){uint32_t s=ms/1000;return [NSString stringWithFormat:@"%u:%02u",s/60,s%60];}
