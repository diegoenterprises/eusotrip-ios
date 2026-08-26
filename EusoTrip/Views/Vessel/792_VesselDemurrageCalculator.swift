//
//  792_VesselDemurrageCalculator.swift
//  EusoTrip — Vessel Operator · Demurrage Calculator.
//
//  Faithful 1:1 port of "792 Vessel Demurrage Calculator.svg" (Light + Dark), RECONSTRUCTED to a
//  TIER-LADDER calculator archetype — DISTINCT from the detention dashboards (790/793/795/796).
//  Composition mirrors the SVG: a computed-total gradient figure headline, an INPUTS summary card
//  (start/end/free-time/status), a 3-tile strip (ACCRUAL highlighted), and a commercial-terms
//  ladder card with persisted days/rate/subtotal + proportional fill bars + a total row, CTA pair.
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME) —
//  the same Shell + BottomNav wrapper the registered vessel siblings 664/680/757 ship. COMPLIANCE is
//  inked because demurrage/detention is a D&D-compliance surface.
//
//  Data / wiring:
//    vesselShipments.getVesselDemurrage returns the actor's company-scoped vessel_demurrage book.
//    vesselShipments.calculateVesselDemurrage recomputes one selected shipment from its persisted
//      discharge/gate-out event trail and awarded free-time/rate terms, then records the accrual.
//    No truck detention claim, platform rate ladder, implicit departure time, or auto-approval is used.
//
//  0 mock data on load · honest empty/error states — every value renders from decoded response rows.
//  KpiTile792 / LadderTier792 / SecondaryButton792 / EmptyInput792 are file-scoped
//  bespoke helpers (the canonical port's KpiTile/Money/DurFmt/SecondaryButton/ESangRow are not shared
//  app symbols), built from the same grammar the registered siblings use to preserve the wireframe look.
//

import SwiftUI

struct VesselDemurrageCalculatorScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselDemurrageCalculatorBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct LadderTier792: Identifiable {
    let id = UUID()
    let name: String
    let band: String
    let hours: String
    let rate: String
    let subtotal: String
    let frac: Double
    let tone: Color
}

private struct VesselDemurrageCalculatorBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var selectedClaim: VesselDemurrageRow792? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var actionInFlight = false

    @State private var total    = "$0"
    @State private var subline  = "computing billable time over free time…"
    @State private var freeUsed = "120m"
    @State private var billable = "0.0h"
    @State private var estTotal = "$0"
    @State private var tiers: [LadderTier792] = []

    private var arrivalDisplay: String { displayDate792(selectedClaim?.startDate) }
    private var departureDisplay: String { displayDate792(selectedClaim?.endDate) }
    private var activeFreeTimeDays: Int? { selectedClaim?.freeTimeDays }
    private var freeTimeDisplay: String { activeFreeTimeDays.map { "\($0) days" } ?? "unknown" }
    private var statusDisplay: String { selectedClaim?.status?.replacingOccurrences(of: "_", with: " ").uppercased() ?? "UNKNOWN" }
    private var containerLabel: String { selectedClaim?.containerNumber ?? selectedClaim?.bookingNumber ?? "VESSEL D&D" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text(total).font(.system(size: 34, weight: .bold, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Computing…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if selectedClaim == nil {
                    EusoEmptyState(systemImage: "shippingbox.and.arrow.backward",
                                   title: "No recalculable vessel demurrage",
                                   subtitle: "No company-scoped vessel accrual is tied to a shipment in an accruing or disputed state.")
                } else {
                    inputsCard
                    HStack(spacing: 8) {
                        KpiTile792(caption: "FREE USED",  value: freeUsed, footnote: "of \(freeTimeDisplay)", highlighted: false)
                        KpiTile792(caption: "BILLABLE",   value: billable, footnote: "over free", highlighted: false)
                        KpiTile792(caption: "ACCRUAL", value: estTotal, footnote: selectedClaim?.currency ?? "unknown currency", highlighted: true)
                    }
                    Text("COMMERCIAL TERMS · PER CONTAINER · PER DAY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    if tiers.isEmpty {
                        EusoEmptyState(systemImage: "function",
                                       title: "Within free time",
                                       subtitle: "The persisted vessel record has no chargeable day beyond its \(freeTimeDisplay) free window.")
                    } else {
                        ladderCard
                    }
                    HStack(spacing: 8) {
                        CTAButton(title: "Refresh", action: { Task { await load() } }, trailingIcon: "arrow.clockwise")
                        SecondaryButton792(title: actionInFlight ? "Recalculating…" : "Recalculate") { Task { await recalculate() } }
                    }
                    if let error = actionError {
                        LifecycleCard(accentDanger: true) {
                            Text(error).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if let message = actionMessage {
                        LifecycleCard {
                            Text(message).font(EType.caption).foregroundStyle(Brand.success)
                        }
                    }
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PROVENANCE · VESSEL DEMURRAGE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                            Text("Shipment \(selectedClaim?.shipmentId ?? 0) · charge \(selectedClaim?.id ?? 0) · \(statusDisplay.lowercased())")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DEMURRAGE CALC").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(containerLabel).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 6) {
                Text("Compliance").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var inputsCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("INPUTS · persisted vessel accrual").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                HStack(spacing: 0) {
                    field("Arrival",   arrivalDisplay)
                    field("Departure", departureDisplay)
                }
                HStack(spacing: 0) {
                    field("Free time", freeTimeDisplay)
                    field("Status",    statusDisplay)
                }
            }
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text(value).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ladderCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("BASIS").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("DAYS").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text("RATE").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary).frame(width: 52, alignment: .trailing)
                    Text("SUBTOTAL").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary).frame(width: 64, alignment: .trailing)
                }
                Divider().overlay(palette.borderFaint).padding(.vertical, 8)
                ForEach(tiers) { t in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle().fill(t.tone.opacity(0.14)).frame(width: 12, height: 12)
                            Circle().fill(t.tone).frame(width: 6, height: 6)
                        }.padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(t.band).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(palette.bgCardSoft).frame(height: 5)
                                    Capsule().fill(t.tone).frame(width: geo.size.width * t.frac, height: 5)
                                }
                            }.frame(height: 5)
                        }
                        Text(t.hours).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        Text(t.rate).font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.textSecondary).frame(width: 52, alignment: .trailing)
                        Text(t.subtotal).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary).frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 12)
                    Divider().overlay(palette.borderFaint)
                }
                HStack {
                    Text("Total demurrage due").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(total).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                }.padding(.top, 12)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let rows: [VesselDemurrageRow792] = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselDemurrage",
                input: EmptyInput792())
            let row = rows.first { candidate in
                guard (candidate.shipmentId ?? 0) > 0 else { return false }
                return ["accruing", "disputed"].contains((candidate.status ?? "").lowercased())
            }
            guard let row else {
                selectedClaim = nil
                tiers = []
                total = "$0"
                estTotal = "$0"
                billable = "—"
                freeUsed = "—"
                subline = "no recalculable vessel demurrage record"
                loading = false
                return
            }
            selectedClaim = row
            apply(row)
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func apply(_ row: VesselDemurrageRow792) {
        let currency = row.currency
        let amount = row.totalCharge?.value
        let days = row.chargeableDays
        if let amount, let currency, currency.isEmpty == false {
            total = money792(amount, currency: currency)
        } else if let amount {
            total = "\(moneyNumber792(amount)) · currency unknown"
        } else {
            total = "unknown"
        }
        estTotal = total
        billable = days.map { "\($0)d" } ?? "—"
        let dwellDays = persistedDwellDays792(start: row.startDate, end: row.endDate)
        freeUsed = dwellDays.map { "\(min($0, row.freeTimeDays ?? $0))d" } ?? "—"
        subline = [row.bookingNumber, row.portLabel, row.status, currency ?? "currency unavailable"].compactMap { value in
            guard let value, value.isEmpty == false else { return nil }
            return value
        }.joined(separator: " · ")
        if let chargeableDays = days,
           chargeableDays > 0,
           let rate = row.ratePerDay?.value,
           let amount {
            let rateCurrency = currency ?? "currency unknown"
            tiers = [LadderTier792(
                name: "Persisted accrual",
                band: "\(row.containerCount ?? 1) container(s) · awarded terms",
                hours: "\(chargeableDays)d",
                rate: "\(rateCurrency) \(moneyNumber792(rate))/d",
                subtotal: currency.map { money792(amount, currency: $0) } ?? "\(moneyNumber792(amount)) · currency unknown",
                frac: 1,
                tone: row.status == "disputed" ? Brand.warning : Brand.danger
            )]
        } else {
            tiers = []
        }
    }

    private func recalculate() async {
        guard !actionInFlight else { return }
        actionMessage = nil; actionError = nil
        guard let claim = selectedClaim, let shipmentId = claim.shipmentId, shipmentId > 0 else {
            actionError = "Open a vessel demurrage record tied to a shipment before recalculating."
            return
        }
        actionInFlight = true
        do {
            let result: VesselDemurrageCalculation792 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.calculateVesselDemurrage",
                input: VesselShipmentInput792(shipmentId: shipmentId))
            actionMessage = "Accrual recorded from the vessel event trail · \(money792(result.demurrage, currency: result.currency))."
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
        actionInFlight = false
    }
}

// MARK: - Data shapes (mirror vesselShipments.get/calculateVesselDemurrage)

private struct FlexDouble792: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { value = number; return }
        if let text = try? container.decode(String.self), let number = Double(text) { value = number; return }
        throw DecodingError.typeMismatch(Double.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected a decimal number or numeric string"))
    }
}

private struct VesselDemurrageRow792: Decodable, Identifiable {
    let id: Int
    let shipmentId: Int?
    let containerNumber: String?
    let bookingNumber: String?
    let portLabel: String?
    let currency: String?
    let chargeType: String?
    let freeTimeDays: Int?
    let chargeableDays: Int?
    let ratePerDay: FlexDouble792?
    let totalCharge: FlexDouble792?
    let startDate: String?
    let endDate: String?
    let status: String?
    let containerCount: Int?
}

private struct VesselShipmentInput792: Encodable { let shipmentId: Int }

private struct VesselDemurrageCalculation792: Decodable {
    let demurrage: Double
    let currency: String
    let dwellDays: Double
    let freeTimeDays: Int
    let chargeableDays: Int
    let ratePerDay: Double
    let containerCount: Int
}

private struct EmptyInput792: Encodable {}

// MARK: - File-scoped formatters (the canonical port's Money/DurFmt are not shared app symbols)

private func money792(_ amount: Double, currency: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency
    f.maximumFractionDigits = (amount.truncatingRemainder(dividingBy: 1) == 0) ? 0 : 2
    return f.string(from: NSNumber(value: amount)) ?? "\(currency) \(moneyNumber792(amount))"
}

private func moneyNumber792(_ amount: Double) -> String {
    String(format: amount.rounded() == amount ? "%.0f" : "%.2f", amount)
}

private func displayDate792(_ raw: String?) -> String {
    guard let raw, raw.isEmpty == false else { return "unknown" }
    let compact = raw.replacingOccurrences(of: "T", with: " ")
        .replacingOccurrences(of: "Z", with: "")
    if compact.count >= 16 {
        let monthDayStart = compact.index(compact.startIndex, offsetBy: min(5, compact.count))
        let monthDayEnd = compact.index(compact.startIndex, offsetBy: min(16, compact.count))
        return String(compact[monthDayStart..<monthDayEnd])
    }
    return compact
}

private func persistedDwellDays792(start: String?, end: String?) -> Int? {
    guard let start, let end else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let startDate = formatter.date(from: start) ?? ISO8601DateFormatter().date(from: start)
    let endDate = formatter.date(from: end) ?? ISO8601DateFormatter().date(from: end)
    guard let startDate, let endDate, endDate >= startDate else { return nil }
    return Int(ceil(endDate.timeIntervalSince(startDate) / 86_400))
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// KPI tile strip cell — the canonical port's `KpiTile` is not a shared app
/// symbol, so we render the same caption / value / footnote grammar file-scoped.
/// The highlighted tile carries the gradient rim the registered siblings use.
private struct KpiTile792: View {
    @Environment(\.palette) private var palette
    let caption: String
    let value: String
    let footnote: String
    let highlighted: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(highlighted ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
            Text(footnote).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(highlighted ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                              lineWidth: highlighted ? 1.5 : 1)
        )
    }
}

/// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
/// is not a shared app symbol, so we hand-roll the same outline grammar the
/// registered siblings (757) use, on the RoundedRectangle(Radius.md) standard.
private struct SecondaryButton792: View {
    @Environment(\.palette) private var palette
    let title: String
    let action: () -> Void
    init(title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview("792 · Demurrage Calculator · Night") { VesselDemurrageCalculatorScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("792 · Demurrage Calculator · Light") { VesselDemurrageCalculatorScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
