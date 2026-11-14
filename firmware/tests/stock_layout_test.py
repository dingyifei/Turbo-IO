"""Proves every value in src/stock_layout.h from the stock 1.0.6.11 AP image.

  python3 -I firmware/tests/stock_layout_test.py --stock <stock ZIP> [--llvm-bin DIR]

Each header value has two witnesses in tests/stock_layout_witnesses.json (a derived value has one, plus the two of
each of its parts). A witness names one instruction in the AP image through a locator (never a raw address), the
encoding it must have, its registers, and a transform from the instruction's immediate field to the header value.
The test resolves each locator from link.ld, the build-inputs.json edits and the active rebase table, decodes the
instruction with its own small Thumb-2 decoder, and compares. It also checks that the two witnesses of a value sit
in two different stock functions (one named exception), the pinned literal-load totals, the table addresses of the
LVGL memory counters, the header's refusal of every other stock base, the edits that the header's values must agree
with, and the module message ids. A +1 witness must be followed by bls or bhi, so the bound is shown to be inclusive.
The header may define no macro that escapes the witness rule, the one derived constant is named, and no free text in
the JSON or the header may hold a vendor string. Finally it mutates the header values and the image bytes (every
bit of the first use of each encoding included) and requires every mutation to be refused. Nothing here writes a
file or touches a device.

Locator forms (offsets are signed and counted from the located address):
  link:SYM       the link.ld address of SYM, Thumb bit cleared
  edit:TARGET    the address of the one build-inputs.json edit whose target is exactly TARGET
  value:ROW      the active table's value row ROW, column new, Thumb bit cleared
  lit:ROW#K      the K-th literal load (scan below) whose literal word equals the table row ROW's new value
  str:ID#K       the K-th literal load of the runtime address of one NUL-terminated string; ID is "text" for the
                 three LVGL names only, and sha256=<hex>,len=<n> for every other string
  call:LOC@OFF   the target of the BL at LOC+OFF

The literal-load scan looks at every halfword of the image (no instruction-boundary check): a 16-bit ldr rt,[pc,#n]
or a 32-bit ldr.w rt,[pc,#+-n] counts when its literal word is 4-byte aligned and equals the value.
"""
from fractions import Fraction
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import struct
import subprocess
import sys
import tempfile
import zipfile

FW = Path(__file__).resolve().parents[1]
HEADER = FW/'src'/'stock_layout.h'
WITNESSES = FW/'tests'/'stock_layout_witnesses.json'
TREE_BASE = '1.0.6.11'
FLASH = 0x10190000          # where the AP image is mapped
PREFIX = 'stock_layout: '
LVGL_NAMES = ('lv_timer_handler', 'lv_timer_set_user_data', 'lv_draw_layer_create')
LEGACY_NAMES = ('TIO_MENU_SCROLL_POSITION_OFFSET', 'TIO_MENU_EXTERNAL_ACTION_OFFSET')
GUARD_MACRO = 'TIO_STOCK_LAYOUT_H'
SAME_FUNCTION_EXCEPTION = ('TIO_STOCK_MESSAGE_ID_MAX', 'same-function: bound and tbb table length')
# Decision R3: the one derived constant, with its parts. Any other derived header macro is refused.
DERIVED_CONSTANT = ('TIO_MENU_SCROLL_POSITION_OFFSET', ('TIO_STOCK_MENU_MOTION', 'TIO_STOCK_MOTION_POSITION'))
# The number of context entries over all records, so that a dropped context is noticed.
CONTEXT_ENTRIES = 51
# A +1 witness is an unsigned compare whose bound is inclusive: the next flag reader is bls (in range) or bhi (out
# of range), with only flag-preserving register moves between. bcc/bcs would make the bound exclusive.
PLUS_ONE_SHAPES = ('cmp-imm8', 'cmp.w-imm')
PLUS_ONE_CONDS = {8: 'hi', 9: 'ls'}
# Vendor text (decision R4): no free text in the JSON (`why`, `note`) and no line of stock_layout.h may contain a
# whole NUL-delimited AP image string of VENDOR_MIN bytes or more, except the three LVGL names and a plain word
# (letters only) shorter than PLAIN_WORD_MAX, which is ordinary English that the image also happens to hold (on
# 1.0.6.11 the longest such word in the current texts has 10 letters). Every other JSON string has a fixed grammar
# (locators, header names, shape and key names) that check_json and the locators enforce.
VENDOR_MIN = 8
PLAIN_WORD_MAX = 12
TOP_KEYS = {'format', 'stockBase', 'note', 'loads', 'moduleMessageIds', 'witnesses'}
TRANSFORMS = ('id', '+1', '+8', 'vfp', 'tbb')
RECORD_KEYS = {'constant', 'n', 'where', 'at', 'function', 'shape', 'regs', 'transform', 'context', 'checks', 'why',
               'exception'}
CONTEXT_KEYS = {'where', 'at', 'shape', 'regs', 'field', 'target'}
WALK_WINDOW = 0x2000


class Fail(Exception):
    """One failure line (without the prefix)."""


def hexs(v):
    if isinstance(v, Fraction):
        return str(v.numerator) if v.denominator == 1 else str(v)
    return '-0x%x' % -v if v < 0 else '0x%x' % v


def signed(v):
    return ('-0x%x' if v < 0 else '+0x%x') % abs(v)


# ---------------------------------------------------------------------------------------------------------------
# Decoder. Each encoding: size, fixed bits per halfword (mask, value), optional excluded bit patterns, the register
# fields, the immediate field, and where the lowest bit of the immediate sits (halfword index, bit) for mutation.
# ---------------------------------------------------------------------------------------------------------------

def expand_imm(i12):
    """ThumbExpandImm of the 12-bit i:imm3:imm8 field."""
    if i12 >> 10 == 0:
        x = i12 & 0xff
        return (x, x | x << 16, x << 8 | x << 24, x * 0x01010101)[(i12 >> 8) & 3]
    u, r = 0x80 | (i12 & 0x7f), i12 >> 7
    return ((u >> r) | (u << (32 - r))) & 0xffffffff


def vfp_imm(imm8):
    """VFPExpandImm for a single-precision vmov immediate, as an exact fraction."""
    a, b, cd, frac = imm8 >> 7, (imm8 >> 6) & 1, (imm8 >> 4) & 3, imm8 & 0xf
    exp = (cd - 3) if b else (cd + 1)
    value = Fraction(16 + frac, 16) * (Fraction(2) ** exp)
    return -value if a else value


def bl_target(a, h1, h2):
    s = (h1 >> 10) & 1
    i1, i2 = 1 - (((h2 >> 13) & 1) ^ s), 1 - (((h2 >> 11) & 1) ^ s)
    off = s << 24 | i1 << 23 | i2 << 22 | (h1 & 0x3ff) << 12 | (h2 & 0x7ff) << 1
    return a + 4 + (off - (1 << 25) if s else off)


def _i12(h1, h2):
    return (h1 >> 10 & 1) << 11 | (h2 >> 12 & 7) << 8 | (h2 & 0xff)


def _lo3(h, shift):
    return (h >> shift) & 7


def _modimm_ok(h1, h2):
    """False for the UNPREDICTABLE modified-immediate forms: a replicated pattern (i:imm3 = 0001..0011) of a zero
    byte."""
    i12 = _i12(h1, h2)
    return not (i12 >> 10 == 0 and (i12 >> 8) & 3 and i12 & 0xff == 0)


# A field-less bit that no record compares must be named in `dontcare` (one mask per halfword); the opcode self-check
# requires every other bit of an encoding to be fixed or to change the decoded registers or field.
ENC = {
    # 16-bit data processing
    'movs-imm8': dict(n=2, fixed=[(0xf800, 0x2000)], regs=lambda h, g: {'rd': _lo3(h, 8)}, field=lambda h, g, a: h & 0xff, low=(0, 0)),
    'cmp-imm8': dict(n=2, fixed=[(0xf800, 0x2800)], regs=lambda h, g: {'rn': _lo3(h, 8)}, field=lambda h, g, a: h & 0xff, low=(0, 0)),
    'adds-imm8': dict(n=2, fixed=[(0xf800, 0x3000)], regs=lambda h, g: {'rdn': _lo3(h, 8)}, field=lambda h, g, a: h & 0xff, low=(0, 0)),
    'subs-imm8': dict(n=2, fixed=[(0xf800, 0x3800)], regs=lambda h, g: {'rdn': _lo3(h, 8)}, field=lambda h, g, a: h & 0xff, low=(0, 0)),
    'adds-imm3': dict(n=2, fixed=[(0xfe00, 0x1c00)], regs=lambda h, g: {'rd': h & 7, 'rn': _lo3(h, 3)}, field=lambda h, g, a: _lo3(h, 6), low=(0, 6)),
    'subs-imm3': dict(n=2, fixed=[(0xfe00, 0x1e00)], regs=lambda h, g: {'rd': h & 7, 'rn': _lo3(h, 3)}, field=lambda h, g, a: _lo3(h, 6), low=(0, 6)),
    'mov-reg': dict(n=2, fixed=[(0xff00, 0x4600)], regs=lambda h, g: {'rd': (h >> 7 & 1) << 3 | (h & 7), 'rm': (h >> 3) & 0xf}, field=None, low=None),
    # 32-bit data processing (modified immediate, S = 0 for mov.w and add.w)
    'mov.w-imm': dict(n=4, fixed=[(0xfbff, 0xf04f), (0x8000, 0x0000)], valid=_modimm_ok, regs=lambda h, g: {'rd': (g >> 8) & 0xf}, field=lambda h, g, a: expand_imm(_i12(h, g)), low=(1, 0)),
    'add.w-imm': dict(n=4, fixed=[(0xfbf0, 0xf100), (0x8000, 0x0000)], valid=_modimm_ok, regs=lambda h, g: {'rd': (g >> 8) & 0xf, 'rn': h & 0xf}, field=lambda h, g, a: expand_imm(_i12(h, g)), low=(1, 0)),
    'cmp.w-imm': dict(n=4, fixed=[(0xfbf0, 0xf1b0), (0x8f00, 0x0f00)], valid=_modimm_ok, regs=lambda h, g: {'rn': h & 0xf}, field=lambda h, g, a: expand_imm(_i12(h, g)), low=(1, 0)),
    # 16-bit loads and stores, immediate offset
    'ldr-imm5': dict(n=2, fixed=[(0xf800, 0x6800)], regs=lambda h, g: {'rt': h & 7, 'rn': _lo3(h, 3)}, field=lambda h, g, a: ((h >> 6) & 31) * 4, low=(0, 6)),
    'str-imm5': dict(n=2, fixed=[(0xf800, 0x6000)], regs=lambda h, g: {'rt': h & 7, 'rn': _lo3(h, 3)}, field=lambda h, g, a: ((h >> 6) & 31) * 4, low=(0, 6)),
    'ldrb-imm5': dict(n=2, fixed=[(0xf800, 0x7800)], regs=lambda h, g: {'rt': h & 7, 'rn': _lo3(h, 3)}, field=lambda h, g, a: (h >> 6) & 31, low=(0, 6)),
    'ldrh-imm5': dict(n=2, fixed=[(0xf800, 0x8800)], regs=lambda h, g: {'rt': h & 7, 'rn': _lo3(h, 3)}, field=lambda h, g, a: ((h >> 6) & 31) * 2, low=(0, 6)),
    'strh-imm5': dict(n=2, fixed=[(0xf800, 0x8000)], regs=lambda h, g: {'rt': h & 7, 'rn': _lo3(h, 3)}, field=lambda h, g, a: ((h >> 6) & 31) * 2, low=(0, 6)),
    # 32-bit loads and stores, positive 12-bit immediate (Rn = pc is the literal form, excluded)
    'ldr.w-imm12': dict(n=4, fixed=[(0xfff0, 0xf8d0), (0, 0)], exclude=(0x000f, 0x000f), regs=lambda h, g: {'rt': g >> 12, 'rn': h & 0xf}, field=lambda h, g, a: g & 0xfff, low=(1, 0)),
    'str.w-imm12': dict(n=4, fixed=[(0xfff0, 0xf8c0), (0, 0)], exclude=(0x000f, 0x000f), regs=lambda h, g: {'rt': g >> 12, 'rn': h & 0xf}, field=lambda h, g, a: g & 0xfff, low=(1, 0)),
    'ldrb.w-imm12': dict(n=4, fixed=[(0xfff0, 0xf890), (0, 0)], exclude=(0x000f, 0x000f), regs=lambda h, g: {'rt': g >> 12, 'rn': h & 0xf}, field=lambda h, g, a: g & 0xfff, low=(1, 0)),
    'strb.w-imm12': dict(n=4, fixed=[(0xfff0, 0xf880), (0, 0)], exclude=(0x000f, 0x000f), regs=lambda h, g: {'rt': g >> 12, 'rn': h & 0xf}, field=lambda h, g, a: g & 0xfff, low=(1, 0)),
    'ldrsh.w-imm12': dict(n=4, fixed=[(0xfff0, 0xf9b0), (0, 0)], exclude=(0x000f, 0x000f), regs=lambda h, g: {'rt': g >> 12, 'rn': h & 0xf}, field=lambda h, g, a: g & 0xfff, low=(1, 0)),
    # strd with P=1 U=1 W=0
    'strd-imm8': dict(n=4, fixed=[(0xfff0, 0xe9c0), (0, 0)], regs=lambda h, g: {'rt': g >> 12, 'rt2': (g >> 8) & 0xf, 'rn': h & 0xf}, field=lambda h, g, a: (g & 0xff) * 4, low=(1, 0)),
    # VFP single-precision load, store (U = 1) and immediate move
    'vldr-s': dict(n=4, fixed=[(0xffb0, 0xed90), (0x0f00, 0x0a00)], regs=lambda h, g: {'sd': (g >> 12) << 1 | (h >> 6) & 1, 'rn': h & 0xf}, field=lambda h, g, a: (g & 0xff) * 4, low=(1, 0)),
    'vstr-s': dict(n=4, fixed=[(0xffb0, 0xed80), (0x0f00, 0x0a00)], regs=lambda h, g: {'sd': (g >> 12) << 1 | (h >> 6) & 1, 'rn': h & 0xf}, field=lambda h, g, a: (g & 0xff) * 4, low=(1, 0)),
    'vmov.f32-imm': dict(n=4, fixed=[(0xffb0, 0xeeb0), (0x0ff0, 0x0a00)], regs=lambda h, g: {'sd': (g >> 12) << 1 | (h >> 6) & 1}, field=lambda h, g, a: vfp_imm((h & 0xf) << 4 | (g & 0xf)), low=(1, 0)),
    # branches, prologues and literal loads
    'bl': dict(n=4, fixed=[(0xf800, 0xf000), (0xd000, 0xd000)], regs=lambda h, g: {}, field=lambda h, g, a: bl_target(a, h, g), low=None),
    'tbb': dict(n=4, fixed=[(0xffff, 0xe8df), (0xfff0, 0xf000)], regs=lambda h, g: {'rm': g & 0xf}, field=None, low=None),
    # The 16-bit conditional branch after a +1 compare: its field is the condition (8 hi, 9 ls). The branch offset
    # is not compared (where the out-of-range path goes does not change the bound). Conditions 14 and 15 are udf/svc.
    'bcc': dict(n=2, fixed=[(0xf000, 0xd000)], exclude=(0x0e00, 0x0e00), dontcare=(0x00ff,), regs=lambda h, g: {}, field=lambda h, g, a: (h >> 8) & 0xf, low=None),
    'blx-reg': dict(n=2, fixed=[(0xff87, 0x4780)], regs=lambda h, g: {'rm': (h >> 3) & 0xf}, field=None, low=None),
    # A prologue push is recognised by its lr bit; the other registers in its list do not matter.
    'push': dict(n=2, fixed=[(0xff00, 0xb500)], dontcare=(0x00ff,), regs=lambda h, g: {}, field=None, low=None),
    'push.w': dict(n=4, fixed=[(0xffff, 0xe92d), (0xe000, 0x4000)], dontcare=(0, 0x1fff), regs=lambda h, g: {}, field=None, low=None),
    # Only the 16-bit literal load: no witness locator lands on a 32-bit ldr.w literal load, so that decoder entry is
    # left out (an entry no witness uses is deleted). The load scan still counts both forms, by its own definition.
    'ldr-lit': dict(n=2, fixed=[(0xf800, 0x4800)], regs=lambda h, g: {'rt': _lo3(h, 8)}, field=lambda h, g, a: ((a + 4) & ~3) + (h & 0xff) * 4, low=(0, 0)),
}
PUSH_SHAPES = ('push', 'push.w')
LOAD_SHAPES = ('ldr-lit',)


def size_of(h1):
    return 4 if (h1 >> 11) in (0x1d, 0x1e, 0x1f) else 2


def shape_matches(shape, h1, h2):
    e = ENC[shape]
    if e['n'] == 4 and h2 is None:
        return False
    if size_of(h1) != e['n']:
        return False
    words = (h1, h2)
    for k, (m, v) in enumerate(e['fixed']):
        if words[k] & m != v:
            return False
    ex = e.get('exclude')
    if ex and h1 & ex[0] == ex[1]:
        return False
    if 'valid' in e and not e['valid'](h1, h2):
        return False
    return True


class Image:
    def __init__(self, raw):
        self.b = raw if isinstance(raw, bytearray) else bytearray(raw)
        self.end = FLASH + len(self.b)

    def inside(self, a, n=2):
        return FLASH <= a and a + n <= self.end

    def hw(self, a):
        if not self.inside(a):
            raise Fail('address outside the AP image')
        o = a - FLASH
        return self.b[o] | self.b[o + 1] << 8

    def word(self, a):
        o = a - FLASH
        return struct.unpack_from('<I', self.b, o)[0]

    def raw(self, a, n):
        o = a - FLASH
        return bytes(self.b[o:o + n])

    def halves(self, a):
        h1 = self.hw(a)
        return h1, (self.hw(a + 2) if size_of(h1) == 4 and self.inside(a + 2) else None)


class Decoded:
    def __init__(self, shape, a, h1, h2):
        e = ENC[shape]
        self.shape, self.a, self.n = shape, a, e['n']
        self.regs = e['regs'](h1, h2)
        self.field = e['field'](h1, h2, a) if e['field'] else None


def decode(img, a, shape, used=None):
    """Decode the instruction at a as `shape`; None when its fixed bits do not match. Records the match in `used`."""
    h1, h2 = img.halves(a)
    if not shape_matches(shape, h1, h2):
        return None
    if used is not None:
        used.add(shape)
    return Decoded(shape, a, h1, h2)


def insn_bytes(img, a):
    h1 = img.hw(a)
    return img.raw(a, size_of(h1)).hex()


# Fixed-bit recognisers used only by the function walker; their fields are never compared with header values.

def classify(h1, h2, a):
    """('call'|'branch'|'cbranch'|'return'|'it'|'tbb'|'bad'|'other', target or IT count)."""
    if h2 is not None and size_of(h1) == 4:
        if h1 & 0xf800 == 0xf000 and h2 & 0xd000 == 0xd000:
            return 'call', bl_target(a, h1, h2)
        if h1 & 0xf800 == 0xf000 and h2 & 0xd001 == 0xc000:
            return 'call', None                                   # blx immediate
        if h1 & 0xf800 == 0xf000 and h2 & 0xd000 == 0x9000:
            return 'branch', bl_target(a, h1, h2)                 # b.w (same offset layout as bl)
        if h1 & 0xf800 == 0xf000 and h2 & 0xd000 == 0x8000 and (h1 >> 6) & 0xe != 0xe:
            s = (h1 >> 10) & 1
            off = s << 20 | ((h2 >> 11) & 1) << 19 | ((h2 >> 13) & 1) << 18 | (h1 & 0x3f) << 12 | (h2 & 0x7ff) << 1
            return 'cbranch', a + 4 + (off - (1 << 21) if s else off)
        if h1 == 0xe8df and h2 & 0xfff0 == 0xf000:
            return 'tbb', None
        if h1 & 0xfff0 == 0xe8d0 and h2 & 0xffe0 == 0xf000:
            return 'bad', 'a table branch the walker cannot follow'
        if h1 == 0xe8bd and h2 & 0x8000:
            return 'return', None                                 # pop.w {..., pc}
        if h1 >> 9 == 0x7c and h1 & 0x0010 and h2 >> 12 == 15 and h1 & 0x0060 == 0x0040:
            return 'return', None                                 # ldr.w pc, [...]
        if h1 & 0xffd0 in (0xe890, 0xe910) and h2 & 0x8000:
            return 'bad', 'a load of pc from a register list the walker cannot follow'   # ldm.w / ldmdb with pc
        return 'other', None
    if h1 & 0xff87 == 0x4700 and (h1 >> 3) & 0xf != 14:
        return 'bad', 'an indirect branch (bx through a register other than lr) the walker cannot follow'
    if h1 & 0xfd87 == 0x4487:
        return 'bad', 'a write to pc (mov or add) the walker cannot follow'
    if h1 & 0xf800 == 0xe000:
        off = (h1 & 0x7ff) << 1
        return 'branch', a + 4 + (off - 0x1000 if off & 0x800 else off)
    if h1 & 0xf000 == 0xd000 and (h1 >> 8) & 0xf < 0xe:
        off = (h1 & 0xff) << 1
        return 'cbranch', a + 4 + (off - 0x200 if off & 0x100 else off)
    if h1 & 0xf500 == 0xb100:
        return 'cbranch', a + 4 + (((h1 >> 9) & 1) << 6 | ((h1 >> 3) & 0x1f) << 1)
    if h1 & 0xff00 == 0xbd00:
        return 'return', None                                     # pop {..., pc}
    if h1 == 0x4770:
        return 'return', None                                     # bx lr
    if h1 & 0xff00 == 0xbf00 and h1 & 0xf:
        m = h1 & 0xf
        return 'it', 4 - ((m & -m).bit_length() - 1)
    return 'other', None


def is_flow(h1, h2, a):
    """A branch, call or return of any kind (rule 1: none may come before the prologue push)."""
    kind, _ = classify(h1, h2, a)
    if kind in ('call', 'branch', 'cbranch', 'return', 'tbb', 'bad'):
        return True
    if size_of(h1) == 2 and h1 & 0xff00 == 0x4700:
        return True                                               # bx / blx register
    if size_of(h1) == 2 and h1 & 0xff00 == 0x4600 and ((h1 >> 7 & 1) << 3 | (h1 & 7)) == 15:
        return True                                               # mov pc, rm
    return False


def touches_sp(h1, h2):
    """Any instruction that reads or writes through sp, or changes sp (rule 1)."""
    if size_of(h1) == 2:
        if h1 & 0xf000 == 0x9000 or h1 & 0xf800 == 0xa800 or h1 & 0xff00 == 0xb000:
            return True
        if h1 & 0xfe00 in (0xb400, 0xbc00):
            return True
        if h1 & 0xfc00 == 0x4400:
            return 13 in ((h1 >> 7 & 1) << 3 | (h1 & 7), (h1 >> 3) & 0xf)
        return False
    if h2 is None:
        return False
    rn, rd, rm = h1 & 0xf, (h2 >> 8) & 0xf, h2 & 0xf
    if h1 & 0xfe00 == 0xe800 or h1 >> 9 == 0x7c or h1 & 0xee00 == 0xec00:
        return rn == 13
    if h1 & 0xf800 == 0xf000 and not h2 & 0x8000:
        return rn == 13 or rd == 13
    if h1 & 0xfe00 == 0xea00 or h1 & 0xfe00 == 0xfa00:
        return 13 in (rn, rd, rm)
    return False


def tbb_table(img, a):
    """The tbb table after the tbb at a: (entries, e). e is the smallest non-zero entry; the table is 2e bytes."""
    tab, ent = a + 4, []
    while True:
        if not img.inside(tab + len(ent), 1):
            raise Fail('tbb table runs off the image')
        ent.append(img.b[tab + len(ent) - FLASH])
        nz = [x for x in ent if x]
        if nz and len(ent) >= 2 * min(nz):
            e = min(nz)
            return ent[:2 * e], e


def walk(img, entry):
    """Instruction starts reached from entry by fall-through and every branch target (not calls). A path ends at an
    unconditional branch or a return; inside an IT block every instruction is conditional. Stays in entry+0x2000."""
    seen, work = set(), [entry]
    while work:
        a, itn = work.pop(), 0
        while entry <= a < entry + WALK_WINDOW and a not in seen:
            seen.add(a)
            h1, h2 = img.halves(a)
            n = size_of(h1)
            cond = itn > 0
            if itn:
                itn -= 1
            kind, x = classify(h1, h2, a)
            if kind == 'it':
                itn = x
            elif kind == 'bad':
                raise Fail('reaches %s at entry%s' % (x, signed(a - entry)))
            elif kind == 'tbb':
                if cond:
                    raise Fail('reaches a conditional tbb at entry%s' % signed(a - entry))
                ent, e = tbb_table(img, a)
                cases = ent[:-1] if ent[-1] == 0 else ent
                if 0 in cases:
                    raise Fail('the tbb at entry%s has a zero case' % signed(a - entry))
                work.extend(a + 4 + 2 * c for c in cases)
                break
            elif kind in ('branch', 'cbranch'):
                work.append(x)
                if kind == 'branch' and not cond:
                    break
            elif kind == 'return' and not cond:
                break
            a += n
    return seen


def identity(img, entry, used=None):
    """The address of the prologue push: one of the first five instructions, with no branch, call, return or sp
    access before it. Raises Fail when there is none."""
    a = entry
    for _ in range(5):
        h1, h2 = img.halves(a)
        for shape in PUSH_SHAPES:
            if shape_matches(shape, h1, h2):
                if used is not None:
                    used.add(shape)
                return a
        if is_flow(h1, h2, a) or touches_sp(h1, h2):
            break
        a += size_of(h1)
    raise Fail('has no push {..., lr} within its first five instructions')


# Immediate-offset store forms the highest-store check recognises: (form name, bytes stored; 0 for a list store).
STORE_FORMS = (
    ('str-imm5', 4), ('strh-imm5', 2), ('strb-imm5', 1),
    ('str.w-imm12', 4), ('strh.w-imm12', 2), ('strb.w-imm12', 1),
    ('str-imm8', 4), ('strh-imm8', 2), ('strb-imm8', 1),
    ('strd', 8), ('vstr-s', 4), ('vstr-d', 8), ('stm', 0),
)


def store_extent(h1, h2):
    """(form, rn, end offset or None, writeback) for an immediate-offset store, or None for anything else."""
    if size_of(h1) == 2:
        if h1 & 0xf800 == 0x6000:
            return 'str-imm5', (h1 >> 3) & 7, ((h1 >> 6) & 31) * 4 + 4, False
        if h1 & 0xf800 == 0x8000:
            return 'strh-imm5', (h1 >> 3) & 7, ((h1 >> 6) & 31) * 2 + 2, False
        if h1 & 0xf800 == 0x7000:
            return 'strb-imm5', (h1 >> 3) & 7, ((h1 >> 6) & 31) + 1, False
        if h1 & 0xf800 == 0xc000:
            return 'stm', (h1 >> 8) & 7, 4 * bin(h1 & 0xff).count('1'), True
        return None
    if h2 is None:
        return None
    rn = h1 & 0xf
    for form, val, n in (('str.w-imm12', 0xf8c0, 4), ('strh.w-imm12', 0xf8a0, 2), ('strb.w-imm12', 0xf880, 1)):
        if h1 & 0xfff0 == val:
            return form, rn, (h2 & 0xfff) + n, False
    for form, val, n in (('str-imm8', 0xf840, 4), ('strh-imm8', 0xf820, 2), ('strb-imm8', 0xf800, 1)):
        if h1 & 0xfff0 == val and h2 & 0x0800:
            p, u, w = (h2 >> 10) & 1, (h2 >> 9) & 1, (h2 >> 8) & 1
            off = (h2 & 0xff) if u else -(h2 & 0xff)
            return form, rn, (off if p else 0) + n, bool(w)
    if h1 & 0xfe50 == 0xe840:                                     # strd (any P/U/W)
        p, u, w = (h1 >> 8) & 1, (h1 >> 7) & 1, (h1 >> 5) & 1
        if p or w:
            off = (h2 & 0xff) * 4 * (1 if u else -1)
            return 'strd', rn, (off if p else 0) + 8, bool(w)
    if h1 & 0xffb0 == 0xed00 and h2 & 0x0e00 == 0x0a00:           # vstr with U = 0 (ends at or below +0)
        return ('vstr-s' if h2 & 0x0f00 == 0x0a00 else 'vstr-d'), rn, 0, False
    if h1 & 0xffb0 == 0xed80 and h2 & 0x0e00 == 0x0a00:           # vstr with U = 1
        n = 4 if h2 & 0x0f00 == 0x0a00 else 8
        return ('vstr-s' if n == 4 else 'vstr-d'), rn, (h2 & 0xff) * 4 + n, False
    if h1 & 0xffd0 == 0xe880 or h1 & 0xffd0 == 0xe900:            # stmia.w / stmdb
        return 'stm', rn, (4 * bin(h2 & 0xffff).count('1') if h1 & 0x0100 == 0 else 0), bool(h1 & 0x20)
    return None


# Planted encodings that prove each store recogniser can match (decoder branch must fire): (h1, h2, form, rn, end).
STORE_SAMPLES = (
    (0x6122, None, 'str-imm5', 4, 0x14), (0x80a2, None, 'strh-imm5', 4, 6), (0x7122, None, 'strb-imm5', 4, 5),
    (0xc40c, None, 'stm', 4, 8),
    (0xf8c4, 0x3104, 'str.w-imm12', 4, 0x108), (0xf8a4, 0x3010, 'strh.w-imm12', 4, 0x12),
    (0xf884, 0x3100, 'strb.w-imm12', 4, 0x101),
    (0xf844, 0x3c04, 'str-imm8', 4, 0), (0xf824, 0x3e02, 'strh-imm8', 4, 4), (0xf804, 0x3e01, 'strb-imm8', 4, 2),
    (0xe9c4, 0x5541, 'strd', 4, 0x10c), (0xed84, 0x7a04, 'vstr-s', 4, 0x14), (0xed84, 0x7b02, 'vstr-d', 4, 0x10),
    (0xe884, 0x000c, 'stm', 4, 8),
)


# ---------------------------------------------------------------------------------------------------------------
# Inputs: stock image, tree data, header.
# ---------------------------------------------------------------------------------------------------------------

def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def active_table(spec):
    """The one rebase table in baseline/ whose `to` is the tree's stock base."""
    found = []
    for p in sorted((FW/'baseline').glob('rebase-*-to-*.json')):
        t = json.loads(p.read_text())
        if t.get('to') == spec['stockBase']:
            found.append(t)
    if len(found) != 1:
        raise Fail('%d rebase tables lead to %s, need exactly 1' % (len(found), spec['stockBase']))
    return found[0]


def read_link():
    out = {}
    for m in re.finditer(r'^\s*(\w+)\s*=\s*(0x[0-9a-fA-F]+)\s*;', (FW/'link.ld').read_text(), re.M):
        if m.group(1) in out:
            raise Fail('link.ld defines %s twice' % m.group(1))
        out[m.group(1)] = int(m.group(2), 16) & ~1
    return out


def clang(args, text):
    r = subprocess.run(['xcrun', 'clang'] + args + ['-x', 'c', '-'], input=text, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


class Evaluator:
    """Integers (optionally with a u suffix) combined with + - * and parentheses, nothing else."""
    TOKEN = re.compile(r'\s*(?:(0[xX][0-9a-fA-F]+|\d+)[uU]?(?![0-9A-Za-z_])|([-+*()]))')

    def __init__(self, text):
        self.toks, pos = [], 0
        text = text.strip()
        while pos < len(text):
            m = self.TOKEN.match(text, pos)
            if not m or m.end() == pos:
                raise ValueError(text)
            self.toks.append(int(m.group(1), 0) if m.group(1) else m.group(2))
            pos = m.end()
        self.k = 0

    def value(self):
        v = self.sum()
        if self.k != len(self.toks):
            raise ValueError('trailing tokens')
        return v

    def peek(self):
        return self.toks[self.k] if self.k < len(self.toks) else None

    def sum(self):
        v = self.product()
        while self.peek() in ('+', '-'):
            op = self.toks[self.k]; self.k += 1
            v = v + self.product() if op == '+' else v - self.product()
        return v

    def product(self):
        v = self.atom()
        while self.peek() == '*':
            self.k += 1
            v *= self.atom()
        return v

    def atom(self):
        t = self.peek()
        self.k += 1
        if isinstance(t, int):
            return t
        if t == '(':
            v = self.sum()
            if self.peek() != ')':
                raise ValueError('missing )')
            self.k += 1
            return v
        if t == '-':
            return -self.atom()
        raise ValueError('unexpected %r' % (t,))


def header_values(flags):
    """{name: (value, derived parts or None)} for every TIO_STOCK_* macro and the two legacy TIO_MENU_* names."""
    rc, out, err = clang(['-dM', '-E', '--target=arm-none-eabi'] + flags, '')
    if rc:
        raise Fail('clang -dM on the tree flags failed: %s' % err.strip().splitlines()[0])
    defs = {}
    for line in out.splitlines():
        m = re.match(r'#define (\w+) (.*)$', line)
        if m and (m.group(1).startswith('TIO_STOCK_') or m.group(1) in LEGACY_NAMES) and m.group(1) != GUARD_MACRO:
            defs[m.group(1)] = m.group(2).strip()
    if not defs:
        raise Fail('no header macros found')
    names = sorted(defs)
    # One probe line per name, keyed by its index (a name between the markers would expand too).
    rc, out, err = clang(['-E', '-P', '--target=arm-none-eabi'] + flags, ''.join('@%d@ %s\n' % (k, n) for k, n in enumerate(names)))
    if rc:
        raise Fail('clang -E on the header probe failed: %s' % err.strip().splitlines()[0])
    expanded = {}
    for line in out.splitlines():
        m = re.match(r'@(\d+)@ (.*)$', line)
        if m:
            if names[int(m.group(1))] in expanded:
                raise Fail('header probe line %s appears twice' % m.group(1))
            expanded[names[int(m.group(1))]] = m.group(2)
    result = {}
    for n in names:
        if n not in expanded:
            raise Fail('header macro %s did not expand in the probe' % n)
        try:
            v = Evaluator(expanded[n]).value()
        except ValueError:
            raise Fail('header macro %s expands to %r, which is not a plain integer expression' % (n, expanded[n]))
        idents = set(re.findall(r'[A-Za-z_]\w*', re.sub(r'(0[xX][0-9a-fA-F]+|\d+)[uU]', '', defs[n])))
        parts = None
        if idents & set(defs):
            parts = re.fullmatch(r'\(?\s*(\w+(?:\s*\+\s*\w+)+)\s*\)?', defs[n])
            if not parts or any(p not in defs for p in re.split(r'\s*\+\s*', parts.group(1))):
                raise Fail('derived header macro %s is not a sum of header names: %s' % (n, defs[n]))
            parts = re.split(r'\s*\+\s*', parts.group(1))
        result[n] = (v, parts)
    return result


def check_header(build, flags):
    """Base refusal, the define lines' names, and no long hex token in the header. Returns the refused labels."""
    fails = []
    text = HEADER.read_text()
    expected = ['TD_STOCK_10412'] + ['TD_STOCK_%s' % b.replace('.', '') for b in build.STOCK_BASES]
    sums = [l for l in text.splitlines() if re.match(r'#if\s+TD_STOCK_\w+\s*\+', l)]
    if len(sums) != 1:
        fails.append('stock_layout.h has %d sum lines, need 1' % len(sums))
    elif re.findall(r'TD_STOCK_\w+', sums[0]) != expected or not re.search(r'!=\s*1\s*$', sums[0]):
        fails.append('stock_layout.h sum line names %s, need %s' % (' + '.join(re.findall(r'TD_STOCK_\w+', sums[0])), ' + '.join(expected)))
    defd = [l for l in text.splitlines() if l.startswith('#if !defined(TD_STOCK_')]
    if len(defd) != 1 or re.findall(r'TD_STOCK_\w+', defd[0]) != expected:
        fails.append('stock_layout.h defined-check line does not name exactly %s' % ', '.join(expected))
    for i, line in enumerate(text.splitlines(), 1):
        for m in re.finditer(r'0[xX][0-9a-fA-F]{6,}\w*', line):
            fails.append('stock_layout.h line %d has a 6-or-more-digit hex token %s' % (i, m.group(0)))
    probe = '#include "stock_layout.h"\n'
    inc = ['--target=arm-none-eabi', '-E', '-P', '-I', str(FW/'src')]
    refused = []
    for b in build.STOCK_BASES:
        rc, _, err = clang(inc + build.stock_defines(b), probe)
        if b == TREE_BASE:
            if rc:
                fails.append('base %s was refused by stock_layout.h: %s' % (b, err.strip().splitlines()[0]))
        elif rc == 0:
            fails.append('base %s was not refused by stock_layout.h' % b)
        elif 'no proven layout for this stock base' not in err:
            fails.append('base %s was refused by stock_layout.h, but not by its no-proven-layout check' % b)
        else:
            refused.append(b)
    rc, _, err = clang(inc, probe)
    if rc == 0:
        fails.append('no define was not refused by stock_layout.h')
    elif 'every TD_STOCK_* base define must be set' not in err:
        fails.append('no define was refused by stock_layout.h, but not by its defined check')
    else:
        refused.append('no define')
    return fails, refused


# ---------------------------------------------------------------------------------------------------------------
# Locators.
# ---------------------------------------------------------------------------------------------------------------

STR_HASH = re.compile(r'sha256=([0-9a-f]{64}),len=(\d+)$')


def str_text_of(sid):
    """The text of a quoted str: ID, or None for a hash ID."""
    m = re.fullmatch(r'"(.*)"', sid)
    return m.group(1) if m else None


class World:
    """Everything the locators read, and the caches built from the original image."""

    def __init__(self, img, link, edits, table, pins):
        self.img, self.link, self.edits = img, link, edits
        self.values = {v['name']: int(v['new'], 16) for v in table['values']}
        self.pins = pins
        self.cache = {}
        self.loads_cache = {}
        self.used = set()
        self.copies = []
        for i in range(0, 4096 - 11, 4):
            s, e, d = struct.unpack_from('<3I', img.b, i)
            if FLASH <= s < e <= img.end and not FLASH <= d < img.end:
                self.copies.append((s, e, d))

    def edit(self, target):
        if not target:
            raise Fail('edit: locator with an empty target')
        m = [e for e in self.edits if e.get('target') == target]
        if len(m) != 1:
            raise Fail('edit:%s matches %d edits, need exactly 1' % (target, len(m)))
        return int(m[0]['address'], 16)

    def string_runtime(self, sid):
        text = str_text_of(sid)
        if text is not None:
            if text not in LVGL_NAMES:
                raise Fail('str:"%s" carries vendor text; write it as sha256 and length' % text)
            raw = text.encode()
            hits = [m.start() for m in re.finditer(b'(?<=\\x00)' + re.escape(raw) + b'(?=\\x00)', self.img.b)]
        else:
            m = STR_HASH.match(sid)
            if not m:
                raise Fail('str:%s is neither a quoted LVGL name nor sha256=<64 hex>,len=<n>' % sid)
            n = int(m.group(2))
            hits = [x.start() for x in re.finditer(b'(?<=\\x00)[^\\x00]{%d}(?=\\x00)' % n, self.img.b)
                    if hashlib.sha256(x.group(0)).hexdigest() == m.group(1)]
        if len(hits) != 1:
            raise Fail('str:%s: %d copies in the AP image, need exactly 1' % (sid, len(hits)))
        fa = FLASH + hits[0]
        recs = [(s, e, d) for s, e, d in self.copies if s <= fa < e]
        if len(recs) != 1:
            raise Fail('str:%s lies in %d start-up copy records, need exactly 1' % (sid, len(recs)))
        s, e, d = recs[0]
        return d + fa - s

    def scan_loads(self, wanted):
        """For each value in `wanted`, the addresses of every literal load of it (C.4 scan), in address order."""
        need = [v for v in wanted if v not in self.loads_cache]
        if not need:
            return
        b, found = self.img.b, {v: [] for v in need}
        targets = set(need)
        hw = memoryview(bytes(b[:len(b) & ~1])).cast('H')
        count = len(hw)
        for k in range(count):
            h = hw[k]
            i = 2 * k
            if 0x4800 <= h <= 0x4fff:
                t = ((i + 4) & ~3) + (h & 0xff) * 4
            elif h == 0xf8df or h == 0xf85f:
                if k + 1 >= count:
                    continue
                imm = hw[k + 1] & 0xfff
                t = ((i + 4) & ~3) + (imm if h == 0xf8df else -imm)
            else:
                continue
            if t & 3 or t < 0 or t + 4 > len(b):
                continue
            w = struct.unpack_from('<I', b, t)[0]
            if w in targets:
                found[w].append(FLASH + i)
        self.loads_cache.update(found)

    def loads(self, value):
        self.scan_loads([value])
        return self.loads_cache[value]

    def lit_value(self, row):
        if row not in self.values:
            raise Fail('lit:%s: no such value row in the active table' % row)
        return self.values[row]

    def resolve(self, loc):
        if loc not in self.cache:
            self.cache[loc] = self._resolve(loc)
        return self.cache[loc]

    def _resolve(self, loc):
        if loc.startswith('call:'):
            inner, _, off = loc[5:].rpartition('@')
            if not inner or not re.fullmatch(r'0x[0-9a-f]+', off):
                raise Fail('%s: malformed call: locator' % loc)
            a = self.resolve(inner) + int(off, 16)
            d = decode(self.img, a, 'bl')
            if d is None:
                raise Fail('%s: no BL at %s%s (bytes %s)' % (loc, inner, signed(int(off, 16)), insn_bytes(self.img, a)))
            return d.field & ~1
        kind, _, rest = loc.partition(':')
        if kind == 'link':
            if rest not in self.link:
                raise Fail('%s: no such link.ld symbol' % loc)
            return self.link[rest]
        if kind == 'edit':
            return self.edit(rest)
        if kind == 'value':
            if rest not in self.values:
                raise Fail('%s: no such value row in the active table' % loc)
            return self.values[rest] & ~1
        if kind in ('lit', 'str'):
            key, _, k = rest.rpartition('#')
            if not key or not k.isdigit():
                raise Fail('%s: malformed locator' % loc)
            value = self.lit_value(key) if kind == 'lit' else self.string_runtime(key)
            pin = self.pins.get(kind, {}).get(key)
            if pin is None:
                raise Fail('%s: no pinned load total for %s' % (loc, key))
            got = self.loads(value)
            if len(got) != pin:
                raise Fail('%s:%s: %d loads, pinned %d' % (kind, key, len(got), pin))
            if int(k) >= len(got):
                raise Fail('%s: load %s does not exist' % (loc, k))
            return got[int(k)]
        raise Fail('%s: unknown locator form' % loc)

    def is_entry_form(self, loc):
        return loc.split(':', 1)[0] in ('link', 'edit', 'value', 'call')

    def check_load(self, loc, used):
        """For a lit: or str: locator, the instruction at the located address must decode as a literal load."""
        if loc.split(':', 1)[0] not in ('lit', 'str'):
            return
        a = self.resolve(loc)
        if not any(decode(self.img, a, s, used) for s in LOAD_SHAPES):
            raise Fail('%s: the located instruction (bytes %s) is not a literal load' % (loc, insn_bytes(self.img, a)))


def locators_in(loc):
    """Every locator nested in loc, outermost first."""
    out = [loc]
    while loc.startswith('call:'):
        loc = loc[5:].rpartition('@')[0]
        out.append(loc)
    return out


# ---------------------------------------------------------------------------------------------------------------
# Witness checks.
# ---------------------------------------------------------------------------------------------------------------

def transform(rec, img, d):
    t = rec['transform']
    if t == 'tbb':
        ent, e = tbb_table(img, d.a)
        return 2 * e, ('table of %d bytes' % (2 * e)), ent
    f = d.field
    if t == 'id' or t == 'vfp':
        return f, None, None
    if t == '+1':
        return f + 1, None, None
    if t == '+8':
        return f + 8, None, None
    return f + t['add'], None, None


def label(rec, off=None):
    return '%s witness %d (%s%s)' % (rec['constant'], rec['n'], rec['where'], signed(rec['at'] if off is None else off))


def check_regs(what, d, want):
    for k, v in sorted(want.items()):
        if k not in d.regs:
            raise Fail('%s: shape %s has no register %s' % (what, d.shape, k))
        if d.regs[k] != v:
            raise Fail('%s: register %s is %s%d, record says %s%d' % (what, k, 's' if k == 'sd' else 'r', d.regs[k], 's' if k == 'sd' else 'r', v))
    missing = sorted(set(d.regs) - set(want))
    if missing:
        raise Fail('%s: record does not give register(s) %s' % (what, ', '.join(missing)))


def check_witness(rec, world, img, header_value, used=None):
    """Check 4 for one record: locate, decode, registers, context, extra checks, transform, compare. Raises Fail."""
    base = world.resolve(rec['where'])
    a = base + rec['at']
    for loc in locators_in(rec['where']):
        world.check_load(loc, used)
    d = decode(img, a, rec['shape'], used)
    if d is None:
        raise Fail('%s: expected shape %s, found bytes %s that match no %s form' % (label(rec), rec['shape'], insn_bytes(img, a), rec['shape']))
    check_regs(label(rec), d, rec.get('regs', {}))
    for c in rec.get('context', []):
        cw = c.get('where', rec['where'])
        ca = world.resolve(cw) + c['at']
        what = '%s context %s%s' % (label(rec), cw, signed(c['at']))
        for loc in locators_in(cw):
            world.check_load(loc, used)
        cd = decode(img, ca, c['shape'], used)
        if cd is None:
            raise Fail('%s: expected shape %s, found bytes %s that match no %s form' % (what, c['shape'], insn_bytes(img, ca), c['shape']))
        check_regs(what, cd, c.get('regs', {}))
        if 'field' in c and cd.field != c['field']:
            raise Fail('%s: field %s, record says %s' % (what, hexs(cd.field), hexs(c['field'])))
        if 'target' in c:
            want = world.resolve(c['target'])
            if cd.field & ~1 != want:
                raise Fail('%s: bl does not go to %s' % (what, c['target']))
    if rec['transform'] == '+1':
        # The compare's flags must reach the bls/bhi unchanged: only mov-reg (which sets no flags) may come between.
        bcc = [c for c in rec['context'] if c['shape'] == 'bcc'][0]
        x, end = a + d.n, base + bcc['at']
        while x < end:
            if decode(img, x, 'mov-reg') is None:
                raise Fail('%s: the instruction at %s%s (bytes %s) between the compare and its bcc may change the flags' % (
                    label(rec), rec['where'], signed(x - base), insn_bytes(img, x)))
            x += 2
        cond = decode(img, end, 'bcc').field
        if x != end or cond not in PLUS_ONE_CONDS:
            raise Fail('%s: the compare is not followed by bls or bhi' % label(rec))
    value, note, ent = transform(rec, img, d)
    if rec['transform'] == 'tbb':
        if value != header_value + 1 or ent[header_value] != 0:
            raise Fail('%s: tbb %s, last byte %s; header says %s entries (needs a %d-byte table ending in a zero pad)' % (
                label(rec), note, hexs(ent[-1]), hexs(header_value), header_value + 1))
        return d
    if value != header_value:
        raise Fail('%s: field %s, transform %s gives %s, header says %s' % (
            label(rec), hexs(d.field), rec['transform'] if isinstance(rec['transform'], str) else 'add %d' % rec['transform']['add'],
            hexs(value), hexs(header_value)))
    return d


def function_entry(rec, world):
    f = rec.get('function')
    if f is None:
        return rec['where'], world.resolve(rec['where'])
    return '%s%s' % (f['where'], signed(f['at'])), world.resolve(f['where']) + f['at']


def check_function(rec, world, img, used=None):
    """Check 5 (rules 1 to 3) for one record. Returns the identity (prologue address)."""
    name, entry = function_entry(rec, world)
    try:
        ident = identity(img, entry, used)
        reached = walk(img, entry)
    except Fail as e:
        raise Fail('%s witness %d: function entry %s %s' % (rec['constant'], rec['n'], name, e))
    a = world.resolve(rec['where']) + rec['at']
    if a not in reached:
        raise Fail('%s witness %d: %s%s is not reached from its function entry' % (rec['constant'], rec['n'], rec['where'], signed(rec['at'])))
    foreign = sorted(x for x in reached if x != ident and any(shape_matches(s, *img.halves(x)) for s in PUSH_SHAPES))
    if foreign:
        raise Fail('%s witness %d: function entry %s reaches a second push {..., lr} at entry%s' % (rec['constant'], rec['n'], name, signed(foreign[0] - entry)))
    for c in rec.get('context', []):
        if 'where' in c and c['where'] != rec['where']:
            other = world.resolve(c['where'])
            try:
                oid = identity(img, other, used)
                oreached = walk(img, other)
            except Fail as e:
                raise Fail('%s witness %d: context function entry %s %s' % (rec['constant'], rec['n'], c['where'], e))
            if other + c['at'] not in oreached:
                raise Fail('%s witness %d: context %s%s is not reached from its function entry' % (rec['constant'], rec['n'], c['where'], signed(c['at'])))
            if any(x != oid and any(shape_matches(s, *img.halves(x)) for s in PUSH_SHAPES) for x in oreached):
                raise Fail('%s witness %d: context function entry %s reaches a second push {..., lr}' % (rec['constant'], rec['n'], c['where']))
        elif world.resolve(rec['where']) + c['at'] not in reached:
            raise Fail('%s witness %d: context %s%s is not reached from its function entry' % (rec['constant'], rec['n'], rec['where'], signed(c['at'])))
    for chk in rec.get('checks', []):
        reg = int(chk['highest-store'][1:])
        limit = None
        for x in sorted(reached):
            st = store_extent(*img.halves(x))
            if st and st[1] == reg:
                if st[3]:
                    raise Fail('%s witness %d: a store at entry%s writes back to r%d' % (rec['constant'], rec['n'], signed(x - entry), reg))
                limit = st[2] if limit is None else max(limit, st[2])
        if limit is None:
            raise Fail('%s witness %d: no store through r%d is reached' % (rec['constant'], rec['n'], reg))
        rec['_highest'] = limit
    return ident


def check_highest(rec, header_value):
    if 'checks' in rec and rec['_highest'] > header_value:
        raise Fail('%s: a store through %s ends at %s, beyond the header value %s' % (
            label(rec), rec['checks'][0]['highest-store'], hexs(rec['_highest']), hexs(header_value)))


# ---------------------------------------------------------------------------------------------------------------
# JSON structure (check 3).
# ---------------------------------------------------------------------------------------------------------------

def check_json(data):
    fails = []
    if data.get('format') != 'turboio-stock-layout-1' or data.get('stockBase') != TREE_BASE:
        fails.append('stock_layout_witnesses.json: format must be turboio-stock-layout-1 and stockBase %s' % TREE_BASE)
    if set(data) != TOP_KEYS:
        fails.append('stock_layout_witnesses.json: top-level keys must be exactly %s' % ', '.join(sorted(TOP_KEYS)))
    for row in data.get('moduleMessageIds', []):
        if set(row) != {'name', 'source'} or not re.fullmatch(r'[A-Z][A-Z0-9_]*', str(row.get('name'))) or \
                not re.fullmatch(r'[\w./-]+\.[ch]', str(row.get('source'))) or '..' in str(row.get('source')):
            fails.append('stock_layout_witnesses.json: module message id row %r needs exactly a macro name and a source path' % (row,))
    locs = []
    for i, r in enumerate(data.get('witnesses', [])):
        tag = 'record %d (%s)' % (i, r.get('constant'))
        extra = set(r) - RECORD_KEYS
        miss = {'constant', 'n', 'where', 'at', 'shape', 'regs', 'transform', 'why'} - set(r)
        if extra or miss:
            fails.append('%s: fields %s missing, %s unknown' % (tag, sorted(miss), sorted(extra)))
            continue
        if r['shape'] not in ENC:
            fails.append('%s: unknown shape %s' % (tag, r['shape']))
        if not (r['transform'] in TRANSFORMS or (isinstance(r['transform'], dict) and set(r['transform']) == {'add'} and isinstance(r['transform']['add'], int))):
            fails.append('%s: unknown transform %r' % (tag, r['transform']))
        if (r['transform'] == 'tbb') != (r['shape'] == 'tbb'):
            fails.append('%s: the tbb transform goes with the tbb shape only' % tag)
        if r['n'] not in (1, 2) or not isinstance(r['at'], int):
            fails.append('%s: n must be 1 or 2 and at an integer' % tag)
        if not isinstance(r['why'], str) or len(r['why']) < 10:
            fails.append('%s: why must be a sentence' % tag)
        if 'function' in r:
            if set(r['function']) != {'where', 'at'}:
                fails.append('%s: function needs exactly where and at' % tag)
            else:
                locs.append(r['function']['where'])
        elif not r['where'].split(':', 1)[0] in ('link', 'edit', 'value', 'call'):
            fails.append('%s: a %s locator is never a function entry; the record needs a function' % (tag, r['where'].split(':', 1)[0]))
        if 'exception' in r and (r['constant'], r['exception']) != SAME_FUNCTION_EXCEPTION:
            fails.append('%s: the only allowed exception is %s on %s' % (tag, SAME_FUNCTION_EXCEPTION[1], SAME_FUNCTION_EXCEPTION[0]))
        if 'checks' in r and (r['checks'] != [{'highest-store': r['checks'][0].get('highest-store')}] or not re.fullmatch(r'r\d+', str(r['checks'][0].get('highest-store'))) or r['transform'] != '+8'):
            fails.append('%s: checks may only be one highest-store on a register, with the +8 transform' % tag)
        if r['transform'] == '+8' and 'checks' not in r:
            fails.append('%s: the +8 transform needs the highest-store check' % tag)
        if r['transform'] == '+1':
            bccs = [c for c in r.get('context', []) if isinstance(c, dict) and c.get('shape') == 'bcc']
            if r['shape'] not in PLUS_ONE_SHAPES:
                fails.append('%s: the +1 transform goes with %s only' % (tag, ' or '.join(PLUS_ONE_SHAPES)))
            if len(bccs) != 1 or 'where' in bccs[0] or bccs[0].get('field') not in PLUS_ONE_CONDS or not isinstance(bccs[0].get('at'), int) or bccs[0]['at'] <= r['at']:
                fails.append('%s: the +1 transform needs one bcc context after the compare, in the same place, with field %s' % (
                    tag, ' or '.join('%d (%s)' % kv for kv in sorted(PLUS_ONE_CONDS.items()))))
        elif any(isinstance(c, dict) and c.get('shape') == 'bcc' for c in r.get('context', [])):
            fails.append('%s: a bcc context goes with the +1 transform only' % tag)
        locs.append(r['where'])
        for c in r.get('context', []):
            if set(c) - CONTEXT_KEYS or not {'at', 'shape'} <= set(c) or c['shape'] not in ENC:
                fails.append('%s: malformed context entry %r' % (tag, c))
                continue
            if 'target' in c and c['shape'] != 'bl':
                fails.append('%s: a context target goes with the bl shape only' % tag)
            locs.extend(x for x in (c.get('where'), c.get('target')) if x)
    for loc in locs:
        for inner in locators_in(loc):
            if inner.startswith('str:'):
                sid = inner[4:].rpartition('#')[0]
                text = str_text_of(sid)
                if text is not None and text not in LVGL_NAMES:
                    fails.append('str:"%s" carries vendor text; write it as sha256 and length' % text)
                elif text is None and not STR_HASH.match(sid):
                    fails.append('str:%s is neither a quoted LVGL name nor sha256=<64 hex>,len=<n>' % sid)
    for key in data.get('loads', {}).get('str', {}):
        text = str_text_of(key)
        if text is not None and text not in LVGL_NAMES:
            fails.append('str:"%s" carries vendor text; write it as sha256 and length' % text)
    if set(data.get('loads', {})) != {'lit', 'str'}:
        fails.append('stock_layout_witnesses.json: loads must hold lit and str pins')
    return fails, locs


def free_texts(data):
    """(where, text) for the JSON's free text: the note and every why."""
    out = [('stock_layout_witnesses.json note', data.get('note', ''))]
    for i, r in enumerate(data.get('witnesses', [])):
        out.append(('stock_layout_witnesses.json record %d (%s) why' % (i, r.get('constant')), r.get('why', '')))
    return [(w, t) for w, t in out if isinstance(t, str)]


def check_vendor_text(raw, texts):
    """Decision R4: refuse any text that contains a whole NUL-delimited AP image string of VENDOR_MIN bytes or more,
    other than the three LVGL names and a plain short word. Prints only the hash and length of what it finds."""
    allowed = {n.encode() for n in LVGL_NAMES}
    by_prefix = {}
    for m in re.finditer(b'(?<=\\x00)[^\\x00]{%d,}(?=\\x00)' % VENDOR_MIN, raw):
        s = m.group(0)
        if s in allowed or (len(s) < PLAIN_WORD_MAX and re.fullmatch(b'[A-Za-z]+', s)):
            continue
        by_prefix.setdefault(s[:VENDOR_MIN], set()).add(s)
    fails = []
    for where, text in texts:
        t = text.encode()
        for i in range(len(t) - VENDOR_MIN + 1):
            for s in by_prefix.get(t[i:i + VENDOR_MIN], ()):
                if t.startswith(s, i):
                    fails.append('%s holds an AP image string (sha256=%s,len=%d); vendor text may appear only as sha256 and length' % (
                        where, hashlib.sha256(s).hexdigest(), len(s)))
    return fails


# ---------------------------------------------------------------------------------------------------------------
# Item 5 (C.8).
# ---------------------------------------------------------------------------------------------------------------

def before_image(before, address):
    raw = bytes.fromhex(before)
    img = Image(bytes(address - FLASH) + raw + bytes(4))
    return img, len(raw)


def check_item5(spec, world, H, data, used):
    fails = []
    edits = spec['edits']

    def one(pred, what):
        m = [e for e in edits if pred(e)]
        if len(m) != 1:
            raise Fail('%s: %d edits, need exactly 1' % (what, len(m)))
        e = m[0]
        a = int(e['address'], 16)
        if world.img.raw(a, len(bytes.fromhex(e['before']))) != bytes.fromhex(e['before']):
            raise Fail('%s: before bytes differ from the stock image' % what)
        return e, a

    try:
        e, a = one(lambda e: e.get('target') == 'port_allocate_menu', 'edit port_allocate_menu')
        img, n = before_image(e['before'], a)
        d = decode(img, a, 'mov.w-imm', used)
        b = decode(img, a + 4, 'bl', used)
        if n != 8 or d is None or d.regs['rd'] != 0 or b is None or b.field & ~1 != world.resolve('link:port_stock_new'):
            raise Fail('edit port_allocate_menu: before is not mov.w r0,#imm then bl port_stock_new')
        if d.field != H['TIO_STOCK_MENU_BYTES'][0]:
            raise Fail('edit port_allocate_menu: before allocates %s bytes, TIO_STOCK_MENU_BYTES is %s' % (hexs(d.field), hexs(H['TIO_STOCK_MENU_BYTES'][0])))
        if a != world.resolve('link:nav_ensure_menu') + 0x38:
            raise Fail('edit port_allocate_menu: address is not link:nav_ensure_menu+0x38')
    except Fail as x:
        fails.append(str(x))
    try:
        if len([e for e in edits if not e.get('target')]) != 1:
            raise Fail('edits with an empty target: %d, need exactly 1' % len([e for e in edits if not e.get('target')]))
        e, a = one(lambda e: e.get('role') == 'Carousel item count 7 to 13' and not e.get('target'), 'edit "Carousel item count 7 to 13"')
        img, n = before_image(e['before'], a)
        d = decode(img, a, 'movs-imm8', used)
        if n != 2 or d is None or d.regs['rd'] != 1:
            raise Fail('edit "Carousel item count 7 to 13": before is not movs r1,#imm')
        if d.field != H['TIO_STOCK_MENU_TILES'][0]:
            raise Fail('edit "Carousel item count 7 to 13": before counts %d tiles, TIO_STOCK_MENU_TILES is %d' % (d.field, H['TIO_STOCK_MENU_TILES'][0]))
        if a != world.resolve('link:stock_ctor') + 0x48:
            raise Fail('edit "Carousel item count 7 to 13": address is not link:stock_ctor+0x48')
    except Fail as x:
        fails.append(str(x))
    try:
        e, a = one(lambda e: e.get('target') == 'stream_register_shim', 'edit stream_register_shim')
        img, n = before_image(e['before'], a)
        want = [('movs-imm8', {'rd': 4}, 0), ('ldr-lit', {'rt': 0}, None), ('ldr-lit', {'rt': 3}, None),
                ('str-imm5', {'rt': 4, 'rn': 0}, H['TIO_STOCK_FILE_CB_RECEIVE'][0]), ('str-imm5', {'rt': 3, 'rn': 0}, 0)]
        x = a
        for shape, regs, field in want:
            d = decode(img, x, shape, used)
            if d is None or d.regs != regs or (field is not None and d.field != field):
                raise Fail('edit stream_register_shim: before%s is not the expected %s' % (signed(x - a), shape))
            x += d.n
        if x - a != n:
            raise Fail('edit stream_register_shim: before has %d bytes, not the five instructions' % n)
    except Fail as x:
        fails.append(str(x))
    ids = data.get('moduleMessageIds', [])
    if not ids:
        fails.append('stock_layout_witnesses.json lists no module message ids')
    for row in ids:
        path = FW/'src'/row['source']
        text = path.read_text() if path.is_file() else ''
        name = re.escape(row['name'])
        hits = re.findall(r'^#define %s (0x[0-9a-fA-F]+)[uU]?\s*$' % name, text, re.M) + \
            re.findall(r'(?<![\w])%s\s*=\s*(0x[0-9a-fA-F]+)[uU]?(?![\w])' % name, text)
        if len(hits) != 1:
            fails.append('module message id %s: %d definitions in src/%s, need exactly 1' % (row['name'], len(hits), row['source']))
        elif int(hits[0], 16) <= H['TIO_STOCK_MESSAGE_ID_MAX'][0]:
            fails.append('module message id %s is %s, not above TIO_STOCK_MESSAGE_ID_MAX %d' % (row['name'], hits[0], H['TIO_STOCK_MESSAGE_ID_MAX'][0]))
    return fails, len(ids)


# ---------------------------------------------------------------------------------------------------------------
# Optional: assemble each witness's instruction with the pinned clang and compare bytes.
# ---------------------------------------------------------------------------------------------------------------

def asm_text(d, img):
    r, f, s = d.regs, d.field, d.shape
    R = lambda k: 'r%d' % r[k]
    mem = lambda: '[%s, #%d]' % (R('rn'), f)
    if s in ('movs-imm8', 'adds-imm8', 'subs-imm8', 'cmp-imm8'):
        return '%s %s, #%d' % (s.split('-')[0], R('rd' if 'rd' in r else 'rn' if 'rn' in r else 'rdn'), f)
    if s in ('adds-imm3', 'subs-imm3'):
        return '%s %s, %s, #%d' % (s.split('-')[0], R('rd'), R('rn'), f)
    if s == 'mov-reg':
        return 'mov %s, %s' % (R('rd'), R('rm'))
    if s in ('mov.w-imm', 'cmp.w-imm'):
        return '%s %s, #%d' % (s.split('-')[0], R('rd' if 'rd' in r else 'rn'), f)
    if s == 'add.w-imm':
        return 'add.w %s, %s, #%d' % (R('rd'), R('rn'), f)
    if s.endswith('-imm5'):
        return '%s.n %s, %s' % (s.split('-')[0], R('rt'), mem())
    if s.endswith('-imm12'):
        return '%s %s, %s' % (s.split('-')[0], R('rt'), mem())
    if s == 'strd-imm8':
        return 'strd %s, %s, %s' % (R('rt'), R('rt2'), mem())
    if s in ('vldr-s', 'vstr-s'):
        return '%s s%d, %s' % (s[:4], r['sd'], mem())
    if s == 'vmov.f32-imm':
        return 'vmov.f32 s%d, #%s' % (r['sd'], float(f))
    if s == 'tbb':
        return 'tbb [pc, %s]' % R('rm')
    return None


def llvm_check(records, world, llvm):
    lines, expect = [], []
    for rec, d in records:
        t = asm_text(d, world.img)
        if t is None:
            continue
        lines.append(t)
        expect.append((rec, world.img.raw(d.a, d.n)))
    src = '.syntax unified\n.thumb\n.text\n' + ''.join(l + '\n' for l in lines)
    with tempfile.TemporaryDirectory() as tmp:
        s, o, b = Path(tmp)/'w.S', Path(tmp)/'w.o', Path(tmp)/'w.bin'
        s.write_text(src)
        r = subprocess.run([str(llvm/'clang'), '--target=arm-none-eabi', '-mcpu=cortex-m33', '-mthumb', '-mfloat-abi=hard', '-mfpu=fpv5-sp-d16', '-c', str(s), '-o', str(o)], capture_output=True, text=True)
        if r.returncode:
            raise Fail('--llvm-bin: assembling the witness texts failed: %s' % r.stderr.strip().splitlines()[0])
        r = subprocess.run([str(llvm/'llvm-objcopy'), '-O', 'binary', '-j', '.text', str(o), str(b)], capture_output=True, text=True)
        if r.returncode:
            raise Fail('--llvm-bin: llvm-objcopy failed: %s' % r.stderr.strip())
        out = b.read_bytes()
    pos, fails = 0, []
    for (rec, raw), text in zip(expect, lines):
        got = out[pos:pos + len(raw)]
        if got != raw:
            fails.append('%s: clang assembles %r to %s, the image has %s' % (label(rec), text, got.hex(), raw.hex()))
        pos += len(raw)
    if pos != len(out):
        fails.append('--llvm-bin: assembled %d bytes, expected %d' % (len(out), pos))
    return fails, len(lines)


# ---------------------------------------------------------------------------------------------------------------
# Main.
# ---------------------------------------------------------------------------------------------------------------

def fail_out(lines):
    for l in dict.fromkeys(lines):
        print(PREFIX + l)
    raise SystemExit(1)


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('--stock', type=Path, required=True)
    p.add_argument('--llvm-bin', type=Path)
    args = p.parse_args(argv)

    # 1. The image pin.
    spec = json.loads((FW/'build-inputs.json').read_text())
    with zipfile.ZipFile(args.stock) as z:
        raw = z.read('nuttx_ap.bin')
    sha = hashlib.sha256(raw).hexdigest()
    if sha != spec['stockAP']:
        fail_out(['stock AP sha256 %s is not build-inputs.json stockAP %s' % (sha, spec['stockAP'])])
    if spec.get('stockBase') != TREE_BASE:
        fail_out(['build-inputs.json stockBase is %r; this test proves the %s layout only' % (spec.get('stockBase'), TREE_BASE)])

    # 2. The header: base refusal, define lines, no long hex token; then its values.
    build = load_module(FW/'build.py', 'stock_layout_build')
    host_layout = load_module(FW/'tests'/'host_layout.py', 'stock_layout_host_layout')
    fails, refused = check_header(build, host_layout.flags())
    try:
        H = header_values(host_layout.flags())
    except Fail as e:
        fails.append(str(e))
    if fails:
        fail_out(fails)
    # Every macro the header defines (other than its guard) must be one that needs witnesses, so a name outside the
    # TIO_STOCK_ prefix, or a function-like macro, cannot carry a stock value unproven.
    for i, line in enumerate(HEADER.read_text().splitlines(), 1):
        m = re.match(r'\s*#\s*define\s+(\w+)', line)
        if m and m.group(1) != GUARD_MACRO and m.group(1) not in H:
            fails.append('stock_layout.h line %d defines %s, which is not a witnessed header macro (TIO_STOCK_* or %s)' % (
                i, m.group(1), ' or '.join(LEGACY_NAMES)))
    derived = sorted(n for n in H if H[n][1])
    for n in derived:
        if (n, tuple(H[n][1])) != DERIVED_CONSTANT:
            fails.append('derived header macro %s = %s is not the one allowed derived constant %s = %s (decision R3)' % (
                n, ' + '.join(H[n][1]), DERIVED_CONSTANT[0], ' + '.join(DERIVED_CONSTANT[1])))
    if DERIVED_CONSTANT[0] not in derived:
        fails.append('header macro %s is not the sum %s' % (DERIVED_CONSTANT[0], ' + '.join(DERIVED_CONSTANT[1])))
    if fails:
        fail_out(fails)

    # 3. The JSON, and no vendor text in it or in the header.
    data = json.loads(WITNESSES.read_text())
    fails, _ = check_json(data)
    fails += check_vendor_text(raw, free_texts(data) +
                               [('stock_layout.h line %d' % i, l) for i, l in enumerate(HEADER.read_text().splitlines(), 1)])
    if fails:
        fail_out(fails)
    recs = data['witnesses']
    by_const = {}
    for r in recs:
        by_const.setdefault(r['constant'], []).append(r)
    for name in sorted(set(H) | set(by_const)):
        have = len(by_const.get(name, []))
        if name not in H:
            fails.append('witness records name %s, which is not a header macro' % name)
            continue
        need = 1 if H[name][1] else 2
        if have != need:
            fails.append('header macro %s has %d witnesses, need %d' % (name, have, need))
        elif sorted(r['n'] for r in by_const[name]) != list(range(1, need + 1)):
            fails.append('header macro %s: witness numbers are %s' % (name, sorted(r['n'] for r in by_const[name])))
        for part in H[name][1] or []:
            if H[part][1]:
                fails.append('derived header macro %s names %s, which is itself derived' % (name, part))
    nctx = sum(len(r.get('context', [])) for r in recs)
    if nctx != CONTEXT_ENTRIES:
        fails.append('stock_layout_witnesses.json has %d context entries, pinned %d' % (nctx, CONTEXT_ENTRIES))
    if fails:
        fail_out(fails)

    img = Image(raw)
    table = active_table(spec)
    world = World(img, read_link(), spec['edits'], table, data['loads'])
    used = set()

    # Resolve every pinned total in one scan, so the scan runs once.
    try:
        wanted = [world.lit_value(k) for k in data['loads']['lit']] + [world.string_runtime(k) for k in data['loads']['str']]
    except Fail as e:
        fail_out([str(e)])
    world.scan_loads(wanted)

    # 4 and 5. Each witness, then the function rule.
    decoded, idents = [], {}
    for r in recs:
        try:
            d = check_witness(r, world, img, H[r['constant']][0], used)
            ident = check_function(r, world, img, used)
            check_highest(r, H[r['constant']][0])
            decoded.append((r, d))
            idents.setdefault(r['constant'], []).append((r, ident))
        except Fail as e:
            fails.append(str(e))
    same_pairs = 0
    for name, items in sorted(idents.items()):
        if H[name][1] or len(items) != 2:
            continue
        (r1, i1), (r2, i2) = items
        named = all(r.get('exception') == SAME_FUNCTION_EXCEPTION[1] for r in (r1, r2)) and name == SAME_FUNCTION_EXCEPTION[0]
        if i1 == i2 and not named:
            fe = r1.get('function', {'where': r1['where'], 'at': 0})
            ident_off = i1 - world.resolve(fe['where'])
            fails.append('%s: both witnesses are in the function whose prologue is at %s%s; need two functions' % (name, fe['where'], signed(ident_off)))
        elif i1 != i2 and named:
            fails.append('%s: named same-function exception, but the witnesses are in two functions; drop the exception' % name)
        elif named:
            same_pairs += 1
        elif any('exception' in r for r in (r1, r2)):
            fails.append('%s: an exception must be on both witnesses' % name)

    # 6. The pinned load totals.
    for kind in ('lit', 'str'):
        for key, pin in sorted(data['loads'][kind].items()):
            try:
                value = world.lit_value(key) if kind == 'lit' else world.string_runtime(key)
                got = len(world.loads(value))
                if got != pin:
                    fails.append('%s:%s: %d loads, pinned %d' % (kind, key, got, pin))
            except Fail as e:
                fails.append(str(e))
            if not any(inner.startswith('%s:%s#' % (kind, key)) for r in recs
                       for loc in [r['where'], r.get('function', {}).get('where', '')] + [c.get('where', '') for c in r.get('context', [])] + [c.get('target', '') for c in r.get('context', [])]
                       for inner in locators_in(loc) if loc):
                fails.append('%s:%s: pinned but used by no locator' % (kind, key))

    # 7. The table cross-checks.
    v = world.values
    for row, name in (('native_light_current', 'TIO_STOCK_LVGL_MEM_USED'), ('native_light_peak', 'TIO_STOCK_LVGL_MEM_PEAK')):
        if row not in v or 'display_unit' not in v or v[row] != v['display_unit'] + H[name][0]:
            fails.append('table row %s is not display_unit + %s' % (row, name))

    # 8. Item 5.
    f5, nids = check_item5(spec, world, H, data, used)
    fails += f5

    # Every decoder entry must have matched at least once, and every store recogniser must match its sample.
    unused = sorted(set(ENC) - used)
    if unused:
        fails.append('decoder entries that no witness uses (delete them): %s' % ', '.join(unused))
    for h1, h2, form, rn, end in STORE_SAMPLES:
        st = store_extent(h1, h2)
        if not st or st[:3] != (form, rn, end):
            fails.append('store recogniser %s does not match its sample' % form)
    if {s[2] for s in STORE_SAMPLES} != {f for f, _ in STORE_FORMS}:
        fails.append('store samples do not cover every store recogniser')

    if args.llvm_bin and not fails:
        lf, _ = llvm_check(decoded, world, args.llvm_bin)
        fails += lf
    if fails:
        fail_out(fails)

    # 9. The mutation self-check.
    refused_count = 0
    for r, d in decoded:
        hv = H[r['constant']][0]
        try:
            check_witness(r, world, img, hv + 1)
            fails.append('%s: still passes with the header value plus one' % label(r))
        except Fail:
            refused_count += 1
        if r['shape'] == 'tbb':
            ent, e = tbb_table(img, d.a)
            o = d.a + 4 + ent.index(e) - FLASH
            old = img.b[o]
            img.b[o] = old + 1
        elif ENC[r['shape']]['low'] is None:
            fails.append('%s: shape %s has no immediate field to mutate' % (label(r), r['shape']))
            continue
        else:
            k, bit = ENC[r['shape']]['low']
            o = d.a + 2 * k - FLASH + (bit >> 3)
            old = img.b[o]
            img.b[o] = old ^ (1 << (bit & 7))
        try:
            check_witness(r, world, img, hv)
            fails.append('%s: still passes with its immediate field changed in the image' % label(r))
        except Fail:
            refused_count += 1
        finally:
            img.b[o] = old
    # Every bit of the first live use of each encoding, flipped one at a time. A fixed bit must make the shape fail
    # and the record fail. Any other bit must change the decoded registers or field, or be a declared don't-care bit
    # that changes neither; so a mask that is too loose, or a don't-care mask that hides a field, is refused.
    first = {}
    for r, d in decoded:
        for shape, a in uses_of(r, world, img):
            first.setdefault(shape, (r, a))
    for shape in sorted(ENC):
        if shape not in first:
            fails.append('encoding %s: no witness use to mutate' % shape)
            continue
        r, a = first[shape]
        e = ENC[shape]
        ref = decode(img, a, shape)
        dontcare = e.get('dontcare', (0,) * len(e['fixed']))
        for k in range(e['n'] // 2):
            fixed = e['fixed'][k][0]
            for bit in range(16):
                o = a - FLASH + 2 * k + (bit >> 3)
                old = img.b[o]
                img.b[o] = old ^ (1 << (bit & 7))
                try:
                    got = decode(img, a, shape)
                    same = got is not None and got.regs == ref.regs and got.field == ref.field
                    if fixed >> bit & 1:
                        if got is not None:
                            fails.append('encoding %s: still matches with fixed bit %d of halfword %d flipped' % (shape, bit, k))
                            continue
                        try:
                            check_witness(r, world, img, H[r['constant']][0])
                            check_function(r, world, img)
                            fails.append('encoding %s: %s still passes with fixed bit %d of halfword %d flipped' % (shape, label(r), bit, k))
                        except Fail:
                            pass
                    elif dontcare[k] >> bit & 1:
                        if not same:
                            fails.append('encoding %s: declared don\'t-care bit %d of halfword %d changes the decode' % (shape, bit, k))
                    elif same:
                        fails.append('encoding %s: bit %d of halfword %d is not fixed, not in a field and not declared don\'t-care' % (shape, bit, k))
                finally:
                    img.b[o] = old
    if fails:
        fail_out(fails)

    leaves = [n for n in H if not H[n][1]]
    derived = [n for n in H if H[n][1]]
    bases = [b for b in refused if b != 'no define']
    print('PASS stock layout (%s): %d constants, %d witnesses (%d constants with two, in distinct functions except %d named '
          'same-function pair%s; %d derived constant%s with one direct witness), bases %s and no define refused, %d mutations '
          'refused, every encoding refuses a changed opcode, the menu allocation, carousel count and file callback edits '
          'agree, %d module message ids above %d' % (
              TREE_BASE, len(H), len(recs), len(leaves), same_pairs, '' if same_pairs == 1 else 's', len(derived),
              '' if len(derived) == 1 else 's', ', '.join(bases), refused_count, nids, H['TIO_STOCK_MESSAGE_ID_MAX'][0]))


def uses_of(rec, world, img):
    """(shape, address) of every live decode in one record: the literal loads of its locators, its instruction, its
    context instructions and its function's prologue push."""
    out = []
    locs = [rec['where']] + [c['where'] for c in rec.get('context', []) if 'where' in c]
    for loc in locs:
        for inner in locators_in(loc):
            if inner.split(':', 1)[0] in ('lit', 'str'):
                a = world.resolve(inner)
                for s in LOAD_SHAPES:
                    if decode(img, a, s):
                        out.append((s, a))
    out.append((rec['shape'], world.resolve(rec['where']) + rec['at']))
    for c in rec.get('context', []):
        out.append((c['shape'], world.resolve(c.get('where', rec['where'])) + c['at']))
    _, entry = function_entry(rec, world)
    ident = identity(img, entry)
    for s in PUSH_SHAPES:
        if decode(img, ident, s):
            out.append((s, ident))
    return out


if __name__ == '__main__':
    main(sys.argv[1:])
