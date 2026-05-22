//
//  349_CatalystAwardedConfirmation.swift
//  EusoTrip — Catalyst · Awarded confirmation (§271).
//
//  Wireframe slot: 03 Catalyst / 349 Catalyst Awarded Confirmation.
//  Sister surface to 348 (Counter Receipt). Where 348 is the
//  post-counter-acceptance receipt, this surface is the broader
//  "load awarded" confirmation — fires after any path that lands the
//  load on the catalyst (posted-rate accept, counter accept, or
//  direct tender award). Single-source-of-truth read: `loads.getById`
//  with `status == "awarded"`.
//
//  Doctrine: every visible value binds to a real tRPC proc. No
//  scenario literals; "—" until data resolves. No mock data.
//

import SwiftUI

// MARK: - tRPC decode shape

private struct CACLoad: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let equipmentType: String?
    let hazmatClass: String?
    let pickupLocation: CACCityState?
    let deliveryLocation: CACCityState?
    let pickupDate: String?
    let deliveryDate: String?
    let updatedAt: String?
    struct CACCityState: Decodable, Hashable {
        let city: String?
        let state: String?
    }
}

// MARK: - Screen

struct CatalystAwardedConfirmationScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var onAssignDriver: (() -> Void)? = nil
    var onDone: (() -> Void)? = nil

    var body: some View {
        Shell(theme: theme) {
            CACBody(loadId: loadId, onAssignDriver: onAssignDriver, onDone: onDone)
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

private struct CACBody: View {
    let loadId: String
    let onAssignDriver: (() -> Void)?
    let onDone: (() -> Void)?
    @Environment(\.palette) private var palette
    @State private var load: CACLoad?

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
    private var pickupDateDisplay: String {
        guard let iso = load?.pickupDate,
              let dt = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d · h:mm a"
        return f.string(from: dt)
    }
    private var awardedAtDisplay: String {
        guard let iso = load?.updatedAt,
              let dt = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d · h:mm a"
        return f.string(from: dt)
    }
    private var rpmDisplay: String {
        guard let r = load?.rate, let n = Double(r), n > 0,
              let d = load?.distance, d > 0 else { return "—" }
        return String(format: "$%.2f/mi", n / d)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                citationPill
                awardedHero
                kpiGrid
                loadDetailCard
                nextStepCard
                actionRibbon
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
                Text("CATALYST · DISPATCH · AWARDED · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            Text("Load awarded")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Tender resolved · ledger row flips BIDDING → AWARDED")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var citationPill: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AWARDED · LEDGER COMMITTED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · \(equipmentDisplay) · \(rateDisplay) · awarded")
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

    private var awardedHero: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("AWARDED AMOUNT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("AWARDED")
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
                    Text("Awarded \(awardedAtDisplay)")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(label: String, value: String, sub: String, tint: Color)] = [
            ("RATE",      rateDisplay,        "linehaul · awarded",    .green),
            ("RPM",       rpmDisplay,         distanceDisplay,         .blue),
            ("PICKUP",    pickupDateDisplay,  "appt window",           .blue),
            ("EQUIPMENT", equipmentDisplay,   load?.hazmatClass.map { "HAZ \($0)" } ?? "lane", load?.hazmatClass != nil ? .orange : .blue),
        ]
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(k.value)
                        .font(.system(size: 16, weight: .heavy).monospacedDigit())
                        .foregroundStyle(k.tint).lineLimit(1)
                    Text(k.sub)
                        .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.tint.opacity(0.3)))
            }
        }
    }

    private var loadDetailCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("LOAD DETAIL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                rowFor(label: "Load number", value: loadNumberDisplay)
                rowFor(label: "Lane", value: laneDisplay ?? "—")
                rowFor(label: "Distance", value: distanceDisplay)
                rowFor(label: "Equipment", value: equipmentDisplay)
                if let haz = load?.hazmatClass, !haz.isEmpty {
                    rowFor(label: "Hazmat class", value: haz, tint: .orange)
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
                Text("Load is yours. Assign a driver from the dispatcher board to start the haul.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            Button { onAssignDriver?() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Assign driver").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(.white)
                .background(onAssignDriver == nil
                            ? AnyShapeStyle(LinearGradient(colors: [palette.textTertiary, palette.textTertiary], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(LinearGradient.diagonal))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(onAssignDriver == nil)

            Button { onDone?() } label: {
                Text("Done").font(EType.caption.weight(.semibold))
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

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
        } catch { /* tolerated */ }
    }
}

// MARK: - Previews

#Preview("349 Awarded · Light") {
    CatalystAwardedConfirmationScreen(theme: Theme.light, loadId: "0", onAssignDriver: {}, onDone: {})
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("349 Awarded · Dark") {
    CatalystAwardedConfirmationScreen(theme: Theme.dark, loadId: "0", onAssignDriver: {}, onDone: {})
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
