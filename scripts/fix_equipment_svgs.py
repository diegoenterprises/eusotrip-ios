#!/usr/bin/env python3
"""
fix_equipment_svgs.py

Batch transforms every Equipment animation SVG to address founder bugs from
2026-05-16 TestFlight pass:

  #3  Strip the hardcoded TRUCK / RAIL / VESSEL mode pill + the PLT / BBL /
      TEU / MT unit pill that were baked into each SVG. These are now
      rendered as live SwiftUI overlays by `EquipmentAnimation.topRightBadgeStack`
      and the SVG-baked copy doesn't react to the user's quantity-unit
      selection, so the screen shows duplicate badges (one reactive, one
      dead).

  #4  Replace the placeholder letter "E" rendered inside the brand-mark
      circle with the canonical Eusorone orb-and-spokes glyph (the same
      mark used by the bottom-nav ESANG orb / esang-ai-logo.svg).

  #5  Tighten the viewBox so the artwork fills the iOS preview tile instead
      of letterboxing. Adds preserveAspectRatio="xMidYMid slice" so the
      SVG covers the host container edge-to-edge.

  #6  Add @media (prefers-color-scheme: dark) CSS overrides so the artwork
      reads natively against a dark backdrop instead of looking like a
      light-mode collage glued onto the dark theme. The WKWebView host
      forwards the SwiftUI color scheme via `overrideUserInterfaceStyle`
      (see EquipmentAnimation.swift).

Runs idempotently — safe to re-run; uses sentinels in the output to skip
already-processed files.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "EusoTrip/Resources/Animations/Equipment"

SENTINEL = "<!-- EUSOTRIP-FIX-2026-05-17 -->"

# Brand-lockup is handled by `strip_balanced_g()` below, not a regex —
# the group nests a `<g class="brand-mark">` inside it, so non-greedy
# `.*?</g>` matches the wrong close.

# Strip the equipment-label group (e.g. "53' REEFER · REFRIGERATED · COLD CHAIN").
# Catches both the comment-anchored block and the variant some vessel SVGs
# use where the label is just standalone <text> elements at x=60.
EQUIPMENT_LABEL_RE = re.compile(
    r'\s*<!--\s*Equipment label\s*-->\s*<g[^>]*>.*?</g>\s*',
    re.DOTALL | re.IGNORECASE,
)
EQUIPMENT_LABEL_STANDALONE_RE = re.compile(
    r'\s*<text\s+x="60"\s+y="(?:78|106)"[^>]*>[^<]+</text>\s*',
    re.DOTALL,
)
EQUIPMENT_LABEL_RULE_RE = re.compile(
    r'\s*<line\s+x1="60"\s+y1="86"\s+x2="[^"]+"\s+y2="86"[^>]*/>\s*',
    re.DOTALL,
)

# Strip the bottom-left chevron "play" indicator that clips at the new viewBox.
CHEVRON_RE = re.compile(
    r'\s*<g\s+opacity="0\.[0-9]+"><path\s+d="M\s*70\s+540[^>]*/></g>\s*',
    re.DOTALL,
)

# Strip vessel-name "hull badge" text rendered on the side of the ship
# (e.g. "EUSO POLARIS", "EUSO ARCTIC", "EUSO PIONEER"). Positioned at
# x=500 y=447 in every vessel SVG — clips at the tightened viewBox.
VESSEL_HULL_NAME_RE = re.compile(
    r'\s*<text\s+x="500"\s+y="447"[^>]*>EUSO[^<]*</text>\s*',
    re.DOTALL,
)

# Strip any low-opacity "EUSOTRIP" / "EUSO …" watermark text painted on
# the trailer / boxcar / flatcar body. Catches the livery wordmark a few
# SVGs render at font-size 38-40 with opacity 0.18.
TRAILER_WATERMARK_RE = re.compile(
    r'\s*<text\s+[^>]*>(?:EUSOTRIP|EUSO\s+[A-Z]+)</text>\s*',
    re.DOTALL,
)

# Canonical Eusorone brand glyph — gradient orb + cardinal spokes + satellites
# + AI spark. 38×38 viewport, centered at (19,19), matches the existing
# `<circle cx="19" cy="19" r="18">` carrier shape so we only swap the inner
# letter-E render, not the host group.
EUSORONE_GLYPH = """    <!-- Canonical Eusorone orb glyph (replaces stub letter-E). -->
    <g transform="translate(19 19)" stroke="#FFFFFF" stroke-linecap="round" fill="none">
      <circle cx="0" cy="0" r="11" stroke-width="0.7" opacity="0.45"/>
      <g stroke-width="1.05" opacity="0.92">
        <line x1="0" y1="0" x2="0" y2="-8.4"/>
        <line x1="0" y1="0" x2="0" y2="8.4"/>
        <line x1="0" y1="0" x2="-8.4" y2="0"/>
        <line x1="0" y1="0" x2="8.4" y2="0"/>
      </g>
      <g fill="#FFFFFF" stroke="none">
        <circle cx="0" cy="0" r="2.2"/>
        <circle cx="0" cy="-8.4" r="1.55"/>
        <circle cx="0" cy="8.4" r="1.55"/>
        <circle cx="-8.4" cy="0" r="1.55"/>
        <circle cx="8.4" cy="0" r="1.55"/>
        <circle cx="6.4" cy="-5.8" r="0.85"/>
      </g>
    </g>"""

# Dark-mode CSS appended inside the existing <style> block. Targets only the
# light-mode-leaning surfaces (sky, ground line, wordmark text, equipment
# label) — keeps every brand gradient / vehicle paint untouched so the
# carbon-fiber finish on tractors and the hull paint on vessels remain
# recognizable. Hooked via the prefers-color-scheme media query which the
# WKWebView honors when overrideUserInterfaceStyle = .dark.
DARK_MODE_CSS = """
    /* ========== DARK-MODE OVERRIDES (2026-05-16) ========== */
    @media (prefers-color-scheme: dark) {
      .sky-bg          { fill: url(#skyDark) !important; }
      .ground-line     { stroke: #5E4FC6 !important; opacity: 0.55 !important; }
      .ground-shadow   { fill: #060912 !important; opacity: 0.55 !important; }
      .brand-word      { fill: #C9B6FF !important; }
      .brand-tagline   { fill: #8B7FE3 !important; }
      .equipment-label { fill: #C9B6FF !important; }
      .equipment-sub   { fill: #8B7FE3 !important; }
      .equipment-rule  { stroke: #6E4DFF !important; }
    }"""

# Dark sky gradient definition appended inside <defs>. Deep navy → indigo →
# violet-black; reads as a moody dusk over the rig.
DARK_SKY_DEF = """    <linearGradient id="skyDark" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%"  stop-color="#0A0F1F"/>
      <stop offset="55%" stop-color="#141A2E"/>
      <stop offset="100%" stop-color="#0B0F1B"/>
    </linearGradient>
"""

# Regex patterns ----------------------------------------------------------

# `<svg ... viewBox="0 0 1200 600" ...>` — the only opening svg tag.
SVG_OPEN_RE = re.compile(
    r'<svg\s+([^>]*?)viewBox="0 0 1200 600"([^>]*?)>',
    re.DOTALL,
)

# Mode badge — anchor on the stable rect coordinates that every Equipment
# Animation Design System badge uses (x="1052" y="58" width="100" height="32").
# Some SVGs precede with `<!-- Mode badge -->`, some don't; consume the
# comment if present. Match terminates at the OUTER `</g>` (the one after
# the TRUCK/RAIL/VESSEL label text), not the icon's `</g>`.
MODE_BADGE_RE = re.compile(
    r'\s*(?:<!--[^>]*?(?:Mode badge|MODE BADGE)[^>]*?-->\s*)?'
    r'<g(?:\s+[^>]*)?>\s*<rect\s+x="1052"\s+y="58"[^>]*?/>'
    r'.*?>(?:TRUCK|RAIL|VESSEL)</text>\s*</g>',
    re.DOTALL | re.IGNORECASE,
)

# Unit badge — anchored on rect coords (x="1062" y="100" width="80"
# height="28"). Label text is variable per vertical: PLT, BBL, MT, TEU,
# FEU, LBS, KG, LB, BU, TON, GAL, CWT, etc. — we don't pin on the token,
# we just consume until the OUTER `</g>`.
UNIT_BADGE_RE = re.compile(
    r'\s*(?:<!--[^>]*?(?:Unit badge|UNIT BADGE)[^>]*?-->\s*)?'
    r'<g(?:\s+[^>]*)?>\s*<rect\s+x="1062"\s+y="100"[^>]*?/>'
    r'\s*<text[^>]*?>[^<]+</text>\s*</g>',
    re.DOTALL | re.IGNORECASE,
)

# Inside `<g class="brand-mark">` — the inner <text ...>E</text> we want to
# replace with the glyph. Match it loosely (font-size="20" or "22" both
# appear in different SVGs).
BRAND_E_RE = re.compile(
    r'(<g\s+class="brand-mark"\s*>\s*<circle[^>]*?/>\s*<circle[^>]*?/>\s*)'
    r'<text[^>]*?>E</text>',
    re.DOTALL,
)

# Sky rectangle that paints the backdrop — usually:
# `<rect width="1200" height="600" fill="url(#sky)"/>` (some SVGs vary on
# x/y/order, so match loosely).
SKY_RECT_RE = re.compile(
    r'<rect\s+([^>]*?)fill="url\(#sky\)"([^>]*?)/>',
    re.DOTALL,
)

# Equipment label group — most SVGs use this comment block:
#     <!-- Equipment label -->
#     <g opacity="0.75">
#       <text ...>53' REEFER</text>
#       <line ... stroke="#9B7FD9".../>
#       <text ... opacity="0.7">REFRIGERATED · COLD CHAIN</text>
#     </g>
# Tag classes on the inner text + line so dark-mode CSS can swap fills.
EQUIP_LABEL_BLOCK_RE = re.compile(
    r'(<!--\s*Equipment label\s*-->\s*<g[^>]*>)\s*'
    r'(<text\s+[^>]*?)(>)([^<]+)(</text>)\s*'
    r'(<line\s+[^>]*?)(/>)\s*'
    r'(<text\s+[^>]*?)(>)([^<]+)(</text>)',
    re.DOTALL,
)

# Closing </style> — used to append dark-mode CSS just before it.
STYLE_CLOSE_RE = re.compile(r'\]\]>\s*</style>', re.DOTALL)

# Inside <defs> — append dark sky gradient before the first existing
# gradient definition. We anchor on the very first `<linearGradient id="`
# inside <defs>.
DEFS_FIRST_GRAD_RE = re.compile(
    r'(<defs>\s*)(<linearGradient\s+id=")',
    re.DOTALL,
)


def add_class(tag_inner: str, klass: str) -> str:
    """Append `klass` to the class="..." attribute on a tag's attribute
    string, or insert one if missing."""
    if 'class="' in tag_inner:
        return re.sub(r'class="([^"]*)"',
                      lambda m: f'class="{m.group(1).strip()} {klass}".strip()'
                      .replace('.strip()', '').replace('"  ', '" '), tag_inner)
    return f'class="{klass}" ' + tag_inner


def strip_balanced_g(svg: str, opening_match: str) -> str:
    """Remove an outer `<g ...>...</g>` group whose opening tag matches
    `opening_match` (e.g. `<g class="brand-lockup"`). Properly counts
    nested `<g>` opens / closes so the right outer `</g>` is found.

    Idempotent — if the opening match isn't present, returns input unchanged.
    """
    open_idx = svg.find(opening_match)
    if open_idx < 0:
        return svg
    # Find the end of the opening tag.
    tag_end = svg.find('>', open_idx)
    if tag_end < 0:
        return svg
    # Walk forward counting <g and </g.
    depth = 1
    i = tag_end + 1
    while i < len(svg) and depth > 0:
        next_open  = svg.find('<g', i)
        next_close = svg.find('</g>', i)
        if next_close < 0:
            return svg  # malformed — bail
        if next_open >= 0 and next_open < next_close:
            # ensure it's an actual <g + space or > (not <glyph etc.)
            char_after = svg[next_open + 2] if next_open + 2 < len(svg) else ''
            if char_after in (' ', '>', '\n', '\t'):
                depth += 1
            i = next_open + 2
        else:
            depth -= 1
            i = next_close + 4
            if depth == 0:
                close_end = i
                return svg[:open_idx] + '\n  ' + svg[close_end:]
    return svg


def transform(svg: str) -> str:
    if SENTINEL in svg:
        return svg  # already processed

    # 1. Strip hardcoded badges -------------------------------------------
    svg = MODE_BADGE_RE.sub('\n  ', svg)
    svg = UNIT_BADGE_RE.sub('\n  ', svg)

    # 1b. Strip baked text. All label text is now rendered reactively in
    # SwiftUI overlay (founder firing 2026-05-17 — baked text was being
    # clipped at the tightened viewBox). Artwork stays; text disappears.
    # Order matters: balanced-group stripper first (handles nested <g>),
    # then standalone-text regexes.
    svg = strip_balanced_g(svg, '<g class="brand-lockup"')
    svg = EQUIPMENT_LABEL_RE.sub('\n  ', svg)
    svg = EQUIPMENT_LABEL_STANDALONE_RE.sub('\n  ', svg)
    svg = EQUIPMENT_LABEL_RULE_RE.sub('\n  ', svg)
    svg = CHEVRON_RE.sub('\n  ', svg)
    svg = VESSEL_HULL_NAME_RE.sub('\n  ', svg)
    svg = TRAILER_WATERMARK_RE.sub('\n  ', svg)

    # 2. Replace brand-mark letter-E with the orb glyph (kept for the
    # in-SVG glyph; SwiftUI overlay renders the wordmark separately).
    svg = BRAND_E_RE.sub(lambda m: m.group(1).rstrip() + '\n' + EUSORONE_GLYPH, svg)

    # 3. Tighten viewBox + add slice fit ----------------------------------
    # New viewBox crops 50px of empty sky off the top and ~70px of empty
    # ground off the bottom. Aspect ~2.5:1 (closer to the iOS preview
    # tile's natural aspect). slice mode covers the box edge-to-edge.
    def _svg_open(m: re.Match) -> str:
        pre, post = m.group(1), m.group(2)
        attrs = (pre + post)
        # Strip any existing preserveAspectRatio so we don't double-up.
        attrs = re.sub(r'\s*preserveAspectRatio="[^"]*"', '', attrs)
        attrs = attrs.strip()
        return (
            f'<svg {attrs} viewBox="0 50 1200 480" '
            f'preserveAspectRatio="xMidYMid slice">'
        )
    svg = SVG_OPEN_RE.sub(_svg_open, svg, count=1)

    # 4. Tag sky rect with class="sky-bg" so dark-mode CSS can swap it ----
    def _sky(m: re.Match) -> str:
        before, after = m.group(1), m.group(2)
        if 'class="sky-bg"' in before or 'class="sky-bg"' in after:
            return m.group(0)
        return f'<rect class="sky-bg" {before}fill="url(#sky)"{after}/>'
    svg = SKY_RECT_RE.sub(_sky, svg, count=1)

    # 5. Tag equipment-label text + rule so dark-mode CSS can swap fills.
    def _equip(m: re.Match) -> str:
        return (
            m.group(1) + '\n    ' +
            m.group(2) + ' class="equipment-label"' + m.group(3) + m.group(4) + m.group(5) +
            '\n    ' +
            m.group(6) + ' class="equipment-rule"' + m.group(7) +
            '\n    ' +
            m.group(8) + ' class="equipment-sub"' + m.group(9) + m.group(10) + m.group(11)
        )
    svg = EQUIP_LABEL_BLOCK_RE.sub(_equip, svg, count=1)

    # 6. Append dark-mode CSS just before `]]></style>` -------------------
    svg = STYLE_CLOSE_RE.sub(DARK_MODE_CSS + '\n  ]]></style>', svg, count=1)

    # 7. Inject dark-sky gradient definition inside <defs> ----------------
    svg = DEFS_FIRST_GRAD_RE.sub(r'\1' + DARK_SKY_DEF + r'    \2', svg, count=1)

    # 8. Drop the sentinel into the closing tag so re-runs are idempotent.
    svg = svg.replace('</svg>', f'  {SENTINEL}\n</svg>', 1)

    return svg


def main() -> int:
    if not ROOT.is_dir():
        print(f"ROOT not found: {ROOT}")
        return 1
    targets = sorted(ROOT.rglob('*_anim.svg'))
    print(f"Transforming {len(targets)} SVGs under {ROOT}…")
    changed = 0
    skipped = 0
    for p in targets:
        original = p.read_text(encoding='utf-8')
        if SENTINEL in original:
            skipped += 1
            continue
        updated = transform(original)
        if updated != original:
            p.write_text(updated, encoding='utf-8')
            changed += 1
            print(f"  ✓ {p.relative_to(ROOT)}")
    print(f"Done. Changed: {changed}  Skipped (already-processed): {skipped}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
