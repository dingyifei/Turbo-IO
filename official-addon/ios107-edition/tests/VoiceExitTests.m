#import "Core.h"
#import "TIOLanguage.h"
#include <assert.h>
#include <stdio.h>
static void expect(NSString *s, BOOL yes){BOOL got=TIOIsVoiceExitCommand(s);if(got!=yes)fprintf(stderr,"FAIL [%s]: expected %d got %d\n",s.UTF8String,yes,got);assert(got==yes);}
int main(void){@autoreleasepool{
    for(NSString *s in @[@"Never mind.",@"never mind",@"never  mind",@"STOP!",@"; STOP ;",@"That’s all",@"Hey RayNeo, close the window.",@"Hey\t  RayNeo, close the window.",@" exit ",@"Goodbye",@"退下吧",@"退下",@"关闭",@"没事了。",@"关闭窗口！",@"小雷小雷，关闭窗口。",@"关闭对话",@"结束对话",@"退出对话",@"不用了",@"就这样吧"])expect(s,YES);
    for(NSString *s in @[@"how do I close the window",@"don't stop",@"stop the music",@"close the door",@"never mind the weather today please",@"",@"exit 5",@"goodbye to you",@"怎么关闭窗口",@"不要关闭窗口",@"帮我添加待办关闭窗口",@"他说没事了",@"等会再关闭",@"“关闭”是什么意思",@"没事了但是我还有问题"])expect(s,NO);
    TIOSetUILanguageOverride(@"en");assert([TIOUILanguage() isEqual:@"en"]);
    for(NSString *s in @[@"退下吧",@"退下",@"关闭",@"没事了。",@"关闭窗口！",@"小雷小雷，关闭窗口。",@"关闭对话",@"结束对话",@"退出对话",@"不用了",@"就这样吧"])expect(s,YES);
    for(NSString *s in @[@"怎么关闭窗口",@"不要关闭窗口",@"帮我添加待办关闭窗口",@"他说没事了",@"等会再关闭",@"“关闭”是什么意思",@"没事了但是我还有问题"])expect(s,NO);
    expect(@"关闭窗口。",YES);expect(@"小雷小雷，退下吧！",YES);
    NSDictionary *table=TIOStringTable();assert(!table[@"，。！？,.!?、：:"]);assert(!table[@"。！？!?；;\n"]);assert(!table[@"，,、：: "]);
    TIOSetUILanguageOverride(@"auto");puts("PASS voice exit EN exact phrases, ZH preservation under EN UI, negatives and keep-marked logic strings");
}return 0;}
