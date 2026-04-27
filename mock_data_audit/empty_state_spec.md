# `EusoEmptyState` — Branded Empty / Coming-Soon Component

**Purpose.** Replace every seeded mock array with an on-brand empty state that either (a) tells the driver "nothing to show yet" (when backend is up but empty), or (b) tells the driver "this surface is coming — we're building it" (when backend is missing). Both variants use the same primitive.

**Why.** The user has declared 0% mock data. Screens whose backend isn't ready must still render — they just render an empty, honest, on-brand state. This component is the answer.

---

## 1. Visual treatment

Reads against the existing dark gradient aesthetic (uses `palette`, `ActiveCard`, `LinearGradient.diagonal`, `Brand.*`, `Space.*`, `Radius.*`, `EType` — all from the existing design system).

```
┌────────────────────────────────────────────┐
│                                            │
│            ◎  (gradient glyph, 32pt)       │
│                                            │
│            Title (h2, primary)             │
│            Subtitle (body, secondary)      │
│                                            │
│         ┌────────────────┐                 │
│         │ CTA (gradient) │  (optional)     │
│         └────────────────┘                 │
│                                            │
│   [ "Coming soon" StatusPill ]  (optional) │
└────────────────────────────────────────────┘
```

- **Glyph chip** — 56×56 rounded-rect `Radius.md`, `palette.tintNeutral` fill, SF Symbol at 20pt rendered via `LinearGradient.diagonal` (matches the `actionPill` in DriverWalletPane + the "Add account" affordance).
- **Title** — `EType.h2`, `palette.textPrimary`. Sentence case, no ALL CAPS.
- **Subtitle** — `EType.body`, `palette.textSecondary`. Single sentence. Numbers first when a count is involved.
- **CTA** — optional, reuses `CTAButton` component. Only shown when there's a real action (sign in, connect ELD, link bank, etc.).
- **Badge** — optional `StatusPill(text: "Coming soon", kind: .info)` for Phase-3 surfaces where the backend is still being built.
- **Container** — sits inside an `ActiveCard { }` so the gradient border + paired brand shadow match every other pane on the Me hub. Vertical padding `Space.s6` top and bottom for breathe density (§7).
- **Motion** — respects the existing `TileStack` staggered reveal. No bespoke animation.
- **Accessibility** — `accessibilityElement(children: .combine)` on the whole card; VoiceOver reads "Empty. <title>. <subtitle>. <cta label>".

---

## 2. Swift signature

File: `EusoTrip/Theme/Components/EusoEmptyState.swift`

```swift
import SwiftUI

/// Branded empty / coming-soon state shown in place of seeded mock data.
///
/// Usage:
///
///     EusoEmptyState(
///         icon: "dollarsign.circle",
///         title: "No transactions yet",
///         subtitle: "Your wallet activity shows up here the moment a load clears.",
///         cta: .init(label: "Open wallet") { sheet = .deposit }
///     )
///
/// Or, for a Phase-3 "not built yet" surface:
///
///     EusoEmptyState(
///         icon: "trophy",
///         title: "Leaderboard is on the way",
///         subtitle: "We're lining up season standings — you'll see your rank the moment it ships.",
///         badge: .comingSoon
///     )
///
struct EusoEmptyState: View {
    @Environment(\.palette) var palette

    /// SF Symbol name rendered inside the gradient glyph chip.
    let icon: String

    /// Primary title — `EType.h2`, sentence case.
    let title: String

    /// One-line subtitle — `EType.body`, numbers-first copy.
    let subtitle: String

    /// Optional CTA rendered as the brand gradient button. Nil = no CTA.
    let cta: CTA?

    /// Optional status pill. Use `.comingSoon` for Phase-3 surfaces where
    /// the backend isn't built yet, `.liveSoon` when a feature flag is
    /// staging, or `.none` for the normal "backend is up, there's just
    /// nothing to show" empty state (default).
    let badge: Badge

    init(
        icon: String,
        title: String,
        subtitle: String,
        cta: CTA? = nil,
        badge: Badge = .none
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.cta = cta
        self.badge = badge
    }

    // MARK: Nested types

    struct CTA {
        let label: String
        let action: () -> Void
    }

    enum Badge {
        case none
        case comingSoon
        case liveSoon
        case beta

        var pill: StatusPill? {
            switch self {
            case .none:       return nil
            case .comingSoon: return StatusPill(text: "Coming soon", kind: .info)
            case .liveSoon:   return StatusPill(text: "Going live soon", kind: .success)
            case .beta:       return StatusPill(text: "Beta", kind: .warning)
            }
        }
    }

    // MARK: Body

    var body: some View {
        ActiveCard {
            VStack(alignment: .center, spacing: Space.s4) {
                glyphChip
                VStack(spacing: Space.s2) {
                    Text(title)
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let cta {
                    CTAButton(title: cta.label, action: cta.action)
                        .padding(.top, Space.s2)
                }
                if let pill = badge.pill {
                    pill
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Empty. \(title). \(subtitle)")
        .accessibilityHint(cta?.label ?? "")
    }

    // MARK: Glyph

    private var glyphChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintNeutral)
                .frame(width: 56, height: 56)
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
        }
    }
}

#Preview("Empty state · dark") {
    VStack(spacing: Space.s5) {
        EusoEmptyState(
            icon: "dollarsign.circle",
            title: "No transactions yet",
            subtitle: "Your wallet activity shows up here the moment a load clears.",
            cta: .init(label: "Link bank account", action: {})
        )

        EusoEmptyState(
            icon: "trophy",
            title: "Leaderboard is on the way",
            subtitle: "We're lining up season standings — you'll see your rank the moment it ships.",
            badge: .comingSoon
        )
    }
    .padding()
    .background(Color.black)
    .environment(\.palette, Palette.dark)
}
```

---

## 3. Copy guidance

- **Never** use "Loading…" as an empty-state copy (that's a different state owned by the loader).
- **Never** apologise ("sorry, nothing here"). Be matter-of-fact.
- **Always** tell the driver *when* they'll see content: "…the moment a load clears", "…as soon as you finish your first load", "…when dispatch assigns one".
- **Always** ground in action: nudge them to the next step (link bank, accept a load, complete DVIR).
- **Never** include exclamation marks. Voice is calm, numeric, professional.

---

## 4. Standard copy by surface

Reuse these verbatim so surfaces feel unified.

| Surface | Icon | Title | Subtitle | CTA | Badge |
|---|---|---|---|---|---|
| Wallet transactions | `dollarsign.circle` | No transactions yet | Your wallet activity shows up here the moment a load clears. | Link bank account | none |
| Wallet payment methods | `creditcard` | No payment method linked | Add a bank or debit card to get paid instantly when a load clears. | Add account | none |
| Eusoboards (no results) | `truck.box` | No loads match these filters | Widen the equipment filter or try a different origin/destination. | Clear filters | none |
| My Loads · Active | `shippingbox` | No active loads | Accept a tender from Eusoboards and you'll see it here. | Open Eusoboards | none |
| My Loads · Pending | `clock.arrow.circlepath` | No pending tenders | Brokers will offer here — tender accept or decline within the window. | — | none |
| My Loads · Finished | `checkmark.circle` | No completed loads yet | Your finished loads + POD receipts will log here. | — | none |
| Earnings summary | `chart.bar` | Earnings kick in after your first load | Week, month, and YTD rollups show up once settlements post. | — | none |
| Tax / 1099 | `doc.plaintext` | 1099 ships each January | Your YTD gross + withholding table will populate as settlements clear. | — | none |
| Missions | `flag.checkered` | Missions are being tuned | We're balancing the weekly + monthly tracks. You'll see them here any day. | — | comingSoon |
| Rewards catalog | `gift` | Rewards store going live soon | Fuel cards, cash payouts, and gear are coming — stack points now, redeem later. | — | liveSoon |
| Badges | `rosette` | No badges yet | Your first 100 loads, safety streaks, and MPG wins all unlock here. | — | none |
| Leaderboard | `trophy` | Leaderboard going live soon | We're lining up season standings — you'll see your rank the moment it ships. | — | comingSoon |
| Fleet assets | `truck.box` | Fleet management coming soon | Tractor, trailer, and APU records will sync in once the fleet service ships. | — | comingSoon |
| Fuel card | `fuelpump` | EusoFuel card available to driver fleets | Enterprise admins can enable the EusoFuel card for your driver ID. | — | comingSoon |
| Inbox | `envelope` | Inbox is quiet | Messages from dispatch, brokers, and Eusorone land here. | — | none |
| Driver lobby (group chat) | `person.3` | No room activity yet | Hop into a drivers' room to chat, swap lane intel, or call in a convoy. | — | none |
| Smart stops amenities | `mappin.and.ellipse` | Smart Stop coverage is expanding | You'll see amenity maps for each stop as we light up the partner network. | — | comingSoon |
| Telemetry (tank, scale, trailer) | `gauge.with.dots.needle.50percent` | Live telemetry coming soon | Flow rate, fill %, temperature, and axle weight wire in with the sensor stack. | — | comingSoon |

---

## 5. Acceptance checklist

- [ ] Renders in both light and dark palette (uses `palette` not hardcoded colors).
- [ ] Works inside a `TileStack` without breaking stagger.
- [ ] No text truncation on iPhone SE (375pt wide).
- [ ] VoiceOver reads the whole card as one element, not three.
- [ ] Zero dependencies beyond the existing design system primitives.
- [ ] One SF Symbol only — no Lottie, no bespoke assets.
- [ ] Respects `accessibilityDifferentiateWithoutColor` — never uses color alone to carry meaning (the badge pill uses text + color, per existing `StatusPill` spec).
