//
//  173_DriverClearinghouseStatus.swift
//  EusoTrip — Screen 173 · Driver Clearinghouse Status (LIVE-wired)
//
//  Purpose: give the driver a single, honest read on their FMCSA Drug &
//  Alcohol program standing — random-testing rates, annual query coverage,
//  and this-year test results — so nothing about their safety-sensitive
//  status is a surprise at hire or roadside.
//
//  Wiring manifest:
//    drugTesting.getComplianceStatus  EXISTS · routers/drugTesting.ts:375
//      output { overall, randomTesting{ drugRate{required,actual,compliant},
//               alcoholRate{...} }, clearinghouse{ annualQueriesRequired,
//               annualQueriesCompleted, preEmploymentPending, compliant },
//               testingMetrics{ totalTestsYTD, negativeResults,
//               positiveResults, refusals } }  (real drug_tests aggregates)
//  HONEST GAP handed to the-oath: the live FMCSA Clearinghouse query feed is
//  env-gated behind CLEARINGHOUSE_API_KEY (services/clearinghouse.ts) — until
//  a provider is configured the platform persists UNKNOWN / NOT_ENROLLED,
//  never a fabricated CLEAR. This screen therefore reports the driver's
//  program compliance (real), and surfaces the individual query-result +
//  return-to-duty detail as pending the live feed (never faked). Proposed:
//  clearinghouse.getDriverStatus({ driverId }) driver-scoped consent/RTD.
//  transportMode = truck · country US (49 CFR Part 382).
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//

import SwiftUI

// MARK: - Wire models

private struct Rate: Decodable { let required: Double; let actual: Double; let compliant: Bool }
private struct RandomTesting: Decodable { let drugRate: Rate; let alcoholRate: Rate }
private struct ClearinghouseBlock: Decodable {
    let annualQueriesRequired: Int
    let annualQueriesCompleted: Int
    let preEmploymentPending: Int
    let compliant: Bool
}
private struct TestingMetrics: Decodable {
    let totalTestsYTD: Int
    let negativeResults: Int
    let positiveResults: Int
    let refusals: Int
}
private struct DAComplianceStatus: Decodable {
    let overall: String
    let randomTesting: RandomTesting
    let clearinghouse: ClearinghouseBlock
    let testingMetrics: TestingMetrics
}

// MARK: - ViewModel

@MainActor
private final class ClearinghouseViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, error(String) }
    @Published var phase: Phase = .idle
    @Published var status: DAComplianceStatus?

    func load() async {
        phase = .loading
        do {
            let s: DAComplianceStatus = try await EusoTripAPI.shared
                .queryNoInput("drugTesting.getComplianceStatus")
            status = s
            phase = .ready
        } catch {
            phase = .error("Couldn't reach the Clearinghouse status feed.")
        }
    }
}

// MARK: - Screen body

struct ClearinghouseStatusView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm = ClearinghouseViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverUtilityHeader(eyebrow: "DRIVER · CLEARINGHOUSE", caption: "FMCSA",
                                title: "Clearinghouse",
                                subtitle: "drug & alcohol program",
                                rightTop: "MICHAEL EUSORONE · DR-00427",
                                rightBottom: "Eusotrans LLC")
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading: DriverUtilityLoading(text: "Checking your D&A standing…")
            case .error(let m):   DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:          content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
    }

    @ViewBuilder private var content: some View {
        if let s = vm.status {
            VStack(spacing: Space.s4) {
                statusHero(s)
                metrics(s.testingMetrics)
                checksCard(s)
                feedNote
                CTAButton(title: "Refresh status", action: { Task { await vm.load() } },
                          leadingIcon: "arrow.clockwise")
            }
            .padding(Space.s5)
        }
    }

    private func statusHero(_ s: DAComplianceStatus) -> some View {
        let clear = s.overall.lowercased() == "compliant"
        let unknown = s.overall.lowercased() == "unknown"
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("PROGRAM STATUS").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                StatusPill(text: unknown ? "Unknown" : (clear ? "Clear" : "Review"),
                           kind: unknown ? .neutral : (clear ? .success : .warning))
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(unknown ? "—" : (clear ? "Clear" : "Review"))
                    .font(EType.display).foregroundStyle(LinearGradient.diagonal)
                Text(s.testingMetrics.positiveResults == 0 ? "no positives YTD"
                     : "\(s.testingMetrics.positiveResults) positive this year")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
            }
            Text(clear
                 ? "Random testing rate is meeting the DOT minimum and no positive results are on file this year."
                 : unknown ? "Not enough test history on file to certify the program rate yet."
                 : "Random testing rate is below the DOT minimum — coverage needs attention.")
                .font(EType.caption).foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private func metrics(_ m: TestingMetrics) -> some View {
        HStack(spacing: Space.s3) {
            MetricTile(label: "Tests YTD", value: "\(m.totalTestsYTD)")
            MetricTile(label: "Negative", value: "\(m.negativeResults)", accent: Brand.success)
            MetricTile(label: "Positive", value: "\(m.positiveResults)",
                       accent: m.positiveResults > 0 ? Brand.danger : nil)
        }
    }

    private func checksCard(_ s: DAComplianceStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CHECK · TYPE").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("STATUS").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)
            checkRow("Random drug testing",
                     detail: pct(s.randomTesting.drugRate.actual) + " of " + pct(s.randomTesting.drugRate.required) + " req.",
                     ok: s.randomTesting.drugRate.compliant,
                     value: s.randomTesting.drugRate.compliant ? "MET" : "LOW")
            Divider().overlay(palette.borderFaint).padding(.vertical, Space.s3)
            checkRow("Random alcohol testing",
                     detail: pct(s.randomTesting.alcoholRate.actual) + " of " + pct(s.randomTesting.alcoholRate.required) + " req.",
                     ok: s.randomTesting.alcoholRate.compliant,
                     value: s.randomTesting.alcoholRate.compliant ? "MET" : "LOW")
            Divider().overlay(palette.borderFaint).padding(.vertical, Space.s3)
            checkRow("Annual queries",
                     detail: "\(s.clearinghouse.annualQueriesCompleted) of \(s.clearinghouse.annualQueriesRequired) drivers",
                     ok: s.clearinghouse.compliant,
                     value: s.clearinghouse.compliant ? "CURRENT" : "DUE")
            Divider().overlay(palette.borderFaint).padding(.vertical, Space.s3)
            checkRow("Pre-employment pending",
                     detail: "queries awaiting completion",
                     ok: s.clearinghouse.preEmploymentPending == 0,
                     value: "\(s.clearinghouse.preEmploymentPending)")
            Divider().overlay(palette.borderFaint).padding(.vertical, Space.s3)
            checkRow("Refusals YTD",
                     detail: "test refusals on file this year",
                     ok: s.testingMetrics.refusals == 0,
                     value: "\(s.testingMetrics.refusals)")
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func checkRow(_ title: String, detail: String, ok: Bool, value: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ok ? Brand.success : Brand.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(detail).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(value).font(EType.mono(.caption)).fontWeight(.bold)
                .foregroundStyle(ok ? Brand.success : Brand.warning)
        }
    }

    private var feedNote: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "lock.shield")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textTertiary)
            Text("Your individual Clearinghouse query result and return-to-duty status come from the live FMCSA feed — shown here once that provider is connected, never inferred.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}

// MARK: - Screen (Shell + Driver nav · ME current)

struct ClearinghouseStatusScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ClearinghouseStatusView()
        } nav: {
            BottomNav(leading: driverUtilityNavLeading(),
                      trailing: driverUtilityNavTrailing(meCurrent: true), orbState: .idle)
        }
    }
}

#Preview("Clearinghouse · Dark") {
    ClearinghouseStatusScreen(theme: Theme.dark)
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Clearinghouse · Light") {
    ClearinghouseStatusScreen(theme: Theme.light)
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
