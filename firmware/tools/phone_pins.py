#!/usr/bin/env python3
"""Generate the phone's firmware pins for every release configuration from the exact release ZIPs.

Input: ios-addon/releases.json (one entry per phone release, named cN: the stock base its
packages are built on (1.0.6.11, the only base a phone release may have), its hosts, which must be exactly
["1021-full"], the 1.0.21 full host, and its packages: a list of {label, zip {input, bytes, sha256}, acceptCurrent},
the ZIP's path under $TURBO_INPUTS with its size and SHA-256 and the glasses versions that package may be flashed
over). The first package is the default the phone selects at every launch and must be a TMG build; a second one, if
listed, must be labelled STOCK-<base>. Any other label is refused.
For every package this reads the ZIP, checks its manifest, its pinned identity, and that AP, APC1 and BTH all report
the base (build.py's core_identity). A TMG package's non-AP members must be byte-for-byte the members of the stock ZIP
of its base (except nuttx_bth.bin in the package whose label is the tree's label, when build-inputs.json has a bth
block: it must be the BTH image pinned there) and its AP must differ from the stock AP; the TMG package whose label is the tree's label (../RELEASE)
must also be the ZIP in ../build-inputs.json, on the same stock base. A STOCK-<base> package must equal the base's
stock ZIP in every member, the AP and the manifest included: it is the stock package and nothing else. An emulator-only build is never a phone release: a base whose
phoneRelease is false, an emuOnly tree's label or ZIP, and an -EMU-ONLY- ZIP name are all refused, in every mode
(--resolve included) before the ZIP is read and before anything is written. Every mode, --resolve included, also
refuses a ZIP whose own package shape or cores (AP, APC1, BTH) are not on its stock base, so an older emulator-only
ZIP listed under a phone base is refused even when no name, label or tree record marks it. An older emulator-only
ZIP that is a valid build on a base that has since become a phone release base (the TMG12 candidates 1 to 3 on
1.0.6.11) is refused by its pinned SHA-256 (SUPERSEDED_ZIPS), in every mode, before the ZIP is read. So is the first
TMG17 ZIP, a valid 1.0.6.11 phone build made before the fix in tmg17(2).

Output (--write DIR / --check DIR):
  FirmwarePins.h          one block per release, chosen at compile time by TIO_RELEASE_<NAME>. With no define, the
                          only release is chosen when releases.json has exactly one; with several, no define is a
                          compile error. A block holds the release-wide values (TIO_FW_RELEASE, the marker, the base,
                          the type-5 OtaVersion, the folder and the feed's versionName/versionCode) and TIO_FW_PACKAGES,
                          one entry per package in order: its ZIP size and SHA-256, AP and manifest pins, payload
                          totals, member pins, accepted versions and query codes, OtaVersion and bundle resource name.
  firmware-pins-<n>.json  the default package's pins with the release's policy at the top level, as before, and
                          "packages", every package's entry (there is no firmware-pins.json)

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
ED = ROOT/'ios-addon'
RELEASE_NAME = re.compile(r'c[0-9]+')
VERSION = re.compile(r'([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)')
# The one host name (turbo-package.sh --host) a release may list: the 1.0.21 full host.
HOSTS = ('1021-full',)
# The one stock base a phone release may be built on. The firmware tree's own stock-base knowledge stays in build.py.
RELEASE_BASES = ('1.0.6.11',)
TMG_LABEL = re.compile(r'TMG[0-9]+')
# The fixed name each kind of package has inside the app bundle (package.mjs bundles it there, the addon reads it
# back); the TMG name is the one the bundled release ZIP has always had.
PACKAGE_RESOURCES = {'TMG': 'TurboWeReadCandidate.zip', 'STOCK': 'TurboStockFirmware.zip'}
# ZIPs that must never become a phone release, by SHA-256: the emulator-only TMG12 candidates 1 to 3 on stock
# 1.0.6.11, which the TMG12 release (candidate 4's bytes) replaced. Their own bytes are a valid 1.0.6.11 build, so
# once 1.0.6.11 became a phone release base only this list refuses them under a label other than the tree's. Also
# the first TMG17 ZIP, built before the fix in tmg17(2): a valid 1.0.6.11 phone build that only this list refuses
# (RELEASE.md: "Never flash the first TMG17 ZIP").
SUPERSEDED_ZIPS = {
    'eacb5dcabc513570978edc31a47d3304b2bc361036d5b171e15bd4c3c281e9b5': 'TMG12 emulator-only candidate 1',
    'a8b9de49f2d5dc45311c5b19d61f96d9cc1acb2ed81ab55fb14534c0b68ad849': 'TMG12 emulator-only candidate 2',
    '007f1dd77b5b93eba3451e4df2ca6ba18264cee1444d9b97b40355b60f103325': 'TMG12 emulator-only candidate 3',
    'dbe8cfbb7e8733ffea62f144211bd3a0ac0716f61d6f94c7c31414760d1b7b87': 'the first TMG17 ZIP, built before the fix in tmg17(2)',
}


def release_label(root=None):
    """The one place the tree's release label comes from: RELEASE at the tree root. Never the folder name."""
    label = ((root or Path(__file__).resolve().parents[1]) / 'RELEASE').read_text().strip()
    if not re.fullmatch(r'TMG[0-9]+', label):
        raise ValueError('RELEASE must hold one label such as TMG8')
    return label


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_archive(raw, base):
    """The manifest and the payloads of a release ZIP, every row checked against its bytes. The base is required: the
    package shape (payload names and row count) is the one build.package_shape(base) names."""
    shape = load_build().package_shape(base)
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        names = z.namelist()
        if len(names) != len(set(names)):
            raise ValueError('duplicate ZIP member')
        manifest_data = z.read('OtaFileInfo.json')
        manifest = json.loads(manifest_data)
        if not isinstance(manifest, list) or len(manifest) != shape['manifestRows']:
            raise ValueError('expected %d payload manifest rows for stock %s' % (shape['manifestRows'], base))
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
        if set(payloads) != set(shape['payloads']):
            raise ValueError('ZIP payload names are not the stock %s payloads' % base)
    return manifest_data, payloads


def pins_for(archive, name, base):
    """The identity pins of one ZIP (the first ten fields of firmware-pins-<n>.json); the base is the stock base it is built on."""
    raw = Path(archive).read_bytes()
    manifest_data, payloads = read_archive(raw, base)
    ap = payloads['nuttx_ap.bin']
    return {
        'name': name,
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


def stock_zip(base, inputs=None):
    """The stock ZIP of a base: build.stock_zip_path is the one resolver (a repository file, or one under $TURBO_INPUTS)."""
    return load_build().stock_zip_path(base, inputs)


def load_build(root=FW):
    spec = importlib.util.spec_from_file_location('phone_pins_build', root/'build.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def package_kind(label, base):
    """TMG for a TMG build, STOCK for the base's stock package (label STOCK-<base>); any other label is refused."""
    if isinstance(label, str) and TMG_LABEL.fullmatch(label):
        return 'TMG'
    if label == 'STOCK-' + base:
        return 'STOCK'
    raise ValueError('unknown package label ' + repr(label) + ': a package is TMGn or STOCK-' + base)


def load_releases(path):
    data = json.loads(Path(path).read_text())
    if data.get('schema') != 1 or not isinstance(data.get('releases'), dict) or not data['releases']:
        raise ValueError('releases.json: schema 1 with at least one release required')
    for name, spec in data['releases'].items():
        if not RELEASE_NAME.fullmatch(name):
            raise ValueError('release name must be cN: ' + name)
        if not isinstance(spec, dict):
            raise ValueError(name + ': a release is an object')
        version_parts(spec.get('stockBase'))
        if spec['stockBase'] not in RELEASE_BASES:
            raise ValueError(name + ': a phone release is built only on stock ' + ' or '.join(RELEASE_BASES))
        # The release's ZIP and versions live in its packages; the single-package keys of the old schema are refused.
        for old in ('firmware', 'zip', 'acceptCurrent'):
            if old in spec:
                raise ValueError(name + ': ' + old + ' belongs to a package now (packages)')
        packages = spec.get('packages')
        if not isinstance(packages, list) or not 1 <= len(packages) <= 2:
            raise ValueError(name + ': packages must list one TMG package and at most one STOCK package')
        kinds = []
        for package in packages:
            if not isinstance(package, dict):
                raise ValueError(name + ': a package is an object')
            kinds.append(package_kind(package.get('label'), spec['stockBase']))
            zip_spec = package.get('zip', {})
            if (not isinstance(zip_spec, dict) or not isinstance(zip_spec.get('input'), str) or zip_spec['input'].startswith(('/', '~'))
                    or '..' in zip_spec['input'] or type(zip_spec.get('bytes')) is not int
                    or not re.fullmatch(r'[0-9a-f]{64}', zip_spec.get('sha256', ''))):
                raise ValueError(name + ': ' + package['label'] + ': zip needs a relative input path, bytes and sha256')
            accept = package.get('acceptCurrent')
            if not isinstance(accept, list) or not accept or len(set(accept)) != len(accept):
                raise ValueError(name + ': ' + package['label'] + ': acceptCurrent must list distinct versions')
            for version in accept:
                version_parts(version)
        # The first package is the default the phone selects at launch: always the TMG build. A second one is the stock package.
        if kinds[0] != 'TMG' or kinds[1:] not in ([], ['STOCK']):
            raise ValueError(name + ': the first package must be a TMG build and a second one must be STOCK-' + spec['stockBase'])
        if len({p['zip']['sha256'] for p in packages}) != len(packages):
            raise ValueError(name + ': two packages share one ZIP')
        if spec.get('hosts') != list(HOSTS):
            raise ValueError(name + ': hosts must be exactly ' + json.dumps(list(HOSTS)))
    return data['releases']


def packages(spec):
    """Each package of a release as the checks below read it: its label (as firmware), the release's stock base, its
    ZIP and accepted versions, and its kind (TMG or STOCK)."""
    return [{'firmware': p['label'], 'stockBase': spec['stockBase'], 'zip': p['zip'], 'acceptCurrent': p['acceptCurrent'],
             'kind': package_kind(p['label'], spec['stockBase'])} for p in spec['packages']]


def package_spec(spec, label=None):
    """The package of a release with that label; with no label, the first (the default)."""
    found = [p for p in packages(spec) if label is None or p['firmware'] == label]
    if not found:
        raise ValueError('no package ' + repr(label) + ' in this release')
    return found[0]


def refuse_emulator_only(name, spec, build=None, tree_spec=None, tree_label=None):
    """An emulator-only build never becomes a phone release: not on a base that has none, not under an EMU name, and
    not under an emuOnly tree's label or ZIP. Every mode runs this itself, before it reads the release ZIP."""
    build = build or load_build()
    tree_spec = tree_spec if tree_spec is not None else json.loads((FW/'build-inputs.json').read_text())
    tree_label = tree_label or release_label()
    if not build.package_shape(spec['stockBase'])['phoneRelease']:
        raise ValueError(name + ': stock ' + spec['stockBase'] + ' has no phone release (emulator only)')
    if '-EMU-ONLY-' in spec['zip']['input']:
        raise ValueError(name + ': an -EMU-ONLY- ZIP cannot be a phone release')
    # Every mode checks the ZIP's bytes against this pinned SHA-256 before using them, so refusing the pin is enough.
    if spec['zip']['sha256'] in SUPERSEDED_ZIPS:
        raise ValueError(name + ': this ZIP is superseded (' + SUPERSEDED_ZIPS[spec['zip']['sha256']] + ') and cannot be a phone release')
    if build.emu_only(tree_spec):
        if spec['firmware'] == tree_label:
            raise ValueError(name + ': ' + tree_label + ' is the label of an emuOnly tree')
        if spec['zip']['sha256'] == tree_spec['archive']['sha256']:
            raise ValueError(name + ': this is the ZIP of an emuOnly tree')


def refuse_other_base(name, raw, base, build):
    """The ZIP's own bytes must be a build on its stock base: the base's package shape, and AP, APC1 and BTH each
    reporting that base (build.core_identity). This catches an emulator-only ZIP that no longer matches any name,
    label or tree record, such as an older candidate. It needs no stock ZIP."""
    try:
        manifest_data, payloads = read_archive(raw, base)
        build.core_identity(payloads, base)
    except (ValueError, AssertionError, KeyError, zipfile.BadZipFile) as error:
        raise ValueError(name + ': the ZIP is not a build on stock ' + base + ': ' + str(error)) from error
    return manifest_data, payloads


def resolve(spec, inputs, name='release', build=None, tree_spec=None, tree_label=None):
    """The release ZIP under $TURBO_INPUTS, refused if it is an emulator-only build, unless its size and SHA-256 are
    the pinned ones, or unless its own shape and cores are on its stock base."""
    build = build or load_build()
    refuse_emulator_only(name, spec, build, tree_spec, tree_label)
    path = Path(inputs)/spec['zip']['input']
    raw = path.read_bytes()
    if len(raw) != spec['zip']['bytes'] or sha256(raw) != spec['zip']['sha256']:
        raise ValueError('release ZIP does not match its pin: ' + spec['zip']['input'])
    refuse_other_base(name, raw, spec['stockBase'], build)
    return path


def release_pins(name, spec, archive, build=None, tree_spec=None, tree_label=None):
    """Everything the phone compiles in for one package of a release (spec: one entry of packages()), derived from
    its ZIP and checked against its stock base."""
    base = spec['stockBase']
    kind = package_kind(spec['firmware'], base)
    build = build or load_build()
    tree_spec = tree_spec if tree_spec is not None else json.loads((FW/'build-inputs.json').read_text())
    tree_label = tree_label or release_label()
    refuse_emulator_only(name, spec, build, tree_spec, tree_label)
    raw = Path(archive).read_bytes()
    if len(raw) != spec['zip']['bytes'] or sha256(raw) != spec['zip']['sha256']:
        raise ValueError(name + ': ZIP does not match releases.json')
    manifest_data, payloads = refuse_other_base(name, raw, base, build)
    stock_raw = stock_zip(base).read_bytes()
    # For a STOCK package the stock ZIP must be the one build-inputs.json records for the tree's base, so the package is not only compared with itself.
    if kind == 'STOCK' and tree_spec.get('stockBase') == base and sha256(stock_raw) != tree_spec.get('stockZIP'):
        raise ValueError(name + ': the stock ' + base + ' ZIP is not the one recorded in build-inputs.json')
    stock_manifest, stock_payloads = read_archive(stock_raw, base)
    if set(stock_payloads) != set(payloads):
        raise ValueError(name + ': member names differ from stock ' + base)
    # A TMG package changes the AP; the tree's own package may also change the Bluetooth core (build-inputs.json bth),
    # and then only to the BTH image the tree pins.
    changed = set() if kind == 'STOCK' else {'nuttx_ap.bin'}
    if kind == 'TMG' and spec['firmware'] == tree_label and 'bth' in tree_spec:
        changed.add('nuttx_bth.bin')
        if sha256(payloads['nuttx_bth.bin']) != tree_spec['bth']['BTHSHA256']:
            raise ValueError(name + ': nuttx_bth.bin is not the BTH image build-inputs.json pins')
    for member, data in payloads.items():
        if member not in changed and data != stock_payloads[member]:
            raise ValueError(name + ': ' + member + ' is not the stock ' + base + ' member')
    if kind == 'STOCK' and manifest_data != stock_manifest:
        raise ValueError(name + ': OtaFileInfo.json is not the stock ' + base + ' manifest')
    # A TMG package carries its own AP: the stock package under a TMG label is refused.
    if kind == 'TMG' and payloads['nuttx_ap.bin'] == stock_payloads['nuttx_ap.bin']:
        raise ValueError(name + ': ' + spec['firmware'] + ' carries the stock ' + base + ' AP; a TMG package must be a TMG build')
    # Never mix cores, and the base in releases.json is the one the ZIP's own cores report.
    if build.core_identity(payloads, base) != build.core_identity(stock_payloads, base):
        raise ValueError(name + ': cores differ from stock ' + base)
    if kind == 'TMG' and spec['firmware'] == tree_label and (spec['zip']['sha256'] != tree_spec['archive']['sha256'] or base != tree_spec['stockBase']):
        raise ValueError(name + ': ' + tree_label + ' is the tree label but this is not the ZIP in build-inputs.json')
    pins = pins_for(archive, spec['firmware'], base)
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


def package_entry(pins, policy):
    """One package as firmware-pins-<n>.json "packages" records it: its pins, kind, bundle resource, type-5 OtaVersion
    and accepted versions (the release-wide values stay at the top level)."""
    kind = package_kind(pins['name'], policy['stockBase'])
    return {**pins, 'kind': kind, 'resource': PACKAGE_RESOURCES[kind], 'otaVersion': policy['otaVersion'],
            'acceptOsVersions': policy['acceptOsVersions'], 'acceptQueryCodes': policy['acceptQueryCodes']}


def release_json(computed):
    """firmware-pins-<n>.json: the default package's pins and the release policy at the top level, and every package."""
    pins, _members, policy = computed[0]
    return {**pins, **policy, 'packages': [package_entry(p, q) for p, _m, q in computed]}


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


def block(name, computed):
    """One release's lines of FirmwarePins.h; computed is [(pins, members, policy)] per package, the default first."""
    pins, _members, policy = computed[0]
    # The first package's part keeps the marker's old shape; each other package follows as "; package=<label>; ...".
    marker = 'ota release=%s; firmware=%s; zip=%s; accepts %s; target %s' % (
        name, pins['name'], pins['zipSHA256'], ', '.join(policy['acceptOsVersions']), policy['otaVersion'])
    for other, _m, other_policy in computed[1:]:
        marker += '; package=%s; zip=%s; accepts %s; target %s' % (
            other['name'], other['zipSHA256'], ', '.join(other_policy['acceptOsVersions']), other_policy['otaVersion'])
    entries = []
    for p, members, q in computed:
        entry = package_entry(p, q)
        entry['acceptVersionsText'] = ' / '.join(v[len('Strix OS '):] for v in q['acceptOsVersions'])
        entry['memberPins'] = members
        entries.append(entry)
    return [
        '#define TIO_FW_RELEASE @' + json.dumps(name),
        '#define TIO_FW_RELEASE_MARKER ' + json.dumps(marker),
        '#define TIO_FW_BASE @' + json.dumps(policy['stockBase']),
        '#define TIO_FW_OTA_VERSION @' + json.dumps(policy['otaVersion']),
        '#define TIO_FW_OTA_FOLDER @' + json.dumps(policy['folder']),
        '#define TIO_FW_FEED_VERSION_NAME @' + json.dumps(policy['feedVersionName']),
        '#define TIO_FW_FEED_VERSION_CODE %d' % policy['feedVersionCode'],
        # The default package (the first), for the uses outside the flash path: the firmware export and the hub.
        '#define TIO_FW_DEFAULT_NAME @' + json.dumps(pins['name']),
        '#define TIO_FW_DEFAULT_ZIP_SHA256 @' + json.dumps(pins['zipSHA256']),
        '#define TIO_FW_PACKAGE_COUNT %du' % len(entries),
        '#define TIO_FW_PACKAGES ' + objc(entries),
    ]


def render(releases, computed):
    names = list(releases)
    if not names:
        raise ValueError('no release to render')
    defined = ['defined(TIO_RELEASE_%s)' % n.upper() for n in names]
    lines = ['// Generated by phone_pins.py from releases.json and the exact release ZIPs; do not edit.',
             '// TIO_RELEASE_<NAME> selects a release (build.sh TIO_RELEASE=cN, turbo-package.sh --release cN). With no',
             '// define, the only release is selected when there is one; with several, no define is a compile error.',
             '#ifndef TIO_FIRMWARE_PINS_H', '#define TIO_FIRMWARE_PINS_H']
    if len(names) > 1:
        lines.append('#if ' + ' + '.join(defined) + ' > 1')
        lines += ['#error "more than one TIO_RELEASE_<NAME> defined"', '#endif']
    lines.append('#if ' + ' && '.join('!' + d for d in defined))
    if len(names) == 1:
        lines.append('#define TIO_RELEASE_%s 1' % names[0].upper())
    else:
        lines.append('#error "several releases: define one TIO_RELEASE_<NAME>"')
    lines.append('#endif')
    for i, name in enumerate(names):
        lines.append(('#if' if i == 0 else '#elif') + ' ' + defined[i])
        lines += block(name, computed[name])
    lines.append('#endif')
    lines.extend(['#endif', ''])
    outputs = {'FirmwarePins.h': '\n'.join(lines).encode('utf-8')}
    for name in names:
        outputs['firmware-pins-%s.json' % name] = (json.dumps(release_json(computed[name]), indent=2) + '\n').encode('utf-8')
    return outputs


def compute_all(releases, inputs):
    """Per release, [(pins, members, policy)] for every package in order, each ZIP resolved and checked."""
    build = load_build()
    return {name: [release_pins(name, p, resolve(p, inputs, name, build), build) for p in packages(spec)]
            for name, spec in releases.items()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--releases', type=Path, default=ED/'releases.json')
    parser.add_argument('--inputs', type=Path, help='$TURBO_INPUTS: the release ZIP paths in releases.json are relative to it')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--write', type=Path, metavar='DIR')
    mode.add_argument('--check', type=Path, metavar='DIR')
    mode.add_argument('--resolve', metavar='RELEASE', help="print the checked path of that release's ZIP (the first package, or --package)")
    mode.add_argument('--tree-release', action='store_true', help="print the release whose ZIP is the tree's build")
    mode.add_argument('--verify', metavar='RELEASE', help='check --zip is that release (the first package, or --package) and matches its firmware-pins JSON in --dir')
    parser.add_argument('--package', metavar='LABEL', help='with --resolve or --verify: the package of the release with this label (for example STOCK-1.0.6.11)')
    parser.add_argument('--zip', type=Path)
    parser.add_argument('--dir', type=Path, default=ED)
    args = parser.parse_args(argv)
    try:
        if args.tree_release:
            tree = json.loads((FW/'build-inputs.json').read_text())
            if load_build().emu_only(tree):
                raise ValueError('--tree-release: emuOnly tree has no phone release')
        if args.package is not None and args.resolve is None and args.verify is None:
            raise ValueError('--package goes with --resolve or --verify')
        releases = load_releases(args.releases)
        if args.tree_release:
            found = [n for n, s in releases.items() if package_spec(s)['firmware'] == release_label() and package_spec(s)['zip']['sha256'] == tree['archive']['sha256']]
            if not found:
                raise ValueError('no release carries the tree build ' + release_label())
            print(found[0])
            return 0
        if args.resolve is not None:
            if args.inputs is None or args.resolve not in releases:
                raise ValueError('--resolve needs --inputs and a known release')
            print(resolve(package_spec(releases[args.resolve], args.package), args.inputs, args.resolve))
            return 0
        if args.verify is not None:
            if args.zip is None or args.verify not in releases:
                raise ValueError('--verify needs --zip and a known release')
            spec = releases[args.verify]
            index = [p['firmware'] for p in packages(spec)].index(package_spec(spec, args.package)['firmware'])
            pins, _members, policy = release_pins(args.verify, packages(spec)[index], args.zip)
            name = 'firmware-pins-%s.json' % args.verify
            recorded = json.loads((args.dir/name).read_text())
            entries = recorded.get('packages') if isinstance(recorded, dict) else None
            top = {k: v for k, v in recorded.items() if k != 'packages'} if isinstance(recorded, dict) else None
            # The package's own entry, and for the default package also the top level, must be what the ZIP gives.
            if (not isinstance(entries, list) or len(entries) != len(spec['packages']) or entries[index] != package_entry(pins, policy)
                    or (index == 0 and top != {**pins, **policy})):
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
        # Any other firmware-pins*.json (a removed release, or the old firmware-pins.json) is stale.
        stale = sorted(p.name for p in args.check.glob('firmware-pins*.json') if p.name not in outputs)
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
