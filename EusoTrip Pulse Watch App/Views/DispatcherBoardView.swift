//
//  DispatcherBoardView.swift
//  EusoTrip Watch App
//
//  Dispatcher persona — surfaces the live exception feed from the
//  control tower so the dispatcher can glance at what needs attention
//  without pulling out the phone. Items are tappable for a voice
//  briefing on the wrist.
//

import SwiftUI
import Combine
import WatchKit

struct DispatcherException: Identifiable, Equatable {
    let id: String
    let loadId: String
    let label: String
    let severity: String   // info / warn / critical
    let at: Date
}

@MainActor
final class DispatcherBoardStore: ObservableObject {
    static let shared = DispatcherBoardStore()
    /// No seed data. Doctrine: no mocks, no fake exceptions. A
    /// dispatcher with three hard-coded "LD-48231 / LD-48194 /
    /// LD-48127" seeds is worse than an empty board — they see fake
    /// load ids and ignore the real ones. MCP-verified real endpoint:
    /// `dispatch.getExceptions` at
    /// `frontend/server/routers/dispatch.ts:1503`.
    @Published var exceptions: [DispatcherException] = []
    @Published var hasLoadedOnce: Bool = false
    @Published var lastError: String?

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else {
            lastError = "Sign in on your iPhone"
            return
        }
        do {
            let client = EsangClient(auth: auth)
            // Previously called `controlTower.listExceptions`, which
            // does not exist on the server. The wrist silently 404'd
            // and the fake seeds sat on-screen forever. Switched to
            // the real `dispatch.getExceptions` proc.
            let data = try await client.queryJSON("dispatch.getExceptions")
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: [RemoteException]
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            /// Server row shape — every field optional so a row with
            /// missing load id or severity still decodes. `dispatch.
            /// getExceptions` ships a richer object (load, driver,
            /// status, type, etc.); we flatten just enough to render
            /// the wrist row.
            struct RemoteException: Decodable {
                let id: String?
                let loadId: String?
                let loadNumber: String?
                let label: String?
                let title: String?
                let type: String?
                let severity: String?
                let priority: String?
                let at: String?
                let createdAt: String?
                let reportedAt: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            exceptions = env.result.data.json.map { r in
                DispatcherException(
                    id: r.id ?? UUID().uuidString,
                    loadId: r.loadNumber ?? r.loadId ?? "—",
                    label: r.title ?? r.label ?? r.type?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Exception",
                    severity: r.severity ?? r.priority ?? "info",
                    at: ISO8601DateFormatter.iso.date(from: r.at ?? r.reportedAt ?? r.createdAt ?? "") ?? Date()
                )
            }
            hasLoadedOnce = true
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Can't reach dispatch"
        }
    }
}

struct DispatcherBoardView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @StateObject private var store = DispatcherBoardStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: S.s1) {
                Text("Exceptions")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if store.exceptions.isEmpty {
                    Text("All clear.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    ForEach(store.exceptions) { ex in
                        exceptionRow(ex)
                    }
                }

                Button {
                    WKInterfaceDevice.current().play(.click)
                    connectivity.requestPhoneActivation(
                        transcript: "open control tower",
                        reply: "Opening control tower on your iPhone."
                    )
                } label: {
                    Label("Open on iPhone", systemImage: "iphone.and.arrow.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: R.sm))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.vertical, S.s1)
            .padding(.horizontal, S.s2)
        }
        .navigationTitle("Board")
        .task { await store.refresh(auth: auth) }
        // Prevent overscroll of the brand-gradient "Open on iPhone"
        // button or any severity-colored row from bleeding past the
        // watch's rounded bezel.
        .clipShape(ContainerRelativeShape())
    }

    @ViewBuilder
    private func exceptionRow(_ ex: DispatcherException) -> some View {
        HStack(spacing: 6) {
            Circle().fill(severityColor(ex.severity)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(ex.loadId)
                    .font(.system(size: 10, weight: .bold))
                Text(ex.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(ex.at, style: .relative)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    private func severityColor(_ sev: String) -> Color {
        switch sev.lowercased() {
        case "critical": return Color.esangDanger
        case "warn", "warning": return Color.esangAmber
        default: return Color.esangGreen
        }
    }
}
