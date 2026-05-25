//
//  583_RailCrossBorderInterchange.swift
//  EusoTrip — Rail 583 · Cross-Border Interchange
//

import SwiftUI

// MARK: - Outer shell

struct RailCrossBorderInterchangeScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) {
            RailCrossBorderInterchangeBody(railId: railId)
        } nav: {
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

// MARK: - Data shapes

private struct InterchangePoint583: Decodable {
    let cars: Int?
    let carrierFrom: String?
    let carrierTo: String?
    let port: String?
    let direction: String?
    let tradeAgreement: String?
}

private struct CrossingTime583: Decodable {
    let estimatedHours: Double?
}

private struct ComplianceCheck583: Decodable {
    let checkName: String?
    let checkCode: String?
    let detail: String?
    let status: String?
    let category: String?
}

private struct CrewCerts583: Decodable {
    let certified: Bool?
    let reliefCarrier: String?
    let reliefType: String?
    let hazmatBlock: Bool?
    let carCount: Int?
}

private struct RailIdIn583: Encodable { let railId: String }

// MARK: - Body

private struct RailCrossBorderInterchangeBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var interchangePoint: InterchangePoint583? = nil
    @State private var crossingTime: CrossingTime583? = nil
    @State private var complianceChecks: [ComplianceCheck583] = []
    @State private var crewCerts: CrewCerts583? = nil
    @State private var isRunningCheck = false

    // MARK: Derived

    private var carrierLabel: String {
        let from = interchangePoint?.carrierFrom ?? "BNSF"
        let to   = interchangePoint?.carrierTo   ?? "KCSM"
        return "\(from) to \(to)"
    }
    private var tradeAgreementLabel: String {
        (interchangePoint?.tradeAgreement ?? "USMCA") + " OK"
    }
    private var dwellLabel: String {
        guard let h = crossingTime?.estimatedHours else { return "—" }
        return String(format: "%.1fh", h)
    }
    private var portLabel: String {
        guard let p = interchangePoint?.port, let d = interchangePoint?.direction else { return "—" }
        return "\(p) · \(d)"
    }
    private var carCount: Int  { interchangePoint?.cars ?? 0 }
    private var clearedCount: Int {
        complianceChecks.filter { ($0.status ?? "").lowercased() == "cleared" }.count
    }
    private var totalChecks: Int { max(complianceChecks.count, 1) }
    private var checksLabel: String { "\(clearedCount)/\(totalChecks)" }
    private var checksAllClear: Bool {
        !complianceChecks.isEmpty && clearedCount == complianceChecks.count
    }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                headline
                IridescentHairline()
                heroCard
                kpiStrip
                complianceSection
                crewCertsStrip
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task { await loadAll() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · INTERCHANGE")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(railId)
                .font(.system(size: 9, weight: .heavy).monospaced())
                .kerning(0.6)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Border interchange")
                .font(.system(size: 28, weight: .heavy))
                .kerning(-0.4)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: Hero card

    private var heroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                // Top pills
                HStack(spacing: Space.s2) {
                    Text(tradeAgreementLabel)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Brand.success.opacity(0.14)))
                        .foregroundColor(Brand.success)

                    Text(carrierLabel)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                        .foregroundColor(palette.textPrimary)
                }

                // Dwell figure + cars column
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: Space.s2) {
                        Text(dwellLabel)
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("est. crossing dwell")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(palette.textSecondary)
                            Text(portLabel)
                                .font(.system(size: 11))
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CARS")
                            .font(.system(size: 10, weight: .black))
                            .kerning(0.6)
                            .foregroundColor(palette.textTertiary)
                        Text("\(carCount)")
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundColor(palette.textPrimary)
                        Text("in block")
                            .font(.system(size: 11))
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 116)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "CHECKS", value: checksLabel,    accent: checksAllClear ? Brand.success : palette.textPrimary)
            MetricTile(label: "CARS",   value: "\(carCount)")
            MetricTile(label: "DWELL",  value: dwellLabel)
        }
    }

    // MARK: Compliance checks

    private var complianceSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("COMPLIANCE CHECKS")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundColor(palette.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(complianceChecks.enumerated()), id: \.offset) { idx, check in
                    if idx > 0 {
                        Divider()
                            .overlay(Color.black.opacity(0.06))
                            .padding(.horizontal, Space.s4)
                    }
                    complianceRow(check)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func complianceRow(_ check: ComplianceCheck583) -> some View {
        let (chipColor, chipIcon) = checkChipInfo(check)
        let (pillLabel, pillColor) = checkPillInfo(check.status)
        let subText = [check.checkCode, check.detail].compactMap { $0 }.joined(separator: " · ")

        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: chipIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(chipColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(check.checkName ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                if !subText.isEmpty {
                    Text(subText)
                        .font(.system(size: 11).monospaced())
                        .kerning(0.4)
                        .foregroundColor(palette.textSecondary)
                }
            }
            Spacer()
            Text(pillLabel)
                .font(.system(size: 11, weight: .bold))
                .kerning(0.5)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(pillColor.opacity(0.14)))
                .foregroundColor(pillColor)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }

    // MARK: Crew certs strip

    private var crewCertsStrip: some View {
        let certified     = crewCerts?.certified     ?? false
        let reliefCarrier = crewCerts?.reliefCarrier ?? "KCSM"
        let reliefType    = crewCerts?.reliefType    ?? "gateway"
        let hazmat        = crewCerts?.hazmatBlock   ?? false
        let cars          = crewCerts?.carCount      ?? carCount
        let line1 = certified
            ? "interchange crew certified · \(reliefCarrier) relief at \(reliefType)"
            : "crew certification pending"
        let line2 = "est. crossing \(dwellLabel) · \(hazmat ? "hazmat block" : "standard block") · \(cars) cars"

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CREW CERTS")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.8)
                    .foregroundColor(palette.textTertiary)
                Spacer()
            }
            Text(line1)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
            Text(line2)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Run check",
                action: { isRunningCheck = true; Task { await runCheck() } },
                leadingIcon: "plus",
                isLoading: isRunningCheck
            )
            Button("Border docs") {}
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    Capsule()
                        .fill(palette.bgCard)
                        .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
                )
        }
    }

    // MARK: Helpers

    private func checkChipInfo(_ check: ComplianceCheck583) -> (Color, String) {
        let cat    = (check.category ?? "").lowercased()
        let status = (check.status   ?? "").lowercased()
        let color: Color = status == "cleared" ? Brand.success
                         : (status == "failed" ? Brand.danger : Brand.warning)
        return (cat == "dg" || cat == "hazmat")
            ? (color, "exclamationmark.triangle.fill")
            : (color, "doc.badge.checkmark.fill")
    }

    private func checkPillInfo(_ status: String?) -> (String, Color) {
        switch (status ?? "").lowercased() {
        case "cleared": return ("CLEARED", Brand.success)
        case "failed":  return ("FAILED",  Brand.danger)
        case "hold":    return ("HOLD",    Brand.danger)
        case "pending": return ("PENDING", Brand.info)
        default:        return ("—",       Brand.info)
        }
    }

    // MARK: Data loading

    private func loadAll() async {
        async let pointTask: InterchangePoint583 = EusoTripAPI.shared.query(
            "railShipments.getCrossBorderInterchangePoints",
            input: RailIdIn583(railId: railId)
        )
        async let timeTask: CrossingTime583 = EusoTripAPI.shared.query(
            "railShipments.estimateRailBorderCrossingTime",
            input: RailIdIn583(railId: railId)
        )
        async let checksTask: [ComplianceCheck583] = EusoTripAPI.shared.query(
            "railShipments.checkCrossBorderRailCompliance",
            input: RailIdIn583(railId: railId)
        )
        async let certsTask: CrewCerts583 = EusoTripAPI.shared.query(
            "railShipments.getCrossBorderCrewCerts",
            input: RailIdIn583(railId: railId)
        )

        interchangePoint = try? await pointTask
        crossingTime     = try? await timeTask
        complianceChecks = (try? await checksTask) ?? []
        crewCerts        = try? await certsTask
    }

    private func runCheck() async {
        defer { isRunningCheck = false }
        let result: [ComplianceCheck583]? = try? await EusoTripAPI.shared.query(
            "railShipments.checkCrossBorderRailCompliance",
            input: RailIdIn583(railId: railId)
        )
        if let r = result { complianceChecks = r }
    }
}
