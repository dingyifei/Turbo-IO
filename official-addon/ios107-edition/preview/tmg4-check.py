"""Assert the real injected UI report and the preview shot matrix.

Every screen is shot in the same matrix (preview/shoot.sh):
  EN and ZH-Hans x light and dark at the default text size, plus one accessibility
  content-size pass (EN, light).  Stems are <screen>-<lang>-<appearance> and
  <screen>-en-light-ax.  Each report records the interface style and content-size
  category the process actually rendered with, so a shot cannot pass on a simulator
  that ignored the requested setting.
"""
from pathlib import Path
import hashlib,json,sys

LANGS=('en','zh-Hans')
APPEARANCES=('light','dark')
STANDARD_SIZE='UICTContentSizeCategoryL'
AX_SIZE='UICTContentSizeCategoryAccessibilityXXXL'
TABLE_SCREENS=('tiles','runtime','knob')
# Screens whose navigation title is localized today; the others only assert the process language.
LOCALIZED_TITLE=('tiles','runtime','knob','captions')
PANELS={'nav':'TIOMapKitNavigationPanel','nav-active':'TIOMapKitNavigationPanel','captions':'TIOAppleCaptionPanel'}

def han(s):return any('㐀'<=c<='鿿' for c in s)
def matrix():
    """(suffix, language, appearance, content-size category) for every shot of a screen."""
    cells=[('-'+lang+'-'+look,lang,look,STANDARD_SIZE) for look in APPEARANCES for lang in LANGS]
    return cells+[('-en-light-ax','en','light',AX_SIZE)]
def check_table(screen,report,lang,stem,size):
    sections=report['sections'];text=' '.join([report['screen']]+[s['title'] for s in sections]+[str(r[k]) for s in sections for r in s['rows'] for k in ('title','status')])
    assert 'tmg4.' not in text,'untranslated key in '+str(stem)
    if screen=='tiles':
        assert not report['editing'] or report['selectionWhileEditing'],'tile actions are unselectable while reordering'
        assert len(sections)==3 and len(sections[0]['rows'])==7 and not any(r['movable'] for r in sections[0]['rows'])
        custom=sections[1]['rows'];assert len(custom)==6 and all(r['movable'] for r in custom)
        assert all(r["editingSwitch"] for r in custom if r["switchOn"] is not None),"editing mode hid visibility controls"
        # At accessibility sizes the rows legitimately scroll past the first screen.
        assert size==AX_SIZE or all(r["rendered"] for r in custom),"custom tile fixture must be visible"
        switches=[r['switchOn'] for r in custom if r['switchOn'] is not None];assert len(switches)==5 and switches.count(False)==2 and switches.count(True)==3
        assert custom[0]['switchOn'] is None and custom[0]['accessory']==3,'Camera must stay visible in reversed fixture'
        assert {r['id'] for r in sections[2]['rows']}=={'tiles-read','tiles-save','tiles-reset'}
    else:
        assert len(sections)==5 and len(sections[0]['rows'])==8 and len(sections[1]['rows'])==5
        assert 'TMG4' in sections[0]['rows'][1]['status'] and '44444444' in sections[0]['rows'][1]['status']
        assert '600' in sections[0]['rows'][6]['status']
        assert {r['id'] for r in sections[1]['rows'][2:]}=={'knob-start','knob-finish','knob-cancel'}
        if screen=='knob':assert '4800' in sections[1]['rows'][1]['status'],'completed one-turn fixture missing'
def check_panel(screen,report,stem):
    assert report['controllerClass']==PANELS[screen],'not the real panel in '+str(stem)+': '+report['controllerClass']
    if screen in ('nav','nav-active'):
        nav=report['navigation'];active=screen=='nav-active'
        assert nav['routeLoaded'] and nav['metrics'].strip() and nav['title'].strip(),'stub route did not reach the panel: '+str(stem)
        assert nav['navigating']==active,'wrong navigation state in '+str(stem)
        assert nav['endVisible']==active,'End must show only while navigating: '+str(stem)
        assert nav['startVisible']!=active,'Start must hide while navigating: '+str(stem)
        assert nav['lastActionOnScreen'],'the last action button is clipped or off screen (Apple Maps unreachable): '+str(stem)+' '+nav['lastActionFrame']
        assert nav['modeControlVisible']!=active,'Walk/Cycle/Drive must be hidden while navigating and shown otherwise: '+str(stem)
        assert not active or nav['searchText'].strip(),'the collapsed top card must still show the destination: '+str(stem)
    else:
        assert report['sections'] and any(s['rows'] for s in report['sections']),'captions fixture rendered no rows: '+str(stem)
def check(root,screens):
    receipts=[]
    for screen in screens:
        shas={}
        for suffix,lang,look,size in matrix():
            stem=root/(screen+suffix);png=stem.with_suffix('.png');report=json.loads(stem.with_suffix('.json').read_text())
            assert png.stat().st_size>20000 and report['deviceIO'] is False and report['hardwareValidated'] is False
            assert report['preferredLanguage'].startswith(lang),'wrong process language in '+str(stem)
            assert report['interfaceStyle']==look,'wrong appearance in '+str(stem)+': '+report['interfaceStyle']
            assert report['contentSizeCategory']==size,'wrong text size in '+str(stem)+': '+report['contentSizeCategory']
            if screen in LOCALIZED_TITLE:assert not han(report['screen']) if lang=='en' else han(report['screen']),'wrong UI language: '+str(stem)
            if screen in TABLE_SCREENS:check_table(screen,report,lang,stem,size)
            if screen in PANELS:check_panel(screen,report,stem)
            sha=hashlib.sha256(png.read_bytes()).hexdigest();shas[(lang,look,size)]=sha
            receipts.append({'screen':screen,'language':lang,'appearance':look,'contentSize':size,'sha256':sha,'sections':len(report['sections'])})
        for lang in LANGS:
            assert shas[(lang,'light',STANDARD_SIZE)]!=shas[(lang,'dark',STANDARD_SIZE)],screen+' '+lang+': light and dark shots are identical'
        assert shas[('en','light',STANDARD_SIZE)]!=shas[('en','light',AX_SIZE)],screen+': accessibility size shot is identical to the default size'
    (root/'tmg4-check.json').write_text(json.dumps({'passed':True,'matrix':[[s,l,a,c] for s,l,a,c in matrix()],'screens':receipts,'deviceIO':False,'hardwareValidated':False},indent=2)+'\n')
    print('PREVIEW MATRIX PASS: '+str(len(receipts))+' shots ('+str(len(screens))+' screens x '+str(len(matrix()))+')')
if __name__=='__main__':check(Path(sys.argv[1]),sys.argv[2:])
