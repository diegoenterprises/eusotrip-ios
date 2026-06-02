//
//  570_RailDemurrageDispute.swift
//  EusoTrip — Rail Engineer · Demurrage Dispute (carrier-side dispute-filing surface).
//
//  Verbatim port of "570 Rail Demurrage Dispute.svg" (Light + Dark).
//  Action companion to watch-only 558 Rail Demurrage Watch. Charge filing surface
//  with dwell attribution, disposition pills, and createDispute CTA.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Data:
//    railShipments.calculateRailDemurrage  (EXISTS railShipments.ts:597)         → charge hero
//    railDemurrageAuto.dashboard           (EXISTS railDemurrageAuto.ts:18)      → KPI summary
//    railDemurrageAuto.reportByDwellReason (EXISTS railDemurrageAuto.ts:93)      → attribution rows
//    railDemurrageAuto.createDispute       (EXISTS railDemurrageAuto.ts:78)      → File-dispute CTA
//

import SwiftUI

struct RailDemurrageDisputeScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) { RailDemurrageDisputeBody(railId: railId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct DemurrageCharge570: Decodable {
    let id: String?
    let railId: String?
    let facilityName: String?
    let containerNumber: String?
    let shipper: String?
    let accruedUsd: Double?
    let daysAccrued: Int?
    let dailyRateUsd: Double?
    let contestedUsd: Double?
    let contestedDays: Int?
    let status: String?
}

private struct DemurrageDashboard570: Decodable {
    let totalAccruedUsd: Double?
    let totalContestedUsd: Double?
    let winRatePct: Double?
}

private struct DwellAttribution570: Decodable, Identifiable {
    let id: Int
    let reason: String?
    let reasonLabel: String?
    let days: Double?
    let attribution: String?
    let disposition: String?        // "contest" | "valid" | "waiver"
    let amountUsd: Double?
}

// MARK: - Body

private struct RailDemurrageDisputeBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var charge: DemurrageCharge570? = nil
    @State private var dashboard: DemurrageDashboard570? = nil
    @State private var attributions: [DwellAttribution570] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isFiling = false

    // MARK: Derived

    private var accruedLabel: String  { charge?.accruedUsd.map { "$\(Int($0))" } ?? dashboard?.totalAccruedUsd.map { "$\(Int($0))" } ?? "—" }
    private var contestedLabel: String {
        let amt = charge?.contestedUsd ?? attributions.filter { contestDisp($0.disposition) }.compactMap { $0.amountUsd }.reduce(0, +)
        return amt > 0 ? "$\(Int(amt))" : "—"
    }
    private var contestedAmount: Double {
        charge?.contestedUsd ?? attributions.filter { contestDisp($0.disposition) }.compactMap { $0.amountUsd }.reduce(0, +)
    }
    private var winRateLabel: String { dashboard?.winRatePct.map { "\(Int($0))%" } ?? "—" }
    private var disputeIdCaption: String { charge?.id ?? "DEM-—" }

    private func contestDisp(_ d: String?) -> Bool { (d ?? "").lowercased() == "contest" }

    private var chargeContextSub: String {
        let days = charge?.daysAccrued ?? 0
        let rate = charge?.dailyRateUsd.map { "@$\(Int($0))" } ?? ""
        let container = charge?.containerNumber ?? "—"
        let shipper = charge?.shipper ?? "—"
        return "\(container) · \(shipper)\(days > 0 || !rate.isEmpty ? " · \(days) days \(rate)" : "")"
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading dispute…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    attributionList
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · DEMURRAGE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(disputeIdCaption)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Demurrage dispute")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text((charge?.status ?? "CONTESTABLE").uppercased())
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
                Text(charge?.facilityName ?? "—")
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(accruedLabel)
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    let days = charge?.daysAccrued ?? 0
                    let rate = charge?.dailyRateUsd.map { " · \(days) days @ $\(Int($0))" } ?? ""
                    Text("accrued\(rate)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(chargeContextSub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("CONTESTED")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(contestedLabel)
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Brand.danger)
                    Text("\(charge?.contestedDays ?? 0) days")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "ACCRUED",   value: accruedLabel)
            MetricTile(label: "CONTESTED", value: contestedLabel, gradientNumeral: true)
            MetricTile(label: "WIN RATE",  value: winRateLabel, accent: Brand.success)
        }
    }

    // MARK: - Attribution list

    private var attributionList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("DWELL ATTRIBUTION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("reportByDwellReason")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if attributions.isEmpty {
                EusoEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No dwell attribution",
                    subtitle: "Dwell reason breakdown will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(attributions.enumerated()), id: \.element.id) { idx, attr in
                        attributionRow(attr)
                        if idx < attributions.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                                .overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func reasonIcon(_ reason: String?) -> String {
        switch (reason ?? "").lowercased() {
        case let r where r.contains("congestion") || r.contains("ramp"): return "chart.line.uptrend.xyaxis"
        case let r where r.contains("consignee") || r.contains("building"): return "building.2"
        case let r where r.contains("weather"): return "cloud.fill"
        case let r where r.contains("gate") || r.contains("outage"): return "exclamationmark.circle"
        default: return "clock"
        }
    }

    private func reasonChipColor(_ reason: String?, disposition: String?) -> Color {
        let disp = (disposition ?? "").lowercased()
        if disp == "waiver" { return Brand.info }
        if disp == "valid"  { return Color(red: 0.38, green: 0.49, blue: 0.55) }
        let r = (reason ?? "").lowercased()
        if r.contains("weather") { return Brand.info }
        return Brand.warning
    }

    private func dispositionChipColor(_ d: String?) -> Color {
        switch (d ?? "").lowercased() {
        case "contest": return Brand.warning
        case "waiver":  return Brand.success
        default:        return Color(red: 0.38, green: 0.49, blue: 0.55)
        }
    }
    private func dispositionPillLabel(_ d: String?) -> String {
        (d ?? "VALID").uppercased()
    }

    private func attributionRow(_ attr: DwellAttribution570) -> some View {
        let reason     = attr.reason ?? ""
        let disp       = attr.disposition
        let chipColor  = reasonChipColor(reason, disposition: disp)
        let pillColor  = dispositionChipColor(disp)
        let label      = attr.reasonLabel ?? reason.replacingOccurrences(of: "_", with: " ").capitalized
        let daysStr    = attr.days.map { $0 == Double(Int($0)) ? "\(Int($0)) day\(Int($0) == 1 ? "" : "s")" : "\($0) days" } ?? "—"
        let attribStr  = attr.attribution ?? "—"
        let amountStr  = attr.amountUsd.map { $0 == 0 ? "$0" : "$\(Int($0))" } ?? "—"

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: reasonIcon(reason))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chipColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(daysStr) · \(attribStr)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(dispositionPillLabel(disp))
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(pillColor.opacity(0.14)))
                Text(amountStr)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(attr.amountUsd == 0 ? palette.textTertiary : palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        let cLabel = contestedAmount > 0 ? "File dispute · $\(Int(contestedAmount))" : "File dispute"
        return HStack(spacing: Space.s2) {
            CTAButton(title: cLabel, action: { Task { await fileDispute() } }, leadingIcon: "list.bullet.rectangle", isLoading: isFiling)
            Button {} label: {
                Text("Save draft")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct RailIn: Encodable { let railId: String }
        struct EmptyIn: Encodable {}
        do {
            async let charge: DemurrageCharge570 = EusoTripAPI.shared.query(
                "railShipments.calculateRailDemurrage", input: RailIn(railId: railId))
            async let dash: DemurrageDashboard570 = EusoTripAPI.shared.query(
                "railDemurrageAuto.dashboard", input: EmptyIn())
            async let attrs: [DwellAttribution570] = EusoTripAPI.shared.query(
                "railDemurrageAuto.reportByDwellReason", input: RailIn(railId: railId))
            let (c, d, a) = try await (charge, dash, attrs)
            self.charge       = c
            self.dashboard    = d
            self.attributions = a
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func fileDispute() async {
        isFiling = true
        struct DisputeIn: Encodable { let railId: String; let contestedUsd: Double; let reason: String }
        struct DisputeOut: Decodable {}
        do {
            let _: DisputeOut = try await EusoTripAPI.shared.query(
                "railDemurrageAuto.createDispute",
                input: DisputeIn(railId: railId, contestedUsd: contestedAmount, reason: "carrier-attributable dwell"))
            await load()
        } catch { /* keep current state */ }
        isFiling = false
    }
}

#Preview("570 · Rail Demurrage Dispute · Night") { RailDemurrageDisputeScreen(theme: Theme.dark, railId: "RAIL-260523-7C3A0B12D4").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("570 · Rail Demurrage Dispute · Light") { RailDemurrageDisputeScreen(theme: Theme.light, railId: "RAIL-260523-7C3A0B12D4").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
