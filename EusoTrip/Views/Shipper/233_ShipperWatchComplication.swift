//
//  233_ShipperWatchComplication.swift
//  EusoTrip iOS — Shipper Watch Complication design-spec (§35.3 Arc L)
//
//  iOS twin of the wireframe canonical at:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/02 Shipper/Code/
//    233_ShipperWatchComplication.swift
//
//  Surface: Apple Watch Ultra 3 + Infograph face complication preview for
//  the canonical 8-stage lifecycle. Three native ClockKit families
//  (graphic-corner / graphic-circular / graphic-rectangular) bind to the
//  same WatchComplication.ContentState (loadId, stageIndex, etaSeconds,
//  distanceRemainingMi, carrierGrade, nextBidValue). Tapping any
//  complication hands off to 231 ShipperPushNotificationLanding which
//  then deep-links into 232 ShipperLockScreenLiveActivity (escort
//  divergence) or 205 ShipperLoadDetail (any other tap).
//
//  §11.4 row 3 anchor (active complication payload):
//    LD-260427-B41782FF02 · Eusorone Technologies (companyId 1) · Kansas
//    City MO → Omaha NE · MC-331 anhydrous-ammonia UN1005 · Driver
//    Michael Eusorone (Eusotrans LLC USDOT 3 194 882) · stage 5 In
//    transit · advanced 38m ago · Carrier eSang AB grade A.
//  §11.2 next-bid stat tile cites MATRIX-50 row 2: LA → PHX reefer
//  $2,200 verbatim.
//
//  Doctrine: §2 nav, §3 numbers-first, §4.3 single hairline, §7 breathe
//  density, §11 Diego canon, §11.2/§11.4 MATRIX-50 lane, §17.2 width-
//  locked status grammar, §19.2 file-scoped helpers (TierLetterBadge,
//  CornerComplication, CircularComplication, RectangularComplication,
//  MicroStrip, StatTileLite, GradientLivePill, GradientCapsuleCTA),
//  §20.4 no dead buttons, §22.2 counter eyebrow color encodes screen-
//  status, §35.3 Arc L iOS-platform integration surfaces.
//
//  Backend (server) endpoints owed (EUSO-2152):
//    watchComplications.currentForUser   -> [WatchComplication]
//    watchComplications.recentTransitions(loadId, since) -> [Transition]
//    watchComplications.setSlotForFamily(family, complicationId)
//    watchComplications.setOptInForCategory(category, enabled)
//    eta.recompute(loadId)               -> ClockKit reload trigger
//
//  iOS API surface (consumed by LiveDataStore):
//    ShipperWatchComplicationAPI.currentComplications() -> [WatchComplication]
//    ShipperWatchComplicationAPI.reloadComplications()  -> Void
//    ShipperWatchComplicationAPI.setSlotForFamily(_:to:)
//    ShipperWatchComplicationAPI.setOptInForCategory(_:enabled:)
//
//  ClockKit binding:
//    CLKComplicationDataSource — .graphicCorner / .graphicCircular /
//    .graphicRectangular families render the same ContentState at their
//    native scale; reload queue triggers off eta.recompute + lifecycle
//    stage advance.
//
//  Both #Preview blocks (Dark + Light) ship per §11.4 doctrine.
//

import SwiftUI

// MARK: - Screen

struct ShipperWatchComplication: View {
    /// In-app SFSafariViewController for `app.eusotrip.com` deep
    /// links. Replaces the prior `openURL(url)` Safari kick so the
    /// shipper stays inside the EusoTrip app while reviewing watch
    /// surfaces on web.
    @State private var inAppLink: EusoSafariLink? = nil
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL

    // §22.2 counter eyebrow — slot count + opt-in count.
    private let counterEyebrow = "3 SLOTS · 1 OF 7 OPT-IN"

    // §11.4 row 3 active complication payload.
    private let watch = WatchActivity(
        id:               "wc_2026-04-28T13:42:00Z_LD-260427-B41782FF02",
        loadId:           "LD-260427-B41782FF02",
        persona:          "Eusorone Technologies",
        lane:             "Kansas City MO → Omaha NE · MC-331 NH₃",
        stageIndex:       4,
        stageKicker:      "Stage 5 — In transit · advanced 38m ago",
        relativeAgo:      "38m ago",
        liveLabel:        "LIVE · UN1005 ESCORT · 4H 36M",
        carrierGrade:     "A",
        carrierGradeLine: "Carrier grade A · Tap any complication → 231 deep-link receiver",
        cornerSlot:       CornerSlotPayload(
                            stageTag:    "5/8",
                            etaPrimary:  "4h",
                            etaSub:      "36m"
                          ),
        circularSlot:     CircularSlotPayload(
                            eyebrow:    "ESCORT · A",
                            value:      "4h 36m",
                            sub:        "STAGE 5/8"
                          ),
        rectangularSlot:  RectangularSlotPayload(
                            headline:    "UN1005 · NH₃",
                            laneSub:     "KC MO → OMA NE",
                            etaPrimary:  "4h 36m",
                            etaSub:      "178/198 mi",
                            currentStageIndex: 4
                          ),
        nextBid:          StatLite(eyebrow: "NEXT BID",  value: "$2,200",  sub: "LA → PHX reefer", highlighted: false),
        exception:        StatLite(eyebrow: "EXCEPTION", value: "1",        sub: "UN1005 active",   highlighted: true),
        slots:            StatLite(eyebrow: "SLOTS",     value: "3 / 5",    sub: "on face",          highlighted: false),
        optIn:            StatLite(eyebrow: "OPT-IN",    value: "1 / 7",    sub: "categories",       highlighted: false),
        ctaLabel:         "Open in 231 Push Notification Landing →",
        ctaTargetScreen:  "231 Push Notification Landing"
    )

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, Space.s5)
            titleBlock
                .padding(.top, Space.s3)

            IridescentHairline()
                .padding(.top, Space.s3)

            sectionLabel("ACTIVE LOAD · WATCH HANDOFF")
                .padding(.top, Space.s5)
            activeLoadCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("WATCH COMPLICATION FAMILIES (CORNER · CIRCULAR · RECTANGULAR)")
                .padding(.top, Space.s5)
            familiesCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            openCTA
                .padding(.horizontal, Space.s7)
                .padding(.top, Space.s4)

            settingsPointerLink
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)

            footer
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s5)
        }
        .sheet(item: $inAppLink) { link in
            EusoInAppSafari(url: link.url).ignoresSafeArea()
        }
    }

    // MARK: - TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · WATCH")
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
                .accessibilityLabel("Three complication slots configured. One of seven categories opted in.")
        }
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Watch face")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Complication design-spec · Eusorone Technologies")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Section label

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }

    // MARK: - ACTIVE LOAD · WATCH HANDOFF card

    private var activeLoadCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                GradientLivePill(label: watch.liveLabel)
                Spacer(minLength: 0)
                Text(watch.relativeAgo)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(watch.persona)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)

                Text(watch.loadId)
                    .font(EType.mono(.caption))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)

                Text(watch.lane)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 2)
            }
            .padding(.top, 12)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                TierLetterBadge(letter: watch.carrierGrade)
                Text(watch.carrierGradeLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.top, 56)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - WATCH COMPLICATION FAMILIES card

    private var familiesCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Row 1 · CORNER · 60×60
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CORNER · 60×60")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                    Text("stage dot + ETA only")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    Text("slot: top-left or top-right of face · graphic-corner family")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                    Text("CLKComplicationFamilyGraphicCorner")
                        .font(EType.mono(.micro))
                        .tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CornerComplication(payload: watch.cornerSlot)
                    .frame(width: 60, height: 60)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .frame(height: 92, alignment: .top)

            Divider()
                .background(palette.borderFaint)
                .padding(.horizontal, 20)

            // Row 2 · CIRCULAR · 88×88
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CIRCULAR · 88×88")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                    Text("eyebrow + value + sub")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    Text("slot: face center · graphic-circular family")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                    Text("CLKComplicationFamilyGraphicCircular")
                        .font(EType.mono(.micro))
                        .tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                    Text("Carrier grade \"A\" inline next to eyebrow ✦ tier-letter primitive · 213 recipe")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CircularComplication(payload: watch.circularSlot)
                    .frame(width: 88, height: 88)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .frame(height: 116, alignment: .top)

            Divider()
                .background(palette.borderFaint)
                .padding(.horizontal, 20)

            // Row 3 · RECTANGULAR · 168×52
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECTANGULAR · 168×52")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                    Text("headline + lane + ETA + 8-dot strip")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    Text("slot: face bottom · graphic-rectangular family")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                    Text("CLKComplicationFamilyGraphicRectangular")
                        .font(EType.mono(.micro))
                        .tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RectangularComplication(payload: watch.rectangularSlot)
                    .frame(width: 168, height: 52)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .frame(height: 80, alignment: .top)

            // Stage kicker
            Text(watch.stageKicker)
                .font(EType.mono(.caption))
                .tracking(0.4)
                .foregroundStyle(LinearGradient.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 6)

            // 4-cell stat strip
            HStack(alignment: .top, spacing: 0) {
                StatTileLite(stat: watch.nextBid)
                StatTileLite(stat: watch.exception)
                StatTileLite(stat: watch.slots)
                StatTileLite(stat: watch.optIn)
            }
            .padding(.top, 12)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Open in 231 CTA

    private var openCTA: some View {
        Button(action: tapOpenTarget) {
            GradientCapsuleCTA(label: watch.ctaLabel)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open this Watch complication in \(watch.ctaTargetScreen)")
    }

    // MARK: - Settings pointer

    private var settingsPointerLink: some View {
        Button(action: tapManageWatchSurfaces) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watch face complications")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Slot picks + opt-in categories · 211 Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("→")
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
        .accessibilityLabel("Watch face complications. Slot picks and opt-in categories live in 211 Settings.")
    }

    // MARK: - Footer (persona+batch anchor)

    private var footer: some View {
        Text("companyId 1 · Eusorone Technologies · MATRIX-50-2026-04-26")
            .font(.system(size: 10))
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Space.s5)
    }

    // MARK: - Tap handlers (§20.4 no dead buttons)

    private func tapOpenTarget() {
        NotificationCenter.default.post(
            name: .eusoShipperWatchComplicationOpenTarget,
            object: nil,
            userInfo: [
                "source": "233_ShipperWatchComplication",
                "watchId": watch.id,
                "loadId": watch.loadId,
                "stageIndex": watch.stageIndex,
                "carrierGrade": watch.carrierGrade,
                "targetScreen": watch.ctaTargetScreen,
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/watch/\(watch.id)/open") {
            inAppLink = EusoSafariLink(url: url)
        }
    }

    private func tapManageWatchSurfaces() {
        NotificationCenter.default.post(
            name: .eusoShipperWatchComplicationManageSurfaces,
            object: nil,
            userInfo: [
                "source": "233_ShipperWatchComplication",
                "targetScreen": "211 Settings",
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/settings/watch") {
            inAppLink = EusoSafariLink(url: url)
        }
    }
}

// MARK: - Domain models (file-scoped — LiveDataStore wires these from
//          ShipperWatchComplicationAPI.currentComplications() at runtime)

private struct StatLite {
    let eyebrow:     String
    let value:       String
    let sub:         String
    let highlighted: Bool
}

private struct CornerSlotPayload {
    let stageTag:    String
    let etaPrimary:  String
    let etaSub:      String
}

private struct CircularSlotPayload {
    let eyebrow:     String
    let value:       String
    let sub:         String
}

private struct RectangularSlotPayload {
    let headline:           String
    let laneSub:            String
    let etaPrimary:         String
    let etaSub:             String
    let currentStageIndex:  Int
}

private struct WatchActivity {
    let id:                  String
    let loadId:              String
    let persona:             String
    let lane:                String
    let stageIndex:          Int
    let stageKicker:         String
    let relativeAgo:         String
    let liveLabel:           String
    let carrierGrade:        String
    let carrierGradeLine:    String
    let cornerSlot:          CornerSlotPayload
    let circularSlot:        CircularSlotPayload
    let rectangularSlot:     RectangularSlotPayload
    let nextBid:             StatLite
    let exception:           StatLite
    let slots:               StatLite
    let optIn:               StatLite
    let ctaLabel:            String
    let ctaTargetScreen:     String
}

// MARK: - TierLetterBadge (lifted from 213 Catalyst Scorecard at watch
//          scale — 22×14 gradient pill with single white heavy letter)

private struct TierLetterBadge: View {
    let letter: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient.primary)
            Text(letter)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 14)
        .accessibilityLabel("Carrier tier grade \(letter).")
    }
}

// MARK: - GradientLivePill (220×22 LIVE pill — same recipe as 232)

private struct GradientLivePill: View {
    let label: String

    var body: some View {
        ZStack {
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
                Text(label)
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 220, height: 22)
        .accessibilityLabel("Live Activity is broadcasting. \(label).")
    }
}

// MARK: - GradientCapsuleCTA (full-width gradient capsule — same as 232)

private struct GradientCapsuleCTA: View {
    let label: String

    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient.primary)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
    }
}

// MARK: - CornerComplication (60×60 quarter-notch · graphic-corner family)

private struct CornerComplication: View {
    let payload: CornerSlotPayload

    var body: some View {
        ZStack(alignment: .topLeading) {
            CornerNotchShape()
                .fill(Color(red: 0.043, green: 0.043, blue: 0.062))

            ZStack {
                Circle()
                    .fill(LinearGradient.primary.opacity(0.30))
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(LinearGradient.primary)
                    .frame(width: 8, height: 8)
            }
            .offset(x: 8, y: 8)

            Text(payload.stageTag)
                .font(EType.mono(.micro))
                .foregroundStyle(.white)
                .frame(width: 60, alignment: .trailing)
                .padding(.trailing, 10)
                .padding(.top, 11)

            VStack(spacing: 2) {
                Text(payload.etaPrimary)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(payload.etaSub)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .monospacedDigit()
            }
            .frame(width: 60, height: 60, alignment: .center)
            .offset(y: 6)
        }
        .frame(width: 60, height: 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Corner complication. Stage \(payload.stageTag). ETA \(payload.etaPrimary) \(payload.etaSub).")
    }
}

private struct CornerNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(
            to:      CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - CircularComplication (88×88 · graphic-circular family)

private struct CircularComplication: View {
    let payload: CircularSlotPayload

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.043, green: 0.043, blue: 0.062))
            Circle()
                .strokeBorder(LinearGradient.primary, lineWidth: 2)

            VStack(spacing: 2) {
                Text(payload.eyebrow)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(LinearGradient.primary)
                Text(payload.value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(payload.sub)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
        }
        .frame(width: 88, height: 88)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Circular complication. \(payload.eyebrow). \(payload.value). \(payload.sub).")
    }
}

// MARK: - RectangularComplication (168×52 with embedded MicroStrip)

private struct RectangularComplication: View {
    let payload: RectangularSlotPayload

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.043, green: 0.043, blue: 0.062))

            ZStack {
                Circle()
                    .fill(LinearGradient.primary.opacity(0.30))
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(LinearGradient.primary)
                    .frame(width: 8, height: 8)
            }
            .offset(x: 8, y: 8)

            HStack(alignment: .firstTextBaseline) {
                Text(payload.headline)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(payload.etaPrimary)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .padding(.leading, 26)
            .padding(.trailing, 12)
            .padding(.top, 10)

            HStack(alignment: .firstTextBaseline) {
                Text(payload.laneSub)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
                Spacer(minLength: 0)
                Text(payload.etaSub)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.top, 26)

            MicroStrip(currentStageIndex: payload.currentStageIndex)
                .padding(.leading, 14)
                .padding(.top, 42)
        }
        .frame(width: 168, height: 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rectangular complication. \(payload.headline). \(payload.laneSub). ETA \(payload.etaPrimary). \(payload.etaSub). Stage \(payload.currentStageIndex + 1) of 8.")
    }
}

// MARK: - MicroStrip (~140pt 8-dot lifecycle — 232 recipe lifted to
//          watch-face width with 20pt dot spacing)

private struct MicroStrip: View {
    let currentStageIndex: Int

    private let totalStages = 8
    private let dotSpacing: CGFloat = 20
    private let dotRadius:  CGFloat = 2

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { _ in
                Path { path in
                    let progressX = CGFloat(currentStageIndex) * dotSpacing
                    path.move(to: CGPoint(x: 0, y: dotRadius))
                    path.addLine(to: CGPoint(x: progressX, y: dotRadius))
                }
                .stroke(LinearGradient.primary, lineWidth: 1.4)

                Path { path in
                    let progressX = CGFloat(currentStageIndex) * dotSpacing
                    let totalX    = CGFloat(totalStages - 1) * dotSpacing
                    path.move(to: CGPoint(x: progressX, y: dotRadius))
                    path.addLine(to: CGPoint(x: totalX, y: dotRadius))
                }
                .stroke(Color.white.opacity(0.20), lineWidth: 1.4)
            }
            .frame(width: CGFloat(totalStages - 1) * dotSpacing, height: dotRadius * 2)

            HStack(spacing: dotSpacing - dotRadius * 2) {
                ForEach(0..<totalStages, id: \.self) { idx in
                    if idx < currentStageIndex {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: dotRadius * 2, height: dotRadius * 2)
                    } else if idx == currentStageIndex {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: dotRadius * 3, height: dotRadius * 3)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: 0.8)
                            )
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.30))
                            .frame(width: dotRadius * 2, height: dotRadius * 2)
                    }
                }
            }
        }
        .frame(width: CGFloat(totalStages - 1) * dotSpacing + dotRadius * 3, height: dotRadius * 3)
    }
}

// MARK: - StatTileLite (4-cell stat strip cell — narrower than 232's
//          StatTile to fit 4 cells in 360pt; highlighted variant paints
//          value in gradient)

private struct StatTileLite: View {
    @Environment(\.palette) var palette
    let stat: StatLite

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.eyebrow)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            if stat.highlighted {
                Text(stat.value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LinearGradient.primary)
                    .monospacedDigit()
            } else {
                Text(stat.value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
            }
            Text(stat.sub)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.eyebrow). \(stat.value). \(stat.sub).")
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Watch complication "Open in 231" CTA tap — deep-link route into
    /// the canonical 231 receiver, which then hands off to 232 (escort
    /// divergence) or 205 Load Detail. Payload carries watchId + loadId
    /// + stageIndex + carrierGrade + targetScreen for the parent state-
    /// machine to hydrate the destination + post seen-ack to ClockKit's
    /// reload queue.
    static let eusoShipperWatchComplicationOpenTarget       = Notification.Name("eusoShipperWatchComplicationOpenTarget")

    /// "Watch face complications" pointer link tap — routes into 211
    /// Settings's Watch toggles card (source of truth for slot picks +
    /// per-category opt-in/opt-out prefs).
    static let eusoShipperWatchComplicationManageSurfaces   = Notification.Name("eusoShipperWatchComplicationManageSurfaces")
}

// MARK: - Shell wrapper + Shipper BottomNav (Me current — Watch surfaces
//          live behind the Me tab in the Shipper IA, matching the
//          wireframe SVG nav highlight)

private func shipperNavLeading() -> [NavSlot] {
    [
        NavSlot(label: "Home",  systemImage: "house.fill",   isCurrent: false),
        NavSlot(label: "Loads", systemImage: "shippingbox",  isCurrent: false),
    ]
}
private func shipperNavTrailing() -> [NavSlot] {
    [
        NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
        NavSlot(label: "Me",     systemImage: "person.fill",  isCurrent: true),
    ]
}

struct ShipperWatchComplicationScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperWatchComplication()
        } nav: {
            BottomNav(leading: shipperNavLeading(),
                      trailing: shipperNavTrailing(),
                      orbState: .idle)
        }
    }
}

// MARK: - Previews (Dark + Light per §11.4 doctrine)

#Preview("Shipper Watch Complication · Dark") {
    ShipperWatchComplicationScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Shipper Watch Complication · Light") {
    ShipperWatchComplicationScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}
