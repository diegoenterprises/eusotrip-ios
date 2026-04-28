//
//  256_PostLoadAddressPicker.swift
//  EusoTrip — Shipper · Post-a-Load · Address picker.
//
//  Tries `users.getSavedAddresses` (server may not have it yet —
//  surfaces an em-dash empty state if so). Manual address entry is
//  always available.
//

import SwiftUI

struct PostLoadAddressPickerScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    /// Which slot to fill: "origin" or "destination" or "stop_N".
    var slot: String = "origin"
    var body: some View {
        Shell(theme: theme) {
            AddressPickerBody(draft: draft, slot: slot)
        } nav: { shipperLifecycleNav() }
    }
}

private struct SavedAddress: Decodable, Identifiable, Hashable {
    let id: Int
    let label: String?
    let address: String
    let city: String?
    let state: String?
}

private struct AddressPickerBody: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft
    let slot: String

    @State private var manual: String = ""
    @State private var saved: [SavedAddress] = []
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                manualCard
                savedCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAddresses() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · ADDRESS PICKER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pick or enter an address").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var manualCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ENTER ADDRESS", icon: "pencil")
            TextField("Full address or City, ST", text: $manual)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button {
                apply(address: manual)
            } label: {
                Text("Use this address").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var savedCard: some View {
        if loading {
            LifecycleCard {
                LifecycleSection(label: "SAVED ADDRESSES", icon: "bookmark")
                Text("Loading saved addresses…").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) {
                LifecycleSection(label: "SAVED ADDRESSES", icon: "bookmark")
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if saved.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "SAVED ADDRESSES", icon: "bookmark")
                Text("No saved addresses yet. Save lanes from the post-a-load wizard or the web shipper page to populate this list.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            LifecycleCard {
                LifecycleSection(label: "SAVED ADDRESSES", icon: "bookmark")
                ForEach(saved) { row in
                    Button {
                        apply(address: format(row))
                    } label: {
                        HStack {
                            Image(systemName: "bookmark.fill").foregroundStyle(LinearGradient.diagonal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dashIfEmpty(row.label)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                                Text(format(row)).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                        }
                        .padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func format(_ a: SavedAddress) -> String {
        [a.address, [a.city, a.state].compactMap { $0 }.joined(separator: ", ")]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func apply(address: String) {
        switch slot {
        case "origin":      draft.origin = address
        case "destination": draft.destination = address
        default:            break
        }
        NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "250"])
    }

    private func loadAddresses() async {
        loading = true; loadError = nil
        // The server doesn't have `users.getSavedAddresses` yet (per
        // §5 audit). When it ships, swap the queryNoInput call here
        // and remove the empty-state. Until then surface the empty
        // state so manual entry is the path of least resistance.
        struct Empty: Decodable {}
        do {
            let _ : Empty = try await EusoTripAPI.shared.api.queryNoInput("users.getSavedAddresses")
            // If the call returns an array, decode it into `saved` —
            // but the endpoint shape is undefined, so this branch is
            // documentation more than code. Keeping `saved` empty is
            // the safe path until the server contract is concrete.
        } catch {
            // Suppress error noise on missing endpoint — surface the
            // empty state instead.
            saved = []
        }
        loading = false
    }
}

#Preview("256 · Address picker · Night") {
    PostLoadAddressPickerScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("256 · Address picker · Afternoon") {
    PostLoadAddressPickerScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
