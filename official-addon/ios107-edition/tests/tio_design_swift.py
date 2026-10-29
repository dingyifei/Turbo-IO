"""TIODesign.swift must carry the same tokens as docs/design-system/tokens.json
and type-check under the Swift 5 (Apple AI) and Swift 6 (offline captions)
modes. The Swift file imports UIKit, which the macOS host cannot run, so values
are compared as text. Usage: tio_design_swift.py tokens.json TIODesign.swift"""
import json,re,subprocess,sys
from pathlib import Path

def numbers(value):
    return [float(p[:-2] if p.endswith('px') else p) for p in value.split()]

def table(source,name):
    m=re.search(r'static let '+name+r':[^=]*=\s*\[(.*?)\n    \]',source,re.S)
    assert m,name+' table missing'
    return m.group(1)

def main(tokens,swift):
    spec=json.loads(Path(tokens).read_text());source=Path(swift).read_text()
    colors=table(source,'colorTable')
    found={n:(int(a,16),int(b,16)) for n,a,b in re.findall(r'"([a-z0-9-]+)":\s*\(0x([0-9a-f]{6}),\s*0x([0-9a-f]{6})\)',colors)}
    want={}
    for token in spec['color']['tokens']:
        v=token['value']
        want[token['name']]=tuple(int((v[k] if isinstance(v,dict) else v)[1:],16) for k in ('light','dark'))
    assert found==want,'colors differ: '+str(sorted(set(found.items())^set(want.items()))[:6])
    types=table(source,'typeTable')
    found={n:(float(s),int(w)) for n,s,w in re.findall(r'"([a-z0-9-]+)":\s*\((\d+),\s*(\d+)\)',types)}
    want={s['name']:(numbers(s['fontSize'])[0],s['fontWeight']) for s in spec['type']['groups'][0]['styles']}
    assert found==want,'type styles differ'
    nums=table(source,'numberTable')
    found={n:float(v) for n,v in re.findall(r'"([a-z0-9-]+)":\s*(\d+),',nums)}
    want={t['name']:numbers(t['value'])[0] for g in ('spacing','radius','size') for t in spec[g]['tokens']}
    assert found==want,'numbers differ'
    block=source[source.index('enum Color'):source.index('enum TextStyle')]
    names={raw or case for case,raw in re.findall(r'(?:case |, )(\w+)(?: = "([a-z0-9-]+)")?',block) if case not in ('Color','String','CaseIterable')}
    assert names=={t['name'] for t in spec['color']['tokens']},'Color enum names differ from tokens'
    for version in ('5','6'):
        sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
        subprocess.run(['xcrun','--sdk','iphoneos','swiftc','-typecheck','-swift-version',version,'-target','arm64-apple-ios26.0','-sdk',sdk,swift],check=True)
    print('PASS TIODesign.swift matches tokens.json')

if __name__=='__main__':main(*sys.argv[1:3])
