#pragma once
#import <Foundation/Foundation.h>

static inline BOOL TIOScriptIsHan(unichar c) {
    return (c>=0x3400&&c<=0x4DBF)||(c>=0x4E00&&c<=0x9FFF)||
        (c>=0xF900&&c<=0xFAFF)||(c>=0xD840&&c<=0xD8BF);
}
static inline BOOL TIOScriptIsLatinLetter(unichar c) {
    return (c>='A'&&c<='Z')||(c>='a'&&c<='z')||
        (c>=0x00C0&&c<=0x024F&&c!=0x00D7&&c!=0x00F7);
}
static inline BOOL TIOScriptLanguageIsChinese(NSString * _Nullable lang) {
    return [lang isKindOfClass:NSString.class]&&[lang.lowercaseString hasPrefix:@"zh"];
}
