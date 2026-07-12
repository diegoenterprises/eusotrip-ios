//
//  824_VesselRiskProfile.swift
//  EusoTrip — Vessel Operator · Vessel Screening Risk Profile.
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/824 Vessel Risk Profile.svg" (Light + Dark), built on the
//  canonical DesignSystem at the golden-era bar. Archetype = RISK-METER + FLAG-TIMELINE +
//  FACTOR-LEDGER — a hull-IDENTITY screening board (composite score, reflagging history, and a
//  GISIS/flag-churn/AIS/STS/sanctions factor ledger), deliberately distinct from an AIS-track view.
//  Competitive bar: Kpler, Windward, Pole Star PurpleTRAC. Role VESSEL_OPERATOR · nav COMPLIANCE inked.
//
//  Data / wiring (endpoints confirmed on disk this fire):
//    STUB · named-gap handed to the-oath: the composite identity score + GISIS scrap-registry lookup +
//      flag-change-history are NOT modelled server-side (grep risk/GISIS/reflagging = 0). Propose
//      vessel.getScreeningProfile: vesselProcedure.query({imo}) -> {score, band:low|review|block,
//      flagHistory:[{flag, from, to}], factors:[{key:gisis|flagChurn|aisGap|sts|sanctions,
//      state:clear|watch|fail, note}]} · vessel.rescreenVessel({imo, confirm:true}).mutation ->
//      re-runs the screen, writes blockchainAuditTrail vessel.screening_run. This screen ATTEMPTS the
//      real query and renders the honest AWAITING state until it lands — no fabricated score/factors.
//    Real adjacent vessel-compliance signals that exist today (surfaced to the-oath as the compose
//      source): vesselShipments.getVesselCompliance:2047 · getUSCGCompliance:3462 ·
//      getVesselAttention:3650 — RBAC vesselProcedure.
//    Regulator band = published screening authorities (US OFAC SDN/CBP · CA OSFI/CBSA · MX UIF/SEMAR).
//
//  ScreeningProfile824 / RiskFactor824 are file-scoped bespoke types. Dark + Light #Preview.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Proposed data shape (vessel.getScreeningProfile)

private struct FlagSpan824: Decodable, Identifiable { let flag: String?; let from: String?; let to: String?; var id: String { "\(flag ?? "")\(from ?? "")" } }
private struct RiskFactor824: Decodable, Identifiable { let key: String?; let state: String?; let note: String?; var id: String { key ?? UUID().uuidString } }
private struct ScreeningProfile824: Decodable {
    let score: Int?
    let band: String?
    let flagHistory: [FlagSpan824]?
    let factors: [RiskFactor824]?
}

// The 5 screening dimensions (the ledger structure · industry-standard checks).
private struct FactorDim824: Identifiable {
    let id: String
    let title: String
    let note: String
}
private let factorDims824: [FactorDim824] = [
    .init(id: "gisis",     title: "GISIS scrap registry", note: "not a reactivated / phantom hull"),
    .init(id: "flagChurn", title: "Flag changes (12 mo)",  note: "reflagging churn vs stable registry"),
    .init(id: "aisGap",    title: "AIS continuity",        note: "dark gaps over 4h on voyage"),
    .init(id: "sts",       title: "STS transfer pattern",  note: "loiter + gap rendezvous flags"),
    .init(id: "sanctions", title: "Sanctions list",        note: "OFAC / EU / UN · ownership chain"),
]

// MARK: - Screen wrapper (Shell + vessel nav · COMPLIANCE inked)

struct VesselRiskProfileScreen: View {
    let theme: Theme.Palette
    var imo: String

    init(theme: Theme.Palette, imo: String = "") { self.theme = theme; self.imo = imo }

    var body: some View {
        Shell(theme: theme) {
            VesselRiskProfileBody824(imo: imo)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselRiskProfileBody824: View {
    @Environment(\.palette) private var palette
    let imo: String

    @State private var profile: ScreeningProfile824? = nil
    @State private var loading = true

    private var hasProfile: Bool { profile?.score != nil }
    private var score: Int? { profile?.score }
    private var bandLabel: String {
        switch (profile?.band ?? "").lowercased() {
        case "low": return "LOW RISK"; case "review": return "REVIEW"; case "block": return "BLOCK"
        default: return hasProfile ? "SCREENED" : "AWAITING"
        }
    }
    private var bandColor: Color {
        switch (profile?.band ?? "").lowercased() {
        case "low": return Brand.success; case "review": return Brand.warning; case "block": return Brand.danger
        default: return palette.textTertiary
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                topBar
                IridescentHairline()
                heroCard
                flagTimeline
                factorLedger
                regulatorBand
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Eyebrow + top bar

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · VESSEL SCREENING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("IMO GISIS").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Vessel risk profile").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    // MARK: Hero (score + risk meter · gradient rim)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text(imo.isEmpty ? "IMO — · flag —" : "IMO \(imo) · flag —")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(bandColor).frame(width: 6, height: 6)
                    Text(bandLabel).font(.system(size: 8.5, weight: .heavy)).tracking(0.4).foregroundStyle(bandColor)
                }
                .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(palette.bgCardSoft))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(score.map(String.init) ?? "—").font(.system(size: 30, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("/ 100").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textTertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("COMPOSITE SCREENING SCORE").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                    Text(hasProfile ? "screening engine result"
                                    : "awaiting vessel.getScreeningProfile")
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
            }
            riskMeter
            HStack {
                Text("0 · clear").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.textTertiary)
                Spacer(); Text("50 · review").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.textTertiary)
                Spacer(); Text("100 · block").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
    }

    private var riskMeter: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bgCard).frame(height: 8)
                Capsule().fill(LinearGradient(colors: [Brand.success, Brand.warning, Brand.danger], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8).opacity(hasProfile ? 1 : 0.35)
                if let s = score {
                    let x = CGFloat(min(max(s, 0), 100)) / 100 * w
                    RoundedRectangle(cornerRadius: 2).fill(palette.textPrimary).frame(width: 4, height: 18).offset(x: x - 2)
                }
            }
        }
        .frame(height: 18)
    }

    // MARK: Flag history timeline

    private var flagTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("FLAG HISTORY · reflagging 12mo")
                Spacer()
                Text("IMO GISIS · ship registry").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            let flags = profile?.flagHistory ?? []
            if flags.isEmpty {
                awaitingBlock(icon: "flag", line: "Flag-change history surfaces here once the GISIS registry lookup is wired.")
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(flags.enumerated()), id: \.offset) { idx, f in
                        VStack(spacing: 6) {
                            Circle().fill(idx == 0 ? Brand.info : palette.textTertiary).frame(width: 12, height: 12)
                            Text(f.flag ?? "—").font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textPrimary)
                            Text("\(f.from ?? "")\(f.to.map { "→\($0)" } ?? "")").font(.system(size: 8)).foregroundStyle(palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        if idx < flags.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 2).frame(maxWidth: 40).offset(y: 5) }
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    // MARK: Risk factor ledger

    private var factorLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("RISK FACTORS · screening")
                Spacer()
                Text("STUB · getScreeningProfile").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(factorDims824.enumerated()), id: \.offset) { idx, dim in
                    factorRow(dim)
                    if idx < factorDims824.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 44) }
                }
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func factorRow(_ dim: FactorDim824) -> some View {
        let live = profile?.factors?.first(where: { $0.key == dim.id })
        let state = (live?.state ?? "").lowercased()
        let c: Color = state == "clear" ? Brand.success : (state == "watch" ? Brand.warning : (state == "fail" ? Brand.danger : palette.textTertiary))
        let icon = state == "clear" ? "checkmark" : (state == "fail" ? "xmark" : "exclamationmark")
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(c.opacity(0.16)).frame(width: 20, height: 20)
                if state.isEmpty {
                    Circle().strokeBorder(palette.textTertiary, lineWidth: 1.2).frame(width: 12, height: 12)
                } else {
                    Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(c)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(dim.title).font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(live?.note ?? dim.note).font(.system(size: 8.5)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Text(state.isEmpty ? "AWAITING" : state.uppercased())
                .font(.system(size: 8, weight: .heavy)).foregroundStyle(c)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 10)
    }

    // MARK: Regulator band

    private var regulatorBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("REGULATOR · single active gated")
                Spacer()
                Text("screening · country").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 6) {
                regRow(active: true,  code: "US", body: "OFAC SDN · CBP vessel arrival", state: "ACTIVE")
                regRow(active: false, code: "CA", body: "OSFI / CBSA · marine security", state: "STANDBY")
                regRow(active: false, code: "MX", body: "UIF / SEMAR · buque", state: "STANDBY")
            }
            .padding(Space.s3)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private func regRow(active: Bool, code: String, body: String, state: String) -> some View {
        HStack(spacing: Space.s2) {
            Text(code).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(active ? .white : palette.textSecondary)
                .frame(width: 22, height: 14).background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard)).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(body).font(.system(size: 10.5, weight: active ? .bold : .semibold)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary).lineLimit(1)
            Spacer(minLength: Space.s2)
            Text(state).font(.system(size: 8, weight: .heavy)).foregroundStyle(active ? Brand.success : palette.textTertiary)
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s2) {
                CTAButton(title: "Re-screen vessel", action: {}, trailingIcon: "arrow.right", isLoading: true)
                    .frame(maxWidth: .infinity)
                Button(action: {}) {
                    Text("GISIS record")
                        .font(EType.title).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).frame(maxWidth: 140)
            }
            Text("Re-screening is a gated, audited write — live when vessel.rescreenVessel lands.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Helpers

    private func awaitingBlock(icon: String, line: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(palette.textTertiary.opacity(0.14)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            Text(line).font(.system(size: 11)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }

    // MARK: Load

    private func load() async {
        loading = true
        struct In824: Encodable { let imo: String }
        // Attempts the proposed screening endpoint; absent today -> honest awaiting state, no fabrication.
        profile = try? await EusoTripAPI.shared.query("vessel.getScreeningProfile", input: In824(imo: imo))
        loading = false
    }
}

// MARK: - Previews

#Preview("824 · Vessel Risk Profile · Night") {
    VesselRiskProfileScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("824 · Vessel Risk Profile · Light") {
    VesselRiskProfileScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
