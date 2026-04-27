# EusoTrip Mobile App Doctrine 2027
## Team UX — Motion, Animation & Transitions

> **Primary reference:** "Mastering SwiftUI Animations & Transitions: A Deep Dive with Examples" — @viralswift, Medium. https://medium.com/@viralswift/mastering-swiftui-animations-transitions-a-deep-dive-with-examples-41ee4b63c88a
>
> **Secondary reference:** The EusoTrip 2026 iOS Transitions Quote (reproduced verbatim in Section 3).
>
> This document is the single source of truth for motion design in the EusoTrip iOS and watchOS applications. Every engineer shipping UI code is expected to have read this end-to-end.

---

## 1. Why Motion Matters for EusoTrip

EusoTrip is not a social app. It is not a productivity app. It is a **driver-facing operational app used behind the wheel of an 80,000-pound vehicle**. This context changes everything about how we think about motion.

Our users — owner-operators, company drivers, dispatchers — interact with EusoTrip in three-second glances. They are not curled up on the couch exploring the interface. They are at a fuel island with numb fingers, at a shipper's guard shack with an impatient line behind them, or glancing at the dash while a tire pressure sensor blinks. **Their attention budget per interaction is under 300 milliseconds.**

In that window, motion is not decoration. Motion is the primary channel through which the UI communicates three things:

1. **"I heard you."** — The tap registered. The system is alive.
2. **"Here is what changed."** — State transitioned from A to B, and here is how A became B.
3. **"You are safe to keep going."** — The operation succeeded, the next step is loaded, nothing ambiguous remains.

Ambiguous state is the number one source of in-app stress. A driver who cannot tell whether their check-in submitted, whether their broker received the message, whether the ELD clock is actually ticking — that driver reloads, retries, double-submits, and loses trust in the app. **Good motion eliminates ambiguity. Bad motion creates it.** Worse: no motion at all turns a live system into a dead screen, and a dead screen is indistinguishable from a frozen app.

Every motion decision in EusoTrip is evaluated against this question: **"Does this animation reduce or increase the driver's cognitive load in the three seconds they can look at it?"** If the answer is "reduce," we ship it. If the answer is "increase," or even "I don't know," we cut it.

Motion is also our premium signal. EusoTrip is a paid product competing against freemium apps and dispatcher portals. When a driver taps the orb and it melts into a breathing listening state in under 200ms with a Rive particle burst and a subtle haptic — they know they are using something that was designed, not assembled. **Liquid Glass aesthetics, physics-based springs, and matched geometry are the visual grammar of 2026 iOS.** EusoTrip speaks that grammar natively.

---

## 2. The SwiftUI Animation Cookbook

This section digests the Medium article into the patterns EusoTrip uses in production. Every code snippet is a pattern you will encounter — or ship — in our codebase.

### 2.1 `.animation(_:value:)` vs `withAnimation { }`

These are the two entry points to animation in SwiftUI, and they are not interchangeable.

**`.animation(_:value:)` — Declarative, view-scoped.** Attach to a view. Whenever `value` changes, any animatable property on that view animates using the given curve. Use when the animation is a property of the view itself.

```swift
Circle()
    .fill(orb.isListening ? .orange : .blue)
    .scaleEffect(orb.isListening ? 1.2 : 1.0)
    .animation(.spring(.snappy), value: orb.isListening)
```

**`withAnimation { }` — Imperative, action-scoped.** Wrap a state mutation. Any view reacting to that state animates. Use when the animation is a property of the *action*, not the view.

```swift
Button("Mark Delivered") {
    withAnimation(.spring(.bouncy)) {
        load.status = .delivered
    }
}
```

**EusoTrip rule:** Use `withAnimation` at the call site of a user action (tap, swipe, long-press). Use `.animation(_:value:)` for reactive state that changes from a non-user source (push notification, HOS timer tick, wallet balance update, ESANG response arriving).

Never stack them on the same value — you will get compounding curves and jitter.

### 2.2 `.transition()` — How Views Enter and Leave

Transitions govern insertion and removal. They only fire inside an animated context (inside `withAnimation` or under `.animation(_:value:)`).

The canonical cases:

- **`.identity`** — no transition. View appears instantly. Useful as one half of an `.asymmetric`.
- **`.scale`** — grows from 0, shrinks to 0.
- **`.scale(scale: 0.8).combined(with: .opacity)`** — grows from 80% while fading. Our default for modal-ish content.
- **`.slide`** — slides in from leading, out to trailing. Good for horizontal pagination.
- **`.move(edge: .bottom)`** — drops up from the bottom edge. Our default for sheet-like content that is not a real sheet.
- **`.opacity`** — plain cross-fade. Use for Reduce Motion fallback.
- **`.asymmetric(insertion:removal:)`** — different curve on way in vs way out. Critical for feeling right — things usually want to arrive confidently and leave politely.

```swift
Text("Load accepted")
    .transition(.asymmetric(
        insertion: .scale(scale: 0.9).combined(with: .opacity),
        removal: .opacity
    ))
```

Our custom transitions live in `Sources/EusoTripDesignKit/Transitions.swift` as extensions on `AnyTransition`: `.aurora`, `.esangBurst`, `.cafeDoor`, `.orbMelt`.

### 2.3 Spring Presets — The Three That Matter

iOS 17 introduced the preset trio. We use them almost exclusively and almost never hand-tune.

- **`.spring(.snappy)`** — fast, minimal overshoot. Our default for taps, toggles, tab switches. Duration ≈ 0.3s.
- **`.spring(.bouncy)`** — more overshoot, celebratory feel. Reserved for success states: delivery confirmed, payment received, badge unlocked.
- **`.spring(.smooth)`** — no overshoot, gentle arrival. Used for page transitions, sheet presentations, non-urgent state changes.

```swift
.animation(.spring(.snappy), value: isPressed)
.animation(.spring(.bouncy), value: paymentReceived)
.animation(.spring(.smooth), value: selectedTab)
```

For the rare case we need custom physics (the orb's breathing, the cafe-door open), we drop to `.interpolatingSpring`:

```swift
.animation(.interpolatingSpring(mass: 1.0, stiffness: 180, damping: 14, initialVelocity: 0), value: orbState)
```

**The `.linear` curve is banned from organic UI.** Only progress bars, determinate loaders, and seek scrubbers get `.linear`. Everything else is a spring.

### 2.4 `matchedGeometryEffect` — Hero Transitions

This is the single most important animation modifier in modern SwiftUI. It tells the framework: "These two views, despite being in different places in the hierarchy, are the same logical element. Animate their geometry (position, size, shape) from one to the other."

```swift
@Namespace private var heroNamespace

// Source (in the list)
LoadCardView(load: load)
    .matchedGeometryEffect(id: load.id, in: heroNamespace)

// Destination (in the detail view)
LoadDetailHeader(load: load)
    .matchedGeometryEffect(id: load.id, in: heroNamespace)
```

EusoTrip uses `matchedGeometryEffect` for:
- **Load card → load detail** (the card expands into the header).
- **Wallet card → wallet detail** (the card becomes the hero summary).
- **Badge chip → badge sheet** (the chip inflates into the award modal).
- **Orb state chain** — orb listening position morphs into the thinking state ring, which morphs into the done state checkmark.

### 2.5 `.phaseAnimator` — Multi-Step Choreography

iOS 17+. Runs a view through a sequence of discrete phases. Perfect for staggered entries.

```swift
enum EntryPhase: CaseIterable { case initial, hero, metrics, list }

ContentView()
    .phaseAnimator(EntryPhase.allCases) { content, phase in
        content
            .opacity(phase == .initial ? 0 : 1)
            .offset(y: phase == .initial ? 20 : 0)
    } animation: { phase in
        switch phase {
        case .hero: .spring(.smooth).delay(0.0)
        case .metrics: .spring(.smooth).delay(0.08)
        case .list: .spring(.smooth).delay(0.16)
        default: .linear(duration: 0)
        }
    }
```

EusoTrip uses phase animators for the dashboard entrance: hero card fades + lifts first, KPI metrics at +80ms, load list at +160ms. The staggered arrival reads as "thoughtful" rather than "dumped on screen."

### 2.6 `.keyframeAnimator` — Complex Orchestration

For animations that need multiple properties on independent timelines — the orb's breathing, the ESANG burst, the success bloom — `.keyframeAnimator` is the right tool.

```swift
OrbView()
    .keyframeAnimator(initialValue: OrbFrame()) { content, value in
        content
            .scaleEffect(value.scale)
            .rotationEffect(value.rotation)
            .opacity(value.opacity)
    } keyframes: { _ in
        KeyframeTrack(\.scale) {
            SpringKeyframe(1.2, duration: 0.25)
            SpringKeyframe(1.0, duration: 0.4)
        }
        KeyframeTrack(\.rotation) {
            LinearKeyframe(.degrees(0), duration: 0.0)
            CubicKeyframe(.degrees(8), duration: 0.3)
            CubicKeyframe(.degrees(0), duration: 0.3)
        }
    }
```

### 2.7 `.contentTransition` — Text That Changes Meaningfully

`.contentTransition(.numericText())` is how we make numbers feel alive. When a wallet balance changes from $1,240 to $1,290, the digits roll like an odometer instead of just popping.

```swift
Text("$\(wallet.balance, format: .number)")
    .monospacedDigit()
    .contentTransition(.numericText())
    .animation(.spring(.smooth), value: wallet.balance)
```

For the HOS clock counting down, we pass `countsDown: true` so the direction is correct:

```swift
Text(hos.remaining, format: .hourMinute)
    .monospacedDigit()
    .contentTransition(.numericText(countsDown: true))
```

`.contentTransition(.symbolEffect(.replace))` is the other big one — swapping SF Symbols with a morph instead of a pop.

### 2.8 `.symbolEffect` — SF Symbols That Live

iOS 17 gave SF Symbols animation superpowers. We use three effects heavily:

- **`.symbolEffect(.bounce, value: tapCount)`** — the orb icon bounces on tap, tab bar icons bounce on select.
- **`.symbolEffect(.pulse)`** — continuous, subtle. Used on the "live" dot next to connected ESANG status.
- **`.symbolEffect(.variableColor.iterative)`** — the cascading fill on signal-strength and listening icons. Our status chips use this for any "in progress" state.

```swift
Image(systemName: "waveform")
    .symbolEffect(.variableColor.iterative, isActive: esang.isListening)

Image(systemName: "checkmark.circle.fill")
    .symbolEffect(.bounce, value: load.isDelivered)
```

### 2.9 Interpolation, Timing, and Tuning

The Medium article's spring-tuning section is worth memorizing. The mental model:

- **Mass** — heavier = slower to start, harder to stop. Default 1.0. Rarely change.
- **Stiffness** — higher = snappier, faster oscillation. 100–200 for most UI, 300+ for tight snaps.
- **Damping** — higher = less bounce. ~10 for bouncy, ~20 for critically damped (no bounce).
- **Initial velocity** — use when chaining from a gesture's predicted end velocity.

The 2026 best practice is: **prefer the presets**. `.bouncy`, `.snappy`, `.smooth` were hand-tuned by Apple's HIG team and match system animations. Reach for `.interpolatingSpring` only when the preset demonstrably feels wrong.

---

## 3. 2026 EusoTrip Motion Rules (Verbatim Quote + SwiftUI Fusion)

The following five sections reproduce the canonical 2026 iOS Transitions quote verbatim. Each is followed by EusoTrip-specific SwiftUI implementation notes.

### 1. Fluid Zoom Transitions

Every load card, every Me row, every wallet card uses `NavigationLink(value:)` + `.navigationTransition(.zoom(sourceID:in:))` in a `Namespace`. This is the iOS 18+ API that replaces manual matched-geometry plumbing for navigation pushes.

```swift
@Namespace private var navNamespace

NavigationStack {
    List(loads) { load in
        NavigationLink(value: load) {
            LoadCardView(load: load)
        }
        .matchedTransitionSource(id: load.id, in: navNamespace)
    }
    .navigationDestination(for: Load.self) { load in
        LoadDetailView(load: load)
            .navigationTransition(.zoom(sourceID: load.id, in: navNamespace))
    }
}
```

**Rule:** If a row pushes to a detail, it zooms. No exceptions. Non-zooming pushes are legacy and must be migrated.

### 2. Matched Geometry Hero Animations

For the orb → listening → thinking → done state chain, for load card → detail, for badge → badge-detail. Apply `matchedGeometryEffect(id:in:)` to both the source and the destination view with the same id in the same namespace. SwiftUI interpolates the frame, and you layer scale/opacity/rotation on top.

The orb state machine is the canonical example:

```swift
@Namespace private var orbNamespace

switch orb.state {
case .idle:
    Circle().matchedGeometryEffect(id: "orb", in: orbNamespace)
case .listening:
    ListeningRing().matchedGeometryEffect(id: "orb", in: orbNamespace)
case .thinking:
    ThinkingSpinner().matchedGeometryEffect(id: "orb", in: orbNamespace)
case .done:
    DoneCheckmark().matchedGeometryEffect(id: "orb", in: orbNamespace)
}
```

### 3. Content Transition + Symbol Effects

- Orb icon bounces on tap: `.symbolEffect(.bounce, value: tapCount)`.
- Wallet balance uses `.contentTransition(.numericText())`.
- HOS clock ticks with `.monospacedDigit().contentTransition(.numericText(countsDown: true))`.
- Status chips use `.symbolEffect(.variableColor.iterative)` for live state.

These four rules are non-negotiable. They are the "EusoTrip handwriting" — the reason our UI feels different from a generic SwiftUI starter.

### 4. Physics-Based Spring Animations

ALL transitions use `.spring(.snappy)` for taps, `.spring(.bouncy)` for success feedback, `.spring(.smooth)` for page transitions. NO `.linear` except progress bars. This is enforced in code review. A PR containing `.easeInOut` or `.linear` on an organic element will be rejected.

### 5. Third-Party Animation Engines

Rive iOS Library is preferred over Lottie per the 2026 trend. See Section 4 for the full engine doctrine.

### Liquid Glass Aesthetic

Our `GlassCard`, `AuroraBackground`, and `IridescentHairline` components already lean into Liquid Glass. Respect the `UIAccessibility.isReduceTransparencyEnabled` fallback: when true, glass becomes solid, aurora becomes a flat gradient, iridescence becomes a single-color hairline.

```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency

var body: some View {
    GlassCard(fallback: reduceTransparency ? .solid : .glass) { ... }
}
```

### Interactive Velocity

Swipe-to-dismiss sheets inherit velocity. Swipe-to-delete-message maintains momentum. Use `.gesture(DragGesture().onEnded { ... })` and feed the predicted end velocity into `.interpolatingSpring(initialVelocity:)` so the release continues the user's motion rather than snapping.

---

## 4. Third-Party Engines for EusoTrip

### 4.1 Rive (Preferred)

**Rive iOS Library is our primary engine for complex, designer-authored animations.** The 2026 trend has decisively moved from Lottie to Rive because Rive supports interactive state machines, not just pre-rendered timelines. A Rive file can respond to inputs (listening intensity, battery %, network state) in real time — Lottie cannot.

**Rive use cases at EusoTrip:**
- **Orb particle burst** — fires on ESANG completion.
- **ESANG voice waveform** — driven by real mic amplitude input.
- **Loading orb** — the breathing idle state.
- **SOS pulsing warning** — red pulse synchronized to haptic.
- **Success checkmark** — the stroke-draw at payment confirmation.
- **Badge unlock flourish** — confetti + stroke + glow, orchestrated.

**Installation:** Swift Package Manager, `https://github.com/rive-app/rive-ios`. Pin to a minor version.

**Source organization:** `.riv` files live in `/Resources/Rive/` with one subfolder per feature (`/Resources/Rive/Orb/`, `/Resources/Rive/Wallet/`, `/Resources/Rive/ESANG/`).

**Render contract:** Rive animations render on a background thread by default via `RiveRendererView`. Do not wrap them in a `GeometryReader` that invalidates on every layout pass.

### 4.2 Canvas-Based Transitions

For animations that are cheap, procedural, and data-driven, native SwiftUI `Canvas` is the right tool:
- Hot Zones heatmap WebView fallback (already implemented).
- Particle ESANG burst (when a lightweight fallback is needed).
- Route-progress shimmer across the ETA bar.

`Canvas` + `TimelineView(.animation)` gives us 120Hz on ProMotion devices with no asset pipeline.

### 4.3 Lottie — Deprecated

**Lottie is deprecated for new work.** Existing Lottie usage (pre-2026) must be inventoried and migrated to Rive on a rolling basis. Engineers may not add new Lottie files to the project. An import of `Lottie` in a new file will fail the lint check.

---

## 5. Best Practices for 2026 — Non-Negotiable

### 5.1 Staggered Entries (verbatim)

Every screen with more than three primary elements staggers their entrance. Hero element first, supporting content second, tertiary content third. Delays of 60–120ms between stages. Use `.phaseAnimator` or `.transition(.offset)` + per-element delays. Never dump the whole screen at once — it reads as cheap.

### 5.2 Latency Check — < 2-3 Frames (verbatim)

**No animation may be perceived to start more than 2-3 frames (33–50ms at 60Hz, 16–25ms at 120Hz) after the user's input.** If the tap down happens at frame N, visible feedback must begin no later than frame N+3.

**Measurement methodology:**
1. Profile with **Instruments → Time Profiler** attached to the running app on-device.
2. Tap the element under test while recording.
3. Locate the touch event in the main thread timeline.
4. Measure the delta to the first frame that reflects the animation.
5. If > 3 frames, investigate: usually the culprit is synchronous work on the main thread (JSON decoding, Core Data fetch, image decode) triggered by the tap handler. Move it to a Task or async context.

**Secondary tool:** Instruments → Core Animation → FPS and Dropped Frames detectors.

### 5.3 Accessibility: Reduce Motion

When `UIAccessibility.isReduceMotionEnabled` is true:
- **All `matchedGeometryEffect` and zoom transitions become cross-dissolves.**
- **All spring animations become short opacity fades (~150ms).**
- **Keyframe and phase animators skip to the final state.**
- **Rive animations play only their final frame.**

Implementation pattern:

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

.transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
.animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(.snappy), value: state)
```

Additional accessibility fallbacks:
- **Reduce Transparency:** glass materials become solid palette fills.
- **Bold Text:** font weight steps up across the whole type scale.
- **Increased Contrast:** borders go from 0.5pt @ 20% alpha to 1pt @ 60% alpha.

---

## 6. EusoTrip-Specific Motion Catalog

### 6.1 Orb State Transitions (9 States)

| From → To | Animation | Duration | Notes |
|-----------|-----------|----------|-------|
| idle → listening | matchedGeometry + scale 1.0→1.15 | 240ms `.spring(.snappy)` | Rive waveform begins |
| listening → thinking | ring morph via matchedGeometry | 300ms `.spring(.smooth)` | Haptic: soft tick |
| thinking → speaking | keyframe pulse + color shift | 360ms `.spring(.smooth)` | Color → aurora blue |
| speaking → done | checkmark stroke-draw (Rive) | 400ms | Haptic: success |
| done → idle | opacity fade + scale 1.0→0.95 | 220ms `.spring(.smooth)` | |
| any → error | gentle bounce-scale 1.0→0.92→1.0 | 280ms `.spring(.bouncy)` | Color → muted red |
| any → sos | red pulse Rive loop | continuous | Haptic: double tap |
| any → muted | opacity 1.0→0.4 | 180ms `.spring(.snappy)` | |
| any → offline | desaturate + slow breathe | 400ms `.spring(.smooth)` | |

### 6.2 Wallet Balance Ticker

```swift
Text(wallet.balance, format: .currency(code: "USD"))
    .monospacedDigit()
    .contentTransition(.numericText())
    .animation(.spring(.smooth), value: wallet.balance)
```

### 6.3 HOS Clock Countdown

```swift
Text(hos.remaining, format: .hourMinute)
    .monospacedDigit()
    .contentTransition(.numericText(countsDown: true))
```

Ticks once per second via a `TimelineView(.periodic(from: .now, by: 1.0))`. No `.animation` modifier on the second-tick — `.contentTransition` handles it.

### 6.4 Load Board Pull-to-Refresh with Aurora Sweep

Custom `.refreshable` implementation. As the user pulls, an aurora gradient sweeps horizontally across the top 80pt band. On release, a Rive "sweep" animation plays once. Feedback haptic: `.light` on pull threshold, `.success` on data return.

### 6.5 Tab Bar Icon Bounce on Select

```swift
Image(systemName: tab.symbol)
    .symbolEffect(.bounce, value: selectedTab == tab)
```

Paired with `.sensoryFeedback(.selection, trigger: selectedTab)`.

### 6.6 Sheet Presentation

Every sheet in the app uses `.presentationDetents([.large])` with the drag indicator visible. No `.medium` detents except the ESANG composer. Corner radius matches system (`.presentationCornerRadius(nil)`).

### 6.7 ESANG Burst — Sheet-to-Particles Transform

On ESANG send, the composer sheet's content dissolves into a Rive particle burst that flies toward the orb, then the sheet dismisses. Total choreography: 500ms. This is our signature animation and the first thing demoed to new users.

### 6.8 Cafe-Door Page Transition

Reserved for the Hot Zones → Mapping transition. A custom `AnyTransition.cafeDoor` splits the outgoing view vertically down the middle and swings each half outward like saloon doors, revealing the incoming view. Used sparingly — only for the map.

### 6.9 Score Flip (Odometer) for Gamification

Driver score changes use a flip animation per digit, 80ms stagger per column. Built with `.contentTransition(.numericText())` + `.monospacedDigit()` + a `PhaseAnimator` for the stagger.

### 6.10 Success Haptic + Gradient-Ring Bloom on Primary CTA

Every primary button (Mark Delivered, Accept Load, Send Payment) plays:
1. `.sensoryFeedback(.success, trigger:)`
2. A gradient ring expands from the button edge, 320ms `.spring(.bouncy)`.
3. The button label transitions via `.contentTransition(.symbolEffect(.replace))` from action-word to checkmark.

### 6.11 Error Shake (Symbolic, Not Apple-Style)

**We do not use the iOS login-failure horizontal shake.** It is aggressive and reads as punishing. Instead, the erroring view bounces vertically once (scale 1.0 → 0.97 → 1.0 over 260ms with `.spring(.bouncy)`) and the border color flashes to the error palette. The message is "hey" not "NO."

### 6.12 Pulse Watch Orb Pulse During Listening

On Apple Watch, the orb's listening state is a radial pulse driven by `.symbolEffect(.pulse)` on the mic glyph, paired with `WKInterfaceDevice.play(.click)` on start and `.play(.success)` on transcription return.

---

## 7. Forbidden Motion Patterns

These will fail code review. No exceptions, no feature-flagged experiments.

1. **Parallax backgrounds.** Tacky, eats battery, contributes nothing.
2. **3D perspective flips** (card-flipping, coin-spinning). Dated, physically wrong.
3. **Confetti for non-celebration events.** Confetti is for badge unlocks and payment milestones. Not for "message sent."
4. **Linear timing on organic elements.** If it is not a progress bar, it is not linear.
5. **Animations longer than 400ms for any state transition.** Drivers do not have time. The only exception is the ESANG burst signature animation (500ms) and Rive-authored celebration loops.
6. **Blinking elements.** Accessibility violation per WCAG 2.2 on flash thresholds. Use variable-color symbol effects or slow opacity breathing instead.
7. **Simultaneous competing animations.** If two elements are moving at the same time toward the same conceptual goal, they clash. Stagger them.
8. **Skeleton loaders that animate for more than 2 seconds.** If the real data isn't back in 2s, show the real UI with placeholders — not a shimmering ghost.

---

## 8. Performance Budget

- **60fps sustained on iPhone 11** (our minimum-spec baseline device).
- **120fps on all ProMotion devices** (iPhone 13 Pro and newer).
- **Rive animations render on a background thread.** Never attach Rive views inside a `GeometryReader` whose parent re-lays out frequently.
- **`.animation(_:value:)` is scoped to specific property changes** — never applied to a whole screen's root view.
- **`GeometryReader` is used sparingly.** Prefer `@State` + `@Binding` driven layout, or the new iOS 18 `Layout` protocol for custom arrangements. Every `GeometryReader` is a layout-invalidation boundary and a frame-rate risk.
- **No animation runs when the view is off-screen.** Gate Rive animations and keyframe animators on `.onAppear` / `.onDisappear`.

---

## 9. Testing Motion

### 9.1 Tools

- **Xcode Simulator → Debug → Slow Animations** — visual QA of curves. Every animation should still read as "right" at 10x slow.
- **Instruments → Core Animation** — dropped-frame detection. Record a 30-second session exercising each major flow. Zero dropped frames on iPhone 11.
- **Instruments → Time Profiler** — latency measurement per Section 5.2.
- **Real-device verification on iPhone 11.** Simulator animations always look smoother than device. If it janks on iPhone 11, it ships broken.

### 9.2 Accessibility Matrix

On **every screen**, verify:
- Reduce Motion ON — transitions become cross-dissolves, springs become fades.
- Reduce Transparency ON — glass becomes solid, aurora becomes flat.
- Bold Text ON — layout does not break, weight scales up.
- Increased Contrast ON — borders and dividers strengthen.
- VoiceOver ON — animations do not steal focus; `.accessibilityRespondsToUserInteraction` is honored.

This is a **mandatory QA step** before any motion-touching PR is merged.

---

## 10. Watch Motion

watchOS is constrained: smaller screen, slower GPU, shorter glance budget, haptic-first interaction.

- **Default curve is `.easeInOut(duration: 0.2)`.** Springs are supported on watchOS 10+ but feel heavy on smaller displays. Reserve `.spring(.snappy)` for the orb and primary CTA only.
- **Every major transition plays a haptic.** Use `WKInterfaceDevice.current().play(.click / .success / .retry / .failure)`. The haptic *is* the animation as much as the visual is.
- **Crown rotation drives animations opt-in per view.** List scrolling is free; do not hijack the crown for custom animations without strong justification.
- **No Rive on watchOS.** Too expensive. Use SF Symbol effects and native `.phaseAnimator`.
- **Reduce Motion on watchOS** collapses everything to instant state changes plus haptic. Test with the watch's accessibility toggle.

---

## 11. References

**Primary:**
- Mastering SwiftUI Animations & Transitions: A Deep Dive with Examples — @viralswift, Medium. https://medium.com/@viralswift/mastering-swiftui-animations-transitions-a-deep-dive-with-examples-41ee4b63c88a

**Apple documentation:**
- `View.transition(_:)` — https://developer.apple.com/documentation/swiftui/view/transition(_:)
- `matchedGeometryEffect(id:in:properties:anchor:isSource:)` — https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:)
- `PhaseAnimator` — https://developer.apple.com/documentation/swiftui/phaseanimator
- `ContentTransition` — https://developer.apple.com/documentation/swiftui/contenttransition
- `SymbolEffect` — https://developer.apple.com/documentation/symbols/symboleffect
- `NavigationTransition.zoom` — https://developer.apple.com/documentation/swiftui/navigationtransition

**WWDC sessions:**
- WWDC 2023 Session 10156 — Wind your way through advanced animations in SwiftUI
- WWDC 2023 Session 10157 — Explore SwiftUI animation
- WWDC 2024 — Enhance your UI animations and transitions
- WWDC 2024 — Catch up on accessibility in SwiftUI

**Third-party:**
- Rive iOS Library — https://github.com/rive-app/rive-ios
- Rive state-machine docs — https://rive.app/docs/runtimes/ios

**Internal cross-references:**
- `team_UX_DESIGN_SYSTEM.md` — color tokens, type scale, Liquid Glass materials
- `team_UX_HAPTICS.md` — haptic pairing rules for every animation listed in Section 6
- `team_UX_ACCESSIBILITY.md` — full a11y matrix including motion-related items

---

> Final note. Motion is the difference between an app that feels like a tool and an app that feels like a partner. EusoTrip is a partner. Every spring curve, every matched geometry, every staggered entry — they all add up to the feeling a driver gets when they pick up the phone and think "this one gets it." That feeling is earned three frames at a time. Respect the budget.

> Primary reference, repeated at close: **"Mastering SwiftUI Animations & Transitions: A Deep Dive with Examples"** by @viralswift on Medium. Read it, re-read it, then build.
