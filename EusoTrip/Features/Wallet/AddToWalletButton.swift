//
//  AddToWalletButton.swift
//  EusoTrip — the ONE reusable entry point. Drop this on every surface that should
//  offer the pickup pass (load detail, post-booking, driver active-load, etc.) so the
//  picker + themed Add-to-Wallet behave identically everywhere ("across the board").
//
//  It owns the single source of truth for the entry behavior: tap → present the
//  bespoke card-style picker (WalletCardPickerView) in a sheet, pre-seeded with the
//  load so the picker can mint + add the THEMED Apple Wallet pickup pass.
//
//  Usage:
//    AddToWalletButton(loadId: load.id)                 // full-width primary button
//    AddToWalletButton(loadId: load.id, compact: true)  // inline pill (lists / toolbars)
//    // bespoke surfaces supply their own label but reuse the SAME picker behavior:
//    AddToWalletButton(loadId: load.id) { myBrandedTile }
//
//  TARGET: EusoTrip/Features/Wallet/AddToWalletButton.swift
//

import SwiftUI

/// Reusable Add-to-Wallet entry. Generic over its label so bespoke surfaces (e.g.
/// the 205 load-detail document strip) can keep their own visual tile while still
/// routing through the one picker-sheet behavior — no duplicated nav logic.
struct AddToWalletButton<Label: View>: View {
    let loadId: String
    @ViewBuilder var label: () -> Label
    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: { label() }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPicker) {
                NavigationStack { WalletCardPickerView(loadId: loadId) }
                    .presentationDragIndicator(.visible)
            }
            .accessibilityLabel("Add pickup pass to Apple Wallet")
            .accessibilityHint("Pick a card style, then add it to Wallet")
    }
}

// MARK: - Default label (the standard primary / compact button)
//
// The convenience init keeps the original call sites working
// (`AddToWalletButton(loadId:)`, `AddToWalletButton(loadId:compact:)`) and renders
// the canonical bordered-prominent button.
extension AddToWalletButton where Label == DefaultAddToWalletLabel {
    init(loadId: String, compact: Bool = false, title: String = "Add to Apple Wallet") {
        self.init(loadId: loadId) { DefaultAddToWalletLabel(compact: compact, title: title) }
    }
}

struct DefaultAddToWalletLabel: View {
    var compact: Bool = false
    var title: String = "Add to Apple Wallet"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wallet.pass")
            Text(compact ? "Wallet" : title).bold()
        }
        .frame(maxWidth: compact ? nil : .infinity)
        .frame(height: compact ? 36 : 50)
        .padding(.horizontal, compact ? 14 : 0)
        .foregroundStyle(.white)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
