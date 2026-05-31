//
//  598_RailEquipmentSpecs.swift
//  EusoTrip — Rail Engineer · Equipment Specs (carrier-side UMLER lookup).
//
//  Verbatim port of "598 Rail Equipment Specs.svg" (Dark).
//  CARRIER-SIDE. Reconstructed to flagship DETAIL grammar per FOUNDER CADENCE
//  DIRECTIVE 2026-05-24: back chevron, eyebrow, mono ID caption, title 28/-0.4,
//  gradient-rimmed hero ActiveCard, 3-cell KPI strip (GROSS · LENGTH · PLATFORM),
//  itemized UMLER spec ListRow stack, ASSET HEALTH secondary strip, CTA pair.
//  Carrier-side UMLER/Railinc equipment lookup for a railcar in the active
//  consist: spec summary, GRL/length/platform KPIs, AAR car-type + mechanical
//  designation rows, asset-health cross-reference, pull-health action.
//  Rail-native; distinct from 575 Equipment Health (condition) and
//  585 Equipment Positions (location).
//  Nav (REAL): HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME.
//
//  Data:
//    railShipments.getEquipmentSpecs  (EXISTS railShipments.ts:747) → UMLER spec rows
//    railShipments.getAssetHealth     (EXISTS railShipments.ts:761) → asset health
//  Both require { railcarNumber: string } and may return null (key unconfigured).
//

import SwiftUI

struct RailEquipmentSpecsScreen: View {
    let theme: Theme.Palette
    /// Railcar this carrier-side UMLER lookup is scoped to. Defaults to the
    /// DTTX 748213 well-car shown in the wireframe; any other stored property
    /// is defaulted so the only required init param is `theme`.
    var railcarNumber: String = "DTTX748213"

    var body: some View {
        Shell(theme: theme) { RailEquipmentSpecsBody(railcarNumber: railcarNumber) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror UMLEREquipmentSpecs / AssetHealthResult)

private struct UMLERDimensions598: Decodable {
    let insideLength: Double?
    let insideWidth: Double?
    let insideHeight: Double?
    let doorWidth: Double?
    let doorHeight: Double?
    let cubicCapacity: Double?
}

private struct UMLERSpecs598: Decodable {
    let railcarNumber: String?
    let carType: String?
    let capacity: Double?
    let tareWeight: Double?
    let loadLimit: Double?
    let owner: String?
    let lessee: String?
    let dimensions: UMLERDimensions598?
    let buildDate: String?
    let aarType: String?
    let plateC: String?
}

private struct MaintenanceAlert598: Decodable, Identifiable {
    let alertId: String?
    let severity: String?
    let description: String?
    let dueDate: String?
    let component: String?
    var id: String { alertId ?? UUID().uuidString }
}

private struct ComponentStatus598: Decodable, Identifiable {
    let component: String?
    let condition: String?
    let lastInspectionDate: String?
    let notes: String?
    var id: String { component ?? UUID().uuidString }
}

private struct AssetHealth598: Decodable {
    let railcarNumber: String?
    let overallCondition: String?
    let mechanicalCondition: String?
    let maintenanceAlerts: [MaintenanceAlert598]?
    let componentStatus: [ComponentStatus598]?
    let lastInspectionDate: String?
    let nextInspectionDue: String?
}

// MARK: - Body

private struct RailEquipmentSpecsBody: View {
    let railcarNumber: String

    @Environment(\.palette) private var palette

    @State private var specs: UMLERSpecs598? = nil
    @State private var health: AssetHealth598? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var pulling = false

    // The canonical rail ID for this carrier-side equipment lookup.
    private let railRefId = "RAIL-260523-7C3A0B12D4"

    // MARK: Derived labels (fall back to representative shapes from the SVG
    // only as the empty-string placeholder — NEVER fabricated numerics; if a
    // field is absent we show an em-dash.)

    private var reportingMark: String {
        // "DTTX 748213" — Railinc returns the bare car number; format with a
        // space after the 4-char reporting mark when long enough.
        let raw = specs?.railcarNumber ?? railcarNumber
        if raw.count > 4 {
            let idx = raw.index(raw.startIndex, offsetBy: 4)
            return "\(raw[raw.startIndex..<idx]) \(raw[idx...])"
        }
        return raw
    }

    /// Gross rail load, derived from loadLimit + tareWeight when present
    /// (UMLER GRL). Rendered as the "286k" hero numeral.
    private var grossRailLoad: Double? {
        if let ll = specs?.loadLimit, let tw = specs?.tareWeight { return ll + tw }
        return specs?.loadLimit
    }
    private var grossLabel: String {
        guard let g = grossRailLoad else { return "—" }
        return g >= 1000 ? "\(Int((g / 1000).rounded()))k" : "\(Int(g.rounded()))"
    }

    /// Well-car length (ft) — from inside length when present.
    private var lengthLabel: String {
        guard let l = specs?.dimensions?.insideLength else { return "—" }
        return "\(Int(l.rounded())) ft"
    }

    /// Platform count — UMLER plate/car-type carries the unit count for
    /// articulated well cars; absent → em-dash.
    private var platformLabel: String {
        if let p = specs?.plateC, !p.isEmpty { return p }
        return "—"
    }

    private var carTypeChip: String {
        guard let t = specs?.carType, !t.isEmpty else { return "well-car" }
        return t
    }
    private var aarTypeLetter: String { specs?.aarType ?? "—" }

    private var mechHealthy: Bool {
        let c = (health?.overallCondition ?? health?.mechanicalCondition ?? "").uppercased()
        return c == "GOOD" || c == "FAIR" || c.contains("SERVICE")
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading equipment specs…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if specs == nil && health == nil {
                    EusoEmptyState(systemImage: "tram",
                                   title: "No equipment record",
                                   subtitle: "UMLER specs for this railcar will appear here.")
                } else {
                    heroCard
                    kpiStrip
                    umlerCard
                    assetHealthStrip
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header (eyebrow · mono ID · back chevron · title 28/-0.4)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("✦ RAIL ENGINEER · EQUIP SPECS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(railRefId)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Equipment")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 10)
            IridescentHairline()
                .padding(.top, 14)
        }
    }

    // MARK: - Hero (gradient-rimmed ActiveCard: IN CONSIST · TTX well-car · 286k GRL · 53 ft)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("IN CONSIST")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Color(hex: 0x5B9BFF))
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.blue.opacity(0.12)))
                Text(carTypeChip)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(grossLabel)
                            .font(.system(size: 34, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("lb gross rail load")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text("per UMLER")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("LENGTH")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(lengthLabel)
                        .font(.system(size: 22, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("well")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(Space.s5)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - KPI strip (3-cell: GROSS · LENGTH · PLATFORM)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            specKPITile("GROSS",    value: grossLabel,    isGradient: true)
            specKPITile("LENGTH",   value: lengthLabel,   isGradient: false)
            specKPITile("PLATFORM", value: platformLabel, isGradient: false)
        }
    }

    @ViewBuilder
    private func specKPITile(_ label: String, value: String, isGradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if isGradient {
                Text(value)
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Text(value)
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    // MARK: - UMLER specs card (itemized rows)

    private var umlerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("UMLER SPECS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("RAILINC")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                specRow(
                    icon: "rectangle.split.3x1.fill",
                    iconTint: Brand.info,
                    title: "AAR car type · \(aarTypeLetter)",
                    sub: "double-stack intermodal",
                    pillText: "TYPE \(aarTypeLetter)",
                    pillTint: nil,
                    trailing: aarTypeLetter,
                    trailingColor: palette.textPrimary
                )
                rowDivider
                specRow(
                    icon: "rectangle.split.3x1.fill",
                    iconTint: Brand.info,
                    title: "Gross rail load",
                    sub: "loaded double-stack",
                    pillText: "GRL",
                    pillTint: nil,
                    trailing: grossLabel,
                    trailingColor: palette.textPrimary
                )
                rowDivider
                specRow(
                    icon: "gauge.with.needle.fill",
                    iconTint: Brand.success,
                    title: "Mechanical designation",
                    sub: "mech-design · in-service",
                    pillText: mechHealthy ? "OK" : "CHECK",
                    pillTint: mechHealthy ? Brand.success : Brand.warning,
                    trailing: nil,
                    trailingColor: palette.textPrimary
                )
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.horizontal, 16)
            .overlay(palette.borderFaint)
    }

    @ViewBuilder
    private func specRow(icon: String, iconTint: Color, title: String, sub: String,
                         pillText: String, pillTint: Color?, trailing: String?,
                         trailingColor: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconTint.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let tint = pillTint {
                    Text(pillText)
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(tint.opacity(0.14)))
                } else {
                    Text(pillText)
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(trailingColor)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Asset health secondary strip

    private var assetHealthStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ASSET HEALTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("AAR-1")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, 10)
            Text(wheelsetLine)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.textSecondary)
            Text(lastInspectionLine)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    private var wheelsetLine: String {
        if let mech = health?.mechanicalCondition, !mech.isEmpty {
            return mech
        }
        return mechHealthy ? "Wheelset + bearing temps in spec" : "Mechanical condition pending"
    }
    private var lastInspectionLine: String {
        guard let raw = health?.lastInspectionDate, !raw.isEmpty else {
            return "Last AAR Rule 1 inspection · —"
        }
        return "Last AAR Rule 1 inspection · \(relativeDays(raw))"
    }

    private func relativeDays(_ iso: String) -> String {
        let date: Date? = ISO8601DateFormatter().date(from: iso) ?? {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: iso)
        }()
        guard let d = date else { return iso }
        let days = Int((Date().timeIntervalSince(d) / 86400).rounded())
        if days <= 0 { return "today" }
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }

    // MARK: - CTA pair (Pull asset health · UMLER)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Pull asset health",
                      action: { Task { await pullHealth() } },
                      trailingIcon: "arrow.right",
                      isLoading: pulling)
            Button {} label: {
                Text("UMLER")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(Color(hex: 0x232932))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct CarIn: Encodable { let railcarNumber: String }
        do {
            // Both endpoints return the record OR `null` when the
            // RAILINC_API_KEY is unconfigured / no record exists. Decoding
            // into an OPTIONAL lets a `null` body resolve to `nil` (→ empty
            // state) while a real transport/auth failure still throws and
            // surfaces as `loadError`.
            async let s = EusoTripAPI.shared.query(
                "railShipments.getEquipmentSpecs",
                input: CarIn(railcarNumber: railcarNumber)) as UMLERSpecs598?
            async let h = EusoTripAPI.shared.query(
                "railShipments.getAssetHealth",
                input: CarIn(railcarNumber: railcarNumber)) as AssetHealth598?
            let (sp, he) = try await (s, h)
            self.specs  = sp
            self.health = he
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func pullHealth() async {
        pulling = true
        struct CarIn: Encodable { let railcarNumber: String }
        do {
            let h = try await EusoTripAPI.shared.query(
                "railShipments.getAssetHealth",
                input: CarIn(railcarNumber: railcarNumber)) as AssetHealth598?
            if let h { self.health = h }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        pulling = false
    }
}

#Preview("598 · Rail Equipment Specs · Night") {
    RailEquipmentSpecsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("598 · Rail Equipment Specs · Light") {
    RailEquipmentSpecsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
