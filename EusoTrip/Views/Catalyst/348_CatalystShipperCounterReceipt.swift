//
//  348_CatalystShipperCounterReceipt.swift
//  EusoTrip — Catalyst · Outbound-counter receipt (§270).
//
//  Wireframe slot: 03 Catalyst / 348 Catalyst Shipper Counter Receipt.
//  Read-only post-acceptance surface — the shipper has just tapped
//  ACCEPT on a counter the catalyst submitted via shippers.counterBid
//  / catalysts.respondToCounter. This screen is the catalyst's
//  receipt of that acceptance: load details, the accepted amount,
//  the lane, and the next-step affordance.
//
//  Doctrine: every visible value binds to a real tRPC proc. No
//  scenario literals — the wireframe ships canonical Aurora /
//  Diego / LA→PHX / $2,425 strings to illustrate; production
//  substitutes whichever load was the counter subject and shows
//  "—" while data resolves.
//
//  tRPC procs consumed (verified real):
//    · loads.getById — load context (lane, equipment, rate, status)
//

import SwiftUI

// MARK: - tRPC decode shape

private struct CCRLoad: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let equipmentType: String?
    let hazmatClass: String?
    let pickupLocation: CCRCityState?
    let deliveryLocation: CCRCityState?
    let pickupDate: String?
    let updatedAt: String?
    struct CCRCityState: Decodable, Hashable {
        let city: String?
        let state: String?
    }
}

// MARK: - Screen

struct CatalystShipperCounterReceiptScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var onDone: (() -> Void)? = nil

    var body: some View {
        Shell(theme: theme) {
            CCRBody(loadId: loadId, onDone: onDone)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",                isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.stack.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet",  systemImage: "creditcard.fill",      isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct CCRBody: View {
    let loadId: String
    let onDone: (() -> Void)?
    @Environment(\.palette) private var palette
    @State private var load: CCRLoad?

    private var loadNumberDisplay: String { load?.loadNumber ?? "—" }
    private var rateDisplay: String {
        if let r = load?.rate, let n = Double(r), n > 0 {
            let v = n.rounded()
            return v < 1000 ? String(format: "$%.0f", v) : "$\(Int(v).formatted(.number))"
        }
        return "—"
    }
    private var laneDisplay: String? {
        let p = [load?.pickupLocation?.city, load?.pickupLocation?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let d = [load?.deliveryLocation?.city, load?.deliveryLocation?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if p.isEmpty && d.isEmpty { return nil }
        return "\(p.isEmpty ? "—" : p) → \(d.isEmpty ? "—" : d)"
    }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "—" }
        return "\(Int(d.rounded())) mi"
    }
    private var equipmentDisplay: String {
        let parts = [load?.equipmentType, load?.cargoType].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
    private var acceptedAtDisplay: String {
        guard let iso = load?.updatedAt,
              let dt = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d · h:mm a"
        return f.string(from: dt)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationPill
                receiptHero
                ledgerImpactCard
                nextStepCard
                doneButton
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · OUTBOUND · COUNTER · RECEIPT · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text("Counter accepted")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Shipper tapped ACCEPT · ledger row flips PENDING → ACCEPTED")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var citationPill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OUTBOUND COUNTER · ACCEPTED · LEDGER LANDED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · \(equipmentDisplay) · \(rateDisplay) · accepted")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lane = laneDisplay {
                    Text("\(lane) · \(distanceDisplay)")
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var receiptHero: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ACCEPTED AMOUNT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("ACCEPTED")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
                Text(rateDisplay)
                    .font(.system(size: 32, weight: .heavy).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text("Accepted \(acceptedAtDisplay)")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var ledgerImpactCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("LEDGER IMPACT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                rowFor(label: "Load number", value: loadNumberDisplay)
                rowFor(label: "Lane", value: laneDisplay ?? "—")
                rowFor(label: "Equipment", value: equipmentDisplay)
                rowFor(label: "Distance", value: distanceDisplay)
                if let haz = load?.hazmatClass, !haz.isEmpty {
                    rowFor(label: "Hazmat", value: haz, tint: .orange)
                }
                rowFor(label: "Status", value: (load?.status ?? "—").uppercased(), tint: .green)
            }
        }
    }

    private func rowFor(label: String, value: String, tint: Color = .blue) -> some View {
        HStack {
            Text(label)
                .font(.caption2).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }

    private var nextStepCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("Load is yours. Assign a driver via the dispatcher board when ready.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var doneButton: some View {
        Button { onDone?() } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13, weight: .heavy))
                Text("Done").font(EType.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(onDone == nil)
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
        } catch { /* tolerated; UI shows "—" */ }
    }
}

// MARK: - Previews

#Preview("348 Counter Receipt · Light") {
    CatalystShipperCounterReceiptScreen(theme: Theme.light, loadId: "0", onDone: {})
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("348 Counter Receipt · Dark") {
    CatalystShipperCounterReceiptScreen(theme: Theme.dark, loadId: "0", onDone: {})
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
