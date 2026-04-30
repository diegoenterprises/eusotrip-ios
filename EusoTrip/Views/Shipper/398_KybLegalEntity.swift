//
//  398_KybLegalEntity.swift
//  EusoTrip — Shipper · KYB · legal entity (Arc B+ / Arc A onboarding).
//

import SwiftUI

struct KybLegalEntityScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { KybLegalBody() } nav: { shipperLifecycleNav() }
    }
}

private struct KybLegalBody: View {
    @Environment(\.palette) private var palette
    @State private var legalName: String = ""
    @State private var ein: String = ""
    @State private var duns: String = ""
    @State private var dotNumber: String = ""
    @State private var mcNumber: String = ""
    @State private var sending = false
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                fieldsCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.below.ecg").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("EUSOTRIP · KYB · LEGAL ENTITY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Tell us about your business").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Required for compliance + insurance + payments. Encrypted at rest.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ENTITY", icon: "building.columns")
            field("Legal name", text: $legalName)
            field("EIN (US) / BN (Canada) / RFC (Mexico)", text: $ein)
            field("DUNS (optional)", text: $duns)
            field("USDOT (if applicable)", text: $dotNumber)
            field("MC (if applicable)", text: $mcNumber)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField(label, text: text).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Submitting…" : "Continue").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || legalName.isEmpty || ein.isEmpty)
    }

    private func save() async {
        sending = true; actionError = nil
        struct In: Encodable {
            let legalName: String; let ein: String; let duns: String?
            let dotNumber: String?; let mcNumber: String?
        }
        struct Out: Decodable { let success: Bool; let kybId: String? }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation(
                "kyb.submit",
                input: In(legalName: legalName, ein: ein, duns: duns.isEmpty ? nil : duns,
                          dotNumber: dotNumber.isEmpty ? nil : dotNumber,
                          mcNumber: mcNumber.isEmpty ? nil : mcNumber)
            )
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "399"])
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("398 · KYB · Night") { KybLegalEntityScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("398 · KYB · Afternoon") { KybLegalEntityScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
