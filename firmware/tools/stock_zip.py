"""Build or check the canonical stock ZIP of a base that has no official ZIP (today 1.0.6.11). Never connects to a device.

  python3 -I firmware/tools/stock_zip.py build --base 1.0.6.11 --members DIR --out PATH
  python3 -I firmware/tools/stock_zip.py check --base 1.0.6.11 --zip PATH

Every member and the container itself are pinned by the literals in PINS below. They are never read from a file at
run time (the SHA256SUMS in --members is ignored). The archive is written by build.py's own writer (write_archive)
and re-read through build.safe_zip with the container pin, so a ZIP that differs by one byte is refused. There is no
members-only fallback: if the writer environment ever changes the bytes, the container pin changes only in its own
reviewed commit. On any failure `build` deletes its output. main(argv) returns the exit code (0 or 1)."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys

FW = Path(__file__).resolve().parents[1]
REPO = FW.parent
IGNORED = ('SHA256SUMS', 'PROVENANCE.md')
PINS = {'1.0.6.11': {
  'members': {
    'amap_rtos_sdk': 'a14c47776864b5786bf61e4c37e159259c8d7c9b94ad6664e4526eadc445574a',
    'bt_controller.bin': 'dd935af210755d94c43995c62d9ec03e469157cd14965b1642c83d2f1daa440b',
    'cb_fw_venus.bin': '8799f12071bdac082218e3601c24ab0989275fc2f7db74e37b8314a225c2cf7d',
    'fac_test_img.bin': '18eb0901c3e0daeae48dd5f015252b6931ea7368f0160c2c985c4e74296d17eb',
    'images.bin': '404ae1d33592db7592467b24bc29c1c783260fb7cf53f4be22838097f38fa501',
    'lotties.bin': 'a8b5fa78e57775a025d90aa94d41245495a555c7ca4399b226b515bc03997162',
    'nuttx_ap.bin': '9bbf7be31ebb7f8600e6ea4bf51831a151e2af6d4eb8e6ccfcf55d67f2e71260',
    'nuttx_apc1.bin': 'c24794d051df5803152fac770051374aff4bd34f6d41ef8ab39853e7b4d05ba9',
    'nuttx_audio.bin': '549a72c032595e3829da7d63b7e1fd13cceda1a55dfefa7a7cad02db5a9b42ab',
    'nuttx_bth.bin': '1fd910ea03124cd26d010c3ea3ef6a1b68dc61bd6283dcd07d2ad744d28759ec',
    'nuttx_ota.bin': '016cdd0ba9424512c9669d229b7c81d94eebdb24e15ba3c1c7b461ca32f2bc1a',
    'ota_installer_progress.bin': '6fd65d296a667e1a7d94ec129adfd26458a4008ef403b331f855192c36eb3e3f',
    'OtaFileInfo.json': 'c5c09444e28bde6d13c9916aca17dd78b19e676854be4991b260e134d55f91a9',
    'pil_algo_up_demo_nand.dll': 'e266726fe055ac6ec6f785a9440e8da7421402f2b4d3d7889039ad9b94e119c2',
    'pil_algo_vad_demo.dll': '0153a5a8e6b69ca0b9dd4cc742d45a758351d8209e604f38dbfe046c31f29f01',
    'pil_algo_wakeup_dll_nand.dll': 'd1594cb8658b228e52c2606d02f1eab696d35a11ed42ddcb725e76a745f5550f',
    'smf.json': '43998e7acf06c8f9bc39635655d79120b7061a46f7b23f791f8699536f81836d'},
  'container': {'sha256': '5821506f720a43a9a3aea9c5722a1548463dcf1cbedcb2d97a242e2a64037d6e', 'bytes': 9447267},
  'provenance': {'ownerRezip': {'name': 'Strix_OS_1.0.6.11-rezipped-20261112-224028.zip',
    'sha256': 'ecfd6ec3bd580f22a69c20f9be976b5429911eedea5b79cd1fcef6e402d1c0ea', 'bytes': 18315227}}}}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load_build():
    spec = importlib.util.spec_from_file_location('stock_zip_build', FW/'build.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def pinned(base):
    assert base in PINS, 'no pinned canonical stock for %r' % (base,)
    return PINS[base]


def verify(path, base, build=None):
    """The checks `check` runs, and `build` runs on its own output: container hash (first), package shape, size,
    every member pin, the manifest pin and core identity."""
    build = build or load_build(); pin = pinned(base)
    assert build.package_shape(base)['container'] == 'canonical-members', base + ' is not a canonical-members base'
    files, rows = build.safe_zip(path, pin['container']['sha256'], base)
    assert path.stat().st_size == pin['container']['bytes'], 'container size %d, pinned %d' % (path.stat().st_size, pin['container']['bytes'])
    assert {n: sha(b) for n, b in files.items()} == pin['members'], 'pin mismatch: members'
    build.check_stock_members(files, {'stockMembers': {n: h for n, h in pin['members'].items() if n != 'OtaFileInfo.json'},
                                      'stockManifestSHA256': pin['members']['OtaFileInfo.json']}, base)
    build.core_identity(files, base)
    data = path.read_bytes()
    return {'base': base, 'zip': str(path), 'bytes': len(data), 'sha256': sha(data), 'members': len(files),
            'container': 'canonical-members', 'deviceIO': False}


def read_members(members, base):
    pin = pinned(base)['members']
    assert members.is_dir(), 'members folder not found: %s' % members
    for p in members.iterdir():
        assert p.name in pin or p.name in IGNORED, 'unexpected file in the members folder: ' + p.name
    files = {}
    for name, want in pin.items():
        p = members/name
        assert not p.is_symlink(), 'member is a symlink: ' + name
        assert p.is_file(), 'member missing: ' + name
        data = p.read_bytes()
        assert sha(data) == want, 'pin mismatch: member ' + name
        files[name] = data
    return files


def inside_repo(out):
    """True when out is the repository or lies under it. The nearest existing ancestor of out is compared with the
    repository by file identity (os.path.samefile), so a spelling in other letter case on a case-insensitive disk,
    a symlinked parent or '..' cannot slip past a string comparison."""
    resolved = out.resolve()
    existing = next(p for p in (resolved, *resolved.parents) if p.exists())
    repo = REPO.resolve()
    return any(os.path.samefile(p, repo) for p in (existing, *existing.parents))


def build_zip(base, members, out):
    build = load_build()
    files = read_members(members, base)
    assert not out.exists() and not out.is_symlink(), 'output exists: %s' % out
    assert 'original' not in out.name.casefold(), 'output name must not contain "original" (that name is kept for official ZIPs)'
    assert not inside_repo(out), 'output must not lie inside the repository'
    try:
        build.write_archive(out, files)
        return verify(out, base, build)
    except BaseException:
        out.unlink(missing_ok=True)
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description='Build or check the canonical stock ZIP of a base (no device I/O).')
    sub = parser.add_subparsers(dest='command', required=True)
    b = sub.add_parser('build'); b.add_argument('--base', required=True, choices=sorted(PINS))
    b.add_argument('--members', type=Path, required=True); b.add_argument('--out', type=Path, required=True)
    c = sub.add_parser('check'); c.add_argument('--base', required=True, choices=sorted(PINS))
    c.add_argument('--zip', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        result = build_zip(args.base, args.members, args.out) if args.command == 'build' else verify(args.zip, args.base)
    except Exception as error:
        print('stock_zip %s: FAIL: %s' % (args.command, str(error) or type(error).__name__), file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
