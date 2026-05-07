//
//  316_EsangAssistStatus.swift
//  EusoTrip — Shipper · ESang · Status query (Arc I).
//

import SwiftUI

struct EsangAssistStatusScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { StatusBody() } nav: { shipperLifecycleNav() }
    }
}

private struct StatusEnvelope: Decodable, Hashable {
    struct Match: Decodable, Hashable, Identifiable {
        let loadId: String
        let loadNumber: String
        let lane: String?
        let status: String
        let etaISO: String?
        let lastEvent: String?
        var id: String { loadId }
    }
    let answer: String
    let matches: [Match]
}

private struct StatusBody: View {
    @Environment(\.palette) private var palette
    @State private var query: String = ""
    @State private var env: StatusEnvelope? = nil
    @State private var loading = false
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                inputCard
                if loading { LifecycleCard { Text("ESang searching loads…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let e = env { answerCard(e); matchesCard(e) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · STATUS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Where's my load?").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var inputCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ASK", icon: "questionmark.bubble")
            TextField("e.g. 'UN1203 to Dallas' or 'LD-260427-A38FB12C7E'", text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit { Task { await ask() } }
            Button { Task { await ask() } } label: {
                Text("Ask").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(query.isEmpty)
        }
    }

    private func answerCard(_ e: StatusEnvelope) -> some View {
        LifecycleCard(accentGradient: true) {
            Text(e.answer).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func matchesCard(_ e: StatusEnvelope) -> some View {
        VStack(spacing: 8) {
            ForEach(e.matches) { m in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "205", "loadId": m.loadId])
                } label: {
                    LifecycleCard {
                        LifecycleSection(label: m.loadNumber.uppercased(), icon: "doc.text")
                        LifecycleRow(label: "Status",     value: m.status.uppercased())
                        LifecycleRow(label: "Lane",       value: dashIfEmpty(m.lane))
                        LifecycleRow(label: "ETA",        value: humanISO(m.etaISO))
                        LifecycleRow(label: "Last event", value: dashIfEmpty(m.lastEvent))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func ask() async {
        loading = true; loadError = nil; env = nil
        struct In: Encodable { let query: String }
        do {
            let r: StatusEnvelope = try await EusoTripAPI.shared.query("esangAI.statusQuery", input: In(query: query))
            env = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("316 · Status · Night") { EsangAssistStatusScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("316 · Status · Afternoon") { EsangAssistStatusScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
