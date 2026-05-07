//
//  255_PostLoadMultiStop.swift
//  EusoTrip — Shipper · Post-a-Load · Multi-stop builder.
//

import SwiftUI

struct PostLoadMultiStopScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { MultiStopBody(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

private struct MultiStopBody: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft
    @State private var newAddress: String = ""
    @State private var newContact: String = ""
    @State private var newPhone: String = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                listCard
                addCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "list.number").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · POST A LOAD · MULTI-STOP").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Add intermediate stops").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Drag to reorder. Each stop carries its own contact and appointment.").font(EType.body).foregroundStyle(palette.textSecondary)
        }
    }

    private var listCard: some View {
        LifecycleCard {
            LifecycleSection(label: "STOPS", icon: "list.bullet")
            if draft.stops.isEmpty {
                Text("No intermediate stops yet. Add one below.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(draft.stops.indices, id: \.self) { i in
                    HStack {
                        Text("\(draft.stops[i].sequence)")
                            .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(LinearGradient.diagonal).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.stops[i].address).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text(draft.stops[i].contactName.isEmpty ? "—" : draft.stops[i].contactName)
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            draft.stops.remove(at: i)
                            renumber()
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(Brand.danger)
                        }.buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var addCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "ADD STOP", icon: "plus.circle.fill")
            inputField(label: "Address", text: $newAddress, placeholder: "City, ST or full address")
            inputField(label: "Contact", text: $newContact, placeholder: "Optional contact name")
            inputField(label: "Phone",   text: $newPhone,   placeholder: "Optional phone")
            Button {
                guard !newAddress.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                draft.stops.append(PostLoadDraft.Stop(
                    sequence: draft.stops.count + 1,
                    address: newAddress,
                    contactName: newContact,
                    contactPhone: newPhone
                ))
                newAddress = ""; newContact = ""; newPhone = ""
            } label: {
                Text("Add stop").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    private func inputField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func renumber() {
        for i in draft.stops.indices { draft.stops[i].sequence = i + 1 }
    }

    private var ctaRow: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "250"])
        } label: {
            Text("Done").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }
}

#Preview("255 · Multi-stop · Night") {
    PostLoadMultiStopScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("255 · Multi-stop · Afternoon") {
    PostLoadMultiStopScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
