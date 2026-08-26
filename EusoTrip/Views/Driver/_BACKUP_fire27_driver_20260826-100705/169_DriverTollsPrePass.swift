//
//  169_DriverTollsPrePass.swift
//  EusoTrip — Screen 169 · Driver Tolls & PrePass (LIVE-wired)
//
//  Purpose: show the driver whether their weigh-station/toll transponder
//  is live and how often it green-lights them, plus the FMCSA eligibility
//  that keeps the bypass working — so a pull-in (or a toll account lapse)
//  never surprises them mid-corridor.
//
//  Wiring manifest:
//    driverMobile.getPrePassStatus   EXISTS · routers/driverMobile.ts:1134
//      output { enrolled, provider, transponderStatus, drivewyzeEnrolled,
//               bypassRate, totalBypasses, totalPullIns, recentActivity[],
//               eligibility{ safetyRating, ispScore, csaScore,
//               insuranceCurrent, registrationCurrent } }
//      real source: userIntegrationConnections (prepass/drivewyze) +
//      integrationEventLog bypass.snapshot / bypass.pullin counts.
//  HONEST GAP handed to the-oath: there is NO per-plaza toll-tariff engine
//  on the web peer (no tolls.ts). The trip-toll cost ledger the wireframe
//  sketched is therefore surfaced as an explicit "not yet wired" state —
//  we never fabricate a $ toll total. Proposed: tolls.calculateRoute
//  ({ routePolyline }) → { plazas[], total }.
//  transportMode = truck · country US.
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//

import SwiftUI

// MARK: - Wire model

private struct PrePassEligibility: Decodable {
    let safetyRating: String?
    let ispScore: Int?
    let csaScore: Int?
    let insuranceCurrent: Bool?
    let registrationCurrent: Bool?
}
private struct PrePassStatus: Decodable {
    let enrolled: Bool
    let provider: String?
    let transponderStatus: String
    let drivewyzeEnrolled: Bool
    let bypassRate: Double
    let totalBypasses: Int
    let totalPullIns: Int
    let eligibility: PrePassEligibility
}

// MARK: - ViewModel

@MainActor
private final class TollsPrePassViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, error(String) }
    @Published var phase: Phase = .idle
    @Published var status: PrePassStatus?

    let laneLabel: String
    init(laneLabel: String) { self.laneLabel = laneLabel }

    private struct EmptyIn: Encodable {}

    func load() async {
        phase = .loading
        do {
            let s: PrePassStatus = try await EusoTripAPI.shared.query(
                "driverMobile.getPrePassStatus", input: EmptyIn())
            status = s
            phase = .ready
        } catch {
            phase = .error("Couldn't reach your transponder account.")
        }
    }
}

// MARK: - Screen body

struct TollsPrePassView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm: TollsPrePassViewModel

    init(laneLabel: String = "") {
        _vm = StateObject(wrappedValue: TollsPrePassViewModel(laneLabel: laneLabel))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverUtilityHeader(eyebrow: "DRIVER · TOLLS", caption: "PREPASS",
                                title: "Tolls & PrePass",
                                subtitle: vm.laneLabel.isEmpty ? "transponder account" : vm.laneLabel,
                                rightTop: "MICHAEL EUSORONE · DR-00427",
                                rightBottom: "Eusotrans LLC")
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading: DriverUtilityLoading(text: "Checking transponder…")
            case .error(let m):   DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:          content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
    }

    @ViewBuilder private var content: some View {
        if let s = vm.status {
            VStack(spacing: Space.s4) {
                transponderHero(s)
                bypassStats(s)
                eligibilityCard(s.eligibility)
                tollLedgerGap
                CTAButton(title: "Refresh status", action: { Task { await vm.load() } },
                          leadingIcon: "arrow.clockwise")
            }
            .padding(Space.s5)
        }
    }

    // Hero — transponder state + bypass rate
    private func transponderHero(_ s: PrePassStatus) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("TRANSPONDER").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                StatusPill(text: s.enrolled ? "Active" : "Not enrolled",
                           kind: s.enrolled ? .success : .neutral)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(s.enrolled ? "\(Int(s.bypassRate.rounded()))" : "—")
                    .font(EType.display).foregroundStyle(LinearGradient.diagonal)
                Text(s.enrolled ? "% green-lit" : "no bypass provider")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 6) {
                Image(systemName: s.enrolled ? "checkmark.seal.fill" : "seal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(s.enrolled ? Brand.success : palette.textTertiary)
                Text(s.enrolled
                     ? "\(s.provider ?? "PrePass") transponder live\(s.drivewyzeEnrolled ? " · Drivewyze too" : "")"
                     : "Enroll PrePass or Drivewyze to bypass open scales")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private func bypassStats(_ s: PrePassStatus) -> some View {
        HStack(spacing: Space.s3) {
            MetricTile(label: "Bypasses", value: "\(s.totalBypasses)")
            MetricTile(label: "Pull-ins", value: "\(s.totalPullIns)",
                       accent: s.totalPullIns > 0 ? Brand.warning : nil)
            MetricTile(label: "Green rate", value: s.enrolled ? "\(Int(s.bypassRate.rounded()))%" : "—",
                       gradientNumeral: true)
        }
    }

    private func eligibilityCard(_ e: PrePassEligibility) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("BYPASS ELIGIBILITY").font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            eligRow("Safety rating", (e.safetyRating ?? "—").capitalized,
                    ok: (e.safetyRating ?? "").lowercased() == "satisfactory")
            Divider().overlay(palette.borderFaint)
            eligRow("ISP score", e.ispScore.map { "\($0)" } ?? "—", ok: (e.ispScore ?? 0) >= 75)
            Divider().overlay(palette.borderFaint)
            eligRow("CSA score", e.csaScore.map { "\($0)" } ?? "—", ok: (e.csaScore ?? 100) <= 50)
            Divider().overlay(palette.borderFaint)
            eligRow("Insurance", (e.insuranceCurrent ?? false) ? "Current" : "Review",
                    ok: e.insuranceCurrent ?? false)
            Divider().overlay(palette.borderFaint)
            eligRow("Registration", (e.registrationCurrent ?? false) ? "Current" : "Review",
                    ok: e.registrationCurrent ?? false)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func eligRow(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Text(label).font(EType.body).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value).font(EType.mono(.caption)).fontWeight(.bold)
                .foregroundStyle(ok ? Brand.success : Brand.warning)
        }
        .padding(.vertical, 2)
    }

    // Honest gap: no toll-tariff engine on the web peer
    private var tollLedgerGap: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "road.lanes")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Per-plaza toll estimate")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("Toll-tariff routing isn't connected on this build — no plaza costs are shown rather than an estimate we can't stand behind.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
    }
}

// MARK: - Screen (Shell + Driver nav · ME current)

struct TollsPrePassScreen: View {
    let theme: Theme.Palette
    var laneLabel: String = ""
    var body: some View {
        Shell(theme: theme) {
            TollsPrePassView(laneLabel: laneLabel)
        } nav: {
            BottomNav(leading: driverUtilityNavLeading(),
                      trailing: driverUtilityNavTrailing(meCurrent: true), orbState: .idle)
        }
    }
}

#Preview("Tolls PrePass · Dark") {
    TollsPrePassScreen(theme: Theme.dark, laneLabel: "Los Angeles CA → Phoenix AZ")
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Tolls PrePass · Light") {
    TollsPrePassScreen(theme: Theme.light, laneLabel: "Los Angeles CA → Phoenix AZ")
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
