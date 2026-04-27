# 01 · Brand DNA and Design Rules

**What this covers.** The complete visual law of the EusoTrip mobile app — brand DNA, gradient doctrine, forbidden design patterns, design tokens + component APIs, screen anatomy, microcopy and voice, and accessibility. Every pixel in the app defers to this file. It merges wave-1 shards `team_A_agent_1` (Brand DNA), `team_A_agent_2` (Design tokens + component API), `team_A_agent_3` (Screen anatomy), `team_A_agent_4` (Microcopy + voice), and `team_A_agent_5` (Accessibility + a11y).

**When you need this.** Every time you put a pixel on screen, every time you write a string, every time you add a primitive, every time you review a PR that touches UI. Contradictions between this file and code mean the code is wrong.

---

## Part A — Brand DNA, Gradient Doctrine, Forbidden Design (team_A_agent_1)

### A.1 Brand identity + "Powered by ESANG AI™" tagline positioning

EusoTrip is not a trucking app. It is a cross-mode freight operating system — truck, rail, vessel — built around a matrix of 24 roles × 3 modes × 9 verticals × 3 countries (US / CA / MX). The iOS surface is the Driver-first door into that operating system, but every other role (Shipper, Carrier, Broker, Catalyst, Escort, Terminal, Admin) rides on the same design language. The brand must read as one system, not seven apps glued together.

The single identity line is **"Powered by ESANG AI™."** ESANG is the intelligence layer — the voice assistant, the dispatch cortex, the diagnostic brain, the documents co-pilot. In the UI ESANG appears as:

- **The center orb** on the bottom navigation (`OrbESang` in DesignSystem.swift lines 264–384). It rotates slowly in idle, locks into a travelling waveform while listening, and snaps to a fast tempo while thinking.
- **The tagline** — shown only once per session at IntroSplash, and in the app-store listing. It is never stamped on screen chrome. The gradient *is* the tagline; if you need to say "Powered by ESANG AI™" with text, you are over-communicating.
- **The flower mark** (`EsangFlowerMark` lines 392–410) — six tapered white petals on the orb face, used at Figma frames 212:428 and 212:444 when the orb is rendered statically.

Brand positioning is "operator calm." The freight industry already ships a dozen apps that look like they were designed by defense contractors (Samsara) or indie startups who still think dashboards should look like rocket ships (Motive, KeepTruckin). EusoTrip's visual voice is the opposite: minimal surfaces, a single iridescent gradient, matte blacks, honest matte whites, typography that respects the driver's eyes at 5 a.m. in a cab. The app is an instrument, not a spectacle.

**Tagline positioning rules.**
- "Powered by ESANG AI™" renders exclusively in `EType.caption` (12pt regular) as a hairline over `LinearGradient.diagonal`, centered below the EusoTrip wordmark on IntroSplash. Nowhere else.
- ESANG is never abbreviated to "AI" in chrome. The brand is ESANG; "AI" alone is generic and cedes the name.
- ESANG is never visualized as a chatbot avatar, anthropomorphic character, or Siri-style waveform blob. The orb *is* the avatar.
- The trademark symbol (™) is rendered at 60% scale of the surrounding character via `Text("Powered by ESANG AI")` + `Text("™").font(.system(size: 9))`.

### A.2 Brand color hex values (verbatim extract)

Every primary color token lives in `enum Brand` at DesignSystem.swift lines 60–72. These are the only hex literals allowed anywhere in the codebase outside of the Brand enum and the two `eusoCardFillDark` / `eusoCardFillLight` constants.

```swift
Brand.blue    = 0x1473FF   //  20, 115, 255   — gradient stop 1
Brand.magenta = 0xBE01FF   // 190,   1, 255   — gradient stop 2
Brand.success = 0x00C48C   //   0, 196, 140   — system green (tint only, never fill)
Brand.warning = 0xFFA726   // 255, 167,  38   — amber (tint only)
Brand.danger  = 0xF44336   // 244,  67,  54   — red (tint only)
Brand.info    = 0x2196F3   //  33, 150, 243   — utility blue (links / info badges only)
Brand.hazmat  = 0xFFB100   // 255, 177,   0   — hazmat chip (vertical-specific)
Brand.escort  = 0x9C27B0   // 156,  39, 176   — escort mode accent (pilot-car role)
Brand.rail    = 0x607D8B   //  96, 125, 139   — rail mode accent
Brand.vessel  = 0x00ACC1   //   0, 172, 193   — vessel mode accent
```

**Usage law.** `Brand.blue` and `Brand.magenta` never appear as standalone fills or tints. They exist solely to compose `LinearGradient.diagonal` and its siblings. If you see `.fill(Brand.blue)` or `.tint(Brand.blue)` in a diff, it is a bug and must be rewritten as `.fill(LinearGradient.diagonal)` (possibly wrapped in `AnyShapeStyle`). `Brand.info` is the only blue that may appear flat, and only for utility (links, info-kind `StatusPill`).

`Brand.success`, `.warning`, `.danger`, `.info`, `.hazmat` only render as *tinted* capsules — their palette tint (14% opacity dark, 10% opacity light) fills the shape, and the solid color is used only for the foreground text/glyph. They never dominate a card surface.

`Brand.escort`, `.rail`, `.vessel` are mode-indicator accents — used exclusively inside role-badge glyphs on the mode picker and in the TerminalRole badge on the BottomNav. Never as CTAs.

### A.3 `LinearGradient.diagonal` specification

```swift
static let diagonal = LinearGradient(
    colors: [Brand.blue, Brand.magenta],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

**Direction.** Top-leading (upper-left corner) to bottom-trailing (lower-right corner). This is a 135° diagonal in screen-space convention (SwiftUI uses unit-rect coords where (0,0) is top-leading). The gradient runs "down-right."

**Stops.** Exactly two: `Brand.blue (0x1473FF)` at 0.0, `Brand.magenta (0xBE01FF)` at 1.0. No middle stop. No reversed pairs. No alpha adjustments.

**Sibling gradients (allowed).**
- `.primary` — horizontal variant (leading→trailing) for wide pills and header chrome.
- `.reverse` — magenta→blue (leading→trailing). Used only for the "paired" hero.
- `.revenue` — success→blue (diagonal). Wallet credit indicators only.
- `.expense` — danger→warning (diagonal). Wallet debit indicators only.
- `.esangSoft` — blue@18% → magenta@18% (diagonal). Used behind ESANG-composer chrome.
- `.iridescentHairlineDark` — blue@40% → magenta@40% (horizontal). 1pt hairline on dark register.
- `.iridescentHairlineLight` — blue@55% → magenta@55% (horizontal).

**Blend.** No `.blendMode(.plusLighter)` or `.screen` on the gradient itself. Always sRGB. Do not shift to OKLab, HSL, or P3 — both because backend/web/Android clients must match and because colorspace conversion dulls the gradient.

### A.4 Typography ramp — every `EType.*` token

| Token | Size (pt) | Weight | Use |
|---|---:|---|---|
| `EType.display` | 34 | bold | IntroSplash wordmark, wallet hero |
| `EType.h1` | 28 | bold | Screen titles (Home, Wallet, Me root) |
| `EType.h2` | 22 | semibold | Section headers, card titles |
| `EType.title` | 17 | semibold | Row titles, CTA button label, sheet titles |
| `EType.body` | 15 | regular | Primary body text, descriptions, helper copy |
| `EType.bodyStrong` | 15 | semibold | Emphasized body, row labels with status |
| `EType.caption` | 12 | regular | Secondary captions, timestamps, tagline |
| `EType.micro` | 10 | semibold | ALL-CAPS chip labels, metric tile labels, StatusPill text |
| `EType.numeric` | 28 | semibold | Metric tile values (monospaced-digit) |

**Monospaced variant.** `EType.mono(.body)` = 13pt medium monospaced. Used only for: load IDs, trailer numbers, VINs, timestamps in compliance logs, IFTA fuel-receipt codes, HOS log entries, BOL tracking numbers. Do not use monospaced for body copy — this is an AI-template tell (the "terminal aesthetic" is forbidden).

**Type color.** Always via palette: `palette.textPrimary`, `palette.textSecondary`, `palette.textTertiary`, `palette.textOnGradient` (white — only on gradient). Never `.foregroundStyle(.white)` or `.black` except on gradient.

### A.5 Space + Radius tokens

**Space (CGFloat).** `s1=4, s2=8, s3=12, s4=16, s5=20, s6=24, s7=32, s8=40`. Every `.padding`, `VStack(spacing:)`, `HStack(spacing:)` uses one of these eight values.

**Radius (CGFloat).** `sm=8, md=12, lg=16, xl=20, xxl=28, pill=999`. Every rounded rectangle, clip shape, strokeBorder uses one of six values. `style: .continuous` is always passed so curvature matches iOS system corners.

**Device constants.** `width=440, height=956, safeTop=54, safeBottom=34, navHeight=70, navOrbDiameter=60, navOrbLift=24, navCornerRadius=24`.

### A.6 Palette — Night and Afternoon registers

**Night (dark).** `textPrimary #F5F5F7`, `textSecondary #AAB2BB`, `textTertiary #6E7681`, `bgPage #030309` (ink-black — the new canonical; NOT `#05060A`), `bgPrimary #07070F`, `bgSecondary #0B0C16`, `bgCard #0D0E1A`, `bgCardSoft #131427`, `bgNav #141928 @ 75%`, `bgSheet #161B22 @ 88%`, `borderFaint white@8%`, `borderSoft white@12%`, `borderStrong white@22%`, tints @ 14% of Brand colors, `iridescentHairline` = dark variant, `deviceBezel #0B0B0F`.

**Afternoon (light).** `textPrimary #0D1117`, `textSecondary #52606D`, `textTertiary #8A96A3`, `bgPage #E9ECF1`, `bgPrimary #F4F5F7`, `bgSecondary white`, `bgCard white`, `bgCardSoft #F4F5F7`, `bgNav white@82%`, `bgSheet white@92%`, `borderFaint black@6%`, `borderSoft black@10%`, `borderStrong black@18%`, tints @ 10-14%, `iridescentHairline` = light variant, `deviceBezel #1A1B20`.

**Special card fills.** `Color.eusoCardFillDark = #030309` (dissolves into bgPage). `Color.eusoCardFillLight = pure #FFFFFF` (not `#F7F8FB`).

### A.7 FORBIDDEN design patterns (exhaustive)

#### AI-generic "futuristic" tropes (all forbidden)
- Circuit-board gradients, neon-cyan grid floors (Tron), Matrix scrolling text, cryptic terminal abbreviations (`SYS.CORE // OP.9421`), dark-hologram wireframe lines, glitch effects, "cyberpunk trucking" aesthetic, flat tech-bro gradients (pink→purple Stripe imitations), terminal-green monospace.

#### Flat-blue-tint misuse
- `.tint(Brand.info)` on `Toggle`, `TabView`, `ProgressView`, `Button`. Every toggle uses `GradientToggleStyle()`.
- `.fill(Brand.blue)` on anything that isn't a brand-info badge.
- SwiftUI's default `.tint` leaking into any control.

#### Glassmorphism overuse
- `.ultraThinMaterial` on every card surface. EusoTrip uses `.regularMaterial` only on the bottom nav plate and the bottom veil. Cards are solid.
- Blurred-glass cards stacked on blurred-glass backgrounds on blurred-glass sheets. One glass layer per composition, maximum.

#### Drop shadows
- Any `.shadow` with `radius > 20`.
- Black-tinted shadows in light mode. Use brand-tinted shadows.
- Diffused shadows under every element. A shadow is an information channel, not a decoration.

#### Emoji in UI chrome
- No 🚚 🚢 🚂 📦 💰 ⚡️ 🔥 in nav bars, tab bars, headers, button labels. Use `StatusPill` + SF Symbols. The only exception: user-generated content (messaging threads).

#### Custom keyboard fonts
- No `Inter`, `SF Compact Display`, `Space Grotesk`, `JetBrains Mono`, `Satoshi`, `Geist`, Google Fonts. EusoTrip uses **only** `Font.system` with weights/designs in `EType`.

#### All-caps bullet-separated subtitles (the "AI-template" tell)
- Subtitles formatted as `SECTION · LABEL · TAG` in gray small-caps. This is the single clearest "ChatGPT landing page" signature. Forbidden everywhere.
- Decorative mid-dots separating unrelated metadata in a header.
- All-caps titles beyond `EType.micro` (10pt).

#### Stock SF-Symbol gray tile rows
- Vertical list of `Image(systemName:)` in gray square tiles with captions. Shortcuts-app aesthetic. Forbidden.
- SF Symbols at `foregroundStyle(.gray)`. Always palette-driven.

#### Neumorphism, 3D skeuomorphism, rainbow accents
- Soft dual-shadow pillow surfaces. Dead aesthetic. Forbidden.
- Realistic truck illustrations, 3D container renderings. Flat brand-gradient glyphs only.
- Multi-stop gradients (blue→magenta→pink→orange→yellow). Signature is exactly two stops. Per-tab differently-colored accents. Pride-month limited-edition rainbow.

#### Other dealbreakers
- Animated loading spinners other than the ESANG orb.
- Toast notifications at top-of-screen that push content down.
- Tab-bar labels longer than one word.
- Modal sheets that present from the side.
- Push transitions for Me sub-routes.
- More than one font weight on the same line.
- Hard-coded 1pt dividers in neutral gray. Use `IridescentHairline`.
- Splash-screen version numbers, git hashes.

### A.8 ALLOWED primitives (the full kit)

- **`EusoHeader`** — screen title + subtitle. Title = `EType.h1`, subtitle = `EType.body` at `palette.textSecondary`. Optional trailing button.
- **`EusoBadge`** — mode/role/country tag. Capsule at `Radius.pill` with `palette.tintNeutral` fill, `EType.micro` text, optional leading SF Symbol. Gradient fill only if `isActive`.
- **`EusoEmptyState`** — every "no data yet" state. Orb at idle, `EType.h2` headline, `EType.body` sub, optional `CTAButton`.
- **`ActiveCard`** — hero card with gradient stroke and brand-tinted shadow. `palette.bgCard` fill, `LinearGradient.diagonal` 1.5pt border.
- **`MetricTile`** — label above, value below. `EType.micro` label, 20pt semibold monospaced-digit value, optionally gradient-filled via `gradientNumeral: true`.
- **`StatusPill`** — semantic capsule. Six kinds: success, warning, danger, info, hazmat, neutral.
- **`CTAButton`** — primary action. `LinearGradient.primary` fill, white `EType.title` text, `Radius.md` continuous.
- **`OrbESang`** — the ESANG avatar. Three states: `.idle`, `.listening`, `.thinking`. Never smaller than 40pt or larger than 120pt.
- **`EsangParticleField`** — the 90-particle swarm inside the orb. Do not reuse outside the orb.
- **`AuroraBackground`** — full-screen aurora wash. Auth surfaces only.
- **`IridescentHairline`** — 1pt gradient divider. Replaces every neutral gray 1pt rule.
- **`GlassCard`** — `.regularMaterial` over `palette.bgCardSoft`. Auth surfaces only.
- **`GradientToggleStyle`** — the only toggle style.
- **`.eusoCard()` modifier** — three intensities: `.whisper`, `.standard`, `.feature`.
- **`BottomNav`** — five-slot nav with center orb. Liquid Glass on iOS 26+, hand-rolled fallback below.

### A.9 Anti-AI-cliché manifesto

If you show the app to someone who doesn't know EusoTrip and they say "oh, it looks AI-generated," it is wrong. Symptoms:

1. **ChatGPT landing page** — oversized hero type in pink-purple gradient, emoji bullets, `Inter` everywhere.
2. **Vercel / Next.js starter** — gradient text on dark with geist-mono, neutral shadcn cards.
3. **Midjourney dashboard** — dark frosted glass everywhere, blurry purple orbs.
4. **V0 / Bolt / Lovable generation** — three-column feature grid with iconic SF Symbols, rainbow chip tags.
5. **Crypto exchange** — bright lime-green numeric heroes, candlestick motifs.
6. **Web3 wallet** — glassmorphism over psychedelic wallpapers.
7. **Indie AI startup launch week** — rotating isometric cards, spring-animated counters.

Strip the EusoTrip wordmark. Is it still obviously not-ChatGPT, not-Vercel, not-Midjourney? If yes, doctrine-compliant. If no, rework.

### A.10 Gradient usage map

**Gradient belongs.** Active chips, primary CTAs, numeric heroes, progress bars, icon rings, selected nav tabs, toggle thumbs (on), ActiveCard outlines, eusoCard outlines, OrbESang fill, IridescentHairline, wallet revenue/expense gradients, ESANG composer background wash (`.esangSoft`).

**Gradient does NOT belong.** Body text, inactive pills, neutral dividers, shadows (use blue@20% + magenta@20% as separate shadow calls), loading spinners, text field cursors, large background fills (AuroraBackground uses radial blooms at very low alpha), icon backgrounds on non-active rows, tab labels (text), pressed states (hue-shift -8°, don't change stops), error chrome, avatar placeholders, onboarding illustrations (none exist).

---

## Part B — Design Tokens + Component API (team_A_agent_2)

### B.1 Card-surface tokens (the `eusoCard` skin)

`EusoCardIntensity` has three levels:
- `.whisper` — outline opacity 0.35, weight 1.0, no outer glow. Nested / secondary rows.
- `.standard` — outline 0.70, weight 1.25, glow radius 10. Default.
- `.feature` — outline 1.00, weight 1.75, glow radius 18. Hero (Hot Zones, active load).

### B.2 Component API signatures (verbatim)

```swift
struct EusoHeader<Trailing: View>: View {
    enum Size { case pane, sheet }
    let title: String
    let supertitle: String?
    let subtitle: String?
    var size: Size = .pane
    init(title: String, supertitle: String? = nil, subtitle: String? = nil, size: Size = .pane, @ViewBuilder trailing: @escaping () -> Trailing)
}

enum EusoBadgeKind: Equatable { case info, warning, hot, success, neutral, hazmat }
struct EusoBadge: View { init(label: String, kind: EusoBadgeKind = .neutral, icon: Image? = nil) }

struct EusoEmptyState: View {
    typealias CTA = (label: String, action: () -> Void)
    init(systemImage: String, title: String, subtitle: String? = nil, cta: CTA? = nil, comingSoon: Bool = false)
}

struct ActiveCard<Content: View>: View { @ViewBuilder var content: () -> Content }

struct MetricTile: View {
    let label: String
    let value: String
    var gradientNumeral: Bool = false
}

struct StatusPill: View {
    enum Kind { case success, warning, danger, info, hazmat, neutral }
    let text: String
    let kind: Kind
}

struct CTAButton: View { let title: String; var action: () -> Void = {} }

struct OrbESang: View {
    enum State { case idle, listening, thinking }
    let state: State
    var diameter: CGFloat = Device.navOrbDiameter
}
```

### B.3 Usage rules per primitive

- **`EusoHeader`** — every pane root, every sheet root, Home greeting block. Never for in-scroll section headings (reach for `Text(...).font(EType.h2)`). `.bullet-separated UPPERCASE` supertitles are forbidden — the AI-template tell.
- **`EusoBadge`** — HOT markers, equipment chips, single-word role tags. Never for changing status (use `StatusPill`).
- **`EusoEmptyState`** — every surface whose backend is absent. Never fake data.
- **`ActiveCard`** — the "one active thing." Never nest. Never as a generic container.
- **`MetricTile`** — 2-up / 3-up / 4-up rails. Never standalone. Always `gradientNumeral: true` on revenue/earnings.
- **`StatusPill`** — operational state that changes. Never static classifications.
- **`CTAButton`** — primary action, one per surface. Use `LifecycleCTAButton` inside trip state machine.
- **`GlassCard` / `AuroraBackground`** — auth surfaces only.
- **`OrbESang`** — exactly one per screen, in BottomNav or as hero of DriverHome / ESANG coach sheet. Never inline in a list.

### B.4 Animation rules

- Button press: `.easeOut(duration: 0.12)`.
- Orb rotation: `.linear(duration: currentPeriod).repeatForever(autoreverses: false)`, periods: idle 18s / listening 6s / thinking 2s (doubled under `accessibilityReduceMotion`).
- Orb hue-shift breath: `.easeInOut(duration: 6).repeatForever(autoreverses: true)`. Disabled under reduce-motion.
- Particle field: 60 Hz `TimelineView(.animation(minimumInterval: 1/60))`, paused under reduce-motion.
- Card elevation changes: never animated.

### B.5 Haptic patterns

Via `Haptics.play(_:)`:
- `.click` — selection, tab switch, row tap. `.light` impact.
- `.success` — load accepted, payment cleared, DVIR submitted. `.success` notification.
- `.retry` — failed action auto-retrying. `.soft` impact ×2, 80ms apart.
- `.failure` — destructive error, HOS violation, card declined. `.error` notification.
- `.start` — trip advance, lifecycle phase transition, wizard step. `.medium` impact.

Never chain under 150ms. Never inside a `ForEach`. Fire once after the user action completes.

### B.6 Register invariants

Both registers render the same layout to the pixel. What changes: palette tokens only. Pixel-parity checklist: screenshot at 440×956 Night + Afternoon, overlay at 50%, every element at same (x,y,w,h).

### B.7 Before / After — AI-template sin vs doctrine-compliant

#### Sin (13 lines, 7 violations)
```swift
VStack(alignment: .leading, spacing: 8) {
    Text("CAREER · COMPLIANCE · REPUTATION")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.gray)
        .tracking(1.2)
    Text("My Performance")
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(.white)
}
.padding()
.background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.1, green: 0.1, blue: 0.15)))
```
Violations: bullet-separated UPPERCASE supertitle, raw `Color.gray`, raw `Color.white`, 1.2 tracking, raw hex, 20pt bold (doctrine is 40pt heavy gradient), literal `12` instead of `Radius.md`.

#### Doctrine-compliant replacement
```swift
EusoHeader(title: "My Performance", supertitle: "Career snapshot", size: .pane)
    .eusoCard(radius: Radius.lg, intensity: .standard)
```
Two lines. Palette-aware. Theme-flippable. VoiceOver-correct. Dynamic-Type-safe. This is the bar.

---

## Part C — Screen Anatomy (team_A_agent_3)

### C.1 Screen layout grammar

Every driver screen is a six-layer stack:

1. **`Shell`** (DesignSystem.swift:1227) — root frame, draws `theme.bgPrimary`, inner ScrollView with bottom spacer equal to `Device.navHeight + Device.safeBottom + Space.s4` so BottomNav never occludes, anchors BottomNav with ESANG orb.
2. **`EusoHeader`** — 40pt heavy gradient title (pane) or 28pt (sheet). Optional supertitle, subtitle, trailing slot. Home is the only pane that uses a bespoke topBar.
3. **`IridescentHairline`** — 1pt full-width gradient hairline. Sits flush under every EusoHeader. This line IS the contract between chrome and content.
4. **`ScrollView`** wrapping **`TileStack`** — variadic container applying cafe-door reveal (fade+lift, 50ms stagger per index).
5. **Clearance spacer** — `Color.clear.frame(height: Device.navHeight + Device.safeBottom + Space.s4)`. Mandatory.
6. **Sticky CTAs** — optional. Lifecycle screens anchor `LifecycleCTAButton` at the bottom of the scroll.

`.refreshable { await vm.load() }` on the ScrollView, not the TileStack.

### C.2 Sheet vs push vs tab

Driver surface is **tab-primary, sheet-secondary, push-never**.

- **Tab pane** — four top-level verbs (Home / Trips / Loads / Me). `.transition(.opacity).animation(.easeOut(duration: 0.18))` cross-fade.
- **Sheet** — `.sheet` with `.presentationDetents([.large])` and `.presentationDragIndicator(.visible)`. Sheets pass `.environment(\.palette, palette)` through.
- **Push** — not used. `NavigationLink` is banned.

Decision rule:
- Peers → tabs.
- Detail about one thing → sheet, `.large`.
- Forward through linear flow (pre-trip → en-route → pickup → BOL → delivery) → lifecycle screen swap, driven by `trip.phase`.
- Coached, not navigated → ESANG overlay.

Deep links: `NotificationCenter.default.post(name: .eusoSwitchToTripsTab, object: nil)`.

### C.3 Tab bar: home / trips / loads / me

`DriverTab` (010_DriverHome.swift:813) enumerates four slots plus orb:
- **`.home`** — personalized dashboard.
- **`.trips`** — Eusoboards when idle; active-trip surface when `trip.phase.isActiveTrip == true`. Single branch point that makes Trips dual-purpose.
- **`.wallet`** (back-compat case name) — actual label **"Loads"**, systemImage `shippingbox.fill`, routes to `DriverLoadsPane`.
- **`.me`** — profile, vehicle, weekly plan, trips history, earnings, notifications.
- **ESANG orb (center)** — not a tab. Opens `DriverESangCoachSheet` via dissolve-to-orb transition.

Wallet is not a top-level tab — it's a metric tile on Home opening `DriverWalletPane` as a `.large` sheet. Deliberate: Wallet is detail, not a destination.

### C.4 Hero card pattern (gradient ring + big number + caption + meta row)

Canonical hero layered top-to-bottom:
1. Meta row — one or two `StatusPill`s left, monospaced load ID right.
2. Hero numeral — 52pt bold monospacedDigit, `foregroundStyle(LinearGradient.diagonal)`. Never flat.
3. Caption under numeral — `EType.caption`, `palette.textSecondary`.
4. Route row — three-column `origin → gradient arrow → destination`.
5. Action row — 2fr/1fr split: `LifecycleCTAButton` wide, outlined secondary button 110×50pt.

Container = `ActiveCard`: `palette.bgCard` fill, `Radius.xl`, 1.5pt `LinearGradient.diagonal` strokeBorder, dual-color shadows (`Brand.blue` −2x, `Brand.magenta` +2x, radius 6, opacity 0.20 dark / 0.10 light).

### C.5 MetricTile 2×3 grid

Per-tile: `palette.bgCard` fill, `Radius.lg`, `palette.borderFaint` 1pt stroke. Label = uppercase `EType.micro`, `tracking(0.6)`, `palette.textTertiary`. Value = 20pt semibold monospacedDigit, `.lineLimit(1).minimumScaleFactor(0.5)`. Padding `Space.s4`.

Tiles always wrapped in `Button { showSheet = true } label: { MetricTile(...) }.buttonStyle(.plain)` — every tile is a live deep-link.

### C.6 Activity-feed pattern

Five-zone row:
```
[40×40 glyph tile] [title + subtitle (2 lines max)] [Spacer] [trail amount + chevron]
```
Glyph tile: 40×40, `Radius.md`, soft tint fill, icon 16pt semibold. Title: `EType.bodyStrong`, `lineLimit(2)`. Subtitle: `EType.caption`, `palette.textSecondary`. Trail: bodyStrong amount (color by sign) + chevron. Divider: `palette.borderFaint`, 68pt left inset to align with text column. Every row is a Button using `ActivityRowButtonStyle` (scale 0.985, opacity 0.85, 0.12s easeOut).

### C.7 Empty state pattern

```swift
EusoEmptyState(
    systemImage: "truck.box",
    title: "No loads match your lane right now",
    subtitle: "New tenders appear here the moment they hit the board."
)
```

Prose rule is strict: present-tense declarative + forward-looking second line. Never "You have no X." Always "No X right now" + "New X appear here when Y."

### C.8 Loading state

Never spinner + diagnostic text. The original "Contacting EusoTrip tRPC · loads.search · hos.getStatus" leaked backend plumbing.

Canonical: `LoadingParticleField(count: 160, height: 180)` inside `ActiveCard`. 160 drifting specks in brand blue/magenta. No text, no progress bar, just brand-identity motion.

Lightweight: centered `ProgressView().progressViewStyle(.circular).padding(Space.s5)`. Example: MyLoadsSheet while loading + visible empty.

Never combine both patterns on the same surface.

### C.9 Error state

**Inline offline banner** — thin strip above hero. 6pt `Brand.warning` dot + "Offline preview" micro-label + right-aligned "Retry" text button. `palette.bgCardSoft` + `palette.borderFaint`. Rule: offline is non-blocking, acknowledged, retryable.

**Error card** — `ActiveCard`. Header row: `exclamationmark.triangle.fill` `Brand.warning` + "Backend unavailable" bodyStrong. Body: message in `EType.caption`. Footer: full-width outlined "Retry". Only one action. Never "Contact support" or "Restart app."

Forbidden: modal error alerts, destructive-red banners, full-screen crash pages, error copy that names endpoint or HTTP status.

### C.10 Home top-of-screen greeting

Bespoke three-column layout (the only non-EusoHeader pane header):
- **Left (180pt max)**: `Text(greetingFirstName.isEmpty ? "Welcome back" : "Hey, \(greetingFirstName)")` at `.system(size: 40, weight: .heavy)` with `foregroundStyle(LinearGradient.diagonal)` and `lineSpacing(-4)`.
- **Right (140pt max)**: two-line meta. Top = uppercase time-of-day greeting (`EType.micro`, `tracking(1.0)`, `palette.textTertiary`). Bottom = gradient `location.fill` + city (`.system(size: 13, weight: .semibold)`, `palette.textSecondary`).
- **Far right**: `MessagesBadgeButton` with live unread count.

Phrasing rules: first line is always "Hey, {first name}". Time-of-day is diegetic ("Good afternoon"). Location is city, not timezone. No em-dashes, no bullets, no "AI" language.

### C.11 Gesture language

- **Pull-to-refresh** — every live-data scroll surface.
- **Swipe-to-delete / swipe-actions** — only in notifications and messages. Load cards never swipe-deletable.
- **Long-press** — reserved for the watch ESANG orb (recording). Not used on iOS.
- **Triple-tap debug overlays** — not present on iOS. Watch has an isolated 28×28 hit zone in DEBUG.
- **Tap-outside-to-dismiss** — ESANG overlay backdrop only.
- **Carousel swipe** — horizontal ScrollView + LazyHStack + `.scrollTargetBehavior(.viewAligned)` + `.scrollClipDisabled()`.

### C.12 Navigation transitions

1. **Cafe-door tile reveal** — canonical entry via `TileStack`. Fade + 8–12pt lift + 50ms stagger.
2. **Standard push** — not used.
3. **Sheet slide** — system `.sheet`, `.large` detent. Backdrop cross-fades against `Color.black.opacity(0.45)`.
4. **ESANG burst (dissolve-to-orb)** — `DriverHomeScreen.dissolveESang()` (line 971). Sheet simultaneously scales to 0.15, blurs 12pt, opacity 0 while `ESangParticleBurst` converges on `orbAnchor` (0.65s total). The signature transition.

Tab switches are `.transition(.opacity).animation(.easeOut(duration: 0.18))`.

### C.13 Watch anatomy (iPhone is a different surface)

**Two-page TabView**, not a tab bar.

- **Page 1 — Idle Orb.** Bare. Just `EsangOrbWatch` at 104pt, centered, drifting ±2pt on 5.6s breath, halo breathing radius 24→34. Cool indigo when signed-out → magenta when paired. No chips, no load card, no chrome. The orb IS the screen.
- **Page 2 — Instrument Panel.** Precision-instrument layout. Two vertical HOS gauges hug bezels (drive remaining left, 14h window right). Small circular complications top. Active load strip mid-screen. Three circular action dials bottom: HOS / Phone / SOS.

Every surface is live-data driven, no placeholders. Tap orb → listening. Double-tap orb (300ms dedup) → stop-and-submit. Swipe left → instrument. Debug: `#if DEBUG` 28×28 invisible top-right hit zone with ladybug glyph at 0.25 opacity.

No `StatusPill`, no `MetricTile`, no `ActiveCard` on watch. The watch shows one thing, breathing. If a driver has to swipe more than once on the wrist, the information should have been on Page 1.

---

## Part D — Microcopy + Voice (team_A_agent_4)

### D.1 Voice & Tone pillars

1. **Direct.** Lead with verb or fact. "Load accepted." "Break starts now." "2 hours until reset."
2. **Respectful.** Never "champ," "rockstar," "hero," "legend."
3. **Pragmatic.** Every string answers: What happened? What do I do? What will it cost?
4. **Blue-collar-fluent.** BOL, POD, DVIR, HOS, deadhead, detention, lumper, bobtail — we use the language of the user.
5. **Never patronizing.** No "Great job!" after logging a break.
6. **Never tech-bro.** No "powered by AI." No "next-generation." No "reimagined."

Max chrome string: 40 characters. Max notification: 120 characters. Max watch glance: 24 characters.

### D.2 Forbidden words

- **Corporate-speak**: empower, leverage, optimize, synergize, unlock, streamline, seamless, frictionless, best-in-class, world-class, enterprise-grade, mission-critical, at scale, scalable, holistic, robust, cutting-edge, turnkey, end-to-end, one-stop, ecosystem, stakeholder, alignment, circle back, bandwidth, move the needle, game-changer, paradigm, disruptive, transformative.
- **Cutesy errors**: whoops, oopsie, oops, uh-oh, yikes, d'oh, sad trumpet, sorry about that, something went wrong, looks like, it seems.
- **Tech-bro**: ultimate, revolutionary, reimagined, AI-powered, AI-driven, powered by AI, smart (prefix), intelligent (prefix), next-gen, cyberpunk, futuristic, the future of, bleeding-edge, sleek, beautifully designed, delightful, magical.
- **Participation trophy**: champ, rockstar, hero, legend, superstar, ninja, guru, warrior, beast, boss (compliment), crushed it, nailed it, way to go, great job, amazing work.
- **Over-softeners**: just, simply, easily, quickly (as filler), kindly, please (except once in a true request), a little, a bit, sort of, kind of.
- **Condescension**: let's get you started, no worries, don't worry, we've got you, rest assured.
- **Banned ESANG framings**: "As an AI," "I'm just an AI," "I think," "I believe," "I feel," "in my opinion," "great question," "happy to help."

### D.3 Approved CTA verbs

Accept, Book, Deliver, Log, Start, Resume, Sign, Submit, Call dispatch, SOS, Cancel, Retry, Refresh, Open, Close, Pair, Unpair, Install, Update.

- **Accept / Decline** — load offers only.
- **Book** — committing to a load on the board. Different from Accept (dispatched offers).
- **Deliver** — arrival at consignee + final POD.
- **Log** — HOS, fuel, DVIR, expense.
- **Start / Resume** — Start trip, Start break, Resume route. Not "Begin."
- **Sign** — BOL, POD, lease, settlement, DVIR.
- **Submit** — paperwork to dispatch/accounting/DOT.
- **Call dispatch** — always two words, always this phrasing.
- **SOS** — emergency escalation. Never "Help."
- **Cancel** — back out of pending action.
- **Retry** — re-attempt failed network/device action. Not "Try again" in chrome.
- **Refresh** — pull latest.
- **Pair / Unpair** — ELD, dashcam, TPMS, watch, Bluetooth.

Destructive actions use verb + object: "Delete load," "Remove driver," "End trip." Always paired with Cancel.

### D.4 Empty-state copy bank (one fact line + one next step)

- **Wallet — Transactions**: `No transactions yet.` / `Settlements and fuel charges land here.`
- **Wallet — Pending Payouts**: `No payouts pending.` / `Delivered loads show up within 24 hours of POD.`
- **Missions**: `No missions today.` / `New missions post Monday 06:00 local.`
- **Loads — Available**: `No loads in your lanes.` / `Widen your radius in Settings > Lanes.`
- **Loads — Booked**: `No booked loads.` / `Accept an offer or book from the board.`
- **Loads — History**: `No delivered loads yet.` / `Completed loads stay here for 7 years.`
- **Messages**: `No messages.` / `Dispatch, brokers, and ESANG post here.`
- **Documents — POD**: `No PODs on file.` / `Capture at the consignee before you leave.`
- **HOS Log**: `No duty events today.` / `Events start when the ELD is paired and moving.`
- **IFTA — Current Quarter**: `No miles recorded this quarter.` / `Miles log automatically once the ELD is paired.`
- **ESANG — History**: `No ESANG history.` / `Say "Hey ESANG" or tap the mic.`
- **Detention Timer**: `No detention events.` / `Timer starts at 2 hours after appointment time.`
- **Offline Queue**: `No pending items.` / `Actions taken offline queue here until you reconnect.`

### D.5 Error copy bank (name the problem, then the next action)

- **Network no connection**: `No connection.` / `Check Wi-Fi or cell signal, then Retry.`
- **Auth wrong password**: `Password doesn't match.` / `Retry or reset.`
- **Auth locked**: `Account locked after 5 tries.` / `Reset password or call support.`
- **Permission location denied**: `Location is off.` / `Turn on in Settings > Privacy > Location.`
- **Permission mic denied (ESANG)**: `Mic access is off.` / `Turn on to talk to ESANG.`
- **Offline action queued**: `You're offline.` / `This will send when you reconnect.`
- **Server 500**: `Server error.` / `Retry in a minute.`
- **Rate limit**: `Too many requests.` / `Wait 30 seconds and Retry.`
- **Validation required**: `Missing: [field name].`
- **ELD not paired**: `ELD not paired.` / `Pair in Settings > Devices.`
- **ELD disconnected mid-trip**: `ELD disconnected.` / `Check the cable. Events will back-fill on reconnect.`
- **Card declined**: `Card declined.` / `Try another card or call your bank.`
- **Offer expired**: `Offer expired.` / `Check the board for similar loads.`

If the system truly doesn't know: `Something failed and we don't know why. Retry, or call support with code [CODE].`

### D.6 Confirmation copy bank (question + consequence)

- **Delete document**: `Delete this [doc type]?` / `This can't be undone.` Buttons: Delete / Cancel.
- **Cancel booked load**: `Cancel this load?` / `Cancellations may affect your score and pay.` Buttons: Cancel load / Keep it.
- **Accept offer**: `Accept this load?` / `[Pickup] -> [Drop], [miles] mi, [rate].` Buttons: Accept / Decline.
- **Log off-duty**: `Log off-duty now?` / `Your 10-hour reset starts now.` Buttons: Log off-duty / Cancel.
- **Sign BOL**: `Sign this BOL?` / `Your signature goes on the document as filed.` Buttons: Sign / Cancel.
- **Submit POD**: `Submit POD to dispatch?` / `This closes out the load.` Buttons: Submit / Cancel.
- **SOS**: `Send SOS?` / `Your dispatcher and emergency contact will be called.` Buttons: Send SOS / Cancel.
- **Sign out**: `Sign out of EusoTrip?` / `Offline queue will send next time you sign in.` Buttons: Sign out / Cancel.

### D.7 ESANG voice lines

Rules:
- First-person sparingly. "I can't reach the server" OK; "I think you should..." not.
- Never "great question," "happy to help," "as an AI," "I believe," "I feel."
- Confirm in past tense: "Logged." "Sent." "Booked." "Paired."
- Report facts with numbers: "2 hours until your 30-minute break."
- On failure: `Couldn't [verb] — [specific reason]. [Next step].`
- Use driver vocabulary. Do not translate.

Examples:
- `Logged. Your next break is in 2 hours.`
- `Off-duty logged. 10-hour reset running.`
- `BOL scanned. Filed under load 8842.`
- `3 loads in your lanes. Want me to read them?`
- `Fuel's cheaper 12 miles up at the Pilot in Amarillo — $0.14 under.`
- `Couldn't send POD — no signal. I'll retry when you're back online.`
- `Didn't catch that. Say a load number or 'cancel.'`

### D.8 Push notification pattern

`[Subject or status]. [Fact]. [Action if needed].`

- `Load offer — Laredo to Kansas City. $2,840. Expires 14:00.`
- `Booked. Pickup 14:30 at DHL Laredo.`
- `30 min to your 8-hour break.`
- `Drive time ends in 10 min. Find parking.`
- `Detention pay triggered. $75 added to load 8842.`
- `Dispatch: [first 60 chars of message]`
- `Payout of $3,420 is in your wallet.`

No all-caps. One exclamation across the entire app (SOS only). Title case for first two words only.

### D.9 Watch notification copy (≤24 chars)

- `30 min to break`
- `Load offer — $2,840`
- `Detention: 2h hit`
- `Ice on I-80 in 40 min`
- `ELD off`
- `POD needed`

Two-tap actions only: Accept / Decline, Open on phone, Dismiss. No free-text on watch beyond dictation to ESANG.

### D.10 Localization

- **Primary**: en-US. Source of truth.
- **Required at launch**: es-MX, fr-CA. Non-negotiable for cross-border.
- **Secondary (post-launch)**: es-US, en-CA, pt-BR.
- Driver idioms (BOL, POD, DVIR, HOS) stay in English in every locale.
- Regulatory references are jurisdiction-specific (US FMCSA vs Canada HOS vs MX SCT reglamento).
- Chrome strings get a 40% length budget in translation; longer needs rewrite, not truncation.
- Currency via ICU MessageFormat.
- es-MX defaults to tú informal (usted in legal).
- fr-CA defaults to tu in chrome, vous in compliance.

### D.11 Date/time and units

- **en-US**: `MMM d`, 12-hour a.m./p.m.
- **es-MX**: `dd/mm/yyyy`, 24-hour.
- **en-CA**: en-US format, 12/24 hybrid.
- **fr-CA**: `d MMM yyyy`, 24-hour.
- Relative time preferred in chrome. Time zones displayed for distant events (`14:30 CT` or `14:30 local`).
- Durations: `2 h 15 min`, never `2:15` (ambiguous with clock time).
- Distance: miles/km toggle. Default by plate country.
- Fuel: gallons/liters toggle.
- Weight: lbs/kg. Axle weights always show unit.
- Temperature: °F/°C for reefer and weather.
- Currency: origin-country for rates, profile for payouts. Conversion labeled.

### D.12 Driver-specific idioms — preserved verbatim

**Paperwork**: BOL, POD, DVIR, HOS, IFTA, IRP, ELD, RODS, EFS, ComCheck.
**Operations**: deadhead, detention, layover, lumper, backhaul, bobtail, reefer, dry van, flatbed, tanker, step deck, conestoga, hotshot, LTL, TL, FTL, drop-and-hook, live load, pre-pass, scale, chicken coop, yard, fifth wheel, kingpin, glad hands, tandems, sliders.
**Roles**: OO (owner-operator), O/O, company driver, team driver, dispatcher, broker, shipper, consignee, receiver, DOT officer.
**Places**: TA, Petro, Flying J, Pilot, Love's, weigh station, truck stop, customer, drop yard, terminal.
**Events**: no-touch, touch freight, pallet jack, lumper fee, assessorial, layover pay, detention pay, fuel surcharge, FSC, APU, deadheading home.

No italics, no quotes, no tooltip. The app that translates "deadhead" into "unloaded return trip" is the app drivers delete.

---

## Part E — Accessibility (team_A_agent_5)

### E.1 Prologue

Accessibility is not a feature. It is the substrate on which every other feature stands. For EusoTrip, it is legal, App Store, moral, and quality. If a feature cannot be used by a driver with a screen reader, motor impairment, low vision, cognitive load from driving, or any combination, that feature is not shippable.

### E.2 WCAG 2.1 AA baseline — the floor, not the ceiling

Required for App Store approval, ADA / EU / UK / Canada / AU statutes, CA Unruh Act + state consumer protection. We follow the stricter of Apple HIG and WCAG. WCAG 2.2 additions (focus appearance, dragging, target size enhanced) treated as aspirational; ship AA today with roadmap to AAA.

Every shipped screen carries a compliance attestation in its SwiftUI preview header: WCAG criteria verified, date, verifier initials, assistive-tech matrix.

### E.3 Color contrast

- 4.5:1 for body text <18pt regular or <14pt bold.
- 3:1 for large text and graphical interface elements.
- Both registers independently.

Palette tokens carry computed contrast ratios as metadata. Testing via Xcode Accessibility Inspector + Stark Figma. Gradients must pass at lightest AND darkest sample along gradient. AuroraBackground text uses a scrim or falls back to solid `bgPage`. Subtitle greys below 4.5:1 are banned regardless of elegance.

### E.4 Touch target — 44×44pt everywhere

Apple HIG minimum, WCAG 2.2 requirement. When visual element must be smaller (28pt close glyph, 20pt inline info icon), wrap in 44×44 hit region via `.contentShape(Rectangle().frame(width: 44, height: 44))`. ESANG orb visual 72–96pt but hit region always 120×120 for driving-context motor imprecision. Primary driving CTAs (start trip, end trip, SOS, ESANG activate) expand to 80pt buffer zone.

### E.5 Dynamic Type — through AX5

Semantic font styles or `UIFontMetrics`-mapped. Hardcoded sizes need `// a11y:fixed-size` comment. Test xSmall through AX5. Layouts reflow: cards stack vertically, two-column grids collapse, fixed-height rows become flex-height, truncation becomes wrapping.

Trip cards reflow horizontal→stacked at AX3+. Tab bar switches to large-content labels. Modals become fullscreen at AX5.

### E.6 VoiceOver

Every interactive view has `.accessibilityLabel("...")` describing purpose. "Heart" is not acceptable; "Save trip to favorites" is. Every button gets `.isButton`. Headers get `.isHeader`. Selectable get `.isSelected` conditionally. Toggles convey state via `.accessibilityValue("On"|"Off")`.

Rotor support: trip detail exposes "trip segments" rotor. Trip list exposes "trips" rotor. Settings expose "sections" rotor. Via `.accessibilityRotor`.

Hints only when non-obvious. Composite views use `.accessibilityElement(children: .combine)` with natural-reading label.

### E.7 Voice Control

iOS Voice Control requires verbal labels. Icon-only buttons without labels are invisible to Voice Control and banned. Test with "Show Names" overlay — every primary interactive surface must show a label.

Gestures without buttons (swipe to dismiss, long-press to reorder) need Voice Control alternatives: visible menu item, `.accessibilityAction`, custom command via `.accessibilityAction(.default)`.

### E.8 Reduced Motion

Observed at render time. When true:
- AuroraBackground frozen at midpoint.
- Orb breath replaced by static orb.
- ESANG burst replaced by opacity crossfade.
- Parallax disabled.
- Shared-element transitions become crossfades.
- Aurora flow replaced by solid `bgPage`.
- Decorative particles suppressed.

Functional animations (progress bar, chevron rotate on expand, toggle slide) continue at reduced duration (150ms vs 300ms) without overshoot.

Global `@Environment(\.accessibilityReduceMotion)` feeds a `MotionPolicy`. Components ask the policy.

### E.9 Reduced Transparency

AuroraBackground collapses to solid `bgPage`. Frosted-glass card backgrounds become opaque `bgElevated`. Nav bar translucency → opaque. Sheet dimmed backdrop → solid scrim.

Tested independently in both registers at all Dynamic Type sizes.

### E.10 Increased Contrast

Cards gain 1.5pt `borderStrong` borders where they had none or `borderSubtle`. Subtitle greys promoted to `textPrimary`. Focus rings thicken 2pt→3pt. Icon strokes thicken. Dividers become visible.

Two render paths per card component, selected by environment.

### E.11 Bold Text

Promotes every weight by one step. Handled centrally in `EusoText` wrapper. Custom fonts that lack intermediate weights fall back to nearest available, then to system font.

### E.12 Differentiate Without Color

Every status-colored element carries a non-color differentiator. Green success → checkmark glyph + "Completed" label. Amber warning → triangle + "Attention." Red error → X or exclamation + "Error." Holds even for color-sighted users (reduces cognitive load).

Graphs use shapes or patterns per series. Map pins use distinct silhouettes, not only color. Selected vs unselected tabs differ in weight and underline, not only tint.

### E.13 Hearing — captions for ESANG voice

Every ESANG voice output generates a simultaneous TranscriptTile. Persists for duration + three-second dwell, available in session history. Always on.

Audio alerts have visual twins (toast, banner, flash).

### E.14 Motor — configurable thresholds

Long-press threshold configurable 200ms–1200ms in settings. 8pt minimum buffer between tap targets. Swipes always have a button alternative. Drag gestures have non-drag alternative through edit mode or accessibility action. Shake-to-undo supplemented by visible Undo toast for 5s. Force touch / 3D Touch never the only path.

### E.15 Cognitive — plain English

Error messages: what happened + why + what to do. "Network error code 503" is banned. "We couldn't reach the server. Check your connection and try again, or tap Retry below." is the pattern.

No jargon in consumer copy. Deep flows carry breadcrumb headers. Users can back out without data loss; forms autosave.

### E.16 Pulse Watch a11y

watchOS 44×44 target floor with primary actions at full available width. Every visual state has haptic alternative:
- Orb pulse healthy → `Haptic.directionUp`.
- Attention → `Haptic.notification`.
- Emergency → `Haptic.failure`.

Digital Crown supported for every list and numeric selector. VoiceOver on watchOS tested independently. Always-on display legible at active-display contrast.

### E.17 AssistiveTouch

Every gesture has an AssistiveTouch-reachable alternative — visible button, `.accessibilityAction`, or iOS-standard path.

### E.18 Language and region — RTL-safe

Leading/trailing semantics, not left/right. Mirrored icons registered in asset catalog. Text alignment `.leading`/`.trailing`. Pseudo-localization at every RC. Arabic not launch but layouts must be RTL-safe today.

### E.19 Driver-specific accessibility

Driving is an accessibility mode in its own right. First-class.

- **Glove-friendly tap buffer.** Primary driving CTAs extend hit regions to 80pt. Visual button normally sized; invisible hit region grows.
- **High-sun readability.** Above ambient-light threshold (`UIScreen.main.brightness` proxy or ALS), Afternoon register shifts to high-contrast sub-register. Text scales up one Dynamic Type step automatically when driving mode is active.
- **Night-driving Night default.** After sunset, Night register becomes default regardless of system. Red-shifted accents replace blue for night vision. Orb uses dimmer baseline luminance.
- **Voice-first.** Every driving-mode task completable through ESANG alone. Superset of VoiceOver — requires conversational intent model mapping natural speech to every action.

### E.20 Closing standard

Three gates: design review (contrast, layout, Dynamic Type, differentiation), engineering review (labels, traits, focus, announcements), release QA (full matrix: VoiceOver, Voice Control, AssistiveTouch, Switch Control sample, 5 AX sizes, both registers, Reduced Motion on/off, Reduced Transparency on/off, Increased Contrast on/off, Bold Text on/off). No release with any open accessibility regression. A11y debt is P0 debt. Every screen. Every component. Every release.

---

## Closing

This document is the brand DNA, gradient doctrine, forbidden design rules, design token catalog, component API, screen anatomy, microcopy voice, and accessibility substrate for the EusoTrip 2027 mobile app. Every other team's deliverable defers to these values.

The gradient is the tagline. The orb is the voice. The palette is the lighting. The typography is the discipline. The copy is blue-collar-fluent and never patronizing. The accessibility is the substrate. That is the app.

**Cross-links.**
- Engineering rules that enforce this doctrine: [02_Engineering_Principles.md](./02_Engineering_Principles.md).
- How this doctrine plays across web: [91_Web_Mobile_Parity.md](./91_Web_Mobile_Parity.md).
- How Figma maps to real procedures: [85_Figma_Gap_Audit_and_Recommendations.md](./85_Figma_Gap_Audit_and_Recommendations.md).
- Copy for emergencies and SOS: [70_Messaging_and_ESANG_AI.md](./70_Messaging_and_ESANG_AI.md) + [80_User_Journeys_and_Load_Lifecycle.md#7-12-incident-journey](./80_User_Journeys_and_Load_Lifecycle.md).

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
