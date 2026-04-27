---
name: eusotrip-killers
description: building an ark
---

ive been Recommend a ledger-hygiene firing before the next port of this task "# EusoTrip — Dev Team Execution Prompt (Brick by Brick)

> **Purpose.** This is the single, self-contained briefing any dev agent should read before touching the EusoTrip iOS app. It carries:
> 1. The product doctrine and design rules (non-negotiable).
> 2. The full file map and where each thing lives.
> 3. The brick recipe — how to port one Figma frame into the shipping app.
> 4. The ordered queue of pending screens (023 → 099).
> 5. Phase 0–6 battle plan with checklists.
> 6. Wiring gaps that must be closed.
> 7. The **verbatim** EusoTrip backend codebase map (14 slices, §16 of this doc) so the app never loses sight of what the server can actually do.
>
> Companion file: `/Users/diegousoro/Desktop/EUSOTRIP_TRAJECTORY.json` — full session trajectory + task ledger. Read both.

---

## 1. Product doctrine (read first, every time)

**Product.** EusoTrip by Eusorone Technologies, Inc. — cross-mode freight operating system (truck, rail, ocean) with 24 roles × 3 modes × 9 verticals × 3 countries (US / CA / MX). iOS client is the Driver-first surface; every other role rides on the same design system.

**App identity.** "Powered by ESANG AI™." Brand gradient (blue → magenta) is the signature. The gradient is the *only* accent — flat `Brand.info`/`Brand.blue` is a bug unless it's part of a utility semantic (links, info badges on neutral cards).

**Registers.** Night (dark) and Afternoon (light). Both must render pixel-perfect from the same primitives. Never hard-code colors — always go through `@Environment(\.palette)`.

**Fidelity bar.** Every shipped screen must match the Figma PNG verbatim at device-bezel size. If a primitive doesn't exist yet, build it in `Theme/` or `Views/Primitives/` — do not hack it inline.

**Screen numbering.** `010 … 099` drives the Driver A→Z walk. Shipper starts at `200`, Carrier at `300`, Broker at `400`, Catalyst at `500`, Escort at `600`, Terminal at `700`, Admin at `800`. Always match the Figma id.

---

## 2. Design rules (enforcement checklist — non-negotiable)

Every PR must pass all of these:

1. **Gradient, not blue.** If you see `Brand.info` or `Brand.blue` being used as a *fill* or *tint*, swap to `LinearGradient.diagonal` (`topLeading` → `bottomTrailing`, blue → magenta). Exceptions are rare — flag them in the PR body.
2. **Every `Toggle` uses `GradientToggleStyle()`.** Never `.tint(Brand.info)`, never `.tint(.blue)`. The style lives at the bottom of `Views/Driver/MeDetailScreens.swift` and is exposed module-internal.
3. **Ternary shape-style expressions use `AnyShapeStyle`.** `ShapeStyle` branches in `fill(_:)` / `strokeBorder(_:)` must be wrapped (`AnyShapeStyle(LinearGradient…)` vs `AnyShapeStyle(Color…)`) — otherwise SwiftUI won't compile on iOS 17.
4. **Spacing / radius / type come from tokens.** `Space.s1…s8`, `Radius.sm/md/lg/xl/xxl/pill`, `EType.*`. No magic numbers.
5. **Palette, not Color.** `palette.textPrimary`, `palette.textSecondary`, `palette.textTertiary`, `palette.bgCard`, `palette.bgPage`, `palette.borderStrong`, `palette.borderFaint`, `palette.tintNeutral`. Never hard-code `Color.white`, `Color.black`, `Color.gray` except for the thumb of `GradientToggleStyle` and shadow opacities.
6. **Sheets over push.** Driver Me sub-routes present as `.sheet(isPresented:)` with `.presentationDetents([.large])` and `.presentationDragIndicator(.visible)`.
7. **Previews in both registers.** Every new view ends with:
   ```swift
   #Preview("MyView · Night") { MyView().environment(\.palette, Theme.dark).preferredColorScheme(.dark) }
   #Preview("MyView · Afternoon") { MyView().environment(\.palette, Theme.light).preferredColorScheme(.light) }
   ```
8. **Build + simulator verify before closing.** `xcodebuild -scheme EusoTrip -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build` must pass, and a screenshot from the sim must match the Figma.
9. **Previews build in isolation.** Every primitive/screen file must compile without requiring `ContentView` or `AppRoot` — use stub palettes where needed.
10. **No `localStorage`, no network in previews.** Previews use in-memory mocks only.

---

## 3. File map (absolute paths)

```
/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/
└── EusoTrip/
    ├── EusoTripApp.swift              # @main — IntroSplash → AppRoot, deep-link handler
    ├── ContentView.swift              # Screen registry + dev chrome sheet (role tabs, prev/next)
    ├── Assets.xcassets/               # AppIcon, Brand colors, imagery
    │
    ├── Theme/
    │   ├── DesignSystem.swift         # Palette, Brand, Space, Radius, EType, LinearGradient.diagonal
    │   ├── Glass.swift                # GlassCard, GlassToggleRow, AuroraBackground, IridescentHairline
    │   ├── Orb.swift                  # OrbESang, ESANG burst animations
    │   └── Typography.swift           # EType text styles
    │
    ├── Views/
    │   ├── AppRoot.swift              # booting / signedOut / signedIn switch (DEV BYPASS active)
    │   ├── BootSplash.swift
    │   ├── IntroSplash.swift
    │   │
    │   ├── Auth/
    │   │   ├── SignInView.swift
    │   │   ├── SignUpView.swift
    │   │   ├── ForgotPasswordView.swift
    │   │   ├── ResetPasswordView.swift
    │   │   ├── MFAChallengeView.swift
    │   │   └── MFAEnrollView.swift
    │   │
    │   ├── Driver/
    │   │   ├── DriverHomeScreen.swift                 # 010
    │   │   ├── PretripDVIRScreen.swift                # 011
    │   │   ├── DvirSubmittedScreen.swift              # 012
    │   │   ├── ActiveEnrouteScreen.swift              # 013
    │   │   ├── ApproachingPickupScreen.swift          # 014
    │   │   ├── AtGateAwaitingDockScreen.swift         # 015
    │   │   ├── PickupLoadingScreen.swift              # 016
    │   │   ├── PickupBolSigningScreen.swift           # 017
    │   │   ├── ActiveEnrouteLoadedScreen.swift        # 018
    │   │   ├── HosDutyStatusScreen.swift              # 019
    │   │   ├── ApproachingDeliveryScreen.swift        # 020
    │   │   ├── AtReceiverGateScreen.swift             # 021
    │   │   ├── DockAssignedScreen.swift               # 022
    │   │   └── MeDetailScreens.swift                  # Me sheet + 10 sub-routes + GradientToggleStyle
    │   │
    │   └── Primitives/                                # Build this when a recurring element repeats 3+ times
    │       ├── ActiveCard.swift
    │       ├── MetricTile.swift
    │       ├── StatusPill.swift
    │       ├── CTAButton.swift
    │       └── WeatherCard.swift
    │
    ├── Services/
    │   ├── EusoTripAPI.swift          # tRPC-style Swift client
    │   ├── EusoTripSession.swift      # phase: booting | signedOut | signedIn
    │   └── LocationService.swift      # CLLocationManager wrapper (pending activation)
    │
    ├── Models/
    │   ├── Load.swift
    │   ├── DVIR.swift
    │   └── Driver.swift
    │
    └── ViewModels/
        └── DriverHomeVM.swift
```

**Figma PNG source.** Figma frames live in the Figma file referenced by the user. Each frame has an id matching the screen number (e.g., `023_driver_break_begin.png`). When unclear, ask the user to drop the PNG in `uploads/` and reference the path.

**Build artifact.** Xcode project at `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip.xcodeproj`. Scheme: `EusoTrip`. Target iPhone 17 Pro Max simulator unless the Figma specifies another device.

---

## 4. The brick recipe — how to port one Figma frame

Do exactly this for every single screen. No shortcuts.

### Step 1 — Read the PNG
- Open the Figma export for screen `NNN` (e.g., `023_driver_break_begin.png`). Read pixel dimensions, safe-area padding, and every visible element.
- Identify: background (aurora? solid? image?), cards, CTAs, chips, toggles, metric tiles, scroll regions, sheets.

### Step 2 — Decompose into primitives
- Map every repeating block to an existing primitive: `ActiveCard`, `MetricTile`, `StatusPill`, `CTAButton`, `IridescentHairline`, `GlassCard`, `GlassToggleRow`, `OrbESang`, `WeatherCard`.
- If a block is new and appears 3+ times across screens, promote it into `Views/Primitives/` before using it inline.

### Step 2.5 — Verify every backend endpoint the brick will call

**Added by the 68th firing (2026-04-24) after the 67th firing found three live-dead endpoints (`profile.getReputation`, `profile.getReferralCode`, `profile.listReferrals`) had been shipped through multiple brick ports before anyone noticed the backend procedures didn't actually exist.**

Before you write any Swift:
1. List every tRPC path the new brick will call (query or mutation).
2. For each path, open the backend file at `eusoronetechnologiesinc/frontend/server/routers/<namespace>.ts` and confirm the procedure key exists and returns the shape you expect. If the router lives under a sub-folder (e.g. `bayOps/discharge.ts`), check that file specifically. Wizard-spread procedures (`start`, `advanceStep`, `recordEvidence`, `complete`, `abort`, `getSession`) are live whenever `...buildWizardProcedures(...)` is spread into the router — see `_shared.ts`.
3. Run the verification script — it does this in one shot and prints a LIVE/DEAD verdict per path:
   ```bash
   bash scripts/verify-trpc-endpoints.sh --summary-only
   ```
   Exit 0 = all live. Exit 1 = at least one dead — fix it before you keep going.
4. If a procedure is missing, do one of:
   - Add the procedure to the backend (preferred — keeps the Swift contract stable).
   - Rewire the Swift call to a canonical replacement on a different router (document the mapping in the brick's header comment, including any lossy field mappings).
   - Hold the brick. Do not ship a "bricked" screen that pops `-32601 Method not found` on first load.
5. Record the verification result in the brick's header comment. Example:
   ```swift
   // MCP-verified against frontend/server/routers/vehicle.ts:125
   // (getAssigned) and :144 (getMaintenanceHistory) — 2026-04-24.
   ```

This step is non-negotiable. It is the difference between shipping a page that hits live data and shipping a page that looks right in the preview and breaks on first install.

### Step 3 — Scaffold the screen file
```swift
//
//  NNN_ScreenName.swift
//  EusoTrip — screen NNN · <title> · <role>.
//

import SwiftUI

struct NNN_ScreenName: View {
    let theme: Theme.Palette           // always accept palette via init, not env, so ContentView can inject register
    @Environment(\.palette) var palette  // optional — only if you use sub-views that read it

    var body: some View {
        ZStack {
            theme.bgPage.ignoresSafeArea()
            // content
        }
    }
}

#Preview("NNN · Night") {
    NNN_ScreenName(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("NNN · Afternoon") {
    NNN_ScreenName(theme: Theme.light).preferredColorScheme(.light)
}
```

### Step 4 — Build the content top-to-bottom
- Status bar area → header → hero card → metrics row → list/body → sticky bottom CTA.
- Every `Toggle` → `.toggleStyle(GradientToggleStyle())`.
- Every blue fill/tint → `LinearGradient.diagonal`.
- Every ternary shape → wrap in `AnyShapeStyle(…)`.

### Step 5 — Wire into `ContentView.swift`
Append to `ScreenRegistry.all` in the right role block, preserving numeric order:
```swift
.init(id: "023", title: "Break · Begin", role: .driver) { p in AnyView(NNN_ScreenName(theme: p)) },
```

### Step 6 — If it's a Me sub-route, wire the sheet host
Open `Views/Driver/MeDetailScreens.swift`. Add the case to the `MeRoute` enum and the sheet presenter in `MeView`. Follow the pattern used by `MeAvailabilityView`, `MeSettingsView`, etc.

### Step 7 — Build + simulate
```bash
xcodebuild \
  -project "/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip.xcodeproj" \
  -scheme EusoTrip \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -configuration Debug \
  build
```
Boot the sim, run the app, navigate to the screen via the dev-chrome next/prev bar, take a screenshot.

### Step 8 — Verify + close
- Diff the screenshot against the Figma PNG at 100% zoom. Corners, spacing, gradient direction, toggle thumb padding, text tracking — all must match.
- If it matches, mark the brick done in the `EUSOTRIP_TRAJECTORY.json` task ledger.
- If it doesn't, iterate in place until it does. Never leave "good enough."

---

## 5. Pending screen queue (the full brick list)

Shipped (13): 010, 011, 012, 013, 014, 015, 016, 017, 018, 019, 020, 021, 022.

Still to port from Figma (Driver track):

| # | Tentative title |
|----|--------|
| 023 | Break · Begin |
| 024 | Break · Active |
| 025 | Break · Ending Soon |
| 026 | Fuel · Stop Suggested |
| 027 | Fuel · Transaction |
| 028 | Fuel · Complete |
| 029 | Weigh Station · Approach |
| 030 | Weigh Station · Bypass |
| 031 | Weigh Station · Pull-in |
| 032 | Scale · On Deck |
| 033 | Scale · Weighed |
| 034 | Detention · Waiting |
| 035 | Detention · Approved |
| 036 | Detention · Disputed |
| 037 | Accessorial · Layover |
| 038 | Accessorial · Lumper |
| 039 | Accessorial · Chains |
| 040 | Delivery · Unloading |
| 041 | Delivery · POD Signing |
| 042 | Delivery · Complete |
| 043 | Exception · Breakdown |
| 044 | Exception · Weather |
| 045 | Exception · Accident |
| 046 | Exception · Theft/Damage |
| 047 | Dispatch · New Offer |
| 048 | Dispatch · Accept |
| 049 | Dispatch · Decline |
| 050 | Dispatch · Pre-plan |
| 051 | Messaging · Thread |
| 052 | Messaging · Dispatcher |
| 053 | Messaging · Broker |
| 054 | Messaging · Haul Lobby |
| 055 | Docs · BOL |
| 056 | Docs · Rate Con |
| 057 | Docs · POD Scan |
| 058 | Docs · Lumper Receipt |
| 059 | Docs · Fuel Receipt |
| 060 | The Haul · Dashboard |
| 061 | The Haul · Missions |
| 062 | The Haul · Badges |
| 063 | The Haul · Crates |
| 064 | The Haul · Leaderboard |
| 065 | The Haul · Streaks |
| 066 | The Haul · Cosmetics |
| 067 | Me · Profile |
| 068 | Me · Earnings |
| 069 | Me · Wallet (expand — 8 sections, see §9) |
| 070 | Me · Settlements |
| 071 | Me · Tax (W-9 / 1099 / IFTA) |
| 072 | Me · Docs (CDL / Medical / TWIC / Hazmat) |
| 073 | Me · Vehicle |
| 074 | Me · HOS Logs |
| 075 | Me · Safety Score |
| 076 | Me · Training |
| 077 | Zeun · Dashboard |
| 078 | Zeun · Breakdown |
| 079 | Zeun · ESANG Diagnose |
| 080 | Zeun · Repair Shops |
| 081 | Zeun · Maintenance Schedule |
| 082 | Zeun · Recalls |
| 083 | Zeun · DTC Codes |
| 084 | HOS · Clock |
| 085 | HOS · Log Edit |
| 086 | HOS · Certify |
| 087 | HOS · Remark |
| 088 | ELD · Diagnostics |
| 089 | ELD · Fault Codes |
| 090 | Cross-border · US→CA |
| 091 | Cross-border · US→MX |
| 092 | Cross-border · Carta Porte |
| 093 | Cross-border · ACE/ACI |
| 094 | Escort · Active |
| 095 | Escort · Handoff |
| 096 | Autonomous · Monitor |
| 097 | Autonomous · Handoff |
| 098 | Emergency · SOS |
| 099 | Shutdown |

**If the Figma has different titles/numbers, trust Figma. This list is a scaffold, not a contract.**

Other roles (Shipper 200s, Carrier 300s, Broker 400s, Catalyst 500s, Escort 600s, Terminal 700s, Admin 800s) open after Driver 010–099 is 100% shipped. Stub each role's `ScreenRegistry.forRole(…)` block with one placeholder screen now so the role tabs render.

---

## 6. Phase 0 → Phase 6 battle plan

### Phase 0 — Lock the doctrine (this file exists; done).

### Phase 1 — Close the wiring gaps (before any new screens)
1. **Remove the AppRoot dev bypass.** `Views/AppRoot.swift` line ~30 currently routes `signedOut` to `ContentView()`. Revert to `SignInView()` once §5 screens are shipped. Until then, document the bypass in a banner on the ContentView dev chrome.
2. **Verify all 13 shipped driver screens render edge-to-edge in both registers.** Open each via the next/prev chrome, screenshot both registers, commit screenshots to `/Users/diegousoro/Desktop/EusoTrip-verification-screenshots/` (create the folder). Fail = re-port.
3. **Audit MeDetailScreens for gradient compliance.** Grep for `Brand.info` and `Brand.blue` in `Views/` — every hit that's a fill/tint must become `LinearGradient.diagonal` + `GradientToggleStyle` where applicable. (`ripgrep "Brand\\.(info|blue)" -n Views/`)
4. **Primitive consolidation.** Any element duplicated 3+ times across the 13 shipped screens gets promoted into `Views/Primitives/`. Priority candidates: `ActiveCard`, `MetricTile`, `StatusPill`, `CTAButton`, `WeatherCard`.
5. **Stub the non-driver role registries.** Add a placeholder screen per role so every role tab activates.

### Phase 2 — Port 023–042 (break / fuel / weigh / delivery lifecycle)
- 20 screens. Follow the brick recipe for each.
- Verify weather-animated sky on any "enroute" variant matches time-of-day.
- At end of phase, all 33 screens render cleanly.

### Phase 3 — Port 043–066 (exceptions, dispatch, messaging, docs, The Haul)
- 24 screens. This wave introduces messaging (hit the two parallel routers — use `messages.ts` canonical API, see §16 messaging-docs slice).
- Haul Lobby raw-SQL tables are a known gap — render UI against the real `messages.ts` endpoints, not `haul_lobby_*`.

### Phase 4 — Port 067–083 (Me, Zeun, wallet expansion)
- 17 screens including the Wallet 8-section rebuild (see §9 below).
- Tax screens pull from `taxReporting.ts` (be mindful of the duplicate generators — see §16 money slice).

### Phase 5 — Port 084–099 (HOS, ELD, cross-border, escort, autonomous, emergency)
- 16 screens. Cross-border screens use USMCA / VUCEM / Carta Porte / ACE/ACI / NOM / TDG data shapes from the intermodal-xborder slice.
- Emergency SOS must dial 911 via `UIApplication.shared.open(URL(string: "tel://911"))` with a confirmation sheet.

### Phase 6 — Other roles + polish + ship
- Build Shipper 200s, Carrier 300s, Broker 400s screens (Figma TBD).
- Re-enable `SignInView` in AppRoot.
- Enable live weather with Location Services.
- Blur content scrolling past bottom nav.
- ESANG burst becomes the sheet-to-particles transform.
- TestFlight ship.

---

## 7. Wiring gaps that must be closed

These are the specific cuts I (or the previous agent) left in the codebase. Every one must be resolved before TestFlight.

1. **`AppRoot.swift` `signedOut` case** — currently renders `ContentView()` (dev bypass). Revert once auth flow is visually approved.
2. **`DriverMePane` ScrollView wrap** — the Me pane in DriverHomeScreen must scroll; verify it uses a `ScrollView` at the outermost level of the pane and not inside a `List`.
3. **Shipper / Carrier / Broker / Catalyst / Escort / Terminal / Admin `ScreenRegistry`** — empty. Add one placeholder each so role tabs activate (see ContentView.swift `roleTabs`).
4. **EusoWallet screen (#069) is still minimal** — rebuild with 8 sections (see §9).
5. **All toggles must be `GradientToggleStyle()`.** Re-verify after any new file: grep for `.tint(` in Views/ — every hit must be justified.
6. **Deep-link reset password** — already wired in `EusoTripApp.swift` and `AppRoot.swift`. Test with `xcrun simctl openurl booted "eusotrip://reset?token=TEST123"`.
7. **Previews that reference missing VMs** — any Preview that instantiates a live API client must be replaced with a mock. Previews are allowed to cheat; production code is not.

---

## 8. Gradient toggle style (reference implementation)

This lives at the bottom of `Views/Driver/MeDetailScreens.swift`. Module-internal. Reuse everywhere.

```swift
struct GradientToggleStyle: ToggleStyle {
    @Environment(\.palette) var palette

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: Space.s3)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        configuration.isOn
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(Color.white.opacity(0.14))
                    )
                    .frame(width: 51, height: 31)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                configuration.isOn
                                ? AnyShapeStyle(Color.clear)
                                : AnyShapeStyle(Color.white.opacity(0.08)),
                                lineWidth: 1
                            )
                    )
                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .padding(2)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}
```

**Every `Toggle` in the codebase must use `.toggleStyle(GradientToggleStyle())`.** No exceptions.

---

## 9. EusoWallet (#069) — the 8-section rebuild

`DriverWalletPane` currently stubs a single hero. Full spec:

1. **Hero balance card** — big balance, "Available" + "Pending" split, gradient ring around a circular icon.
2. **Quick-actions row** — Transfer, Deposit, Withdraw, Card (4 pill buttons with gradient icons).
3. **Weekly chart** — 7-day bar chart of net settlements. Bars = gradient fill. X-axis = day initials.
4. **Upcoming settlements** — list of 3–5 pending payouts with expected date, net amount, source.
5. **Activity feed** — infinite scroll of transactions. Each row = icon + title + subtitle + amount. Gradient icon for credits, neutral for debits.
6. **Factoring offer** — if HaulPay eligibility = true, show a gradient card with "Get paid today" CTA.
7. **Linked accounts** — bank + debit cards, masked to last 4. Add/remove buttons.
8. **Tax withholdings** — YTD withheld, quarterly estimate, "Download 1099" link (disabled until Jan 31 of next year).

Pull data from `money.ts` + `wallet_overview` MCP tool per §16 money slice. **Do not hit Stripe directly.**

---

## 10. Verification checklist (before closing any brick)

- [ ] Figma PNG screenshot open side-by-side with the sim screenshot.
- [ ] Night register matches at 100% zoom.
- [ ] Afternoon register matches at 100% zoom.
- [ ] Every `Toggle` uses `GradientToggleStyle()`.
- [ ] No `Brand.info` / `Brand.blue` fills remain.
- [ ] All ternary shape-styles wrapped in `AnyShapeStyle`.
- [ ] Previews compile in isolation.
- [ ] `xcodebuild` exits 0.
- [ ] Screen is wired into `ContentView.ScreenRegistry.all` in numeric order.
- [ ] If it's a Me sub-route, added to `MeRoute` enum + sheet presenter.
- [ ] Task ledger in `EUSOTRIP_TRAJECTORY.json` updated.

---

## 11. How to run things (copy/paste)

```bash
# Build
xcodebuild \
  -project "/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip.xcodeproj" \
  -scheme EusoTrip \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -configuration Debug \
  build

# Boot sim
xcrun simctl boot "iPhone 17 Pro Max" || true
open -a Simulator

# Install + launch
xcrun simctl install booted "/Users/diegousoro/Library/Developer/Xcode/DerivedData/EusoTrip-*/Build/Products/Debug-iphonesimulator/EusoTrip.app"
xcrun simctl launch booted com.eusorone.EusoTrip

# Deep link test
xcrun simctl openurl booted "eusotrip://reset?token=TEST123"

# Screenshot
xcrun simctl io booted screenshot /Users/diegousoro/Desktop/EusoTrip-verification-screenshots/NNN_register.png
```

---

## 12. tRPC surfaces the client talks to (quick map)

For every screen you port, know which backend router it reads/writes. Full details in §16; summary:

| Client pane | Backend router | Slice |
|---|---|---|
| Driver Home · load card | `loads.getActive`, `dispatch.getCurrent` | loads-lifecycle |
| DVIR | `dvir.submit`, `dvir.getPrevious` | compliance-safety |
| HOS clock | `hos.getStatus`, `hos.changeDuty` | compliance-safety (stubs flagged) |
| Wallet | `wallet.getBalance`, `money.getSettlements`, `factoring.eligibility` | money |
| Messaging | `messages.*` (canonical) — NOT `messaging.*` | messaging-docs |
| The Haul | `gamification.*`, `rewards.*` | the-haul |
| Zeun | `zeunMechanics.*` (NOT `zeun.*`) | zeun-mechanics |
| Dispatch | `dispatch.getBoard`, `dispatch.accept`, `dispatch.decline` | loads-lifecycle |
| Rate cons | `documentManagement.generateRateConfirmation` | loads-lifecycle |
| Tax | `taxReporting.*` (admin) — mobile surface is `taxReporting.mobile.*` | money |
| Settlements | `settlementBatching.*` | money |
| ELD | `eld.getStatus`, `eld.getFaults` | compliance-safety |
| Cross-border | `crossBorder.usmca`, `crossBorder.vucem`, `crossBorder.cartaPorte`, etc. | intermodal-xborder |

**When a router is flagged as "stub" or "gap" in §16, the client must render the UI but surface a neutral empty state — do not fake data.**

---

## 13. Bugs known in backend (don't front-run them)

- `fee calculator adaptiveLive` is in-memory and diverges across instances — platform fees on Stripe checkout are flat, not adaptive. Client should not claim "live shadow pricing" until backend is fixed.
- `haulpay health` double-calls requireRole — FACTORING-role users can't hit the endpoint. Client must guard with a pre-check on `user.role`.
- `zeun_maintenance` MCP tool hits a non-existent table — use `zeunMechanics.*` tRPC router instead.
- `rail aux routers` (tender, audit, demurrage, lease) skip RAIL mode gating — client must not expose these to non-rail roles.
- `imdg` router uses `protectedProcedure`, not `vesselProcedure` — client must enforce role gating on the UI side.
- Push device register/unregister procedures are missing — stub the Settings "Push notifications" toggle as local-only until they ship.
- `loot_crates`, `user_inventory`, `miles_transactions` have zero writers — The Haul crate rewards are display-only, never hit the wallet. Do not show "cash added" toasts.

---

## 14. Definition of "done" for the whole app

- All 90+ driver screens ported, both registers, verified.
- Other 7 roles have at minimum the 5 highest-value screens each (home, inbox, doc, earnings, profile).
- Auth flow enabled (AppRoot dev bypass removed).
- Live weather via Location Services.
- Bottom-nav blur.
- ESANG burst as sheet-to-particles transform.
- No `.tint(Brand.info)` / `.tint(Brand.blue)` in `grep -r`.
- All `Toggle`s use `GradientToggleStyle`.
- Every backend stub gap has a neutral empty state on the client (no fake data).
- TestFlight build succeeds, sanity walk passes on a real iPhone 17 Pro Max.

---

## 15. Working discipline

- **One brick per commit.** Commit message: `feat(NNN): <title> · both registers verified`. Include sim screenshot path in body.
- **Never leave gradients flat.** If you're unsure whether a blue belongs to brand or utility, treat it as brand.
- **Never invent data shapes.** If a procedure name isn't in §16, ask — don't guess.
- **Update the JSON ledger as you close bricks.** `/Users/diegousoro/Desktop/EUSOTRIP_TRAJECTORY.json` → `active_task_ledger_snapshot` → move items from `pending` → `completed` with the brick number, file path, and verification screenshot path.
- **If the Figma disagrees with this prompt, the Figma wins** (for visuals). If the backend disagrees with this prompt, §16 wins (for data). If the doctrine disagrees, the doctrine wins.

---

## 16. EusoTrip Codebase Map — Master Index (embedded verbatim, never lose this)

> This is the full text of the user-uploaded `README 2.md` that sits at the top of the backend repo. It is pasted here so no build wave ever loses sight of what the server actually provides. Individual slices (`auth-identity-rbac.md`, `loads-lifecycle.md`, etc.) live alongside this index in the backend repo.

---

# EusoTrip Codebase Map — Master Index

Persistent reference for the full backend + client surface. Built by 14 parallel recon agents reading every router, schema, service, and MCP tool under `frontend/`. Every slice is a markdown file in this directory; nothing here is speculative — all procedures, tables, and gaps are grounded in source files.

**When in doubt, open the slice.** Do not rebuild from memory. These maps exist so build waves have a real reference to execute against.

---

## The 14 slices

| # | File | What it covers | Lines |
|---|------|----------------|------:|
| 01 | [auth-identity-rbac.md](./auth-identity-rbac.md) | 24 roles, procedure helpers, session/MFA, tenants, mode isolation | 317 |
| 02 | [loads-lifecycle.md](./loads-lifecycle.md) | End-to-end truck load: creation → dispatch → transit → delivery → settlement. 37-state machine + tanker sub-states | 514 |
| 03 | [rail.md](./rail.md) | 6 RAIL roles, 5 rail routers, 19-state rail lifecycle, FRA/PHMSA/STCC compliance, intermodal handoff | 332 |
| 04 | [vessel.md](./vessel.md) | 6 VESSEL roles, 9 vessel routers, 19-state ocean lifecycle, ISF 10+2 gate, IMDG, VGM | 340 |
| 05 | [intermodal-xborder.md](./intermodal-xborder.md) | Ocean→rail→truck journey, drayage/chassis, US/CA/MX cross-border: USMCA, VUCEM, Carta Porte, ACE/ACI, NOM, TDG | 223 |
| 06 | [money.md](./money.md) | Platform fees, Stripe Connect, factoring/HaulPay, settlement, EusoWallet, billing, 1099/W-9/IFTA, FSC, pricebook/rates | 486 |
| 07 | **[messaging-docs.md](./messaging-docs.md)** | **Two parallel messaging routers, Haul Lobby, moderation, push notifications, 10-table document compliance model, announcements** | **365** |
| 08 | [compliance-safety.md](./compliance-safety.md) | HOS/ELD, DVIR, FMCSA, ADR/IMDG/TDG, FDA/USDA/FSMA, bridge clearance, escorts, autonomous, safety incidents, audit | 890 |
| 09 | [the-haul.md](./the-haul.md) | Gamification: XP engine, missions, badges, streaks, crates, leaderboards, referrals, guilds, tournaments, cosmetic inventory, Haul Lobby | 381 |
| 10 | [zeun-mechanics.md](./zeun-mechanics.md) | Fleet mechanics: breakdowns, ESANG AI diagnosis, repair shops, maintenance, recalls, DTCs, 9 `zeun_*` tables — **NOT gamification** | 219 |
| 11 | [intelligence.md](./intelligence.md) | ESANG AI (Gemini 2.5 Flash), Autopilot 7-layer cortex (52 agents), SpectraMatch (crude oil 12-param), AI doc/dispatch, HERE LBS, analytics | 366 |
| 12 | [fleet-rates-verticals.md](./fleet-rates-verticals.md) | Vehicles/trailers, driver lifecycle, dispatch board, rates/pricebook, verticals (tanker, reefer, flatbed, livestock, auto-hauler, LTL), allocation, scoring, broker mgmt | 936 |
| 13 | [admin-tenant-ops.md](./admin-tenant-ops.md) | Admin console, tenants, portals, branding, approvals, bulk import/export, experiments, control tower, DD alerts | 410 |
| 14 | [roles-modes-verticals-countries.md](./roles-modes-verticals-countries.md) | Capstone matrix: 24 roles × 3 modes × 9 verticals × 3 countries, with 6 end-to-end scenarios | 293 |

**Total: 6,072 lines covering ~300 routers, 24 roles, 3 modes, 9 verticals, 3 countries.**

---

## How to use this before a build wave

1. Open the slice(s) that touch what you're building.
2. Read every procedure list — these are the real names in source, not guesses.
3. Read the `## Gaps` / `⚠️` section at the bottom — those are the known holes. Your wave either fixes them or deliberately skips them.
4. Cross-reference with `roles-modes-verticals-countries.md` to confirm which role/mode/country combinations you need to support.
5. Only then write code.

---

## Critical gaps surfaced across all 14 slices

These are the big ones — pulled from every slice's `## Gaps` section and grouped by area. Any build wave that touches one of these areas should plan to fix or explicitly defer.

### Auth / session
- `revokeAllSessions` and `resetPassword` bump `tokenVersion` but `verifyToken` never reads it — session revocation is a no-op until JWT natural expiry.
- `getSessions` / `terminateSession` return stub data — there is no `sessions` table.
- `registerAdmin` is a public mutation. `users.updateRole` and `users.impersonate` are only `protectedProcedure` (no admin gate).
- Super-admins bootstrap via hard-coded emails in `auth.ts` with a race-prone max-10 cap.
- Three parallel MFA surfaces; legacy SMS 2FA stores the 6-digit code in `users.metadata` plaintext.
- Action×Resource×Scope RBAC primitives declared but not wired into `roleProcedure`.

### Loads lifecycle
- No standalone `checkcalls.ts` — overdue check-calls are an event type inside `dispatch.getExceptions`.
- No `disputes.ts` — 5 routers carry `disputeXxx` mutations with no shared dispute entity.
- `rateConfirmations.send` is a stub; real rate-cons flow through `documentManagement.generateRateConfirmation`.
- Status enum drift: `TANKER_LOAD_STATUSES` (lowercase, 56) vs `LOAD_STATES` (UPPERCASE, 37), reconciled only by runtime case-folding.

### Money / payments — biggest cluster of landmines
- **Stripe checkout never calls the adaptive fee engine** — `createLoadCheckout` / `createPaymentIntent` use flat `feeCalculator.calculateFee`, so the shadow/live flag doesn't actually move money.
- `adaptiveLive` is an in-memory boolean in `feeCalculator.ts` L546 — not persisted, resets on restart, diverges across instances.
- `application_fee_amount` + `transfer_data.destination` only set when caller passes `catalystConnectId`/`destinationConnectId`; without it, Stripe keeps 100% and platform collects nothing.
- `settlementBatching.processBatchPayment` creates PaymentIntents with no `application_fee_amount` — no platform fee on batch payouts.
- `fscEngine.calculateFSC` never invoked during settlement generation.
- No wallet↔settlement ledger bridge. Duplicate 1099 generators (admin `taxReporting.ts` vs mobile `taxReporting.mobile.ts`).
- `haulpay.router.ts` `health` double-calls `requireRole`, blocking FACTORING-role users.

### Messaging / docs
- Two parallel messaging routers (`messaging.ts` + `messages.ts`) against the same tables.
- Haul Lobby uses raw-SQL tables (`haul_lobby_messages`, `haul_lobby_user_strikes`, `haul_lobby_moderation_log`) **not declared in drizzle/schema.ts** — bootstrapped at runtime via `CREATE TABLE IF NOT EXISTS`.
- Missing push device register/unregister procedures. Quiet-hours stored but never applied.
- W-9/1099 seed rows missing from document_types.

### The Haul
- XP formula duplicated between `rewardsEngine` and `gamificationDispatcher`. Streak/prestige multipliers defined but not multiplied into actual XP writes.
- `loot_crates`, `user_inventory`, `miles_transactions` tables declared but **zero router readers/writers** — crate "cash" rewards are display-only, never hit the wallet.
- `equipCustomization` only persists `type='title'` — frames, emotes, trailer cosmetics are in-memory only.
- No multi-level referral chain, no guild mission writers, no tournament prize dispatch.

### Zeun mechanics
- `zeunRouter` is mostly stubs; `zeunMechanicsRouter` (~1900 lines) is the live surface.
- `zeunFleetMaintenanceSchedules` has no CRUD exposed.
- `dtc_codes` re-created at runtime inside `lookupDTC` via raw SQL.
- No scheduled J1939/OBD-II/ELD fault-code ingestion into breakdowns — codes come from the client only.
- No NHTSA/OEM recall ingestion pipeline — `zeun_vehicle_recalls` rows must be inserted manually.
- MCP tool `zeun_maintenance` hits a non-existent `maintenance_orders` table and silently falls back to `inspections` — should be rewired to the tRPC router.

### Compliance / safety
- `hos.certifyLog` / `hos.addRemark` are non-persisting stubs.
- FDA/USDA/FSMA exist only as services — no tRPC router.
- Bridge clearance scattered across 3 locations (escorts, services/bridgeClearance, eld LiDAR) with hard-coded NBI registry.
- Three parallel audit routers (`auditCompliance`, `auditLogs`, `blockchainAudit`) with unclear ownership.

### Rail / vessel / intermodal
- Rail aux routers (tender workflow, audit, demurrage, lease) use bare `protectedProcedure` — bypass RAIL-mode and role gating.
- `imdg` router uses `protectedProcedure`, not `vesselProcedure` — bypasses VESSEL gating.
- SOLAS VGM field missing from `vesselShipments` / `shippingContainers`.
- `etaPrediction` reads a `transitDays` column that doesn't exist.
- No live CBP/CBSA/C-TPAT/PAC integrations — all return `_note` stubs.
- `advanceSegment` hard-codes only 3-leg intermodal transitions.

### Admin / tenant
- Multi-tenant isolation is thin — only 3 tables carry tenantId; core tables rely on `isolationMiddleware` using `companyId`.
- Approval workflow covers user accounts only — no credit-line, new-broker, or contract approval flows.
- Feature flags UI exists but no `feature_flags` table. `features` router is for feature *requests* (voting), not flags.
- `admin.impersonateUser` and several system-settings endpoints return mock data.

### Roles / modes / countries
- **There is no `TRUCK_DRIVER` or `MX_DRIVER` role** — the only trucking driver role is `DRIVER`. MX drivers are modelled implicitly.
- `users.transportModes` has no self-service setter — cross-mode access requires a direct DB UPDATE.
- `SHARED_RESOURCES` declared but never enforced.

---

## Naming landmines to remember

- **Zeun ≠ The Haul.** Zeun is fleet mechanics (breakdowns, diagnostics, shops, recalls). The Haul is gamification (XP, missions, badges, crates, leaderboards). Never confuse these two.
- **"The Lobby"** exists in two forms: (a) a per-company conversation row in the standard messaging stack, and (b) a cross-company Haul Lobby with its own ad-hoc tables inside the gamification router.
- **Messaging has two parallel routers.** Use `messages.ts` (canonical OpenIM-style) for new work; treat `messaging.ts` as legacy/transitional.
- **ROLES constant lives in `server/_core/trpc.ts`** — not in a separate `roles.ts`.
- **Procedure names drift between helpers.** `isolatedProcedure` is aliased as `protectedProcedure` in some files. Trust the source.

---

## How this was built

14 parallel general-purpose agents, each owning one slice, reading source under `frontend/server/`, `frontend/client/`, and `frontend/drizzle/`. Each agent wrote its own markdown directly to this directory. The capstone slice (`roles-modes-verticals-countries.md`) cross-references the other 13.

**Regeneration:** if source drifts significantly, re-fire the mapping wave. Individual slices can be regenerated by re-firing just that agent's prompt.

---

## 17. Hand-off

Pick the next brick from §5, follow §4, verify via §10, commit, update `EUSOTRIP_TRAJECTORY.json`. Repeat.

If anything in this prompt contradicts reality (file moved, primitive renamed, Figma id changed), update this file in the same commit that fixes it. This document is the north star — keep it sharp.

— End of briefing.

trajectory memory" some of it may be outdated but the command is the same. please catch things up to speed and continue the mission of completing the app to production ready. we have multiple users. we will do them one by one.  rinse and repeat. always do an audit of what your task is and whatis up to date becaus emy dev team will also be working on the same thing so you have to work together. and when you are done and only when you are done every single time i want you to open the file on my desktop titled "2027 motivation" and open it and read the command in that document and do exactly what it says as far as your task at hand. which is keep building after you are up to speed on audit. when youre done "" ContentView's ScreenRegistry." "(the bash sandbox is Linux so xcodebuild isn't available, but I can do symbol-grep against the design system to confirm no references to undefined APIs)." i need you to take control . i give you permission to take control to update xcode and the app connect. content view screen registry i hope is just an organized place you put the screens before they get wired up to backend, the wbesockets, dynamic code, no dead buttons, no stubs, no none of that. real working code. that is what you need to also fix when building make sure it is wired up to where it goes based on what trigger event triggers it. every step you take is to make sure our platform is production ready. lean on the web platform so you understand what code is for what. make sure all 40+ previous drivers screens shipped and new screens created and ported to brick are dynamic, no mock data, no stubs, no fake data, it needs to be 1000% dynamic. these arent pnjs no more they need to be live code ready for production and plugged into backend only activating with the events that trigger them. no more fake data. dynamic ready pages with 0 data. plugged into backend. remember to always connect to the eusorone web app mcp so you have the proper guide reinforcements to build perfectly.