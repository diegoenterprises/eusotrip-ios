# Canonical Home — Reference Spec

**File:** `/EusoTrip/Views/Driver/010_DriverHome.swift`
**Struct:** `DriverHome` (also wrapped by `DriverHomeScreen`)
**Tokens source:** `/EusoTrip/Theme/DesignSystem.swift`

## Header (the reference)

Home does NOT use the "gradient title + CAREER · COMPLIANCE · REPUTATION" pattern. It uses a personalized two-column top bar:

- Left: `Text("Hey, \(firstName)")` at `.system(size: 40, weight: .heavy)` filled with `LinearGradient.diagonal` — lines 269–278
- Right rail: uppercase `EType.micro` time-of-day ("GOOD AFTERNOON"), then a gradient `location.fill` glyph + `palette.textSecondary` city (lines 286–300)
- Chat button `MessagesBadgeButton` (40x40, `Radius.sm`, `palette.bgCard` + `borderFaint`)
- Padding: `.horizontal, Space.s5` / `.top, Space.s5` / `.bottom, Space.s3`
- Immediately followed by `IridescentHairline()` (1pt blue→magenta gradient strip)

## Card treatment (two families, both canonical)

### A. `ActiveCard` — the "hero" surface
DesignSystem.swift lines 1075–1100.
- Padding: `Space.s5` (20pt)
- Background: `palette.bgCard`
- Shape: `RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)` = **20pt**
- Border: `LinearGradient.diagonal`, `lineWidth: 1.5`
- Shadow: dual blue/magenta — `Brand.blue@0.20 r=6 x=-2 y=2` + `Brand.magenta@0.20 r=6 x=2 y=2` (dark), both halved in light

### B. `.eusoCard()` modifier — the "melt into page" surface
DesignSystem.swift lines 1312–1410. Used by Home's recent-activity list, no-active-load carousel, suggested load cards.
- Fill: `#030309` (dark) / `#FFFFFF` (light) — exactly the page color
- Outline: `blue→magenta` gradient, `standard` = opacity 0.70, weight 1.25
- Outer glow (dark mode only): gradient stroke blurred r=10
- Radius default: `Radius.lg` = **16pt**

## Active load card (the canonical hero content)

010_DriverHome.swift lines 503–569.
- Wrapped in `ActiveCard`
- Top row: `StatusPill` (pickup status, `.info`) + optional neutral weight pill; right-aligned mono load ID (12pt monospaced, tracking 0.5, `palette.textSecondary`)
- Amount: `.system(size: 52, weight: .bold).monospacedDigit()` with `LinearGradient.diagonal`
- Caption under amount: `EType.caption` / `palette.textSecondary`
- Route row: origin → `gradientArrow` (`arrow.right` 16pt, gradient) → destination. Cities: `EType.bodyStrong` primary. Addresses: `EType.caption` secondary.
- CTA row: `LifecycleCTAButton` (full-width gradient) + fixed-width `Details` button (110x50, `palette.bgCardSoft`, `borderSoft`, `Radius.md`)

## Metric row (the canonical two-up)

Lines 595–619. Two `MetricTile`s side by side, `spacing: Space.s3`.
`MetricTile` spec (DesignSystem.swift 1104–1139):
- Label: `EType.micro`, tracking 0.6, uppercase, `palette.textTertiary`
- Value: `.system(size: 20, weight: .semibold).monospacedDigit()`, optionally gradient
- Padding `Space.s4`, background `palette.bgCard`, border `palette.borderFaint`, `Radius.lg`

## Typography ramp used on Home

| Token | Value | Used for |
|---|---|---|
| Hero display | `.system(size: 40, weight: .heavy)` + gradient | "Hey, {name}" |
| Big numeric | `.system(size: 52, weight: .bold).monospacedDigit()` + gradient | Active-load $ amount |
| `EType.h2` | 22pt semibold | Card sub-headings |
| `EType.title` | 17pt semibold | CTA button text |
| `EType.bodyStrong` | 15pt semibold | Route cities, row titles |
| `EType.caption` | 12pt regular | Supporting meta, addresses |
| `EType.micro` | 10pt semibold | ALL-CAPS tracked labels (0.6–0.8) |
| `EType.mono(.caption)` | 11pt mono | Load IDs |

## Spacing / radius scale (canonical)

- Space: `s1=4, s2=8, s3=12, s4=16, s5=20, s6=24, s7=32, s8=40`
- Radius: `sm=8, md=12, lg=16, xl=20, xxl=28, pill=999`
- Home padding: `TileStack(spacing: Space.s5)` inside `.padding(Space.s5)` — 20pt gutters, 20pt tile spacing.

## Buttons — canonical primary

Full-width gradient CTA uses `CTAButton` (DesignSystem 1181–1213):
- `LinearGradient.primary` (blue→magenta, leading→trailing)
- `RoundedRectangle(cornerRadius: Radius.md = 12)` — NOT pill
- `EType.title` white text, `padding(.vertical, 14)`
- Press: hueRotation −8°, saturation 1.08, scale 0.985

## Status pill — canonical

`StatusPill` (DesignSystem 1143–1177). Pill-shaped (`Capsule`), `EType.micro`, tracking 0.6, UPPERCASE, `color=Brand.x`, `background=palette.tintX` (14% in dark, 10–12% in light). Six kinds: success / warning / danger / info / hazmat / neutral.

## Icon language on Home

- SF Symbols only
- Small glyphs (clocks, chevrons): `.system(size: 11–14, weight: .semibold)`, `palette.textTertiary` or `textSecondary`
- Accent glyphs (arrow.right, flame, location.fill): gradient fill via `LinearGradient.diagonal`
- No stroke-width or fill-mode inconsistency inside Home itself
