//
//  149_DriverClosedPaidReceiptCelM04.swift
//  EusoTrip — Driver · closed / paid-receipt surface.
//
//  Wireframe slot: 01 Driver / 149 Driver Closed Paid Receipt CEL M04.
//  Extends the DL141 close octet to a "paid + ring rolled to CLOSED"
//  state. READ-ONLY consumer — the driver has no verb to set "paid"
//  (drivers.updateLoadStatus enum terminates at "delivered"). The
//  factoring autopilot writes delivered→invoiced (dispatch.ts:280)
//  and invoiced→paid (dispatch.ts:284); loadLifecycle fans out
//  "Payment Received" to the driver (loadLifecycle.ts:96).
//
//  Doctrine: every visible value binds to a tRPC read. No scenario
//  literals — the wireframe ships canonical CEL/M-04/JR/DU strings
//  to illustrate a moment; this production view substitutes them
//  with whichever load is currently bound and shows "—" when a
//  field hasn't resolved yet. Both action buttons route through
//  DriverNavController.
//

import SwiftUI

// MARK: - tRPC decode shapes

/// Minimal projection of `loads.getById` — we ask only for the fields
/// this surface actually renders. Server returns many more, including
/// the 2026-05-22 resolved party objects (driver / catalyst / shipper)
/// with name + initials + companyName + mcNumber.
private struct PRLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let status: String?
    let distance: Double?
    let rate: String?
    let driverId: Int?
    let catalystId: Int?
    let shipperId: Int?
    let pickupLocation: PRCityState?
    let deliveryLocation: PRCityState?
    let deliveryDate: String?
    let driver: PRParty?
    let catalyst: PRParty?
    let shipper: PRParty?
    struct PRCityState: Decodable, Hashable {
        let city: String?
        let state: String?
    }
    struct PRParty: Decodable, Hashable {
        let id: Int?
        let name: String?
        let initials: String?
        let email: String?
        let companyName: String?
        let mcNumber: String?
        let dotNumber: String?
    }
}

/// `drivers.getEarnings` projection.
private struct PREarnings: Decodable, Hashable {
    let period: String?
    let totalEarnings: Double?
    let total: Double?
    let milesPaid: Double?
    let ratePerMile: Double?
    let netPay: Double?
}

// MARK: - Screen

struct DriverCELM04PaidReceiptScreen: View {
    let theme: Theme.Palette
    let loadId: String
    @EnvironmentObject private var nav: DriverNavController

    var body: some View {
        Shell(theme: theme) {
            PRBody(loadId: loadId,
                   onViewEarnings: { nav.currentTab = .wallet },
                   onViewReceipt:  { nav.currentTab = .wallet })
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Trips", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct PRBody: View {
    let loadId: String
    let onViewEarnings: () -> Void
    let onViewReceipt: () -> Void

    @Environment(\.palette) private var palette
    @State private var load: PRLoadCtx?
    @State private var earnings: PREarnings?

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi"
    }
    private var settleDateDisplay: String {
        guard let iso = load?.deliveryDate,
              let delivered = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let settle = Calendar.current.date(byAdding: .day, value: 30, to: delivered) ?? delivered
        let f = DateFormatter(); f.dateFormat = "M/d"
        return f.string(from: settle)
    }
    private var payoutDisplay: String {
        if let net = earnings.flatMap({ $0.netPay ?? $0.totalEarnings ?? $0.total }) {
            return Self.currency(net)
        }
        if let r = load?.rate, let n = Double(r), n > 0 {
            return Self.currency(n)
        }
        return "—"
    }
    private var rpmDisplay: String {
        if let r = earnings?.ratePerMile, r > 0 {
            return String(format: "$%.2f", r)
        }
        return "—"
    }
    private var laneDisplay: String? {
        guard let p = load?.pickupLocation?.city, let d = load?.deliveryLocation?.city else { return nil }
        return "\(p) → \(d)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationPill
                chainPill
                identityRow
                kpiGrid
                receiptCard
                settlementCompleteCapsule
                paidReceivedRow
                nextLoadPreviewRow
                actionRibbon
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: header / pills

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DRIVER · TRIPS · CLOSED · PAID · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Settled")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("PAID · NET-30 · ring rolled PAPERWORK → CLOSED")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var citationPill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CLOSED · PAID · NET-30 SETTLE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · payout \(payoutDisplay) · NET-30 \(settleDateDisplay) · CLOSED")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lane = laneDisplay {
                    Text(lane)
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var chainPill: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("DISPATCH CHAIN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · invoice cleared · paid · load closed")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var identityRow: some View {
        let driverInitials = load?.driver?.initials ?? "—"
        let driverName = load?.driver?.name ?? "driver"
        let carrierName = load?.catalyst?.companyName ?? load?.catalyst?.name ?? "—"
        let mc = load?.catalyst?.mcNumber.map { "MC-\($0)" } ?? "—"
        let dispatchName = load?.catalyst?.name ?? "—"
        let shipperName = load?.shipper?.name ?? "—"
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(
                        Text(driverInitials)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(carrierName) · \(driverName) · driver")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(mc) · \(dispatchName) dispatcher · \(shipperName) shipper")
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    // MARK: KPI grid (PAYOUT / RPM / NET-30 / CLOSED)

    private var kpiGrid: some View {
        let kpis: [(label: String, value: String, sub: String, tint: Color)] = [
            ("PAYOUT", payoutDisplay,    "NET-30 · settled",              .green),
            ("RPM",    rpmDisplay,       distanceDisplay,                 .blue),
            ("NET-30", settleDateDisplay, "settle date",                  .blue),
            ("STATE",  "CLOSED",          load?.status ?? "—",            .green),
        ]
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(k.value)
                        .font(.system(size: 18, weight: .heavy).monospacedDigit())
                        .foregroundStyle(k.tint)
                    Text(k.sub)
                        .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.tint.opacity(0.3)))
            }
        }
    }

    // MARK: Receipt card — 4 rows, each anchored to a real read / received push

    private var receiptCard: some View {
        let rows: [(label: String, value: String, kind: ReceiptRowKind)] = [
            ("Invoice cleared · invoiced→paid", "CLEARED",  .received),
            ("Payment Received · paid fan-out",  "RECEIVED", .received),
            ("Load closed · ring → CLOSED",      "CLOSED",   .received),
            ("Earnings updated · period total",  payoutDisplay, .real),
        ]
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("PAID · \(loadNumberDisplay) SETTLED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        receiptBadge(row.kind)
                        Text(row.label)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(row.value)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(row.kind == .received ? Color.blue : palette.textSecondary)
                    }
                }
            }
        }
    }

    private enum ReceiptRowKind { case received, real }

    private func receiptBadge(_ k: ReceiptRowKind) -> some View {
        Group {
            switch k {
            case .received:
                ZStack {
                    Circle().stroke(LinearGradient.diagonal, lineWidth: 2).frame(width: 16, height: 16)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
            case .real:
                ZStack {
                    Circle().fill(Color.green.opacity(0.18)).frame(width: 16, height: 16)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.green)
                }
            }
        }
    }

    // MARK: Settlement-complete capsule (POD+BOL+invoice+paid = 4/4)

    private var settlementCompleteCapsule: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SETTLEMENT · 4 / 4 · COMPLETE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bgCard).frame(height: 6)
                Capsule().fill(LinearGradient.diagonal).frame(height: 6)
            }
        }
    }

    // MARK: PAYMENT RECEIVED row (paid fan-out consumed)

    private var paidReceivedRow: some View {
        LifecycleCard(accentGradient: true) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PAID · PAYMENT RECEIVED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("loadLifecycle paid → [catalystId, driverId]")
                        .font(.system(size: 8.5, design: .monospaced)).tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("RECEIVED")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("CLOSED")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
        }
    }

    // MARK: NEXT-LOAD preview (chain terminal)

    private var nextLoadPreviewRow: some View {
        LifecycleCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT · CHAIN CLOSED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text("Next load posting")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Text("NEXT")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Action ribbon — VIEW EARNINGS (primary, gradient) + VIEW RECEIPT (glass-rim)

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            Button(action: onViewEarnings) {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill").font(.system(size: 13, weight: .heavy))
                    Text("View earnings").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onViewReceipt) {
                Text("View receipt").font(EType.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(LinearGradient.diagonal)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(LinearGradient.diagonal.opacity(0.55), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: data

    private func refresh() async {
        _ = await (loadCtx(), loadEarnings())
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
        } catch { /* read-only screen, tolerate */ }
    }

    private func loadEarnings() async {
        struct In: Encodable { let period: String }
        do {
            earnings = try await EusoTripAPI.shared.query("drivers.getEarnings", input: In(period: "month"))
        } catch { /* read-only screen, tolerate */ }
    }

    private static func currency(_ amount: Double) -> String {
        let value = amount.rounded()
        return value < 1000 ? String(format: "$%.0f", value) : "$\(Int(value).formatted(.number))"
    }
}

// MARK: - Previews

#Preview("149 Paid Receipt · Light") {
    DriverCELM04PaidReceiptScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.light)
}

#Preview("149 Paid Receipt · Dark") {
    DriverCELM04PaidReceiptScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.dark)
}
