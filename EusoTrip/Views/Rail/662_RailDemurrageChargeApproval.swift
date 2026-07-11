//
//  662_RailDemurrageChargeApproval.swift
//  EusoTrip — Rail Engineer · Demurrage Charge Approval (Dark + Light ·
//  verbatim port of "05 Rail / 662 Rail Demurrage Charge Approval.svg").
//
//  ARCHETYPE = DECISION QUEUE: the pending figure, a 3-cell posture strip, a
//  DECISION QUEUE where every charge carries a recommendation pill (APPROVE /
//  ADJUST) plus its basis and age, a footnote, a free-time regime band, and an
//  Approve-all / Adjust CTA pair. Deliberately distinct from its accrual
//  sibling (661) which CALCULATES the charges — 662 DECIDES on them.
//
//  WIRING (grep-confirmed · frontend/server/routers/railDemurrageAuto.ts):
//    • posture + queue → railDemurrageAuto.dashboard (query · :46)
//        { summary{ totalChargesAccruing, activeAccruals, disputesOpen },
//          perCarRunway[{ demurrageId, railcarNumber, chargeableHours,
//          ratePerHour, usdToday }] }.
//    • Adjust / dispute → railDemurrageAuto.createDispute (mutation · :264)
//        input { confirm:true, demurrageId, reason, notes?, requestedWaiverAmount? }.
//    • Approve / Approve all → STUB · named-gap railDemurrageAuto.approveCharges
//        (proposed: approveCharges({ demurrageIds[] }) -> { approved, total };
//        writes rail_demurrage.status + blockchainAuditTrail; broadcasts
//        WS_EVENTS.CHARGE_APPROVED). Surfaced honestly — no fabricated approve.
//    HONEST NOTE: the APPROVE / ADJUST row pill is a client recommendation over
//    live data, not a stored decision; the real action is the createDispute
//    mutation (Adjust) — Approve awaits the router's approve verb.
//
//  RBAC: protectedProcedure. transportMode=rail · US·USD.
//  NAV (RailEngineerNavController): current = COMPLIANCE.
//

import SwiftUI

struct RailDemurrageChargeApprovalScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDemurrageChargeApprovalBody() } nav: {
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

// MARK: - Decodables

private struct ApprovalDashboard662: Decodable {
    struct Summary: Decodable {
        let activeAccruals: Int?
        let totalChargesAccruing: Double?
        let disputesOpen: Int?
    }
    struct Car: Decodable, Identifiable {
        let demurrageId: Int?
        let railcarNumber: String?
        let chargeableHours: Double?
        let ratePerHour: Double?
        let usdToday: Double?
        var id: Int { demurrageId ?? railcarNumber.hashValue }
    }
    let summary: Summary?
    let perCarRunway: [Car]?
}

private struct DisputeResult662: Decodable {
    let disputeId: String?
    let status: String?
    let reason: String?
    let requestedWaiver: Double?
}

private enum DemCountry662: String, CaseIterable, Identifiable {
    case US, CA, MX
    var id: String { rawValue }
    var freeLabel: String { self == .MX ? "24h free" : "48h free" }
    var rateLabel: String { self == .MX ? "$40/hr · MXN" : (self == .CA ? "$35/hr · CAD" : "$35/hr · USD") }
}

// MARK: - Body

private struct RailDemurrageChargeApprovalBody: View {
    @Environment(\.palette) private var palette

    @State private var data: ApprovalDashboard662? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var country: DemCountry662 = .US
    @State private var busy = false
    @State private var ack: String? = nil

    private var cars: [ApprovalDashboard662.Car] { data?.perCarRunway ?? [] }
    private var pending: Double { data?.summary?.totalChargesAccruing ?? 0 }
    private var onClock: Int { data?.summary?.activeAccruals ?? cars.count }
    private var disputesOpen: Int { data?.summary?.disputesOpen ?? 0 }

    /// Recommendation heuristic over live data: a charge with an odd basis
    /// (billed dollars but no chargeable hours) is flagged ADJUST for review;
    /// everything else reads APPROVE. This is a client recommendation, not a
    /// stored decision.
    private func recommendsAdjust(_ c: ApprovalDashboard662.Car) -> Bool {
        (c.usdToday ?? 0) > 0 && (c.chargeableHours ?? 0) <= 0
    }

    private var oldest: ApprovalDashboard662.Car? {
        cars.max { ($0.chargeableHours ?? 0) < ($1.chargeableHours ?? 0) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                heroFigure
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    postureStrip
                    decisionQueue
                    footnote
                    freeTimeBand
                    if let ack {
                        Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: Eyebrow + title + hero

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · APPROVALS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("QUEUE · \(cars.count) PENDING")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Demurrage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    private var heroFigure: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dollars(pending))
                    .font(.system(size: 32, weight: .bold)).tracking(-0.6).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("pending")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("\(cars.count) charge\(cars.count == 1 ? "" : "s") awaiting decision · \(disputesOpen) in dispute")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Posture strip

    private var postureStrip: some View {
        HStack(spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("PENDING").font(EType.micro).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.85))
                Text(dollars(pending))
                    .font(.system(size: 20, weight: .bold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            postureCell("ON THE CLOCK", "\(onClock)", accent: palette.textPrimary)
            postureCell("DISPUTES", "\(disputesOpen)",
                        accent: disputesOpen > 0 ? Brand.danger : palette.textPrimary)
        }
    }

    private func postureCell(_ label: String, _ value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold)).monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Decision queue

    private var decisionQueue: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("DECISION QUEUE").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("basis · amount")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            if cars.isEmpty {
                EusoEmptyState(
                    icon: Image(systemName: "checkmark.seal"),
                    title: "Nothing awaiting approval",
                    subtitle: "The decision queue clears as accruals are approved. Rows read from railDemurrageAuto.dashboard.",
                    comingSoon: false
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(cars.enumerated()), id: \.element.id) { idx, c in
                        decisionRow(c)
                        if idx < cars.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.vertical, Space.s3)
                        }
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func decisionRow(_ c: ApprovalDashboard662.Car) -> some View {
        let adjust = recommendsAdjust(c)
        let accent: Color = adjust ? Brand.warning : Brand.success
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: adjust ? "exclamationmark.triangle" : "doc.text")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.railcarNumber ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("demurrage \(hrs(c.chargeableHours))h · \(dollars(c.ratePerHour ?? 0))/hr")
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(adjust ? "ADJUST" : "APPROVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(accent.opacity(0.16)).clipShape(Capsule())
                Text(dollars(c.usdToday ?? 0))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Footnote

    private var footnote: some View {
        (Text("Approve all clears ")
            + Text(dollars(pending)).fontWeight(.bold).foregroundColor(palette.textPrimary)
            + Text(" · auto-approve ≤ $200"))
            .font(.system(size: 11))
            .foregroundStyle(palette.textSecondary)
    }

    // MARK: Free-time band

    private var freeTimeBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FREE-TIME REGIME · BY COUNTRY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(DemCountry662.allCases) { c in
                    let active = c == country
                    Button { country = c } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(c.rawValue) · \(c.freeLabel)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(active ? Color.white : palette.textPrimary)
                            Text(c.rateLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(active ? Color.white.opacity(0.9) : palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .frame(minHeight: 44)
                        .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(active ? Color.clear : palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await approveAll() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    Text(busy ? "Working…" : "Approve all")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(busy ? 0.6 : 1).disabled(busy)

            Button { Task { await adjustOldest() } } label: {
                Text("Adjust")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(busy ? 0.6 : 1).disabled(busy)
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 64)
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 260)
        }
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Formatting

    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$\(f.string(from: NSNumber(value: v)) ?? "0")"
    }
    private func hrs(_ v: Double?) -> String {
        let x = v ?? 0
        return x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x)
    }

    // MARK: Data

    private func reload() async {
        loading = true; loadError = nil
        do {
            self.data = try await EusoTripAPI.shared.queryNoInput("railDemurrageAuto.dashboard")
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Approve-all — the router has no approve verb yet (railDemurrageAuto has
    /// dashboard / calculateAccrual / runBulkAccrual / createDispute only). We
    /// surface the gap honestly rather than fabricating a bulk approval.
    private func approveAll() async {
        guard !cars.isEmpty else { ack = "Nothing pending to approve."; return }
        ack = "Approve-all is pending railDemurrageAuto.approveCharges — the router ships no approve verb yet. Per-charge Adjust (createDispute) is live below."
    }

    /// Adjust — opens a real dispute on the oldest pending charge via
    /// railDemurrageAuto.createDispute (EXISTS).
    private func adjustOldest() async {
        guard let car = oldest, let demId = car.demurrageId else {
            ack = "No charge with a demurrage id to adjust."
            return
        }
        busy = true; ack = nil
        defer { busy = false }
        struct Input: Encodable {
            let confirm: Bool
            let demurrageId: Int
            let reason: String
        }
        do {
            let res: DisputeResult662 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.createDispute",
                input: Input(confirm: true, demurrageId: demId, reason: "data_error"))
            ack = "Adjustment opened for \(car.railcarNumber ?? "car") · \(res.disputeId ?? "dispute") (\(res.status ?? "submitted"))."
        } catch {
            ack = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("662 · Rail Demurrage Charge Approval · Night") {
    RailDemurrageChargeApprovalScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("662 · Rail Demurrage Charge Approval · Light") {
    RailDemurrageChargeApprovalScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
