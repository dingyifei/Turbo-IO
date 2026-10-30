"""Find compiled CJK string literals outside the dedicated firmware table."""
from pathlib import Path
import json
import re
import sys
fw=Path(sys.argv[1]);d=json.loads((fw/'build-inputs.json').read_text())
paths={fw/'src'/x['source'] for x in d['sources']}|{fw/x['path'] for x in d['extras']}
paths|=set((fw/'src').rglob('*.h'))|set((fw/'src').rglob('*.inc'))
paths|={fw/'src/navigation-runtime-v1/nav_map.c',fw/'src/menu-grid-v2/menu_config.c'}
errors=[]
for p in sorted(paths):
 if p==fw/'src/common-v1/tio_text.c' or p.name.endswith('_test.c'):continue
 source=p.read_text()
 for match in re.finditer(r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/',source,re.S):
  if match[1] and re.search('[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]',match[1]):
   errors.append(str(p.relative_to(fw))+':'+str(source.count('\n',0,match.start())+1))
if errors:raise SystemExit('\n'.join(errors))
print('CJK_OK: compiled firmware strings are table-driven')
