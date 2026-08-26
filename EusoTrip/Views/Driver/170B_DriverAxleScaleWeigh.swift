//
//  170B_DriverAxleScaleWeigh.swift
//  EusoTrip — Screen 170B · Driver Axle Scale Weigh (LIVE-wired)
//
//  Bespoke AXLE-SCALE archetype: the driver has just pulled onto a CAT
//  scale after loading. This screen reads each axle group against its
//  federal limit on one diagram and tells the driver the exact tandem
//  slide to make BEFORE rolling — so an overweight ticket ($100–$16,000+)
//  and a re-load are prevented at the scale, not downstream.
//
//  Wiring manifest (every path confirmed on-disk this fire):
//    escorts.calculateAxleWeights          EXISTS · routers/escorts.ts:2766
//        input  { totalWeight, axleCount }
//        output { compliant, steerAxle, driveAxle, trailerAxle, gvw,
//                 violations[], bridgeFormulaMax, recommendation }
//        engine services/oversizeEnforcement.ts:351 (FEDERAL_LIMITS:
//        single 20,000 · tandem 34,000 · GVW 80,000 · Bridge Formula B)
//    telemetry.scales.listWeighs           EXISTS · routers/telemetry/scales.ts:104
//    telemetry.scales.recordWeigh          EXISTS · routers/telemetry/scales.ts:44
//        (mounted routers.ts:2238 mergeRouters telemetry+telemetryFeeds)
//  Honest gaps handed to the-oath:
//    · recordWeigh persists a telemetry_events row but does NOT yet insert
//      a blockchainAuditTrail row or broadcast WS_EVENTS.WEIGH_RECORDED.
//    · The per-hole slide math (≈ 5 holes fwd) is a display heuristic over
//      the engine's `recommendation`; no dedicated slide-solver endpoint.
//  transportMode = truck · country US (49 CFR 658.17). CA (NSC/SPIF kg) +
//  MX (NOM-012-SCT) axle tables are a COUNTRY-DONE gap on cross-border lanes.
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//
//  §W OFFLINE POLICY: ONLINE_ONLY(the axle split is computed server-side by the oversize engine
//  and a weigh record is a 49 CFR 658.17 artifact; neither may be
//  extrapolated on-device nor replayed from a queue).
//  Honored: nothing on this surface is persisted or replayed client-side;
//  on any failure the model is cleared and the reason is surfaced.
//

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Wire models

private struct AxleWeightResult: Decodable {
    let compliant: Bool
    let steerAxle: Double
    let driveAxle: Double
    let trailerAxle: Double
    let gvw: Double
    let violations: [String]
    let bridgeFormulaMax: Double
    let recommendation: String
}

private struct WeighRow: Decodable, Identifiable {
    let id: String
    let axle: String
    let gross: Double
    let lat: Double?
    let lng: Double?
    let stationId: String?
    let capturedAt: String?
}
private struct WeighList: Decodable { let weighs: [WeighRow] }

// MARK: - Federal limits (49 CFR 658.17 · FEDERAL_LIMITS)

private enum FedLimit {
    static let steer:  Double = 20_000
    static let tandem: Double = 34_000
    static let gvw:    Double = 80_000
}

// MARK: - ViewModel

@MainActor
private final class AxleScaleViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, awaitingScale, error(String) }

    @Published var phase: Phase = .idle
    @Published var result: AxleWeightResult?
    @Published var lastWeigh: WeighRow?
    @Published var recording = false
    @Published var toast: String?

    let loadId: Int?
    let loadLabel: String
    let laneLabel: String
    let equipmentLabel: String
    let totalWeight: Double?
    let axleCount: Int

    init(loadId: Int?, loadLabel: String, laneLabel: String,
         equipmentLabel: String, totalWeight: Double?, axleCount: Int) {
        self.loadId = loadId
        self.loadLabel = loadLabel
        self.laneLabel = laneLabel
        self.equipmentLabel = equipmentLabel
        self.totalWeight = totalWeight
        self.axleCount = axleCount
    }

    private struct AxleIn: Encodable { let totalWeight: Double; let axleCount: Int }
    private struct WeighIn: Encodable { let loadId: Int; let limit: Int }
    private struct RecordIn: Encodable {
        let loadId: Int; let axle: String; let gross: Double
        let lat: Double; let lng: Double; let stationId: String?
        let capturedAt: String
    }
    // Tolerant: we only care that the mutation didn't throw — decode any object.
    private struct RecordOut: Decodable {}

    func load() async {
        phase = .loading
        // The legal verdict is the real engine output for THIS load's weight.
        guard let totalWeight, totalWeight > 0 else {
            // No gross on file yet — honest empty state, never a frozen number.
            await refreshWeighs()
            phase = .awaitingScale
            return
        }
        do {
            let r: AxleWeightResult = try await EusoTripAPI.shared.query(
                "escorts.calculateAxleWeights",
                input: AxleIn(totalWeight: totalWeight, axleCount: axleCount))
            result = r
            await refreshWeighs()
            phase = .ready
        } catch {
            phase = .error("Axle engine unreachable — rough estimate (degraded).")
        }
    }

    func refreshWeighs() async {
        guard let loadId else { return }
        do {
            let list: WeighList = try await EusoTripAPI.shared.query(
                "telemetry.scales.listWeighs", input: WeighIn(loadId: loadId, limit: 10))
            lastWeigh = list.weighs.first(where: { $0.axle == "gross" }) ?? list.weighs.first
        } catch { /* keep prior */ }
    }

    /// Record the gross weigh with the phone's GPS fix at the moment of the weigh.
    func recordWeigh() async {
        guard let loadId, let totalWeight, totalWeight > 0 else {
            toast = "No gross reading to record yet."
            return
        }
        recording = true
        defer { recording = false }
        let location = await DriverLocationResolver.shared.currentLocation()
        guard let location,
              let coordinate = LatLongParser.validatedCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ) else {
            toast = "Location is unavailable, so the weigh was not recorded. Enable Location Services or move to a place with GPS reception, then try again."
            return
        }
        do {
            let _: RecordOut = try await EusoTripAPI.shared.mutation(
                "telemetry.scales.recordWeigh",
                input: RecordIn(loadId: loadId, axle: "gross", gross: totalWeight,
                                lat: coordinate.latitude, lng: coordinate.longitude,
                                stationId: nil,
                                capturedAt: ISO8601DateFormatter().string(from: location.timestamp)))
            toast = "Weigh recorded to the load."
            await refreshWeighs()
        } catch {
            toast = "Couldn't record the weigh. Try again."
        }
    }

    // Derived legal facts ----------------------------------------------------
    var steer: Double { result?.steerAxle ?? 0 }
    var drive: Double { result?.driveAxle ?? 0 }
    var trailer: Double { result?.trailerAxle ?? 0 }

    /// Scale-derived gross, or nil when the axle engine has not answered.
    ///
    /// This previously fell back to `totalWeight` — the SHIPPER'S STATED
    /// weight off the load record, a paper number that was then painted under
    /// the headings "ON THE SCALE" and "CAT SCALE · CERTIFIED PLATFORM" as if
    /// it had been read off the platform, and rendered "GROSS 0 lb · LEGAL" in
    /// green when that was absent too. An unanswered engine is now nil and the
    /// verdict renders as unavailable rather than as a legal clearance.
    var gross: Double? { result?.gvw }

    /// The SERVER's compliance verdict. The previous expression
    /// `gross <= gvw && (compliant ?? false || gross <= gvw)` is tautologically
    /// equal to `gross <= gvw`, so the engine's own `compliant` field was dead
    /// and "LEGAL" was decided purely by client arithmetic against a hardcoded
    /// 80,000. Nil (no verdict) is neither legal nor over — callers must
    /// render the unavailable state, not a color.
    var grossLegal: Bool? {
        guard let r = result else { return nil }
        return r.compliant
    }
    var recommendation: String { result?.recommendation ?? "" }
}

// MARK: - Screen body

struct AxleScaleWeighView: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: AxleScaleViewModel

    init(loadId: Int? = nil,
         loadLabel: String = "",
         laneLabel: String = "",
         equipmentLabel: String = "",
         totalWeight: Double? = nil,
         axleCount: Int = 5) {
        _vm = StateObject(wrappedValue: AxleScaleViewModel(
            loadId: loadId, loadLabel: loadLabel, laneLabel: laneLabel,
            equipmentLabel: equipmentLabel, totalWeight: totalWeight, axleCount: axleCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading:
                loadingState
            default:
                cards
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
        .overlay(alignment: .bottom) { toastBar }
    }

    // MARK: TopBar
    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                EusoTripEyebrow(verbatim: "DRIVER · SCALE & AXLE WEIGHTS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("49 CFR 658.17")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                backChip
                VStack(alignment: .leading, spacing: 3) {
                    Text("Axle scale")
                        .font(EType.h1)
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.loadLabel.isEmpty ? "no load bound" : vm.loadLabel)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("GVW 80,000 LB · FED LIMIT")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(vm.equipmentLabel.isEmpty ? "flatbed" : vm.equipmentLabel)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    /// Back affordance. This was a bare `Image` styled to look exactly like
    /// the tappable 40pt back chips on 167/168 — a visible, chevron-shaped
    /// control with no action at all. It is now a real Button: it pops the
    /// Driver Me stack (`.eusoDriverMeNavBack`, owned by `DriverMeSurface`)
    /// and also calls `dismiss()` so it works in a sheet/push context.
    private var backChip: some View {
        Button {
            NotificationCenter.default.post(name: .eusoDriverMeNavBack, object: nil)
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            ProgressView().tint(palette.textPrimary)
            Text("Reading axle distribution…")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: Cards
    private var cards: some View {
        VStack(spacing: Space.s4) {
            heroDiagram
            legalGaugeCard
            if !vm.recommendation.isEmpty { coachCard }
            weighRecordCard
            ctaPair
        }
        .padding(Space.s5)
    }

    // MARK: Hero — rig on the scale
    private var heroDiagram: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ON THE SCALE")
                    .font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(grossVerdictText)
                    .font(EType.mono(.caption)).fontWeight(.bold)
                    // No server verdict = no color. Green/red here is a legal
                    // clearance; it is never painted from an absent value.
                    .foregroundStyle(vm.grossLegal == nil
                                     ? palette.textTertiary
                                     : (vm.grossLegal == true ? Brand.success : Brand.danger))
            }
            AxleDiagram(steer: vm.steer, drive: vm.drive, trailer: vm.trailer,
                        awaiting: vm.phase == .awaitingScale || vm.result == nil)
                .frame(height: 176)
            HStack(spacing: 6) {
                Image(systemName: "scalemass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                // The platform is not verified by anything on this screen
                // (recordWeigh sends stationId: nil), so it is described as
                // the driver's action, not asserted as a certified platform.
                Text("WEIGH ON A CERTIFIED PLATFORM")
                    .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var grossVerdictText: String {
        if vm.phase == .awaitingScale { return "AWAITING SCALE" }
        // Absent engine answer: say so. Never print a gross figure sourced
        // from the shipper's paperwork, and never print a legal verdict the
        // server did not return.
        guard let g = vm.gross, let legal = vm.grossLegal else {
            return "GROSS UNAVAILABLE"
        }
        return "GROSS \(Int(g.rounded()).grouped) lb · \(legal ? "LEGAL" : "OVER")"
    }

    // MARK: Legal gauge card
    private var legalGaugeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AXLE GROUP · LEGAL CHECK")
                    .font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("BRIDGE FORMULA B")
                    .font(EType.micro).tracking(0.4).foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)
            axleGaugeRow("Steer axle", detail: "single · 20,000 lb limit",
                         value: vm.steer, limit: FedLimit.steer)
            Divider().overlay(palette.borderFaint).padding(.vertical, Space.s3)
            axleGaugeRow("Drive tandem", detail: "tandem · 34,000 lb limit",
                         value: vm.drive, limit: FedLimit.tandem)
            Divider().overlay(palette.borderFaint).padding(.vertical, Space.s3)
            axleGaugeRow("Trailer tandem", detail: "tandem · 34,000 lb limit",
                         value: vm.trailer, limit: FedLimit.tandem)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func axleGaugeRow(_ title: String, detail: String,
                              value: Double, limit: Double) -> some View {
        let awaiting = vm.phase == .awaitingScale || value <= 0
        let over = value > limit
        let delta = abs(value - limit)
        let frac = limit > 0 ? min(max(value / limit, 0), 1) : 0
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: over ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(awaiting ? palette.textTertiary : (over ? Brand.danger : Brand.success))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(detail).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(awaiting ? "— lb" : "\(Int(value.rounded()).grouped) lb")
                        .font(EType.mono(.body)).fontWeight(.bold)
                        .foregroundStyle(awaiting ? palette.textTertiary : (over ? Brand.danger : palette.textPrimary))
                    if !awaiting {
                        Text(over ? "\(Int(delta.rounded()).grouped) OVER" : "\(Int(delta.rounded()).grouped) under")
                            .font(EType.micro).fontWeight(.bold)
                            .foregroundStyle(over ? Brand.danger : Brand.success)
                    }
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint)
                    Capsule()
                        .fill(awaiting ? AnyShapeStyle(palette.borderSoft)
                              : (over ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(Brand.success)))
                        .frame(width: max(geo.size.width * frac, awaiting ? 0 : 6))
                }
            }
            .frame(height: 5)
        }
    }

    // MARK: ESANG scale coach
    private var coachCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                    Text("E").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                }
                Text("ESANG").font(EType.micro).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("· SCALE COACH").font(EType.micro).tracking(0.8).foregroundStyle(Brand.info)
                Spacer()
            }
            Text(vm.grossLegal == true
                 ? "Distribution is within legal limits"
                 : "Rebalance before you roll")
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text(vm.recommendation)
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    // MARK: Weigh record
    private var weighRecordCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("WEIGH RECORD")
                    .font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                if vm.lastWeigh != nil {
                    StatusPill(text: "Captured", kind: .success)
                } else {
                    StatusPill(text: "Awaiting scale", kind: .neutral)
                }
            }
            if let w = vm.lastWeigh {
                HStack(alignment: .top) {
                    metaCol("GROSS", "\(Int(w.gross.rounded()).grouped) lb")
                    Spacer()
                    metaCol("GPS", coordinateLabel(latitude: w.lat, longitude: w.lng))
                }
                HStack(alignment: .top) {
                    metaCol("TIME", shortTime(w.capturedAt))
                    Spacer()
                    // The recording party is stamped server-side on the
                    // telemetry_events row; `telemetry.scales.listWeighs` does
                    // not return it. Attributing the weigh to a hardcoded name
                    // put one fabricated person's signature on every driver's
                    // 49 CFR 658.17 record — show the honest unknown instead.
                    metaCol("BY", "—")
                }
            } else {
                Text("No weigh captured for this load yet. Pull onto a CAT scale and tap Record weigh.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func metaCol(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
        }
    }

    private func coordinateLabel(latitude: Double?, longitude: Double?) -> String {
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: latitude,
            longitude: longitude
        ) else { return "Not recorded" }
        return LatLongParser.displayString(coordinate)
    }

    // MARK: CTA pair
    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: vm.recording ? "Recording…" : "Record weigh",
                      action: { Task { await vm.recordWeigh() } },
                      leadingIcon: "square.and.arrow.down",
                      isLoading: vm.recording)
            Button { Task { await vm.load() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Re-weigh")
                }
                .font(EType.title).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var toastBar: some View {
        if let t = vm.toast {
            Text(t)
                .font(EType.caption).foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                .background(palette.bgSheet, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.borderSoft))
                .padding(.bottom, Space.s6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    withAnimation { vm.toast = nil }
                }
        }
    }

    private func shortTime(_ iso: String?) -> String {
        guard let iso, iso.count >= 16 else { return "—" }
        return String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

// MARK: - Axle diagram (bespoke vector)

private struct AxleDiagram: View {
    let steer: Double
    let drive: Double
    let trailer: Double
    let awaiting: Bool
    @Environment(\.palette) var palette

    private func chip(_ value: Double, limit: Double) -> (String, Color) {
        if awaiting || value <= 0 { return ("—", palette.textTertiary) }
        let over = value > limit
        return ("\(Int(value.rounded()).grouped)", over ? Brand.danger : Brand.success)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let deckY: CGFloat = 150
            let s = chip(steer, limit: FedLimit.steer)
            let d = chip(drive, limit: FedLimit.tandem)
            let t = chip(trailer, limit: FedLimit.tandem)
            ZStack {
                // scale deck
                RoundedRectangle(cornerRadius: 2)
                    .fill(palette.bgCardSoft)
                    .frame(width: w, height: 11)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(palette.borderFaint))
                    .position(x: w / 2, y: deckY)
                // rig silhouette
                RigSilhouette()
                    .fill(LinearGradient.diagonal)
                    .frame(width: w * 0.9, height: 60)
                    .position(x: w / 2, y: deckY - 40)
                // wheels
                ForEach(wheelXs(w), id: \.self) { x in
                    Circle().fill(Color(hex: 0x0E1116))
                        .overlay(Circle().strokeBorder(palette.borderSoft))
                        .frame(width: 22, height: 22)
                        .position(x: x, y: deckY - 4)
                }
                // callout chips
                calloutChip(s, at: CGPoint(x: w * 0.16, y: deckY - 96), tag: "STEER")
                calloutChip(d, at: CGPoint(x: w * 0.40, y: deckY - 108), tag: "DRIVE")
                calloutChip(t, at: CGPoint(x: w * 0.80, y: deckY - 96), tag: "TRAILER")
            }
        }
    }

    private func wheelXs(_ w: CGFloat) -> [CGFloat] {
        [0.16, 0.36, 0.44, 0.76, 0.84].map { $0 * w }
    }

    private func calloutChip(_ chip: (String, Color), at p: CGPoint, tag: String) -> some View {
        VStack(spacing: 3) {
            Text(chip.0)
                .font(EType.mono(.caption)).fontWeight(.bold)
                .foregroundStyle(chip.1)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(chip.1.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(chip.1.opacity(0.45)))
            Text(tag).font(.system(size: 8, weight: .bold)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
        .position(p)
    }
}

private struct RigSilhouette: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let h = r.height, w = r.width
        // cab
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + h * 0.35))
        p.addLine(to: CGPoint(x: r.minX + w * 0.06, y: r.minY + h * 0.05))
        p.addLine(to: CGPoint(x: r.minX + w * 0.16, y: r.minY + h * 0.05))
        p.addLine(to: CGPoint(x: r.minX + w * 0.18, y: r.minY + h * 0.35))
        // deck
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.35))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Grouped-number helper

private extension Int {
    var grouped: String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: self)) ?? String(self)
    }
}

// MARK: - Screen (Shell + Driver nav · TRIPS current)

private func axleNavLeading() -> [NavSlot] {
    [ NavSlot(label: "Home",  systemImage: "house", isCurrent: false),
      NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: true) ]
}
private func axleNavTrailing() -> [NavSlot] {
    [ NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
      NavSlot(label: "Me",    systemImage: "person", isCurrent: false) ]
}

struct AxleScaleWeighScreen: View {
    let theme: Theme.Palette
    var loadId: Int? = nil
    var loadLabel: String = ""
    var laneLabel: String = ""
    var equipmentLabel: String = ""
    var totalWeight: Double? = nil
    var axleCount: Int = 5

    var body: some View {
        Shell(theme: theme) {
            AxleScaleWeighView(loadId: loadId, loadLabel: loadLabel, laneLabel: laneLabel,
                               equipmentLabel: equipmentLabel, totalWeight: totalWeight,
                               axleCount: axleCount)
        } nav: {
            BottomNav(leading: axleNavLeading(), trailing: axleNavTrailing(), orbState: .idle)
        }
    }
}

// MARK: - Previews

#Preview("Axle Scale · Dark") {
    AxleScaleWeighScreen(theme: Theme.dark,
                         loadId: 50, loadLabel: "LD-260426-A5F78115",
                         laneLabel: "Pittsburgh PA → Cleveland OH",
                         equipmentLabel: "48′ flatbed · steel coils",
                         totalWeight: 79_400, axleCount: 5)
        .preferredColorScheme(.dark)
        .environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Axle Scale · Light") {
    AxleScaleWeighScreen(theme: Theme.light,
                         loadId: 50, loadLabel: "LD-260426-A5F78115",
                         laneLabel: "Pittsburgh PA → Cleveland OH",
                         equipmentLabel: "48′ flatbed · steel coils",
                         totalWeight: 79_400, axleCount: 5)
        .preferredColorScheme(.light)
        .environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
