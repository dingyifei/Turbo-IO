#!/usr/bin/env python3
"""Check the WP5 preview matrix produced by wp5-screens.sh."""
import hashlib
import json
import sys
from pathlib import Path

FIXTURES = (
    'unavailable', 'missing-key', 'auto-on', 'ready-download', 'download-open',
    'stale-version', 'ready-authorize', 'authorized', 'installing', 'failed',
)
STEMS = ('hub', 'hub-dev', 'more', 'lifelog') + tuple(f'ota-{name}' for name in FIXTURES)
EXPECTED_OTA = {
    'missing-key': (1, False),
    'auto-on': (1, False),
    'ready-download': (2, True),
    'download-open': (2, True),
    'stale-version': (3, False),
    'ready-authorize': (3, True),
    'authorized': (3, True),
    'installing': (3, False),
    'failed': (3, True),
}


def has_cjk(value):
    return any(0x4E00 <= ord(char) <= 0x9FFF for char in str(value))


def check(out):
    failures = []
    reports = {}
    expected_names = {f'{stem}-{lang}' for stem in STEMS for lang in ('en', 'zh')}
    found_png = {path.stem for path in out.glob('*.png')}
    found_json = {path.stem for path in out.glob('*.json') if path.name != 'ui-report.json'}
    if found_png != expected_names:
        failures.append(f'PNG matrix mismatch: missing={sorted(expected_names-found_png)} extra={sorted(found_png-expected_names)}')
    if found_json != expected_names:
        failures.append(f'JSON matrix mismatch: missing={sorted(expected_names-found_json)} extra={sorted(found_json-expected_names)}')
    for name in sorted(expected_names):
        png = out / f'{name}.png'
        report_file = out / f'{name}.json'
        if png.is_file() and png.stat().st_size <= 40 * 1024:
            failures.append(f'{name}: PNG is not larger than 40 KiB')
        if not report_file.is_file():
            continue
        try:
            report = json.loads(report_file.read_text())
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            failures.append(f'{name}: unreadable JSON: {error}')
            continue
        if not isinstance(report, dict):
            failures.append(f'{name}: report is not an object')
            continue
        if 'TMG2' in json.dumps(report, ensure_ascii=False):
            failures.append(f'{name}: contains TMG2')
        sections = report.get('sections', [])
        buttons = report.get('buttons', [])
        if not isinstance(sections, list) or not isinstance(buttons, list):
            failures.append(f'{name}: sections/buttons are not arrays')
            continue
        if any(not isinstance(section, dict) or not isinstance(section.get('rows', []), list) for section in sections):
            failures.append(f'{name}: malformed section rows')
            continue
        if any(not isinstance(button, dict) for button in buttons):
            failures.append(f'{name}: malformed button')
            continue
        reports[name] = report
        lang = name.rsplit('-', 1)[-1]
        if lang == 'en':
            strings = [report.get('screen', ''), report.get('subtitle', '')]
            strings += [section.get('title', '') for section in sections if isinstance(section, dict)]
            strings += [row.get(field, '') for section in sections if isinstance(section, dict)
                        for row in section.get('rows', []) if isinstance(row, dict)
                        for field in ('title', 'status')]
            strings += [button.get('title', '') for button in buttons]
            strings += [step.get('label', '') for step in report.get('steps', []) if isinstance(step, dict)]
            if any(has_cjk(value) for value in strings):
                failures.append(f'{name}: CJK in English UI text')
        else:
            titles = [section.get('title', '') for section in sections if isinstance(section, dict)]
            if not any(titles):
                failures.append(f'{name}: no non-empty section title')
            if any(title and not has_cjk(title) for title in titles):
                failures.append(f'{name}: section title lacks CJK')
        limit = 40 if lang == 'en' else 20
        for section in sections:
            if not isinstance(section, dict):
                failures.append(f'{name}: malformed section')
                continue
            for row in section.get('rows', []):
                if not isinstance(row, dict):
                    failures.append(f'{name}: malformed row')
                    continue
                status = row.get('status', '')
                if len(status) > limit:
                    failures.append(f'{name}: status too long for {row.get("id", "")}: {len(status)}>{limit}')

    for lang in ('en', 'zh'):
        first = reports.get(f'hub-{lang}')
        expanded = reports.get(f'hub-dev-{lang}')
        expected = ['Glasses', 'Assistant', 'Media', 'Developer'] if lang == 'en' else ['眼镜', '助手', '媒体', '开发者']
        for label, report in (('hub', first), ('hub-dev', expanded)):
            if not report:
                continue
            sections = report.get('sections', [])
            titles = [section.get('title', '') for section in sections]
            if titles != expected:
                failures.append(f'{label}-{lang}: section order {titles!r} != {expected!r}')
            if len(sections) == 4:
                developer_rows = sections[3].get('rows', [])
                if (label == 'hub' and developer_rows) or (label == 'hub-dev' and not developer_rows):
                    failures.append(f'{label}-{lang}: Developer collapse state incorrect')
                glasses_ids = [row.get('id') for row in sections[0].get('rows', [])]
                if 'hub-language' not in glasses_ids:
                    failures.append(f'{label}-{lang}: Language row missing from Glasses')
        seen = set()
        for label in ('hub-dev', 'more', 'lifelog'):
            report = reports.get(f'{label}-{lang}')
            if not report:
                continue
            for section in report.get('sections', []):
                for row in section.get('rows', []):
                    identifier = row.get('id', '')
                    if not identifier.startswith('hub-'):
                        failures.append(f'{label}-{lang}: non-hub row id {identifier!r}')
                    if identifier in seen:
                        failures.append(f'{label}-{lang}: duplicate route {identifier!r}')
                    seen.add(identifier)

        for fixture in FIXTURES:
            name = f'ota-{fixture}-{lang}'
            report = reports.get(name)
            if not report:
                continue
            if 'TMG3' not in report.get('subtitle', ''):
                failures.append(f'{name}: subtitle does not name TMG3')
            steps = report.get('steps', [])
            buttons = {button.get('id'): button for button in report.get('buttons', [])}
            primary = buttons.get('ota-primary')
            if fixture == 'unavailable':
                if steps:
                    failures.append(f'{name}: unavailable has visible steps')
                if primary and not primary.get('hidden'):
                    failures.append(f'{name}: unavailable has visible primary button')
                continue
            if [step.get('id') for step in steps] != ['ota-step-1', 'ota-step-2', 'ota-step-3']:
                failures.append(f'{name}: expected exactly three ordered steps')
            selected = [index for index, step in enumerate(steps, 1) if step.get('selected')]
            expected_step, expected_enabled = EXPECTED_OTA[fixture]
            if selected != [expected_step]:
                failures.append(f'{name}: selected step {selected} != {[expected_step]}')
            if not primary or primary.get('hidden') or primary.get('enabled') is not expected_enabled:
                failures.append(f'{name}: primary visibility/enabled state incorrect')
            if fixture == 'authorized':
                secondary = buttons.get('ota-secondary')
                if not secondary or secondary.get('hidden'):
                    failures.append(f'{name}: revoke button not visible')

    en_png = out / 'hub-en.png'
    zh_png = out / 'hub-zh.png'
    if en_png.is_file() and zh_png.is_file():
        if hashlib.md5(en_png.read_bytes()).digest() == hashlib.md5(zh_png.read_bytes()).digest():
            failures.append('hub-en and hub-zh screenshots are identical')

    summary = {'pass': not failures, 'cases': len(expected_names), 'checkedReports': len(reports), 'failures': failures}
    out.mkdir(parents=True, exist_ok=True)
    (out / 'ui-report.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False) + '\n')
    if failures:
        print('WP5 CHECK FAIL')
        for failure in failures:
            print(f'- {failure}')
        return 1
    print('WP5 CHECK PASS: 28 PNGs and 28 reports')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: wp5-check.py SHOTS_DIRECTORY', file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(check(Path(sys.argv[1])))
