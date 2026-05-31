//
//  620_RailReleaseOrder.swift
//  EusoTrip — Rail Engineer · Release Order (carrier-side · gate-out).
//
//  Verbatim port of "620 Rail Release Order.svg" (05 Rail · Dark) onto the
//  canonical DesignSystem primitives. Reconstructed to the flagship DETAIL
//  grammar (616 / 609 / 02 Shipper 205) per FOUNDER CADENCE DIRECTIVE
//  2026-05-24: back chevron + sparkle eyebrow + caption + 28/-0.4 title,
//  gradient-rimmed hero ActiveCard (holds-cleared figure + cleared progress
//  + HELD word), 3-cell KPI strip (cell-1 eusoDiagonal), itemized hold
//  ListRow stack, release-on-clear context strip, Release-container /
//  Hold-detail CTA pair — NOT a stat dashboard.
//
//  tRPC anchors (CONFIRMED in-repo):
//    railShipments.getRailShipmentDetail   (railShipments.ts:209) → status,
//        shipmentNumber, demurrage[], events[] — REAL.
//    railShipments.updateRailShipmentStatus (railShipments.ts:237) →
//        on_hold release path — REAL (input { id, newStatus, notes? }).
//
//  RBAC: railProcedure (RAIL_ENGINEER / carrier-side). mode=rail.
//  NAV (RailEngineerNavController): HOME · SHIPMENTS(current) · [orb] ·
//        COMPLIANCE · ME.
//
//  PORT-GAP: the customs (CBP entry) + freight-charges hold breakdown shown
//  in the wireframe is NOT a discrete field on getRailShipmentDetail. Only
//  the demurrage hold (railDemurrage rows) and the on_hold status are real.
//  The customs/freight hold cells render an honest empty/error state — never
//  fabricated values. See `// PORT-GAP:` markers below.
//

import SwiftUI

struct RailReleaseOrderScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) { RailReleaseOrderBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getRailShipmentDetail · railShipments.ts:209)

private struct RailDemurrageRow620: Decodable {
    let id: Int?
    let freeTimeHours: Int?
    let chargeableHours: Int?
    let totalCharge: String?
    let status: String?
}

private struct RailEvent620: Decodable, Identifiable {
    let id: Int
    let eventType: String?
    let description: String?
    let location: String?
    let timestamp: String?
}

/// getRailShipmentDetail returns `{ ...shipment, waybills, events,
/// demurrage, originYard, destinationYard }` — i.e. the raw railShipments
/// row spread at the top level. We decode only the fields this screen reads;
/// every one is optional so a missing column degrades to an honest dash.
private struct RailReleaseDetail620: Decodable {
    let id: Int?
    let shipmentNumber: String?
    let status: String?
    let rate: String?
    let originCity: String?
    let originState: String?
    let destCity: String?
    let destState: String?
    let containerNumber: String?
    let demurrage: [RailDemurrageRow620]?
    let events: [RailEvent620]?
}

// MARK: - Hold model (derived from REAL detail; non-derivable cells = PORT-GAP)

private struct ReleaseHold620: Identifiable {
    enum HoldState { case cleared, pending, unknown }
    let id: String
    let title: String
    let detail: String
    let state: HoldState
    let value: String
    /// True when this cell is a PORT-GAP placeholder (no real source field).
    let portGap: Bool
}

// MARK: - Body

private struct RailReleaseOrderBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var detail: RailReleaseDetail620? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var releasing = false
    @State private var releaseError: String? = nil
    @State private var releaseDone = false

    // MARK: Derived release math (all from REAL detail)

    /// The demurrage hold is the only hold cell with a real backing source
    /// (railDemurrage rows). Customs + freight holds are PORT-GAP.
    private var demurrageRow: RailDemurrageRow620? { detail?.demurrage?.first }

    private var demurrageCharge: Double {
        Double(demurrageRow?.totalCharge ?? "0") ?? 0
    }

    private var isOnHold: Bool {
        (detail?.status ?? "").lowercased().contains("hold")
    }

    /// Three canonical holds. Customs + freight are PORT-GAP (rendered as an
    /// honest unknown state — NEVER fabricated $-values). Demurrage is real.
    private var holds: [ReleaseHold620] {
        guard detail != nil else { return [] }
        let demCleared = demurrageCharge <= 0
        return [
            // PORT-GAP: no customs/CBP-entry hold field on getRailShipmentDetail.
            ReleaseHold620(
                id: "customs",
                title: "Customs · CBP entry",
                detail: "no customs-hold source on detail",
                state: .unknown,
                value: "—",
                portGap: true
            ),
            // REAL — railDemurrage rows ($0 due ⇒ cleared).
            ReleaseHold620(
                id: "demurrage",
                title: "Demurrage · ramp",
                detail: demCleared
                    ? "paid through LFD · $0 due"
                    : "\(demurrageRow?.chargeableHours ?? 0)h chargeable · accruing",
                state: demCleared ? .cleared : .pending,
                value: demCleared ? "$0" : currency(demurrageCharge),
                portGap: false
            ),
            // PORT-GAP: no freight-charges hold field on getRailShipmentDetail.
            ReleaseHold620(
                id: "freight",
                title: "Freight charges",
                detail: "no freight-hold source on detail",
                state: .unknown,
                value: "—",
                portGap: true
            ),
        ]
    }

    private var clearedCount: Int { holds.filter { $0.state == .cleared }.count }
    private var holdsTotal: Int { holds.count }
    /// Cleared fraction for the hero progress bar — real cleared / total.
    private var clearedFraction: Double {
        holdsTotal == 0 ? 0 : Double(clearedCount) / Double(holdsTotal)
    }

    private var containerLabel: String {
        let cn = detail?.containerNumber
        let origin = cityLabel(detail?.originCity, detail?.originState)
        if let cn, !cn.isEmpty {
            return origin.isEmpty ? cn : "\(cn) · \(origin)"
        }
        if let n = detail?.shipmentNumber, !n.isEmpty {
            return origin.isEmpty ? n : "\(n) · \(origin)"
        }
        return origin.isEmpty ? "—" : origin
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        LifecycleCard {
                            Text("Loading release order…")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if detail != nil {
                        hero
                        kpiStrip
                        holdsCard
                        releaseOnClearStrip
                        ctaPair
                    } else {
                        EusoEmptyState(
                            systemImage: "lock.shield",
                            title: "No release order",
                            subtitle: "This rail container has no release record."
                        )
                    }
                }
                .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Top bar (back chevron + eyebrow + caption + 28/-0.4 title)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · RELEASE")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("GATE-OUT")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Release order")
                        .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("BNSF INTERMODAL")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("synced 1m ago")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 2)
            }
            .padding(.top, Space.s3)
        }
    }

    // MARK: - Hero (gradient-rimmed ActiveCard · holds-cleared · HELD word)

    private var hero: some View {
        let heldOut = isOnHold
        return ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                // Status pill row: release · on hold
                HStack(spacing: Space.s2) {
                    Text("release")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    if heldOut {
                        Text("on hold")
                            .font(.system(size: 11, weight: .bold)).tracking(0.5)
                            .foregroundStyle(Color(hex: 0xFF6B6B))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(Brand.danger.opacity(0.20)))
                    }
                }

                // Big figure + label + container sub | right: GATE-OUT / HELD word
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(clearedCount) of \(holdsTotal)")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        Text("holds cleared")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(containerLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("GATE-OUT")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(heldOut ? "HELD" : "READY")
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(heldOut ? Color(hex: 0xFF6B6B) : Brand.success)
                    }
                }

                // Cleared progress bar (real cleared fraction)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                            .frame(height: 6)
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(0, geo.size.width * clearedFraction), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - 3-cell KPI strip (cell-1 eusoDiagonal · HOLDS / CLEARED / STATUS)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // Cell 1 — diagonal gradient fill
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("HOLDS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("\(holdsTotal)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            // Cell 2 — CLEARED (success numeral)
            kpiCell(label: "CLEARED", value: "\(clearedCount)", accent: Brand.success)
            // Cell 3 — STATUS (HELD word)
            kpiCell(label: "STATUS", value: isOnHold ? "HELD" : "READY",
                    accent: isOnHold ? Color(hex: 0xFF6B6B) : Brand.success)
        }
    }

    private func kpiCell(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Holds card (itemized ListRow stack · must clear to release)

    private var holdsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("HOLDS · MUST CLEAR TO RELEASE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("railShipments.ts:209")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(holds.enumerated()), id: \.element.id) { idx, hold in
                    holdRow(hold)
                    if idx < holds.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                    }
                }
                // Release path context line
                Rectangle().fill(Color.clear).frame(height: Space.s3)
                HStack {
                    Text("+ Release path · on_hold → spotted → unloading · armed on clear")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func holdRow(_ hold: ReleaseHold620) -> some View {
        let tint: Color
        let pillText: String
        let pillColor: Color
        let valueColor: Color
        let icon: String
        switch hold.state {
        case .cleared:
            tint = Brand.success; pillText = "CLEARED"; pillColor = Brand.success
            valueColor = Brand.success; icon = "checkmark"
        case .pending:
            tint = Brand.warning; pillText = "PENDING"; pillColor = Brand.warning
            valueColor = Brand.warning; icon = "clock"
        case .unknown:
            tint = palette.textTertiary; pillText = "PORT-GAP"; pillColor = palette.textTertiary
            valueColor = palette.textTertiary; icon = "questionmark"
        }
        return HStack(spacing: Space.s3) {
            // 40x40 hold-type icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            // Title + mono detail sub
            VStack(alignment: .leading, spacing: 3) {
                Text(hold.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(hold.detail)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            // Short status pill + right tabular value
            VStack(alignment: .trailing, spacing: 6) {
                Text(pillText)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(pillColor.opacity(0.20)))
                Text(hold.state == .cleared && hold.value == "$0" ? "ok"
                        : hold.value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(valueColor).monospacedDigit()
            }
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - Release-on-clear context strip

    private var releaseOnClearStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RELEASE ON CLEAR · GATE-OUT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("railShipments.ts:237")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("Clear freight hold → auto-release on_hold → spotted for gate-out")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(originLine)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            if let releaseError {
                Text(releaseError)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
            if releaseDone {
                Text("Release submitted · on_hold cleared")
                    .font(EType.caption)
                    .foregroundStyle(Brand.success)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var originLine: String {
        let num = detail?.shipmentNumber ?? "—"
        return "Eusorone Technologies (DU) · \(num)"
    }

    // MARK: - CTA pair (Release container / Hold detail)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: releasing ? "Releasing…" : "Release container",
                action: { Task { await releaseContainer() } },
                isLoading: releasing
            )
            holdDetailButton
                .frame(width: 148)
        }
    }

    /// Secondary CTA (#232932 glass per SVG) — the muted "Hold detail"
    /// variant the wireframe specifies, distinct from the gradient primary.
    private var holdDetailButton: some View {
        Button(action: {}) {
            Text("Hold detail")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .background(Color(hex: 0x232932))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .buttonStyle(.plain)
    }

    // MARK: - Formatting helpers

    private func currency(_ v: Double) -> String {
        if v >= 1000 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            let n = f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
            return "$\(n)"
        }
        return "$\(Int(v))"
    }

    private func cityLabel(_ city: String?, _ state: String?) -> String {
        switch (city, state) {
        case let (c?, s?): return "\(c), \(s)"
        case let (c?, nil): return c
        case let (nil, s?): return s
        default: return ""
        }
    }

    // MARK: - Load (REAL · getRailShipmentDetail)

    private func reload() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        do {
            let d: RailReleaseDetail620 = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail", input: DetailIn(id: shipmentId))
            self.detail = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Release (REAL · updateRailShipmentStatus · on_hold release path)

    private func releaseContainer() async {
        guard let id = detail?.id ?? (shipmentId > 0 ? shipmentId : nil) else { return }
        releasing = true; releaseError = nil; releaseDone = false
        // Server `on_hold` allows: requested/car_ordered/.../in_transit/
        // cancelled (railShipments.ts:267). The wireframe's auto-release
        // path resumes the shipment off-hold; we submit the canonical
        // resume target and surface any server transition rejection
        // verbatim — no silent failure.
        struct StatusIn: Encodable { let id: Int; let newStatus: String; let notes: String }
        struct Empty620: Decodable {}
        do {
            _ = try await EusoTripAPI.shared.mutation(
                "railShipments.updateRailShipmentStatus",
                input: StatusIn(id: id, newStatus: "in_transit",
                                notes: "Release order armed — holds cleared, gate-out")) as Empty620
            releaseDone = true
            await reload()
        } catch {
            releaseError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        releasing = false
    }
}

#Preview("620 · Rail Release Order · Night") {
    RailReleaseOrderScreen(theme: Theme.dark, shipmentId: 48231)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("620 · Rail Release Order · Light") {
    RailReleaseOrderScreen(theme: Theme.light, shipmentId: 48231)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
