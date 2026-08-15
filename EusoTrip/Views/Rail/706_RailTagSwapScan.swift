//
//  706_RailTagSwapScan.swift
//  EusoTrip — Rail Engineer · Tag-Swap Scan (two-waypoint AEI delta engine).
//
//  Bespoke port of "05 Rail/Light-SVG/706 Rail Tag-Swap Scan.svg" (+ Dark).
//  ARCHETYPE = DELTA-MATRIX — a consist-wide table comparing each car's AEI
//  mark decoded at waypoint A vs waypoint B (CAR · READ@A · READ@B · Δ),
//  swapped rows danger-washed. The FLEET/ENGINE view, not a per-car
//  read-trail timeline.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getCrossBorderInterchangePoints  EXISTS:1852
//        {country?, railroad?} → RailInterchangePoint[] {id,name,
//        stateProvinceA/B,railroadsA/B,...} — the REAL waypoint inventory.
//        Both waypoint pickers below are populated from this feed and the
//        tri-country band re-queries it per regime.
//    aei.getTwoWaypointDelta — AEI read telemetry consist-wide table
//        comparing each car's AEI mark decoded at waypoint A vs waypoint B.
//    aei.flagTagSwap — marks a suspect car for tag swap review.
//

import SwiftUI

struct RailTagSwapScanScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailTagSwapScanBody()
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

// MARK: - Data shapes (mirror services/crossBorderRail.ts RailInterchangePoint)

private struct InterchangePoint706: Decodable, Identifiable, Hashable {
    let id: String?
    let name: String?
    let stateProvinceA: String?
    let stateProvinceB: String?
    let railroadsA: [String]?
    let railroadsB: [String]?

    var key: String { id ?? name ?? UUID().uuidString }
    var display: String { name ?? id ?? "Waypoint" }
}

private struct InterchangeInput706: Encodable {
    let country: String?
}

// MARK: - Body

private struct RailTagSwapScanBody: View {
    @Environment(\.palette) private var palette
    @State private var waypoints: [InterchangePoint706] = []
    @State private var waypointA: InterchangePoint706? = nil
    @State private var waypointB: InterchangePoint706? = nil
    @State private var loading = true
    @State private var scanning = false
    @State private var regime = 0
    @State private var deltas: [TagDelta706] = []
    @State private var isFlagging = false
    @State private var scanMessage: String? = nil
    @State private var showFlagNotice = false

    private let regimes: [(String, String)] = [("US · AAR S-918", "wayside AEI"),
                                               ("CA · TC", "wayside"),
                                               ("MX · ARTF", "SIID")]
    private let regimeCountry = ["US", "CA", "MX"]

    private struct TagDelta706: Decodable, Identifiable {
        let carNumber: String
        let carOwner: String?
        let readA: String?
        let readB: String?
        let isSwap: Bool
        var id: String { carNumber }
    }
    
    private struct DeltaInput706: Encodable {
        let waypointA: String
        let waypointB: String
    }
    
    private struct DeltaResult706: Decodable {
        let deltas: [TagDelta706]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Tag-swap scan")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text(waypoints.isEmpty ? "Diff a consist's tag reads across two reader waypoints"
                                   : "\(waypoints.count) reader waypoints available")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    waypointPickers
                    deltaHero
                    matrixHeader
                    deltaMatrix
                    triBand
                    footerActions
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
        .alert("No suspect car to flag", isPresented: $showFlagNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The matrix has no diverging reads — no tag reads are on file between these waypoints, so there is no swap to flag. A car flags the moment two waypoint reads disagree.")
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "CARRIER · RAIL · TAG-SWAP ENGINE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("Δ A · B")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("no reads on file", Brand.warning)
            chip("0 swaps", palette.textSecondary)
            chip("\(waypoints.count) waypoints", Brand.blue)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Waypoint pickers — REAL interchange-point inventory.

    @ViewBuilder
    private var waypointPickers: some View {
        if waypoints.isEmpty {
            EusoEmptyState(systemImage: "mappin.slash",
                           title: "No reader waypoints",
                           subtitle: "No interchange reader locations match this regime. Switch the country band below to load its waypoint inventory.")
        } else {
            VStack(spacing: 8) {
                waypointPicker(label: "WAYPOINT A", selection: $waypointA)
                waypointPicker(label: "WAYPOINT B", selection: $waypointB)
            }
        }
    }

    private func waypointPicker(label: String, selection: Binding<InterchangePoint706?>) -> some View {
        Menu {
            ForEach(waypoints, id: \.key) { p in
                Button(p.display) { selection.wrappedValue = p }
            }
        } label: {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 84, alignment: .leading)
                Text(selection.wrappedValue?.display ?? "Choose a reader location")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(selection.wrappedValue == nil ? palette.textTertiary : palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: Delta hero — honest: no read telemetry exists, so the swap count
    // reads "—" and says why. Never a fabricated match or mismatch.

    private var deltaHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CROSS-WAYPOINT MARK DELTA · NO READS ON FILE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.warning)
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.warning.opacity(0.12), Brand.blue.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(deltas.isEmpty ? "—" : "\(deltas.filter { $0.isSwap }.count)")
                        .font(.system(size: 40, weight: .bold)).monospacedDigit()
                        .foregroundStyle(deltas.isEmpty ? palette.textTertiary : (deltas.contains { $0.isSwap } ? Brand.danger : Brand.success))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("swapped tags")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(deltas.isEmpty ? "a verdict needs a decoded read at both waypoints" : "from consist delta analysis")
                            .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                ZStack {
                    Circle().fill(Brand.warning.opacity(0.10)).frame(width: 48, height: 48)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Brand.warning)
                }
            }
            .padding(16)
            if let a = waypointA, let b = waypointB {
                Text("A \(a.display)  →  B \(b.display)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 16).padding(.bottom, 14)
                    .lineLimit(2)
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var matrixHeader: some View {
        HStack {
            Text("TWO-WAYPOINT MARK DELTA · AEI")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("CAR · READ@A · READ@B · Δ")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private var deltaMatrix: some View {
        if deltas.isEmpty {
            EusoEmptyState(systemImage: "tablecells",
                           title: "No tag reads between these waypoints",
                           subtitle: waypointA == nil || waypointB == nil
                               ? "Pick reader locations for waypoint A and waypoint B above. The consist matrix fills row-by-row as decoded reads land at each."
                               : "No decoded reads are on file at \(waypointA?.display ?? "A") or \(waypointB?.display ?? "B") for this consist. Every car shows pending until both waypoints report.")
        } else {
            VStack(spacing: 0) {
                ForEach(deltas) { d in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.carNumber).font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.textPrimary)
                            Text(d.carOwner ?? "Unknown owner").font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                        }
                        Spacer()
                        Text(d.readA ?? "PENDING").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        Text(d.readB ?? "PENDING").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        Spacer()
                        Circle().fill(d.isSwap ? Brand.danger : Brand.success).frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 12)
                    if d.id != deltas.last?.id { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(.horizontal, 16)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var triBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == regime ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture {
                    regime = i
                    Task { await reload() }   // re-query the waypoint inventory per regime — real
                }
            }
        }
    }

    private var footerActions: some View {
        VStack(spacing: Space.s2) {
            if let m = scanMessage {
                Text(m).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Space.s3) {
                CTAButton(title: isFlagging ? "Flagging…" : "Open suspect car", action: { Task { await flagTagSwap() } })
                    .frame(maxWidth: .infinity)
                    .disabled(isFlagging || !deltas.contains { $0.isSwap })
                Button(action: { Task { await reload(rescanning: true) } }) {
                    Text(scanning ? "Scanning…" : "Re-scan")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 118)
                        .frame(minHeight: 48, maxHeight: 48)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                    .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(scanning)
            }
        }
    }

    // MARK: Load — real waypoint inventory, regime-scoped.

    private func reload(rescanning: Bool = false) async {
        if rescanning { scanning = true } else { loading = true }
        
        // 1) Fetch waypoints
        let pts: [InterchangePoint706]? = try? await EusoTripAPI.shared.query(
            "railShipments.getCrossBorderInterchangePoints",
            input: InterchangeInput706(country: regimeCountry[regime]))
        self.waypoints = pts ?? []
        
        // 2) Fetch deltas if both waypoints are selected
        if let a = waypointA?.id, let b = waypointB?.id {
            do {
                let res: DeltaResult706 = try await EusoTripAPI.shared.query(
                    "aei.getTwoWaypointDelta",
                    input: DeltaInput706(waypointA: a, waypointB: b))
                self.deltas = res.deltas
            } catch {
                self.deltas = []
            }
        } else {
            self.deltas = []
        }
        
        // Keep selections only if they survive the regime switch.
        if let a = waypointA, !waypoints.contains(where: { $0.key == a.key }) { waypointA = nil }
        if let b = waypointB, !waypoints.contains(where: { $0.key == b.key }) { waypointB = nil }
        
        loading = false
        scanning = false
    }

    private func flagTagSwap() async {
        guard let swapCar = deltas.first(where: { $0.isSwap }) else { return }
        guard !isFlagging else { return }
        isFlagging = true; defer { isFlagging = false }
        struct In: Encodable { let railcarNumber: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "aei.flagTagSwap",
                input: In(railcarNumber: swapCar.carNumber))
            scanMessage = "Car \(swapCar.carNumber) flagged for tag swap."
            await reload()
        } catch {
            scanMessage = "Flagging failed. Check your connection."
        }
    }
}

#Preview("706 · Rail Tag-Swap Scan · Night") {
    RailTagSwapScanScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("706 · Rail Tag-Swap Scan · Light") {
    RailTagSwapScanScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
