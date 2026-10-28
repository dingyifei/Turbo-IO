"""Assert the real injected TMG4 UI report and EN/ZH screenshot matrix."""
from pathlib import Path
import hashlib,json,sys

def han(s):return any('\u3400'<=c<='\u9fff' for c in s)
def check(root,screens):
    receipts=[]
    for screen in screens:
        if screen not in ('tiles','runtime','knob'):continue
        for lang in ('en','zh-Hans'):
            stem=root/(screen+'-'+lang);png=stem.with_suffix('.png');report=json.loads(stem.with_suffix('.json').read_text())
            assert png.stat().st_size>20000 and report['deviceIO'] is False and report['hardwareValidated'] is False
            sections=report['sections'];text=' '.join([report['screen']]+[s['title'] for s in sections]+[str(r[k]) for s in sections for r in s['rows'] for k in ('title','status')])
            assert 'tmg4.' not in text,'untranslated key in '+str(stem)
            assert not han(text) if lang=='en' else han(report['screen']), 'wrong UI language: '+str(stem)
            if screen=='tiles':
                assert not report['editing'] or report['selectionWhileEditing'],'tile actions are unselectable while reordering'
                assert len(sections)==3 and len(sections[0]['rows'])==7 and not any(r['movable'] for r in sections[0]['rows'])
                custom=sections[1]['rows'];assert len(custom)==6 and all(r['movable'] for r in custom)
                assert all(r["editingSwitch"] for r in custom if r["switchOn"] is not None),"editing mode hid visibility controls"
                assert all(r["rendered"] for r in custom),"custom tile fixture must be visible"
                switches=[r['switchOn'] for r in custom if r['switchOn'] is not None];assert len(switches)==5 and switches.count(False)==2 and switches.count(True)==3
                assert custom[0]['switchOn'] is None and custom[0]['accessory']==3,'Camera must stay visible in reversed fixture'
                assert {r['id'] for r in sections[2]['rows']}=={'tiles-read','tiles-save','tiles-reset'}
            else:
                assert len(sections)==5 and len(sections[0]['rows'])==8 and len(sections[1]['rows'])==5
                assert 'TMG4' in sections[0]['rows'][1]['status'] and '44444444' in sections[0]['rows'][1]['status']
                assert '600' in sections[0]['rows'][6]['status']
                assert {r['id'] for r in sections[1]['rows'][2:]}=={'knob-start','knob-finish','knob-cancel'}
                if screen=='knob':assert '4800' in sections[1]['rows'][1]['status'],'completed one-turn fixture missing'
            receipts.append({'screen':screen,'language':lang,'sha256':hashlib.sha256(png.read_bytes()).hexdigest(),'sections':len(sections)})
    (root/'tmg4-check.json').write_text(json.dumps({'passed':True,'screens':receipts,'deviceIO':False,'hardwareValidated':False},indent=2)+'\n')
    print('TMG4 PREVIEW PASS: '+str(len(receipts))+' EN/ZH reports/screens')
if __name__=='__main__':check(Path(sys.argv[1]),sys.argv[2:])
