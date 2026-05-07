//
//  386_FreightClaimComposer.swift
//  EusoTrip — Shipper · Freight claim composer (Arc N).
//

import SwiftUI
import PhotosUI

struct FreightClaimComposerScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var initialClaimType: String = "damage"
    var body: some View {
        Shell(theme: theme) { ClaimComposerBody(loadId: loadId, claimType: initialClaimType) } nav: { shipperLifecycleNav() }
    }
}

private struct ClaimComposerBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State var claimType: String
    @State private var amount: Double? = nil
    @State private var description: String = ""
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photo: UIImage? = nil
    @State private var sending = false
    @State private var sent = false
    @State private var actionError: String? = nil

    private let claimTypes = ["damage", "shortage", "loss", "delay", "contamination", "reefer_excursion", "other"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("Claim filed. Carrier insurance + Eusorone ops will respond within 24 hours.").font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                typeCard
                amountCard
                descriptionCard
                evidenceCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("SHIPPER · FREIGHT CLAIM").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.warning)
            }
            Text("File a freight claim").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var typeCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CLAIM TYPE", icon: "tag")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(claimTypes, id: \.self) { t in
                        Button { claimType = t } label: {
                            Text(t.replacingOccurrences(of: "_", with: " ").capitalized).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(claimType == t ? .white : palette.textPrimary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(claimType == t ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var amountCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CLAIM AMOUNT (USD)", icon: "dollarsign.circle")
            TextField("e.g. 2400", value: $amount, format: .number).keyboardType(.decimalPad).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var descriptionCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DESCRIPTION", icon: "text.alignleft")
            TextField("What happened, when, where?", text: $description, axis: .vertical).lineLimit(4...10).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var evidenceCard: some View {
        LifecycleCard {
            LifecycleSection(label: "EVIDENCE PHOTO", icon: "photo")
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(photo == nil ? "Attach photo" : "Replace photo")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .onChange(of: photoItem) { _, item in
                Task { if let i = item, let data = try? await i.loadTransferable(type: Data.self), let img = UIImage(data: data) { photo = img } }
            }
            if let img = photo {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var ctaRow: some View {
        Button { Task { await fileClaim() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Filing…" : "File claim").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || amount == nil || description.isEmpty)
    }

    private func fileClaim() async {
        sending = true; actionError = nil
        struct In: Encodable {
            let loadId: String; let claimType: String; let amount: Double; let description: String; let evidenceBase64: String?
        }
        struct Out: Decodable { let success: Bool; let claimId: String? }
        let evidenceB64 = photo?.jpegData(compressionQuality: 0.85)?.base64EncodedString()
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("freightClaims.fileClaim", input: In(loadId: loadId, claimType: claimType, amount: amount ?? 0, description: description, evidenceBase64: evidenceB64))
            sent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("386 · Claim composer · Night") { FreightClaimComposerScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("386 · Claim composer · Afternoon") { FreightClaimComposerScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
