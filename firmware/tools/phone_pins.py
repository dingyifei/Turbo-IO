#!/usr/bin/env python3
"""Generate the phone's firmware pins for every release configuration from the exact release ZIPs.

Input: official-addon/ios107-edition/releases.json (one entry per phone release: the firmware label, the stock base
the ZIP is built on, the ZIP's path under $TURBO_INPUTS with its size and SHA-256, and the accepted current glasses
versions). For each release this reads the ZIP, checks its manifest, its pinned identity, that every non-AP member
is byte-for-byte the member of the stock ZIP of its base, and that AP, APC1 and BTH all report that base (build.py's
core_identity). The release whose firmware is the tree's label (../RELEASE) must also be the ZIP in
../build-inputs.json, on the same stock base.

Output (--write DIR / --check DIR):
  FirmwarePins.h          one block per release, chosen at compile time by TIO_RELEASE_<NAME> (no define = default)
  firmware-pins.json      the default release (format unchanged since TMG3)
  firmware-pins-<n>.json  each other release, with its version policy

Every version literal of the phone's OTA path comes from these macros: the accepted current OsVersion, the feed's
query classifier, the type-5 OtaVersion, the official folder name, the feed's versionName/versionCode/download name,
baseFirmware, and the member pins.

This does not audit executable edits, authorize flashing, or change OTA routing. The firmware build's audit
remains required.
"""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import sys
import zipfile

FW = Path(__file__).resolve().parents[1]
ROOT = FW.parent
ED = ROOT/'official-addon'/'ios107-edition'
RELEASE_NAME = re.compile(r'default|c[0-9]+')
VERSION = re.compile(r'([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)')


def release_label(root=None):
    """The one place the tree's release label comes from: RELEASE at the tree root. Never the folder name."""
    label = ((root or Path(__file__).resolve().parents[1]) / 'RELEASE').read_text().strip()
    if not re.fullmatch(r'TMG[0-9]+', label):
        raise ValueError('RELEASE must hold one label such as TMG8')
    return label


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_archive(raw):
    """The manifest and the 15 payloads of a release ZIP, every row checked against its bytes."""
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        names = z.namelist()
        if len(names) != len(set(names)):
            raise ValueError('duplicate ZIP member')
        manifest_data = z.read('OtaFileInfo.json')
        manifest = json.loads(manifest_data)
        if not isinstance(manifest, list) or len(manifest) != 15:
            raise ValueError('expected 15 payload manifest rows')
        payloads = {}
        for row in manifest:
            if not isinstance(row, dict):
                raise ValueError('manifest row is not an object')
            name = row.get('Name')
            if (not isinstance(name, str) or not name or '/' in name or '\\' in name
                    or name in {'.', '..', 'OtaFileInfo.json'} or name in payloads):
                raise ValueError('invalid or duplicate manifest member')
            data = z.read(name)
            if type(row.get('Size')) is not int or row['Size'] != len(data):
                raise ValueError(f'manifest size mismatch: {name}')
            if row.get('Md5') != hashlib.md5(data).hexdigest():
                raise ValueError(f'manifest MD5 mismatch: {name}')
            payloads[name] = data
        if set(names) != set(payloads) | {'OtaFileInfo.json'}:
            raise ValueError('ZIP member set differs from manifest')
    return manifest_data, payloads


def pins_for(archive, name=None):
    """The identity pins of one ZIP (the ten fields of firmware-pins.json)."""
    raw = Path(archive).read_bytes()
    manifest_data, payloads = read_archive(raw)
    ap = payloads['nuttx_ap.bin']
    return {
        'name': name or release_label(),
        'zipBytes': len(raw),
        'zipSHA256': sha256(raw),
        'apBytes': len(ap),
        'apSHA256': sha256(ap),
        'apMD5': hashlib.md5(ap).hexdigest(),
        'manifestBytes': len(manifest_data),
        'manifestSHA256': sha256(manifest_data),
        # Independent of the runtime gate's counters and the test's slice loop.
        # The manifest itself is sent as type 6, never as a type 7 payload.
        'payloadBytes': sum(len(data) for data in payloads.values()),
        'payloadSlices': sum((len(data) + 51199) // 51200 for data in payloads.values()),
    }


def version_parts(version):
    match = VERSION.fullmatch(version) if isinstance(version, str) else None
    if not match:
        raise ValueError('not a four-part Strix version: ' + repr(version))
    return [int(x) for x in match.groups()]


def os_version(version):
    """What the glasses answer in a type-1 reply (OsVersion) and what the type-5 reply names (OtaVersion)."""
    version_parts(version)
    return 'Strix OS ' + version


def query_code(version):
    """The current version as the stock app puts it into the feed query (versionCode=01.00.05.0005)."""
    a, b, c, d = version_parts(version)
    return '%02d.%02d.%02d.%04d' % (a, b, c, d)


def feed_version_name(version):
    """versionName in the feed reply: the query code without dots (0100050005); versionCode is its integer."""
    return query_code(version).replace('.', '')


def stock_zip(base):
    return ROOT/'firmware-research'/('strix-' + base)/'stock'/('Strix-OS-' + base + '-original.zip')


def load_build(root=FW):
    spec = importlib.util.spec_from_file_location('phone_pins_build', root/'build.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_releases(path):
    data = json.loads(Path(path).read_text())
    if data.get('schema') != 1 or not isinstance(data.get('releases'), dict) or 'default' not in data['releases']:
        raise ValueError('releases.json: schema 1 with a default release required')
    for name, spec in data['releases'].items():
        if not RELEASE_NAME.fullmatch(name):
            raise ValueError('release name must be default or cN: ' + name)
        if not re.fullmatch(r'TMG[0-9]+', spec.get('firmware', '')):
            raise ValueError(name + ': firmware must be a TMG label')
        version_parts(spec.get('stockBase'))
        zip_spec = spec.get('zip', {})
        if (not isinstance(zip_spec.get('input'), str) or zip_spec['input'].startswith(('/', '~')) or '..' in zip_spec['input']
                or type(zip_spec.get('bytes')) is not int or not re.fullmatch(r'[0-9a-f]{64}', zip_spec.get('sha256', ''))):
            raise ValueError(name + ': zip needs a relative input path, bytes and sha256')
        accept = spec.get('acceptCurrent')
        if not isinstance(accept, list) or not accept or len(set(accept)) != len(accept):
            raise ValueError(name + ': acceptCurrent must list distinct versions')
        for version in accept:
            version_parts(version)
        if not isinstance(spec.get('hosts'), list) or not spec['hosts'] or not set(spec['hosts']) <= {'107', '1011-full'}:
            raise ValueError(name + ': hosts must be 107 and/or 1011-full')
        if name != 'default' and spec['hosts'] != ['1011-full']:
            raise ValueError(name + ': a named release is a 1.0.11 full-host build')
    return data['releases']


def resolve(spec, inputs):
    """The release ZIP under $TURBO_INPUTS, refused unless its size and SHA-256 are the pinned ones."""
    path = Path(inputs)/spec['zip']['input']
    raw = path.read_bytes()
    if len(raw) != spec['zip']['bytes'] or sha256(raw) != spec['zip']['sha256']:
        raise ValueError('release ZIP does not match its pin: ' + spec['zip']['input'])
    return path


def release_pins(name, spec, archive, build=None, tree_spec=None, tree_label=None):
    """Everything the phone compiles in for one release, derived from its ZIP and checked against its stock base."""
    raw = Path(archive).read_bytes()
    if len(raw) != spec['zip']['bytes'] or sha256(raw) != spec['zip']['sha256']:
        raise ValueError(name + ': ZIP does not match releases.json')
    manifest_data, payloads = read_archive(raw)
    base = spec['stockBase']
    build = build or load_build()
    _stock_manifest, stock_payloads = read_archive(stock_zip(base).read_bytes())
    if set(stock_payloads) != set(payloads):
        raise ValueError(name + ': member names differ from stock ' + base)
    for member, data in payloads.items():
        if member != 'nuttx_ap.bin' and data != stock_payloads[member]:
            raise ValueError(name + ': ' + member + ' is not the stock ' + base + ' member')
    # Never mix cores, and the base in releases.json is the one the ZIP's own cores report.
    if build.core_identity(payloads, base) != build.core_identity(stock_payloads, base):
        raise ValueError(name + ': cores differ from stock ' + base)
    tree_spec = tree_spec if tree_spec is not None else json.loads((FW/'build-inputs.json').read_text())
    tree_label = tree_label or release_label()
    if spec['firmware'] == tree_label and (spec['zip']['sha256'] != tree_spec['archive']['sha256'] or base != tree_spec['stockBase']):
        raise ValueError(name + ': ' + tree_label + ' is the tree label but this is not the ZIP in build-inputs.json')
    pins = pins_for(archive, spec['firmware'])
    members = {member: [len(data), sha256(data)] for member, data in payloads.items()}
    members['OtaFileInfo.json'] = [len(manifest_data), sha256(manifest_data)]
    members = dict(sorted(members.items()))
    accept = spec['acceptCurrent']
    policy = {
        'release': name,
        'stockBase': base,
        'otaVersion': os_version(base),
        'folder': 'Strix_OS_' + base,
        'feedVersionName': feed_version_name(base),
        'feedVersionCode': int(feed_version_name(base)),
        'acceptOsVersions': [os_version(v) for v in accept],
        'acceptQueryCodes': [query_code(v) for v in accept],
    }
    return pins, members, policy


def objc(value):
    if isinstance(value, bool):
        raise TypeError('no booleans')
    if isinstance(value, int):
        return '@%d' % value
    if isinstance(value, str):
        return '@' + json.dumps(value)
    if isinstance(value, list):
        return '@[' + ','.join(objc(v) for v in value) + ']'
    if isinstance(value, dict):
        return '@{' + ','.join(objc(k) + ':' + objc(v) for k, v in value.items()) + '}'
    raise TypeError(type(value))


def block(name, pins, members, policy):
    fields = [
        ('NAME', 'name'), ('ZIP_BYTES', 'zipBytes'), ('ZIP_SHA256', 'zipSHA256'),
        ('AP_BYTES', 'apBytes'), ('AP_SHA256', 'apSHA256'), ('AP_MD5', 'apMD5'),
        ('MANIFEST_BYTES', 'manifestBytes'), ('MANIFEST_SHA256', 'manifestSHA256'),
        ('PAYLOAD_BYTES', 'payloadBytes'), ('PAYLOAD_SLICES', 'payloadSlices'),
    ]
    lines = []
    for macro, key in fields:
        value = pins[key]
        literal = f'{value}u' if isinstance(value, int) else '@' + json.dumps(value)
        lines.append(f'#define TIO_FW_{macro} {literal}')
    marker = 'ota release=%s; firmware=%s; zip=%s; accepts %s; target %s' % (
        name, pins['name'], pins['zipSHA256'], ', '.join(policy['acceptOsVersions']), policy['otaVersion'])
    lines += [
        '#define TIO_FW_RELEASE @' + json.dumps(name),
        '#define TIO_FW_RELEASE_MARKER ' + json.dumps(marker),
        '#define TIO_FW_BASE @' + json.dumps(policy['stockBase']),
        '#define TIO_FW_OTA_VERSION @' + json.dumps(policy['otaVersion']),
        '#define TIO_FW_OTA_FOLDER @' + json.dumps(policy['folder']),
        '#define TIO_FW_FEED_VERSION_NAME @' + json.dumps(policy['feedVersionName']),
        '#define TIO_FW_FEED_VERSION_CODE %d' % policy['feedVersionCode'],
        '#define TIO_FW_ACCEPTED_OS_VERSIONS ' + objc(policy['acceptOsVersions']),
        '#define TIO_FW_ACCEPTED_QUERY_CODES ' + objc(policy['acceptQueryCodes']),
        '#define TIO_FW_ACCEPTED_VERSIONS_TEXT @' + json.dumps(' / '.join(v[len('Strix OS '):] for v in policy['acceptOsVersions'])),
        '#define TIO_FW_MEMBER_PINS ' + objc(members),
    ]
    return lines


def render(releases, computed):
    named = [n for n in releases if n != 'default']
    lines = ['// Generated by phone_pins.py from releases.json and the exact release ZIPs; do not edit.',
             '// No TIO_RELEASE_<NAME> define selects the default release; turbo-package.sh --release cN defines one.',
             '#ifndef TIO_FIRMWARE_PINS_H', '#define TIO_FIRMWARE_PINS_H']
    if named:
        lines.append('#if ' + ' + '.join('defined(TIO_RELEASE_%s)' % n.upper() for n in named) + ' > 1')
        lines += ['#error "more than one TIO_RELEASE_<NAME> defined"', '#endif']
    for i, name in enumerate(named):
        lines.append(('#if' if i == 0 else '#elif') + ' defined(TIO_RELEASE_%s)' % name.upper())
        lines += block(name, *computed[name])
    if named:
        lines.append('#else')
    lines += block('default', *computed['default'])
    if named:
        lines.append('#endif')
    lines.extend(['#endif', ''])
    outputs = {'FirmwarePins.h': '\n'.join(lines).encode('utf-8'),
               'firmware-pins.json': (json.dumps(computed['default'][0], indent=2) + '\n').encode('utf-8')}
    for name in named:
        pins, _members, policy = computed[name]
        outputs['firmware-pins-%s.json' % name] = (json.dumps({**pins, **policy}, indent=2) + '\n').encode('utf-8')
    return outputs


def compute_all(releases, inputs):
    build = load_build()
    return {name: release_pins(name, spec, resolve(spec, inputs), build) for name, spec in releases.items()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--releases', type=Path, default=ED/'releases.json')
    parser.add_argument('--inputs', type=Path, help='$TURBO_INPUTS: the release ZIP paths in releases.json are relative to it')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--write', type=Path, metavar='DIR')
    mode.add_argument('--check', type=Path, metavar='DIR')
    mode.add_argument('--resolve', metavar='RELEASE', help='print the checked path of that release ZIP')
    mode.add_argument('--tree-release', action='store_true', help="print the release whose ZIP is the tree's build")
    mode.add_argument('--verify', metavar='RELEASE', help='check --zip is that release and matches its firmware-pins JSON in --dir')
    parser.add_argument('--zip', type=Path)
    parser.add_argument('--dir', type=Path, default=ED)
    args = parser.parse_args(argv)
    try:
        releases = load_releases(args.releases)
        if args.tree_release:
            tree = json.loads((FW/'build-inputs.json').read_text())
            found = [n for n, s in releases.items() if s['firmware'] == release_label() and s['zip']['sha256'] == tree['archive']['sha256']]
            if not found:
                raise ValueError('no release carries the tree build ' + release_label())
            print(found[0])
            return 0
        if args.resolve is not None:
            if args.inputs is None or args.resolve not in releases:
                raise ValueError('--resolve needs --inputs and a known release')
            print(resolve(releases[args.resolve], args.inputs))
            return 0
        if args.verify is not None:
            if args.zip is None or args.verify not in releases:
                raise ValueError('--verify needs --zip and a known release')
            pins, _members, policy = release_pins(args.verify, releases[args.verify], args.zip)
            name = 'firmware-pins.json' if args.verify == 'default' else 'firmware-pins-%s.json' % args.verify
            want = pins if args.verify == 'default' else {**pins, **policy}
            if json.loads((args.dir/name).read_text()) != want:
                print('PHONEPINS_MISMATCH: ' + name, file=sys.stderr)
                return 1
            print('PHONEPINS_RELEASE_OK ' + args.verify)
            return 0
        if args.inputs is None:
            raise ValueError('--write/--check need --inputs')
        outputs = render(releases, compute_all(releases, args.inputs))
        if args.write is not None:
            args.write.mkdir(parents=True, exist_ok=True)
            for name, data in outputs.items():
                (args.write / name).write_bytes(data)
            print('PHONEPINS_WRITTEN')
            return 0
        failures = []
        for name, data in outputs.items():
            path = args.check / name
            if not path.is_file() or path.read_bytes() != data:
                failures.append(name)
        stale = sorted(p.name for p in args.check.glob('firmware-pins-*.json') if p.name not in outputs)
        if failures or stale:
            print('PHONEPINS_MISMATCH: ' + ', '.join(failures + ['stale ' + s for s in stale]), file=sys.stderr)
            return 1
        print('PHONEPINS_OK ' + ', '.join(releases))
        return 0
    except (OSError, ValueError, KeyError, AssertionError, zipfile.BadZipFile, RuntimeError) as error:
        print(f'PHONEPINS_ERROR: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
