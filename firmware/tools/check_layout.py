"""Refuse raw stock offsets, extents and queue ids in the firmware tree. Never connects to a device.

  python3 -I firmware/tools/check_layout.py firmware              # check the tree
  python3 -I firmware/tools/check_layout.py --self-test firmware  # plant one hit per rule in a copy and require each

Every stock object offset, size and id the tree uses has one name in src/stock_layout.h, proven from the stock image
by tests/stock_layout_test.py. This lint makes sure the code uses those names: a numeric literal (0 included) in one
of the positions below is refused. Comments and the contents of string and character literals are blanked first. There
is no allowance for literal arithmetic: a stride or width is written sizeof(uint32_t), for example
ptr(app,TIO_STOCK_MENU_ROWS+sizeof(uint32_t)*i).

Literals are hex, binary, octal, decimal and floating. Line breaks are whitespace like any other. Redundant
parentheses around a lone literal or identifier are ignored, so (0x98) reads as 0x98.

Rules (C files and headers unless noted):
  cast      a byte-view cast plus a literal: (uint8_t *)X + N, (char *)X + N, (unsigned char *)X + N,
            (int8_t *)X + N, with or without const, also through a cast chain such as (uint8_t *)(uintptr_t)X + N,
            and with the literal first. Any literal in the added expression is refused.
  helper    any literal in the offset argument of a helper: a function or function-like macro whose body adds that
            parameter to a byte view (a byte-view cast, or a byte-pointer local initialised from one or from a
            parameter), in either order and in parentheses or not. Helpers are found in the file and in every
            in-scope header it sees: its includes followed transitively, plus src/firmware_profile.h (which build.py
            and the host tests force-include) and that header's includes. They are not listed by name.
  wordcast  a pointer cast of (X + expression with a literal): (uint32_t *)(app + 0x98) and every other pointer view,
            also with scalar casts between them, (uint32_t *)(uintptr_t)(app + 0x98), or inside, ((uintptr_t)app+N).
  index     a pointer view indexed with a literal: ((uint32_t *)X)[3], or N[(uint32_t *)X], and every other pointer
            view.
  abs       a cast of an absolute address (any integer literal) in a stock window (either base's AP flash, RAM, the
            copy region), unless the address is a value of the active rebase table on the tree's base (F2's tools
            prove those sites). The windows must agree with rebase_apply.leftovers() on every edge.
  addr      (a) a literal plus a literal where either is in 0x10000000..0x1fffffff (stock flash, stock RAM and the
            test models' fake bases); (b) a literal added to an identifier of
            the receiver table inside its function; (c) any literal in the extent (second) argument of ram( in
            render_idle.c.
  asm       in .S files, a memory operand [rN,#imm] whose immediate is not one TIO_STOCK_* name, and a bare [rN],
            for any base register other than sp and pc.
  queue     any literal in the first argument of a call to stream_queue_send, or to a parameter of the enclosing
            function declared with type TIOCopyEnqueue.

Scope: the built set (build-inputs.json sources and extras and the .c files they include), the C test models
(tests/*.c and the two test files under src/ that test.py runs), and the headers (every .h under src/ and include/,
and ImageWireFormat.h). Exemptions are a whole file or file + rule + the exact matched text and its hit count, each
with a reason; a stale one, or one whose count changed, fails. Guarded deferrals hold only while their guard file
still starts with the three-line "not ported to 1.0.6.11 yet" guard, and each deferred file's hits are pinned exactly
(rule, text, count). The tool also pins the set of link.ld symbols that nothing references.
"""
import functools
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rebase_apply  # noqa: E402  (read-only use: the active table and the flash base)

SRC_TESTS = ('src/image-upload-test/render_idle_test.c', 'src/image-upload-test/native_file_bridge_test.c')

# Whole-file exemptions (E1 to E3) and exact-text exemptions (E4 to E7). Never a line number or a function name.
EXEMPT_FILES = (
    ('E1', 'src/dashboard-v1/native.c', 'A2UI subsystem: out of scope for this port, not studied'),
    ('E2', 'src/dashboard-editor-v1/editor_native.c', 'A2UI subsystem: out of scope for this port, not studied'),
    ('E3', 'src/common-v1/coexist.S', 'a copy of stock code (labels CEL_<old address>); its offsets are stock\'s own '
           'and match stock nav_business_idle'),
)
# Each key is (rule, exact text, number of hits it must match): a second copy of an exempt text is refused too.
EXEMPT_TEXTS = (
    ('E4', 'src/app-runtime-v1/app_store.c', (('cast', '(char *)p+20', 1), ('cast', '(char *)p+44', 1)),
     'the module\'s own TAI1 store record, not a stock object'),
    ('E5', 'src/navigation-runtime-v1/nav_map.c', (('cast', '(const char *)p+8', 1),),
     'the module\'s own navigation wire body'),
    ('E6', 'src/menu8-native-lvgl.c', (('cast', '(const uint8_t*)decoder+0x10', 1),),
     'the stock PNG decoder\'s name field has no second witness; png_type validates itself and only returns false'),
    ('E7', 'trampolines.S', (('asm', 'str r3,[r0]', 1),),
     'the shim replays stock\'s own store to file callback slot +0 from the edited range; the witness test checks '
     'the edit\'s before-bytes hold that store'),
)
# Rule addr (b): file, function, identifiers that hold stock addresses read from stock memory.
RECEIVERS = (
    ('src/image-upload-test/render_idle.c', 'tio_render_graph_idle', ('unit', 'display', 'layer')),
)
# Guarded deferrals: the files whose hits are deferred, valid while the guard file keeps its guard. Each file's hits
# are pinned exactly (rule, text, count), so a new or changed raw offset in a deferred file is refused, and so is a
# removed one (the pin is then stale and must be updated in the same change).
_R = 'src/global-remote-v1/remote_native.c'
DEFERRALS = (
    ('G1', {_R: (('cast', '(uint8_t*)t+8', 2), ('cast', '(uint8_t*)t+12', 3), ('cast', '(uint8_t *)app+0x88', 2),
                 ('cast', '(uint8_t *)app+0xa0', 1), ('cast', '(uint8_t *)app+0x90', 1),
                 ('wordcast', '(Control**)((uint8_t*)t+12)', 3),
                 ('wordcast', '(uint32_t *)((uint8_t *)app+0x88)', 2),
                 ('wordcast', '(uint32_t *)((uint8_t *)app+0xa0)', 1),
                 ('wordcast', '(uint32_t *)((uint8_t *)app+0x90)', 1),
                 ('wordcast', '(int16_t*)(driver+6)', 1)),
            'src/menu-grid-v2/menu_config.c': ()},
     _R,
     'the phone test tile_roundtrip.py compiles this file by exact text with no base define; F4 moves it with the '
     'tile protocol'),
    ('G2', {'tests/native_remote_test.c': (('wordcast', '(uint32_t *)(app+0xa0)', 3),
                                           ('wordcast', '(uint32_t *)(app+0x88)', 3))},
     _R, 'included by tests/tile_roundtrip_bridge.c in that phone test'),
)
GUARD_LINE_1 = '#if defined(TD_STOCK_10611) && TD_STOCK_10611'
GUARD_LINE_2 = '#error not ported to 1.0.6.11 yet: '
GUARD_LINE_3 = '#endif'
# link.ld symbols referenced by no built file, header or edit target. The F4 prune changes this list in its commit.
UNREFERENCED = ()
RULES = ('cast', 'helper', 'wordcast', 'index', 'abs', 'addr', 'asm', 'queue')
# The stock windows of rule abs. The flash window comes from rebase_apply (FLASH and the table's AP sizes). The RAM
# start is rebase_apply.DATA_RUNTIME. The RAM end and the copy region are written in rebase_apply only inside
# leftovers(), so they are repeated here, and check() runs leftovers() on both edges of every window: if the two
# tools ever disagree, the lint fails.
RAM_WINDOW = (rebase_apply.DATA_RUNTIME, 0x1a000000)
COPY_WINDOW = (0x100000, 0x101000)
# Rule addr (a): the 0x1xxxxxxx region, where stock flash, stock RAM and the test models' fake bases all lie.
# Larger literals (a Unix epoch, a timer wrap value, an LCG multiplier in the test models) are not addresses.
ADDR_REGION = (0x10000000, 0x20000000)

# Hex, binary, decimal (octal) integers and floats, with suffixes.
NUM = r'(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\d[\d.]*(?:[eE][+-]?\d+)?|\.\d+)[uUlLfF]*'
LITERAL = re.compile(r"(?<![\w.])" + NUM + r"(?![\w.])|'[^'\n]*'")
INT_BODY = r'(0[xX][0-9a-fA-F]+|0[bB][01]+|\d+)[uUlL]*'
INT = re.compile(r'(?<![\w.])' + INT_BODY + r'(?![\w.])')
IDENT = r'[A-Za-z_]\w*'
WS = ' \t\r\n\f\v'
BYTE_TYPE = r'(?:uint8_t|int8_t|char|unsigned\s+char|signed\s+char)'
BYTEVIEW = re.compile(r'\(\s*(?:const\s+|volatile\s+)*' + BYTE_TYPE + r'\s*(?:const\s*)?\*\s*\)')
# A byte pointer declaration: const uint8_t *name = ...
BYTE_DECL = re.compile(r'(?<![\w.>])(?:const\s+|volatile\s+)*' + BYTE_TYPE +
                       r'\s*(?:const\s*)?\*\s*(?:const\s+)?(' + IDENT + r')\s*(=)?')
# Any pointer type in a cast: one or more words, then one or more stars.
PTRVIEW = re.compile(r'\(\s*((?:' + IDENT + r'\s+)*' + IDENT + r'\s*(?:const\s*)?(?:\*\s*(?:const\s*)?)+)\)')
# A scalar (non-pointer) type name in a cast: the builtin integer and floating types and any name ending in _t.
SCALAR_GROUP = re.compile(r'\(\s*(?:(?:const|volatile|unsigned|signed|long|short)\s+)*(?:unsigned|signed|int|long|'
                          r'short|char|void|bool|_Bool|float|double|' + r'\w+_t)\s*(?:(?:int|long)\s*)*\)')


def c_int(s):
    """The value of a C integer literal body (hex, binary, octal or decimal)."""
    s = s.lower()
    if s.startswith('0x'):
        return int(s, 16)
    if s.startswith('0b'):
        return int(s[2:], 2)
    if len(s) > 1 and s.startswith('0'):
        return int(s, 8) if re.fullmatch(r'[0-7]+', s) else int(s, 10)
    return int(s, 10)


def type_group(text):
    """True when `text`, a whole parenthesised group, is a cast's type name: any pointer type or a scalar type."""
    return PTRVIEW.fullmatch(text) is not None or SCALAR_GROUP.fullmatch(text) is not None
KEYWORDS = {'if', 'for', 'while', 'switch', 'return', 'sizeof', 'case', 'else', 'do', 'goto', '_Static_assert',
            'defined', '_Alignof', 'alignof', 'typeof', '__typeof__', '__attribute__', 'asm', '__asm__'}
TYPE_START = re.compile(r'\s*(?:const\s+|volatile\s+|static\s+|register\s+)*(?:unsigned|signed|int|long|short|char|'
                        r'void|bool|float|double|size_t|uintptr_t|intptr_t|u?int\d+_t|struct\s+\w+|TIO\w+)\b')
DELIMS = set(',;)]}?:<>=!&|^')
# A cast of an integer literal (hex, binary, octal or decimal): (T)0x..., (T *)402653248u
ABS_CAST = re.compile(r'\(\s*((?:' + IDENT + r'\s+)*' + IDENT + r'\s*\**)\s*\)\s*' + INT_BODY + r'(?![\w.])')
# Words after which a parenthesised group is an operand, not a call's argument list.
OPERAND_AFTER = {'return', 'case', 'else', 'do'}


class Hit:
    def __init__(self, path, line, rule, text):
        self.path, self.line, self.rule, self.text = path, line, rule, text

    def key(self):
        return (self.path, self.rule, self.text)

    def __str__(self):
        return '%s:%d: %s: %s' % (self.path, self.line, self.rule, self.text)


@functools.lru_cache(maxsize=None)
def blank_c(text, asm=False):
    """Comments become spaces; string (and in C, character) literal contents become spaces. Length and newlines are
    kept. With asm=True, '@' also starts a comment to the end of the line, and a quote mark is not a character
    literal."""
    out, i, n = [], 0, len(text)
    quotes = '"' if asm else '"\''
    while i < n:
        c = text[i]
        if text.startswith('/*', i):
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r'[^\n]', ' ', text[i:j]))
            i = j
        elif text.startswith('//', i) or (asm and c == '@'):
            j = text.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i))
            i = j
        elif c in quotes:
            j = i + 1
            while j < n and text[j] != c and text[j] != '\n':
                j += 2 if text[j] == '\\' else 1
            j = min(j, n - 1)
            out.append(c + re.sub(r'[^\n]', ' ', text[i + 1:j]) + text[j])
            i = j + 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def has_literal(expr):
    return LITERAL.search(expr) is not None


def line_of(text, pos):
    return text.count('\n', 0, pos) + 1


def match_paren(text, i):
    """Index of the bracket closing the one at text[i] (any of ( [ {), or -1."""
    pairs = {'(': ')', '[': ']', '{': '}'}
    stack = []
    for j in range(i, len(text)):
        c = text[j]
        if c in pairs:
            stack.append(pairs[c])
        elif c in ')]}':
            if not stack or stack.pop() != c:
                return -1
            if not stack:
                return j
    return -1


@functools.lru_cache(maxsize=None)
def strip_parens(t):
    """Blank the redundant parentheses around a lone literal or identifier, keeping length and newlines, so that
    (0x98)+(uint8_t *)t, (0x1850ce1c)+0x124 and (display)+0x2a0 read like their plain forms. A group is kept when it
    is a call's argument list (an identifier other than return/case/else/do just before it), when it is a cast's type
    name, and, for an identifier, when an operand follows it (it may be a cast of a typedef name)."""
    pat = re.compile(r'\(\s*(' + NUM + r'|' + IDENT + r')\s*\)')
    while True:
        out, changed = list(t), False
        for m in pat.finditer(t):
            k = m.start() - 1
            while k >= 0 and t[k] in WS:
                k -= 1
            if k >= 0 and (t[k].isalnum() or t[k] == '_'):
                w = k
                while w > 0 and (t[w - 1].isalnum() or t[w - 1] == '_'):
                    w -= 1
                if t[w:k + 1] not in OPERAND_AFTER:
                    continue
            word = m.group(1)
            if not re.match(r'[\d.]', word):
                if type_group(m.group(0)):
                    continue
                nxt = re.compile(r'[' + WS + r']*(.)', re.S).match(t, m.end())
                if nxt and re.match(r"[\w(\"']", nxt.group(1)):
                    continue
            out[m.start()] = ' '
            out[m.end() - 1] = ' '
            changed = True
        t = ''.join(out)
        if not changed:
            return t


def span_text(raw, t, a, b):
    """The source text of a hit at t[a:b], widened over parentheses that strip_parens blanked at its edges."""
    a2, b2 = a, b
    while a2 > 0 and t[a2 - 1] in WS and raw[a2 - 1] in '(' + WS:
        a2 -= 1
    while b2 < len(t) and t[b2] in WS and raw[b2] in ')' + WS:
        b2 += 1
    s = raw[a2:b2].strip()
    while s.startswith('(') and s.count('(') > s.count(')'):
        s = s[1:].strip()
    while s.endswith(')') and s.count(')') > s.count('('):
        s = s[:-1].strip()
    return s if s.count('(') == s.count(')') else raw[a:b].strip()


def operand_end(text, i):
    """End of a cast operand (a unary/postfix expression) that starts at text[i], or -1. A leading cast (a
    parenthesised type name) is part of the operand: (uint8_t *)(uintptr_t)t+8 has the operand (uintptr_t)t."""
    n = len(text)
    while i < n and text[i] in WS:
        i += 1
    while i < n and text[i] in '*&':
        i += 1
        while i < n and text[i] in WS:
            i += 1
    if i < n and text[i] == '(':
        j = match_paren(text, i)
        if j < 0:
            return -1
        if type_group(text[i:j + 1]):
            e = operand_end(text, j + 1)
            if e >= 0:
                return e
        i = j + 1
    else:
        m = re.compile(IDENT).match(text, i)
        if not m:
            return -1
        i = m.end()
    while True:
        m = re.compile(r'\s*(?:->|\.)\s*' + IDENT).match(text, i)
        if m:
            i = m.end()
            continue
        m = re.compile(r'\s*[\[(]').match(text, i)
        if m:
            j = match_paren(text, m.end() - 1)
            if j < 0:
                return -1
            i = j + 1
            continue
        return i


def additive_end(text, i):
    """End of the additive expression that starts at text[i]: stops at a depth-0 delimiter."""
    n, depth = len(text), 0
    while i < n:
        c = text[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            if depth == 0:
                return i
            depth -= 1
        elif depth == 0 and c in DELIMS:
            if c in '<>' and text.startswith(c * 2, i):  # a shift is still arithmetic
                i += 2
                continue
            return i
        i += 1
    return n


def split_args(text, open_paren):
    """(arguments, index of the closing paren) of the call whose '(' is at text[open_paren]."""
    close = match_paren(text, open_paren)
    if close < 0:
        return None, -1
    args, depth, cur = [], 0, open_paren + 1
    for j in range(open_paren + 1, close):
        c = text[j]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ',' and depth == 0:
            args.append((cur, j))
            cur = j + 1
    args.append((cur, close))
    return args, close


@functools.lru_cache(maxsize=None)
def functions(text):
    """(name, params text, start, body open, body close) of each function definition in blanked C text."""
    out = []
    for m in re.finditer(r'\b(' + IDENT + r')\s*\(', text):
        name = m.group(1)
        if name in KEYWORDS:
            continue
        close = match_paren(text, m.end() - 1)
        if close < 0:
            continue
        k = close + 1
        while k < len(text) and text[k] in ' \t\n':
            k += 1
        if k >= len(text) or text[k] != '{':
            continue
        pre = text[:m.start()].rstrip()
        if not pre or not (re.search(r'[\w*]$', pre)) or re.search(r'\b(?:return|else)$', pre):
            continue
        end = match_paren(text, k)
        if end < 0:
            continue
        out.append((name, text[m.end():close], m.start(), k, end))
    return tuple(out)


def param_names(params):
    names = []
    for p in params.split(','):
        p = p.strip()
        fp = re.search(r'\(\s*\*\s*(' + IDENT + r')\s*\)', p)
        if fp:
            names.append(fp.group(1))
            continue
        m = re.search(r'(' + IDENT + r')\s*(?:\[[^\]]*\])?\s*$', p)
        names.append(m.group(1) if m and m.group(1) not in ('void',) and len(p.split()) + p.count('*') > 1 else '')
    return names


def declared_in(text, fn, ident):
    """True when `ident` is a parameter of fn or declared in a declaration statement of its body."""
    name, params, start, body_open, body_close = fn
    if ident in param_names(params):
        return True
    body = text[body_open + 1:body_close]
    for stmt in re.split(r'[;{}]', body):
        m = TYPE_START.match(stmt)
        if not m:
            continue
        rest = stmt[m.end():]
        depth, cur, parts = 0, '', []
        for c in rest:
            if c in '([':
                depth += 1
            elif c in ')]':
                depth -= 1
            if c == ',' and depth == 0:
                parts.append(cur)
                cur = ''
            else:
                cur += c
        parts.append(cur)
        for part in parts:
            d = re.match(r'\s*\**\s*(' + IDENT + r')\s*(?:=|\[|$)', part)
            if d and d.group(1) == ident:
                return True
    return False


def byte_names(body, params):
    """Locals of `body` that hold a byte view: a byte pointer initialised from a byte-view cast, from a parameter or
    from another such local (const uint8_t *b=base;), followed in declaration order."""
    names = set()
    for m in BYTE_DECL.finditer(body):
        if not m.group(2):
            continue
        init = body[m.end():additive_end(body, m.end())]
        if BYTEVIEW.search(init):
            names.add(m.group(1))
            continue
        e = operand_end(init, 0)
        core = re.sub(r'^[\s(]*', '', init)
        while True:  # drop leading casts
            g = re.match(r'\s*(\([^()]*\))', core)
            if g and type_group(g.group(1)):
                core = core[g.end():]
            else:
                break
        w = re.match(r'\s*(' + IDENT + r')\b', core)
        if e >= 0 and w and (w.group(1) in params or w.group(1) in names):
            names.add(m.group(1))
    return names


def adds_param(body, params):
    """Indexes of `params` that `body` adds to a byte view (a byte-view cast or a byte_names local), in either order;
    the parameter may sit anywhere in the added expression, in parentheses or not."""
    out = set()
    names = byte_names(body, params)
    starts = []  # (start of the byte view, end of its operand)
    for b in BYTEVIEW.finditer(body):
        e = operand_end(body, b.end())
        if e >= 0:
            starts.append((b.start(), e))
    for nm in names:
        for m in re.finditer(r'(?<![\w.>])' + re.escape(nm) + r'\b(?!\s*[\[(]|\s*->|\s*\.)', body):
            starts.append((m.start(), m.end()))
    for s, e in starts:
        plus = re.compile(r'\s*\+(?![+=])').match(body, e)
        added = body[plus.end():additive_end(body, plus.end())] if plus else ''
        # the operands added before it, back to the nearest delimiter: off+(const uint8_t *)base
        before = re.search(r'([^;{}?:,=(\[]*?)(?<!\+)\+\s*$', body[:s])
        lead = before.group(1) if before else ''
        for k, pn in enumerate(params):
            if pn and (re.search(r'\b' + re.escape(pn) + r'\b', added) or
                       re.search(r'\b' + re.escape(pn) + r'\b', lead)):
                out.add(k)
    return out


def macro_defs(text):
    """(name, parameter names, body, start) of each function-like macro in blanked C text (continued lines joined)."""
    out = []
    for m in re.finditer(r'(?m)^[ \t]*#[ \t]*define[ \t]+(' + IDENT + r')\(([^)]*)\)', text):
        end = m.end()
        while True:
            nl = text.find('\n', end)
            if nl < 0:
                end = len(text)
                break
            if text[:nl].rstrip(' \t\r').endswith('\\'):
                end = nl + 1
                continue
            end = nl
            break
        params = [p.strip() for p in m.group(2).split(',')]
        out.append((m.group(1), params, text[m.end():end].replace('\\\n', '  '), m.start()))
    return out


@functools.lru_cache(maxsize=None)
def find_helpers(text):
    """name -> parameter indexes that the helper's body adds to a byte view. Helpers are functions and function-like
    macros."""
    out = {}
    for name, params, start, body_open, body_close in functions(text):
        k = adds_param(text[body_open:body_close + 1], param_names(params))
        if k:
            out.setdefault(name, set()).update(k)
    for name, params, body, start in macro_defs(text):
        k = adds_param(body, params)
        if k:
            out.setdefault(name, set()).update(k)
    return out


def call_sites(text, name):
    """Positions of '(' for calls of `name` (not member calls, not definitions or prototypes)."""
    defs = {s for (n, p, s, o, c) in functions(text) if n == name}
    for m in re.finditer(r'(?<![\w.>])' + re.escape(name) + r'\s*\(', text):
        if m.start() in defs:
            continue
        yield m


def is_declaration_arg(arg):
    return TYPE_START.match(arg) is not None and re.match(r'\s*(?:const\s+)?\w+(?:\s+\w+)*\s*\**\s*\w*\s*$', arg)


def scan_c(rel, raw, helper_map, abs_ok, windows):
    t = strip_parens(blank_c(raw))
    hits = []

    def add(rule, a, b):
        hits.append(Hit(rel, line_of(t, a), rule, span_text(raw, t, a, b)))

    # cast: (byte *)X + expr with a literal
    for b in BYTEVIEW.finditer(t):
        e = operand_end(t, b.end())
        if e < 0:
            continue
        m = re.compile(r'\s*\+(?![+=])\s*').match(t, e)
        if m:
            end = additive_end(t, m.end())
            if has_literal(t[m.end():end]):
                add('cast', b.start(), end)
        # the same with the literal written first: N + (byte *)X
        m = re.search(r'(?<![\w.])' + NUM + r'\s*\+\s*$', t[max(0, b.start() - 40):b.start()])
        if m and e > 0:
            add('cast', max(0, b.start() - 40) + m.start(), e)
    # helper: a literal in the offset argument of a byte-view helper
    for name, idxs in helper_map.items():
        for m in call_sites(t, name):
            args, close = split_args(t, m.end() - 1)
            if args is None:
                continue
            for k in idxs:
                if k < len(args):
                    a, b = args[k]
                    if is_declaration_arg(t[a:b]):
                        continue
                    if has_literal(t[a:b]):
                        add('helper', m.start(), close + 1)
                        break
    # wordcast and index: pointer views of (X + literal) and pointer views indexed with a literal
    for p in PTRVIEW.finditer(t):
        typ = p.group(1)
        if re.match(r'\s*(?:return|sizeof|case|if|while|else)\b', typ):
            continue
        # look through intervening scalar casts: (uint32_t *)(uintptr_t)(app+0x98)
        k = p.end()
        while True:
            g = re.compile(r'\s*\(').match(t, k)
            if not g:
                break
            gc = match_paren(t, g.end() - 1)
            if gc < 0 or not SCALAR_GROUP.fullmatch(t[g.end() - 1:gc + 1]):
                break
            k = gc + 1
        after = re.compile(r'\s*\(').match(t, k)
        if after:
            o = after.end() - 1
            c = match_paren(t, o)
            if c > 0:
                inner = t[o + 1:c]
                e = operand_end(inner, 0)
                m = re.compile(r'\s*\+(?![+=])').match(inner, e) if e > 0 else None
                first = re.match(r'\s*' + NUM + r'\s*\+', inner)  # the literal written first: (T *)(N + X)
                if (m and has_literal(inner[m.end():])) or first:
                    add('wordcast', p.start(), c + 1)
        # index: ( (T *)X )[N]
        if p.start() > 0:
            q = t.rfind('(', 0, p.start())
            if q >= 0 and t[q + 1:p.start()].strip() == '':
                c = match_paren(t, q)
                if c > 0:
                    m = re.compile(r'\s*\[').match(t, c + 1)
                    if m:
                        e = match_paren(t, m.end() - 1)
                        if e > 0 and has_literal(t[m.end():e]):
                            add('index', q, e + 1)
        # index written the other way round: N[(T *)X]
        lb = re.search(r'(?<![\w.])' + NUM + r'\s*\[\s*$', t[max(0, p.start() - 40):p.start()])
        if lb:
            a = max(0, p.start() - 40) + lb.start()
            e = match_paren(t, t.index('[', a))
            if e > 0:
                add('index', a, e + 1)
    # abs: a cast of an absolute stock-window address that is not a table value
    for m in ABS_CAST.finditer(t):
        if m.group(1).split()[0] in KEYWORDS:
            continue
        v = c_int(m.group(2))
        if any(lo <= v < hi for lo, hi in windows) and v not in abs_ok:
            add('abs', m.start(), m.end())
    # addr (a): literal + literal where either lies in the stock and fake-base address region
    for m in re.finditer(INT.pattern + r'\s*\+(?![+=])\s*' + INT.pattern, t):
        a, b = c_int(m.group(1)), c_int(m.group(2))
        if any(ADDR_REGION[0] <= v < ADDR_REGION[1] for v in (a, b)):
            add('addr', m.start(), m.end())
    # queue: a literal in the first argument of a queue send
    for m in call_sites(t, 'stream_queue_send'):
        args, close = split_args(t, m.end() - 1)
        if args and not is_declaration_arg(t[args[0][0]:args[0][1]]) and has_literal(t[args[0][0]:args[0][1]]):
            add('queue', m.start(), close + 1)
    for name, params, start, body_open, body_close in functions(t):
        for pm in re.finditer(r'\bTIOCopyEnqueue\s+(' + IDENT + r')', params):
            q = pm.group(1)
            for m in re.finditer(r'(?<![\w.>])(?:' + re.escape(q) + r'|\(\s*\*\s*' + re.escape(q) + r'\s*\))\s*\(',
                                 t[:body_close]):
                if m.start() <= body_open:
                    continue
                args, close = split_args(t, m.end() - 1)
                if args and has_literal(t[args[0][0]:args[0][1]]):
                    add('queue', m.start(), close + 1)
    return hits, t


def scan_receivers(rel, raw, t, stale):
    """Rule addr (b) and (c) for render_idle.c; `stale` collects receiver rows whose identifier is not declared."""
    hits = []
    fns = functions(t) if any(r[0] == rel for r in RECEIVERS) else ()
    for path, fname, idents in RECEIVERS:
        if path != rel:
            continue
        fn = next((f for f in fns if f[0] == fname), None)
        if fn is None:
            stale.append('receiver row %s %s: function not found' % (path, fname))
            continue
        for ident in idents:
            if not declared_in(t, fn, ident):
                stale.append('receiver row %s %s %s: identifier not declared in that function (stale row)'
                             % (path, fname, ident))
                continue
            body_open, body_close = fn[3], fn[4]
            for m in re.finditer(r'(?<![\w.>])' + ident + r'\s*(?:\+(?![+])=?)\s*', t[:body_close]):
                if m.start() <= body_open:
                    continue
                end = additive_end(t, m.end())
                if has_literal(t[m.end():end]):
                    hits.append(Hit(rel, line_of(t, m.start()), 'addr', span_text(raw, t, m.start(), end)))
            for m in re.finditer(r'(?:' + NUM + r')\s*\+\s*' + ident + r'\b', t[body_open:body_close]):
                a = body_open + m.start()
                if re.match(r'[\w.]', t[a - 1]):
                    continue
                hits.append(Hit(rel, line_of(t, a), 'addr', span_text(raw, t, a, body_open + m.end())))
    if rel == 'src/image-upload-test/render_idle.c':
        for m in call_sites(t, 'ram'):
            args, close = split_args(t, m.end() - 1)
            if args and len(args) > 1 and not is_declaration_arg(t[args[1][0]:args[1][1]]) and \
                    has_literal(t[args[1][0]:args[1][1]]):
                hits.append(Hit(rel, line_of(t, m.start()), 'addr', span_text(raw, t, m.start(), close + 1)))
    return hits


# The base register may be a macro argument (\b).
ASM_OPERAND = re.compile(r'\[\s*(\\?[A-Za-z]\w*)\s*(?:,\s*([^\]]*))?\]')
ASM_NOT_BASE = {'sp', 'pc', 'r13', 'r15'}


def scan_asm(rel, raw):
    t = blank_c(raw, asm=True)
    hits = []
    for m in ASM_OPERAND.finditer(t):
        reg, rest = m.group(1).lower(), m.group(2)
        if reg in ASM_NOT_BASE:
            continue
        bad = False
        if rest is None:
            bad = True
        else:
            rest = rest.strip()
            if rest.startswith('#'):
                bad = re.fullmatch(r'#\s*TIO_STOCK_\w+', rest) is None
            else:
                bad = has_literal(rest) and not re.match(r'[A-Za-z]\w*\s*,\s*(?:lsl|lsr|asr|ror)\b', rest, re.I)
        if bad:
            s = t.rfind('\n', 0, m.start()) + 1
            e = t.find('\n', m.end())
            e = len(t) if e < 0 else e
            stmt = t[s:e]
            # the statement that holds the operand (statements on one line may be separated by ';')
            off = m.start() - s
            a = stmt.rfind(';', 0, off) + 1
            b = stmt.find(';', off)
            b = len(stmt) if b < 0 else b
            text = re.sub(r'^\s*(?:\w+:\s*)*', '', raw[s + a:s + b]).strip()
            hits.append(Hit(rel, line_of(t, m.start()), 'asm', text))
    return hits


def guarded(fw, rel):
    p = fw / rel
    if not p.is_file():
        return False
    lines = p.read_text(errors='replace').split('\n')
    return len(lines) >= 3 and lines[0] == GUARD_LINE_1 and lines[1].startswith(GUARD_LINE_2) and \
        lines[2] == GUARD_LINE_3


def built_files(fw, errors):
    spec = json.loads((fw / 'build-inputs.json').read_text())
    files = ['src/' + r['source'] for r in spec['sources']] + [r['path'] for r in spec['extras']]
    out, queue = [], list(files)
    while queue:
        rel = queue.pop(0)
        if rel in out:
            continue
        p = fw / rel
        if not p.is_file():
            errors.append('built file %s does not exist' % rel)
            continue
        out.append(rel)
        if p.suffix == '.c':
            for inc in re.findall(r'^\s*#\s*include\s+"([^"]+\.c)"', p.read_text(errors='replace'), re.M):
                queue.append((p.parent / inc).resolve().relative_to(fw.resolve()).as_posix())
    return out, spec


def scope(fw, errors):
    built, spec = built_files(fw, errors)
    tests = sorted(p.relative_to(fw).as_posix() for p in (fw / 'tests').glob('*.c'))
    for rel in SRC_TESTS:
        if not (fw / rel).is_file():
            errors.append('test model %s does not exist' % rel)
        else:
            tests.append(rel)
    headers = sorted({p.relative_to(fw).as_posix() for d in ('src', 'include') for p in (fw / d).rglob('*.h')})
    if not (fw / 'ImageWireFormat.h').is_file():
        errors.append('ImageWireFormat.h does not exist')
    else:
        headers.append('ImageWireFormat.h')
    overlap = (set(built) & set(tests)) | (set(built) & set(headers)) | (set(tests) & set(headers))
    if overlap:
        errors.append('files in two scope classes: %s' % ', '.join(sorted(overlap)))
    return built, tests, headers, spec


def unreferenced(fw, built, headers, spec):
    link = (fw / 'link.ld').read_text()
    syms = re.findall(r'^\s*(\w+)\s*=\s*0x[0-9a-fA-F]+\s*;', link, re.M)
    texts = [(fw / rel).read_text(errors='replace') for rel in list(built) + list(headers)]
    targets = {e.get('target') for e in spec['edits'] if e.get('target')}
    out = []
    for s in dict.fromkeys(syms):
        w = re.compile(r'\b' + re.escape(s) + r'\b')
        if s not in targets and not any(w.search(x) for x in texts):
            out.append(s)
    return out, syms


# build.py and the host tests (tests/host_layout.py) pass -include src/firmware_profile.h, which includes
# stock_layout.h, so every scanned file sees the helpers of this header and of everything it includes.
FORCED_INCLUDE = 'src/firmware_profile.h'
INCLUDE_DIRS = ('src', 'src/app-runtime-v1/arm-include', 'include', '.')


def direct_headers(fw, rel, raw, headers):
    """In-scope headers that `rel` includes directly (quote or angle include, resolved like build.py's -I list)."""
    out = []
    for inc in re.findall(r'^\s*#\s*include\s*[<"]([^">]+\.h)[">]', raw, re.M):
        for base in [(fw / rel).parent] + [fw / d for d in INCLUDE_DIRS]:
            p = (base / inc)
            if p.is_file():
                r = p.resolve().relative_to(fw.resolve()).as_posix()
                if r in headers:
                    out.append(r)
                break
    return out


def included_headers(fw, rel, raws, headers):
    """Every in-scope header that `rel` sees: its includes followed transitively, plus the forced include and its
    includes."""
    seen, queue = [], [rel] + ([FORCED_INCLUDE] if FORCED_INCLUDE in raws else [])
    while queue:
        cur = queue.pop(0)
        if cur != rel:
            if cur in seen:
                continue
            seen.append(cur)
        queue += [h for h in direct_headers(fw, cur, raws[cur], headers) if h not in seen and h != rel]
    return seen


def window_drift(table, base, windows):
    """Errors when rebase_apply.leftovers() (the L8 scan) and this lint's abs windows disagree on either edge of a
    window: the first and last address inside it, and the addresses just outside it, that the table does not know."""
    col = rebase_apply.column(table, base)
    known = {int(r[col], 16) for r in table['linkld']} | {int(v[col], 16) for v in table['values']}
    known |= {int(e[col + 'Address'], 16) for e in table['edits']} | {int(table['moduleVA'][col], 16)}
    known |= {int(r[col], 16) for r in table['stockAbiRanges']}
    known |= {int(t, 16) for t in table.get('notStock', {})}
    out = []
    for lo, hi in windows:
        inside = [next(a for a in range(lo, hi) if a not in known), next(a for a in range(hi - 1, lo, -1)
                                                                         if a not in known)]
        for a, want in [(lo - 1, False), (hi, False)] + [(a, True) for a in inside]:
            if a in known or any(w[0] <= a < w[1] for w in windows if w != (lo, hi)):
                continue
            got = bool(rebase_apply.leftovers(table, base, {'probe': '%#x' % a}))
            if got != want:
                out.append('stock window %#x..%#x: rebase_apply.leftovers says %#x is %s a stock window, this lint '
                           'says %s' % (lo, hi, a, 'in' if got else 'not in', 'in' if want else 'not in'))
    return out


_SCAN_CACHE = {}  # scan_c results by file, text, helpers and windows (the self-test rescans unchanged files)


def check(fw, table):
    """Scan the tree at fw. Returns (errors, hits left after exemptions and deferrals, counts)."""
    fw = Path(fw)
    errors = []
    built, tests, headers, spec = scope(fw, errors)
    col = rebase_apply.column(table, spec['stockBase'])
    abs_ok = {int(v[col], 16) for v in table['values']}
    abs_key = tuple(sorted(abs_ok))
    top = rebase_apply.FLASH + max(b['stockAPBytes'] for b in table['bases'].values())
    windows = ((rebase_apply.FLASH, top), RAM_WINDOW, COPY_WINDOW)
    raws = {rel: (fw / rel).read_text(errors='replace') for rel in built + tests + headers if (fw / rel).is_file()}
    if FORCED_INCLUDE not in raws:
        errors.append('forced include %s does not exist' % FORCED_INCLUDE)
    errors += window_drift(table, spec['stockBase'], windows)
    header_helpers = {}
    for rel in headers:
        header_helpers[rel] = find_helpers(strip_parens(blank_c(raws[rel])))
    hits, stale = [], []
    for rel in built + tests + headers:
        raw = raws[rel]
        if rel.endswith('.S'):
            hits += scan_asm(rel, raw)
            continue
        hm = {}
        for h in included_headers(fw, rel, raws, headers):
            for k, v in header_helpers[h].items():
                hm.setdefault(k, set()).update(v)
        for k, v in find_helpers(strip_parens(blank_c(raw))).items():
            hm.setdefault(k, set()).update(v)
        key = (rel, raw, tuple(sorted((k, tuple(sorted(v))) for k, v in hm.items())), abs_key, windows,
               ADDR_REGION)
        if key not in _SCAN_CACHE:
            _SCAN_CACHE[key] = scan_c(rel, raw, hm, abs_ok, windows)
        h, t = _SCAN_CACHE[key]
        hits += h
        hits += scan_receivers(rel, raw, t, stale)
    for rel in (r[0] for r in RECEIVERS):
        if rel not in raws:
            stale.append('receiver row file %s is not in scope' % rel)
    errors += stale
    # Exemptions: whole files, then exact texts. Each must match at least one hit.
    left = []
    used = {}
    for h in hits:
        tag = next((e[0] for e in EXEMPT_FILES if e[1] == h.path), None)
        if tag is None:
            for e in EXEMPT_TEXTS:
                if e[1] == h.path and (h.rule, h.text) in [k[:2] for k in e[2]]:
                    tag = '%s %s %s' % (e[0], h.rule, h.text)
                    break
        if tag is None:
            left.append(h)
        else:
            used[tag] = used.get(tag, 0) + 1
    for tag, path, reason in EXEMPT_FILES:
        if path not in raws:
            errors.append('exemption %s: %s is not in scope (stale)' % (tag, path))
        elif not used.get(tag):
            errors.append('exemption %s: whole file %s has no hit (stale)' % (tag, path))
    for tag, path, keys, reason in EXEMPT_TEXTS:
        if path not in raws:
            errors.append('exemption %s: %s is not in scope (stale)' % (tag, path))
        for rule, text, count in keys:
            n = used.get('%s %s %s' % (tag, rule, text), 0)
            if not n:
                errors.append('exemption %s: %s %s %s matches nothing (stale)' % (tag, path, rule, text))
            elif n != count:
                errors.append('exemption %s: %s %s %s matches %d hits, pinned %d' % (tag, path, rule, text, n, count))
    # Guarded deferrals.
    hits, left = left, []
    deferred = {}
    for h in hits:
        d = next((x for x in DEFERRALS if h.path in x[1]), None)
        if d is None:
            left.append(h)
        else:
            deferred.setdefault(d[0], []).append(h)
    for tag, files, guard, reason in DEFERRALS:
        for f in files:
            if f not in raws:
                errors.append('deferral %s: %s is not in scope (stale)' % (tag, f))
        if not guarded(fw, guard):
            errors.append('deferral %s: %s no longer starts with the "not ported to 1.0.6.11 yet" guard, so its %d '
                          'hits are refused' % (tag, guard, len(deferred.get(tag, []))))
            left += deferred.get(tag, [])
            continue
        if not deferred.get(tag):
            errors.append('deferral %s: %s has no hit (stale)' % (tag, ', '.join(files)))
        for f, pins in files.items():
            got = counter((h.rule, h.text) for h in deferred.get(tag, []) if h.path == f)
            want = {(r, t): n for r, t, n in pins}
            for k in sorted(set(got) | set(want)):
                if got.get(k, 0) != want.get(k, 0):
                    errors.append('deferral %s: %s has %d hits of %s %s, pinned %d' % (tag, f, got.get(k, 0), k[0],
                                                                                      k[1], want.get(k, 0)))
    # Unreferenced link.ld symbols.
    unref, syms = unreferenced(fw, built, headers, spec)
    for s in unref:
        if s not in UNREFERENCED:
            errors.append('link.ld symbol %s is referenced by no built file, header or edit target (new '
                          'unreferenced symbol)' % s)
    for s in UNREFERENCED:
        if s not in syms:
            errors.append('pinned unreferenced symbol %s is no longer in link.ld' % s)
        elif s not in unref:
            errors.append('pinned unreferenced symbol %s is now referenced; update the pinned list' % s)
    counts = dict(built=len(built), tests=len(tests), headers=len(headers),
                  exemptions=len(EXEMPT_FILES) + len(EXEMPT_TEXTS), receivers=len(RECEIVERS),
                  deferrals=len(DEFERRALS), unreferenced=len(unref))
    return errors, left, counts


def report(errors, left):
    for e in errors:
        print('LAYOUT_ERROR: ' + e)
    for h in left:
        print('LAYOUT_ERROR: %s (unnamed stock offset or queue id)' % h)


def main_check(fw, table):
    errors, left, c = check(fw, table)
    if errors or left:
        report(errors, left)
        print('LAYOUT_FAIL: %d errors, %d refused positions' % (len(errors), len(left)))
        return 1
    print('LAYOUT_OK: %d files (%d built, %d test models, %d headers), no unnamed stock offset or queue id; '
          '%d exemptions, %d receiver row and %d guarded deferrals in use; %d unreferenced link.ld symbols pinned'
          % (c['built'] + c['tests'] + c['headers'], c['built'], c['tests'], c['headers'], c['exemptions'],
             c['receivers'], c['deferrals'], c['unreferenced']))
    return 0


# ---------------------------------------------------------------------------------------------------------- self-test

COPIED = ('src', 'tests', 'include', 'trampolines.S', 'link.ld', 'build-inputs.json', 'ImageWireFormat.h')


class Copy:
    def __init__(self, fw, root):
        self.fw = Path(root) / 'firmware'
        self.fw.mkdir(parents=True)
        for part in COPIED:
            src = Path(fw) / part
            if src.is_dir():
                shutil.copytree(src, self.fw / part, ignore=shutil.ignore_patterns('__pycache__'))
            else:
                shutil.copy2(src, self.fw / part)
        self.saved = {}

    def read(self, rel):
        return (self.fw / rel).read_text()

    def write(self, rel, text):
        if rel not in self.saved:
            self.saved[rel] = self.read(rel)
        (self.fw / rel).write_text(text)

    def restore(self):
        for rel, text in self.saved.items():
            (self.fw / rel).write_text(text)
        self.saved = {}


def fail(msg):
    print('LAYOUT_SELF_TEST_FAIL: ' + msg)
    raise SystemExit(1)


def into_function(c, rel, name, stmt, param_type=None):
    """Insert `stmt` right after the opening brace of function `name` (or of the first function with a
    `param_type` parameter) in the copy's `rel`."""
    raw = c.read(rel)
    t = blank_c(raw)
    for fname, params, start, body_open, body_close in functions(t):
        if (name and fname == name) or (param_type and re.search(param_type, params)):
            c.write(rel, raw[:body_open + 1] + stmt + raw[body_open + 1:])
            return
    fail('%s: no function to plant into (%s)' % (rel, name or param_type))


def counter(items):
    out = {}
    for k in items:
        out[k] = out.get(k, 0) + 1
    return out


def self_test(fw, table):
    fw = Path(fw)
    spec = json.loads((fw / 'build-inputs.json').read_text())
    col = rebase_apply.column(table, spec['stockBase'])
    values = {int(v[col], 16) for v in table['values']}
    # A RAM-window address that no table value uses, and a table value that render_idle.c uses.
    stray = next(a for a in range(RAM_WINDOW[0] + 0x10, RAM_WINDOW[1], 4) if a not in values)
    idle = 'src/image-upload-test/render_idle.c'
    owned = [v for v in table['values'] if idle in v['sites'] and v['kind'] == 'ram']
    if len(owned) != 1:
        fail('expected one RAM value row with a site in %s, found %d' % (idle, len(owned)))
    owned = owned[0][col]
    with tempfile.TemporaryDirectory(prefix='check_layout_') as root:
        c = Copy(fw, root)
        base_errors, base_left, _ = check(c.fw, table)
        base = counter(h.key() for h in base_left)
        planted = [
            ('cast', 'src/app-runtime-v1/app_service.c', '(uint8_t *)t+8',
             lambda: c.write('src/app-runtime-v1/app_service.c', c.read('src/app-runtime-v1/app_service.c') +
                             '\nstatic void *tio_plant_cast(void *t){return (uint8_t *)t+8;}\n')),
            ('helper', 'src/music-runtime-v1/menu10.c', 'ptr(app,0xc+4*i)',
             lambda: c.write('src/music-runtime-v1/menu10.c', c.read('src/music-runtime-v1/menu10.c') +
                             '\nstatic void *tio_plant_helper(void *app,unsigned i){return ptr(app,0xc+4*i);}\n')),
            ('wordcast', 'tests/native_ui_test.c', '(uint32_t *)(app+0x98)',
             lambda: c.write('tests/native_ui_test.c', c.read('tests/native_ui_test.c') +
                             '\nstatic uint32_t *tio_plant_wordcast(uint8_t *app){return (uint32_t *)(app+0x98);}\n')),
            ('index', 'src/music-runtime-v1/menu10.c', '((uint32_t *)app)[3]',
             lambda: c.write('src/music-runtime-v1/menu10.c', c.read('src/music-runtime-v1/menu10.c') +
                             '\nstatic uint32_t tio_plant_index(void *app){return ((uint32_t *)app)[3];}\n')),
            ('abs', 'src/music-runtime-v1/menu10.c', '(uintptr_t)%#x' % stray,
             lambda: c.write('src/music-runtime-v1/menu10.c', c.read('src/music-runtime-v1/menu10.c') +
                             '\nstatic void *tio_plant_abs(void){return *(void **)(uintptr_t)%#x;}\n' % stray)),
            ('addr', idle, 'display+0x2a0',
             lambda: into_function(c, idle, 'tio_render_graph_idle', 'uint32_t layer=0;read(display+0x2a0,&layer);')),
            ('addr', idle, '%s+0x124' % owned,
             lambda: into_function(c, idle, 'tio_render_graph_idle', 'read(%s+0x124,0);' % owned)),
            ('addr', idle, 'ram(unit,32)',
             lambda: into_function(c, idle, 'tio_render_graph_idle', 'if(!ram(unit,32))return false;')),
            ('asm', 'trampolines.S', 'ldr r2,[r1,#4]',
             lambda: c.write('trampolines.S', c.read('trampolines.S') + '\n ldr r2,[r1,#4]\n')),
            ('asm', 'trampolines.S', 'ldr r2,[r1]',
             lambda: c.write('trampolines.S', c.read('trampolines.S') + '\n ldr r2,[r1]\n')),
            ('queue', 'src/display-runtime-v1/native_display_file.c', 'enqueue(1,&m)',
             lambda: into_function(c, 'src/display-runtime-v1/native_display_file.c', None,
                                   'TIONativeMessage m={0};enqueue(1,&m);', r'\bTIOCopyEnqueue\s+enqueue\b')),
            ('queue', 'src/focus-v1/focus_service.c', 'q(1,&m)',
             lambda: into_function(c, 'src/focus-v1/focus_service.c', None,
                                   'TIONativeMessage m={0};q(1,&m);', r'\bTIOCopyEnqueue\s+q\b')),
        ]
        caught = set()
        for rule, rel, text, plant in planted:
            plant()
            errors, left, _ = check(c.fw, table)
            c.restore()
            new = counter(h.key() for h in left)
            extra = {k: n - base.get(k, 0) for k, n in new.items() if n > base.get(k, 0)}
            if extra != {(rel, rule, text): 1}:
                fail('planted %s %s in %s: expected exactly that one new hit, got %s' % (rule, text, rel, extra))
            caught.add(rule)
        if caught != set(RULES):
            fail('rules not caught: %s' % ', '.join(sorted(set(RULES) - caught)))
        # Other spellings of the same positions: line breaks, cast chains, binary and decimal literals, redundant
        # parentheses, helpers written with +(off), a byte-view local or a macro, a helper reached only through the
        # forced include, a reversed index and a macro argument as an asm base register.
        app = 'src/app-runtime-v1/app_service.c'

        def append(rel, text):
            return lambda: c.write(rel, c.read(rel) + '\n' + text + '\n')
        variants = [
            ('cast', app, '(uint8_t *)\n    t+8', append(app, 'static void *tio_v1(void *t){return (uint8_t *)\n    t+8;}')),
            ('cast', app, '(uint8_t *)(uintptr_t)t+8',
             append(app, 'static void *tio_v2(void *t){return (uint8_t *)(uintptr_t)t+8;}')),
            ('cast', app, '(uint8_t *)t+0b10011000',
             append(app, 'static void *tio_v3(void *t){return (uint8_t *)t+0b10011000;}')),
            ('cast', app, '(0x98)+(uint8_t *)t', append(app, 'static void *tio_v4(void *t){return (0x98)+(uint8_t *)t;}')),
            ('wordcast', app, '(uint32_t *)(\n    app+0x98)',
             append(app, 'static uint32_t *tio_v5(uint8_t *app){return (uint32_t *)(\n    app+0x98);}')),
            ('wordcast', app, '(uint32_t *)(uintptr_t)(app+0x98)',
             append(app, 'static uint32_t *tio_v6(uint8_t *app){return (uint32_t *)(uintptr_t)(app+0x98);}')),
            ('wordcast', app, '(uint32_t *)((uintptr_t)app+0x98)',
             append(app, 'static uint32_t *tio_v7(uint8_t *app){return (uint32_t *)((uintptr_t)app+0x98);}')),
            ('helper', app, 'tio_v8_get(app,0x98)',
             append(app, 'static uint32_t tio_v8_get(const void *base,unsigned off){return *(const uint32_t *)'
                         '((const uint8_t *)base+(off));}\nstatic uint32_t tio_v8(void *app){return tio_v8_get(app,0x98);}')),
            ('helper', app, 'tio_v9_get(app,0x98)',
             append(app, 'static uint32_t tio_v9_get(const void *base,unsigned off){const uint8_t *b=base;return '
                         '*(const uint32_t *)(b+off);}\nstatic uint32_t tio_v9(void *app){return tio_v9_get(app,0x98);}')),
            ('helper', app, 'TIO_V10_AT(t,0x98)',
             append(app, '#define TIO_V10_AT(p,n) ((uint8_t *)(p)+(n))\nstatic void *tio_v10(void *t){return '
                         'TIO_V10_AT(t,0x98);}')),
            ('helper', app, 'tio_v11_word(app,0x98)',
             lambda: (c.write('src/stock_layout.h', c.read('src/stock_layout.h') +
                              '\nstatic inline uint32_t tio_v11_word(const void *a,unsigned o){return '
                              '*(const uint32_t *)((const uint8_t *)a+o);}\n'),
                      c.write(app, c.read(app) + '\nstatic uint32_t tio_v11(void *app){return tio_v11_word(app,0x98);}\n'))),
            ('index', app, '38[(uint32_t *)app]', append(app, 'static uint32_t tio_v12(void *app){return 38[(uint32_t *)app];}')),
            ('abs', app, '(uintptr_t)%du' % stray,
             append(app, 'static void *tio_v13(void){return *(void **)(uintptr_t)%du;}' % stray)),
            ('abs', app, '(uintptr_t)(%#x)' % stray,
             append(app, 'static void *tio_v14(void){return *(void **)(uintptr_t)(%#x);}' % stray)),
            ('addr', idle, '(display)+0x2a0',
             lambda: into_function(c, idle, 'tio_render_graph_idle', 'uint32_t layer=0;read((display)+0x2a0,&layer);')),
            ('addr', idle, '%s+(0x124)' % owned,
             lambda: into_function(c, idle, 'tio_render_graph_idle', 'read(%s+(0x124),0);' % owned)),
            ('asm', 'trampolines.S', 'ldr r2,[\\b,#4]',
             append('trampolines.S', ' .macro TIO_V17 b\n ldr r2,[\\b,#4]\n .endm')),
        ]
        for rule, rel, text, plant in variants:
            plant()
            errors, left, _ = check(c.fw, table)
            c.restore()
            new = counter(h.key() for h in left)
            extra = {k: n - base.get(k, 0) for k, n in new.items() if n > base.get(k, 0)}
            if extra != {(rel, rule, text): 1} or errors != base_errors:
                fail('planted %s %r in %s: expected exactly that one new hit, got %s %s' % (rule, text, rel, extra,
                                                                                          errors))
        # The sizeof stride form and a table-value cast pass.
        for rel, text in (('src/music-runtime-v1/menu10.c',
                           '\nstatic void *tio_plant_ok(void *app,unsigned i){return '
                           'ptr(app,TIO_STOCK_MENU_ROWS+sizeof(uint32_t)*i);}\n'),
                          ('src/music-runtime-v1/menu10.c',
                           '\nstatic void *tio_plant_ok2(void){return *(void **)(uintptr_t)%s;}\n' % owned)):
            c.write(rel, c.read(rel) + text)
            errors, left, _ = check(c.fw, table)
            c.restore()
            new = counter(h.key() for h in left)
            extra = {k: n - base.get(k, 0) for k, n in new.items() if n > base.get(k, 0)}
            if extra or errors != base_errors:
                fail('accepted form %r was reported: %s %s' % (text.strip(), extra, errors))

        def refused(label, change, needle):
            if any(needle in e for e in base_errors):
                fail('%s: the unchanged copy already reports %r' % (label, needle))
            change()
            errors, left, _ = check(c.fw, table)
            c.restore()
            if not any(needle in e for e in errors):
                fail('%s was not refused (wanted an error containing %r; got %s)' % (label, needle, errors))

        store = 'src/app-runtime-v1/app_store.c'
        refused('stale exemption', lambda: c.write(store, c.read(store).replace('(char *)p+20', '(char *)p+TAP_ID')),
                'exemption E4: %s cast (char *)p+20 matches nothing (stale)' % store)
        refused('second copy of an exempt text',
                append(store, 'static char *tio_dup(void *p){return (char *)p+20;}'),
                'exemption E4: %s cast (char *)p+20 matches 2 hits, pinned 1' % store)
        refused('new raw offset in a deferred file',
                append('src/menu-grid-v2/menu_config.c', 'static void *tio_g(void *t){return (uint8_t *)t+0x98;}'),
                'deferral G1: src/menu-grid-v2/menu_config.c has 1 hits of cast (uint8_t *)t+0x98, pinned 0')
        rtest = 'tests/native_remote_test.c'
        refused('one deferred hit named',
                lambda: c.write(rtest, c.read(rtest).replace('(uint32_t *)(app+0xa0)', '(uint32_t *)(app+TIO_A)', 1)),
                'deferral G2: %s has 2 hits of wordcast (uint32_t *)(app+0xa0), pinned 3' % rtest)

        def drift():
            global RAM_WINDOW
            saved, RAM_WINDOW = RAM_WINDOW, (RAM_WINDOW[0], RAM_WINDOW[1] + 0x10000)
            try:
                return check(c.fw, table)[0]
            finally:
                RAM_WINDOW = saved
        if not any('rebase_apply.leftovers says' in e for e in drift()):
            fail('a RAM window that differs from rebase_apply.leftovers was not refused')

        def rename_unit():
            raw = c.read(idle)
            t = blank_c(raw)
            fn = next(f for f in functions(t) if f[0] == 'tio_render_graph_idle')
            body = re.sub(r'\bunit\b', 'unit_renamed', raw[fn[3]:fn[4] + 1])
            c.write(idle, raw[:fn[3]] + body + raw[fn[4] + 1:])
        refused('stale receiver row', rename_unit,
                'receiver row %s tio_render_graph_idle unit: identifier not declared' % idle)
        remote = 'src/global-remote-v1/remote_native.c'
        refused('unguarded deferral',
                lambda: c.write(remote, '\n'.join(c.read(remote).split('\n')[3:])),
                'deferral G1: %s no longer starts with' % remote)
        refused('new unreferenced symbol',
                lambda: c.write('link.ld', c.read('link.ld') +
                                '\ntio_plant_unreferenced = 0x%x;\n' % rebase_apply.FLASH),
                'link.ld symbol tio_plant_unreferenced is referenced by no built file')
    print('LAYOUT_SELF_TEST_OK: %d rules each caught in a planted copy, the sizeof stride form accepted; stale '
          'exemption, stale receiver row, unguarded deferral and new unreferenced symbol refused' % len(caught))
    return 0


def main(argv):
    args = argv[1:]
    st = '--self-test' in args
    args = [a for a in args if a != '--self-test']
    if len(args) != 1:
        raise SystemExit('usage: check_layout.py [--self-test] <firmware dir>')
    fw = Path(args[0])
    table = rebase_apply.load_table(fw=fw.resolve())
    return self_test(fw, table) if st else main_check(fw, table)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
