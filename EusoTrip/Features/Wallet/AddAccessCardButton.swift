//
//  AddAccessCardButton.swift
//  EusoTrip — the ONE reusable entry point for the STAFF ACCESS CARD, the
//  sibling of AddToWalletButton (which owns the pickup pass). Drop this on the
//  terminal/staff surface (703 Terminal Me) to offer "Add access card to
//  Wallet": tap → present the SAME bespoke card-style picker
//  (WalletCardPickerView) in a sheet, in ACCESS mode, so the access card is
//  minted with the user's chosen theme.
//
//  GROUNDED, NOT FABRICATED: the minted pass wraps the staff member's REAL
//  temporary access token (server `staffAccessTokens`, issued by
//  `terminals.generateAccessLink`). The button never invents an access code —
//  it asks the server to sign the themed pass for the caller's existing grant
//  via `terminals.createStaffAccessCredential` (the signing proc being built on
//  that grant), and falls back to the inline QR + 6-digit code when PassKit
//  isn't yet wired.
//
//  Usage:
//    AddAccessCardButton()                 // full-width primary button
//    AddAccessCardButton(compact: true)    // inline pill (toolbars / rows)
//    AddAccessCardButton { myBrandedTile }  // bespoke label, same picker behavior
//
//  TARGET: EusoTrip/Features/Wallet/AddAccessCardButton.swift
//

import SwiftUI

/// Reusable Add-Access-Card entry. Generic over its label so bespoke surfaces
/// can keep their own visual tile while still routing through the one
/// picker-sheet behavior — no duplicated nav logic. Presents the shared
/// `WalletCardPickerView` in ACCESS mode.
struct AddAccessCardButton<Label: View>: View {
    @ViewBuilder var label: () -> Label
    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: { label() }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPicker) {
                NavigationStack { WalletCardPickerView(mode: .staffAccess) }
                    .presentationDragIndicator(.visible)
            }
            .accessibilityLabel("Add staff access card to Apple Wallet")
            .accessibilityHint("Pick a card style, then add your access card to Wallet")
    }
}

// MARK: - Default label (the standard primary / compact button)
//
// The convenience init keeps simple call sites terse
// (`AddAccessCardButton()`, `AddAccessCardButton(compact: true)`) and renders
// the canonical bordered-prominent button.
extension AddAccessCardButton where Label == DefaultAddAccessCardLabel {
    init(compact: Bool = false, title: String = "Add access card to Wallet") {
        self.init { DefaultAddAccessCardLabel(compact: compact, title: title) }
    }
}

struct DefaultAddAccessCardLabel: View {
    var compact: Bool = false
    var title: String = "Add access card to Wallet"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wallet.pass")
            Text(compact ? "Access card" : title).bold()
        }
        .frame(maxWidth: compact ? nil : .infinity)
        .frame(height: compact ? 36 : 50)
        .padding(.horizontal, compact ? 14 : 0)
        .foregroundStyle(.white)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
