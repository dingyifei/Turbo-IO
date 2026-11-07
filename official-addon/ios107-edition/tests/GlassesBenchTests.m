// Fixture builders of the Glasses test bench (GlassesBench.m): the 240 B lyric clip, the 120 B dashboard card cap, value ranges and the
// card editor's stepping rules, Chinese lyric lengths, and that the demo text never depends on the phone's language.
// The layout each lyric fixture lands in is checked against the firmware's own wrapping in tests/GlassesBenchLayout_test.c.
#import "GlassesBench.h"
#import "TIOLanguage.h"
#include "card.h"
#include <assert.h>
#include <stdio.h>

static NSUInteger Bytes(NSString *s){return [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];}
static NSUInteger Chars(NSString *s){__block NSUInteger n=0;[s enumerateSubstringsInRange:NSMakeRange(0,s.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *c,NSRange r,NSRange e,BOOL *stop){n++;}];return n;}
static NSUInteger Han(NSString *s){NSUInteger n=0;for(NSUInteger i=0;i<s.length;i++){unichar c=[s characterAtIndex:i];if(c>=0x4E00&&c<=0x9FFF)n++;}return n;}
static NSDictionary *Fixture(NSString *ident){for(NSDictionary *f in TGBLyricFixtures())if([f[@"id"] isEqual:ident])return f;assert(0);return nil;}

static void ClipTests(void){
 assert([TGBClipText(@"hello",240) isEqual:@"hello"]);
 assert([TGBClipText(@"hello",3) isEqual:@"hel"]);
 assert([TGBClipText(nil,240) isEqual:@""]&&[TGBClipText((id)@7,240) isEqual:@""]);
 assert([TGBClipText(@"a\tb\nc\r\n",240) isEqual:@"a b c  "]);                 // control characters become spaces, like MusicBridge
 // Never cuts inside a character: three-byte Han, four-byte emoji, a flag (two code points, one character).
 NSString *han=@"歌歌歌歌";assert([TGBClipText(han,7) isEqual:@"歌歌"]&&Bytes(TGBClipText(han,8))==6);
 NSString *emoji=@"a😀b";assert([TGBClipText(emoji,2) isEqual:@"a"]&&[TGBClipText(emoji,5) isEqual:@"a😀"]);
 NSString *flag=@"x🇨🇳y";assert([TGBClipText(flag,8) isEqual:@"x"]&&[TGBClipText(flag,9) isEqual:@"x🇨🇳"]);   // one composed character of 8 bytes
 for(NSUInteger max=0;max<40;max++){NSString *c=TGBClipText(@"Turbo 歌词 😀 test",max);assert(Bytes(c)<=max&&[c dataUsingEncoding:NSUTF8StringEncoding]!=nil);}
}

static void LyricTests(void){
 NSArray *fixtures=TGBLyricFixtures();
 NSArray *expect=@[@"en3",@"en4",@"en4s",@"en5",@"enell",@"ennext",@"zh3",@"zh4"];
 assert(fixtures.count==expect.count);
 for(NSUInteger i=0;i<fixtures.count;i++)assert([fixtures[i][@"id"] isEqual:expect[i]]);
 TIOSetUILanguageOverride(@"zh");NSArray *zhUI=TGBLyricFixtures();NSArray *zhRows=TGBLyricRows(Fixture(@"en3"));
 TIOSetUILanguageOverride(@"en");
 assert([zhUI isEqual:TGBLyricFixtures()]);                                      // the fixtures are the same in every UI language
 assert([zhRows isEqual:TGBLyricRows(Fixture(@"en3"))]);
 for(NSDictionary *f in fixtures){
  NSArray *rows=TGBLyricRows(f);
  assert(rows.count==2&&[rows[0][@"ms"] unsignedIntValue]==0&&[rows[1][@"ms"] unsignedIntValue]==TGB_LYRIC_NEXT_MS);
  assert(TGB_LYRIC_POSITION_MS<TGB_LYRIC_NEXT_MS&&TGB_LYRIC_NEXT_MS<TGB_LYRIC_DURATION_MS);   // paused at 0:05: the first line is the current one
  for(NSDictionary *row in rows){                                               // every line is clipped to the 240 B cap
   NSString *text=row[@"text"];assert(text.length&&Bytes(text)<=TGB_LYRIC_CAP);
  }
  assert([rows[0][@"text"] isEqual:TGBClipText(f[@"current"],TGB_LYRIC_CAP)]&&[rows[1][@"text"] isEqual:TGBClipText(f[@"next"],TGB_LYRIC_CAP)]);
  assert([f[@"current"] hasPrefix:rows[0][@"text"]]);                           // a clip is a prefix, nothing is rewritten
  BOOL zh=[f[@"lang"] isEqual:@"zh"];
  assert(zh==(Han(f[@"current"])>10)&&zh==(Han(f[@"next"])>0));
 }
 // The "..." case is longer than the cap on purpose, so it exercises the clip; every other fixture fits whole.
 for(NSDictionary *f in fixtures){
  BOOL over=Bytes(f[@"current"])>TGB_LYRIC_CAP;
  assert(over==[f[@"id"] isEqual:@"enell"]);
  if(over){assert(Bytes(f[@"current"])>TGB_LYRIC_CAP+10);assert(Bytes(TGBLyricRows(f)[0][@"text"])>TGB_LYRIC_CAP-4);}
  else assert([TGBLyricRows(f)[0][@"text"] isEqual:f[@"current"]]);
 }
 assert([Fixture(@"ennext")[@"nextEllipsis"] boolValue]&&Bytes(Fixture(@"ennext")[@"next"])<=TGB_LYRIC_CAP&&Bytes(Fixture(@"ennext")[@"next"])>80);
 // Chinese lengths: a 24 px row holds about 19 characters, so 3 rows are 39...57 characters and 4 rows 58...76; 3 bytes each, far below the cap.
 NSUInteger zh3=Chars(Fixture(@"zh3")[@"current"]),zh4=Chars(Fixture(@"zh4")[@"current"]);
 assert(zh3>=39&&zh3<=57&&zh4>=58&&zh4<=76);
 assert(Bytes(Fixture(@"zh3")[@"current"])<=zh3*3+6&&Bytes(Fixture(@"zh4")[@"current"])<=zh4*3+6);
 // Latin lengths: 3 and 4 line fixtures are short of the cap and growing, 5 lines is near it.
 NSUInteger n3=Bytes(Fixture(@"en3")[@"current"]),n4=Bytes(Fixture(@"en4")[@"current"]),n4s=Bytes(Fixture(@"en4s")[@"current"]),n5=Bytes(Fixture(@"en5")[@"current"]);
 assert(n3<n4&&n4<n4s&&n4s<n5&&n5<=TGB_LYRIC_CAP);
 // The now-playing demo lines follow the phone's language and are short.
 for(NSString *lang in @[@"en",@"zh"]){
  TIOSetUILanguageOverride(lang);NSArray *rows=TGBDemoSongRows();assert(rows.count==3);
  for(NSUInteger i=0;i<3;i++){assert([rows[i][@"ms"] unsignedIntValue]==i*60000&&[rows[i][@"text"] length]>0&&Bytes(rows[i][@"text"])<=TGB_LYRIC_CAP);assert(![rows[i][@"text"] hasPrefix:@"bench."]);}
 }
 TIOSetUILanguageOverride(@"en");
}

static void ParsesAndFits(DCValues v){
 NSString *text=TGBCardText(&v);assert(text);
 NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding];DCValues back;
 assert(data.length>=5&&data.length<=TGB_CARD_BYTES_MAX&&dc_parse(data.bytes,data.length,&back));
 for(unsigned f=0;f<TGBCardFieldCount;f++)assert(TGBCardGet(&v,(TGBCardField)f)==TGBCardGet(&back,(TGBCardField)f));
 assert(v.weekly<=100&&v.claude5h<=100&&v.claudeWeek<=100&&v.ramTotal>0&&v.diskTotal>0&&v.ramFree<=v.ramTotal&&v.diskFree<=v.diskTotal);
 for(unsigned i=0;i<3;i++)assert(v.icons[i]<=2);
}

static void CardTests(void){
 assert([TGBCardPresetIDs() isEqual:(@[@"typical",@"three100",@"empty"])]);
 DCValues v;
 assert(TGBCardPreset(@"typical",&v)&&[TGBCardText(&v) isEqual:@"TDC1;99;90;85;375;1280;1400;2000;0;1;2"]);ParsesAndFits(v);
 assert(TGBCardPreset(@"three100",&v)&&[TGBCardText(&v) isEqual:@"TDC1;100;100;100;375;1280;1400;2000;0;1;2"]);ParsesAndFits(v);
 assert(v.weekly==100&&v.claude5h==100&&v.claudeWeek==100);
 assert(TGBCardPreset(@"empty",&v)&&[TGBCardText(&v) isEqual:@"TDC1;0;0;0;0;1280;0;2000;0;0;0"]);ParsesAndFits(v);
 assert(v.weekly==0&&v.ramFree==0&&v.diskFree==0);
 assert(!TGBCardPreset(@"nope",&v)&&!TGBCardPreset(nil,&v)&&!TGBCardPreset(@"typical",NULL));
 // The card text is exactly what the glasses parse: nothing out of range gets through, and nothing over 120 B.
 TGBCardPreset(@"typical",&v);
 DCValues bad=v;bad.weekly=101;assert(!TGBCardText(&bad));
 bad=v;bad.ramTotal=0;assert(!TGBCardText(&bad));
 bad=v;bad.diskTotal=0;assert(!TGBCardText(&bad));
 bad=v;bad.ramFree=bad.ramTotal+1;assert(!TGBCardText(&bad));
 bad=v;bad.diskFree=bad.diskTotal+1;assert(!TGBCardText(&bad));
 bad=v;bad.icons[1]=3;assert(!TGBCardText(&bad));
 bad=v;bad.ramTotal=100000;assert(!TGBCardText(&bad));
 assert(!TGBCardText(NULL));
 // The widest values the editor can reach, and the wire's own worst case (six digits, which is refused), stay under the cap.
 DCValues widest={100,100,100,2560,2560,8000,8000,{2,2,2}};ParsesAndFits(widest);assert(Bytes(TGBCardText(&widest))<=TGB_CARD_BYTES_MAX);
 DCValues wire={100,100,100,99999,99999,99999,99999,{2,2,2}};NSString *worst=TGBCardText(&wire);assert(worst&&Bytes(worst)<=TGB_CARD_BYTES_MAX);   // 5 digit totals still fit
 // Stepping: ends of the range, free never above total, total never below free.
 TGBCardPreset(@"typical",&v);
 assert(TGBCardStep(&v,TGBCardFieldWeekly,1)&&v.weekly==100&&!TGBCardStep(&v,TGBCardFieldWeekly,1));
 assert(TGBCardStep(&v,TGBCardFieldWeekly,-1)&&v.weekly==95);
 v.weekly=3;assert(TGBCardStep(&v,TGBCardFieldWeekly,-1)&&v.weekly==0&&!TGBCardStep(&v,TGBCardFieldWeekly,-1));
 TGBCardPreset(@"typical",&v);v.ramFree=1275;assert(TGBCardStep(&v,TGBCardFieldRamFree,1)&&v.ramFree==1280&&!TGBCardStep(&v,TGBCardFieldRamFree,1));   // free stops at total
 v.ramFree=1000;unsigned guard=0;while(TGBCardStep(&v,TGBCardFieldRamTotal,-1)&&guard++<100);assert(v.ramTotal==1000&&v.ramFree==1000);   // total stops at free
 TGBCardPreset(@"typical",&v);v.diskFree=1900;assert(TGBCardStep(&v,TGBCardFieldDiskFree,1)&&v.diskFree==2000&&!TGBCardStep(&v,TGBCardFieldDiskFree,1));
 v.diskFree=1700;guard=0;while(TGBCardStep(&v,TGBCardFieldDiskTotal,-1)&&guard++<100);assert(v.diskTotal==1700);
 assert(TGBCardStep(&v,TGBCardFieldIcon1,1)&&TGBCardStep(&v,TGBCardFieldIcon1,1)&&!TGBCardStep(&v,TGBCardFieldIcon1,1)&&v.icons[0]==2);
 assert(!TGBCardStep(&v,TGBCardFieldCount,1)&&!TGBCardStep(&v,TGBCardFieldWeekly,0)&&!TGBCardStep(NULL,TGBCardFieldWeekly,1));
 // Random walk over all ten fields: every state the editor can reach is a card the glasses accept, within 120 B.
 srand(11);TGBCardPreset(@"typical",&v);
 for(unsigned i=0;i<30000;i++){TGBCardStep(&v,(TGBCardField)(rand()%TGBCardFieldCount),(rand()&1)?1:-1);ParsesAndFits(v);if(i%5000==0)TGBCardPreset(TGBCardPresetIDs()[(NSUInteger)rand()%3],&v);}
 // Each field reaches both ends from any preset.
 for(NSString *preset in TGBCardPresetIDs())for(unsigned f=0;f<TGBCardFieldCount;f++){
  assert(TGBCardPreset(preset,&v));unsigned g=0;while(TGBCardStep(&v,(TGBCardField)f,1)&&g++<1000);ParsesAndFits(v);
  g=0;while(TGBCardStep(&v,(TGBCardField)f,-1)&&g++<1000);ParsesAndFits(v);assert(g<1000);
 }
 // Field names and the text the editor shows.
 TGBCardPreset(@"typical",&v);
 assert([TGBCardFieldText(&v,TGBCardFieldWeekly) isEqual:@"99%"]&&[TGBCardFieldText(&v,TGBCardFieldRamFree) isEqual:@"37.5 GB"]&&[TGBCardFieldText(&v,TGBCardFieldRamTotal) isEqual:@"128 GB"]);
 assert([TGBCardFieldText(&v,TGBCardFieldDiskFree) isEqual:@"1.4 TB"]&&[TGBCardFieldText(&v,TGBCardFieldDiskTotal) isEqual:@"2 TB"]&&[TGBCardFieldText(&v,TGBCardFieldIcon3) isEqual:@"2"]);
 NSMutableSet *ids=[NSMutableSet new];
 for(unsigned f=0;f<TGBCardFieldCount;f++){
  NSString *ident=TGBCardFieldID((TGBCardField)f),*key=TGBCardFieldTitleKey((TGBCardField)f);assert(ident.length&&![ids containsObject:ident]);[ids addObject:ident];
  for(NSString *lang in @[@"en",@"zh"]){TIOSetUILanguageOverride(lang);NSString *title=TIOText(key);assert(title.length&&![title isEqual:key]);}
 }
 TIOSetUILanguageOverride(@"en");
}

static void MiscTests(void){
 assert([TGBClockText(0) isEqual:@"0:00"]&&[TGBClockText(65000) isEqual:@"1:05"]&&[TGBClockText(240000) isEqual:@"4:00"]&&[TGBClockText(3599000) isEqual:@"59:59"]);
 assert(TGB_TIMER_SECONDS>=10&&TGB_TIMER_SECONDS<=7200);                         // TFP1 accepts 10...7200 s
 assert(TGB_POSITION_STEP_MS>0&&TGB_LYRIC_DURATION_MS%TGB_POSITION_STEP_MS==0);
 // Every bench string has English and Chinese text, never the key.
 NSMutableArray *keys=[NSMutableArray arrayWithObjects:@"hub.row.testBench",@"bench.demo.title",@"bench.demo.detail",@"bench.blocked",@"bench.blocked.title",@"bench.lyrics.header",@"bench.lyrics.footer",
  @"bench.music.header",@"bench.music.footer",@"bench.music.show",@"bench.music.stop",@"bench.music.playing",@"bench.music.position",@"bench.music.positionOf",@"bench.music.active",@"bench.music.inactive",@"music.status.demo",
  @"bench.card.header",@"bench.card.footer",@"bench.card.size",@"bench.card.invalid",@"bench.card.send",@"bench.card.remove",@"bench.card.status",
  @"bench.timer.header",@"bench.timer.footer",@"bench.timer.start",@"bench.timer.pause",@"bench.timer.resume",@"bench.timer.stop",@"bench.timer.state.left",
  @"bench.notes.header",@"bench.notes.tile.title",@"bench.notes.tile.detail",@"bench.notes.camera.title",@"bench.notes.camera.detail",@"bench.notes.route.title",@"bench.notes.route.detail",@"bench.increase",@"bench.decrease",nil];
 for(NSDictionary *f in TGBLyricFixtures())[keys addObject:[@"bench.lyric." stringByAppendingString:f[@"id"]]];
 for(NSString *p in TGBCardPresetIDs())[keys addObject:[@"bench.card.preset." stringByAppendingString:p]];
 for(NSString *s in @[@"usage",@"memory",@"storage",@"icons"])[keys addObject:[@"bench.card.header." stringByAppendingString:s]];
 for(NSString *s in @[@"unread",@"idle",@"running",@"paused",@"done",@"stopped"])[keys addObject:[@"bench.timer.state." stringByAppendingString:s]];
 for(NSString *key in keys){
  TIOSetUILanguageOverride(@"en");NSString *en=TIOText(key);TIOSetUILanguageOverride(@"zh");NSString *zh=TIOText(key);
  assert(en.length&&zh.length&&![en isEqual:key]&&![zh isEqual:key]&&![en isEqual:zh]&&(Han(zh)>0||[key isEqual:@"bench.music.positionOf"]));   // "%@ / %@" is the same digits and slash in Chinese
 }
 TIOSetUILanguageOverride(@"en");
 // Format strings keep their placeholders in both languages.
 for(NSString *lang in @[@"en",@"zh"]){TIOSetUILanguageOverride(lang);
  assert([TIOText(@"bench.music.positionOf") containsString:@"%@"]&&[TIOText(@"bench.card.size") containsString:@"%lu"]&&[TIOText(@"bench.timer.state.left") containsString:@"%@"]);}
 TIOSetUILanguageOverride(@"en");
}

int main(void){@autoreleasepool{
 ClipTests();LyricTests();CardTests();MiscTests();
 puts("PASS glasses test bench fixtures: 240 B lyric clip, 120 B card cap, value ranges and stepping, Chinese lengths, strings in both languages");
}return 0;}
