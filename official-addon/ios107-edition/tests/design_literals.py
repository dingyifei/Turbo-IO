"""No fixed font sizes and no color literals in phone UI sources outside TIODesign.*
and the glasses-preview surfaces (docs/design-system, SPEC "tokens, not literals").

Usage: design_literals.py <edition dir>. Prints each offending line and exits 1.
Screens must use TIODesignFont/TIODesignColor (or the Swift mirror). Allowed
exceptions are listed here with the reason, never by editing the source audit.
"""
import re,subprocess,sys
from pathlib import Path

# Whole files that are token tables or glasses/lens surfaces, not phone chrome.
EXEMPT_FILES={
 'TIODesign.m':'token tables and the only place literals may live',
 'TIODesign.h':'token API','TIODesign.inc':'token tables',
 'TIODesignTests.m':'compares the tables with tokens.json',
 'local-translation/src/TIODesign.swift':'Swift mirror of the token tables',
 'DisplayHUDRenderer.m':'renders the glasses HUD sample image (lens surface)',
 'EditorCodec.m':'rasterizes 1-bit glasses bitmaps; black and white are pixel values, not chrome',
 'HomeTabBridge.m':'replica of the host app tab bar drawn in the host colors; ds1 keeps it out of scope except for contrast',
}
# Classes that draw a lens surface: exempt from @interface to @end.
EXEMPT_CLASSES={'AppUI.m':['TAPPreview'],'EditorCanvas.m':['TCECanvas']}
# Free C functions that draw a lens surface: exempt from their signature line to the closing brace at column 0.
EXEMPT_FUNCTIONS={'DisplayPhoneUI.m':['NavigationImage'],'EditorCanvas.m':['Attrs'],
 'ImageUploadUI.m':['Luminance']}   # Luminance fills an 8-bit gray raster for the glasses with black: a pixel value, not chrome
SOURCE_SUFFIXES=('.m','.mm','.h','.inc','.swift')
SKIP_DIRS=('build/','tests/','preview/','i18n/','firmware-research/')
SKIP_SUFFIXES=('Tests.m','Test.m')

FONT=re.compile(r'\b(?:boldSystemFontOfSize|systemFontOfSize|monospacedSystemFontOfSize|monospacedDigitSystemFontOfSize|italicSystemFontOfSize|fontWithName|fontWithDescriptor|UIFont\s*\(\s*(?:name|descriptor))\b|\b(?:systemFont|boldSystemFont|italicSystemFont|monospacedSystemFont|monospacedDigitSystemFont)\s*\(\s*ofSize|\.system\s*\(\s*size|Font\.system\s*\(\s*size|\bFont\.custom\s*\(|\bfontWithSize\s*:\s*[0-9]')
RGB=re.compile(r'colorWith(?:Red|White|Hue)\s*:|initWith(?:Red|White|Hue)\s*:|UIColor\s*\(\s*(?:red|white|hue)\s*:|Color\s*\(\s*red\s*:|\bUIColor\.(?:white|black|red|green|blue|gray|lightGray|darkGray|orange|yellow|cyan|magenta|purple|brown)Color\b|\[UIColor\s+(?:white|black|red|green|blue|gray|lightGray|darkGray|orange|yellow|cyan|magenta|purple|brown)Color\]|\bUIColor\.(?:system(?:Red|Green|Blue|Orange|Yellow|Pink|Purple|Teal|Indigo|Mint|Cyan|Brown|Gray[0-9]?))Color\b|\.(?:white|black|red|green|blue|orange|yellow|gray)\b(?=\s*[,)\]]).{0,0}')

# Swift spellings (UIColor.white, UIColor.systemRed, UIColor.init(red:), Color(.sRGB, ...)) and Core Graphics colors.
RGB=re.compile(RGB.pattern+r'|\bUIColor\.(?:white|black|red|green|blue|gray|lightGray|darkGray|orange|yellow|cyan|magenta|purple|brown|system(?:Red|Green|Blue|Orange|Yellow|Pink|Purple|Teal|Indigo|Mint|Cyan|Brown|Gray[0-9]?))\b|\bUIColor\.init\s*\(\s*(?:red|white|hue)\s*:|\bColor\s*\(\s*\.sRGB|\.sRGB\b|\bCGColor\s*\(\s*(?:red|gray|srgbRed|genericGray)|\bCGColorCreate\w*|\bCGColor\(\s*gray')
# Display P3 / sRGB / hex helpers are also color literals.
RGB=re.compile(RGB.pattern+r'|colorWithDisplayP3Red|initWithDisplayP3Red|\bdisplayP3\b|Color\.RGBColorSpace|\b(?:colorWithHex|colorFromHex|colorWithRGB|colorWithRGBA|UIColorFromRGB|UIColorFromHex)\w*|\b\w*ColorFrom(?:Hex|RGB)\w*|\bUIColor\s*\(\s*(?:hex|displayP3Red)\b|\bColor\s*\(\s*hex\b|\bhex(?:String|Color)?\s*:\s*0x')

# Swift implicit-member colors in a color context (`= .white`, `: .systemRed`, `(.black`), Objective-C system hue class methods, and Core Graphics color setters.
_HUES=r'white|black|red|green|blue|gray|lightGray|darkGray|orange|yellow|cyan|magenta|purple|brown|system(?:Red|Green|Blue|Orange|Yellow|Pink|Purple|Teal|Indigo|Mint|Cyan|Brown|Gray[0-9]?)'
RGB=re.compile(RGB.pattern+r'|(?:=|:|\(|,|return)\s*\.(?:'+_HUES+r')\b(?!\s*\()|\[UIColor\s+system(?:Red|Green|Blue|Orange|Yellow|Pink|Purple|Teal|Indigo|Mint|Cyan|Brown|Gray[0-9]?)Color\]|\bCGContextSet(?:RGB|Gray)\w*Color\b|\bCGColorCreate(?:GenericRGB|GenericGray)?\b')

SELFTEST=[('font','UIFont.boldSystemFont(ofSize: 14)'),('font','UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)'),('font','UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)'),
 ('font','[UIFont fontWithDescriptor:d size:12]'),('font','UIFont(descriptor: d, size: 12)'),('font','Font.custom("X", size: 12)'),('font','f=[f fontWithSize:12]'),
 ('color','UIColor.white'),('color','UIColor.systemRed'),('color','UIColor.init(red: 1, green: 0, blue: 0, alpha: 1)'),('color','Color(.sRGB, red: 1, green: 0, blue: 0)'),
 ('color','CGColor(gray: 0.5, alpha: 1)'),('color','CGColorCreateGenericRGB(1,0,0,1)'),('color','UIColor.systemBlue'),
('font','[UIFont systemFontOfSize:14]'),('font','UIFont.systemFont(ofSize: 12)' ),('color','[UIColor colorWithRed:1 green:0 blue:0 alpha:1]'),
 ('color','UIColor(red: 1, green: 0, blue: 0, alpha: 1)'),('color','[UIColor colorWithDisplayP3Red:1 green:0 blue:0 alpha:1]'),
 ('color','UIColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)'),('color','[UIColor colorWithHex:0xff0000]'),('color','TIOColorFromHex(0xff0000)'),('color','[UIColor colorWithWhite:.15 alpha:1]'),
 ('color','label.textColor = .white'),('color','cell.textLabel?.textColor = .systemIndigo'),('color','let c: UIColor = .black'),('color','tint(color: .systemRed)'),
 ('color','[UIColor systemRedColor]'),('color','[UIColor systemBlueColor]'),('color','CGContextSetRGBFillColor(ctx,1,0,0,1)'),('color','CGContextSetGrayStrokeColor(ctx,.5,1)')]
# Semantic and token colors must not be flagged.
CLEAN=['v.backgroundColor = .clear','c.textLabel.textColor=[UIColor labelColor]','TIODesign.color(.accent)','c.tintColor = .tintColor','x = .systemBackground','x = .redacted()']

def selftest():
    # The patterns must catch each of these, or a violation would pass silently.
    miss=[t for k,t in SELFTEST if not (FONT if k=='font' else RGB).search(t)]
    miss+=['false positive: '+t for t in CLEAN if RGB.search(t) or FONT.search(t)]
    # A function range ends where its own braces close: a one-line function exempts only that line, and a multi-line one its body.
    one=['static NSDictionary *Attrs(NSDictionary *c){return @{};}','NSString *Other(void){return [UIColor colorWithRed:1 green:0 blue:0 alpha:1].description;}','}']
    multi=['static void NavigationImage(void) {','  int x;','  if(x){x=0;}','}','NSString *Other(void){}']
    global EXEMPT_FUNCTIONS
    saved=EXEMPT_FUNCTIONS;EXEMPT_FUNCTIONS={'a':['Attrs'],'b':['NavigationImage']}
    try:
        if exempt_ranges('a',one)!=[(0,0)]:miss.append('one-line function range leaks past its own line')
        if exempt_ranges('b',multi)!=[(0,3)]:miss.append('multi-line function range is wrong')
    finally:EXEMPT_FUNCTIONS=saved
    # A // inside a string must not hide the rest of the line; a real comment must still be dropped.
    if not RGB.search(strip_comment('NSURL *u=[NSURL URLWithString:@"https://x"];[UIColor colorWithRed:1 green:0 blue:0 alpha:1];')):miss.append('string // hides a literal')
    if RGB.search(strip_comment('int x; // UIColor.white is only mentioned')):miss.append('comment is scanned')
    return miss

def tracked(root):
    out=subprocess.check_output(['git','-C',str(root),'ls-files','-z','--cached','--others','--exclude-standard','--','.'],text=True).split('\0')
    return [f for f in out if f.endswith(SOURCE_SUFFIXES) and not f.startswith(SKIP_DIRS) and not f.endswith(SKIP_SUFFIXES)]

def strip_comment(line):
    """The line without its // comment. A // inside a string literal ("https://x", @"//") is not a comment."""
    quote=False;i=0
    while i<len(line):
        ch=line[i]
        if quote:
            if ch=='\\':i+=2;continue
            if ch=='"':quote=False
        elif ch=='"':quote=True
        elif ch=='/' and line[i+1:i+2]=='/':return line[:i]
        i+=1
    return line

def exempt_ranges(name,lines):
    spans=[]
    for fn in EXEMPT_FUNCTIONS.get(name,[]):
        start=next((i for i,l in enumerate(lines) if re.match(r'static\s[^;=]*\b'+fn+r'\s*\(',l)),None)
        if start is None:continue
        depth=0;seen=False;end=start
        for j in range(start,len(lines)):   # the function ends where its own braces balance (a one-line function ends on its first line)
            for ch in strip_comment(lines[j]):
                if ch=='{':depth+=1;seen=True
                elif ch=='}':depth-=1
            end=j
            if seen and depth<=0:break
        spans.append((start,end))
    for cls in EXEMPT_CLASSES.get(name,[]):
        start=next((i for i,l in enumerate(lines) if re.match(r'@(interface|implementation)\s+'+cls+r'\b',l)),None)
        if start is None:continue
        # An @interface block and its @implementation each end at the next @end.
        for i,l in enumerate(lines):
            if re.match(r'@(interface|implementation)\s+'+cls+r'\b',l):
                end=next((j for j in range(i,len(lines)) if lines[j].startswith('@end')),i)
                spans.append((i,end))
    return spans

def main(root):
    root=Path(root);bad=[]
    miss=selftest()
    if miss:
        print('\n'.join('pattern misses: '+m for m in miss));print('DESIGN LITERALS FAIL: self-test');return 1
    for name in tracked(root):
        if name in EXEMPT_FILES:continue
        lines=(root/name).read_text(errors='replace').split('\n')
        spans=exempt_ranges(name,lines)
        for i,line in enumerate(lines):
            if any(a<=i<=b for a,b in spans):continue
            code=strip_comment(line)
            for kind,pattern in (('font',FONT),('color',RGB)):
                if pattern.search(code):bad.append('%s:%d: %s literal: %s'%(name,i+1,kind,line.strip()[:140]))
    if bad:
        print('\n'.join(bad));print('DESIGN LITERALS FAIL: %d lines'%len(bad));return 1
    print('DESIGN LITERALS PASS');return 0
if __name__=='__main__':sys.exit(main(sys.argv[1]))
