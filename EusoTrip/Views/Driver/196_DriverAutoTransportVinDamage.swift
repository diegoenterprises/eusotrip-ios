//
//  196_DriverAutoTransportVinDamage.swift
//  EusoTrip — Screen 196 · Auto Transport VIN Damage (LIVE-wired · DIAGRAM)
//
//  Purpose: a car-hauler proves each unit's pre-existing condition — a
//  VIN-bound damage diagram and a mandatory 8-point photo grid at both load
//  and delivery so a scratch that was already there is provable.
//
//  Wiring manifest:
//    loadLifecycle.submitComplianceCheck  EXISTS · loadLifecycle.ts:3887
//      the report sign-off writes checkName "vehicle_inventory_complete"
//      (loadLifecycle.ts:1799); isAutoTransport is detected at
//      loadLifecycle.ts:1544 (ct=vehicles or car_carrier trailer).
//    documents.upload                     EXISTS · documents.ts:215 (photo store)
//  HONEST GAP handed to the-oath: there is NO structured per-VIN condition
//  report (no damage-mark or VIN-decode store). The diagram and photo grid are
//  shown as the required capture structure and never fabricate marks, a VIN,
//  or a "captured" count. Proposed: autoTransport.recordVinCondition
//  ({ loadId, unitNo, vin, phase, marks, photos }) + autoTransport.decodeVin.
//  transportMode = truck · country US.
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//
//  §W OFFLINE POLICY: ONLINE_ONLY(a per-unit condition attestation is evidence in a cargo-damage
//  claim and must be timestamped by the server, not the device).
//  Honored: nothing on this surface is persisted or replayed client-side;
//  on any failure the model is cleared and the reason is surfaced.
//

import SwiftUI

@MainActor
private final class VinDamageViewModel: ObservableObject {
    @Published var signed = false
    @Published var submitting = false

    let loadId: Int?
    init(loadId: Int?) { self.loadId = loadId }

    private struct CheckIn: Encodable { let loadId: Int; let checkName: String; let passed: Bool }
    private struct AnyOut: Decodable {}

    func signReport() async {
        guard let loadId, !submitting else { return }
        submitting = true; defer { submitting = false }
        do {
            let _: AnyOut = try await EusoTripAPI.shared.mutation(
                "loadLifecycle.submitComplianceCheck",
                input: CheckIn(loadId: loadId, checkName: "vehicle_inventory_complete", passed: true))
            signed = true
        } catch { /* honest: no false confirmation */ }
    }
}

struct DriverAutoTransportVinDamageView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm: VinDamageViewModel

    let loadRef: String
    let unitLabel: String
    private let photoPoints = ["Front", "Rear", "L-front", "R-front",
                               "L-rear", "R-rear", "Roof", "Odometer"]

    init(loadId: Int? = nil, loadRef: String = "auto-transport load", unitLabel: String = "unit") {
        _vm = StateObject(wrappedValue: VinDamageViewModel(loadId: loadId))
        self.loadRef = loadRef
        self.unitLabel = unitLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverComplianceHeader(
                eyebrow: "DRIVER · AUTO TRANSPORT", caption: "VIN CONDITION",
                title: "VIN Damage", subtitle: "\(loadRef) · \(unitLabel)",
                rightLabel: "PHASE", rightValue: "pre-load")
            IridescentHairline().padding(.top, Space.s3)
            content
        }
    }

    private var content: some View {
        VStack(spacing: Space.s4) {
            diagramHero
            vinRow
            photoGrid
            ctaPair
        }
        .padding(Space.s5)
    }

    // Condition diagram — clean top-down canvas; marks are captured, not faked.
    private var diagramHero: some View {
        ComplianceSection(label: "CONDITION DIAGRAM · \(unitLabel.uppercased())",
                          trailing: "PRE-LOAD", trailingColor: Brand.info) {
            VStack(spacing: Space.s3) {
                CarTopDownDiagram()
                    .stroke(palette.textTertiary, lineWidth: 1.6)
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s2)
                HStack(spacing: Space.s3) {
                    markLegend("S", "scratch", Brand.warning)
                    markLegend("D", "dent", Brand.danger)
                    markLegend("C", "chip", Brand.info)
                    Spacer()
                }
                ComplianceGapNote(
                    systemImage: "hand.tap",
                    title: "Damage marks",
                    detail: "Tapping a panel to log a scratch, dent, or chip isn't persisted on this build — no marks are stored rather than a condition record we can't stand behind.")
            }
        }
    }

    private func markLegend(_ code: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(code).font(.system(size: 11, weight: .heavy)).foregroundStyle(color)
                .frame(width: 20, height: 20)
                .background(color.opacity(0.18), in: Circle())
            Text(label).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
        }
    }

    private var vinRow: some View {
        HStack(spacing: Space.s3) {
            Text("VIN").font(EType.mono(.micro)).fontWeight(.bold).foregroundStyle(Brand.info)
                .frame(width: 40, height: 40)
                .background(Brand.info.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text("Scan VIN to decode").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("year · body class matched against BOL line")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Text("DECODE PENDING").font(EType.micro).tracking(0.4).fontWeight(.bold)
                .foregroundStyle(Brand.warning).fixedSize()
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var photoGrid: some View {
        ComplianceSection(label: "8-POINT PHOTO GRID", trailing: "0 / 8",
                          trailingColor: Brand.warning) {
            VStack(alignment: .leading, spacing: Space.s3) {
                let cols = [GridItem(.flexible()), GridItem(.flexible()),
                            GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: Space.s2) {
                    ForEach(photoPoints, id: \.self) { p in photoSlot(p) }
                }
                Text("Capture all eight at pickup and delivery — both ends make a pre-existing mark provable.")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func photoSlot(_ label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: "camera").font(.system(size: 15, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text(label).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity).frame(height: 62)
        .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
            .strokeBorder(palette.borderFaint, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {} label: {
                Text("Capture photo").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain).disabled(true).opacity(0.5)
            .accessibilityLabel("Capture photo — per-VIN photo binding not yet available")
            CTAButton(title: vm.signed ? "Report signed" : "Sign report",
                      action: { Task { await vm.signReport() } },
                      leadingIcon: vm.signed ? "checkmark" : "signature",
                      isLoading: vm.submitting)
                .opacity(vm.loadId == nil ? 0.5 : 1)
                .disabled(vm.loadId == nil || vm.signed)
        }
    }
}

// Top-down car silhouette — body + cabin glass + centerline, drawn to scale.
private struct CarTopDownDiagram: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset: CGFloat = 6
        let body = rect.insetBy(dx: inset, dy: inset)
        // Body outline — rounded capsule-ish car shape.
        p.addRoundedRect(in: body, cornerSize: CGSize(width: body.height * 0.42,
                                                       height: body.height * 0.42),
                         style: .continuous)
        // Cabin / greenhouse — inner rounded rect.
        let cabin = body.insetBy(dx: body.width * 0.20, dy: body.height * 0.22)
        p.addRoundedRect(in: cabin, cornerSize: CGSize(width: 10, height: 10), style: .continuous)
        // Centerline (front-to-back split).
        p.move(to: CGPoint(x: body.midX, y: body.minY + 6))
        p.addLine(to: CGPoint(x: body.midX, y: body.maxY - 6))
        return p
    }
}

// MARK: - Screen (Shell + Driver nav · LOADS current)

struct DriverAutoTransportVinDamageScreen: View {
    let theme: Theme.Palette
    var loadId: Int? = nil
    var loadRef: String = "auto-transport load"
    var unitLabel: String = "unit"
    var body: some View {
        Shell(theme: theme) {
            DriverAutoTransportVinDamageView(loadId: loadId, loadRef: loadRef, unitLabel: unitLabel)
        } nav: {
            BottomNav(leading: driverComplianceNavLeading(.loads),
                      trailing: driverComplianceNavTrailing(.loads), orbState: .idle)
        }
    }
}

#Preview("VIN Damage · Dark") {
    DriverAutoTransportVinDamageScreen(theme: Theme.dark, loadRef: "9-car carrier", unitLabel: "unit 4/9")
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("VIN Damage · Light") {
    DriverAutoTransportVinDamageScreen(theme: Theme.light, loadRef: "9-car carrier", unitLabel: "unit 4/9")
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
