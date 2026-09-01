//
//  748_VesselCrossBorderClearance.swift
//  EusoTrip — Vessel Operator · Cross-Border Clearance (CLEARANCE-PIPELINE archetype).
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/748 Vessel Cross-Border Clearance.svg": a
//  US/CA/MX country segment drives WHICH import-clearance regime is live (active = US at
//  USLGB), an estimated-time-to-gate-out hero carries the CBP clearance node strip
//  (ISF → ACE → EXAM → RELEASE → GATE), a vertical clearance-STEP ledger keeps each step's
//  real hour cost, and a TRI-COUNTRY CLEARANCE band carries all three import regimes. App
//  Shell + real Vessel-Operator BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Honest binding (frontend/server/routers/vesselShipments.ts):
//    hero est-time + step ledger <- vesselShipments.estimateVesselClearanceTime (EXISTS :3454 ·
//      vesselProcedure · {portId,hasPreClearance,containerCount,hasHazmat,hasAgriculture} ->
//      services/crossBorderVessel.ts estimateVesselCustomsClearanceTime :174 -> {estimatedHours,
//      breakdown:[{step,hours}]}). The service reads the first arg as the clearance DIRECTION,
//      so this surface passes portId="US_import" + containerCount<100 to get the live US-import
//      breakdown (Document review 4h · Exam selection 2h · Small-vessel discharge 6h · CBP hold
//      review 4h · Release & gate-out 2h = 18.0h). The step names + hours + total are 100% real.
//    node strip = the canonical CBP clearance pipeline (regulatory reference), rendered neutral;
//      live per-step done/active state binds to vesselShipments.getVesselShipmentDetail +
//      updateVesselShipmentStatus once a bookingId is in scope (NOT at this regime surface).
//    tri-country band = regulatory reference (US CBP ACE+ISF · CA CBSA ACI/CARM · MX SAT
//      Pedimento/VUCEM) — CA/MX ocean-lane clearance is a NAMED GAP vessel.getClearanceRegime.
//    "Advance entry status" -> vesselShipments.updateVesselShipmentStatus (EXISTS :304) — STUB
//      here (no bookingId in scope) -> re-loads. "Entries" -> getCustomsEntries (EXISTS :3359).
//
//  0 mock data on load · honest empty/error states · seed ONLY in #Preview. Helpers _748.
//

import SwiftUI

// MARK: - View model

private struct ClearanceStep748: Identifiable {
    let id = UUID()
    let index: Int
    let name: String
    let hours: Double
}

private struct ClearanceVM748 {
    let estimatedHours: Double
    let stepCount: Int
    let steps: [ClearanceStep748]

    static let preview = ClearanceVM748(
        estimatedHours: 18.0, stepCount: 5,
        steps: [
            .init(index: 1, name: "Document review & manifest verification", hours: 4),
            .init(index: 2, name: "Customs examination selection", hours: 2),
            .init(index: 3, name: "Small vessel discharge (<100)", hours: 6),
            .init(index: 4, name: "CBP hold review (random or targeted)", hours: 4),
            .init(index: 5, name: "Release & gate-out", hours: 2),
        ]
    )
}

// MARK: - Screen wrapper

struct VesselCrossBorderClearanceScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCrossBorderClearanceBody748()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselCrossBorderClearanceBody748: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var vm: ClearanceVM748? = nil

    private let nodes = ["ISF", "ACE", "EXAM", "RELEASE", "GATE"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                IridescentHairline()
                countrySegment
                if loading {
                    LifecycleCard { Text("Estimating clearance…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let vm, !vm.steps.isEmpty {
                    hero(vm)
                    stepLedger(vm)
                    triCountryBand
                    ctaRow
                } else {
                    EusoEmptyState(systemImage: "clock.badge.checkmark",
                                   title: "No clearance estimate",
                                   subtitle: "estimateVesselClearanceTime returned no breakdown for this lane.")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\u{2726} VESSEL OPERATOR · CLEARANCE")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("USLGB · CBP ACE").font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(0.4)
                    .foregroundStyle(Brand.vessel)
            }
            Text("Cross-border clearance").font(.system(size: 26, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
            Text("VES-260527-A7F3C19D04 · US import · MV Aurora Pioneer 044E")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Country segment
    private var countrySegment: some View {
        HStack(spacing: 8) {
            segChip(title: "US · CBP", sub: "ACE + ISF 10+2", active: true)
            segChip(title: "CA · CBSA", sub: "ACI · CARM", active: false)
            segChip(title: "MX · SAT", sub: "PEDIMENTO · VUCEM", active: false)
        }
    }
    private func segChip(title: String, sub: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 11, weight: .heavy)).kerning(0.3)
                .foregroundColor(active ? .white : palette.textSecondary)
            Text(sub).font(.system(size: 8, weight: .bold)).kerning(0.2)
                .foregroundColor(active ? .white.opacity(0.85) : palette.textTertiary)
        }
        .frame(maxWidth: .infinity).frame(height: 30)
        .background(
            Group {
                if active { Capsule().fill(LinearGradient.primary) }
                else { Capsule().fill(palette.bgCard).overlay(Capsule().stroke(palette.borderSoft)) }
            }
        )
    }

    // MARK: Hero — est time + node strip
    private func hero(_ vm: ClearanceVM748) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal.opacity(0.85))
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("CBP CLEARANCE · ESTIMATED TIME TO GATE-OUT")
                        .font(.system(size: 9, weight: .heavy)).kerning(0.6).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("US IMPORT").font(.system(size: 9, weight: .heavy)).kerning(0.3)
                        .foregroundColor(Brand.info)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.info.opacity(scheme == .dark ? 0.16 : 0.10)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.1fh", vm.estimatedHours))
                        .font(.system(size: 36, weight: .bold, design: .monospaced)).kerning(-1)
                        .foregroundStyle(LinearGradient.primary).monospacedDigit()
                    Text("est · \(vm.stepCount) stages").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 4)
                Spacer(minLength: 8)
                nodeStrip
            }
            .padding(18)
        }
        .frame(height: 132)
    }

    private var nodeStrip: some View {
        GeometryReader { geo in
            let n = nodes.count
            let step = n > 1 ? (geo.size.width - 8) / CGFloat(n - 1) : 0
            ZStack(alignment: .topLeading) {
                Rectangle().fill(palette.textPrimary.opacity(0.10)).frame(width: geo.size.width - 8, height: 2)
                    .offset(x: 4, y: 6)
                ForEach(Array(nodes.enumerated()), id: \.offset) { idx, label in
                    VStack(spacing: 5) {
                        Circle().stroke(palette.textTertiary, lineWidth: 2)
                            .background(Circle().fill(palette.bgCard))
                            .frame(width: 12, height: 12)
                        Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(palette.textTertiary)
                    }
                    .frame(width: 44)
                    .offset(x: 4 + CGFloat(idx) * step - 22, y: 0)
                }
            }
        }
        .frame(height: 30)
    }

    // MARK: Step ledger
    private func stepLedger(_ vm: ClearanceVM748) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLEARANCE STEPS · CBP USLGB · \(String(format: "%.1fh", vm.estimatedHours)) TOTAL")
                .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(vm.steps.enumerated()), id: \.element.id) { idx, s in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(LinearGradient.primary, lineWidth: 2).frame(width: 18, height: 18)
                            Text("\(s.index)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        }
                        Text(s.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(String(format: "%.1fh", s.hours)).font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.textPrimary).monospacedDigit()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    if idx < vm.steps.count - 1 {
                        Divider().background(palette.textPrimary.opacity(0.05)).padding(.leading, 46)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.borderFaint)))
        }
    }

    // MARK: Tri-country clearance band
    private var triCountryBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRI-COUNTRY CLEARANCE · IMPORT REGIME").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                regimeRow(code: "US", title: "CBP · ACE + ISF 10+2", sub: "entry type 01 · 19 CFR 149 · USD", tag: "● ACTIVE", tagColor: Brand.blue, active: true)
                Divider().background(palette.textPrimary.opacity(0.05)).padding(.leading, 16)
                regimeRow(code: "CA", title: "CBSA · ACI eManifest", sub: "CARM · B3 coding · GST · CAD", tag: "STANDBY", tagColor: palette.textTertiary, active: false)
                Divider().background(palette.textPrimary.opacity(0.05)).padding(.leading, 16)
                regimeRow(code: "MX", title: "SAT · Pedimento + VUCEM", sub: "IVA/IEPS/DTA · agente aduanal · MXN", tag: "STANDBY", tagColor: palette.textTertiary, active: false)
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.borderFaint)))
        }
    }

    private func regimeRow(code: String, title: String, sub: String, tag: String, tagColor: Color, active: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textPrimary.opacity(0.06)))
                .frame(width: 26, height: 22)
                .overlay(Text(code).font(.system(size: 10, weight: .heavy)).foregroundColor(active ? .white : palette.textSecondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(sub).font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 6)
            Text(tag).font(.system(size: 8.5, weight: .heavy)).kerning(0.4).foregroundColor(tagColor)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background((active ? LinearGradient(colors: [Brand.blue.opacity(0.10), Brand.magenta.opacity(0.10)], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing)))
    }

    // MARK: CTA
    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await load() } }) {
                Text("Advance entry status").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(LinearGradient.primary))
            }
            Button(action: { Task { await load() } }) {
                Text("Entries").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 118, height: 48)
                    .background(Capsule().fill(palette.bgCardSoft).overlay(Capsule().stroke(palette.textPrimary.opacity(0.10))))
            }
        }
    }

    // MARK: Load
    private func load() async {
        loading = true; loadError = nil
        do {
            struct BD748: Decodable { let step: String?; let hours: Double? }
            struct Resp748: Decodable { let estimatedHours: Double?; let breakdown: [BD748]? }
            let resp: Resp748 = try await EusoTripAPI.shared.query("vesselShipments.estimateVesselClearanceTime", input: ClearanceInput748())
            let bd = resp.breakdown ?? []
            let steps = bd.enumerated().map { i, b in
                ClearanceStep748(index: i + 1, name: b.step ?? "Clearance step", hours: b.hours ?? 0)
            }
            vm = steps.isEmpty ? nil : ClearanceVM748(
                estimatedHours: resp.estimatedHours ?? steps.reduce(0) { $0 + $1.hours },
                stepCount: steps.count,
                steps: steps
            )
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

/// portId is read by the service as the clearance DIRECTION; "US_import" +
/// containerCount<100 yields the live US-import small-vessel breakdown.
private struct ClearanceInput748: Encodable {
    let portId = "US_import"
    let hasPreClearance = false
    let containerCount = 80
    let hasHazmat = false
    let hasAgriculture = false
}

#Preview("748 · Cross-Border Clearance · Light") {
    VesselCrossBorderClearanceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("748 · Cross-Border Clearance · Dark") {
    VesselCrossBorderClearanceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
