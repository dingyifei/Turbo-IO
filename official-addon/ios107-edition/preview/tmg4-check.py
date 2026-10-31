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
KNOB_STEP_SCREENS=('knob-tmg9','knob-tmg9-confirmed','knob-tmg9-failed','knob-tmg8')
TABLE_SCREENS=('tiles','runtime','knob')+KNOB_STEP_SCREENS
# Screens whose navigation title is localized today; the others only assert the process language.
LOCALIZED_TITLE=('tiles','layout','layout-tmg7','runtime','knob','captions')+KNOB_STEP_SCREENS
# The menu layout screen with canned TMG8 glasses (carousel stored) and with older glasses (three rows, Carousel disabled).
LAYOUT_SCREENS=('layout','layout-tmg7')
SEGMENTS={'en':['Carousel','2 rows','3 rows'],'zh-Hans':['轮播','两排','三排']}
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
        # Status, calibration, knob step, capture, resources, integrity.
        assert len(sections)==6 and len(sections[0]['rows'])==8 and len(sections[1]['rows'])==5 and len(sections[2]['rows'])==4,'section shape in '+str(stem)
        assert {r['id'] for r in sections[1]['rows'][2:]}=={'knob-start','knob-finish','knob-cancel'}
        if screen=='knob':assert '4800' in sections[1]['rows'][1]['status'],'completed one-turn fixture missing'
        check_knob_step(screen,sections,lang,stem)
# What each canned glasses reports and what the knob step section must then show (docs: ds3.md item 6).
#   screen -> (firmware label, reported D, items per turn, setting enabled, stepper value, apply enabled)
KNOB_FIXTURES={'runtime':('TMG4',600,'3.3',False,None,False),'knob':('TMG4',600,'3.3',False,None,False),
    'knob-tmg8':('TMG6',300,'6.7',False,None,False),'knob-tmg9':('TMG6',400,'5.0',True,400,False),
    'knob-tmg9-confirmed':('TMG6',450,'4.4',True,450,False),'knob-tmg9-failed':('TMG6',400,'5.0',True,450,True)}
WORDS={'en':{'items':'items per turn','confirmed':'Confirmed by the glasses','failed':'Not confirmed','unavailable':'Not available','idle':'Not changed','needs':'TMG9','wrap':'wrap from the last item','nowrap':'Wrapping comes with TMG8'},
       'zh-Hans':{'items':'每圈约','confirmed':'眼镜已确认','failed':'未确认','unavailable':'这副眼镜不支持','idle':'未更改','needs':'TMG9','wrap':'回到第一项','nowrap':'首尾循环需要 TMG8'}}
def check_knob_step(screen,sections,lang,stem):
    firmware,detent,items,enabled,value,apply_enabled=KNOB_FIXTURES[screen];w=WORDS[lang];rows=sections[2]['rows'];footer=sections[2]['footer'];tag=' in '+str(stem)
    assert firmware in sections[0]['rows'][1]['status'] and ('6'*8 if firmware=='TMG6' else '4'*8) in sections[0]['rows'][1]['status'],'wrong fixture glasses'+tag
    assert str(detent) in sections[0]['rows'][6]['status'],'the status detent row must show the reported D'+tag
    assert [r['id'] for r in rows]==['knob-step-current','knob-step-choose','knob-step-apply','knob-step-result'],'step rows'+tag
    current,choose,apply,result=rows
    assert str(detent) in current['status'] and items in current['status'] and w['items'] in current['status'],'current step must show the reported D and items per turn'+tag
    assert (choose['stepperEnabled'] is not None)==True and choose['stepperEnabled']==enabled,'stepper enabled only with caps bit 10'+tag
    if value is not None:assert choose['stepperValue']==value,'stepper value'+tag
    assert choose['stepperValue'] is not None and 300<=choose['stepperValue']<=600 and choose['stepperValue']%50==0,'stepper range'+tag
    assert apply['enabled']==apply_enabled,'apply must be live only for a pending change on a TMG9 peer'+tag
    assert (han(footer) if lang=='zh-Hans' else not han(footer)),'footer language'+tag
    if not enabled:assert w['needs'] in footer and w['unavailable'] in result['status'],'the disabled setting must say it needs TMG9'+tag
    else:assert w['needs'] not in footer,'TMG9 glasses must not be told to need TMG9'+tag
    assert (w['wrap'] in footer) if screen!='knob' and screen!='runtime' else (w['nowrap'] in footer),'wrap sentence follows the TMG8 bit'+tag
    expect={'knob-tmg9':w['idle'],'knob-tmg9-confirmed':w['confirmed'],'knob-tmg9-failed':w['failed']}.get(screen)
    if expect:assert expect in result['status'],'result state'+tag+': '+result['status']
    if screen=='knob-tmg9-confirmed':assert '450' in result['status']
    text=' '.join([footer]+[r[k] for r in rows for k in ('title','status')])
    assert 'tmg8.' not in text and 'tmg9.' not in text,'untranslated key'+tag
def check_layout(screen,report,lang,stem):
    facts=report['layout'];segments=facts['segments'];tmg8=screen=='layout'
    assert [x['title'] for x in segments]==SEGMENTS[lang],'segment titles in '+str(stem)+': '+str([x['title'] for x in segments])
    assert [x['selected'] for x in segments]==([True,False,False] if tmg8 else [False,False,True]),'wrong selected layout in '+str(stem)
    assert [x['enabled'] for x in segments]==([True,True,True] if tmg8 else [False,True,True]),'Carousel must be enabled only for TMG8 glasses: '+str(stem)
    assert facts['previewIsElement'] and facts['preview'].strip(),'lens preview must be one VoiceOver element: '+str(stem)
    assert SEGMENTS[lang][0 if tmg8 else 2] in facts['preview'],'preview summary does not name the layout: '+str(stem)
    text=' '.join([facts['preview'],facts['footer']]+[r[k] for s in report['sections'] for r in s['rows'] for k in ('title','status')])
    assert 'tmg8.' not in text and 'tmg4.' not in text,'untranslated key in '+str(stem)
    assert (han(facts['footer']) if lang=='zh-Hans' else not han(facts['footer'])),'footnote language in '+str(stem)
    if tmg8:assert 'TMG8' not in facts['footer'],'TMG8 glasses must not be told to need TMG8: '+str(stem)
    else:assert 'TMG8' in facts['footer'] and 'TMG6' in facts['footer'] and 'TMG7' in facts['footer'],'older glasses footnote must name TMG8 and the version they run: '+str(stem)
    assert len(report['sections'])==5 and any(r['id']=='layout-read' for s in report['sections'] for r in s['rows']),'sections in '+str(stem)
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
            if screen in LAYOUT_SCREENS:check_layout(screen,report,lang,stem)
            if screen in PANELS:check_panel(screen,report,stem)
            sha=hashlib.sha256(png.read_bytes()).hexdigest();shas[(lang,look,size)]=sha
            receipts.append({'screen':screen,'language':lang,'appearance':look,'contentSize':size,'sha256':sha,'sections':len(report['sections'])})
        for lang in LANGS:
            assert shas[(lang,'light',STANDARD_SIZE)]!=shas[(lang,'dark',STANDARD_SIZE)],screen+' '+lang+': light and dark shots are identical'
        assert shas[('en','light',STANDARD_SIZE)]!=shas[('en','light',AX_SIZE)],screen+': accessibility size shot is identical to the default size'
    (root/'tmg4-check.json').write_text(json.dumps({'passed':True,'matrix':[[s,l,a,c] for s,l,a,c in matrix()],'screens':receipts,'deviceIO':False,'hardwareValidated':False},indent=2)+'\n')
    print('PREVIEW MATRIX PASS: '+str(len(receipts))+' shots ('+str(len(screens))+' screens x '+str(len(matrix()))+')')
if __name__=='__main__':check(Path(sys.argv[1]),sys.argv[2:])
