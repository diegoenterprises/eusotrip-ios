//
//  WalletView.swift
//  EusoTrip Watch App
//
//  EusoWallet balance + last 3 payout rows, pulled from wallet.getOverview.
//  Tap "Open on iPhone" to surface the full wallet surface (Stripe Connect
//  + Plaid flows are phone-only — the watch never enters financial data).
//

import SwiftUI
import Combine
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
    // No seed data. Doctrine: no mocks, no fake fake payouts. We
    // render the empty state until `wallet.getOverview` answers —
    // the previous seeded $284.12 / $1,420 / three fake loads were
    // wrong on the wrist for anyone with a different real balance,
    // especially a brand-new driver staring at someone else's
    // numbers. See `MEMORY.md` · "Full-parity doctrine" anchor.
    @Published var availableCents: Int = 0
    @Published var pendingCents: Int = 0
    @Published var recent: [WatchPayout] = []
    /// True once `refresh` has seen the server at least once, so the
    /// view can tell "haven't loaded yet" apart from "really zero."
    @Published var hasLoadedOnce: Bool = false

    /// Error surface — the view reads this to render "Can't reach
    /// your wallet" when something goes wrong, instead of silently
    /// showing $0 and making the driver think they have no money.
    @Published var lastError: String?

    /// Wall-clock the server stamped on the last successful fetch —
    /// used for the "as of …" footer so the driver can see staleness.
    @Published var lastUpdated: Date?

    /// Refresh balance + recent transactions in parallel. Both calls
    /// are driver-scoped server-side (`ctx.user.id` is the signed-in
    /// driver). We don't pass a userId param from the wrist — the
    /// server refuses to answer with someone else's wallet.
    ///
    /// MCP-verified against the real wallet router:
    ///   - `wallet.getBalance`        → `frontend/server/routers/wallet.ts:199`
    ///   - `wallet.getTransactions`   → `frontend/server/routers/wallet.ts:371`
    ///
    /// Previous implementation called `wallet.getOverview` which
    /// does not exist on the server — the call silently 404'd and
    /// the view kept showing stale seeds. Fixed so the wrist wallet
    /// actually connects to the driver's real EusoWallet.
    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else {
            lastError = "Sign in on your iPhone"
            return
        }
        let client = EsangClient(auth: auth)

        // Balance — primary call. If this fails we surface an error
        // banner; there's no point rendering a $0 balance to a real
        // driver who has real money in the account.
        do {
            let data = try await client.queryJSON("wallet.getBalance")
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: BalanceJson
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            /// Server ships balance as dollars (Double). We hold cents on
            /// the wrist so the existing UI contract is preserved.
            struct BalanceJson: Decodable {
                let available: Double
                let pending: Double
                let reserved: Double?
                let currency: String?
                let lastUpdated: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            availableCents = Int((env.result.data.json.available * 100).rounded())
            pendingCents = Int((env.result.data.json.pending * 100).rounded())
            if let iso = env.result.data.json.lastUpdated {
                lastUpdated = ISO8601DateFormatter.iso.date(from: iso)
            }
            lastError = nil
            hasLoadedOnce = true
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Can't reach your wallet"
            return
        }

        // Transactions — recent ≤3 rows for the wrist strip. A failure
        // here does NOT blow away the balance we just loaded — we keep
        // that and just blank the recent list.
        do {
            let data = try await client.queryJSON(
                "wallet.getTransactions",
                input: ["limit": 3]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: [Txn]
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            /// Mirror of the server's row shape at
            /// `frontend/server/routers/wallet.ts:405` — every field
            /// optional so a row with a missing description or
            /// loadNumber still decodes.
            struct Txn: Decodable {
                let id: String
                let type: String?
                let amount: Double?
                let status: String?
                let description: String?
                let loadNumber: String?
                let date: String?
                let completedAt: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            recent = env.result.data.json.prefix(3).map { t in
                let d: Date
                if let c = t.completedAt, let parsed = iso.date(from: c) {
                    d = parsed
                } else if let simple = t.date, !simple.isEmpty {
                    // Server ships the 'date' field as YYYY-MM-DD.
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    df.locale = Locale(identifier: "en_US_POSIX")
                    d = df.date(from: simple) ?? Date()
                } else {
                    d = Date()
                }
                let amount = t.amount ?? 0
                let label: String = t.loadNumber.flatMap { "Load \($0)" }
                    ?? t.description
                    ?? (t.type?.capitalized ?? "Payout")
                return WatchPayout(id: t.id, amount: amount, date: d, label: label)
            }
        } catch {
            // Balance is still valid — just blank the recent list.
            recent = []
        }
    }
}

struct WalletView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @StateObject private var store = WalletStore.shared

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: S.s2) {
                    if let err = store.lastError, !store.hasLoadedOnce {
                        // First-load failure — tell the driver why
                        // the balance is blank rather than letting
                        // them stare at $0.
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 10))
                            Text(err)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: R.sm))
                    }

                    VStack(spacing: 0) {
                        Text("Available")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(store.hasLoadedOnce
                             ? "$\(String(format: "%.2f", Double(store.availableCents) / 100))"
                             : "—")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: R.md))

                    HStack {
                        Text("Pending").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Text(store.hasLoadedOnce
                             ? "$\(String(format: "%.2f", Double(store.pendingCents) / 100))"
                             : "—")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .padding(8)
                    .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))

                    Divider().background(Color.esangBorder)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent").font(.system(size: 10)).foregroundStyle(.secondary)
                        if store.recent.isEmpty {
                            Text(store.hasLoadedOnce
                                 ? "No payouts yet — settlement will land here."
                                 : "Loading recent payouts…")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
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

            // Modular Ultra bezel — wallet summary in the corners so
            // the driver sees balance + pending even while scrolling
            // the recent list.
            ModularTickBezel(
                corners: .init(
                    topLeading:     walletCornerAvailable,
                    topTrailing:    walletCornerPending,
                    bottomLeading:  walletCornerLastPayout,
                    bottomTrailing: walletCornerPhoneLink
                )
            )
            .allowsHitTesting(false)
        }
        .navigationTitle("EusoWallet")
        .task { await store.refresh(auth: auth) }
        // Re-fetch the moment the driver finishes signing in on the
        // phone — before this, the @Published auth.token flip wasn't
        // observed and the wallet tab kept showing the pre-auth empty
        // state until the driver pulled to refresh manually.
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task { await store.refresh(auth: auth) }
        }
        // Clip the entire wallet tab to the bezel curvature so the
        // brand-gradient "Available" card can't spill into the rounded
        // corners on overscroll/bounce.
        .clipShape(ContainerRelativeShape())
    }

    // MARK: - Modular Ultra corner labels

    private var walletCornerAvailable: String {
        guard store.hasLoadedOnce else { return "LOADING" }
        let dollars = Double(store.availableCents) / 100.0
        return "AVL $\(Self.shortMoney(dollars))"
    }

    private var walletCornerPending: String {
        guard store.hasLoadedOnce else { return "—" }
        let dollars = Double(store.pendingCents) / 100.0
        return dollars > 0 ? "PEND $\(Self.shortMoney(dollars))" : "CLEAR"
    }

    private var walletCornerLastPayout: String {
        guard let last = store.recent.first else { return "NO RUNS" }
        return "LAST $\(Self.shortMoney(last.amount))"
    }

    private var walletCornerPhoneLink: String {
        connectivity.isReachable ? "LINKED" : "OFFLINE"
    }

    private static func shortMoney(_ dollars: Double) -> String {
        if dollars >= 10_000 {
            return String(format: "%.1fK", dollars / 1000.0)
        }
        if dollars >= 1_000 {
            return String(format: "%.2fK", dollars / 1000.0)
        }
        return String(format: "%.0f", dollars)
    }
}
