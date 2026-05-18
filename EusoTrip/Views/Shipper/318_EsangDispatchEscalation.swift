//
//  318_eSangDispatchEscalation.swift
//  EusoTrip — Shipper · eSang · Dispatch escalation (Arc I).
//

import SwiftUI

struct eSangDispatchEscalationScreen: View {
    let theme: Theme.Palette
    var loadId: String? = nil
    var body: some View {
        Shell(theme: theme) { EscalationBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct EscalationBody: View {
    @Environment(\.palette) private var palette
    let loadId: String?
    @State private var priority: String = "normal"
    @State private var note: String = ""
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("Escalated. Dispatcher will reach out within 5 minutes.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                priorityCard
                noteCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "phone.arrow.up.right.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESANG · DISPATCH ESCALATION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Escalate to a dispatcher").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var priorityCard: some View {
        LifecycleCard {
            LifecycleSection(label: "PRIORITY", icon: "flag")
            HStack(spacing: 8) {
                ForEach(["normal", "urgent", "critical"], id: \.self) { p in
                    Button { priority = p } label: {
                        Text(p.capitalized).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(priority == p ? .white : palette.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(priority == p ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var noteCard: some View {
        LifecycleCard {
            LifecycleSection(label: "NOTE", icon: "text.alignleft")
            TextField("What's happening?", text: $note, axis: .vertical).lineLimit(3...8).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        Button { Task { await send() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Escalating…" : "Escalate to dispatch")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending)
    }

    private func send() async {
        sending = true; actionError = nil
        struct In: Encodable { let loadId: String?; let priority: String; let note: String }
        struct Out: Decodable { let success: Bool; let ticketId: String? }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation(
                "support.createTicket",
                input: In(loadId: loadId, priority: priority, note: note)
            )
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("318 · Escalation · Night") { eSangDispatchEscalationScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("318 · Escalation · Afternoon") { eSangDispatchEscalationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
