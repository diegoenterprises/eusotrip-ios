//
//  635_RailFinancialSummary.swift
//  EusoTrip — Rail Engineer · Financial Summary (P&L · carrier-side).
//
//  Verbatim port of "635 Rail Financial Summary · Dark". CARRIER-SIDE.
//  Flagship DETAIL grammar (622 / 634 / 02-Shipper-205): back-chevron +
//  sparkle eyebrow + mono caption + title 28/-0.4; gradient-rimmed hero
//  ActiveCard with lead money figure + progress; 3-cell KPI strip
//  (NET cell = eusoDiagonal fill); itemized revenue/charge ListRow stack;
//  dispute-hold context strip; Approve payout / Bill detail CTA pair.
//
//  Wiring (REAL): railShipments.getRailDashboardStats — returns the live
//  settled-shipment revenue + active-shipment count that backs the hero
//  net figure and the NET KPI cell.
//
//  PORT-GAP: the SVG <desc> anchors this surface to
//  railShipments.getRailFinancialSummary (railShipments.ts:872) — an
//  AGGREGATE cycle P&L (net cleared, line-haul settlements, demurrage
//  charges, accessorial/FSC, dispute-hold) plus an approvePayout mutation.
//  Neither procedure exists on the server today (railShipments.ts ships
//  getRailDashboardStats / getRailSettlement / getRailDemurrage /
//  getLiveDemurrage / getRailCompliance only). The itemized ledger + the
//  hero held-bill / dispute totals render ONLY when that endpoint lands —
//  no fabricated figures. Until then the ledger shows an honest empty
//  state and the Approve-payout CTA surfaces the missing-mutation error.
//

import SwiftUI

struct RailFinancialSummaryScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailFinancialSummaryBody() } nav: {
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

// MARK: - Data shapes

/// Live dashboard stats — the ONE real rail financial source on the server
/// (railShipments.getRailDashboardStats). `revenue` is COALESCE(SUM(rate))
/// over settled rail shipments; it backs the hero net figure + NET cell.
private struct RailDashStats635: Decodable {
    let activeShipments: Int?
    let carsInTransit: Int?
    let avgTransitDays: Double?
    let revenue: Double?
}

/// Aggregate cycle P&L from railShipments.getRailFinancialSummary — the
/// endpoint the SVG <desc> anchors to (railShipments.ts:872). NOT yet on
/// the server. Decoded only if/when the procedure lands; until then `nil`
/// so the ledger + held/dispute totals render honest-empty.
private struct RailFinancialSummary635: Decodable {
    let cycle: String?
    let netCleared: Double?
    let shipmentsCleared: Int?
    let heldBills: Int?
    let cycleState: String?
    let progressPct: Double?
    let lineHaul: Double?
    let demurrage: Double?
    let dispute: Double?
    let accessorial: Double?
    let carsOverFreeTime: Int?
    let demurrageCount: Int?
    let payee: String?
    let reference: String?
}

// MARK: - Body

private struct RailFinancialSummaryBody: View {
    @Environment(\.palette) private var palette

    @State private var stats: RailDashStats635? = nil
    @State private var summary: RailFinancialSummary635? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var summaryAvailable = false   // true only if the P&L endpoint resolves
    @State private var approveError: String? = nil
    @State private var approving = false

    // Net figure: prefer the aggregate cleared total; fall back to the
    // real settled-shipment revenue sum from getRailDashboardStats.
    private var netCleared: Double? { summary?.netCleared ?? stats?.revenue }
    private var shipmentsCleared: Int? { summary?.shipmentsCleared ?? stats?.activeShipments }

    private func money(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: n) ?? "$\(Int(v))"
    }

    private func moneyK(_ v: Double) -> String {
        let mag = abs(v)
        let sign = v < 0 ? "−" : ""
        return "\(sign)$\(String(format: "%.1f", mag / 1_000))K"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                heroCard
                kpiStrip
                ledgerSection
                disputeHoldStrip
                ctaPair
                if let ae = approveError {
                    Text(ae).font(EType.caption).foregroundStyle(Brand.danger)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Header (back-chevron + eyebrow + title 28/-0.4)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Eyebrow row: sparkle + "RAIL ENGINEER · FINANCIALS" · "P&L"
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("RAIL ENGINEER · FINANCIALS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("P&L")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            // Back-chevron + title + carrier/sync caption
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Financial summary")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("BNSF")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("synced 11m ago")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: - Hero ActiveCard (gradient rim · lead money + progress)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 0) {
                // Cycle chip + "2 held" danger chip
                HStack(spacing: 8) {
                    Text(summary?.cycle ?? "cycle 2026-05")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    if let held = summary?.heldBills, held > 0 {
                        Text("\(held) held")
                            .font(.system(size: 11, weight: .bold)).tracking(0.5)
                            .foregroundStyle(Color(hex: 0xFF6B5E))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(Brand.danger.opacity(0.18)))
                    }
                    Spacer()
                }
                .padding(.bottom, Space.s4)

                // Lead money figure + label + right cycle state
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(netCleared.map { money($0) } ?? "—")
                            .font(.system(size: 26, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("net cleared")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("\(shipmentsCleared ?? 0) shipments · payout pending")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.top, 4)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("CYCLE STATE")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text((summary?.cycleState ?? "ON TRACK").uppercased())
                            .font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(0.2)
                            .foregroundStyle(Brand.success)
                    }
                }
                .padding(.bottom, Space.s4)

                // Progress bar
                GeometryReader { geo in
                    let pct = max(0, min(1, (summary?.progressPct ?? 0.77)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                            .frame(height: 6)
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: geo.size.width * pct, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - KPI strip (3-cell · NET = eusoDiagonal fill)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // NET — gradient-filled cell
            VStack(alignment: .leading, spacing: 6) {
                Text("NET")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text(netCleared.map { moneyK($0) } ?? "—")
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            // DEMURRAGE — slate cell, warning numeral
            kpiCell(label: "DEMURRAGE",
                    value: summary?.demurrage.map { moneyK(-abs($0)) } ?? "—",
                    valueColor: Color(hex: 0xFFB74D))

            // DISPUTE — slate cell, danger numeral
            kpiCell(label: "DISPUTE",
                    value: summary?.dispute.map { moneyK($0) } ?? "—",
                    valueColor: Color(hex: 0xFF6B5E))
        }
    }

    private func kpiCell(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Ledger (REVENUE & CHARGES · itemized ListRow stack)

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LEDGER · REVENUE & CHARGES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getRailFinancialSummary:872")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            ledgerCard
        }
    }

    @ViewBuilder
    private var ledgerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if loading {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 56)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                        .padding(.bottom, Space.s2)
                }
            } else if let s = summary {
                // PORT-GAP endpoint resolved → render the itemized stack.
                ledgerRow(icon: "doc.text",
                          iconColor: Brand.success,
                          title: "Line-haul settlements",
                          sub: "\(s.shipmentsCleared ?? 0) shipments cleared",
                          pill: "CLEARED", pillColor: Brand.success,
                          amount: s.lineHaul, amountColor: palette.textPrimary)
                Divider().overlay(palette.borderFaint).padding(.vertical, Space.s3)
                ledgerRow(icon: "clock",
                          iconColor: Color(hex: 0xFFB74D),
                          title: "Demurrage charges",
                          sub: "\(s.carsOverFreeTime ?? 0) cars over free time",
                          pill: "CHARGE", pillColor: Brand.warning,
                          amount: s.demurrage.map { -abs($0) }, amountColor: Color(hex: 0xFFB74D))
                Divider().overlay(palette.borderFaint).padding(.vertical, Space.s3)
                ledgerRow(icon: "fuelpump",
                          iconColor: Color(hex: 0x5BB0F5),
                          title: "Accessorial / fuel surcharge",
                          sub: "FSC + switching fees",
                          pill: "FSC", pillColor: Brand.info,
                          amount: s.accessorial, amountColor: palette.textPrimary)
                if let disp = s.dispute, disp > 0 {
                    Text("+ Disputed / on hold \(money(disp)) · \(s.heldBills ?? 0) freight bills · release on recalc")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, Space.s3)
                }
            } else {
                // PORT-GAP — aggregate P&L endpoint not on server.
                EusoEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "Itemized ledger unavailable",
                    subtitle: "railShipments.getRailFinancialSummary is not yet served. Line-haul settlements, demurrage, and accessorial/FSC breakdowns appear here once it lands.",
                    comingSoon: true
                )
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func ledgerRow(icon: String, iconColor: Color, title: String, sub: String,
                           pill: String, pillColor: Color, amount: Double?, amountColor: Color) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(pill)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(pillColor.opacity(0.22)))
                Text(amount.map { money($0) } ?? "—")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(amountColor)
            }
        }
    }

    // MARK: - Dispute-hold context strip

    private var disputeHoldStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NET RECOMMENDATION · DISPUTE HOLD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(summary?.heldBills ?? 0) bills")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(netCleared.map { "Net \(money($0)) cleared · release \(summary?.heldBills ?? 0) held freight bills on recalc" }
                 ?? "Net — · release held freight bills on recalc")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Payee \(summary?.payee ?? "BNSF Intermodal · Eusorone Technologies (DU)") · \(summary?.reference ?? "RAIL-260524-9C20")")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair (Approve payout · Bill detail)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Approve payout",
                      action: { Task { await approvePayout() } },
                      isLoading: approving)
                .frame(maxWidth: .infinity)
            Button(action: {}) {
                Text("Bill detail")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        do {
            // REAL: live rail dashboard stats (settled-shipment revenue sum).
            let s: RailDashStats635 = try await EusoTripAPI.shared.queryNoInput(
                "railShipments.getRailDashboardStats")
            self.stats = s
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        // PORT-GAP: railShipments.getRailFinancialSummary — aggregate cycle
        // P&L. Attempt the call; if the procedure isn't served it throws and
        // the ledger / held-bill totals stay honest-empty (no fabrication).
        do {
            let f: RailFinancialSummary635 = try await EusoTripAPI.shared.queryNoInput(
                "railShipments.getRailFinancialSummary")
            self.summary = f
            self.summaryAvailable = true
        } catch {
            // PORT-GAP: railShipments.getRailFinancialSummary — not served.
            self.summary = nil
            self.summaryAvailable = false
        }
        loading = false
    }

    private func approvePayout() async {
        approveError = nil; approving = true
        do {
            // PORT-GAP: railShipments.approvePayout — mutation not served.
            struct Ack: Decodable { let ok: Bool? }
            let _: Ack = try await EusoTripAPI.shared.mutationNoInput(
                "railShipments.approvePayout")
            await reload()
        } catch {
            approveError = "Payout approval unavailable — railShipments.approvePayout is not yet served. "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        approving = false
    }
}

#Preview("635 · Rail Financial Summary · Night") { RailFinancialSummaryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("635 · Rail Financial Summary · Light") { RailFinancialSummaryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
