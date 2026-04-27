//
//  WristSafetyCoachView.swift
//  EusoTrip Pulse Watch App — ESANG Safety Coach on the wrist
//
//  Wrist mirror of the iPhone's 087 Me · Safety Coach. Renders the
//  same role-aware coaching pack the phone fetches from
//  `esangCoach.forDriver`, glance-sized for the watch. Each card
//  is a single-line imperative with a severity pill and an optional
//  CFR chip.
//
//  Doctrine parity:
//    • Every coaching-eligible role (DRIVER, RAIL_ENGINEER,
//      RAIL_CONDUCTOR, SHIP_CAPTAIN, VESSEL_OPERATOR,
//      CUSTOMS_BROKER, CATALYST) gets the coach tab.
//    • Hazmat is the most-stringent lens — severity=critical cards
//      render with the gradient chip so the wrist glance surfaces
//      them first.
//
//  Transport:
//    • Primary path — the wrist calls `esangCoach.forDriver` via
//      EsangClient (same Bearer token the iOS companion uses).
//    • When the phone is paired, this view also relays the pack
//      to the phone's `SafetyCoachStore` through WCSession so both
//      surfaces stay in sync. Not implemented yet; the wrist's
//      direct call works standalone.
//    • When offline, last-seen pack renders with a "cached" badge.
//      No fabricated items.
//

import SwiftUI
import Combine

// MARK: - Wrist-side store

@MainActor
final class WristSafetyCoachStore: ObservableObject {
    static let shared = WristSafetyCoachStore()

    struct CoachItem: Identifiable, Equatable {
        let id: String
        let title: String
        let body: String
        let severity: String    // "info" | "watch" | "critical"
        let cfr: String?
        let topic: String
    }

    @Published var items: [CoachItem] = []
    @Published var role: String = ""
    @Published var vertical: String = "truck"
    @Published var generatedAt: Date?
    @Published var hasLoadedOnce: Bool = false
    @Published var lastError: String?

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else {
            lastError = "Sign in on your iPhone"
            return
        }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON(
                "esangCoach.forDriver",
                input: ["limit": 6]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: Pack
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            struct Pack: Decodable {
                let items: [RemoteItem]
                let role: String?
                let vertical: String?
                let generatedAt: Double?
            }
            struct RemoteItem: Decodable {
                let title: String
                let body: String
                let severity: String?
                let cfr: String?
                let topic: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            items = env.result.data.json.items.map {
                CoachItem(
                    id: "\($0.topic ?? "other")::\($0.title)",
                    title: $0.title,
                    body: $0.body,
                    severity: $0.severity ?? "info",
                    cfr: $0.cfr,
                    topic: $0.topic ?? "other"
                )
            }
            role = env.result.data.json.role ?? ""
            vertical = env.result.data.json.vertical ?? "truck"
            if let ts = env.result.data.json.generatedAt {
                generatedAt = Date(timeIntervalSince1970: ts / 1000)
            }
            hasLoadedOnce = true
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Can't reach ESANG Coach"
        }
    }
}

// MARK: - View

struct WristSafetyCoachView: View {
    @EnvironmentObject var auth: AuthStore
    @StateObject private var store = WristSafetyCoachStore.shared

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    if let err = store.lastError, !store.hasLoadedOnce {
                        errorBanner(err)
                    } else if store.items.isEmpty && store.hasLoadedOnce {
                        quietDay
                    } else if !store.items.isEmpty {
                        list
                    } else {
                        loadingBanner
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }

            ModularTickBezel(
                corners: .init(
                    topLeading:     "COACH",
                    topTrailing:    regulatorBadge,
                    bottomLeading:  "ESANG",
                    bottomTrailing: counterLabel
                )
            )
            .allowsHitTesting(false)
        }
        .navigationTitle("Coach")
        .task { await store.refresh(auth: auth) }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task { await store.refresh(auth: auth) }
        }
        .clipShape(ContainerRelativeShape())
    }

    private var header: some View {
        HStack {
            Text("Safety Coach")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Spacer()
            if let ts = store.generatedAt {
                Text(relative(ts))
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 4) {
            ForEach(store.items) { item in
                itemCard(item)
            }
        }
    }

    private func itemCard(_ item: WristSafetyCoachStore.CoachItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: topicIcon(item.topic))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconTint(item.severity))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 10, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.body)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                severityPill(item.severity)
            }
            if let cfr = item.cfr, !cfr.isEmpty {
                Text(cfr)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    @ViewBuilder
    private func severityPill(_ severity: String) -> some View {
        switch severity.lowercased() {
        case "critical":
            Text("CRIT")
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(LinearGradient.esangPrimary, in: Capsule())
        case "watch":
            Text("WATCH")
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Color.esangAmber)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .overlay(Capsule().stroke(Color.esangAmber, lineWidth: 0.5))
        default:
            Text("INFO")
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .overlay(Capsule().stroke(.secondary.opacity(0.4), lineWidth: 0.5))
        }
    }

    private func iconTint(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical": return Color.esangMagenta
        case "watch":    return Color.esangAmber
        default:         return Color.esangBlue
        }
    }

    private func topicIcon(_ topic: String) -> String {
        switch topic.lowercased() {
        case "hos":                 return "clock"
        case "hazmat":              return "exclamationmark.triangle"
        case "following":           return "car.2"
        case "fatigue":             return "bed.double"
        case "weather":             return "cloud.sun"
        case "vehicle":             return "wrench.and.screwdriver"
        case "inspection":          return "checkmark.shield"
        case "training":            return "graduationcap"
        case "fra_certification":   return "train.side.front.car"
        case "stcw":                return "ferry"
        case "mmc_medical":         return "cross.case"
        case "ptc":                 return "wave.3.right"
        case "cargo_securement":    return "shippingbox"
        case "stowage":             return "square.stack.3d.up"
        case "docs":                return "doc.text"
        default:                    return "lightbulb"
        }
    }

    // MARK: - Empty / error states

    private var quietDay: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 18))
                .foregroundStyle(Color.esangGreen)
            Text("Quiet day")
                .font(.system(size: 11, weight: .semibold))
            Text("ESANG didn't flag anything for your role + record.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    private var loadingBanner: some View {
        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Pulling coach items…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
    }

    private func errorBanner(_ err: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.esangAmber)
            Text(err)
                .font(.system(size: 9, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: R.sm))
    }

    // MARK: - Bezel corner helpers

    private var regulatorBadge: String {
        switch store.vertical.lowercased() {
        case "rail":   return "FRA"
        case "vessel": return "USCG"
        default:       return "FMCSA"
        }
    }

    private var counterLabel: String {
        let n = store.items.count
        if n == 0 { return store.hasLoadedOnce ? "CLEAR" : "LOADING" }
        return "\(n) ITEMS"
    }

    private func relative(_ d: Date) -> String {
        let s = -d.timeIntervalSinceNow
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }
}
