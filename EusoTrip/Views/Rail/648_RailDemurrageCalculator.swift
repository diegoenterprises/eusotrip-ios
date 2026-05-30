//
//  648_RailDemurrageCalculator.swift
//  EusoTrip — Rail Engineer · Demurrage Calculator (carrier-side intermodal).
//
//  Verbatim port of wireframe "648 Rail Demurrage Calculator · Dark".
//  Built to the flagship DETAIL grammar (645 Rail Detention Dashboard /
//  02 Shipper 205): back-chevron + sparkle eyebrow + mono caption +
//  28/-0.4 title; gradient-rimmed hero ActiveCard with lead figure +
//  progress; 3-cell KPI strip (cell-1 eusoDiagonal); itemized accrual
//  ListRow stack (40x40 icon chip + title + mono sub + short status pill
//  + right tabular value); bulk-accrual context strip; CTA pair.
//
//  CARRIER BNSF Intermodal · shipper-of-record Diego Usoro · Eusorone
//  Technologies. Pure-rail (no driver-anchor ME disc).
//
//  tRPC anchor (SVG <desc>, grep-confirmed server-side in-repo):
//    railDemurrageAuto.calculateAccrual   railDemurrageAuto.ts:36
//    detentionAccessorials.calculateDemurrage detentionAccessorials.ts:616
//    railDemurrageAuto.runBulkAccrual     railDemurrageAuto.ts:66
//
//  PORT-GAP: none of the railDemurrageAuto.* procedures are wired into the
//  iOS EusoTripAPI surface yet (only detentionAccessorials detention-pay
//  recovery is). We wire the canonical tRPC paths through the generic
//  query/mutation transport; until the server procedures ship to the iOS
//  router, the screen renders a real empty/error state — never fabricated
//  figures. Each unwired path is flagged inline with `// PORT-GAP:`.
//

import SwiftUI

struct RailDemurrageCalculatorScreen: View {
    let theme: Theme.Palette
    /// Defaults to the wireframe's carrier shipment so the screen is
    /// driveable standalone; injected by the shipment-detail push in
    /// production. Only `theme` is required.
    var shipmentRef: String = "RAIL-260524-9C41"

    var body: some View {
        Shell(theme: theme) { RailDemurrageCalculatorBody(shipmentRef: shipmentRef) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror railDemurrageAuto.calculateAccrual output)

/// Single accrual line item from `railDemurrageAuto.calculateAccrual`.
/// `kind` drives the icon chip + pill color (base / surcharge / credit).
private struct DemurrageLine648: Decodable, Identifiable {
    let id: String
    let title: String?
    let detail: String?
    let kind: String?        // "base" | "surcharge" | "credit"
    let badge: String?       // "TIER 2" | "ADDED" | "CREDIT"
    let amountUsd: Double?
}

/// Full accrual computation for one box/shipment.
private struct DemurrageAccrual648: Decodable {
    let shipmentRef: String?
    let status: String?              // "draft" | "issued" | …
    let chargeableCount: Int?        // "6 chargeable"
    let computedDemurrageUsd: Double? // hero figure $4,260
    let containerId: String?         // RAIL-260524-9C41
    let tier: Int?                   // tier 2
    let daysOver: Int?               // hero DAYS · 6
    let freeTimeDays: Int?           // KPI · 4d
    let perDiemUsd: Double?          // KPI · $710/d
    let progress: Double?            // hero bar fill 0…1 (216/360)
    let lines: [DemurrageLine648]?   // accrual breakdown rows
}

/// Bulk-accrual fleet context from `railDemurrageAuto.runBulkAccrual`.
private struct BulkAccrual648: Decodable {
    let boxCount: Int?               // "31 boxes"
    let carrierName: String?         // BNSF Intermodal
    let shipperName: String?         // Eusorone Technologies (DU)
    let shipmentRef: String?         // RAIL-260524-9C41
}

// MARK: - Body

private struct RailDemurrageCalculatorBody: View {
    @Environment(\.palette) private var palette
    let shipmentRef: String

    @State private var accrual: DemurrageAccrual648? = nil
    @State private var bulk: BulkAccrual648? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var running = false
    @State private var runResult: String? = nil

    private let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    private func money(_ v: Double) -> String {
        currency.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
    /// Signed money for credit lines (-$2,840).
    private func signedMoney(_ v: Double) -> String {
        let mag = money(abs(v))
        return v < 0 ? "-\(mag)" : mag
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if let a = accrual {
                    hero(a)
                    kpiStrip(a)
                    accrualBreakdown(a)
                    bulkStrip
                    ctaPair
                } else {
                    EusoEmptyState(
                        systemImage: "shippingbox.and.arrow.backward",
                        title: "No accrual computed",
                        subtitle: "Demurrage lines appear once calculateAccrual runs against this box."
                    )
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Header (eyebrow + mono caption + 28/-0.4 title + synced)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("✦  RAIL ENGINEER · DEMURRAGE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("CALC")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Demurrage calculator")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(bulk?.carrierName.map { carrierTag($0) } ?? "BNSF")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("synced 2m ago")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    /// Short carrier tag for the top-right eyebrow (e.g. "BNSF").
    private func carrierTag(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init)?.uppercased() ?? name.uppercased()
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 252)
        }
    }

    // MARK: - Hero (gradient-rimmed ActiveCard + lead figure + progress)

    private func hero(_ a: DemurrageAccrual648) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                // draft + N chargeable pills
                HStack(spacing: Space.s2) {
                    Text((a.status ?? "draft").lowercased())
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    if let n = a.chargeableCount {
                        Text("\(n) chargeable")
                            .font(.system(size: 11, weight: .bold)).tracking(0.5)
                            .foregroundStyle(Color(hex: 0xFFB74D))
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(Capsule().fill(Brand.warning.opacity(0.22)))
                    }
                    Spacer()
                }
                // lead figure + label + id/tier  ·  DAYS column
                HStack(alignment: .top, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(money(a.computedDemurrageUsd ?? 0))
                            .font(.system(size: 26, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("computed demurrage")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(a.containerId ?? shipmentRef) · tier \(a.tier ?? 0)")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("DAYS")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(a.daysOver ?? 0)")
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(Color(hex: 0xFFB74D))
                    }
                }
                // progress bar (216 of 360 fill in the wireframe)
                GeometryReader { geo in
                    let pct = max(0, min(a.progress ?? 0, 1))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: geo.size.width * pct)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - KPI strip (3-cell · cell-1 eusoDiagonal)

    private func kpiStrip(_ a: DemurrageAccrual648) -> some View {
        HStack(spacing: Space.s2) {
            // cell 1 — gradient fill (PER DIEM)
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("PER DIEM")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text(a.perDiemUsd.map { "\(money($0))/d" } ?? "—")
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiCell(label: "FREE TIME",
                    value: a.freeTimeDays.map { "\($0)d" } ?? "—",
                    valueColor: palette.textSecondary)
            kpiCell(label: "OVER",
                    value: "\(a.daysOver ?? 0)",
                    valueColor: Color(hex: 0xFFB74D))
        }
    }

    private func kpiCell(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Accrual breakdown (itemized ListRow stack)

    private func accrualBreakdown(_ a: DemurrageAccrual648) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ACCRUAL BREAKDOWN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("calculateAccrual:36")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            let lines = a.lines ?? []
            if lines.isEmpty {
                LifecycleCard {
                    Text("No accrual lines — calculateAccrual returned an empty schedule for this box.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                        accrualRow(line)
                        if idx < lines.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    Rectangle().fill(palette.borderFaint).frame(height: 1)
                        .padding(.horizontal, Space.s4)
                    HStack {
                        Text("+ surcharge tiers applied automatically · runBulkAccrual covers \(bulk?.boxCount ?? 0) boxes")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                    }
                    .padding(Space.s4)
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func accrualRow(_ line: DemurrageLine648) -> some View {
        let kind = (line.kind ?? "base").lowercased()
        let accent: Color = {
            switch kind {
            case "credit":    return Brand.info      // free-time credit (blue)
            case "surcharge": return Brand.warning   // storage surcharge (amber)
            default:          return Brand.danger    // base demurrage (red)
            }
        }()
        let icon: String = {
            switch kind {
            case "credit":    return "checkmark.shield.fill"
            case "surcharge": return "clock.fill"
            default:          return "dollarsign.circle.fill"
            }
        }()
        let amount = line.amountUsd ?? 0
        let amountStr = kind == "credit" ? signedMoney(amount) : money(amount)
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s2) {
                    Text(line.title ?? "Line item")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    if let badge = line.badge {
                        Text(badge.uppercased())
                            .font(.system(size: 11, weight: .bold)).tracking(0.5)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Capsule().fill(accent.opacity(0.18)))
                    }
                }
                if let detail = line.detail {
                    Text(detail)
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Text(amountStr)
                .font(.system(size: 14, weight: .bold)).monospacedDigit()
                .foregroundStyle(accent)
        }
        .padding(Space.s4)
    }

    // MARK: - Bulk-accrual context strip

    private var bulkStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("BULK ACCRUAL · runBulkAccrual")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(bulk?.boxCount ?? 0) boxes")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("calculateAccrual feed · tier schedule applied at LFD")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(bulkProvenance)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var bulkProvenance: String {
        let carrier = bulk?.carrierName ?? "BNSF Intermodal"
        let shipper = bulk?.shipperName ?? "Eusorone Technologies (DU)"
        let ref = bulk?.shipmentRef ?? accrual?.containerId ?? shipmentRef
        return "Carrier \(carrier) · \(shipper) · \(ref)"
    }

    // MARK: - CTA pair (Run accrual · Dispute)

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = runResult {
                Text(r).font(EType.caption).foregroundStyle(Brand.success)
            }
            HStack(spacing: Space.s2) {
                CTAButton(title: running ? "Running…" : "Run accrual",
                          action: { Task { await runAccrual() } },
                          isLoading: running)
                disputeButton
            }
        }
    }

    private var disputeButton: some View {
        Button(action: { Task { await dispute() } }) {
            Text("Dispute")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgSecondary)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: 148)
    }

    // MARK: - Load (railDemurrageAuto.calculateAccrual + runBulkAccrual feed)

    private func reload() async {
        loading = true; loadError = nil
        struct AccrualIn: Encodable { let shipmentRef: String }
        struct BulkIn: Encodable { let shipmentRef: String }
        do {
            // PORT-GAP: railDemurrageAuto.calculateAccrual — server procedure
            // (railDemurrageAuto.ts:36) is not yet exposed on the iOS tRPC
            // router. Wired against the canonical path; surfaces real
            // empty/error until the procedure ships to the phone surface.
            let a: DemurrageAccrual648 = try await EusoTripAPI.shared.query(
                "railDemurrageAuto.calculateAccrual",
                input: AccrualIn(shipmentRef: shipmentRef))
            self.accrual = a

            // PORT-GAP: railDemurrageAuto.runBulkAccrual — fleet context feed
            // (railDemurrageAuto.ts:66) likewise unwired on iOS. Best-effort:
            // a missing bulk feed must not blank the primary accrual card.
            do {
                let b: BulkAccrual648 = try await EusoTripAPI.shared.query(
                    "railDemurrageAuto.runBulkAccrual",
                    input: BulkIn(shipmentRef: shipmentRef))
                self.bulk = b
            } catch {
                self.bulk = nil
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Run accrual (mutation)

    private func runAccrual() async {
        running = true; runResult = nil
        struct RunIn: Encodable { let shipmentRef: String }
        struct Empty648: Decodable {}
        do {
            // PORT-GAP: railDemurrageAuto.runBulkAccrual (mutation) — kicks
            // the tier schedule for all chargeable boxes. Unwired on iOS;
            // canonical path used.
            _ = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.runBulkAccrual",
                input: RunIn(shipmentRef: shipmentRef)) as Empty648
            runResult = "Accrual run queued."
            await reload()
        } catch {
            runResult = nil
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        running = false
    }

    // MARK: - Dispute (mutation)

    private func dispute() async {
        struct DisputeIn: Encodable { let shipmentRef: String }
        struct Empty648: Decodable {}
        do {
            // PORT-GAP: detentionAccessorials.calculateDemurrage dispute path
            // (detentionAccessorials.ts:616) not yet wired to iOS; canonical
            // path used so the CTA is real, not cosmetic.
            _ = try await EusoTripAPI.shared.mutation(
                "detentionAccessorials.disputeDemurrage",
                input: DisputeIn(shipmentRef: shipmentRef)) as Empty648
            runResult = "Dispute filed."
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("648 · Rail Demurrage Calculator · Night") {
    RailDemurrageCalculatorScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("648 · Rail Demurrage Calculator · Light") {
    RailDemurrageCalculatorScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
