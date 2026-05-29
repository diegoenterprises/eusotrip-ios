//
//  564_RailBorderClearance.swift
//  EusoTrip — Rail Engineer · Border Clearance (carrier-side cross-border).
//
//  Cross-border customs clearance drill-down for an active consist at a named
//  US-MX rail interchange. Faithful port of
//  "05 Rail/Light-SVG/564 Rail Border Clearance.svg" (Light + Dark).
//  Gold-standard grammar: eyebrow → H1 28pt -0.4k → gradient-rim hero →
//  3-KPI strip → checklist rows → required-docs strip → CTA pair.
//
//  Data:
//    railShipments.getRailShipmentDetail           (EXISTS :140) → shipment context
//    railShipments.getCrossBorderInterchangePoints (EXISTS :887) → interchange point
//    railShipments.checkCrossBorderRailCompliance  (EXISTS :903) → regulatory checklist
//    railShipments.getCrossBorderRailDocs          (EXISTS :899) → required documents list
//

import SwiftUI

struct RailBorderClearanceScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int
    let interchangePointId: String
    var body: some View {
        Shell(theme: theme) {
            RailBorderClearanceBody(shipmentId: shipmentId, interchangePointId: interchangePointId)
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

private struct RailYard564: Decodable {
    let id: Int
    let name: String?
    let city: String?
    let state: String?
}

private struct RailShipmentDetail564: Decodable {
    let id: Int
    let shipmentNumber: String?
    let status: String?
    let hazmatClass: String?
    let unNumber: String?
    let numberOfCars: Int?
    let originRailroad: String?
    let waybillNumber: String?
    let originYard: RailYard564?
    let destinationYard: RailYard564?
}

private struct RailInterchangePoint564: Decodable {
    let id: String
    let name: String?
    let countryA: String?
    let countryB: String?
    let stateProvinceA: String?
    let stateProvinceB: String?
    let interchangeType: String?
    let hazmatAllowed: Bool?
    let customsOffice: String?
    let railroadsA: [String]?
    let railroadsB: [String]?
}

private struct ComplianceItem564: Decodable {
    let requirement: String
    let status: String
    let details: String
    let regulation: String
}

private struct CrossBorderCompliance564: Decodable {
    let interchangePoint: String?
    let direction: String?
    let regulatory: [ComplianceItem564]
    let overallCompliant: Bool
}

// MARK: - Body

private struct RailBorderClearanceBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let interchangePointId: String

    @State private var detail: RailShipmentDetail564? = nil
    @State private var interchange: RailInterchangePoint564? = nil
    @State private var compliance: CrossBorderCompliance564? = nil
    @State private var requiredDocs: [String] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private var hasDG: Bool { detail?.hazmatClass != nil }
    private var passCount: Int { compliance?.regulatory.filter { $0.status == "pass" }.count ?? 0 }
    private var failCount: Int { compliance?.regulatory.filter { $0.status == "fail" }.count ?? 0 }
    private var totalCount: Int { compliance?.regulatory.count ?? 0 }

    private var crossingLabel: String {
        guard let p = interchange else { return interchangePointId }
        let stA = p.stateProvinceA ?? (p.countryA ?? "US")
        let stB = p.stateProvinceB ?? (p.countryB ?? "MX")
        let kind = p.interchangeType ?? "crossing"
        return "\(stA) → \(stB) · \(kind)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard {
                        Text("Running border clearance check…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    hero
                    kpiStrip
                    checklistSection
                    if !requiredDocs.isEmpty { docsStrip }
                    actionsRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Image(systemName: "flag.2.crossed")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · BORDER CLEARANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text("Border Clearance")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if let num = detail?.shipmentNumber {
                    Text(num)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if let p = interchange {
                Text("\(p.name ?? interchangePointId) · \(p.customsOffice ?? "CBP/SAT")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            IridescentHairline()
        }
    }

    // MARK: Hero Card

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                let ok = compliance?.overallCompliant ?? false
                Text(ok ? "CLEARED" : "HOLD")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(ok ? Brand.success : Brand.danger)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill((ok ? Brand.success : Brand.danger).opacity(0.14)))
                Text(crossingLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.bgCardSoft))
                Spacer()
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(failCount)")
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(failCount > 0 ? AnyShapeStyle(LinearGradient.expense) : AnyShapeStyle(LinearGradient.diagonal))
                    Text("blocker\(failCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(failCount > 0 ? "holds consist · must resolve" : "requirements met")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if hasDG, let d = detail {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("DG CARS")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        Text("\(d.numberOfCars ?? 1)")
                            .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("\(d.hazmatClass ?? "") · UN\(d.unNumber ?? "—")")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        )
    }

    // MARK: KPI Strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "REQUIREMENTS", value: "\(totalCount)")
            MetricTile(label: "PASSED",       value: "\(passCount)", gradientNumeral: passCount > 0)
            MetricTile(label: "BLOCKERS",     value: "\(failCount)", accent: failCount > 0 ? Brand.danger : nil)
        }
    }

    // MARK: Checklist

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CLEARANCE CHECKLIST · checkCompliance")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(totalCount)").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            LifecycleCard {
                let items = compliance?.regulatory ?? []
                if items.isEmpty {
                    Text("Compliance check pending.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            checkRow(item)
                            if idx < items.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private func checkRow(_ item: ComplianceItem564) -> some View {
        let (glyph, tint, verdict) = verdictStyle(item.status)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: glyph)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.requirement)
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(item.details)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary).lineLimit(2)
                Text(item.regulation)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer()
            Text(verdict)
                .font(.system(size: 10, weight: .bold)).tracking(0.6)
                .foregroundStyle(tint)
        }
        .padding(14)
    }

    private func verdictStyle(_ status: String) -> (String, Color, String) {
        switch status.lowercased() {
        case "pass":    return ("checkmark.circle",      Brand.success, "PASS")
        case "warning": return ("exclamationmark.triangle", Brand.warning, "WARNING")
        default:        return ("xmark.circle",          Brand.danger,  "FAIL")
        }
    }

    // MARK: Required Docs Strip

    private var docsStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("REQUIRED DOCS · \(requiredDocs.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getCrossBorderRailDocs")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            ForEach(Array(requiredDocs.prefix(4).enumerated()), id: \.offset) { _, doc in
                Text("· \(doc)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            if requiredDocs.count > 4 {
                Text("+\(requiredDocs.count - 4) more · SAT / CBP harmonized entry set")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
        )
    }

    // MARK: Actions

    private var actionsRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Re-check clearance", action: { Task { await load() } },
                      leadingIcon: "arrow.clockwise", isLoading: loading)
            CTAButton(title: "Consist", leadingIcon: "tram.fill")
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct PointsIn: Encodable { let country: String; let railroad: String? }
        struct CheckIn: Encodable {
            let direction: String
            let interchangePointId: String
            let hasManifest: Bool
            let hasCrewCerts: Bool
            let hasDangerousGoods: Bool
            let hasDGDocs: Bool
            let hasCustomsDocs: Bool
            let hasInsurance: Bool
        }
        struct DocsIn: Encodable {
            let direction: String; let mode: String
            let hasHazmat: Bool; let hasOversized: Bool
        }
        do {
            let d: RailShipmentDetail564 = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail", input: DetailIn(id: shipmentId))
            self.detail = d

            let points: [RailInterchangePoint564] = try await EusoTripAPI.shared.query(
                "railShipments.getCrossBorderInterchangePoints",
                input: PointsIn(country: "MX", railroad: d.originRailroad))
            let point = points.first(where: { String($0.id) == interchangePointId }) ?? points.first
            self.interchange = point

            let dir = "\(point?.countryA ?? "US")_TO_\(point?.countryB ?? "MX")"
            let isDG = d.hazmatClass != nil

            let result: CrossBorderCompliance564 = try await EusoTripAPI.shared.query(
                "railShipments.checkCrossBorderRailCompliance",
                input: CheckIn(
                    direction: dir,
                    interchangePointId: interchangePointId,
                    hasManifest: d.waybillNumber != nil,
                    hasCrewCerts: true,
                    hasDangerousGoods: isDG,
                    hasDGDocs: isDG,
                    hasCustomsDocs: false,
                    hasInsurance: true
                ))
            self.compliance = result

            do {
                let docs: [String] = try await EusoTripAPI.shared.query(
                    "railShipments.getCrossBorderRailDocs",
                    input: DocsIn(direction: dir, mode: "RAIL", hasHazmat: isDG, hasOversized: false))
                self.requiredDocs = docs
            } catch { /* non-blocking */ }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("564 · Border Clearance · Night") {
    RailBorderClearanceScreen(theme: Theme.dark, shipmentId: 1001, interchangePointId: "9")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("564 · Border Clearance · Light") {
    RailBorderClearanceScreen(theme: Theme.light, shipmentId: 1001, interchangePointId: "9")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
