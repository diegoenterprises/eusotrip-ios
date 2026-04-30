//
//  311_EsangThread.swift
//  EusoTrip — Shipper · ESang AI · Thread (Arc I).
//

import SwiftUI

struct EsangThreadScreen: View {
    let theme: Theme.Palette
    let conversationId: String
    var body: some View {
        Shell(theme: theme) { EsangThreadBody(conversationId: conversationId) } nav: { shipperLifecycleNav() }
    }
}

private struct EsangChatMessage: Decodable, Identifiable, Hashable {
    let id: String
    let senderId: String?
    let senderName: String?
    let body: String
    let createdAt: String
    let isMine: Bool?
}

private struct EsangThreadBody: View {
    @Environment(\.palette) private var palette
    let conversationId: String
    @State private var messages: [EsangChatMessage] = []
    @State private var draft: String = ""
    @State private var sending: Bool = false
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 8)
            ScrollView { VStack(alignment: .leading, spacing: 8) { messagesList }.padding(.horizontal, 14).padding(.top, Space.s2) }
            composer
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · ESANG · THREAD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    @ViewBuilder
    private var messagesList: some View {
        if loading { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        else if let err = loadError { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
        else {
            ForEach(messages) { m in bubble(m) }
        }
    }

    private func bubble(_ m: EsangChatMessage) -> some View {
        HStack {
            if m.isMine == true { Spacer(minLength: 40) }
            VStack(alignment: m.isMine == true ? .trailing : .leading, spacing: 2) {
                Text(dashIfEmpty(m.senderName)).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text(m.body).font(EType.body).foregroundStyle(m.isMine == true ? .white : palette.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(m.isMine == true ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(m.isMine == true ? .clear : palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(humanISO(m.createdAt, format: "HH:mm")).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            if m.isMine != true { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical).lineLimit(1...4).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button { Task { await send() } } label: {
                if sending { ProgressView().tint(.white).frame(width: 36, height: 36).background(LinearGradient.diagonal).clipShape(Circle()) }
                else {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(LinearGradient.diagonal).clipShape(Circle())
                }
            }.buttonStyle(.plain).disabled(sending || draft.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(palette.bgCard.opacity(0.95))
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let conversationId: String }
        do {
            let m: [EsangChatMessage] = try await EusoTripAPI.shared.query("messaging.getMessages", input: In(conversationId: conversationId))
            messages = m
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func send() async {
        sending = true
        struct In: Encodable { let conversationId: String; let body: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("messaging.sendMessage", input: In(conversationId: conversationId, body: draft))
            draft = ""
            await load()
        } catch { /* surface inline */ }
        sending = false
    }
}

#Preview("311 · Thread · Night") {
    EsangThreadScreen(theme: Theme.dark, conversationId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("311 · Thread · Afternoon") {
    EsangThreadScreen(theme: Theme.light, conversationId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
