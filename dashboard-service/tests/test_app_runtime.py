"""TMG7 mini-app contract: TAP1 stays wire-compatible, buttons are caret focus items, 14 px text is retired."""
import base64
import hashlib
import json
import zipfile
from pathlib import Path
from xml.etree import ElementTree

from turbo_dashboard.app_examples import examples
from turbo_dashboard.app_package import read_package, validate_app
from turbo_dashboard.app_wire import encode
from turbo_dashboard.contracts import LENS_MIN_FONT, TEMPLATES, render_font
from turbo_dashboard.gallery import RECIPES, snapshot_doc
from turbo_dashboard.preview import render

FIXTURES = Path(__file__).parent / 'fixtures'
GALLERY = Path(__file__).resolve().parents[2] / 'app-gallery'
SVG = '{http://www.w3.org/2000/svg}'


def fixture(name):
    """Binary test fixtures are committed as base64 text (the source audit rejects committed binaries)."""
    return base64.b64decode((FIXTURES / (name + '.b64')).read_text())


def legacy():
    return fixture('gallery_commute_legacy.zip')


def test_legacy_gallery_package_decodes_unchanged():
    # Pre-TMG7 Gallery_commute.zip, byte for byte, with its 14 px row and outlined-button layout.
    blob = legacy()
    assert hashlib.sha256(blob).hexdigest() == '30e8dede85b7eafaf61ba63df82f6f1e6d130f9b547916ff21be6e34b2041d45'
    checked = read_package(blob)
    doc = checked['document']
    assert checked['budget']['valid'] and checked['budget']['retiredFonts'] == 1
    wire = encode(doc)
    assert wire == fixture('gallery_commute_legacy.tap')
    assert hashlib.sha256(wire).hexdigest() == '59bfcb594af568982ef3f862289325027ca2c73c110780f87c309fec04d9980d'
    assert wire[:4] == b'TAP1' and len(wire) == 808
    # The firmware test (tests/tmg7_app_test.c) feeds this same wire to the unchanged TAP1 parser.


def test_retired_font_renders_at_the_floor():
    assert [render_font(f) for f in (14, 16, 18, 24, 28)] == [16, 16, 18, 24, 28] and LENS_MIN_FONT == 16
    doc = read_package(legacy())['document']
    svg = render(doc, 'detail')
    sizes = {int(t.attrib['font-size']) for t in ElementTree.fromstring(svg).iter(SVG + 'text')}
    assert sizes and min(sizes) == 16 and 14 not in sizes
    assert all(min(t['font'] for t in p['components'] if 'font' in t) >= 14 for p in doc['pages'])   # the package itself is untouched


def test_buttons_are_caret_focus_items_not_outlines():
    doc = read_package(legacy())['document']
    for focus in (0, 1):
        root = ElementTree.fromstring(render(doc, 'home', focus))
        rects = [r for r in root.iter(SVG + 'rect') if r.attrib.get('stroke')]
        assert not rects                                                  # no outline rectangle around any button
        carets = [r for r in root.iter(SVG + 'rect') if r.attrib.get('rx') == '2']
        assert len(carets) == 1 and carets[0].attrib['width'] == '24' and carets[0].attrib['height'] == '3'
        assert carets[0].attrib['fill'] == '#00ff00'
        buttons = {c['text']: c for c in doc['pages'][0]['components'] if c['kind'] == 'button'}
        focused = list(buttons.values())[focus]
        assert int(carets[0].attrib['x']) == focused['x']
        assert int(carets[0].attrib['y']) == focused['y'] + focused['font'] + 1 + 4     # 4 px under the baseline
        fills = {t.text: t.attrib['fill'] for t in root.iter(SVG + 'text')}
        for label, c in buttons.items():
            assert fills[label] == ('#00ff00' if c is focused else '#007700')           # focused lens-full, idle lens-mid (18 px)


def layout_ok(doc, name):
    for page in doc['pages']:
        for c in page['components']:
            assert c['y'] >= 12 and c['y'] + c['h'] <= 172, (name, page['id'], c['id'])   # rows 0-12 and 172-180 stay empty
            if c['kind'] in ('text', 'button'):
                assert c['font'] >= LENS_MIN_FONT, (name, c['id'])
            if c['kind'] == 'button':
                assert c['y'] + c['font'] + 1 + 4 + 3 <= 172, (name, c['id'])               # the caret fits above the bottom reserve
            if c['kind'] == 'progress':
                assert c['h'] <= 4, (name, c['id'])                                         # tracks are 4 px


def test_gallery_and_examples_follow_the_tmg7_rules(tmp_path):
    for recipe in RECIPES:
        doc = snapshot_doc(recipe[0])
        layout_ok(doc, recipe[0])
        assert validate_app(doc)['retiredFonts'] == 0
        # The committed gallery is the current generator output, not stale.
        committed = zipfile.ZipFile(GALLERY / ('Gallery_' + recipe[0] + '.zip')).read('app.json')
        assert json.loads(committed) == doc
        assert json.loads((GALLERY / (recipe[0] + '.json')).read_bytes()) == doc
    for name, doc in examples().items():
        layout_ok(doc, name)
        assert validate_app(doc)['retiredFonts'] == 0


BANDS = ((12, 56), (56, 112), (112, 172))   # PriorityBands on the 540x180 page: T, M, B


def band_of(y, h):
    for i, (lo, hi) in enumerate(BANDS):
        if y >= lo and y + h <= hi:
            return i
    return None


def test_gallery_pages_follow_the_bands_and_the_caret_rules():
    for recipe in RECIPES:
        doc = snapshot_doc(recipe[0])
        for page in doc['pages']:
            ids = [c['id'] for c in page['components']]
            assert 'exit' not in ids and 'back' not in ids, (recipe[0], page['id'])                  # FocusCaret: never list Exit or Back
            assert not any(c.get('action', {}).get('type') == 'exit' for c in page['components']), recipe[0]
            for c in page['components']:
                band = band_of(c['y'], c['h'])
                assert band is not None, (recipe[0], page['id'], c['id'])                              # every item sits in exactly one band
                if c['kind'] == 'text':
                    assert c['x'] >= 40 and c['x'] + c['w'] <= 500, (recipe[0], c['id'])               # primary text inside the lens core
                if c['kind'] == 'button':
                    assert band == 1 and c['font'] == 20, (recipe[0], c['id'])                         # actions sit in M
                    assert band_of(c['y'], c['font'] + 1 + 4 + 3) == band, (recipe[0], c['id'])        # and so does the caret under them
            texts = [c for c in page['components'] if c['kind'] == 'text']
            top = [c['y'] for c in texts if band_of(c['y'], c['h']) == 0]
            assert top and max(top) - min(top) <= 3, (recipe[0], page['id'])                            # band T is one row of ambient text
            assert sum(band_of(c['y'], c['h']) == 2 for c in texts) <= 2 + (page['id'] == 'home'), (recipe[0], page['id'])
        home = doc['pages'][0]['components']
        primary = [c for c in home if c['id'] == 'line_0'][0]
        assert primary['y'] >= 112 and primary['font'] in (20, 24)                                     # the readout sits lowest, largest
        assert [c['action']['target'] for c in home if c['kind'] == 'button'] == ['detail']


def test_dashboard_templates_use_the_floor():
    for template in TEMPLATES:
        assert all(c['font'] >= LENS_MIN_FONT for c in template['components'] if c['kind'] == 'text')
