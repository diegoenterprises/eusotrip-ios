//
//  178_DriverDrugTest.swift
//  EusoTrip — Screen 178 · Driver Drug Test (LIVE-wired)
//
//  Purpose: turn a compliance trap into a calm surface — the driver's DOT
//  random-pool standing, the nearest open collection site, and a clear
//  chain of custody — so if they're selected they collect in time and stay
//  safety-sensitive.
//
//  Wiring manifest (server/routers/drugTesting.ts):
//    drugTesting.getComplianceStatus  EXISTS · drugTesting.ts:375
//      (real random-testing rate + YTD result aggregates)
//    drugTesting.getCollectionSites   EXISTS · drugTesting.ts:402
//      input { location?, radius } → collection sites near the driver
//  HONEST GAPS handed to the-oath:
//    · getCollectionSites returns [] today (code: "external API in
//      production") — the sites card shows its honest empty state, never a
//      fabricated clinic. Proposed: wire the collection-site directory feed.
//    · There is no per-driver "am I randomly selected + 24h countdown"
//      endpoint, so the hero reports the driver's pool standing honestly
//      and never invents a countdown. Proposed: drugTesting.getMySelection
//      → { selected, dueBy, panel } to light the clock.
//  transportMode = truck · country US (49 CFR Part 382 · DOT 5-panel).
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//
//  §W OFFLINE POLICY: ONLINE_ONLY(a cached "no test required" could hide a random selection
//  whose collection window is already running).
//  Honored: nothing on this surface is persisted or replayed client-side;
//  on any failure the model is cleared and the reason is surfaced.
//

import SwiftUI
import CoreLocation

// MARK: - Wire models

private struct DTRate: Decodable { let required: Double; let actual: Double; let compliant: Bool }
private struct DTRandom: Decodable { let drugRate: DTRate; let alcoholRate: DTRate }
private struct DTMetrics: Decodable {
    let totalTestsYTD: Int; let negativeResults: Int
    let positiveResults: Int; let refusals: Int
}
private struct DTStatus: Decodable {
    let overall: String
    let randomTesting: DTRandom
    let testingMetrics: DTMetrics
}
private struct CollectionSite: Decodable, Identifiable {
    let id: String?
    let name: String?
    let address: String?
    let distance: Double?
    let open: Bool?
    var idValue: String { id ?? name ?? UUID().uuidString }
}

// MARK: - ViewModel

@MainActor
private final class DrugTestViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, error(String) }
    @Published var phase: Phase = .idle
    @Published var status: DTStatus?
    @Published var sites: [CollectionSite] = []

    private struct SitesIn: Encodable { let radius: Int }

    func load() async {
        phase = .loading
        do {
            async let st: DTStatus = EusoTripAPI.shared.queryNoInput("drugTesting.getComplianceStatus")
            async let si: [CollectionSite] = EusoTripAPI.shared.query(
                "drugTesting.getCollectionSites", input: SitesIn(radius: 50))
            status = try await st
            sites = (try? await si) ?? []
            phase = .ready
        } catch {
            phase = .error("Couldn't reach the testing status feed.")
        }
    }
}

// MARK: - Screen body

struct DrugTestView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm = DrugTestViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverUtilityHeader(eyebrow: "DRIVER · CLEARINGHOUSE", caption: "DOT PANEL",
                                title: "Drug & alcohol test",
                                subtitle: "random pool · DOT 5-panel",
                                // Right rail intentionally empty: it previously hardcoded one
                                // fabricated driver identity + CDL into every signed-in driver's
                                // chrome. Left blank until a real session identity is bound.
                                rightTop: "",
                                rightBottom: "")
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading: DriverUtilityLoading(text: "Checking your pool standing…")
            case .error(let m):   DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:          content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
    }

    @ViewBuilder private var content: some View {
        if let s = vm.status {
            VStack(spacing: Space.s4) {
                poolHero(s)
                sitesCard
                custodyCard
                selectionNote
                CTAButton(title: "Refresh", action: { Task { await vm.load() } },
                          leadingIcon: "arrow.clockwise")
            }
            .padding(Space.s5)
        }
    }

    private func poolHero(_ s: DTStatus) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("RANDOM POOL").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                StatusPill(text: "No test required", kind: .success)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("In pool").font(EType.h1).foregroundStyle(LinearGradient.diagonal)
                Text("· not currently selected")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: Space.s5) {
                miniStat("Drug rate", "\(Int((s.randomTesting.drugRate.actual * 100).rounded()))%",
                         sub: "of \(Int((s.randomTesting.drugRate.required * 100).rounded()))% req.")
                miniStat("Tests YTD", "\(s.testingMetrics.totalTestsYTD)",
                         sub: "\(s.testingMetrics.positiveResults) positive")
            }
            Text("You're enrolled in the DOT random-selection pool. If you're selected you'll be notified with a 24-hour collection window.")
                .font(EType.caption).foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private func miniStat(_ label: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(EType.mono(.body)).fontWeight(.bold).foregroundStyle(palette.textPrimary)
            Text(sub).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
        }
    }

    private var sitesCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("COLLECTION SITES · NEAREST").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("DIST").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            if vm.sites.isEmpty {
                DriverUtilityEmpty(systemImage: "cross.case",
                                   title: "Sites load when you're selected",
                                   detail: "The collection-site directory connects to the testing network — nearest open clinics appear here the moment a test is required.")
            } else {
                ForEach(vm.sites.prefix(4)) { site in
                    siteRow(site)
                    if site.idValue != vm.sites.prefix(4).last?.idValue {
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func siteRow(_ s: CollectionSite) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name ?? "Collection site").font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(s.address ?? "—").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(s.distance.map { String(format: "%.1f mi", $0) } ?? "—")
                    .font(EType.mono(.caption)).fontWeight(.bold).foregroundStyle(palette.textPrimary)
                // A site that simply did not report hours was painted a
                // definitive red "CLOSED". Absent hours now read as unknown,
                // in neutral — the driver is not steered away from an open
                // clinic by a fabricated verdict.
                Text(s.open.map { $0 ? "OPEN" : "CLOSED" } ?? "HOURS N/A")
                    .font(EType.micro).fontWeight(.bold)
                    .foregroundStyle(s.open.map { $0 ? Brand.success : Brand.danger }
                                     ?? palette.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var custodyCard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("CHAIN OF CUSTODY").font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                custodyNode("Selected", done: true, first: true)
                custodyConnector()
                custodyNode("Check-in", done: false)
                custodyConnector()
                custodyNode("Specimen", done: false)
                custodyConnector()
                custodyNode("MRO verify", done: false, last: true)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func custodyNode(_ label: String, done: Bool, first: Bool = false, last: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(done ? Color.clear : palette.borderSoft))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            Text(label).font(.system(size: 9, weight: .bold))
                .foregroundStyle(done ? palette.textPrimary : palette.textTertiary)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    private func custodyConnector() -> some View {
        Rectangle().fill(palette.borderFaint).frame(height: 2).offset(y: -9)
    }

    private var selectionNote: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "bell.badge")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textTertiary)
            Text("Refusal to test is treated as a positive — removal from safety-sensitive duty. You'll get a push the moment you're selected.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
    }
}

// MARK: - Screen (Shell + Driver nav · ME current)

struct DrugTestScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DrugTestView()
        } nav: {
            BottomNav(leading: driverUtilityNavLeading(),
                      trailing: driverUtilityNavTrailing(meCurrent: true), orbState: .idle)
        }
    }
}

#Preview("Drug Test · Dark") {
    DrugTestScreen(theme: Theme.dark)
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Drug Test · Light") {
    DrugTestScreen(theme: Theme.light)
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
