//
//  194_DriverLivestock28HourLaw.swift
//  EusoTrip — Screen 194 · Livestock 28-Hour Law (LIVE-wired · TIMER archetype)
//
//  Purpose: keep a live-cattle hauler ahead of the federal 28-hour confinement
//  deadline (49 USC 80502) — surface the statutory limit, the driver's real
//  drive clock, and one-tap certified feed/water/rest logging so an FWR stop
//  is timestamped into the compliance record before the clock runs out.
//
//  Wiring manifest:
//    hos.getCurrentStatus                 EXISTS · hos.ts:179
//      → the driver's real drive window (limits.driving.remaining, min).
//    loadLifecycle.submitComplianceCheck  EXISTS · loadLifecycle.ts:3887
//      input { loadId, checkName, passed, notes?, photoBase64? } — the FWR
//      log writes checkName "livestock_28hr_plan" (a recognized cargo guard,
//      loadLifecycle.ts:867) into the load's compliance record.
//  HONEST GAP handed to the-oath: there is NO live 28-hour confinement timer
//  or certified-yard directory on the web peer. The statutory limit is shown
//  as the real legal framework (not a fabricated countdown), the driver's HOS
//  drive clock is the one live number, and "find yard" is surfaced as an
//  explicit gap. Proposed: livestock.getConfinementClock({ loadId }) →
//  { confinedMinutes, minutesToStop } and livestock.findRestYards.
//  transportMode = truck · country US (49 USC 80502 · NCBA density).
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//

import SwiftUI

@MainActor
private final class LivestockViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, error(String) }
    @Published var phase: Phase = .idle
    @Published var driveRemainingMin: Int?
    @Published var canDrive: Bool?
    @Published var hosEvidenceMessage: String?
    @Published var fwrLogged = false
    @Published var submitting = false

    let loadId: Int?
    init(loadId: Int?) { self.loadId = loadId }

    private struct CheckIn: Encodable {
        let loadId: Int; let checkName: String; let passed: Bool; let notes: String
    }
    private struct AnyOut: Decodable {}

    func load() async {
        phase = .loading
        do {
            let hos = try await EusoTripAPI.shared.hos.getCurrentStatus()
            if hos.hasCurrentObservation(),
               let remaining = hos.limits.driving.remaining,
               remaining >= 0 {
                driveRemainingMin = remaining
                canDrive = hos.canDrive
                hosEvidenceMessage = nil
            } else {
                driveRemainingMin = nil
                canDrive = nil
                hosEvidenceMessage = hos.assignmentEligibility().reason
                    ?? "Current HOS evidence is unavailable."
            }
            phase = .ready
        } catch {
            driveRemainingMin = nil
            canDrive = nil
            hosEvidenceMessage = "Current HOS evidence could not refresh."
            phase = .error("Couldn't reach your hours-of-service feed.")
        }
    }

    func logFwrStop() async {
        guard let loadId, !submitting else { return }
        submitting = true; defer { submitting = false }
        do {
            let _: AnyOut = try await EusoTripAPI.shared.mutation(
                "loadLifecycle.submitComplianceCheck",
                input: CheckIn(loadId: loadId, checkName: "livestock_28hr_plan",
                               passed: true, notes: "Feed/water/rest stop certified from driver app"))
            fwrLogged = true
        } catch { /* keep UI honest — no false confirmation */ }
    }
}

struct DriverLivestock28HourLawView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm: LivestockViewModel

    let loadRef: String
    let headCount: String

    init(loadId: Int? = nil, loadRef: String = "active load", headCount: String = "livestock") {
        _vm = StateObject(wrappedValue: LivestockViewModel(loadId: loadId))
        self.loadRef = loadRef
        self.headCount = headCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverComplianceHeader(
                eyebrow: "DRIVER · LIVESTOCK · 28-HR LAW", caption: "49 USC 80502",
                title: "28-Hour Clock", subtitle: "\(loadRef) · \(headCount)",
                rightLabel: "DRIVE LEFT", rightValue: driveClock)
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading: DriverUtilityLoading(text: "Checking your clock…")
            case .error(let m):   DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:          content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: Space.s4) {
            lawHero
            fwrStepper
            trailerCondition
            esangCard
            ctaPair
        }
        .padding(Space.s5)
    }

    // Hero — the statutory 28h framework + the real HOS drive clock.
    private var lawHero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("CONFINEMENT LIMIT · 49 USC 80502").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                StatusPill(text: "Statutory", kind: .hazmat)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("28h 00m").font(EType.display).foregroundStyle(LinearGradient.diagonal)
                Text("max before feed · water · rest")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(palette.borderFaint)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR DRIVE CLOCK · HOS").font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(driveClock).font(EType.mono(.body)).fontWeight(.bold)
                        .foregroundStyle(vm.driveRemainingMin.map { $0 < 90 } == true ? Brand.warning : palette.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("CAN DRIVE").font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(canDriveLabel).font(EType.mono(.micro))
                        .foregroundStyle(vm.canDrive == true ? Brand.success : vm.canDrive == false ? Brand.warning : palette.textTertiary)
                }
            }
            if let message = vm.hosEvidenceMessage {
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ComplianceGapNote(
                systemImage: "timer",
                title: "Live confinement countdown",
                detail: "The per-load 28-hour countdown starts when the animals are confined — that clock isn't wired on this build, so the statutory limit is shown as your framework and every FWR stop below is timestamped into the record.")
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var canDriveLabel: String {
        switch vm.canDrive {
        case true: return "CURRENT · PERMITTED"
        case false: return "CURRENT · HELD"
        case nil: return "EVIDENCE UNAVAILABLE"
        }
    }

    // FWR self-certification stepper.
    private var fwrStepper: some View {
        ComplianceSection(label: "FEED · WATER · REST CERTIFICATION",
                          trailing: vm.fwrLogged ? "LOGGED" : "SELF-CERT",
                          trailingColor: vm.fwrLogged ? Brand.success : Brand.warning) {
            HStack(spacing: 0) {
                fwrNode("Feed", done: vm.fwrLogged, first: true)
                fwrConnector(done: vm.fwrLogged)
                fwrNode("Water", done: vm.fwrLogged)
                fwrConnector(done: false)
                fwrNode("Rest", done: false, last: true, pending: true)
            }
        }
    }

    private func fwrNode(_ label: String, done: Bool, first: Bool = false,
                         last: Bool = false, pending: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? AnyShapeStyle(Brand.success)
                          : AnyShapeStyle(pending ? Brand.warning.opacity(0.18) : palette.bgCardSoft))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(done ? Color.clear : palette.borderSoft))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else if pending {
                    Circle().fill(Brand.warning).frame(width: 8, height: 8)
                }
            }
            Text(label).font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
    private func fwrConnector(done: Bool) -> some View {
        Rectangle().fill(done ? Brand.success.opacity(0.4) : palette.borderFaint)
            .frame(height: 3).offset(y: -10)
    }

    // Trailer condition — NCBA/49 CFR framework, self-attested.
    private var trailerCondition: some View {
        ComplianceSection(label: "LIVESTOCK TRAILER · SELF-ATTESTED") {
            VStack(spacing: Space.s3) {
                ComplianceGateRow(systemImage: "square.stack.3d.up",
                                  tint: Brand.success, title: "Bedding depth",
                                  subtitle: "deep · dry — adequate for ambient", status: "attest")
                Divider().overlay(palette.borderFaint)
                ComplianceGateRow(systemImage: "wind", tint: Brand.success,
                                  title: "Side ventilation",
                                  subtitle: "all vents open · none blocked", status: "attest")
                Divider().overlay(palette.borderFaint)
                ComplianceGateRow(systemImage: "chart.bar", tint: Brand.success,
                                  title: "Stocking density",
                                  subtitle: "within NCBA sqft/cwt ceiling", status: "attest")
                Divider().overlay(palette.borderFaint)
                ComplianceGateRow(systemImage: "thermometer.medium", tint: Brand.info,
                                  title: "Ambient / heat index",
                                  subtitle: "monitor for heat-stress flag", status: "watch",
                                  statusColor: Brand.info)
            }
        }
    }

    private var esangCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG AI · LIVESTOCK PLAN").font(EType.micro).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Log every feed/water/rest stop before 28 hours — a certified stop resets the confinement clock and is your defense on an animal-welfare audit.")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: vm.fwrLogged ? "FWR logged" : "Log FWR stop",
                      action: { Task { await vm.logFwrStop() } },
                      leadingIcon: vm.fwrLogged ? "checkmark" : "drop.fill",
                      isLoading: vm.submitting)
                .opacity(vm.loadId == nil ? 0.5 : 1)
                .disabled(vm.loadId == nil || vm.fwrLogged)
            Button {} label: {
                Text("Find yard").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain).disabled(true).opacity(0.5)
            .accessibilityLabel("Find rest yard — not yet available")
        }
    }

    private var driveClock: String {
        guard let m = vm.driveRemainingMin, m > 0 else { return "—" }
        return "\(m / 60)h \(m % 60)m"
    }
}

// MARK: - Screen (Shell + Driver nav · LOADS current)

struct DriverLivestock28HourLawScreen: View {
    let theme: Theme.Palette
    var loadId: Int? = nil
    var loadRef: String = "active load"
    var headCount: String = "livestock"
    var body: some View {
        Shell(theme: theme) {
            DriverLivestock28HourLawView(loadId: loadId, loadRef: loadRef, headCount: headCount)
        } nav: {
            BottomNav(leading: driverComplianceNavLeading(.loads),
                      trailing: driverComplianceNavTrailing(.loads), orbState: .idle)
        }
    }
}

#Preview("Livestock 28-Hour · Dark") {
    DriverLivestock28HourLawScreen(theme: Theme.dark, loadRef: "cattle pot", headCount: "142 head")
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Livestock 28-Hour · Light") {
    DriverLivestock28HourLawScreen(theme: Theme.light, loadRef: "cattle pot", headCount: "142 head")
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
