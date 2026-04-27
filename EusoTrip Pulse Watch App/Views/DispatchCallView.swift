//
//  DispatchCallView.swift
//  EusoTrip Watch App
//
//  Confirmation sheet when the driver (or a voice action) requests a
//  call to dispatch. Watch can't dial a number on its own unless there's
//  a cellular model paired — so we hand off to the iPhone, which has
//  the dispatcher contact and can place the call.
//

import SwiftUI
import WatchKit

struct DispatchCallView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: S.s2) {
                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient.esangPrimary)

                Text("Call Dispatch")
                    .font(.system(size: 14, weight: .bold))
                Text("Placing call on your iPhone.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    WKInterfaceDevice.current().play(.click)
                    connectivity.requestPhoneActivation(
                        transcript: "call dispatch",
                        reply: "Dialing dispatch on your iPhone."
                    )
                    Task {
                        _ = try? await EsangClient(auth: auth).mutateJSON(
                            "dispatch.requestCall",
                            input: ["source": "watch"]
                        )
                    }
                    dismiss()
                } label: {
                    Label("Open on iPhone", systemImage: "iphone.and.arrow.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: R.sm))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
            .padding(S.s2)
        }
        .navigationTitle("Dispatch")
        // Brand-gradient "Open on iPhone" button + phone circle glyph
        // are vivid; clip to the bezel so they don't bleed past the
        // rounded corners when the sheet presents.
        .clipShape(ContainerRelativeShape())
    }
}
