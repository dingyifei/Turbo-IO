"""Keep all original includes/callees except explicitly removed module symbols."""
from pathlib import Path
import re
import sys

old,new = map(Path,sys.argv[1:])
files = ['music-runtime-v1/menu10.c','focus-v1/focus_menu_native.c',
         'camera-v1/camera_native.c','navigation-runtime-v1/nav_service.c',
         'app-runtime-v1/app_service.c','focus-v1/focus_service.c','music-runtime-v1/music_service.c']
removed = re.compile(r'^(dr_\w+|wr_slot_\w+|wr_handle_event|wr_file_receive|wr_message_\w+|dots_\w+|ce_slot_\w+|ce_native_\w+|ce_menu_slot|ce_message_\w+|reader|ride|dots_menu_slot)$')
# TMG5: the static square cover replaces the rotating artwork (user-approved 2026-10-28).
# Exact names only; add nothing here without user approval.
TMG5_REMOVED = {'tm_rotate'}
keywords = {'if','else','while','for','switch','return','sizeof','_Alignas','_Static_assert',
            'void','bool','char','int','unsigned','uint8_t','uint16_t','uint32_t','int16_t','int32_t','uintptr_t','size_t'}
errors = []
def code(s):
    return re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"', ' ',s,flags=re.S)
for name in files:
    before=(old/'src'/name).read_text();after=(new/'src'/name).read_text()
    for line in re.findall(r'^#include[^\n]+',before,re.M):
        if 'reader_input.h' in line:
            line='#include "../common-v1/wheel_input.h"'
        elif re.search(r'context-english-v1/|dots-v1/|didi-v1/|weread-v1/',line):
            continue
        if line not in after:errors.append(name+': missing '+line)
    current=set(re.findall(r'\b[A-Za-z_]\w*\b',code(after)))
    for identifier in set(re.findall(r'\b([A-Za-z_]\w*)\s*\(',code(before))):
        if identifier not in keywords and not removed.match(identifier) and identifier not in TMG5_REMOVED and identifier not in current:
            errors.append(name+': missing '+identifier)
if errors:raise SystemExit('\n'.join(sorted(errors)))
print('KEPT_OK: original includes and retained call identifiers survived')
