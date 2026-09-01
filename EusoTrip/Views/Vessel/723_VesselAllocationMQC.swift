//
//  723_VesselAllocationMQC.swift
//  EusoTrip — Vessel Operator · Allocation & MQC.
//
//  Faithful 1:1 native port of "723 Vessel Allocation MQC · Dark/Light".
//  SLOT-GRID-BOARD + BURN-DOWN archetype: a per-sailing weekly slot-allocation
//  board + a contract Minimum-Quantity-Commitment burn-down.
//
//  HONEST BINDING (server/routers/vesselShipments.ts + blankSailing.ts):
//    · vesselShipments.getVesselShipments — REAL bookings → booked TEU per sailing (voyage) + YTD total.
//    · blankSailing.dashboard             — REAL scheduled/cancelled sailing counts for loop context.
//  Booked TEU is computed from REAL container counts × ISO-size TEU factor.
//  HONEST GAP (proposed to the-oath): ocean slot-allocation caps + the contract
//  MQC target/ideal-pace (allocation.weeklySlots / allocation.mqcProgress) have
//  no vessel-scoped procedure — the burn-down + per-sailing cap surface as
//  explicit awaiting states, never a fabricated 3,000-TEU commitment.
//  RBAC vesselProcedure · transportMode=vessel · US/CA/MX discharge split.
//

import SwiftUI

private struct VesselShipmentList723: Decodable { let shipments: [VesselShipmentRow723]? }
private struct VesselShipmentRow723: Decodable {
    let id: Int?
    let bookingNumber: String?
    let voyageNumber: String?
    let serviceRoute: String?
    let numberOfContainers: Int?
    let containerSize: String?
    let etd: String?
    let status: String?
}
private struct BlankSailingDash723: Decodable {
    let summary: BlankSummary723?
}
private struct BlankSummary723: Decodable { let cancelledSailings: Int?; let scheduledSailings: Int? }

private struct SailingSlot723: Identifiable {
    let id = UUID()
    let label: String
    let bookedTeu: Double
    let etd: String?
}

struct VesselAllocationMQCScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselAllocationMQCBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselAllocationMQCBody: View {
    @Environment(\.palette) private var palette

    @State private var slots: [SailingSlot723] = []
    @State private var ytdTeu: Double = 0
    @State private var scheduledSailings = 0
    @State private var cancelledSailings = 0
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if slots.isEmpty && ytdTeu <= 0 {
                    EusoEmptyState(
                        systemImage: "square.grid.3x3",
                        title: "No sailings booked",
                        subtitle: "The weekly slot-allocation board and MQC burn-down populate once vessel bookings exist on a service loop.")
                } else {
                    heroCard
                    weeklyBoard
                    burnDownCard
                    spotContractCard
                    dischargeBand
                    ctaRow
                    if let actionMessage {
                        LifecycleCard { Text(actionMessage).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · ALLOCATION · MQC")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("AS-USWC").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            Text("Allocation & MQC").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            ForEach([132, 150, 112], id: \.self) { h in
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: CGFloat(h))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    // Hero — YTD booked TEU
    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(Color(hex: 0x141928)).padding(1.5)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Service loop · weekly sailings").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color(hex: 0xAAB2BB))
                    Spacer()
                    StatusPill(text: "\(scheduledSailings) scheduled", kind: .info)
                }
                Text("Allocation & MQC").font(.system(size: 16, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("Weekly slot allocation · contract MQC").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xAAB2BB))
                Text("\(teu(ytdTeu)) TEU booked").font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                Text("YTD across \(slots.count) sailing\(slots.count == 1 ? "" : "s") · MQC target awaiting contract")
                    .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color(hex: 0x6E7681))
            }
            .padding(Space.s5)
        }
        .frame(minHeight: 132)
    }

    // Weekly allocation board — per-sailing booked TEU (real)
    private var weeklyBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("WEEKLY ALLOCATION", ref: "allocation.weeklySlots", gap: true)
            VStack(spacing: 0) {
                let maxBooked = max(slots.map(\.bookedTeu).max() ?? 1, 1)
                ForEach(Array(slots.prefix(7).enumerated()), id: \.element.id) { idx, s in
                    HStack(spacing: 10) {
                        Text(s.label).font(.system(size: 9.5, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                            .frame(width: 128, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.bgCardSoft).frame(height: 10)
                                Capsule().fill(LinearGradient.primary)
                                    .frame(width: max(6, geo.size.width * CGFloat(s.bookedTeu / maxBooked)), height: 10)
                            }
                        }.frame(height: 10)
                        Text("\(teu(s.bookedTeu))").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                            .frame(width: 40, alignment: .trailing).monospacedDigit()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    if idx < min(slots.count, 7) - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16) }
                }
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            Text("Booked TEU per sailing · allocation cap requires a signed carrier allocation")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }

    // MQC burn-down — awaiting contract target
    private var burnDownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("MQC BURN-DOWN · contract fulfilment", ref: "allocation.mqcProgress", gap: true)
            VStack(alignment: .leading, spacing: 12) {
                let cum = cumulative
                let peak = max(cum.last ?? 1, 1)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(cum.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(LinearGradient.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 8 + CGFloat(cum[i] / peak) * 44)
                    }
                }
                .frame(height: 56, alignment: .bottom)
                Text("Cumulative booked TEU is real; the contract MQC target, ideal pace, and shortfall-fee risk await allocation.mqcProgress — no fabricated commitment line.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
            .padding(16).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private var cumulative: [Double] {
        guard !slots.isEmpty else { return [0] }
        var run = 0.0
        return slots.prefix(7).map { run += $0.bookedTeu; return run }
    }

    private var spotContractCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SPOT vs CONTRACT · $/TEU", ref: "oceanRate", gap: false)
            VStack(alignment: .leading, spacing: 8) {
                Text("Contract vs spot $/TEU comparison surfaces from the ocean rate index (687 Ocean Rate Lookup).")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                Text("Ship on contract when spot runs over — save per-TEU.")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.success)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var dischargeBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ALLOCATION BY DISCHARGE COUNTRY", ref: "loop·country", gap: false)
            CountryBand723(rows: [
                .init(code: "US", line: "US · USWC Long Beach", active: true),
                .init(code: "CA", line: "CA · Vancouver VFPA", active: false),
                .init(code: "MX", line: "MX · Manzanillo API", active: false),
            ])
        }
    }

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Book next slot", action: {
                actionMessage = "A signed service-loop allocation is required before this slot can be booked."
            })
            Button { actionMessage = "A verified contract commitment target is required before this MQC report can be produced." } label: {
                Text("MQC report").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 52)
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ title: String, ref: String, gap: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(gap ? "NOT AVAILABLE" : ref).font(EType.mono(.micro)).foregroundStyle(gap ? Brand.warning : palette.textTertiary)
        }
    }

    private func load() async {
        loading = true; loadError = nil; actionMessage = nil
        defer { loading = false }
        struct ListInput: Encodable { let limit: Int; let offset: Int }
        do {
            let list: VesselShipmentList723 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipments", input: ListInput(limit: 40, offset: 0))
            let rows = list.shipments ?? []
            // Group by sailing (voyageNumber, else booking) → booked TEU.
            var grouped: [String: (teu: Double, etd: String?)] = [:]
            var total = 0.0
            for r in rows {
                let key = firstNonEmpty(r.voyageNumber, r.bookingNumber, r.serviceRoute) ?? "Sailing"
                let t = teuForContainers(count: r.numberOfContainers ?? 0, size: r.containerSize)
                total += t
                var g = grouped[key] ?? (0, r.etd)
                g.teu += t
                if g.etd == nil { g.etd = r.etd }
                grouped[key] = g
            }
            ytdTeu = total
            slots = grouped
                .map { SailingSlot723(label: sailingLabel($0.key), bookedTeu: $0.value.teu, etd: $0.value.etd) }
                .sorted { ($0.etd ?? "") < ($1.etd ?? "") }
            let dash: BlankSailingDash723? = try? await EusoTripAPI.shared.queryNoInput("blankSailing.dashboard")
            scheduledSailings = dash?.summary?.scheduledSailings ?? slots.count
            cancelledSailings = dash?.summary?.cancelledSailings ?? 0
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            slots = []; ytdTeu = 0
        }
    }

    private func teuForContainers(count: Int, size: String?) -> Double {
        let per: Double = {
            guard let s = size?.lowercased() else { return 1 }
            if s.contains("45") { return 2.25 }
            if s.contains("40") { return 2 }
            if s.contains("20") { return 1 }
            return 1
        }()
        return Double(count) * per
    }
    private func sailingLabel(_ raw: String) -> String {
        raw.count > 22 ? String(raw.prefix(22)) : raw
    }
    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { v -> String? in
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty == false) ? t : nil
        }.first
    }
    private func teu(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = (v.rounded() == v) ? 0 : 1
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }
}

private struct CountryBand723: View {
    struct Row: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }
    let rows: [Row]
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                HStack(spacing: 10) {
                    Text(r.code).font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(r.active ? Color.white : palette.textSecondary)
                        .frame(width: 26, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(r.active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft)))
                    Text(r.line).font(.system(size: 10.5, weight: r.active ? .bold : .regular))
                        .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(r.active ? "ACTIVE" : "STANDBY").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(r.active ? Brand.success : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(r.active ? AnyShapeStyle(palette.bgCard) : AnyShapeStyle(Color.clear))
                if idx < rows.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
            }
        }
        .padding(6).background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("723 · Vessel Allocation MQC · Night") { VesselAllocationMQCScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("723 · Vessel Allocation MQC · Light") { VesselAllocationMQCScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
