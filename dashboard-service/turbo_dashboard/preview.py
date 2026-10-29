"""Deterministic SVG developer preview. Not a pixel-accurate firmware screenshot."""
from html import escape
from .contracts import render_font, validate
from .app_package import validate_app


# Lens ramp (docs/design-system tokens "lens"): app pages draw with the same four levels as the glasses.
FULL, HIGH, MID, TRACK = '#00ff00', '#00b000', '#007700', '#003800'
CARET_W, CARET_H, CARET_GAP = 24, 3, 4


def render(document, page=None, focus=0):
    """SVG preview. For an app page `focus` is the focused button in page order (the wheel position)."""
    app = page is not None
    if app:
        validate_app(document)
        selected = next((p for p in document['pages'] if p['id'] == page), None)
        if selected is None: raise ValueError('Unknown page')
        width, height, items = 540, 180, selected['components']
    else:
        validate(document); width, height, items = 256, 194, document['components']
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
           '<title>Turbo IO developer layout preview; not a device screenshot</title>',
           f'<rect width="{width}" height="{height}" fill="black"/>']
    buttons, caret = 0, None
    for i, c in enumerate(items):
        x,y,w,h = (c[k] for k in ('x','y','w','h')); kind=c['kind']
        ink = FULL if app else '#4fff54'
        if app and kind in ('text','button'):
            h = min(max(h, render_font(c['font'])+4), height-y)   # 14 px is retired; the box grows with the drawn size
        out.append(f'<clipPath id="clip{i}"><rect x="{x}" y="{y}" width="{w}" height="{h}"/></clipPath>')
        out.append(f'<g clip-path="url(#clip{i})">')
        if kind in ('text','button'):
            font = render_font(c['font']) if app else c['font']
            if app and kind=='button':
                # FocusCaret: a text focus item, lens-full when focused (else lens-mid, lens-high under 18 px), with a
                # 24x3 caret 4 px under the baseline; no outline and no fill.
                on = buttons == focus; buttons += 1
                ink = FULL if on else (MID if font >= 18 else HIGH)
                if on: caret = (x, min(y+font+1+CARET_GAP, height-CARET_H))
            elif kind=='button':
                out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="4" fill="#123712" stroke="#4fff54"/>')
            align = c.get('align', 'left'); tx = x + (w/2 if align=='center' else w if align=='right' else 0)
            anchor = {'left':'start','center':'middle','right':'end'}[align]
            out.append(f'<text x="{tx}" y="{y+font+(1 if app else 0)}" fill="{ink}" font-size="{font}" font-family="sans-serif" text-anchor="{anchor}">{escape(c["text"])}</text>')
        elif kind=='progress':
            out.extend([f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{TRACK if app else "#143714"}"/>',f'<rect x="{x}" y="{y}" width="{w*c["value"]/100}" height="{h}" fill="{ink}"/>'])
        elif kind in ('image','icon'):
            if kind=='icon':
                # System icon glyphs are platform supplied; never mislabel box as the actual glyph.
                out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none" stroke="{ink}"/><text x="{x+2}" y="{y+12}" fill="{ink}" font-size="10">i{c["icon"]}</text>')
            else:
                import base64
                raw=base64.b64decode(document['assets'][c['asset']]['pixels'] if app else c['pixels'])
                for row in range(h):
                    for col in range(w):
                        bit=row*w+col
                        if raw[bit//8] & (128>>(bit%8)): out.append(f'<rect x="{x+col}" y="{y+row}" width="1" height="1" fill="{ink}"/>')
        elif kind=='frame': out.append(f'<rect x="{x+1}" y="{y+1}" width="{w-2}" height="{h-2}" fill="none" stroke="{MID if app else ink}"/>')
        elif kind=='divider': out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{ink}"/>')
        elif kind=='barChart':
            step=w/len(c['points'])
            for j,v in enumerate(c['points']): out.append(f'<rect x="{x+j*step}" y="{y+h-h*v/100}" width="{max(1,step-3)}" height="{h*v/100}" fill="{ink}"/>')
        elif kind=='lineChart':
            points=' '.join(f'{x+j*w/(len(c["points"])-1)},{y+h-h*v/100}' for j,v in enumerate(c['points']))
            out.append(f'<polyline points="{points}" fill="none" stroke="{ink}" stroke-width="2"/>')
        out.append('</g>')
    if caret:   # drawn last so no label covers it; radius 2 like the firmware caret (corner pixels cut)
        out.append(f'<rect x="{caret[0]}" y="{caret[1]}" width="{CARET_W}" height="{CARET_H}" rx="2" fill="{FULL}"/>')
    return ''.join(out)+'</svg>'
