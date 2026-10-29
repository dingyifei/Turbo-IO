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
 'EditorCanvas.m':'draws the 256x194 glasses card (lens surface)',
 'DisplayPhoneUI.m':'draws the glasses display sample (lens surface)',
 'DisplayHUDRenderer.m':'renders the glasses HUD sample image (lens surface)',
 'EditorCodec.m':'rasterizes 1-bit glasses bitmaps; black and white are pixel values, not chrome',
 'HomeTabBridge.m':'replica of the host app tab bar drawn in the host colors; ds1 keeps it out of scope except for contrast',
}
# Classes inside shared files that draw a lens surface: exempt from @interface to @end.
EXEMPT_CLASSES={'AppUI.m':['TAPPreview']}
SOURCE_SUFFIXES=('.m','.mm','.inc','.swift')
SKIP_DIRS=('build/','tests/','preview/','i18n/','firmware-research/')
SKIP_SUFFIXES=('Tests.m','Test.m')

FONT=re.compile(r'\b(?:boldSystemFontOfSize|systemFontOfSize|monospacedSystemFontOfSize|monospacedDigitSystemFontOfSize|italicSystemFontOfSize|fontWithName|UIFont\s*\(\s*name)\b|\.system\s*\(\s*size|Font\.system\s*\(\s*size')
RGB=re.compile(r'colorWith(?:Red|White|Hue)\s*:|initWith(?:Red|White|Hue)\s*:|UIColor\s*\(\s*(?:red|white|hue)\s*:|Color\s*\(\s*red\s*:|\bUIColor\.(?:white|black|red|green|blue|gray|lightGray|darkGray|orange|yellow|cyan|magenta|purple|brown)Color\b|\[UIColor\s+(?:white|black|red|green|blue|gray|lightGray|darkGray|orange|yellow|cyan|magenta|purple|brown)Color\]|\bUIColor\.(?:system(?:Red|Green|Blue|Orange|Yellow|Pink|Purple|Teal|Indigo|Mint|Cyan|Brown|Gray[0-9]?))Color\b|\.(?:white|black|red|green|blue|orange|yellow|gray)\b(?=\s*[,)\]]).{0,0}')

def tracked(root):
    out=subprocess.check_output(['git','-C',str(root),'ls-files','-z','--cached','--others','--exclude-standard','--','.'],text=True).split('\0')
    return [f for f in out if f.endswith(SOURCE_SUFFIXES) and not f.startswith(SKIP_DIRS) and not f.endswith(SKIP_SUFFIXES)]

def exempt_ranges(name,lines):
    spans=[]
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
    for name in tracked(root):
        if name in EXEMPT_FILES:continue
        lines=(root/name).read_text(errors='replace').split('\n')
        spans=exempt_ranges(name,lines)
        for i,line in enumerate(lines):
            if any(a<=i<=b for a,b in spans):continue
            code=re.sub(r'//.*$','',line)
            for kind,pattern in (('font',FONT),('color',RGB)):
                if pattern.search(code):bad.append('%s:%d: %s literal: %s'%(name,i+1,kind,line.strip()[:140]))
    if bad:
        print('\n'.join(bad));print('DESIGN LITERALS FAIL: %d lines'%len(bad));return 1
    print('DESIGN LITERALS PASS');return 0
if __name__=='__main__':sys.exit(main(sys.argv[1]))
