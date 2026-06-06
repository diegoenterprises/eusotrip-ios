//
//  757_VesselDetentionLetters.swift
//  EusoTrip — Vessel Operator · Detention Letters.
//
//  Faithful 1:1 port of "757 Vessel Detention Letters.svg" (Light + Dark), RECONSTRUCTED to flagship
//  CORRESPONDENCE grammar (mirror 02 Shipper/205 + 06 Vessel/758): 28pt detail title + back chevron
//  + caption + overflow, EXPOSURE gradient-rim hero (total pending detention figure + INITIAL/
//  ESCALATION/FINAL tier chips), and a facility letter ledger where every card now carries a 40x40
//  tier-color letter chip + facility title + NOTICE-id mono sub + tier pill clear of the right status
//  + events/charges/wait line + Review chip + date, CTA pair (Generate letters / Export PDF), ESang
//  chronic-facility row, real Vessel Operator BottomNav with COMPLIANCE inked. Nav anchored to
//  VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME) — the same
//  Shell + BottomNav wrapper the registered vessel siblings 664/680/667 ship.
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    detentionAccessorials.getDetentionLetters (EXISTS frontend/server/routers/detentionAccessorials.ts:1410 ·
//      input {facilityName?,dateFrom?,dateTo?}? · returns {letters:[{facilityName,eventCount,totalCharges,
//      avgWaitMinutes,firstEvent,lastEvent,letterType final_warning|escalation|initial_notice,status:"draft"}]}
//      grouped from detention_claims HAVING event_count>=2, ORDER BY total_charges DESC LIMIT 20. Empty
//      list when no facility has 2+ events — the bespoke empty state renders honestly, no fabricated rows).
//    "Generate letters" -> createDetentionLetter — STUB · named-gap (read-only today: getDetentionLetters
//      returns letterType+status only; a mutation that writes a letter row, sets status='sent', inserts
//      blockchainAuditTrail, broadcasts WS_CHANNELS.detention is the surfaced backend gap).
//    "Export PDF" -> renderLetterPdf — STUB · named-gap.
//
//  0 mock data on load · honest empty/error states — values render from real state; if the endpoint
//  returns no letters the bespoke empty state shows. The two write verbs are honestly flagged STUB
//  (no backing mutation yet) rather than faked. RimCard757 / ESangRow757 are file-scoped bespoke
//  helpers (the canonical port's RimCard/ESangRow are not shared app symbols) built from the same
//  gradient-rim grammar the registered siblings use, to preserve the exact wireframe look.
//

import SwiftUI

private enum LetterTier757 { case initialNotice, escalation, finalNotice
    var label: String { switch self { case .initialNotice: "INITIAL NOTICE"; case .escalation: "ESCALATION"; case .finalNotice: "FINAL NOTICE" } }
    var tint: Color { switch self { case .initialNotice: Color(red: 0.08, green: 0.40, blue: 0.75); case .escalation: Color(red: 0.70, green: 0.45, blue: 0.0); case .finalNotice: Color(red: 0.78, green: 0.16, blue: 0.16) } }
}

private struct FacilityLetter757: Identifiable {
    let id = UUID()
    let facility: String
    let notice: String
    let tier: LetterTier757
    let events: Int
    let charges: String
    let avgWait: String
    let status: String
    let date: String
}

struct VesselDetentionLettersScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselDetentionLettersBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselDetentionLettersBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var hasLetters = false

    @State private var exposure = "$0"
    @State private var exposureSub = "across 0 events"
    @State private var avgWait = "no detention to paper"
    @State private var nInitial = 0
    @State private var nEscalation = 0
    @State private var nFinal = 0

    @State private var letters: [FacilityLetter757] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !hasLetters {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No detention letters to paper",
                                   subtitle: "No facility has 2+ detention events in range. getDetentionLetters returned an empty ledger, nothing to escalate.")
                } else {
                    exposureHero
                    Text("BY FACILITY · WORST OFFENDERS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    ForEach(letters) { facilityCard($0) }
                    HStack(spacing: 8) {
                        CTAButton(title: "Generate letters", action: { Task { await generate() } }, trailingIcon: "doc.badge.plus")
                        secondaryButton(title: "Export PDF") { Task { await exportPdf() } }
                    }
                    ESangRow757(title: "ESang: \(chronicFacility) is your chronic offender",
                                subtitle: chronicSubtitle)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DETENTION LETTERS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("3 TIERS").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Notice letters").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var exposureHero: some View {
        RimCard757 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("PENDING DETENTION · \(letters.count) FACILITIES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("QTD").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(exposure).font(.system(size: 30, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exposureSub).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(avgWait).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    tierChip(count: nInitial, label: "INITIAL", tint: LetterTier757.initialNotice.tint)
                    tierChip(count: nEscalation, label: "ESCALATION", tint: LetterTier757.escalation.tint)
                    tierChip(count: nFinal, label: "FINAL", tint: LetterTier757.finalNotice.tint)
                }
            }
        }
    }

    private func tierChip(count: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            ZStack { Circle().fill(tint).frame(width: 12, height: 12)
                Text("\(count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) }
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.4).foregroundStyle(tint)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.12)))
        .frame(maxWidth: .infinity)
    }

    private func facilityCard(_ l: FacilityLetter757) -> some View {
        LifecycleCard {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(l.tier.tint.opacity(0.12)).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "doc.text").font(.system(size: 16, weight: .semibold)).foregroundStyle(l.tier.tint))
                VStack(alignment: .leading, spacing: 6) {
                    Text(l.facility).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(l.notice).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Text(l.tier.label).font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundStyle(l.tier.tint)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(l.tier.tint.opacity(0.12)))
                    Text("\(l.events) events · \(l.charges) charges · avg wait \(l.avgWait)").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text(l.status).font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(palette.textTertiary)
                    secondaryButton(title: "Review") {}
                        .frame(width: 84, height: 28)
                    Text(l.date).font(.system(size: 11)).monospacedDigit().foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar the
    /// registered siblings (680) use for their secondary CTA.
    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    /// Chronic offender for the ESang row = worst facility (server orders by total_charges DESC,
    /// so the first letter is the highest-exposure facility).
    private var chronicFacility: String { letters.first?.facility ?? "-" }
    private var chronicSubtitle: String {
        guard let top = letters.first else { return "send the final notice now" }
        let verb = (top.tier == .finalNotice) ? "send the final notice now" : "escalate now"
        return "\(verb) - \(top.events) events, \(top.charges) unpapered"
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            struct Letter: Decodable { let facilityName: String?; let eventCount: Int?; let totalCharges: Double?; let avgWaitMinutes: Int?; let letterType: String?; let status: String? }
            struct Resp: Decodable { let letters: [Letter]? }
            let r: Resp = try await EusoTripAPI.shared.query("detentionAccessorials.getDetentionLetters", input: EmptyInput757())
            if let ls = r.letters, !ls.isEmpty {
                var totalCharges = 0.0, totalEvents = 0, totalWait = 0, ini = 0, esc = 0, fin = 0
                letters = ls.map { l in
                    let tier: LetterTier757 = (l.letterType == "final_warning") ? .finalNotice : (l.letterType == "escalation" ? .escalation : .initialNotice)
                    switch tier { case .initialNotice: ini += 1; case .escalation: esc += 1; case .finalNotice: fin += 1 }
                    totalCharges += l.totalCharges ?? 0
                    totalEvents += l.eventCount ?? 0
                    totalWait += l.avgWaitMinutes ?? 0
                    let wait = Double(l.avgWaitMinutes ?? 0) / 60.0
                    return FacilityLetter757(
                        facility: l.facilityName ?? "-",
                        notice: "NOTICE · \(l.facilityName?.prefix(3).uppercased() ?? "-")",
                        tier: tier,
                        events: l.eventCount ?? 0,
                        charges: "$\(Int(l.totalCharges ?? 0))",
                        avgWait: String(format: "%.1fh", wait),
                        status: (l.status ?? "draft").uppercased(),
                        date: "-")
                }
                exposure = "$\(Int(totalCharges))"
                exposureSub = "across \(totalEvents) events"
                let avgHours = Double(totalWait) / Double(ls.count) / 60.0
                avgWait = String(format: "avg wait %.1fh · ready to paper", avgHours)
                nInitial = ini; nEscalation = esc; nFinal = fin
                hasLetters = true
            } else {
                letters = []; hasLetters = false
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func generate() async { /* createDetentionLetter — STUB · named-gap (surfaced to the-oath). */ await load() }
    private func exportPdf() async { /* renderLetterPdf — STUB · named-gap. */ await load() }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (664 `moveContextCard`, 680 `shipmentContextCard`) ship.
private struct RimCard757<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

/// ESang advisory row — the canonical port's `ESangRow` is not a shared app
/// symbol, so we render the same sparkle + advisory grammar file-scoped.
private struct ESangRow757: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

private struct EmptyInput757: Encodable {}

#Preview("757 · Detention Letters · Night") { VesselDetentionLettersScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("757 · Detention Letters · Light") { VesselDetentionLettersScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
