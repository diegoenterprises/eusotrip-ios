//
//  WalletView.swift
//  EusoTrip Pulse Watch App
//
//  Wrist evidence for the canonical iOS EusoWallet. Pulse shows the money
//  state a driver needs at a glance, then hands sensitive payout management
//  to the paired iPhone. No financial entry happens on the watch.
//

import SwiftUI
import Combine
import WatchKit

struct WatchWalletBalance: Equatable {
    let availableCents: Int
    let pendingCents: Int
    let reservedCents: Int?
    let currency: String
    let serverUpdatedAt: Date?
}

enum WatchWalletEntryFlow: Equatable {
    case incoming
    case outgoing
    case neutral

    static func resolve(type: String?, amount: Double?) -> Self {
        guard let amount else { return .neutral }
        if amount < 0 { return .outgoing }

        switch type?.lowercased() {
        case "earnings", "refund", "bonus", "deposit":
            return .incoming
        case "payout", "fee", "transfer":
            return .outgoing
        case "adjustment":
            return amount > 0 ? .incoming : .neutral
        default:
            return .neutral
        }
    }
}

struct WatchWalletEntry: Identifiable, Equatable {
    let id: String
    let amount: Double?
    let currency: String
    let occurredAt: Date?
    let label: String
    let type: String?
    let status: String?

    var flow: WatchWalletEntryFlow {
        WatchWalletEntryFlow.resolve(type: type, amount: amount)
    }
}

private struct WalletBalanceEnvelope: Decodable {
    struct Result: Decodable {
        struct DataContainer: Decodable { let json: BalanceJSON }
        let data: DataContainer
    }

    struct BalanceJSON: Decodable {
        let available: Double
        let pending: Double
        let reserved: Double?
        let currency: String?
        let lastUpdated: String?
    }

    let result: Result
}

private struct WalletTransactionsEnvelope: Decodable {
    struct Result: Decodable {
        struct DataContainer: Decodable { let json: [TransactionJSON] }
        let data: DataContainer
    }

    struct TransactionJSON: Decodable {
        let id: String
        let type: String?
        let amount: Double?
        let currency: String?
        let status: String?
        let description: String?
        let loadNumber: String?
        let date: String?
        let completedAt: String?
    }

    let result: Result
}

@MainActor
final class WalletStore: ObservableObject {
    static let shared = WalletStore()

    @Published private(set) var balance: WatchWalletBalance?
    @Published private(set) var recent: [WatchWalletEntry] = []
    @Published private(set) var hasLoadedBalance = false
    @Published private(set) var hasLoadedActivity = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var balanceError: String?
    @Published private(set) var activityError: String?
    @Published private(set) var lastRefreshAt: Date?

    private(set) var boundUserId: String?
    private var requestGeneration = 0

    func resetForIdentity(_ userId: String?) {
        requestGeneration += 1
        boundUserId = userId
        balance = nil
        recent = []
        hasLoadedBalance = false
        hasLoadedActivity = false
        isRefreshing = false
        balanceError = nil
        activityError = nil
        lastRefreshAt = nil
    }

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn,
              let userId = auth.userId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userId.isEmpty else {
            resetForIdentity(nil)
            balanceError = "Sign in on your iPhone to load EusoWallet."
            return
        }

        if boundUserId != userId {
            resetForIdentity(userId)
        }

        requestGeneration += 1
        let generation = requestGeneration
        isRefreshing = true
        balanceError = nil
        activityError = nil

        let client = EsangClient(auth: auth)

        do {
            let data = try await client.queryJSON("wallet.getBalance")
            let json = try JSONDecoder().decode(WalletBalanceEnvelope.self, from: data).result.data.json
            guard generation == requestGeneration,
                  boundUserId == userId,
                  auth.userId?.trimmingCharacters(in: .whitespacesAndNewlines) == userId else { return }

            balance = WatchWalletBalance(
                availableCents: Self.cents(json.available),
                pendingCents: Self.cents(json.pending),
                reservedCents: json.reserved.map(Self.cents),
                currency: Self.currencyCode(json.currency),
                serverUpdatedAt: Self.parseTimestamp(json.lastUpdated)
            )
            hasLoadedBalance = true
            lastRefreshAt = Date()
        } catch {
            guard generation == requestGeneration, boundUserId == userId else { return }
            balanceError = Self.compactError(error, fallback: "EusoWallet balance is unavailable.")
        }

        do {
            let data = try await client.queryJSON(
                "wallet.getTransactions",
                input: ["limit": 3]
            )
            let rows = try JSONDecoder().decode(WalletTransactionsEnvelope.self, from: data).result.data.json
            let entries = rows.prefix(3).map(Self.entry(from:))
            guard generation == requestGeneration,
                  boundUserId == userId,
                  auth.userId?.trimmingCharacters(in: .whitespacesAndNewlines) == userId else { return }

            recent = Array(entries)
            hasLoadedActivity = true
        } catch {
            guard generation == requestGeneration, boundUserId == userId else { return }
            activityError = Self.compactError(error, fallback: "Recent wallet activity is unavailable.")
        }

        guard generation == requestGeneration, boundUserId == userId else { return }
        isRefreshing = false
    }

    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        if let parsed = ISO8601DateFormatter.iso.date(from: raw) { return parsed }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let parsed = iso.date(from: raw) { return parsed }

        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: raw)
    }

    static func compactAge(_ date: Date, at now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "NOW" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)M" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)H" }
        return "\(hours / 24)D"
    }

    #if targetEnvironment(simulator)
    func installVisualQA(mode: String) {
        let userId = "visual-wallet-user"
        resetForIdentity(userId)

        if mode == "wallet-error" {
            balanceError = "EusoTrip could not verify this balance."
            activityError = "Recent activity could not be verified."
            return
        }

        let now = Date()
        balance = WatchWalletBalance(
            availableCents: 411_842,
            pendingCents: 86_000,
            reservedCents: 22_514,
            currency: "USD",
            serverUpdatedAt: now.addingTimeInterval(-90)
        )
        recent = [
            WatchWalletEntry(
                id: "visual-wallet-earnings",
                amount: 1_900,
                currency: "USD",
                occurredAt: now.addingTimeInterval(-300),
                label: "LD-260427 · Houston-Dallas",
                type: "earnings",
                status: "completed"
            ),
            WatchWalletEntry(
                id: "visual-wallet-payout",
                amount: 850,
                currency: "USD",
                occurredAt: now.addingTimeInterval(-4_500),
                label: "Instant payout",
                type: "payout",
                status: "processing"
            ),
            WatchWalletEntry(
                id: "visual-wallet-refund",
                amount: 42.18,
                currency: "USD",
                occurredAt: nil,
                label: "Fuel rebate",
                type: "refund",
                status: "completed"
            ),
        ]
        hasLoadedBalance = true
        hasLoadedActivity = true
        lastRefreshAt = now.addingTimeInterval(-30)
    }
    #endif

    private static func entry(from row: WalletTransactionsEnvelope.TransactionJSON) -> WatchWalletEntry {
        let load = row.loadNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = row.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = row.type?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label: String
        if let load, !load.isEmpty {
            label = "Load \(load)"
        } else if let description, !description.isEmpty {
            label = description
        } else if let type, !type.isEmpty {
            label = type.replacingOccurrences(of: "_", with: " ").capitalized
        } else {
            label = "Wallet activity"
        }

        return WatchWalletEntry(
            id: row.id,
            amount: row.amount,
            currency: currencyCode(row.currency),
            occurredAt: parseTimestamp(row.completedAt) ?? parseTimestamp(row.date),
            label: label,
            type: type,
            status: row.status
        )
    }

    private static func cents(_ dollars: Double) -> Int {
        guard dollars.isFinite else { return 0 }
        let cents = (dollars * 100).rounded()
        if cents >= Double(Int.max) { return Int.max }
        if cents <= Double(Int.min) { return Int.min }
        return Int(cents)
    }

    private static func currencyCode(_ raw: String?) -> String {
        let code = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return code.count == 3 ? code : "USD"
    }

    private static func compactError(_ error: Error, fallback: String) -> String {
        if let localized = error as? LocalizedError,
           let message = localized.errorDescription,
           !message.isEmpty {
            return message
        }
        return fallback
    }
}

struct WalletView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var connectivity: WatchConnectivityManager
    @StateObject private var store = WalletStore.shared
    @State private var phoneDispatch: PhoneActivationDispatch?
    @State private var showLedger = false

    private var visualState: String? {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["EUSOTRIP_PULSE_VISUAL_STATE"]
        #else
        nil
        #endif
    }

    private var isVisualQA: Bool {
        visualState?.hasPrefix("wallet") == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            walletHeader
            balanceSurface
            activitySection
            phoneButton
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .watchEdgeGlow()
        .navigationTitle("EusoWallet")
        .task {
            #if targetEnvironment(simulator)
            if let visualState, isVisualQA {
                store.installVisualQA(mode: visualState)
                return
            }
            #endif
            await store.refresh(auth: auth)
        }
        .onChange(of: auth.userId) { _, newUserId in
            guard !isVisualQA else { return }
            store.resetForIdentity(newUserId?.trimmingCharacters(in: .whitespacesAndNewlines))
            Task { await store.refresh(auth: auth) }
        }
        .sheet(isPresented: $showLedger) {
            ledgerSheet
        }
        .clipShape(ContainerRelativeShape())
    }

    private var walletHeader: some View {
        Button {
            guard !isVisualQA else { return }
            Task { await store.refresh(auth: auth) }
        } label: {
            HStack(spacing: 6) {
                WalletPulseMark()
                VStack(alignment: .leading, spacing: 1) {
                    Text("EUSOWALLET")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 3) {
                        Circle()
                            .fill(headerEvidenceColor)
                            .frame(width: 5, height: 5)
                        Text(headerEvidenceLabel)
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .tracking(0.4)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Refresh EusoWallet")
        .accessibilityValue(headerEvidenceLabel)
    }

    @ViewBuilder
    private var balanceSurface: some View {
        if let balance = store.balance {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("AVAILABLE TO USE")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Text(money(cents: balance.availableCents, currency: balance.currency))
                            .font(.system(size: 23, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.72)
                            .lineLimit(1)
                            .foregroundStyle(LinearGradient.esangPrimary)
                    }
                    Spacer(minLength: 4)
                    Text(balance.currency)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                walletComposition(balance)

                if let error = store.balanceError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.esangAmber)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.esangCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(LinearGradient.esangPrimary.opacity(0.65), lineWidth: 1)
            }
        } else if store.isRefreshing {
            VStack(spacing: 7) {
                ProgressView()
                    .tint(Color.esangBlue)
                Text("Verifying EusoWallet")
                    .font(.system(size: 10, weight: .semibold))
                Text("Balance and ledger are loading from EusoTrip.")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(Color.esangCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Balance unverified", systemImage: "exclamationmark.lock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.esangAmber)
                Text(store.balanceError ?? "EusoTrip has not returned a verified balance.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await store.refresh(auth: auth) }
                } label: {
                    Label("Retry verification", systemImage: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .foregroundStyle(Color.esangBlue)
                        .background(Color.esangBlue.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color.esangAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.esangAmber.opacity(0.55), lineWidth: 1)
            }
        }
    }

    private func walletComposition(_ balance: WatchWalletBalance) -> some View {
        VStack(spacing: 5) {
            WalletCompositionBar(
                available: max(0, balance.availableCents),
                pending: max(0, balance.pendingCents),
                reserved: max(0, balance.reservedCents ?? 0)
            )
            HStack(spacing: 6) {
                balanceMetric(
                    label: "PENDING",
                    value: money(cents: balance.pendingCents, currency: balance.currency),
                    color: .esangBlue
                )
                Divider().frame(height: 21)
                balanceMetric(
                    label: "HELD",
                    value: money(cents: balance.reservedCents, currency: balance.currency),
                    color: .esangMagenta
                )
            }
        }
    }

    private func balanceMetric(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("RECENT LEDGER")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isRefreshing && store.balance != nil {
                    ProgressView().controlSize(.mini)
                } else if store.recent.count > 1 {
                    Button {
                        showLedger = true
                    } label: {
                        HStack(spacing: 2) {
                            Text("ALL \(store.recent.count)")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.esangBlue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View all \(store.recent.count) wallet entries")
                }
            }

            if let error = store.activityError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.esangAmber)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } else if !store.hasLoadedActivity {
                Text("Waiting for verified activity.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else if store.recent.isEmpty {
                Text("No wallet activity yet.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                if let latest = store.recent.first {
                    ledgerRow(latest)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private var ledgerSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("EUSOWALLET")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text("Recent ledger")
                            .font(.system(size: 15, weight: .bold))
                    }
                    Spacer()
                    Text("\(store.recent.count)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.esangBlue)
                }

                if let error = store.activityError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.esangAmber)
                } else if store.recent.isEmpty {
                    Text("No wallet activity yet.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.recent.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().background(Color.esangBorder)
                        }
                        ledgerRow(entry)
                    }
                }

                Text("Amounts and statuses are read from EusoTrip. Manage payout methods on iPhone.")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
        }
        .watchEdgeGlow()
        .navigationTitle("Ledger")
    }

    private func ledgerRow(_ entry: WatchWalletEntry) -> some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(entryColor(entry).opacity(0.16))
                Image(systemName: entrySymbol(entry))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(entryColor(entry))
            }
            .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.label)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                Text(entryEvidence(entry))
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 3)
            Text(entryAmount(entry))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entryColor(entry))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.vertical, 2)
    }

    private var phoneButton: some View {
        VStack(spacing: 3) {
            Button {
                WKInterfaceDevice.current().play(.click)
                phoneDispatch = connectivity.requestPhoneActivation(
                    transcript: "",
                    reply: "Review EusoWallet on your iPhone.",
                    destination: .wallet,
                    beginListening: false,
                    autoSubmit: false
                )
            } label: {
                Label("Open EusoWallet", systemImage: "iphone.and.arrow.forward")
                    .font(.system(size: 10, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .foregroundStyle(.white)
                    .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            Text(phoneEvidenceLabel)
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(phoneEvidenceColor)
                .lineLimit(1)
        }
    }

    private var headerEvidenceLabel: String {
        if store.balanceError != nil, store.balance != nil { return "STALE" }
        if let sourceTime = store.balance?.serverUpdatedAt {
            return "DATA \(WalletStore.compactAge(sourceTime))"
        }
        if let refresh = store.lastRefreshAt {
            return "SYNC \(WalletStore.compactAge(refresh))"
        }
        if store.isRefreshing { return "VERIFY" }
        return "NO SYNC"
    }

    private var headerEvidenceColor: Color {
        if store.balanceError != nil { return .esangAmber }
        if store.lastRefreshAt != nil { return .esangGreen }
        return .secondary
    }

    private var phoneEvidenceLabel: String {
        switch phoneDispatch {
        case .sent: return "iPhone notified"
        case .queued: return "Queued until iPhone reconnects"
        case .unavailable: return "Pair through EusoTrip on iPhone"
        case nil: return connectivity.isReachable ? "iPhone linked" : "iPhone away"
        }
    }

    private var phoneEvidenceColor: Color {
        switch phoneDispatch {
        case .sent: return .esangGreen
        case .queued: return .esangAmber
        case .unavailable: return .esangDanger
        case nil: return connectivity.isReachable ? .esangGreen : .secondary
        }
    }

    private func money(cents: Int?, currency: String) -> String {
        guard let cents else { return "—" }
        return (Double(cents) / 100).formatted(
            .currency(code: currency).precision(.fractionLength(2))
        )
    }

    private func entryAmount(_ entry: WatchWalletEntry) -> String {
        guard let amount = entry.amount else { return "—" }
        let formatted = abs(amount).formatted(
            .currency(code: entry.currency).precision(.fractionLength(2))
        )
        switch entry.flow {
        case .incoming: return "+\(formatted)"
        case .outgoing: return "−\(formatted)"
        case .neutral: return formatted
        }
    }

    private func entryEvidence(_ entry: WatchWalletEntry) -> String {
        let date = entry.occurredAt.map { WalletStore.compactAge($0) } ?? "UNKNOWN"
        let normalizedStatus = entry.status?
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        let status: String
        switch normalizedStatus {
        case "completed": status = "DONE"
        case "processing": status = "PROCESSING"
        case "pending": status = "PENDING"
        case "failed": status = "FAILED"
        case let value?: status = value.uppercased()
        case nil: status = "STATUS UNKNOWN"
        }
        return "\(date) · \(status)"
    }

    private func entryColor(_ entry: WatchWalletEntry) -> Color {
        if entry.status?.lowercased() == "failed" { return .esangDanger }
        if entry.status?.lowercased() == "processing" || entry.status?.lowercased() == "pending" {
            return .esangAmber
        }
        switch entry.flow {
        case .incoming: return .esangGreen
        case .outgoing: return .esangBlue
        case .neutral: return .secondary
        }
    }

    private func entrySymbol(_ entry: WatchWalletEntry) -> String {
        if entry.status?.lowercased() == "failed" { return "exclamationmark" }
        switch entry.flow {
        case .incoming: return "arrow.down.left"
        case .outgoing: return "arrow.up.right"
        case .neutral: return "equal"
        }
    }
}

private struct WalletPulseMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient.esangPrimary.opacity(0.18))
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(LinearGradient.esangPrimary, lineWidth: 1.2)
                .frame(width: 15, height: 10)
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.esangBlue, lineWidth: 1)
                .frame(width: 12, height: 7)
                .offset(x: 2, y: -3)
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

private struct WalletCompositionBar: View {
    let available: Int
    let pending: Int
    let reserved: Int

    private var total: Double {
        Double(available + pending + reserved)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.esangBorder.opacity(0.65))
                if total > 0 {
                    HStack(spacing: 1) {
                        if available > 0 {
                            Color.esangGreen
                                .frame(width: geometry.size.width * Double(available) / total)
                        }
                        if pending > 0 {
                            Color.esangBlue
                                .frame(width: geometry.size.width * Double(pending) / total)
                        }
                        if reserved > 0 {
                            Color.esangMagenta
                                .frame(width: geometry.size.width * Double(reserved) / total)
                        }
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Wallet balance composition")
    }
}
