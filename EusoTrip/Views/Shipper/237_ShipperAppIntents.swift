//
//  237_ShipperAppIntents.swift
//  EusoTrip iOS — Shipper App Intents authoring (§35.3 Arc L)
//
//  iOS twin of:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/02 Shipper/Code/
//    237_ShipperAppIntents.swift
//
//  Surface: per-Siri-shortcut authoring for the seven App Intents that
//  the EusoTrip Shipper app exposes. Seventh Arc L brick after 231 push
//  → 232 lock screen → 233 watch complication → 234 haptic → 235 Focus
//  Mode → 236 widget gallery. Each intent registers an `AppIntent`
//  conformer whose `perform()` invokes a tRPC procedure; intents donate
//  themselves on each invocation via `IntentDonationManager.shared.donate`
//  so Siri's relevance ranking improves over time.
//
//  §11.4 active hero anchor — PostLoadIntent ran 12m ago against §11.2
//  MATRIX-50 row 1 (LD-260427-A38FB12C7E · Houston TX → Dallas TX ·
//  MC-306 Gasoline · UN1203 · $1,900). LoadStatusIntent + ExceptionsIntent
//  rows reference §11.4 row 3's NH₃ shipment at "stage 5/8" + "1 open"
//  exception. BidsForLoadIntent's Siri phrase cites row 2's "KC to Omaha"
//  lane to anchor speech-recognition templates to MATRIX-50 lanes.
//
//  Doctrine: §2 nav, §3 numbers-first, §4.3 single hairline, §7 breathe
//  density, §11/§11.2/§11.4 Diego canon + MATRIX-50, §17.2 width-locked
//  status grammar, §19.2 file-scoped helpers (PillToggle, GradientLivePill,
//  GradientCapsuleCTA, CategoryDotStrip, InitialsTile, IntentRow),
//  §20.4 no dead buttons, §22.2 counter eyebrow color encodes screen-
//  status, §35.3 Arc L iOS-platform integration surfaces.
//
//  Backend (server) endpoints owed (EUSO-2157):
//    appIntents.listIntents                     -> [Intent]
//    appIntents.setIntentEnabled(intentId, enabled)
//    appIntents.recordIntentInvocation(intentId, invokedAt)
//    appIntents.suggestRelevantIntents(context) -> [Intent]
//
//  iOS API surface (consumed by LiveDataStore):
//    ShipperAppIntentsAPI.currentIntents()            -> [Intent]
//    ShipperAppIntentsAPI.setEnabled(intentId:enabled:)
//    ShipperAppIntentsAPI.runIntent(_:)                -> donate + invoke
//    ShipperAppIntentsAPI.recordInvocation(intentId:)
//
//  iOS framework binding:
//    AppIntents (SiriKit successor — each Intent registers an
//    `AppIntent` conformer that exposes a `perform()` method the App
//    Intents runtime invokes whenever Siri matches the user's utterance
//    to the intent's registered phrases. Intents donate themselves to
//    the system on each successful invocation via
//    `IntentDonationManager.shared.donate(intent:)` so Siri's relevance
//    ranking improves over time).
//
//  Both #Preview blocks (Dark + Light) ship per §11.4 doctrine.
//

import SwiftUI

// MARK: - Screen

struct ShipperAppIntents: View {
    @Environment(\.palette) var palette

    private let counterEyebrow = "7 INTENTS · 4 ENABLED"

    private let activeIntent = ActiveIntent(
        id:                "intent_2026-04-29T13:30:00Z_postload",
        activeLabel:       "ACTIVE · POST LOAD · 1 OF 7 INTENTS",
        headline:          "Hey Siri, \u{201C}post that load again\u{201D}",
        bindingAndCount:   "PostLoadIntent · loads.create · 5\u{00D7} recent",
        enrollmentEyebrow: "INTENTS · 7 ENROLLED",
        enrollmentCaption: "MATRIX-50 · last LD-260427-A38FB12C7E",
        relativeAgo:       "ran 12m ago",
        ctaLabel:          "Run shortcut",
        // 0 PostLoadIntent, 1 LoadStatusIntent, 2 NextDeliveryIntent,
        // 3 ExceptionsIntent, 4 BidsForLoadIntent, 5 WeeklySpendIntent,
        // 6 TopCarrierIntent
        enrollment: [true, true, true, true, false, false, false]
    )

    private let intents: [Intent] = [
        Intent(
            id:           "post_load",
            initials:     "PL",
            title:        "Post a load",
            siriPhrase:   "post that load again",
            binding:      "loads.create · MATRIX-50",
            enabled:      true
        ),
        Intent(
            id:           "load_status",
            initials:     "ST",
            title:        "Load status",
            siriPhrase:   "what\u{2019}s the stage on the NH\u{2083} load",
            binding:      "loads.getById · stage 5/8",
            enabled:      true
        ),
        Intent(
            id:           "next_delivery",
            initials:     "ND",
            title:        "Next delivery",
            siriPhrase:   "what\u{2019}s my next delivery",
            binding:      "controlTower.recentActivity",
            enabled:      true
        ),
        Intent(
            id:           "exceptions",
            initials:     "EX",
            title:        "Open exceptions",
            siriPhrase:   "any exceptions today",
            binding:      "controlTower.exceptions · 1 open",
            enabled:      true
        ),
        Intent(
            id:           "bids_for_load",
            initials:     "BD",
            title:        "Bids for load",
            siriPhrase:   "read me the bids on KC to Omaha",
            binding:      "shippers.getBidsForLoad",
            enabled:      false
        ),
        Intent(
            id:           "weekly_spend",
            initials:     "SE",
            title:        "Weekly spend",
            siriPhrase:   "how much did I pay this week",
            binding:      "settlements.getWeekly",
            enabled:      false
        ),
        Intent(
            id:           "top_carrier",
            initials:     "SC",
            title:        "Top carrier grade",
            siriPhrase:   "how is my top carrier doing",
            binding:      "shippers.getCatalystPerformance",
            enabled:      false
        )
    ]

    private let activeIntentId: String = "post_load"

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, Space.s5)
            titleBlock
                .padding(.top, Space.s3)

            IridescentHairline()
                .padding(.top, Space.s3)

            sectionLabel("ACTIVE INTENT · POST LOAD")
                .padding(.top, Space.s5)
            heroCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("INTENTS · 7 SHORTCUTS")
                .padding(.top, Space.s5)
            intentsCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            settingsPointerLink
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)

            footer
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s5)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\u{2726} SHIPPER · INTENTS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Seven Siri shortcuts total. Four currently enabled.")
        }
        .padding(.horizontal, Space.s5)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("App Intents")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Siri shortcuts · Eusorone Technologies")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                GradientLivePill(label: activeIntent.activeLabel)
                Spacer(minLength: 0)
                Text(activeIntent.relativeAgo)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(activeIntent.headline)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)

                Text(activeIntent.bindingAndCount)
                    .font(EType.mono(.caption))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeIntent.enrollmentEyebrow)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)

                    HStack(alignment: .center, spacing: 0) {
                        CategoryDotStrip(payload: activeIntent.enrollment,
                                         emphasis: .hero)
                        Spacer().frame(width: 8)
                        Text(activeIntent.enrollmentCaption)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }

                Spacer(minLength: 0)

                Button(action: tapRunShortcut) {
                    GradientCapsuleCTA(label: activeIntent.ctaLabel, width: 140)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Run the active Siri shortcut — re-fires the App Intents runtime via IntentDonationManager.shared.donate so Siri's relevance ranking promotes this intent.")
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var intentsCard: some View {
        VStack(spacing: 0) {
            ForEach(intents.indices, id: \.self) { idx in
                IntentRow(
                    intent:       intents[idx],
                    isActive:     intents[idx].id == activeIntentId,
                    onToggleTap:  { tapIntentToggle(intents[idx]) },
                    onRowTap:     { tapIntentRow(intents[idx]) }
                )
                if idx < intents.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var settingsPointerLink: some View {
        Button(action: tapManageIntents) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Siri integration")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Per-intent opt-in matrix · 211 Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\u{2192}")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Manage Siri integration. Per-intent opt-in matrix lives in 211 Settings.")
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Powered by App Intents · Apple Siri Shortcuts")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Text("companyId 1 · Eusorone Technologies · MATRIX-50-2026-04-26")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Tap handlers (§20.4 no dead buttons)

    private func tapRunShortcut() {
        NotificationCenter.default.post(
            name: .eusoShipperIntentRun,
            object: nil,
            userInfo: [
                "source": "237_ShipperAppIntents",
                "intentId": activeIntent.id,
                "activeIntentId": activeIntentId,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapIntentToggle(_ intent: Intent) {
        NotificationCenter.default.post(
            name: .eusoShipperIntentToggle,
            object: nil,
            userInfo: [
                "source": "237_ShipperAppIntents",
                "intentId": intent.id,
                "priorEnabled": intent.enabled,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapIntentRow(_ intent: Intent) {
        NotificationCenter.default.post(
            name: .eusoShipperIntentRow,
            object: nil,
            userInfo: [
                "source": "237_ShipperAppIntents",
                "intentId": intent.id,
                "binding": intent.binding,
                "isActiveIntent": intent.id == activeIntentId,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapManageIntents() {
        NotificationCenter.default.post(
            name: .eusoShipperIntentManage,
            object: nil,
            userInfo: [
                "source": "237_ShipperAppIntents",
                "targetScreen": "211 Settings",
                "shipperCompanyId": 1
            ]
        )
    }
}

// MARK: - Domain models (file-scoped — wired by LiveDataStore from
//          ShipperAppIntentsAPI.currentIntents() + appIntents.listIntents)

private struct ActiveIntent {
    let id:                String
    let activeLabel:       String
    let headline:          String
    let bindingAndCount:   String
    let enrollmentEyebrow: String
    let enrollmentCaption: String
    let relativeAgo:       String
    let ctaLabel:          String
    let enrollment:        [Bool]
}

private struct Intent: Identifiable {
    let id:         String
    let initials:   String
    let title:      String
    let siriPhrase: String
    let binding:    String
    let enabled:    Bool
}

// MARK: - GradientLivePill (240×22 ACTIVE pill — 234/235/236 recipe)

private struct GradientLivePill: View {
    let label: String

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(LinearGradient.primary)
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                }
                .padding(.leading, 8)
                Text(label)
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.trailing, 10)
        }
        .frame(maxWidth: 240, minHeight: 22, maxHeight: 22)
        .accessibilityLabel(label)
    }
}

// MARK: - GradientCapsuleCTA (140×22 hero CTA — 234/235/236 recipe)

private struct GradientCapsuleCTA: View {
    let label: String
    let width: CGFloat

    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient.primary)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
        }
        .frame(width: width, height: 22)
    }
}

// MARK: - CategoryDotStrip (7-dot visualizer — gradient pair when enrolled,
//          neutral pair when disabled; lifted from 235/236)

private enum DotEmphasis {
    case hero
    case row
}

private struct CategoryDotStrip: View {
    @Environment(\.palette) var palette
    let payload:  [Bool]
    let emphasis: DotEmphasis

    var body: some View {
        HStack(spacing: 12) {
            ForEach(payload.indices, id: \.self) { idx in
                ZStack {
                    if payload[idx] {
                        Circle()
                            .fill(LinearGradient.primary.opacity(0.30))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .fill(palette.textPrimary.opacity(0.10))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(palette.textTertiary)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - InitialsTile (36×36 — gradient fill + white mono initials when
//          enabled; neutral fill + textTertiary mono initials when disabled.
//          Apple Shortcuts colored-tile convention applied to the 7-intent
//          catalog.)

private struct InitialsTile: View {
    @Environment(\.palette) var palette
    let initials: String
    let enabled:  Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(enabled
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.textPrimary.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(enabled
                                      ? Color.clear
                                      : palette.borderFaint)
                )
            Text(initials)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(enabled
                                 ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(palette.textTertiary))
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

// MARK: - IntentRow (per-intent row — initials tile + name + Siri phrase
//          + tRPC binding + PillToggle; active row gets 12% gradient wash,
//          leading marker dot, gradient title/binding/chevron)

private struct IntentRow: View {
    @Environment(\.palette) var palette
    let intent:       Intent
    let isActive:     Bool
    let onToggleTap:  () -> Void
    let onRowTap:     () -> Void

    var body: some View {
        Button(action: onRowTap) {
            ZStack(alignment: .leading) {
                if isActive {
                    LinearGradient.primary
                        .opacity(0.12)
                }

                HStack(alignment: .center, spacing: 14) {
                    if isActive {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 6, height: 6)
                            .padding(.leading, 4)
                    } else {
                        Color.clear.frame(width: 10, height: 6)
                    }

                    InitialsTile(initials: intent.initials,
                                 enabled:  intent.enabled)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(intent.title)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textPrimary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text("\u{201C}\(intent.siriPhrase)\u{201D}")
                            .font(.system(size: 10).italic())
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        HStack(alignment: .center, spacing: 6) {
                            Text(intent.binding)
                                .font(EType.mono(.micro))
                                .tracking(0.3)
                                .foregroundStyle(isActive
                                                 ? AnyShapeStyle(LinearGradient.primary)
                                                 : AnyShapeStyle(palette.textTertiary))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                            if isActive {
                                Text("\u{2192}")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(LinearGradient.primary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onToggleTap) {
                        PillToggle(enabled: intent.enabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(intent.title), \(intent.enabled ? "enabled" : "disabled")")
                    .accessibilityHint("Toggles the \(intent.title) Siri shortcut.")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(intent.title) Siri shortcut. Phrase: \(intent.siriPhrase). Binds to \(intent.binding). \(intent.enabled ? "Enabled" : "Disabled").\(isActive ? " Active." : "")")
    }
}

// MARK: - PillToggle (44×24 — 211/234/235/236 recipe)

private struct PillToggle: View {
    @Environment(\.palette) var palette
    let enabled: Bool

    var body: some View {
        ZStack(alignment: enabled ? .trailing : .leading) {
            Capsule()
                .fill(enabled
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.textPrimary.opacity(0.10)))
            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
                .padding(.horizontal, 3)
        }
        .frame(width: 44, height: 24)
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// "Run shortcut" CTA — fires the App Intents runtime via
    /// IntentDonationManager.shared.donate(intent:) to re-promote the
    /// intent in Siri's relevance ranking, then invokes the bound tRPC
    /// procedure. Payload: intentId + activeIntentId.
    static let eusoShipperIntentRun     = Notification.Name("eusoShipperIntentRun")

    /// Per-intent PillToggle tap — flips per-intent enabled state via
    /// appIntents.setIntentEnabled. Carries priorEnabled for revert if
    /// the App Intents registration handshake fails.
    static let eusoShipperIntentToggle  = Notification.Name("eusoShipperIntentToggle")

    /// Per-intent row tap — opens the per-intent edit sheet (Siri
    /// phrase regex, parameter slots, default-load anchoring). Tapping
    /// the active row re-fires IntentDonationManager.shared.donate.
    static let eusoShipperIntentRow     = Notification.Name("eusoShipperIntentRow")

    /// "Manage Siri integration" pointer link tap — routes into 211
    /// Settings's Siri toggles card (source of truth for the per-intent
    /// enrollment matrix + the global App Intents framework opt-in).
    static let eusoShipperIntentManage  = Notification.Name("eusoShipperIntentManage")
}

// MARK: - Shell wrapper + Shipper BottomNav (Me current)

private func shipperNavLeading() -> [NavSlot] {
    [
        NavSlot(label: "Home",  systemImage: "house.fill",   isCurrent: false),
        NavSlot(label: "Loads", systemImage: "shippingbox",  isCurrent: false),
    ]
}
private func shipperNavTrailing() -> [NavSlot] {
    [
        NavSlot(label: "Wallet", systemImage: "creditcard",   isCurrent: false),
        NavSlot(label: "Me",     systemImage: "person.fill",  isCurrent: true),
    ]
}

struct ShipperAppIntentsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperAppIntents()
        } nav: {
            BottomNav(leading: shipperNavLeading(),
                      trailing: shipperNavTrailing(),
                      orbState: .idle)
        }
    }
}

// MARK: - Previews (Dark + Light per §11.4 doctrine)

#Preview("Shipper App Intents · Dark") {
    ShipperAppIntentsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Shipper App Intents · Light") {
    ShipperAppIntentsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}
