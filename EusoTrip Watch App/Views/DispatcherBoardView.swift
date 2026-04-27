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
    @Published var exceptions: [DispatcherException] = [
        .init(id: "e1", loadId: "LD-48231", label: "Driver stopped > 30m", severity: "warn", at: Date().addingTimeInterval(-600)),
        .init(id: "e2", loadId: "LD-48194", label: "Detention clock started", severity: "info", at: Date().addingTimeInterval(-1400)),
        .init(id: "e3", loadId: "LD-48127", label: "ETA slipped 45m", severity: "critical", at: Date().addingTimeInterval(-2100))
    ]

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else { return }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON("controlTower.listExceptions", input: ["limit": 10])
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: [RemoteException]
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            struct RemoteException: Decodable {
                let id: String
                let loadId: String?
                let label: String?
                let severity: String?
                let at: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            exceptions = env.result.data.json.map {
                DispatcherException(
                    id: $0.id,
                    loadId: $0.loadId ?? "—",
                    label: $0.label ?? "Exception",
                    severity: $0.severity ?? "info",
                    at: ISO8601DateFormatter.iso.date(from: $0.at ?? "") ?? Date()
                )
            }
        } catch {}
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
