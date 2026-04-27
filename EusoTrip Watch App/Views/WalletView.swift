//
//  WalletView.swift
//  EusoTrip Watch App
//
//  EusoWallet balance + last 3 payout rows, pulled from wallet.getOverview.
//  Tap "Open on iPhone" to surface the full wallet surface (Stripe Connect
//  + Plaid flows are phone-only — the watch never enters financial data).
//

import SwiftUI
import WatchKit

struct WatchPayout: Identifiable {
    let id: String
    let amount: Double
    let date: Date
    let label: String
}

@MainActor
final class WalletStore: ObservableObject {
    static let shared = WalletStore()
    @Published var availableCents: Int = 284_12
    @Published var pendingCents: Int = 1_420_00
    @Published var recent: [WatchPayout] = [
        .init(id: "1", amount: 1240.00, date: Date().addingTimeInterval(-86400 * 3), label: "Load LD-48231"),
        .init(id: "2", amount: 980.50, date: Date().addingTimeInterval(-86400 * 7), label: "Load LD-48194"),
        .init(id: "3", amount: 1450.75, date: Date().addingTimeInterval(-86400 * 12), label: "Load LD-48127")
    ]

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else { return }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON("wallet.getOverview")
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: Overview
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            struct Overview: Decodable {
                let availableCents: Int?
                let pendingCents: Int?
                let recent: [RemotePayout]?
            }
            struct RemotePayout: Decodable {
                let id: String
                let amountCents: Int
                let date: String?
                let label: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            availableCents = env.result.data.json.availableCents ?? availableCents
            pendingCents = env.result.data.json.pendingCents ?? pendingCents
            if let remote = env.result.data.json.recent {
                recent = remote.map {
                    WatchPayout(
                        id: $0.id,
                        amount: Double($0.amountCents) / 100,
                        date: ISO8601DateFormatter.iso.date(from: $0.date ?? "") ?? Date(),
                        label: $0.label ?? ""
                    )
                }
            }
        } catch {}
    }
}

struct WalletView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @StateObject private var store = WalletStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: S.s2) {
                VStack(spacing: 0) {
                    Text("Available")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("$\(String(format: "%.2f", Double(store.availableCents) / 100))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: R.md))

                HStack {
                    Text("Pending").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.2f", Double(store.pendingCents) / 100))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .padding(8)
                .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))

                Divider().background(Color.esangBorder)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent").font(.system(size: 10)).foregroundStyle(.secondary)
                    ForEach(store.recent) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.label).font(.system(size: 10, weight: .semibold))
                                Text(p.date, style: .date).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("$\(String(format: "%.2f", p.amount))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 3)
                    }
                }
                Button {
                    WKInterfaceDevice.current().play(.click)
                    connectivity.requestPhoneActivation(transcript: "open wallet", reply: "Opening EusoWallet on your iPhone.")
                } label: {
                    Label("Open on iPhone", systemImage: "iphone.and.arrow.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Color.esangBlue, in: RoundedRectangle(cornerRadius: R.sm))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, S.s1)
            .padding(.horizontal, S.s2)
        }
        .navigationTitle("EusoWallet")
        .task { await store.refresh(auth: auth) }
    }
}
