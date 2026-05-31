//
//  619_RailPerDiemTracking.swift
//  EusoTrip — Rail Engineer · Per Diem Tracking (CARRIER-SIDE).
//
//  Verbatim port of "619 Rail Per Diem Tracking · Dark".
//  Carrier-vantage railcar per-diem accrual tracker ($45/car/day over free
//  time) for the BNSF Z-LBCCHI consist. Flagship DETAIL grammar: back
//  chevron + eyebrow + mono caption + title 28/-0.4, gradient-rimmed hero
//  ActiveCard (total-accruing figure + accruing-cars progress + ACCRUING
//  word), 3-cell KPI strip (cell-1 eusoDiagonal), itemized railcar ListRow
//  stack (40x40 railcar icon chip + car title + mono days-over sub + short
//  status pill + right tabular per-diem $), lease per-diem context strip,
//  Dispute-charge / Per-diem-log CTA pair.
//
//  tRPC anchor: railLeaseMgmt.perDiemAccrual (backend EXISTS:58) ·
//  multiModal.getPerDiemTracking (backend EXISTS:1178).
//

import SwiftUI

struct RailPerDiemTrackingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailPerDiemTrackingBody() } nav: {
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

// MARK: - Data shapes (railLeaseMgmt.perDiemAccrual)

private struct PerDiemCar: Decodable, Identifiable {
    let id: String
    let carInitial: String?      // e.g. "BNSU 224517-9"
    let position: String?        // e.g. "well-car 4"
    let daysOver: Double?        // days over free time
    let status: String?          // accruing / over / dispute / settled / paid / waived
    let perDiemDue: Double?      // accrued $ for this car
    let note: String?            // "highest exposure" / "billing disputed" / "returned empty · settled"
    let settled: Bool?
}

private struct PerDiemAccrual: Decodable {
    let totalDue: Double?         // total accruing across the consist
    let carCount: Int?           // accruing cars
    let activeCars: Int?         // total active cars
    let ratePerCarDay: Double?   // $45/car/day
    let avgDaysOver: Double?     // avg 2.4d over
    let consistStatus: String?   // "ACCRUING"
    let leaseRef: String?        // "RAIL-260524-9C20A7E15B"
    let consistId: String?       // "Z-LBCCHI"
    let shipperLabel: String?    // "Eusorone Technologies (DU)"
    let carrier: String?         // "BNSF INTERMODAL"
    let syncedLabel: String?     // "synced 7m ago"
    let cars: [PerDiemCar]?
}

// MARK: - Body

private struct RailPerDiemTrackingBody: View {
    @Environment(\.palette) private var palette
    @State private var accrual: PerDiemAccrual? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var currency: (Double) -> String = { v in
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let n = f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
        return "$\(n)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                IridescentHairline()
                    .padding(.top, Space.s3)

                if loading {
                    loadingState
                        .padding(.top, Space.s5)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.top, Space.s5)
                } else if let a = accrual {
                    heroCard(a)
                        .padding(.top, Space.s5)
                    kpiStrip(a)
                        .padding(.top, Space.s4)
                    railcarsCard(a)
                        .padding(.top, Space.s4)
                    leaseStrip(a)
                        .padding(.top, Space.s4)
                    ctaPair
                        .padding(.top, Space.s5)
                } else {
                    EusoEmptyState(systemImage: "tram.fill",
                                   title: "No per-diem accrual",
                                   subtitle: "Railcar per-diem accrual for this consist will appear here.")
                        .padding(.top, Space.s5)
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · PER DIEM")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("EQUIPMENT")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title block (back chevron + title + carrier + synced)

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)
            Text("Per diem")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text((accrual?.carrier ?? "BNSF INTERMODAL").uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(accrual?.syncedLabel ?? "synced 7m ago")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 2)
        }
        .padding(.top, Space.s4)
    }

    // MARK: - Hero (gradient-rimmed ActiveCard)

    private func heroCard(_ a: PerDiemAccrual) -> some View {
        let totalDue = a.totalDue ?? 0
        let cars = a.carCount ?? a.cars?.count ?? 0
        let rate = a.ratePerCarDay ?? 45
        let avgOver = a.avgDaysOver ?? 0
        let consistStatus = (a.consistStatus ?? "ACCRUING").uppercased()
        // Accruing-cars progress: accruing cars / active cars.
        let active = a.activeCars ?? a.cars?.count ?? max(cars, 1)
        let progress: CGFloat = active > 0 ? CGFloat(cars) / CGFloat(active) : 0

        return ActiveCard {
            VStack(alignment: .leading, spacing: 0) {
                // Chip row: equipment · accruing
                HStack(spacing: Space.s2) {
                    Text("equipment")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    Text("accruing")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color(hex: 0xF5B544))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.warning.opacity(0.22)))
                    Spacer()
                }

                // Figure + sub + right ALL CARS / ACCRUING
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currency(totalDue))
                            .font(.system(size: 30, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("across \(cars) cars")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("$\(Int(rate))/car/day · avg \(String(format: "%.1f", avgOver))d over")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("ALL CARS")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(consistStatus)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .tracking(0.2)
                            .foregroundStyle(Color(hex: 0xF5B544))
                    }
                }
                .padding(.top, Space.s4)

                // Accruing-cars progress
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    GeometryReader { geo in
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(0, geo.size.width * progress), height: 6)
                    }
                    .frame(height: 6)
                }
                .padding(.top, Space.s4)
            }
        }
    }

    // MARK: - KPI strip (3 cells · cell-1 eusoDiagonal)

    private func kpiStrip(_ a: PerDiemAccrual) -> some View {
        let cars = a.carCount ?? a.cars?.count ?? 0
        let avgOver = a.avgDaysOver ?? 0
        let total = a.totalDue ?? 0
        return HStack(spacing: Space.s2) {
            // Cell 1 — eusoDiagonal-filled
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("CARS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(cars)")
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiCell(label: "AVG OVER", value: "\(String(format: "%.1f", avgOver))d")
            kpiCell(label: "TOTAL", value: currency(total))
        }
    }

    private func kpiCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 14).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Railcars · per-diem status

    private func railcarsCard(_ a: PerDiemAccrual) -> some View {
        let cars = a.cars ?? []
        let totalCount = a.carCount ?? cars.count
        // Active (accruing/disputed) rows render in the stack; settled rows
        // collapse into the footer line (per the wireframe's "+ … · settled"
        // overflow row).
        let activeRows = cars.filter { !($0.settled ?? false) }
        let settledRows = cars.filter { $0.settled ?? false }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("RAILCARS · PER-DIEM STATUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(totalCount) cars")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)

            VStack(spacing: 0) {
                if activeRows.isEmpty {
                    EusoEmptyState(systemImage: "tram",
                                   title: "No railcars accruing",
                                   subtitle: "Per-diem railcar status will appear here.")
                        .padding(.vertical, Space.s4)
                } else {
                    ForEach(Array(activeRows.enumerated()), id: \.element.id) { idx, car in
                        railcarRow(car)
                        if idx < activeRows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                        }
                    }
                }

                if let footer = settledFooter(settledRows, total: totalCount) {
                    Rectangle().fill(palette.borderFaint).frame(height: 1)
                    HStack {
                        Text(footer)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, Space.s3)
                }
            }
            .padding(.horizontal, Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func settledFooter(_ settled: [PerDiemCar], total: Int) -> String? {
        guard let first = settled.first else { return nil }
        let initialAndPos = [first.carInitial, first.position]
            .compactMap { $0 }
            .joined(separator: " · ")
        let note = first.note ?? "returned empty · settled"
        return "+ \(initialAndPos) · \(note) · \(total) cars total"
    }

    private func railcarRow(_ car: PerDiemCar) -> some View {
        let tone = rowTone(for: car.status)
        let title: String = {
            let parts = [car.carInitial, car.position].compactMap { $0 }
            return parts.joined(separator: " · ")
        }()
        let sub: String = {
            if let note = car.note, !note.isEmpty {
                return note
            }
            let d = car.daysOver ?? 0
            return "\(String(format: "%g", d))d over free time · accruing"
        }()
        let due = car.perDiemDue ?? 0

        return HStack(alignment: .top, spacing: Space.s3) {
            // 40x40 railcar icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tone.base.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: "tram.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tone.fg)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                Text(tone.label)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(tone.fg)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(tone.base.opacity(tone.pillFillOpacity)))
                Text(currency(due))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.vertical, Space.s3)
    }

    // Status-tone resolver — maps per-diem car status onto the wireframe
    // color language (amber=OVER, red=highest-exposure OVER, blue=DISPUTE).
    private struct RowTone {
        let base: Color
        let fg: Color
        let label: String
        let pillFillOpacity: Double
    }

    private func rowTone(for status: String?) -> RowTone {
        switch (status ?? "over").lowercased() {
        case "dispute", "disputed", "billing disputed":
            return RowTone(base: Brand.info, fg: Color(hex: 0x5BB0F5), label: "DISPUTE", pillFillOpacity: 0.22)
        case "critical", "highest", "highest exposure":
            return RowTone(base: Brand.danger, fg: Color(hex: 0xFF6B6B), label: "OVER", pillFillOpacity: 0.20)
        default:
            return RowTone(base: Brand.warning, fg: Color(hex: 0xF5B544), label: "OVER", pillFillOpacity: 0.24)
        }
    }

    // MARK: - Lease per-diem context strip

    private func leaseStrip(_ a: PerDiemAccrual) -> some View {
        let active = a.activeCars ?? a.cars?.count ?? 0
        let rate = a.ratePerCarDay ?? 45
        let shipper = a.shipperLabel ?? "Eusorone Technologies (DU)"
        let leaseRef = a.leaseRef ?? "RAIL-260524-9C20A7E15B"
        let consist = a.consistId ?? "Z-LBCCHI"
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("LEASE PER-DIEM · ACTIVE CARS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(active) active")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }
            Text("$\(Int(rate)) / car / day · status accruing / paid / disputed / waived")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("\(shipper) · \(leaseRef) · \(consist)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            // Dispute charge — primary gradient (244w in wireframe, ~62%)
            CTAButton(title: "Dispute charge", action: {})
                .frame(maxWidth: .infinity)

            // Per-diem log — secondary glass (148w, ~38%)
            Button(action: {}) {
                Text("Per-diem log")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(hex: 0x232932))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 252)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Load
    //
    // PORT-GAP: railLeaseMgmt.perDiemAccrual — backend procedure CONFIRMED
    // in-repo (search_code, EXISTS:58) but NOT yet surfaced through the
    // Swift EusoTripAPI helper layer. We call it through the generic tRPC
    // query path so the moment the server route is reachable this screen
    // fills with real accrual rows; until then it returns a real empty/error
    // state — never mock data.

    private func reload() async {
        loading = true; loadError = nil
        struct AccrualIn: Encodable { let consistId: String }
        do {
            let a: PerDiemAccrual = try await EusoTripAPI.shared.query(
                "railLeaseMgmt.perDiemAccrual",
                input: AccrualIn(consistId: "Z-LBCCHI"))
            self.accrual = a
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("619 · Rail Per Diem Tracking · Night") { RailPerDiemTrackingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("619 · Rail Per Diem Tracking · Light") { RailPerDiemTrackingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
