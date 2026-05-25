//
//  563_RailExceptionsHolds.swift
//  EusoTrip — Rail Engineer · Exceptions & Holds (carrier-side ops board).
//
//  Visual identity: danger-wash hero card (red/orange 10% tint) when holds/alerts
//  are active; exceptions grouped by category (BAD ORDERS · FRA ALERTS · DEMURRAGE)
//  with icon-differentiated type chips; severity counter in the hero.
//
//  Data:
//    railShipments.getRailCompliance       (EXISTS :568) → inspections + failedCount
//    railShipments.getFRASafetyCompliance  (EXISTS :720) → FRA violations (best-effort)
//    railShipments.getLiveDemurrage        (EXISTS :759) → demurrage accruals (best-effort)
//    railShipments.getAssetHealth          (EXISTS :692) → Railinc asset health (best-effort)
//

import SwiftUI

struct RailExceptionsHoldsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            RailExceptionsHoldsBody()
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

private struct RailInspection563: Decodable {
    let id: Int?
    let status: String?
    let description: String?
    let railcarNumber: String?
    let location: String?
    let defectCode: String?
    let timestamp: String?
}

private struct RailCompliance563: Decodable {
    let inspections: [RailInspection563]
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?
}

private struct FRAViolation563: Decodable {
    let type: String?
    let description: String?
    let severity: String?
    let reviewDue: String?
}

private struct FRASafety563: Decodable {
    let status: String?
    let violationCount: Int?
    let violations: [FRAViolation563]?
}

private struct LiveDemurrage563: Decodable {
    let totalAmount: Double?
    let daysOver: Int?
    let status: String?
}

private struct AssetHealth563: Decodable {
    let condition: String?
    let status: String?
    let notes: String?
}

// MARK: - Display model

private struct ExceptionItem563: Identifiable {
    let id = UUID()
    let glyph: String
    let tintColor: Color
    let title: String
    let subtitle: String
    let pill: String
    let pillColor: Color
    let detail: String
    let detailIsBold: Bool
}

// MARK: - Body

private struct RailExceptionsHoldsBody: View {
    @Environment(\.palette) private var palette
    @State private var compliance: RailCompliance563? = nil
    @State private var fraSafety: FRASafety563? = nil
    @State private var demurrage: LiveDemurrage563? = nil
    @State private var assetHealth: AssetHealth563? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var holdCount: Int {
        compliance?.failedCount
            ?? compliance?.inspections.filter { $0.status == "out_of_service" || $0.status == "fail" }.count
            ?? 0
    }
    private var alertCount: Int { fraSafety?.violationCount ?? fraSafety?.violations?.count ?? 0 }
    private var totalExceptions: Int { holdCount + alertCount + (demurrageBreach ? 1 : 0) }
    private var demurrageBreach: Bool { (demurrage?.daysOver ?? 0) > 0 }
    private var demurrageAmount: String {
        guard let amt = demurrage?.totalAmount, amt > 0 else { return "—" }
        return "$\(Int(amt.rounded()))"
    }
    private var isCritical: Bool { holdCount > 0 || alertCount > 0 }

    // Grouped exception items
    private var badOrderItems: [ExceptionItem563] {
        (compliance?.inspections ?? []).filter { $0.status == "out_of_service" || $0.status == "fail" }.map { insp in
            ExceptionItem563(
                glyph: "nosign",
                tintColor: Brand.danger,
                title: "Bad-order hold — out of service",
                subtitle: "\(insp.railcarNumber ?? "railcar") · \(insp.defectCode ?? "AAR mech defect")",
                pill: "HOLD",
                pillColor: Brand.danger,
                detail: insp.location ?? "—",
                detailIsBold: false
            )
        }
    }

    private var fraItems: [ExceptionItem563] {
        (fraSafety?.violations ?? []).map { v in
            ExceptionItem563(
                glyph: "exclamationmark.triangle.fill",
                tintColor: Brand.warning,
                title: "FRA exception — \(v.type ?? "safety alert")",
                subtitle: "getFRASafetyCompliance · \(v.description ?? "review pending")",
                pill: "FRA ALERT",
                pillColor: Brand.warning,
                detail: v.reviewDue ?? "—",
                detailIsBold: false
            )
        }
    }

    private var demurrageItems: [ExceptionItem563] {
        guard demurrageBreach, let days = demurrage?.daysOver else { return [] }
        return [ExceptionItem563(
            glyph: "clock.badge.exclamationmark.fill",
            tintColor: Brand.danger,
            title: "Demurrage breach — free time out",
            subtitle: "getLiveDemurrage · \(days) day\(days == 1 ? "" : "s") over · accruing",
            pill: "ACCRUING",
            pillColor: Brand.danger,
            detail: demurrageAmount,
            detailIsBold: true
        )]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading exceptions…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    dangerWashHero
                    kpiStrip
                    if !badOrderItems.isEmpty {
                        exceptionGroup(title: "BAD ORDERS · getRailCompliance", items: badOrderItems)
                    }
                    if !fraItems.isEmpty {
                        exceptionGroup(title: "FRA ALERTS · getFRASafetyCompliance", items: fraItems)
                    }
                    if !demurrageItems.isEmpty {
                        exceptionGroup(title: "DEMURRAGE · getLiveDemurrage", items: demurrageItems)
                    }
                    if !badOrderItems.isEmpty && !fraItems.isEmpty && !demurrageItems.isEmpty {
                        // Only show empty state when ALL buckets are empty
                    } else if totalExceptions == 0 {
                        LifecycleCard {
                            HStack(spacing: Space.s3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 28)).foregroundStyle(Brand.success)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("No active exceptions").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                    Text("Fleet clear · no holds, FRA alerts, or demurrage breaches")
                                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                                }
                            }
                        }
                    }
                    contextStrip
                    actionsRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · EXCEPTIONS & HOLDS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Exceptions & holds")
                    .font(.system(size: 28, weight: .heavy)).kerning(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
                if totalExceptions > 0 {
                    Text("\(totalExceptions) OPEN")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.danger.opacity(0.14)))
                }
            }
            IridescentHairline()
        }
    }

    // MARK: DangerWash hero

    private var dangerWashHero: some View {
        ZStack(alignment: .leading) {
            // Danger-wash background
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(isCritical
                    ? LinearGradient(colors: [Brand.danger.opacity(0.10), Brand.warning.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [palette.bgCard, palette.bgCard], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(isCritical ? Brand.danger.opacity(0.35) : LinearGradient.diagonal as! LinearGradient, lineWidth: 1.5)

            HStack(spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(isCritical ? "CRITICAL" : "ALL CLEAR")
                            .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                            .foregroundStyle(isCritical ? Brand.danger : Brand.success)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill((isCritical ? Brand.danger : Brand.success).opacity(0.14)))
                        Text("composed board")
                            .font(.system(size: 10, weight: .heavy)).kerning(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(palette.textTertiary.opacity(0.10)))
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(totalExceptions)")
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(isCritical ? Brand.danger : Brand.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("open exception\(totalExceptions == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                            Text("\(holdCount) hold · \(alertCount) FRA · \(demurrageBreach ? 1 : 0) demurrage")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer()
                exceptionTypeStack
            }
            .padding(Space.s4)
        }
        .frame(height: 118)
    }

    private var exceptionTypeStack: some View {
        VStack(spacing: 8) {
            exceptionTypePill(icon: "nosign", label: "\(holdCount) HOLD", color: Brand.danger, active: holdCount > 0)
            exceptionTypePill(icon: "exclamationmark.triangle.fill", label: "\(alertCount) FRA", color: Brand.warning, active: alertCount > 0)
            exceptionTypePill(icon: "clock.fill", label: demurrageBreach ? "BREACH" : "0 DMR", color: Brand.danger, active: demurrageBreach)
        }
    }

    private func exceptionTypePill(icon: String, label: String, color: Color, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(active ? color : palette.textTertiary)
            Text(label).font(.system(size: 9, weight: .heavy)).kerning(0.4).foregroundStyle(active ? color : palette.textTertiary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill((active ? color : palette.textTertiary).opacity(active ? 0.14 : 0.08)))
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "OPEN HOLDS",  value: "\(holdCount)",    accent: holdCount > 0 ? Brand.danger : nil)
            MetricTile(label: "FRA ALERTS",  value: "\(alertCount)",   accent: alertCount > 0 ? Brand.warning : nil)
            MetricTile(label: "DEMURRAGE",   value: demurrageAmount,   gradientNumeral: demurrageAmount != "—")
        }
    }

    // MARK: Exception group

    private func exceptionGroup(title: String, items: [ExceptionItem563]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    exceptionRow(item)
                    if idx < items.count - 1 { Divider().padding(.leading, 56) }
                }
            }
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(items.first?.pillColor.opacity(0.20) ?? palette.borderFaint))
        }
    }

    private func exceptionRow(_ item: ExceptionItem563) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.tintColor.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: item.glyph)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(item.tintColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(item.subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(item.pill)
                    .font(.system(size: 10, weight: .bold)).tracking(0.6)
                    .foregroundStyle(item.pillColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(item.pillColor.opacity(0.14)))
                Text(item.detail)
                    .font(.system(size: item.detailIsBold ? 14 : 11,
                                  weight: item.detailIsBold ? .bold : .regular))
                    .monospacedDigit().foregroundStyle(palette.textSecondary)
            }
        }
        .padding(14)
    }

    // MARK: Context strip

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("COMPOSED BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getAssetHealth")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("Holds + FRA + demurrage merged · no single getRailAlerts call")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            if let condition = assetHealth?.condition {
                Text("Asset condition: \(condition.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    // MARK: Actions

    private var actionsRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "View shipment", action: {}, leadingIcon: "list.bullet.rectangle")
            CTAButton(title: "Resolve hold", leadingIcon: "checkmark.circle")
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        struct RailroadIn: Encodable { let railroadCode: String }
        struct DemurrageIn: Encodable { let railroad: String; let equipmentId: String }
        struct AssetIn: Encodable { let railcarNumber: String }
        do {
            let c: RailCompliance563 = try await EusoTripAPI.shared.query(
                "railShipments.getRailCompliance", input: Empty())
            self.compliance = c
            let carNum = c.inspections.first(where: { $0.railcarNumber != nil })?.railcarNumber ?? "DTTX762004"
            async let fra = EusoTripAPI.shared.query(
                "railShipments.getFRASafetyCompliance",
                input: RailroadIn(railroadCode: "BNSF")) as FRASafety563
            async let asset = EusoTripAPI.shared.query(
                "railShipments.getAssetHealth",
                input: AssetIn(railcarNumber: carNum)) as AssetHealth563
            async let dem = EusoTripAPI.shared.query(
                "railShipments.getLiveDemurrage",
                input: DemurrageIn(railroad: "BNSF", equipmentId: carNum)) as LiveDemurrage563
            self.fraSafety   = try? await fra
            self.assetHealth = try? await asset
            self.demurrage   = try? await dem
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("563 · Exceptions & Holds · Night") {
    RailExceptionsHoldsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("563 · Exceptions & Holds · Light") {
    RailExceptionsHoldsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
