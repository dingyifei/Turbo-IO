#!/usr/bin/env python3
"""Independent re-derivation of one stock rebase pair. Offline: reads two stock ZIPs and two trees.

  python3 -I firmware/tests/rebase_independent_test.py                 # default pair; exports its old tag itself
  python3 -I firmware/tests/rebase_independent_test.py --pair FROM:TO  # another pair of PAIRS
  python3 -I firmware/tests/rebase_independent_test.py --old-tree DIR  # DIR = a `git archive <oldTag> firmware
                                                                       #   <oldStock>` export
  python3 -I firmware/tests/rebase_independent_test.py --derive-only [--json PATH]   # developer/acceptance only
  python3 -I firmware/tests/rebase_independent_test.py --derive-only --disable-method NAME   # acceptance only:
                                                                       #   NAME (repeatable) is one of TEST_METHODS

The pairs, their old tags, stock ZIPs, AP hashes and known-bad rows are in PAIRS. The default pair is the last pair
whose table exists in the new tree. The new stock ZIP is a repository file or a file under $TURBO_INPUTS (which must
be exported for such a pair); both AP images must have the pinned SHA-256.

It does not read the rebase table to find an address, and it does not use the decomp study, rebase_apply.py,
rebase_derive.py, stock_zip.py or any readiness TSV. Every address is derived again here, at run time, from the two
stock AP images, and only then compared with the new tree and with the pair's table. --derive-only stops after the
derivation: it prints a summary marked "derive-only", compares with no tree or table, and exits 0 when every row
resolves, 3 when some rows are unresolved (each listed with its reason), and 1 when a known-bad row fails or on any
other error.

Universe. Every stock address in the OLD tree (the pair's old tag): the link.ld symbols and module start, the edits
of build-inputs.json (plus the pair's reviewed addedCode, addedRam and addedEdits), the stock ABI ranges, and every hex token under src/, include/, tests/, trampolines.S and
ImageWireFormat.h that falls inside the old AP image or the RAM window 0x18000000-0x1a000000. A token in that window
that is not a stock address must be listed in NOT_STOCK with a reason, else the run fails. The old tree's
tests/stock_abi_test.py lists the ranges on the first base only; for a later pair their old addresses come from the
frozen earlier tables in the old tree (each one's old column must equal the previous result), and the old image must
have the listed hash at every range. A link.ld symbol in the RAM window is derived like a RAM value.

Image layout. The AP image is mapped at FLASH 0x10190000. Its start-up copy table (word triples src, src_end, dst
in the first 4 KiB) is parsed from each image, which gives the copy region (dst 0x100000) and the .data copy
(dst 0x18000000) without hard-coding their file offsets.

Thumb bit. All code searches work on even byte addresses (bit 0 stripped). A code value keeps the bit it had in
the old tree (new = derived | (old & 1)); patch sites and ABI ranges are even; RAM and .data values are plain byte
addresses and are taken whole from literal votes. The run asserts old & 1 == new & 1 for every code value.

Methods.
  sig    Masked signature. A window of old bytes around the address (several shapes: 0..32, 0..48, 0..64, -16..16,
         -32..32, -32..0, -64..0, 0..24, 0..16) is decoded as Thumb-2. The immediate bits of BL and B.W (T4), the
         offset of pc-relative loads, and every literal-pool word those loads reach (pools referenced from up to
         4 KiB before the window included) are masked. Each window is searched over the whole new image (even
         positions). The answer is the hit of the windows that have exactly one hit. Windows holding 16 bytes or
         more at or after the address decide; windows that end before that (the code before the address) only
         decide when no forward window is unique, and their disagreement is printed as "follows a different body"
         (that is how the matcher's tgr_intercept partner went wrong). All deciding windows must agree, and a
         forward window with several hits must contain the answer. A weak answer (no deciding window of 32 bytes,
         or backward windows only) with no caller vote must be corroborated by an edge (below).
  edge   Every BL/B.W inside a matched window gives an (old target, new target) pair. Any pair whose old target is
         a universe code address must equal that address's derived value; pairs are pooled over the whole run.
  call   Caller votes. Up to 12 old BL/B.W sites that target the address are paired by their own masked windows,
         and the new branch target at the paired site is a vote. The top vote must match sig (when both exist).
  lit    Literal votes, for RAM/.data/code-pointer values: every aligned old literal word equal to the value, every
         pc-relative load that reaches it, that load paired by its masked window, and the literal it reads in the
         new image is a vote. At least 75 % of the votes must agree.
  field  For a RAM value with no literal of its own: a resolved RAM base R with 0 < value - R < 0x400, the old
         ldr.w/str.w [Rn,#value-R] sites that use the base literal R, and at their paired new sites the same
         instruction with the same offset and the new base literal. Then new = R' + (value - R).
  str    For .data values: the NUL-terminated string at the old address equals the one at the new address, or differs
         from it by exactly the reviewed substring change of the pair's stringChanges for that old address.
  struct The module VA: the old tree's module start is FLASH + AP bytes - k with the same k-byte trailer in both
         images; the new one is FLASH + new AP bytes - k.
  copy   Copy-region callees (below FLASH): the function bytes in the copy region are identical in both images,
         at the same runtime address, so the value does not move.

  The methods below were added for stock 1.0.6.11. Each one only applies where the methods above leave a row
  unresolved or weak, or adds votes that can only make a row disagree. Two terms:
  - Function end: the first unconditional return after the address (pop {..,pc} or bx lr outside an IT block,
    pop.w/ldm sp! with pc, ldr pc,[sp],#4), capped at 0x200 bytes. The bounded body is [address, function end).
  - T2 mask: the masked window above, plus the U bit of LDR.W (literal), plus the immediate field of the 16-bit
    ALU, load/store, ADR and SP forms, of modified-immediate, MOVW/MOVT, ADDW/SUBW, imm8/imm12 load/store,
    LDRD/STRD, VLDR and VMOV.F32, and the offsets of local branches (B, B<cond>, CBZ/CBNZ, B<cond>.W). VSTR keeps
    its offset (narrower than the spec's VLDR/VSTR, so stricter), and B<cond>.W keeps every bit but its offset.
  bounded  Only for a row whose one problem is "sig X and call Y disagree". When every signature window that alone
         names X ends past the function end, the windows are clipped at the function end (clips under 8 bytes are
         dropped) and sig is computed again. If that names Y or nothing, and the bounded body is T2-equal at Y with
         the same bounded length in the new image, the row resolves to Y; the proof prints at how many new places
         the body is T2-equal with that length, since a short body says little and the answer then rests on the
         caller votes. A window inside the function that names X leaves the row unresolved.
  tsig   When sig has no unique window: the T2-masked bounded body hits once in the old image (at the address) and
         once in the new. The answer is weak (it needs a caller vote or a corroborating edge, as above), and its
         BL/B.W pairs join the edge pool.
  t2site A caller site that no site window pairs is tried with the same windows under the T2 mask; a deciding
         window has exactly one old hit (the site) and one new hit, and all deciding windows must agree. Its votes
         join the call tally. The `call` text (n/m votes for X) counts the T1-paired votes only, so it does not
         change when t2site is disabled, and a row with no T1-paired vote has no `call` text: its votes are
         reported under t2site only, and route names say t2site.
  prefix For a link.ld, edit or ABI row that is unresolved or weak: s is the greatest old BL/B.W target with
         x - 0x400 < s < x, every row at s is resolved by sig, call, t2site or edge (not by prefix or strpool),
         x lies before the end of the bounded body from s and s' + (x - s) before the end of the one from s', and the
         T2-masked old bytes [s, x), decoded from s and landing on x, equal the new bytes at s'. The answer is
         s' + (x - s). It resolves an unresolved or weak row, and a row resolved to another address gets the
         problem "prefix disagrees".
  strpool For an unresolved code-literal value row whose lit votes all name one address c: the printable strings
         of at least 8 bytes that word loads in the old bounded body and in c's bounded body read. A string
         qualifies when it is NUL-delimited, unique in its image once digit runs are normalised, and held by one
         literal word, in both images. Two or more qualifying strings loaded in both bodies resolve the row to c,
         when the one the old body loads first is also loaded at the same instruction index from c (this pins c
         to the function start, not an instruction before or after it); a qualifying old string whose new
         counterpart is loaded outside c's body, or a first load at another index, is a problem.
  reviewed-split  The pair's reviewedSplits block (below). It runs after the known-bad check, and the known-bad
         check runs again after it.

Checks, all fatal: every universe address resolved (no conflicts, every method that applies agrees); every value in
the new tree equals the derived one at the same files and counts as the old tree (and no old value is left); every
table value equals it; universe count == count of rows checked (printed); the edits' `before` bytes match the new
image at the derived address; ABI range hashes match the new image; every known-bad row of the pair has no caller
vote for the bad value (and, where windowsDiffer is True, every forward window mismatches at the bad value) and
either is derived to its good value with at least one caller vote for it ("resolved"), or, only for an entry marked
split=True, stays unresolved with "sig X and call Y disagree" as its one problem, where Y (the callers' winning
address) is the good value without its Thumb bit, the good value has the old value's Thumb bit, and at least three
quarters of all caller votes go to Y ("split, unresolved"). The split case is a function stock split in two: the
signature finds the old first bytes in one place and every caller calls the other. It does not resolve the row: the
row stays unresolved in the rows, the JSON and the exit code (3 in --derive-only) and needs a reviewed decision. The
derivation rule (any disagreement between methods leaves a row unresolved) is the same for every row. The four
copy-region callees are unchanged and the strcmp veneer still reaches strcmp.
resume_X equals trampoline edit X + 5. A mutation check (in a temp copy, never the repo) sets one link.ld address
and one source RAM value of the new tree, and one link.ld row and one edit row of the table, to a neighbour's value,
and requires each to be reported.
"""
import argparse
import bisect
from collections import Counter, defaultdict
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile

FW = Path(__file__).resolve().parents[1]
ROOT = FW.parent
FLASH = 0x10190000
RAM_LO, RAM_HI = 0x18000000, 0x1a000000
SCANNED = ('src', 'include', 'tests', 'trampolines.S', 'ImageWireFormat.h')
SELF = 'tests/rebase_independent_test.py'

# Tokens inside the scanned address windows that are not stock addresses. Each is also checked at run time to have
# no literal in either stock image, except the region bases, which are checked against the parsed copy table.
NOT_STOCK = {
    '0x10190000': 'FLASH base of the AP image (region bound, not an address in it)',
    '0x18000000': 'RAM base / .data copy destination (region bound)',
    '0x18001000': 'fake display unit in native_display_test.c',
    '0x18002000': 'fake display in native_display_test.c',
    '0x18617cb0': 'fake key in render_idle_test.c (no literal in either stock image; not a 1.0.5.5 address)',
    '0x19000000': 'fake unit in render_idle_test.c', '0x1900000c': 'fake unit field', '0x19000018': 'fake unit field',
    '0x19000100': 'fake unit in render_idle_test.c', '0x1900010c': 'fake unit field', '0x19000118': 'fake unit field',
    '0x19100000': 'fake display in render_idle_test.c', '0x191002a0': 'fake display field',
    '0x19200000': 'fake layer in render_idle_test.c', '0x19200038': 'fake layer field',
    '0x19200040': 'fake layer field',
}
# The rebase pairs, in rebase order. Stock paths, AP hashes and known-bad rows are written here in this file's own form,
# independently of build.py's STOCK_SHAPES and of the tables' `bases`. oldStock is a path inside the oldTag export;
# newStock is ('repo', path) or ('inputs', path under $TURBO_INPUTS). addedAfterOldTree: link symbols added after the
# old tree (RAM data, not code), verified by pool_context_check instead of by the old-tree universe. stringChanges:
# old .data address -> the one reviewed substring change its string may have. addedCode: link.ld code symbols added
# after the old tree -> their old-base value (Thumb bit included), reviewed on the old image; each one joins the old
# universe as a link row before the derivation, so every method re-derives it like any other code symbol. addedRam: the
# same for a RAM link.ld symbol (derived by literal votes like any RAM row; at least two votes required). addedEdits: entry
# trampolines added after the old tree -> (old address, old before), reviewed on the old image; each joins the old
# universe as an edit (kind bw) and adds resume_<name> = old + 5 as a link row, so the edit is derived like any code
# address, must be a called function entry (as addedCode) or, marked 'pointer', a stored function pointer (literal votes
# for old | 1 name the derived value | 1, and every voting load is an LDR into r1 directly followed in both images by a
# BL to one slot setter, the new BL target being the setter's signature answer), and its resume row must be the derived
# edit + 5. knownBad: values known to be wrong
# upstream; `good` only cross-checks the derivation and is never used to derive anything. windowsDiffer=None asserts
# nothing about the masked windows at the bad value (native_label_create has an identical-code twin). A known-bad entry
# passes when the bad value has no caller vote and the row resolves to `good`. split=True allows one more case, for a
# function stock split in two (1.0.6.11 split the one at old 0x1057_cfc4): the row is unresolved with the signature and
# caller methods disagreeing as its only problem, the callers' winning address is `good` without its Thumb bit, `good`
# keeps the old value's Thumb bit, and at least 3/4 of all caller votes go to the winning address. The row then stays unresolved (exit 3 in --derive-only) and needs a reviewed
# decision; split never changes the derivation. An entry without split must resolve to `good`. rebase_apply counts
# value tokens in every scanned file, this one included, so a value address here is written with a digit separator.
# reviewedSplits (one entry per line): old link.ld value -> the reviewed decision for a split function. It applies to
# every link.ld row with that old value, after the known-bad check and only when all of these hold: the row's one
# problem is exactly "sig <decoy> and call <new without its Thumb bit> disagree"; its `call` text (T1 votes only)
# equals `votes`; the old bounded body has `old` = (length, sha256); the new bounded body at `new` has `newBytes` =
# (length, sha256); `new` keeps the old Thumb bit; and the edge pool holds no other new address for the old function.
# The row then resolves to `new`, and the known-bad check runs again and must find the good value. Otherwise the row
# stays unresolved and the entry is printed with the reason it did not apply.
PAIRS = {  # insertion order = rebase_apply.TABLES order
 ('1.0.5.5', '1.0.5.12'): dict(oldTag='fw/tmg9', table='baseline/rebase-1.0.5.5-to-1.0.5.12.json',
    oldStock='firmware-research/strix-1.0.5.5/stock/Strix-OS-1.0.5.5-original.zip',   # from the export
    newStock=('repo', 'firmware-research/strix-1.0.5.12/stock/Strix-OS-1.0.5.12-original.zip'),
    oldAP='b3d6d9d7a4ece97e1dbaa64fc080eb5db8a5f7c9fecf340888ebb97a9112cc6c',
    newAP='af701a6525fbf703854b3d63e757734546c20bdb5d50e246867dc6a0565713ae',
    addedAfterOldTree={'tio_imu_family'}, stringChanges={},
    knownBad={'tgr_intercept': dict(bad=0x10625941, good=0x1062c439, windowsDiffer=True)}),
 ('1.0.5.12', '1.0.6.11'): dict(oldTag='fw/tmg11', table='baseline/rebase-1.0.5.12-to-1.0.6.11.json',
    oldStock='firmware-research/strix-1.0.5.12/stock/Strix-OS-1.0.5.12-original.zip',
    newStock=('inputs', 'tmg12-emu/stock/Strix-OS-1.0.6.11-members-canonical.zip'),
    oldAP='af701a6525fbf703854b3d63e757734546c20bdb5d50e246867dc6a0565713ae', newAP='9bbf7be31ebb7f8600e6ea4bf51831a151e2af6d4eb8e6ccfcf55d67f2e71260',
    addedAfterOldTree=set(), stringChanges={0x1804_338b: (':58]', ':62]')},
    addedCode={'tio_light_latest': 0x1062_c3d5,   # F5: stock's latest-light getter
               # TMG13 PIN lock: stock calls (SYMBOLS.md / HOOKS.md of the lock RE)
               'pmu_rtc_epoch': 0x1058_6a49, 'kws_enable': 0x1055_9b75,
               'kws_disable': 0x1055_9be9, 'key_queue_flush': 0x1062_c5f1, 'ots_topic_read': 0x1062_0fcd,
               'neck_send': 0x104e_892d,   # TMG14 head motion: neck_monitor_rpmsg_ap_send_to_bth
               'tio_lv_obj_move_to_index': 0x1054_9db5},   # TMG17: LVGL lv_obj_move_to_index
    addedRam={'tio_key_interceptors': 0x1975_46e4,   # TMG13: the key interceptor list head
              'tio_focus_manager': 0x196c_69f4},   # TMG17: the focus-mode manager singleton pointer
    # TMG13 entry trampolines: role -> (old address, old before[, 'pointer']); each adds resume_<name> = old + 5 to the
    # old universe. ('pointer', arg): reached only through a stored function pointer (no BL caller), loaded into r<arg>
    # right before the BL that consumes it (the indev slot setter, or the LVGL timer constructor)
    addedEdits={'Entry trampoline can_wakeup': (0x1055_a488, '2de9f041'),
                'Entry trampoline open_remote_audio': (0x1055_dbcc, '2de9f047'),
                'Entry trampoline open_recorder': (0x1055_ccfc, 'f0b583b0'),
                'Entry trampoline screen_state': (0x1064_5d48, '2de9f041'),
                'Entry trampoline factory_reset': (0x1058_6098, 'b0b582b0', 'pointer', 0),   # reset worker timer callback
                'Entry trampoline key_read': (0x1080_a918, '002390b5', 'pointer', 1),
                'Entry trampoline wheel_read': (0x1071_caf0, '2de9f04f', 'pointer', 1),
                # TMG14: the neck rx endpoint callback, passed to rpmsg_create_ept (through an ITCM veneer) on the stack
                'Entry trampoline neck_rx': (0x104e_923c, 'b0b590b0', 'pointer', 'stack')},
    newTreeChanges=dict(pruneLink={'dots_getrandom', 'dots_stock_notify', 'ce_utc_time', 'ce_focus_manager',
                                   'ce_focus_enabled', 'ce_head_mode', 'ce_stock_head_notify_resume',
                                   'ce_stock_head_start_resume', 'ce_stock_head_stop_resume',
                                   'ce_stock_sys_destroy_resume'},
                        valueToLink={0x1998_9694: 'tio_launcher_global'},   # '_': not a value token for rebase_apply
                        # F7 candidate 3: code-comment values whose old address was never the function the comment
                        # names. comment_corrections() checks each against this file's own derivation and the new image.
                        commentFix={0x1060_2514: dict(derived=0x1063_1b44, new=0x104d_b610, link='stream_timer_create'),
                                    0x1073_b9c8: dict(derived=0x107c_6cc0, new=0x105f_9460,
                                                      body=(86, '4503e72442837d4f93999c6345fff93a54dd87dc70438e6b337fb31bb865caa4'))}),
    knownBad={'nav_top_app': dict(bad=0x106f4b25, good=0x106f4b59, windowsDiffer=None, split=True),
              'ce_ext_106d3310': dict(bad=0x106f4b25, good=0x106f4b59, windowsDiffer=None, split=True),
              'native_label_create': dict(bad=0x104e7234, good=0x104e587d, windowsDiffer=None)},
    reviewedSplits={
     0x1057cfc5: {'new': 0x106f4b59, 'decoy': 0x1076e518, 'votes': '9/9 votes for 0x106f4b58', 'old': (56, '9be0af4e8be1f9fd3ae2f81dd4ac21ef78d346bc2df0f1afbc62bc58e4283f32'), 'newBytes': (22, 'baf4fbe59c5c921aae141bfaf4afdb32228345a3b798b00d049eb29414c53726'), 'reason': 'nav_top_app and ce_ext_106d3310 return the top app name (const char *); stock split the old function into A (top page, 0x106f4b24) and B (calls A, then the old name lookup, 0x106f4b58); every caller calls B; the decoy (strcmp with the launcher name, returns a bool) only repeats the old head'},
    }),
}
TEST_METHODS = ('bounded', 'tsig', 't2site', 'prefix', 'strpool', 'reviewed-split')
COPY_CALLEES = ('memcpy', 'memset', 'strcmp', 'strlen')
STRCMP_VENEER = 'ce_ext_10941968'

SIG_WINDOWS = ((0, 32), (0, 48), (0, 64), (-16, 16), (-32, 32), (-32, 0), (-64, 0), (0, 24), (0, 16))
SITE_WINDOWS = ((-16, 20), (-24, 28), (-32, 36), (-12, 16), (-8, 12), (0, 24), (-24, 4))


# ---------------------------------------------------------------- image and Thumb-2 decoding

class Image:
    def __init__(self, raw, name):
        self.raw, self.name, self.end = raw, name, FLASH + len(raw)
        self.tables = copy_tables(raw)
        self._branches = None
        self._words = None

    def has(self, va, n=1):
        return FLASH <= va and va + n <= self.end

    def h(self, va):
        return struct.unpack_from('<H', self.raw, va - FLASH)[0]

    def w(self, va):
        return struct.unpack_from('<I', self.raw, va - FLASH)[0]

    def file_of(self, runtime):
        """File offset of a runtime address in a copied region (copy region, .data), or of a flash address."""
        for s, e, d in self.tables:
            if d <= runtime < d + (e - s):
                return s - FLASH + runtime - d
        if self.has(runtime):
            return runtime - FLASH
        return None

    def region(self, dst):
        return next((s, e, d) for s, e, d in self.tables if d == dst)

    def code_end(self):
        """Literal votes skip the .data source (initialised data, not code)."""
        s, e, d = self.region(RAM_LO)
        return s, e

    def branch_sites(self):
        """target -> [site] for every even position that decodes as BL or B.W (T4)."""
        if self._branches is None:
            idx = defaultdict(list)
            raw = self.raw
            for m in re.finditer(rb'(?=[\x00-\xff][\xf0-\xf7][\x00-\xff][\x90-\xbf\xd0-\xff])', raw, re.S):
                i = m.start()
                if i & 1:
                    continue
                b = branch(self, FLASH + i)
                if b:
                    idx[b[1]].append(FLASH + i)
            self._branches = idx
        return self._branches

    def word_sites(self, value):
        if self._words is None:
            self._words = defaultdict(list)
            ds, de = self.code_end()
            for i in range(0, len(self.raw) - 3, 4):
                if ds - FLASH <= i < de - FLASH:
                    continue
                v = struct.unpack_from('<I', self.raw, i)[0]
                if RAM_LO <= v < RAM_HI or FLASH <= v < self.end:
                    self._words[v].append(FLASH + i)
        return self._words.get(value, [])


def copy_tables(raw):
    """(src, src_end, dst) word triples of the start-up copy table, from the first 4 KiB."""
    out = []
    end = FLASH + len(raw)
    for i in range(0, 0x1000 - 8, 4):
        s, e, d = struct.unpack_from('<3I', raw, i)
        if FLASH <= s < e <= end and e - s >= 0x1000 and not (FLASH <= d < end) and d % 4 == 0 and \
                (d < FLASH or RAM_LO <= d < 0x40000000):
            out.append((s, e, d))
    return out


def is32(hw):
    return (hw >> 11) in (0x1d, 0x1e, 0x1f)


def branch(img, pc):
    """('bl'|'b.w', even target) for a 32-bit BL or B.W (T4) at pc, else None."""
    if not img.has(pc, 4):
        return None
    h1, h2 = img.h(pc), img.h(pc + 2)
    if (h1 >> 11) != 0x1e:
        return None
    if (h2 & 0xd000) == 0xd000:
        kind = 'bl'
    elif (h2 & 0xd000) == 0x9000:
        kind = 'b.w'
    else:
        return None
    s = (h1 >> 10) & 1
    i1 = 1 - (((h2 >> 13) & 1) ^ s)
    i2 = 1 - (((h2 >> 11) & 1) ^ s)
    imm = (s << 24) | (i1 << 23) | (i2 << 22) | ((h1 & 0x3ff) << 12) | ((h2 & 0x7ff) << 1)
    if s:
        imm -= 1 << 25
    return kind, pc + 4 + imm


def literal_ref(img, pc):
    """(target, size, instruction length) for a pc-relative load at pc, else None."""
    if not img.has(pc, 2):
        return None
    h1 = img.h(pc)
    base = (pc + 4) & ~3
    if (h1 & 0xf800) == 0x4800:
        return base + (h1 & 0xff) * 4, 4, 2
    if not is32(h1) or not img.has(pc, 4):
        return None
    h2 = img.h(pc + 2)
    up = (h1 >> 7) & 1
    if (h1 & 0xff7f) == 0xf85f:                           # LDR.W (literal)
        imm = h2 & 0xfff
        return base + (imm if up else -imm), 4, 4
    if (h1 & 0xfe7f) == 0xe85f and (h1 & 0x0100):          # LDRD (literal), P=1
        imm = (h2 & 0xff) * 4
        return base + (imm if up else -imm), 8, 4
    if (h1 & 0xff3f) == 0xed1f and (h2 & 0x0e00) == 0x0a00:  # VLDR (literal)
        imm = (h2 & 0xff) * 4
        return base + (imm if up else -imm), (8 if h2 & 0x100 else 4), 4
    return None


def is_return(img, pc):
    """An unconditional return when not in an IT block: pop {..,pc}, bx lr, pop.w/ldm sp! with pc, ldr pc,[sp],#4."""
    h1 = img.h(pc)
    if (h1 & 0xff00) == 0xbd00 or h1 == 0x4770:
        return True
    if is32(h1) and img.has(pc, 4):
        h2 = img.h(pc + 2)
        return (h1 == 0xe8bd and h2 & 0x8000 != 0) or (h1 == 0xf85d and h2 == 0xfb04)
    return False


def fn_end(img, x, cap=0x200):
    """End of the bounded body from x: just after the first unconditional return outside an IT block, at most
    x + cap (and never past the image)."""
    pc, in_it = x, 0
    while pc < x + cap and img.has(pc, 2):
        h1 = img.h(pc)
        size = 4 if is32(h1) else 2
        if not img.has(pc, size):
            break
        if in_it:
            in_it -= 1
        elif (h1 & 0xff00) == 0xbf00 and h1 & 0xf:                 # IT: the next 4 - (trailing zeros of mask)
            mask = h1 & 0xf
            in_it = 4 - (mask & -mask).bit_length() + 1
        elif is_return(img, pc):
            return pc + size
        pc += size
    return min(pc, x + cap)


def t2_keep(h1, h2=None):
    """The T2 keep mask (little-endian bytes) of one instruction that is neither a BL/B.W nor a literal load: its
    immediate field or local branch offset cleared. None when the instruction has neither. h2 is None for a
    16-bit instruction."""
    if h2 is None:
        if (h1 & 0xe000) == 0x6000 or (h1 & 0xf000) == 0x8000:        # LDR/STR(B) imm5, LDRH/STRH imm5
            k = 0xf83f
        elif (h1 & 0xf000) == 0x9000:                                   # LDR/STR sp-relative imm8
            k = 0xff00
        elif (h1 & 0xe000) == 0x2000:                                   # MOVS/CMP/ADDS/SUBS imm8
            k = 0xff00
        elif (h1 & 0xfc00) == 0x1c00:                                   # ADDS/SUBS imm3
            k = 0xfe3f
        elif (h1 & 0xf000) == 0xa000:                                   # ADR, ADD rd,sp,#imm8
            k = 0xff00
        elif (h1 & 0xff00) == 0xb000:                                   # ADD/SUB sp,#imm7
            k = 0xff80
        elif h1 < 0x1800 and h1 & 0x07c0:                               # LSL/LSR/ASR #imm5
            k = 0xf83f
        elif (h1 & 0xf800) == 0xe000:                                   # B (local)
            k = 0xf800
        elif (h1 & 0xf000) == 0xd000 and (h1 & 0x0e00) != 0x0e00:       # B<cond> (local)
            k = 0xff00
        elif (h1 & 0xf500) == 0xb100:                                   # CBZ/CBNZ (local)
            k = 0xfd07
        else:
            return None
        return k.to_bytes(2, 'little')
    k1, k2 = 0xffff, 0xffff
    if (h1 & 0xfff0) in (0xf880, 0xf890, 0xf8a0, 0xf8b0, 0xf8c0, 0xf8d0) and (h1 & 0xf) != 0xf:
        k2 = 0xf000                                                     # LDR/STR(B/H).W imm12
    elif (h1 & 0xff00) == 0xf800 and (h1 & 0xf0) <= 0x50 and (h1 & 0xf) != 0xf and h2 & 0x0800:
        k2 = 0xff00                                                     # LDR/STR(B/H) imm8 (T4 forms)
    elif (h1 & 0xfe40) == 0xe840 and (h1 & 0xf) != 0xf:
        k2 = 0xff00                                                     # LDRD/STRD imm8
    elif (h1 & 0xfa00) == 0xf000 and not h2 & 0x8000:
        k1, k2 = 0xfbff, 0x8f00                                         # modified immediate
    elif (h1 & 0xfb50) == 0xf240 and not h2 & 0x8000:
        k1, k2 = 0xfbf0, 0x8f00                                         # MOVW/MOVT
    elif (h1 & 0xfb00) == 0xf200 and not h2 & 0x8000:
        k1, k2 = 0xfbff, 0x8f00                                         # ADDW/SUBW (and ADR.W)
    elif (h1 & 0xff30) == 0xed10 and (h2 & 0x0e00) == 0x0a00:
        k2 = 0xff00                                                     # VLDR
    elif (h1 & 0xffb0) == 0xeeb0 and (h2 & 0x0ef0) == 0x0a00:
        k1, k2 = 0xfff0, 0xfff0                                         # VMOV.F32 #imm
    elif (h1 & 0xf800) == 0xf000 and (h2 & 0xd000) == 0x8000 and ((h1 >> 6) & 0xe) != 0xe:
        k1, k2 = 0xfbc0, 0xd000                                         # B<cond>.W (local): S, imm6, J1, J2, imm11
    else:
        return None
    return k1.to_bytes(2, 'little') + k2.to_bytes(2, 'little')


def masked_window(img, start, end, t2=False):
    """(bytes, keep masks, edges[(offset, kind, target)], loads[offset]) for [start, end) decoded from start.
    t2=True also applies the T2 mask (see the methods above)."""
    return walk_window(img, start, end, t2)[:4]


def walk_window(img, start, end, t2=False):
    """masked_window, plus the address where the instruction walk stopped (end itself when it lands there)."""
    lits = set()
    for q in range(max(FLASH, start - 4096) & ~1, start, 2):    # pools after the window start, loaded from before it
        r = literal_ref(img, q)
        if r and start - 8 < r[0] < end:
            lits.update(range(r[0], r[0] + r[1]))
    data = img.raw[start - FLASH:end - FLASH]
    keep = bytearray(b'\xff' * len(data))
    edges, loads = [], []
    pc = start
    while pc < end:
        if pc in lits:
            for k in range(pc, min(pc + 4, end)):
                keep[k - start] = 0
            pc += 4
            continue
        h1 = img.h(pc)
        r = literal_ref(img, pc)
        if r:
            lits.update(range(r[0], r[0] + r[1]))
            loads.append(pc - start)
            if r[2] == 2:
                keep[pc - start] = 0                               # imm8
            elif pc + 3 < end:
                keep[pc + 2 - start] = 0                           # imm12 / imm8 low byte
                keep[pc + 3 - start] &= 0xf0 if (h1 & 0xff7f) == 0xf85f else 0xff
            if t2 and (h1 & 0xff7f) == 0xf85f:
                keep[pc - start] &= 0x7f                           # T2: the U bit of LDR.W (literal)
        if is32(h1):
            b = branch(img, pc)
            if b:
                edges.append((pc - start, b[0], b[1]))
                keep[pc - start] = 0
                if pc + 1 < end:
                    keep[pc + 1 - start] &= 0xf8
                if pc + 2 < end:
                    keep[pc + 2 - start] = 0
                if pc + 3 < end:
                    keep[pc + 3 - start] &= 0xd0
            elif t2 and not r and img.has(pc, 4):
                m = t2_keep(h1, img.h(pc + 2))
                for k in range(4 if m else 0):
                    if pc + k < end:
                        keep[pc + k - start] &= m[k]
            pc += 4
        else:
            m = t2_keep(h1) if t2 and not r else None
            for k in range(2 if m else 0):
                if pc + k < end:
                    keep[pc + k - start] &= m[k]
            pc += 2
    for a in lits:
        if start <= a < end:
            keep[a - start] = 0
    return data, bytes(keep), edges, loads, pc


def search(img, data, keep):
    """Even positions in img where data matches under keep."""
    runs, i = [], 0
    while i < len(data):
        if keep[i] == 0xff:
            j = i
            while j < len(data) and keep[j] == 0xff:
                j += 1
            runs.append((j - i, i))
            i = j
        else:
            i += 1
    if not runs:
        return None
    length, off = max(runs)
    if length < 4 or sum(bin(k).count('1') for k in keep) < 8 * min(16, len(data) // 2):
        return None
    anchor = data[off:off + length]
    raw, hits, at = img.raw, [], -1
    while True:
        at = raw.find(anchor, at + 1)
        if at < 0:
            break
        p = at - off
        if p < 0 or p & 1 or p + len(data) > len(raw):
            continue
        if all(((raw[p + k] ^ data[k]) & keep[k]) == 0 for k in range(len(data)) if keep[k]):
            hits.append(FLASH + p)
    return hits


def pair(old, new, at, windows):
    """Resolve the even old address `at` in the new image by masked windows. Returns (new or None, report)."""
    tried, unique, multi = [], {}, []
    for before, after in windows:
        s, e = at + before, at + after
        if not old.has(s, e - s) or e - s < 8:
            continue
        data, keep, edges, loads = masked_window(old, s, e)
        hits = search(new, data, keep)
        if hits is None:
            tried.append((before, after, None))
            continue
        tried.append((before, after, len(hits)))
        if len(hits) == 1:
            unique[(before, after)] = (hits[0] - before, edges)
        elif hits:
            multi.append((set(h - before for h in hits), (before, after)))
    # Windows holding at least 16 bytes at or after the address describe the address itself; backward-only windows
    # describe the code before it, which may be a different body that moved separately (the tgr_intercept trap).
    fwd = {k: v for k, v in unique.items() if k[1] >= 16}
    back = {k: v for k, v in unique.items() if k[1] < 16}
    rep = {'windows': tried, 'unique': len(unique)}
    use = fwd or back
    answers = {v[0] for v in use.values()}
    if len(answers) != 1:
        rep['why'] = 'no unique window' if not answers else 'windows disagree: ' + ', '.join(hex(a) for a in sorted(answers))
        return None, rep
    answer = answers.pop()
    other = {v[0] for v in back.values()} - {answer} if fwd else set()
    if other:
        rep['note'] = 'the bytes before it match elsewhere (%s): it follows a different body' % ','.join(map(hex, other))
    rep['unique'] = len(use)
    rep['short'] = not any(a - b >= 32 for (b, a) in use)
    if not fwd:
        rep['note'] = 'backward windows only'
        rep['short'] = True
    if any(answer not in m for m, w in multi if w[1] >= 16):
        rep['why'] = 'a multi-hit window excludes ' + hex(answer)
        return None, rep
    rep['edges'] = []
    for (before, after), (_, edges) in use.items():
        for off, kind, tgt in edges:
            nb = branch(new, answer + before + off)
            if nb:
                rep['edges'].append((tgt, nb[1], at + before + off))
    return answer, rep



# ---------------------------------------------------------------- methods

class Deriver:
    def __init__(self, old, new):
        self.old, self.new = old, new
        self.edge_pool = defaultdict(set)      # old even target -> {new even target}
        self.load_pairs = {}                   # old load site -> new load site
        self.cache = {}
        self.site_cache = {}
        self.tsig_cache = {}

    def sig(self, at):
        if at not in self.cache:
            ans, rep = pair(self.old, self.new, at, SIG_WINDOWS)
            for o, n, _ in rep.get('edges', []):
                self.edge_pool[o].add(n)
            self.cache[at] = (ans, rep)
        return self.cache[at]

    def site(self, at):
        if at not in self.site_cache:                      # the pairing and its pooled edges do not change
            ans, rep = pair(self.old, self.new, at, SITE_WINDOWS)
            for o, n, _ in rep.get('edges', []):
                self.edge_pool[o].add(n)
            self.site_cache[at] = ans
        return self.site_cache[at]

    def callers(self, target, limit=12):
        votes = Counter()
        for s in self.old.branch_sites().get(target, [])[:limit]:
            ns = self.site(s)
            if ns is None:
                continue
            b = branch(self.new, ns)
            if b:
                votes[b[1]] += 1
        return votes

    def t2_callers(self, target, limit=12):
        """t2site: votes from the caller sites (of the same first `limit`) that no site window pairs, each paired by
        the same windows under the T2 mask. Returns (votes, number of such sites)."""
        votes, tried = Counter(), 0
        for s in self.old.branch_sites().get(target, [])[:limit]:
            if self.site(s) is not None:
                continue
            tried += 1
            answers = set()
            for before, after in SITE_WINDOWS:
                a, e = s + before, s + after
                if not self.old.has(a, e - a) or e - a < 8:
                    continue
                data, keep, _, _ = masked_window(self.old, a, e, t2=True)
                if search(self.old, data, keep) != [a]:
                    continue
                hits = search(self.new, data, keep)
                if hits and len(hits) == 1:
                    answers.add(hits[0] - before)
            if len(answers) == 1:
                b = branch(self.new, answers.pop())
                if b:
                    votes[b[1]] += 1
        return votes, tried

    def tsig(self, at):
        """tsig: the T2-masked bounded body, one old hit (at) and one new hit. Returns (answer or None, report)."""
        if at not in self.tsig_cache:
            end = fn_end(self.old, at)
            data, keep, edges, _ = masked_window(self.old, at, end, t2=True)
            ho, hn = search(self.old, data, keep), search(self.new, data, keep)
            rep = {'unique': 1, 'short': True, 'edges': [], 'note': 'tsig'}
            if ho is None:
                ans, rep['text'] = None, 'none (the %d-byte T2 body keeps too few bits)' % (end - at)
            elif ho != [at] or len(hn) != 1:
                ans, rep['text'] = None, 'none (%d-byte T2 body: %d old hit(s)%s, %d new hit(s))' % (
                    end - at, len(ho), '' if at in ho else ', not at the address', len(hn))
            else:
                ans = hn[0]
                for off, kind, tgt in edges:
                    nb = branch(self.new, ans + off)
                    if nb:
                        rep['edges'].append((tgt, nb[1], at + off))
                        self.edge_pool[tgt].add(nb[1])
                rep['text'] = '%d-byte T2 body, old 1 hit (here), new 1 hit: %s (weak)' % (end - at, hex(ans))
            self.tsig_cache[at] = (ans, rep)
        return self.tsig_cache[at]

    def bounded(self, at, x_sig, y_call):
        """bounded: (answer or None, report) for a row whose sig names x_sig and whose callers name y_call."""
        old, new = self.old, self.new
        end = fn_end(old, at)
        lim = end - at
        deciding = [w for w in SIG_WINDOWS if pair(old, new, at, (w,))[0] == x_sig]
        if not deciding:
            return None, 'none (no signature window alone names %s)' % hex(x_sig)
        inside = [w for w in deciding if w[1] <= lim]
        if inside:
            return None, 'none (window(s) %s inside the %d-byte function name %s)' % (inside, lim, hex(x_sig))
        clipped = []
        for before, after in SIG_WINDOWS:
            w = (before, min(after, lim))
            if w[1] - w[0] >= 8 and w not in clipped:
                clipped.append(w)
        ans, rep = pair(old, new, at, tuple(clipped))
        text = 'window(s) %s naming %s end past the function end at +%d; clipped sig: %s' % (
            deciding, hex(x_sig), lim, hex(ans) if ans is not None else 'none (%s)' % rep.get('why'))
        if ans is not None and ans != y_call:
            return None, 'none (%s, not the callers\' %s)' % (text, hex(y_call))
        data, keep, _, _ = masked_window(old, at, end, t2=True)
        same = new.has(y_call, len(data)) and all(
            ((new.raw[y_call - FLASH + k] ^ data[k]) & keep[k]) == 0 for k in range(len(data)))
        n_end = fn_end(new, y_call) - y_call if new.has(y_call, 2) else None
        if not same or n_end != lim:
            return None, 'none (%s; the %d-byte body is %s at %s, bounded length there %s)' % (
                text, lim, 'T2-equal' if same else 'not T2-equal', hex(y_call), n_end)
        # how much the T2-equal check alone says: the number of new places it matches with that bounded length
        # (a short body matches in many places; the answer then rests on the caller votes)
        # counted directly, since search() declines short or sparse bodies, which are exactly the weak case
        run, off, i = 0, 0, 0
        while i < len(data):
            j = i
            while j < len(data) and keep[j] == 0xff:
                j += 1
            if j - i > run:
                run, off = j - i, i
            i = j + 1
        places, at = 0, -1
        while run:
            at = new.raw.find(data[off:off + run], at + 1)
            if at < 0:
                break
            p = at - off
            if p >= 0 and not p & 1 and p + len(data) <= len(new.raw) and all(
                    ((new.raw[p + k] ^ data[k]) & keep[k]) == 0 for k in range(len(data))) and \
                    fn_end(new, FLASH + p) - (FLASH + p) == lim:
                places += 1
        return y_call, '%s; the %d-byte body is T2-equal at %s with the same bounded length (%s): %s' % (
            text, lim, hex(y_call), '%d place(s) in the new image match it so' % places if run else
            'no unmasked byte to count the places by', hex(y_call))

    def load_sites(self, lit):
        """Old pc-relative loads that read the literal at `lit`."""
        out = []
        for q in range(max(FLASH, lit - 4100) & ~1, lit, 2):
            r = literal_ref(self.old, q)
            if r and r[0] <= lit < r[0] + r[1] and (r[0] == lit or r[1] == 8):
                out.append((q, lit - r[0]))
        return out

    def lit_votes(self, value):
        votes = Counter()
        for lit in self.old.word_sites(value):
            for q, sub in self.load_sites(lit):
                nq = self.load_pairs.get(q) or self.site(q)
                if nq is None:
                    continue
                self.load_pairs[q] = nq
                r = literal_ref(self.new, nq)
                if r and self.new.has(r[0] + sub, 4):
                    votes[self.new.w(r[0] + sub)] += 1
        return votes

    def field(self, value, base_old, base_new):
        """ldr.w/str.w [Rn,#off] after a load of the base literal, paired; returns (old sites, agreeing new sites)."""
        off = value - base_old
        n_old = n_agree = 0
        for lit in self.old.word_sites(base_old):
            for q, sub in self.load_sites(lit):
                if sub:
                    continue
                rd = (self.old.h(q) >> 8) & 7 if (self.old.h(q) & 0xf800) == 0x4800 else self.old.h(q + 2) >> 12
                hit = self._field_use(self.old, q, rd, off)
                if hit is None:
                    continue
                n_old += 1
                nq = self.load_pairs.get(q) or self.site(q)
                if nq is None:
                    continue
                r = literal_ref(self.new, nq)
                if not r or self.new.w(r[0]) != base_new:
                    continue
                rd2 = (self.new.h(nq) >> 8) & 7 if (self.new.h(nq) & 0xf800) == 0x4800 else self.new.h(nq + 2) >> 12
                if self._field_use(self.new, nq, rd2, off) == hit:
                    n_agree += 1
        return n_old, n_agree

    @staticmethod
    def _field_use(img, q, rd, off):
        """Distance (in bytes) from q to the first ldr.w/str.w Rt,[rd,#off] within 40 bytes, else None."""
        pc = q + (2 if (img.h(q) & 0xf800) == 0x4800 else 4)
        while pc < q + 40 and img.has(pc, 4):
            h1 = img.h(pc)
            if is32(h1):
                h2 = img.h(pc + 2)
                if (h1 & 0xffe0) in (0xf8d0, 0xf8c0) and (h1 & 0xf) == rd and (h2 & 0xfff) == off:
                    return pc - q
                pc += 4
            else:
                pc += 2
        return None


def cstring(img, runtime):
    at = img.file_of(runtime)
    if at is None:
        return None
    end = img.raw.find(b'\0', at)
    return img.raw[at:end] if 0 <= end - at < 512 else None


def runtime_of(img, off):
    """Runtime address of a file offset: through the copy tables when it lies in a copied region, else flash."""
    for s, e, d in img.tables:
        if s - FLASH <= off < e - FLASH:
            return d + off - (s - FLASH)
    return FLASH + off


def digit_parts(s):
    """A string with its digit runs normalised: the parts between them."""
    return tuple(re.split(rb'[0-9]+', s))


def nul_matches(img, parts):
    """File offsets of the NUL-delimited strings of img that equal `parts` with any digit runs between them."""
    pat = b'(?<=\x00)' + b'[0-9]+'.join(re.escape(p) for p in parts) + b'(?=\x00)'
    return [m.start() for m in re.finditer(pat, img.raw)]


def loaded_strings(img, start):
    """(parts -> {string address}, parts -> instruction index of its first load) for the printable strings of at
    least 8 bytes that word loads in the bounded body from start read. The index counts whole instructions decoded
    from start (0 is the instruction at start)."""
    out, first = defaultdict(set), {}
    pc, end, i = start, fn_end(img, start), 0
    while pc < end:
        r = literal_ref(img, pc)
        if r and r[1] == 4 and img.has(r[0], 4):
            v = img.w(r[0])
            c = cstring(img, v) if img.file_of(v) is not None else None
            if c and len(c) >= 8 and all(32 <= ch < 127 for ch in c):
                out[digit_parts(c)].add(v)
                first.setdefault(digit_parts(c), i)
        pc += 4 if is32(img.h(pc)) else 2
        i += 1
    return out, first


# ---------------------------------------------------------------- trees

def hex_tokens(text):
    return re.findall(r'(?<![0-9A-Za-z_])0[xX][0-9a-fA-F]{6,8}(?![0-9A-Za-z_])', text)


def scanned(fw):
    for part in SCANNED:
        p = fw/part
        if not p.exists():
            continue
        for q in ([p] if p.is_file() else sorted(x for x in p.rglob('*') if x.is_file())):
            rel = q.relative_to(fw).as_posix()
            if rel == SELF or '__pycache__' in rel:
                continue
            try:
                yield rel, q.read_text()
            except UnicodeDecodeError:
                continue


LINK_SYMBOL = re.compile(r'^\s*(\w+)\s*=\s*(0x[0-9a-fA-F]+)\s*;', re.M)
MODULE_START = re.compile(r'^\s*\.\s*=\s*(0x[0-9a-fA-F]+)\s*;', re.M)
ABI_RANGE = re.compile(r'^\s*\((0x[0-9a-fA-F]+),(\d+),\'([0-9a-f]{64})\'\)', re.M)


def abi_listed(fw):
    """The ABI ranges as tests/stock_abi_test.py lists them (on the first base)."""
    return [(int(a, 16), int(n), h) for a, n, h in ABI_RANGE.findall((fw/'tests/stock_abi_test.py').read_text())]


def read_tree(fw, img, abi=None):
    """The stock-address universe of one tree, from its files alone (abi: the ranges on this tree's base, when the
    tree's stock_abi_test lists them on an earlier base)."""
    link = (fw/'link.ld').read_text()
    spec = json.loads((fw/'build-inputs.json').read_text())
    listed = abi_listed(fw)
    u = {'link': {m.group(1): int(m.group(2), 16) for m in LINK_SYMBOL.finditer(link)},
         'module': [int(x, 16) for x in MODULE_START.findall(link)],
         'moduleVA': int(spec['moduleVA'], 16),
         'edits': {e['role']: e for e in spec['edits']},
         'abi': listed if abi is None else abi,
         'tramp_bytes': {m.group(1): bytes(int(x, 0) for x in m.group(2).split(',')) for m in re.finditer(
             r'^stock_(\w+):\n\.byte ([^\n]+)\n', (fw/'trampolines.S').read_text(), re.M)},
         'sites': defaultdict(Counter)}          # value -> {file: count}
    abi_text = set(hex(a) for a, _, _ in listed + u['abi'])
    for rel, text in scanned(fw):
        for t in hex_tokens(text):
            v = int(t, 16)
            if t.lower() in NOT_STOCK:
                continue
            if rel == 'tests/stock_abi_test.py' and hex(v) in abi_text:
                continue
            if img.has(v) or RAM_LO <= v < RAM_HI:
                u['sites'][v][rel] += 1
    return u


def not_stock_seen(fw, img):
    seen = Counter()
    for rel, text in scanned(fw):
        for t in hex_tokens(text):
            v = int(t, 16)
            if (img.has(v) or RAM_LO <= v < RAM_HI) and t.lower() in NOT_STOCK:
                seen[t.lower()] += 1
    return seen


# ---------------------------------------------------------------- derivation

def derive(old_fw, old, new, abi=None, string_changes=None, disabled=frozenset(), added_code=None, added_ram=None,
           added_edits=None):
    """Rows: one per universe address, each with the derived new value and the evidence. `disabled`: names from
    TEST_METHODS that are not applied (acceptance only)."""
    d = Deriver(old, new)
    u = read_tree(old_fw, old, abi)
    for name, value in (added_code or {}).items():
        assert name not in u['link'] and value & 1 and old.has(value & ~1), 'addedCode %s' % name
        u['link'][name] = value
    for name, value in (added_ram or {}).items():
        assert name not in u['link'] and RAM_LO <= value < RAM_HI and not value % 4, 'addedRam %s' % name
        u['link'][name] = value
    for role, (value, before, *_) in (added_edits or {}).items():
        name = role.removeprefix('Entry trampoline ')
        assert role.startswith('Entry trampoline ') and role not in u['edits'] and 'resume_' + name not in u['link'] and \
            not value & 1 and old.has(value, 4) and old.raw[value - FLASH:value - FLASH + 4].hex() == before, 'addedEdits %s' % role
        u['edits'][role] = {'role': role, 'offset': hex(value - FLASH), 'address': hex(value), 'before': before,
                            'kind': 'bw', 'pad': 0, 'added': True}
        u['link']['resume_' + name] = value + 5
    string_changes = string_changes or {}
    rows = []

    def code_row(kind, name, value):
        at = value & ~1
        row = {'kind': kind, 'name': name, 'old': value, 'new': None, 'methods': {}, 'problems': []}
        rows.append(row)
        if not old.has(at):
            # Copy region: same runtime address, identical function bytes in both images.
            fo, fn = old.file_of(at), new.file_of(at)
            if fo is None or fn is None:
                row['problems'].append('outside the image and every copied region')
                return row
            same = old.raw[fo:fo + 32] == new.raw[fn:fn + 32]
            row['methods']['copy'] = 'file 0x%x / 0x%x, 32 bytes %s' % (fo, fn, 'identical' if same else 'DIFFER')
            if same and fo == fn:
                row['new'] = value
            else:
                row['problems'].append('copy-region bytes or offset differ')
            return row
        ans, rep = d.sig(at)
        row['sigrep'] = rep
        if ans is not None:
            row['methods']['sig'] = 'unique in %d window(s)%s: %s' % (
                rep['unique'], ' (weak: shorter than 32 bytes or backward only)' if rep['short'] else '', hex(ans))
            if rep.get('note'):
                row['methods']['sig'] += ' [%s]' % rep['note']
        else:
            row['methods']['sig'] = 'none (%s)' % rep.get('why')
            if rep.get('why') == 'no unique window':
                if 'tsig' in disabled:
                    row['methods']['tsig'] = 'none (disabled)'
                else:
                    t_ans, t_rep = d.tsig(at)
                    row['methods']['tsig'] = t_rep['text']
                    if t_ans is not None:
                        ans, rep = t_ans, t_rep
                        row['sigrep'] = rep
        votes = d.callers(at)
        if votes:
            top, n = votes.most_common(1)[0]
            row['methods']['call'] = '%d/%d votes for %s' % (n, sum(votes.values()), hex(top))
            if n * 4 < sum(votes.values()) * 3:
                top = None
                row['methods']['call'] += ' (split)'
        else:
            top = None
        # t2site: the `call` text above stays the T1 count and exists only when there is a T1-paired vote; the
        # T2-paired votes are reported under `t2site` only and join the tally that decides
        extra, tried = (Counter(), 0) if 't2site' in disabled else d.t2_callers(at)
        if 't2site' in disabled and old.branch_sites().get(at):
            row['methods']['t2site'] = 'none (disabled)'
        if extra:
            tally = votes + extra
            t, n = tally.most_common(1)[0]
            row['methods']['t2site'] = '%d vote(s) from %d caller site(s) that only T2 windows pair (%s); call ' \
                'tally %d/%d votes for %s' % (sum(extra.values()), tried, ', '.join(
                    '%s: %d' % (hex(k), v) for k, v in sorted(extra.items())), n, sum(tally.values()), hex(t))
            top = t
            if n * 4 < sum(tally.values()) * 3:
                top = None
                row['methods']['t2site'] += ' (split)'
        cand = {x for x in (ans, top) if x is not None}
        if len(cand) > 1:
            row['problems'].append('sig %s and call %s disagree' % (hex(ans), hex(top)))
            if 'bounded' in disabled:
                row['methods']['bounded'] = 'none (disabled)'
            elif row['problems'] == ['sig %s and call %s disagree' % (hex(ans), hex(top))]:
                b_ans, row['methods']['bounded'] = d.bounded(at, ans, top)
                if b_ans is not None:
                    row['new'] = b_ans | (value & 1)
                    row['problems'] = []
                    row['short'] = False
        elif cand:
            row['new'] = cand.pop() | (value & 1)
            row['short'] = ans is not None and rep['short'] and top is None
        else:
            row['problems'].append('unresolved: ' + row['methods']['sig'])
        return row

    def ram_row(kind, name, v, sites):
        row = {'kind': kind, 'name': name, 'old': v, 'new': None, 'methods': {}, 'problems': []}
        if sites is not None:
            row['sites'] = dict(sites)
        rows.append(row)
        votes = d.lit_votes(v)
        if votes:
            top, n = votes.most_common(1)[0]
            total = sum(votes.values())
            row['methods']['lit'] = '%d/%d votes for %s' % (n, total, hex(top))
            if n * 4 >= total * 3:
                row['new'] = top
            else:
                row['problems'].append('literal votes split: ' + str({hex(a): b for a, b in votes.most_common(4)}))
        s_old = cstring(old, v) if old.file_of(v) is not None and v < old.region(RAM_LO)[2] + 0x400000 else None
        if s_old and len(s_old) >= 4 and all(32 <= c < 127 for c in s_old):
            row['string'] = s_old.decode()
            if row['new'] is not None:
                s_new = cstring(new, row['new'])
                ok = s_new == s_old
                change = string_changes.get(v)
                if not ok and change and s_new is not None:
                    a, b = change[0].encode(), change[1].encode()
                    if s_old.count(a) == 1 and s_new == s_old.replace(a, b):
                        row['methods']['str'] = '%r -> %r: the reviewed change %r -> %r' % (
                            s_old.decode()[:32], s_new.decode()[:32], change[0], change[1])
                        return row
                row['methods']['str'] = '%r %s' % (s_old.decode()[:32], 'same at new address' if ok else 'DIFFERS')
                if not ok:
                    row['problems'].append('string differs at new address')
        return row

    def strpool(row, c):
        """strpool for an unresolved code-literal value row whose lit votes all name c."""
        if 'strpool' in disabled:
            row['methods']['strpool'] = 'none (disabled)'
            return
        if not new.has(c & ~1):
            row['methods']['strpool'] = 'none (%s is not in the new image)' % hex(c)
            return
        (mine, i_old), (theirs, i_new) = loaded_strings(old, row['old'] & ~1), loaded_strings(new, c & ~1)
        good, outside, good_parts = [], [], []
        for parts, addrs in sorted(mine.items()):
            if len(addrs) != 1:
                continue
            a = next(iter(addrs))
            fo = old.file_of(a)
            o_hits, n_hits = nul_matches(old, parts), nul_matches(new, parts)
            if o_hits != [fo] or len(old.word_sites(a)) != 1 or len(n_hits) != 1:
                continue                           # not NUL-delimited and unique, or not held by one word
            b = runtime_of(new, n_hits[0])
            if len(new.word_sites(b)) != 1:
                continue
            text = cstring(old, a).decode()[:40]
            if theirs.get(parts) == {b}:
                good.append('%r %s -> %s' % (text, hex(a), hex(b)))
                good_parts.append(parts)
            else:
                outside.append('%r %s -> %s' % (text, hex(a), hex(b)))
        # c must be where the old start is, not an instruction before or after it: the qualifying string the old
        # body loads first is loaded first at the same instruction index from the start in both bodies
        lead = min(good_parts, key=lambda p: i_old[p]) if good_parts else None
        at_start = lead is not None and i_old[lead] == i_new.get(lead)
        row['methods']['strpool'] = '%d qualifying string(s) loaded in both bodies (%s -> %s)%s%s%s' % (
            len(good), hex(row['old']), hex(c), (': ' + '; '.join(good)) if good else '',
            ('; loaded outside the new body: ' + '; '.join(outside)) if outside else '',
            '; the first one is loaded at instruction %d of the old body and %s of the new one' % (
                i_old[lead], i_new.get(lead)) if lead is not None else '')
        if outside:
            row['problems'].append('strpool: %d qualifying string(s) whose new counterpart is loaded outside %s'
                                   % (len(outside), hex(c)))
        elif len(good) >= 2 and not at_start:
            row['problems'].append('strpool: the first qualifying string is loaded at instruction %d of the old '
                                   'body and %s of the body at %s' % (i_old[lead], i_new.get(lead), hex(c)))
        elif len(good) >= 2:
            row['new'] = c
            row['problems'] = []
        else:
            row['methods']['strpool'] = 'none (%s)' % row['methods']['strpool']

    for name, v in u['link'].items():
        if RAM_LO <= v < RAM_HI:
            ram_row('link', name, v, None)
        else:
            code_row('link', name, v)
    for role, e in u['edits'].items():
        r = code_row('edit', role, int(e['address'], 16))
        r['edit'] = e
    for a, n, h in u['abi']:
        r = code_row('abi', 'range %d bytes' % n, a)
        r['abi'] = (n, h)
        if not old.has(a, n) or hashlib.sha256(old.raw[a - FLASH:a - FLASH + n]).hexdigest() != h:
            r['problems'].append('the old image does not have the listed hash at this range')
    # module VA (struct)
    k = FLASH + len(old.raw) - u['moduleVA']
    row = {'kind': 'module', 'name': 'moduleVA', 'old': u['moduleVA'], 'new': None, 'methods': {}, 'problems': []}
    if u['module'] != [u['moduleVA']]:
        row['problems'].append('old link.ld module start != build-inputs moduleVA')
    if 0 < k <= 64 and old.raw[-k:] == new.raw[-k:]:
        row['new'] = FLASH + len(new.raw) - k
        row['methods']['struct'] = 'FLASH + AP bytes - %d (same %d-byte trailer in both images)' % (k, k)
    else:
        row['problems'].append('trailer differs or k=%d' % k)
    rows.append(row)
    # literal values found in the source files
    link_values = set(u['link'].values())
    pending = []
    for v, sites in sorted(u['sites'].items()):
        if old.has(v):
            r = code_row('value', 'code literal', v)
            votes = d.lit_votes(v)
            if votes:
                top, n = votes.most_common(1)[0]
                r['methods']['lit'] = '%d/%d votes for %s' % (n, sum(votes.values()), hex(top))
                if r['new'] is not None and top != r['new']:
                    r['problems'].append('lit %s disagrees with %s' % (hex(top), hex(r['new'])))
                if r['new'] is None and len(votes) == 1 and r['problems'] and \
                        all(p.startswith('unresolved') for p in r['problems']):
                    strpool(r, top)
            r['sites'] = dict(sites)
        else:
            pending.append((v, sites))
    for v, sites in pending:
        ram_row('value', 'ram/.data', v, sites)
    # field method for RAM values without literals, from resolved RAM bases nearby
    resolved = {r['old']: r['new'] for r in rows if r['kind'] in ('value', 'link') and r['new'] is not None and
                RAM_LO <= r['old'] < RAM_HI}
    for row in rows:
        if row['kind'] not in ('value', 'link') or row['new'] is not None or not (RAM_LO <= row['old'] < RAM_HI):
            continue
        bases = sorted((b for b in resolved if 0 < row['old'] - b < 0x400), key=lambda b: row['old'] - b)
        for b in bases:
            n_old, n_agree = d.field(row['old'], b, resolved[b])
            row['methods']['field'] = 'base %s+0x%x: %d old ldr/str sites, %d paired with the same offset on %s' % (
                hex(b), row['old'] - b, n_old, n_agree, hex(resolved[b]))
            if n_old and n_agree * 4 >= n_old * 3:
                row['new'] = resolved[b] + row['old'] - b
                row['problems'] = []
                break
        if row['new'] is None and not row['problems']:
            row['problems'].append('unresolved: no literal and no field evidence')
        elif row['new'] is None:
            row['problems'].append('unresolved')
    # pooled edge check over every universe code address
    derived = {r['old'] & ~1: r['new'] & ~1 for r in rows if r['new'] is not None and old.has(r['old'] & ~1)}
    for r in rows:
        if r['new'] is None or not old.has(r['old'] & ~1):
            continue
        seen = d.edge_pool.get(r['old'] & ~1, set())
        if seen:
            r['methods']['edge'] = '%d pooled edge(s) -> %s' % (len(seen), ','.join(hex(x) for x in sorted(seen)))
            if seen != {r['new'] & ~1}:
                r['problems'].append('edge pool disagrees')
    # a weak signature (only windows shorter than 32 bytes, or only backward windows) with no caller vote needs a
    # corroborating edge: a BL/B.W in the matched window whose old target is another universe code address and whose
    # new target is that address's derived value
    for r in rows:
        if not r.get('short'):
            continue
        good = [(o, n) for o, n, _ in r['sigrep'].get('edges', []) if o != r['old'] & ~1 and o in derived]
        if good and all(derived[o] == n for o, n in good):
            r['methods']['edge'] = (r['methods'].get('edge', '') + ' corroborates the short window: ' + ', '.join(
                '%s->%s' % (hex(o), hex(n)) for o, n in sorted(set(good)))).strip()
        else:
            r['problems'].append('weak signature without a corroborating edge or caller vote')
    prefix(rows, d, old, new, disabled)
    for r in rows:
        if r['new'] is not None and r['kind'] in ('link', 'value') and old.has(r['old']) and \
                (r['old'] & 1) != (r['new'] & 1):
            r['problems'].append('Thumb bit changed')
    return u, rows, d, derived


PREFIX_KINDS = ('link', 'edit', 'abi')


def prefix(rows, d, old, new, disabled):
    """prefix, for the link.ld, edit and ABI rows that are unresolved or weak (see the methods above)."""
    def base_ok(b):
        named = {k for k, v in b['methods'].items() if not v.startswith('none')}
        return resolved(b) and not named & {'prefix', 'strpool', 'reviewed-split'} and \
            named & {'sig', 'call', 't2site', 'edge'}
    at = defaultdict(list)
    for b in rows:
        if b['kind'] in PREFIX_KINDS:
            at[b['old'] & ~1].append(b)
    # rows prefix resolves are not bases: the eligible bases are fixed before the pass
    bases = {s: {b['new'] & ~1 for b in bs} for s, bs in at.items() if all(base_ok(b) for b in bs)}
    targets = sorted(old.branch_sites())
    for r in rows:
        if r['kind'] not in PREFIX_KINDS or resolved(r) or not old.has(r['old'] & ~1):
            continue
        x = r['old'] & ~1
        i = bisect.bisect_left(targets, x) - 1
        if i < 0 or x - targets[i] >= 0x400:
            continue
        s = targets[i]
        if 'prefix' in disabled:
            r['methods']['prefix'] = 'none (disabled)'
            continue
        if s not in bases or len(bases[s]) != 1:
            r['methods']['prefix'] = 'none (start %s is not a row resolved by sig, call, t2site or edge)' % hex(s)
            continue
        sn = next(iter(bases[s]))
        # x must lie inside s's bounded body in the old image, and s' + (x - s) inside s''s in the new one: a prefix
        # that runs past a return compares code of the next function, which stock may have moved or inserted
        o_end, n_end = fn_end(old, s), (fn_end(new, sn) if new.has(sn, 2) else sn)
        if not x < o_end or not sn + (x - s) < n_end:
            r['methods']['prefix'] = 'none (the address is not inside the bounded body from start %s (ends at %s) ' \
                'and from %s (ends at %s))' % (hex(s), hex(o_end), hex(sn), hex(n_end))
            continue
        data, keep, _, _, landed = walk_window(old, s, x, t2=True)
        if landed != x:
            r['methods']['prefix'] = 'none (decoding from start %s does not land on the address)' % hex(s)
            continue
        if not new.has(sn, len(data)) or any((new.raw[sn - FLASH + k] ^ data[k]) & keep[k] for k in range(len(data))):
            r['methods']['prefix'] = 'none (the %d-byte T2 prefix from start %s differs at %s)' % (
                x - s, hex(s), hex(sn))
            continue
        ans = sn + (x - s)
        r['methods']['prefix'] = 'start %s -> %s (%s), %d-byte T2 prefix equal: %s' % (
            hex(s), hex(sn), ', '.join(b['name'] for b in at[s]), x - s, hex(ans))
        if r['new'] is None:
            if r['problems'] and all(p.startswith('unresolved') or p.startswith('weak') for p in r['problems']):
                r['new'] = ans | (r['old'] & 1)
                r['problems'] = []
                seen = d.edge_pool.get(x, set())       # the pooled edge check, as for every other resolved row
                if seen:
                    r['methods']['edge'] = '%d pooled edge(s) -> %s' % (
                        len(seen), ','.join(hex(e) for e in sorted(seen)))
                    if seen != {ans}:
                        r['problems'].append('edge pool disagrees')
        elif (r['new'] & ~1) != ans:
            r['problems'].append('prefix %s disagrees' % hex(ans))
        else:
            r['problems'] = [p for p in r['problems'] if not p.startswith('weak')]


# ---------------------------------------------------------------- comparisons

NEW_TREE = {'pruneLink': set(), 'valueToLink': {}}   # set from the pair's newTreeChanges in check()


def compare_tree(old_u, rows, new_fw, new_img):
    """Problems: the new tree against the derived values."""
    out = []
    nu = read_tree(new_fw, new_img)
    prune, to_link = NEW_TREE['pruneLink'], NEW_TREE['valueToLink']
    by = {(r['kind'], r['name'], r['old']): r for r in rows}
    for r in rows:
        if r['new'] is None:
            continue
        if r['kind'] == 'link' and r['name'] in prune:
            if r['name'] in nu['link']:
                out.append('link.ld %s is pruned (newTreeChanges) but still defined' % r['name'])
            continue
        if r['kind'] == 'value' and r['old'] in to_link:
            sym = to_link[r['old']]
            if nu['link'].get(sym) != r['new']:
                out.append('link.ld %s = %s, derived %s (value %s turned into a link.ld symbol)' % (
                    sym, hex(nu['link'].get(sym) or 0), hex(r['new']), hex(r['old'])))
            for v in (r['new'], r['old']):
                if v in nu['sites']:
                    out.append('value %s is a link.ld symbol now, but the tree still writes it: %s' % (hex(v), dict(nu['sites'][v])))
            continue
        if r['kind'] == 'link':
            got = nu['link'].get(r['name'])
            if got != r['new']:
                out.append('link.ld %s = %s, derived %s' % (r['name'], hex(got or 0), hex(r['new'])))
        elif r['kind'] == 'edit':
            e = nu['edits'].get(r['name'])
            if e is None:
                out.append('edit %r missing' % r['name'])
                continue
            want_off = hex(r['new'] - FLASH)
            if int(e['address'], 16) != r['new'] or int(e['offset'], 16) != r['new'] - FLASH:
                out.append('edit %r address %s offset %s, derived %s / %s' % (
                    r['name'], e['address'], e['offset'], hex(r['new']), want_off))
            before = bytes.fromhex(e['before'])
            actual = new_img.raw[r['new'] - FLASH:r['new'] - FLASH + len(before)]
            if actual != before:
                out.append('edit %r before %s, new image has %s' % (r['name'], e['before'], actual.hex()))
            if e['role'].startswith('Entry trampoline '):
                tb = nu['tramp_bytes'].get(e['role'].removeprefix('Entry trampoline '))
                if tb != before:
                    out.append('trampoline prologue %r != before' % e['role'])
            old_e = r['edit']
            if old_e['kind'] != e['kind'] or not old_e.get('added') and old_e.get('after') is None and e.get('after') is not None:
                out.append('edit %r kind changed' % r['name'])
        elif r['kind'] == 'module':
            if nu['moduleVA'] != r['new'] or nu['module'] != [r['new']]:
                out.append('moduleVA %s / link.ld %s, derived %s' % (hex(nu['moduleVA']), nu['module'], hex(r['new'])))
        elif r['kind'] == 'value':
            new_sites = nu['sites'].get(r['new'], Counter())
            for f, c in r['sites'].items():
                if new_sites.get(f, 0) != c:
                    out.append('%s: %d x %s, old tree had %d x %s' % (f, new_sites.get(f, 0), hex(r['new']), c,
                                                                      hex(r['old'])))
            if r['new'] != r['old'] and r['old'] in nu['sites']:
                out.append('old value %s still in %s' % (hex(r['old']), dict(nu['sites'][r['old']])))
    for f in sorted(set(nu['sites']) - {r['new'] for r in rows if r['new'] is not None}):
        out.append('new tree has a stock-range token %s no old address maps to (%s)' % (hex(f), dict(nu['sites'][f])))
    return out


def pool_context_check(row, old, new):
    """A RAM address with no old-tree row: every literal word of the new address in the new image sits in a pool whose RAM
    neighbours (within 12 words) are, shifted by the row's delta, the neighbours of one literal of the old address in the
    old image; and the old address has no other pool context. Returns problems."""
    o, n = int(row['old'], 16), int(row['new'], 16)
    delta = n - o
    def pools(img, value):
        out = []
        for i in range(0, len(img.raw) - 3, 4):
            if struct.unpack_from('<I', img.raw, i)[0] == value:
                lo, hi = max(0, i - 48), min(len(img.raw) - 3, i + 52)
                out.append(frozenset(w for w in struct.unpack_from('<%dI' % ((hi - lo) // 4), img.raw, lo)
                                     if 0x19000000 <= w < RAM_HI and w != value))
        return out
    new_pools, old_pools = pools(new, n), pools(old, o)
    if not new_pools or not old_pools:
        return ['%s: no literal of %s in the new image or of %s in the old one' % (row['symbol'], hex(n), hex(o))]
    bad = [] if len(new_pools) == len(old_pools) else ['%s: %d literals in the new image, %d in the old' % (
        row['symbol'], len(new_pools), len(old_pools))]
    for np_ in new_pools:
        shifted = {w - delta for w in np_ if (w - delta) >= RAM_LO}
        if not any(len(shifted & op) >= min(3, len(np_)) for op in old_pools):
            bad.append('%s: new pool at literal has no old counterpart shifted by %s' % (row['symbol'], hex(delta)))
    return bad


def compare_table(rows, table, new_img=None, added=frozenset()):
    out = []
    checked = 0
    mine = {(r['kind'], r['name'] if r['kind'] in ('link', 'edit') else r['old']) for r in rows}
    prune, to_link = NEW_TREE['pruneLink'], NEW_TREE['valueToLink']
    mine |= {('link', s) for v, s in to_link.items() if ('value', v) in mine}
    for key in ([('link', r['symbol']) for r in table['linkld']] + [('edit', r['role']) for r in table['edits']] +
                [('abi', int(r['old'], 16)) for r in table['stockAbiRanges']] +
                [('value', int(v['old'], 16)) for v in table['values']]):
        if key[0] == 'link' and key[1] in added:
            continue
        if key not in mine and not (key[0] == 'abi' and any(r['kind'] == 'abi' and r['old'] == key[1] for r in rows)):
            out.append('table row %s %s is not an address of the old tree' % key)
    tl = {r['symbol']: r for r in table['linkld']}
    te = {r['role']: r for r in table['edits']}
    tv = {int(v['old'], 16): v for v in table['values']}
    ta = {(int(r['old'], 16), r['bytes']): r for r in table['stockAbiRanges']}
    for r in rows:
        if r['new'] is None:
            continue
        if r['kind'] == 'link' and r['name'] in prune:
            checked += 1
            if r['name'] in tl:
                out.append('table has a link.ld row for pruned %s' % r['name'])
            continue
        if r['kind'] == 'value' and r['old'] in to_link:
            checked += 1
            t = tl.get(to_link[r['old']])
            if r['old'] in tv:
                out.append('table still has a value row for %s, now link.ld %s' % (hex(r['old']), to_link[r['old']]))
            if not t or int(t['old'], 16) != r['old'] or int(t['new'], 16) != r['new']:
                out.append('table link %s is not %s -> %s' % (to_link[r['old']], hex(r['old']), hex(r['new'])))
            continue
        if r['kind'] == 'link':
            t = tl.get(r['name'])
            if not t:
                out.append('table has no link.ld row for ' + r['name'])
                continue
            checked += 1
            if int(t['old'], 16) != r['old'] or int(t['new'], 16) != r['new']:
                out.append('table link %s %s -> %s, derived %s -> %s' % (r['name'], t['old'], t['new'], hex(r['old']),
                                                                         hex(r['new'])))
        elif r['kind'] == 'edit':
            t = te.get(r['name'])
            if not t:
                out.append('table has no edit row ' + r['name'])
                continue
            checked += 1
            if (int(t['oldAddress'], 16), int(t['newAddress'], 16), int(t['newOffset'], 16)) != \
                    (r['old'], r['new'], r['new'] - FLASH):
                out.append('table edit %r %s -> %s, derived %s' % (r['name'], t['oldAddress'], t['newAddress'],
                                                                  hex(r['new'])))
            if t['oldBefore'] != r['edit']['before']:
                out.append('table edit %r oldBefore %s, old tree %s' % (r['name'], t['oldBefore'], r['edit']['before']))
            if new_img is not None:
                n = len(t['newBefore']) // 2
                got = new_img.raw[r['new'] - FLASH:r['new'] - FLASH + n].hex()
                if got != t['newBefore']:
                    out.append('table edit %r newBefore %s, new image %s' % (r['name'], t['newBefore'], got))
        elif r['kind'] == 'abi':
            t = ta.get((r['old'], r['abi'][0]))
            if not t:
                out.append('table has no ABI range %s' % hex(r['old']))
                continue
            checked += 1
            if int(t['new'], 16) != r['new']:
                out.append('table ABI range %s -> %s, derived %s' % (t['old'], t['new'], hex(r['new'])))
            if t['oldSHA256'] != r['abi'][1]:
                out.append('table ABI range %s old hash' % t['old'])
            r['abi_new_sha'] = t['newSHA256']
        elif r['kind'] == 'module':
            checked += 1
            if int(table['moduleVA']['new'], 16) != r['new'] or int(table['moduleVA']['old'], 16) != r['old']:
                out.append('table moduleVA %s, derived %s' % (table['moduleVA']['new'], hex(r['new'])))
        elif r['kind'] == 'value':
            t = tv.get(r['old'])
            if not t:
                out.append('table has no value row for %s (old tree sites %s; derived %s)' % (
                    hex(r['old']), r['sites'], hex(r['new'])))
                continue
            checked += 1
            if int(t['new'], 16) != r['new']:
                out.append('table value %s %s -> %s, derived %s' % (t['name'], t['old'], t['new'], hex(r['new'])))
            if dict(t['sites']) != r['sites']:
                out.append('table value %s sites %s, old tree %s' % (t['name'], t['sites'], r['sites']))
    return out, checked


# ---------------------------------------------------------------- main

def load_ap(path, pinned):
    """nuttx_ap.bin of a stock ZIP; its SHA-256 must be the pair's pinned AP hash."""
    if not Path(path).is_file():
        raise SystemExit('stock ZIP not found: %s' % path)
    with zipfile.ZipFile(path) as z:
        raw = z.read('nuttx_ap.bin')
    got = hashlib.sha256(raw).hexdigest()
    if got != pinned:
        raise SystemExit('%s: nuttx_ap.bin sha256 %s, the pair pins %s' % (path, got, pinned))
    return raw


def export_old(dest, cfg):
    blob = subprocess.run(['git', '-C', str(ROOT), 'archive', cfg['oldTag'], 'firmware', cfg['oldStock']],
                          check=True, capture_output=True).stdout
    with tarfile.open(fileobj=io.BytesIO(blob)) as t:
        t.extractall(dest, filter='data')
    return Path(dest)


def fw_dir(p):
    p = Path(p)
    return p/'firmware' if (p/'firmware'/'link.ld').exists() else p


def pick_pair(text, new_fw):
    """--pair FROM:TO, else the last pair whose table exists in the new tree."""
    if text:
        key = tuple(text.split(':'))
        if key not in PAIRS:
            raise SystemExit('--pair %s is not one of %s' % (text, ', '.join('%s:%s' % k for k in PAIRS)))
        return key
    have = [k for k, cfg in PAIRS.items() if (new_fw/cfg['table']).exists()]
    if not have:
        raise SystemExit('no pair table in %s/baseline: pass --pair' % new_fw)
    return have[-1]


def new_stock_path(cfg):
    kind, rel = cfg['newStock']
    if kind == 'repo':
        return ROOT/rel
    assert kind == 'inputs', cfg['newStock']
    inputs = os.environ.get('TURBO_INPUTS')
    if not inputs:
        raise SystemExit('TURBO_INPUTS is not set: export TURBO_INPUTS or pass --stock-new (needed for %s)' % rel)
    return Path(inputs)/rel


def old_abi(old_fw, key):
    """The ABI ranges on the pair's old base. The old tree's stock_abi_test lists them on the first base; for a later
    pair they are walked through the frozen earlier tables in the old tree (never the table of the pair under test),
    each one's old column equal to the previous result. None for the first pair (the listed ranges as they are)."""
    keys = list(PAIRS)
    if key == keys[0]:
        return None
    ranges, at = abi_listed(old_fw), keys[0][0]
    for k in keys[:keys.index(key)]:
        t = json.loads((old_fw/PAIRS[k]['table']).read_text())
        assert (t['from'], t['to']) == k and k[0] == at, 'old tree table %s is not the pair %s:%s' % (
            PAIRS[k]['table'], *k)
        rs = {(int(r['old'], 16), r['bytes'], r['oldSHA256']): r for r in t['stockAbiRanges']}
        assert sorted(rs) == sorted(ranges), 'old tree table %s: ABI old column is not the previous ranges' % (
            PAIRS[k]['table'])
        ranges, at = [(int(rs[x]['new'], 16), rs[x]['bytes'], rs[x]['newSHA256']) for x in ranges], k[1]
    assert at == key[0], 'no table chain to %s in the old tree' % key[0]
    return ranges


def stack_call(img, q):
    """('bl', target) of the first BL within 8 instructions after the 16-bit ldr rt,[pc,#] at q, when rt is stored to the
    stack (str rt,[sp,#i]; str.w rt,[sp,#i]; strd with rt) before it; else None."""
    rt, pc, stored = (img.h(q) >> 8) & 7, q + 2, False
    for _ in range(8):
        if not img.has(pc, 4):
            return None
        hw = img.h(pc)
        if is32(hw):
            b, h2 = branch(img, pc), img.h(pc + 2)
            if b:
                return b if stored and b[0] == 'bl' else None
            stored |= (hw == 0xe9cd and rt in (h2 >> 12, (h2 >> 8) & 0xf)) or (hw == 0xf8cd and h2 >> 12 == rt)
            pc += 4
        else:
            stored |= hw >> 11 == 0b10010 and (hw >> 8) & 7 == rt
            pc += 2
    return None


def near_pair(d, old, q):
    """The new address of old site q from the nearest neighbour within 8 bytes that site() pairs, when the bytes from the
    neighbour to q (inclusive of q's halfword) are equal in both images and every pairing neighbour agrees; else None."""
    answers = set()
    for k in (-2, 2, -4, 4, -6, 6, -8, 8):
        n = d.site(q + k)
        if n is None:
            continue
        lo, hi = min(0, k), max(0, k) + 2
        if not old.has(q + lo, hi - lo) or not d.new.has(n - k + lo, hi - lo) or \
                old.raw[q + lo - FLASH:q + hi - FLASH] != d.new.raw[n - k + lo - FLASH:n - k + hi - FLASH]:
            return None
        answers.add(n - k)
    return answers.pop() if len(answers) == 1 else None


def itcm_veneer(img, at):
    """The Thumb ITCM address of a flash veneer `ldr.w pc,[pc,#-0]; .word target` at at, else None."""
    if not img.has(at, 8) or (img.h(at), img.h(at + 2)) != (0xf85f, 0xf000):
        return None
    word = img.w(at + 4)
    return word if word & 1 and word < FLASH else None


def added_entry(added_code, rows, d, old, added_ram=None, added_edits=None):
    """addedCode symbols and addedEdits sites have no old-tree row behind them, so each one's old value must be shown to be
    a function start: an old BL/B.W target with at least one paired caller (T1 or T2) naming the derived value. An
    addedRam symbol must be derived by at least two literal votes. Runs after every pass that can resolve a row, so
    nothing clears the problem it adds."""
    for name, value in (added_ram or {}).items():
        found = [r for r in rows if r['kind'] == 'link' and r['name'] == name]
        assert len(found) == 1, 'addedRam %s: %d link rows' % (name, len(found))
        r = found[0]
        votes = d.lit_votes(value)
        if r['new'] is None or sum(votes.values()) < 2 or votes.most_common(1)[0][0] != r['new']:
            r['problems'].append('addedRam: fewer than two literal votes name the derived value (%s)' % (
                ', '.join('%s: %d' % (hex(k), n) for k, n in votes.items()) or 'no literal vote'))
    for role, (value, _, *proof) in (added_edits or {}).items():
        if not proof or proof[0] != 'pointer':
            continue
        arg = proof[1]
        found = [r for r in rows if r['kind'] == 'edit' and r['name'] == role]
        assert len(found) == 1, 'added edit %s: %d rows' % (role, len(found))
        r, why, ok = found[0], [], 0
        if arg == 'stack':
            # the pointer's load sits in a short ns-bind body that stock has twice, so its own windows hit both copies;
            # a neighbour within 8 bytes that pairs uniquely, with the bytes between equal in both images, pairs it
            for lit in old.word_sites(value | 1):
                for q, sub in d.load_sites(lit):
                    if not sub and q not in d.load_pairs and d.site(q) is None:
                        nq = near_pair(d, old, q)
                        if nq is not None:
                            d.load_pairs[q] = nq
        votes = d.lit_votes(value | 1)
        if r['new'] is None and r['problems'] and all(x.startswith('unresolved') for x in r['problems']) and len(votes) == 1:
            # a stock rewrite left no signature: the one stored pointer (checked below to reach the slot setter) decides,
            # and the row's resume symbol is then this edit + 5 (it has no other evidence either)
            r['new'], r['problems'] = next(iter(votes)) & ~1, []
            r['methods']['lit'] = 'pointer vote %s decides (no signature: stock rewrote the function)' % hex(r['new'] | 1)
            resume = [x for x in rows if x['kind'] == 'link' and x['name'] == 'resume_' + role.removeprefix('Entry trampoline ')]
            if len(resume) == 1 and resume[0]['new'] is None and all(x.startswith('unresolved') for x in resume[0]['problems']):
                resume[0]['new'], resume[0]['problems'] = r['new'] + 5, []
                resume[0]['methods']['resume'] = 'its pointer-decided edit + 5'
        if r['new'] is None or not votes or votes.most_common(1)[0][0] != r['new'] | 1 or len(votes) != 1:
            why.append('literal votes for %s are %s' % (hex(value | 1), {hex(k): n for k, n in votes.items()} or 'none'))
        for lit in old.word_sites(value | 1):
            for q, sub in d.load_sites(lit):
                nq = d.load_pairs.get(q) or d.site(q)
                if nq is None or sub:
                    continue
                new = d.new
                if arg == 'stack':
                    # the pointer is a stack argument: some ldr rt,[pc] whose rt goes to [sp] before the next bl, in both
                    # images; that bl reaches the same consumer (by its signature, or both through an ITCM veneer)
                    bo, bn = stack_call(old, q), stack_call(new, nq)
                    vo, vn = (itcm_veneer(old, bo[1]), itcm_veneer(new, bn[1])) if bo and bn else (None, None)
                    good = old.h(q) & 0xf800 == 0x4800 and new.h(nq) & 0xf800 == 0x4800 and bo and bn and \
                        ((vo is not None and vn is not None) or d.sig(bo[1])[0] == bn[1])
                    if not good:
                        why.append('load %s/%s is not an ldr whose register is stored to the stack before a bl to one consumer' % (
                            hex(q), hex(nq)))
                    else:
                        ok += 1
                    continue
                bo, bn = branch(old, q + 2), branch(new, nq + 2)
                so = d.sig(bo[1])[0] if bo else None
                if old.h(q) & 0xf800 != 0x4800 or (old.h(q) >> 8) & 7 != arg or new.h(nq) & 0xf800 != 0x4800 or \
                        (new.h(nq) >> 8) & 7 != arg or not bo or not bn or bo[0] != 'bl' or bn[0] != 'bl' or so != bn[1]:
                    why.append('load %s/%s is not ldr r%d followed by a bl to one consumer' % (hex(q), hex(nq), arg))
                else:
                    ok += 1
        if not ok:
            why.append('no paired load passes the pointer to the slot setter')
        if why:
            r['problems'].append('added edit (pointer): ' + '; '.join(why))
        else:
            r['methods']['entry'] = 'stored pointer: %d paired ldr %s + bl to one consumer name %s' % (
                ok, 'and stack store' if arg == 'stack' else 'r%d' % arg, hex(r['new'] | 1))
    for kind, name, value in [('link', n, v) for n, v in added_code.items()] + \
            [('edit', role, v) for role, (v, _, *proof) in (added_edits or {}).items() if not proof]:
        found = [r for r in rows if r['kind'] == kind and r['name'] == name]
        assert len(found) == 1, 'added %s %s: %d rows' % (kind, name, len(found))
        r, at = found[0], value & ~1
        calls = d.callers(at) + d.t2_callers(at)[0]
        if not old.branch_sites().get(at):
            r['problems'].append('added %s: the old value is not the target of any old BL/B.W' % kind)
        elif r['new'] is None or not calls.get(r['new'] & ~1):
            r['problems'].append('added %s: no paired caller names the derived value (%s)' % (kind, 
                ', '.join('%s: %d' % (hex(k), n) for k, n in calls.items()) or 'no paired caller'))
        else:
            r['methods']['entry'] = 'old BL/B.W target; %d paired caller vote(s) name %s' % (calls[r['new'] & ~1], hex(r['new'] & ~1))


def run(old_fw, new_fw, table_path, old, new, cfg, abi=None, derive_only=False, disabled=frozenset()):
    u, rows, d, derived = derive(old_fw, old, new, abi, cfg['stringChanges'], disabled, cfg.get('addedCode'),
                                 cfg.get('addedRam'), cfg.get('addedEdits'))
    # the known-bad check runs before the reviewed splits, so that its split case stays load-bearing, and again after
    # them, when it must find the good value on every row a reviewed split resolved
    kb_lines, kb_fails = known_bad(cfg, rows, d, old, new)
    rs_lines, rs_fails, applied = reviewed_splits(cfg, rows, d, old, new, disabled)
    kb_lines += rs_lines
    kb_fails += rs_fails
    if applied:
        lines, fails = known_bad(cfg, rows, d, old, new, applied)
        kb_lines += lines
        kb_fails += fails
    added_entry(cfg.get('addedCode') or {}, rows, d, old, cfg.get('addedRam'), cfg.get('addedEdits'))
    row_problems, problems = [], []
    for r in rows:
        row_problems += ['%s %s %s: %s' % (r['kind'], r['name'], hex(r['old']), p) for p in r['problems']]
        if r['new'] is None and not r['problems']:
            row_problems.append('%s %s %s: unresolved' % (r['kind'], r['name'], hex(r['old'])))
        if r['kind'] == 'edit':
            e = r['edit']
            if old.raw[r['old'] - FLASH:r['old'] - FLASH + len(e['before']) // 2].hex() != e['before']:
                problems.append('old edit %r before bytes do not match the old image' % r['name'])
    if derive_only:
        return u, rows, d, derived, row_problems, problems, [], [], 0, None, (kb_lines, kb_fails)
    # the table of the pair under test is read only now, after the derivation
    cf_lines, cf_fails = comment_corrections(cfg, rows, new)
    kb_lines += cf_lines
    kb_fails += cf_fails
    table = json.loads(table_path.read_text())
    tree_problems = compare_tree(u, rows, new_fw, new)
    added = [r for r in table['linkld'] if r['symbol'] in cfg['addedAfterOldTree']]
    table_extra = [x for r in added for x in pool_context_check(r, old, new)]
    link_text = (new_fw/'link.ld').read_text()
    for r in added:
        if '%s = %s;' % (r['symbol'], r['new']) not in link_text:
            table_extra.append('link.ld does not define %s = %s' % (r['symbol'], r['new']))
    table_problems, table_checked = compare_table(rows, table, new, cfg['addedAfterOldTree'])
    table_problems += table_extra
    for r in rows:
        if r['kind'] == 'abi' and r['new'] is not None and 'abi_new_sha' in r:
            n = r['abi'][0]
            got = hashlib.sha256(new.raw[r['new'] - FLASH:r['new'] - FLASH + n]).hexdigest()
            if got != r['abi_new_sha']:
                table_problems.append('ABI range %s: new image hash %s != table %s' % (hex(r['new']), got,
                                                                                       r['abi_new_sha']))
    return u, rows, d, derived, row_problems, problems, tree_problems, table_problems, table_checked, table, (
        kb_lines, kb_fails)


def known_bad(cfg, rows, d, old, new, must_find=frozenset()):
    """The known-bad check of every knownBad entry: (printed lines, failures). must_find: names a reviewed split
    resolved; for them only case 1 (resolved to the good value) passes."""
    lines, fails = [], []
    byname = {r['name']: r for r in rows if r['kind'] == 'link'}
    for name, kb in cfg['knownBad'].items():
        bad, good = kb['bad'], kb['good']
        r = byname.get(name)
        if r is None:
            lines.append('known bad: %s is not a link.ld symbol of the old tree -> FAIL' % name)
            fails.append('known bad %s not in the old tree' % name)
            continue
        at = r['old'] & ~1
        fwd, back = [], []
        for before, after in SIG_WINDOWS:
            data, keep, _, _ = masked_window(old, at + before, at + after)
            p = (bad & ~1) + before - FLASH
            n = sum(1 for k in range(len(data)) if (new.raw[p + k] ^ data[k]) & keep[k])
            (fwd if after >= 16 else back).append('%d..%d:%d' % (before, after, n))
        fwd_ok = all(not x.endswith(':0') for x in fwd) if kb['windowsDiffer'] else True
        votes = d.callers(at)
        no_bad = fwd_ok and votes.get(bad & ~1, 0) == 0
        # Case 1, any entry: the row resolved to the good value, with a caller vote for it.
        found = no_bad and resolved(r) and r['new'] == good and votes.get(good & ~1, 0) > 0
        # Case 2, split=True entries only: the row is unresolved and its one problem is the sig/call disagreement,
        # the callers' winner is the good value (Thumb bit stripped) with at least 3/4 of all caller votes.
        split, why_not = False, ''
        if not found and name in must_find:
            why_not = 'a reviewed split resolved this row, so it must resolve to the good value'
        elif not found and kb.get('split') is True:
            sig_ans = d.sig(at)[0]
            top, n = votes.most_common(1)[0] if votes else (None, 0)
            total = sum(votes.values())
            if not no_bad:
                why_not = 'the bad value has caller votes' if fwd_ok else 'a forward window matches the bad value'
            elif r['new'] is not None:
                why_not = 'the row resolved to %s, not the good value' % hex(r['new'])
            elif sig_ans is None or top is None or \
                    r['problems'] != ['sig %s and call %s disagree' % (hex(sig_ans), hex(top))]:
                why_not = 'its one problem is not "sig and call disagree": %s' % '; '.join(r['problems'])
            elif top != good & ~1 or n * 4 < total * 3:
                # 3/4 of the votes for the good value also makes it the callers' winning address
                why_not = 'vote count: the good value %s has %d of %d caller votes, under three quarters (the ' \
                          "callers' winning address is %s)" % (hex(good & ~1), votes.get(good & ~1, 0), total, hex(top))
            elif (good & 1) != (r['old'] & 1):
                why_not = 'the good value does not keep the old Thumb bit'
            else:
                split = True
        ok = found or split
        case = ('REJECTED/FOUND (resolved to the good value)' if found else
                'REJECTED, SPLIT AND UNRESOLVED (bad value has no caller vote; callers pick the good value, the '
                'signature another address; the row stays unresolved for a reviewed decision)' if split else
                'FAIL' + (' (split case not met: %s)' % why_not if why_not else ''))
        lines.append('known bad%s: %s old %s; bad value %s: masked mismatches in the windows over the address %s%s, '
                     'over the code before it %s; caller votes %s; derived %s (expected %s)%s -> %s' % (
                         ' (after the reviewed splits)' if must_find else '',
                         name, hex(r['old']), hex(bad), ' '.join(fwd),
                         '' if kb['windowsDiffer'] else ' (not asserted)', ' '.join(back),
                         {hex(k): v for k, v in votes.items()},
                         hex(r['new']) if r['new'] is not None else 'none (%s)' % '; '.join(r['problems']), hex(good),
                         ' [split=True]' if kb.get('split') is True else '', case))
        if not ok:
            fails.append('known bad %s not rejected%s' % (name, ' after the reviewed splits' if must_find else ''))
    return lines, fails


def reviewed_splits(cfg, rows, d, old, new, disabled):
    """Apply the pair's reviewedSplits block (see PAIRS): (printed lines, failures, names it resolved)."""
    lines, fails, applied = [], [], set()
    for key, e in cfg.get('reviewedSplits', {}).items():
        named = [r for r in rows if r['kind'] == 'link' and r['old'] == key]
        if not named:
            fails.append('reviewedSplits %s is not a link.ld value of the old tree' % hex(key))
            continue
        x, y = key & ~1, e['new'] & ~1
        for r in named:
            if 'reviewed-split' in disabled:
                r['methods']['reviewed-split'] = 'none (disabled)'
                continue
            why = []
            want = ['sig %s and call %s disagree' % (hex(e['decoy']), hex(y))]
            if r['problems'] != want:
                why.append('its problems are %s, not %s' % (r['problems'], want))
            if r['methods'].get('call') != e['votes']:
                why.append('call is %r, not %r' % (r['methods'].get('call'), e['votes']))
            for img, at, (n, h), side in ((old, x, e['old'], 'old'), (new, y, e['newBytes'], 'new')):
                got_n = fn_end(img, at) - at if img.has(at, 2) else None
                got_h = hashlib.sha256(img.raw[at - FLASH:at - FLASH + n]).hexdigest() if img.has(at, n) else None
                if got_n != n or got_h != h:
                    why.append('the %s bounded body at %s is %s bytes, sha256 %s, not %d bytes %s' % (
                        side, hex(at), got_n, got_h, n, h))
            if (e['new'] & 1) != (key & 1):
                why.append('new does not keep the old Thumb bit')
            pooled = d.edge_pool.get(x, set()) - {y}
            if pooled:
                why.append('the edge pool also maps the old function to %s' % ','.join(hex(p) for p in sorted(pooled)))
            if why:
                r['methods']['reviewed-split'] = 'none (entry %s does not apply: %s)' % (hex(key), '; '.join(why))
                lines.append('reviewed split: %s %s: entry %s does not apply (%s); the row stays unresolved' % (
                    r['name'], hex(r['old']), hex(key), '; '.join(why)))
                continue
            r['new'] = e['new']
            r['problems'] = []
            r['methods']['reviewed-split'] = 'entry %s: %s, decoy %s, %s, old %d bytes %s, new %d bytes %s: %s' % (
                hex(key), hex(e['new']), hex(e['decoy']), e['votes'], e['old'][0], e['old'][1][:12],
                e['newBytes'][0], e['newBytes'][1][:12], e['reason'])
            seen = d.edge_pool.get(x)
            if seen:
                r['methods']['edge'] = '%d pooled edge(s) -> %s' % (len(seen), ','.join(hex(p) for p in sorted(seen)))
            applied.add(r['name'])
            lines.append('reviewed split: %s %s -> %s (entry %s: the row\'s one problem is the sig/call disagreement '
                         'with decoy %s; call %s; old and new bounded bodies match their pinned hashes)' % (
                             r['name'], hex(r['old']), hex(e['new']), hex(key), hex(e['decoy']), e['votes']))
    return lines, fails, applied


def report(rows):
    for r in rows:
        status = 'AGREE' if r['new'] is not None and not r['problems'] else 'FAIL'
        print('%-5s %-6s %-44s %-11s -> %-11s %s' % (
            status, r['kind'], r['name'][:44], hex(r['old']), hex(r['new']) if r['new'] is not None else '?',
            '; '.join('%s: %s' % kv for kv in r['methods'].items())))
        for p in r['problems']:
            print('      problem: ' + p)
    combos = Counter('+'.join(k for k in r['methods'] if not r['methods'][k].startswith('none')) for r in rows)
    print('methods per row: ' + ', '.join('%s %d' % kv for kv in sorted(combos.items(), key=lambda kv: -kv[1])))


JSON_KIND = {'link': 'linkld', 'edit': 'edit', 'value': 'value', 'abi': 'abi-range'}


def resolved(r):
    return r['new'] is not None and not r['problems']


def derive_only_json(key, rows):
    module = next(r for r in rows if r['kind'] == 'module')
    out = []
    for r in rows:
        if r['kind'] == 'module':
            continue
        row = {'kind': JSON_KIND[r['kind']], 'name': r['name'], 'old': hex(r['old']),
               'new': hex(r['new']) if resolved(r) else None,
               'methods': [k for k, v in r['methods'].items() if not v.startswith('none')]}
        if not resolved(r):
            row['reason'] = '; '.join(r['problems']) or 'unresolved'
        out.append(row)
    return {'pair': '%s:%s' % key, 'moduleVA': hex(module['new']) if resolved(module) else None, 'rows': out}


def main(argv=None):
    """Returns 0 on PASS; any other outcome raises SystemExit (1, or 3 for --derive-only with unresolved rows)."""
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--pair', metavar='FROM:TO', help='default: the last pair whose table exists in the new tree')
    ap.add_argument('--old-tree', type=Path, help="the pair's oldTag export (repo root or its firmware/); "
                                                  'default: git archive')
    ap.add_argument('--new-tree', type=Path, default=FW)
    ap.add_argument('--stock-old', type=Path, help="default: the pair's oldStock in the old-tree export")
    ap.add_argument('--stock-new', type=Path, help="default: the pair's newStock (repository or $TURBO_INPUTS)")
    ap.add_argument('--table', type=Path)
    ap.add_argument('--no-mutation', action='store_true', help='skip the mutation check')
    ap.add_argument('--derive-only', action='store_true',
                    help='developer/acceptance flag, never used in gates: derive only, compare with no tree or table')
    ap.add_argument('--json', type=Path, help='with --derive-only: write the derived rows to this JSON file')
    ap.add_argument('--disable-method', action='append', default=[], choices=TEST_METHODS, metavar='NAME',
                    help='acceptance only, needs --derive-only: do not apply this method (repeatable; one of %s)'
                    % ', '.join(TEST_METHODS))
    args = ap.parse_args(argv)
    if args.json and not args.derive_only:
        raise SystemExit('--json needs --derive-only')
    if args.disable_method and not args.derive_only:
        raise SystemExit('--disable-method needs --derive-only')
    tmp = Path(tempfile.mkdtemp(prefix='rebase-independent-'))
    try:
        code = check(args, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if code:
        raise SystemExit(code)
    return 0


def check(args, tmp):
    derive_only = args.derive_only
    new_fw = fw_dir(args.new_tree)
    key = pick_pair(args.pair, new_fw)
    cfg = PAIRS[key]
    old_root = args.old_tree or export_old(tmp/'old', cfg)
    old_fw = fw_dir(old_root)
    stock_old = args.stock_old or (old_fw.parent/cfg['oldStock'])
    stock_new = args.stock_new or new_stock_path(cfg)
    table_path = args.table or new_fw/cfg['table']
    if not derive_only and not table_path.is_file():
        # an existence check only: the table itself is still read only after the derivation
        raise SystemExit('table not found: %s (use --derive-only for a pair whose table is not written yet)'
                         % table_path)
    old, new =Image(load_ap(stock_old, cfg['oldAP']), key[0]), Image(load_ap(stock_new, cfg['newAP']), key[1])
    fails, soft = [], []

    def need(ok, msg, *involved):
        """A failed check; in --derive-only, one whose rows exist and are unresolved is already listed with them.
        A row that is missing from the old tree (None) is never softened: that is an error."""
        if ok:
            return
        if derive_only and involved and all(r is not None for r in involved) and \
                any(not resolved(r) for r in involved):
            soft.append(msg)
        else:
            fails.append(msg)

    disabled = frozenset(args.disable_method)
    print('pair %s:%s (old tree %s)%s%s' % (key[0], key[1], 'given' if args.old_tree else cfg['oldTag'],
                                            ' -- derive-only' if derive_only else '',
                                            ' -- disabled methods: ' + ', '.join(sorted(disabled)) if disabled else ''))
    print('images: old %d bytes, new %d bytes; copy tables old %s new %s' % (
        len(old.raw), len(new.raw), [tuple(map(hex, t)) for t in old.tables], [tuple(map(hex, t)) for t in new.tables]))
    for dst in (0x100000, RAM_LO):
        try:
            so, sn = old.region(dst), new.region(dst)
        except StopIteration:
            fails.append('no copy table entry for dst %s' % hex(dst))
    abi = old_abi(old_fw, key)
    NEW_TREE.update(pruneLink=set(cfg.get('newTreeChanges', {}).get('pruneLink', ())),
                    valueToLink=dict(cfg.get('newTreeChanges', {}).get('valueToLink', {})))
    u, rows, d, derived, row_problems, problems, tree_problems, table_problems, table_checked, table, (
        kb_lines, kb_fails) = run(old_fw, new_fw, table_path, old, new, cfg, abi, derive_only, disabled)
    report(rows)
    fails += problems + tree_problems + table_problems
    if not derive_only:
        fails += row_problems
    for v in cfg['stringChanges']:
        if not any(r['kind'] == 'value' and r['old'] == v for r in rows):
            fails.append('stringChanges %s is not a value of the old tree' % hex(v))
    # NOT_STOCK tokens: none may have a literal in either stock image (region bounds are checked by the table)
    for t, n in sorted(not_stock_seen(old_fw, old).items()):
        v = int(t, 16)
        if v in (FLASH, RAM_LO):
            ok = v == FLASH or old.region(RAM_LO)[2] == v
        else:
            ok = not old.word_sites(v) and not new.word_sites(v)
        print('not stock: %s x%d  %s%s' % (t, n, NOT_STOCK[t], '' if ok else '  <- HAS A STOCK LITERAL'))
        if not ok:
            fails.append('NOT_STOCK token %s has a stock literal' % t)
    # coverage
    universe = (len(u['link']) + len(u['edits']) + len(u['abi']) + 1 + len(u['sites']))
    code_refs = len(u['link']) + len(u['edits']) + 1
    print('coverage: old tree universe %d addresses (%d link.ld + %d edits + module = %d code references; '
          '%d ABI ranges; %d literal values at %d sites), rows checked %d, table rows compared %s' % (
              universe, len(u['link']), len(u['edits']), code_refs, len(u['abi']), len(u['sites']),
              sum(sum(c.values()) for c in u['sites'].values()), len(rows),
              'none (derive-only)' if derive_only else table_checked))
    if len(rows) != universe:
        fails.append('coverage: %d rows for %d universe addresses' % (len(rows), universe))
    if not derive_only and table_checked != universe:
        fails.append('coverage: table compared on %d of %d addresses' % (table_checked, universe))
    # known bad (run before and, when a reviewed split applied, after the reviewedSplits block): always fatal
    for line in kb_lines:
        print(line)
    fails += kb_fails
    byname = {r['name']: r for r in rows if r['kind'] == 'link'}
    # copy region and the strcmp veneer
    for name in COPY_CALLEES:
        r = byname.get(name)
        if r is None:
            fails.append('copy-region callee %s is not in the old tree' % name)
            continue
        ok = r['new'] == r['old'] and 'copy' in r['methods'] and not old.has(r['old'])
        print('copy region: %s %s -> %s (%s)' % (name, hex(r['old']), hex(r['new'] or 0), r['methods'].get('copy')))
        need(ok, 'copy-region callee %s moved or unchecked' % name, r)
    vr = byname.get(STRCMP_VENEER)
    for img, va in ((old, vr and vr['old']), (new, vr and vr['new'])):
        if va is None:
            need(False, 'strcmp veneer on %s not derived' % img.name, vr)
            continue
        r_ = literal_ref(img, va & ~1)
        h1 = img.h(va & ~1)
        tgt = img.w(r_[0]) if r_ else None
        ok = (h1 & 0xff7f) == 0xf85f and (img.h((va & ~1) + 2) >> 12) == 15 and tgt == byname['strcmp']['old']
        print('strcmp veneer on %s at %s: ldr.w pc,[pc] -> %s %s' % (img.name, hex(va), hex(tgt or 0),
                                                                   'OK' if ok else 'FAIL'))
        need(ok, 'strcmp veneer on %s does not reach strcmp' % img.name, vr)
    # resume_X (link.ld) is the trampoline edit X + 4 (+ Thumb bit): two independently derived rows must agree
    edits = {r['name'].removeprefix('Entry trampoline '): r for r in rows if r['kind'] == 'edit'}
    n_resume = 0
    for name, r in byname.items():
        if name.startswith('resume_') and name[7:] in edits:
            e = edits[name[7:]]
            n_resume += 1
            need(r['old'] == e['old'] + 5 and r['new'] == (e['new'] or 0) + 5,
                 '%s %s is not trampoline edit %s + 5' % (name, hex(r['new'] or 0), hex(e['new'] or 0)), r, e)
    print('resume symbols: %d, each the derived trampoline edit + 5' % n_resume)
    if derive_only:
        return derive_only_result(key, rows, fails, soft, args.json)
    # mutation check
    if not args.no_mutation:
        fails += mutation(old_fw, new_fw, table, old, new, rows, cfg['addedAfterOldTree'])
    print()
    agree = sum(1 for r in rows if resolved(r))
    print('result: %d rows, %d agree, %d fail; %d tree problems, %d table problems' % (
        len(rows), agree, len(rows) - agree, len(tree_problems), len(table_problems)))
    for f in fails:
        print('FAIL ' + f)
    if fails:
        return 1
    print('PASS rebase independent: %d addresses re-derived, tree and table agree' % len(rows))
    return 0


def derive_only_result(key, rows, fails, soft, json_path):
    print()
    open_ = [r for r in rows if not resolved(r)]
    print('derive-only: pair %s:%s, %d rows (moduleVA included), %d resolved, %d unresolved; no tree or table compared'
          % (key[0], key[1], len(rows), len(rows) - len(open_), len(open_)))
    for r in open_:
        print('unresolved: %s %s %s: %s' % (r['kind'], r['name'], hex(r['old']), '; '.join(r['problems']) or
                                             'unresolved'))
    for s in soft:
        print('follows from an unresolved row: ' + s)
    if json_path:
        json_path.write_text(json.dumps(derive_only_json(key, rows), indent=1) + '\n')
        print('derive-only: rows written to %s' % json_path)
    if soft and not open_:
        fails.append('%d softened check(s) but no unresolved row to explain them' % len(soft))
    for f in fails:
        print('FAIL ' + f)
    if fails:
        return 1
    if open_:
        print('derive-only UNRESOLVED: known-bad rows pass; %d rows unresolved (exit 3)' % len(open_))
        return 3
    print('derive-only PASS: %d rows resolved, known-bad rows pass' % len(rows))
    return 0


def comment_corrections(cfg, rows, new):
    """newTreeChanges commentFix: a code-comment value row must first derive to `derived` here; it then takes `new`, which
    must be a function entry in the new image by its bytes (a word that a pc-relative load reads right before it, and a
    push {..., lr} at it) and either the derived new address of link.ld `link` or the pinned `body` bytes. Returns
    (printed lines, failures); the compare stage then sees the corrected rows."""
    lines, fails = [], []
    links = {r['name']: r['new'] for r in rows if r['kind'] == 'link'}
    for old_value, fix in cfg.get('newTreeChanges', {}).get('commentFix', {}).items():
        found = [r for r in rows if r['kind'] == 'value' and r['old'] == old_value]
        x, why = fix['new'], []
        if len(found) != 1:
            fails.append('commentFix %s: %d value rows of the old tree' % (hex(old_value), len(found)))
            continue
        r = found[0]
        if r['new'] != fix['derived']:
            why.append('derived %s, the entry says %s' % (hex(r['new'] or 0), hex(fix['derived'])))
        if x & 1 != old_value & 1 or not new.has(x, 8):
            why.append('Thumb bit or address')
        else:
            h1, h2 = new.h(x), new.h(x + 2)
            if not (h1 & 0xff00 == 0xb500 or (h1 == 0xe92d and h2 & 0x4000)):
                why.append('no push {..., lr} at %s' % hex(x))
            if not any(literal_ref(new, pc) and literal_ref(new, pc)[0] == x - 4 for pc in range(x - 4096, x - 4, 2)):
                why.append('no pc-relative load reads the word before %s' % hex(x))
        if 'link' in fix and (links.get(fix['link']) or 0) & ~1 != x:
            why.append('not the derived link.ld %s' % fix['link'])
        if 'body' in fix and hashlib.sha256(new.raw[x - FLASH:x - FLASH + fix['body'][0]]).hexdigest() != fix['body'][1]:
            why.append('the %d bytes at %s are not the pinned ones' % (fix['body'][0], hex(x)))
        if why:
            fails.append('commentFix %s: %s' % (hex(old_value), '; '.join(why)))
            continue
        lines.append('comment fix: value %s derived %s, written %s (%s)' % (
            hex(old_value), hex(r['new']), hex(x), 'link.ld ' + fix['link'] if 'link' in fix else 'pinned body'))
        r['new'] = x
    return lines, fails


def mutation(old_fw, new_fw, table, old, new, rows, added=frozenset()):
    """Swap one link.ld address and one table address for a neighbour's, in temp copies; both must fail."""
    out = []
    link = [r for r in rows if r['kind'] == 'link' and r['new'] is not None and r['new'] != r['old'] and r['name'] not in NEW_TREE['pruneLink']]
    a, b = link[0], link[1]
    base_tree = set(compare_tree(None, rows, new_fw, new))
    base_table = set(compare_table(rows, table, added=added)[0])
    with tempfile.TemporaryDirectory(prefix='rebase-mutation-') as t:
        tree = Path(t)/'firmware'
        shutil.copytree(new_fw, tree, ignore=shutil.ignore_patterns('__pycache__'))
        p = tree/'link.ld'
        text = p.read_text()
        text2 = re.sub(r'^(%s\s*=\s*)0x[0-9a-fA-F]+;' % re.escape(a['name']), r'\g<1>%s;' % hex(b['new']), text,
                       flags=re.M)
        assert text2 != text
        p.write_text(text2)
        tp = [x for x in compare_tree(None, rows, tree, new) if x not in base_tree and a['name'] in x]
        print('mutation: link.ld %s set to its neighbour %s\'s %s -> %d new tree problem(s) %s%s' % (
            a['name'], b['name'], hex(b['new']), len(tp), 'DETECTED' if tp else 'MISSED', (': ' + tp[0]) if tp else ''))
        if not tp:
            out.append('mutation of link.ld not detected')
        p.write_text(text)
        v = max((r for r in rows if r['kind'] == 'value' and r['new'] is not None and RAM_LO <= r['old'] < RAM_HI and r['old'] not in NEW_TREE['valueToLink']),
                key=lambda r: sum(r['sites'].values()))
        f = sorted(v['sites'])[0]
        q = tree/f
        q.write_text(q.read_text().replace(hex(v['new']), hex(v['new'] + 4), 1))
        tp = [x for x in compare_tree(None, rows, tree, new) if x not in base_tree and f in x]
        print('mutation: %s %s set to its neighbour word %s -> %d new tree problem(s) %s%s' % (
            f, hex(v['new']), hex(v['new'] + 4), len(tp), 'DETECTED' if tp else 'MISSED', (': ' + tp[0]) if tp else ''))
        if not tp:
            out.append('mutation of a RAM value not detected')
        mt = json.loads(json.dumps(table))
        row = next(x for x in mt['linkld'] if x['symbol'] == a['name'])
        row['new'] = hex(b['new'])
        tb = [x for x in compare_table(rows, mt, added=added)[0] if x not in base_table and a['name'] in x]
        print('mutation: table %s new set to %s -> %d new table problem(s) %s%s' % (
            a['name'], hex(b['new']), len(tb), 'DETECTED' if tb else 'MISSED', (': ' + tb[0]) if tb else ''))
        if not tb:
            out.append('mutation of the table not detected')
        e = next(r for r in rows if r['kind'] == 'edit')
        mt = json.loads(json.dumps(table))
        row = next(x for x in mt['edits'] if x['role'] == e['name'])
        row['newAddress'] = hex(e['new'] + 2)
        tb = [x for x in compare_table(rows, mt, added=added)[0] if x not in base_table and e['name'] in x]
        print('mutation: table edit %r newAddress +2 -> %d new table problem(s) %s%s' % (
            e['name'], len(tb), 'DETECTED' if tb else 'MISSED', (': ' + tb[0]) if tb else ''))
        if not tb:
            out.append('mutation of a table edit not detected')
        added_edit = next((r for r in rows if r['kind'] == 'edit' and r['edit'].get('added') and r['new'] is not None), None)
        if added_edit is not None:
            mt = json.loads(json.dumps(table))
            row = next(x for x in mt['edits'] if x['role'] == added_edit['name'])
            row['newAddress'] = hex(added_edit['new'] + 2)
            tb = [x for x in compare_table(rows, mt, added=added)[0] if x not in base_table and added_edit['name'] in x]
            print('mutation: table added edit %r newAddress +2 -> %d new table problem(s) %s%s' % (
                added_edit['name'], len(tb), 'DETECTED' if tb else 'MISSED', (': ' + tb[0]) if tb else ''))
            if not tb:
                out.append('mutation of an added table edit not detected')
            q = tree/'build-inputs.json'
            text = q.read_text()
            spec = json.loads(text)
            e = next(x for x in spec['edits'] if x['role'] == added_edit['name'])
            e['address'], e['offset'] = hex(added_edit['new'] + 2), hex(added_edit['new'] + 2 - FLASH)
            q.write_text(json.dumps(spec, indent=2) + '\n')
            tp = [x for x in compare_tree(None, rows, tree, new) if x not in base_tree and added_edit['name'] in x]
            print('mutation: build-inputs added edit %r address +2 -> %d new tree problem(s) %s%s' % (
                added_edit['name'], len(tp), 'DETECTED' if tp else 'MISSED', (': ' + tp[0]) if tp else ''))
            if not tp:
                out.append('mutation of an added tree edit not detected')
            q.write_text(text)
    return out


if __name__ == '__main__':
    sys.exit(main())
