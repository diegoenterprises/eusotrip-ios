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

    // ESANG document router — classify the evidence so the claim file
    // knows what it's looking at (damage photo / BOL / POD) instead of
    // shipping a raw image. Runs alongside, never blocks, the upload.
    @State private var classifying = false
    @State private var classification: DocumentRouterAPI.ClassifyResponse? = nil
    @State private var classifyError: String? = nil

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
                Task {
                    classification = nil; classifyError = nil
                    guard let i = item,
                          let data = try? await i.loadTransferable(type: Data.self),
                          let img = UIImage(data: data) else { return }
                    photo = img
                    await classifyEvidence(data: data)
                }
            }
            if let img = photo {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            classificationPanel
        }
    }

    @ViewBuilder
    private var classificationPanel: some View {
        if classifying {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7).tint(palette.textPrimary)
                Text("Identifying evidence…").font(EType.caption).foregroundStyle(palette.textTertiary)
            }
        } else if let err = classifyError {
            Text("Couldn't auto-identify this evidence — \(err). Your photo will still be filed with the claim.")
                .font(EType.caption).foregroundStyle(Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
        } else if let c = classification {
            let conf = Int((c.confidence * 100).rounded())
            let unsure = c.classifiedType == "unknown" || c.confidence < 0.6
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("ESANG · EVIDENCE DETECTED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer(minLength: 0)
                    Text("\(conf)%")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(conf >= 85 ? Brand.success : conf >= 60 ? Brand.warning : Brand.danger)
                }
                if unsure {
                    Text("Couldn't confidently identify this document — please confirm it's the right evidence for the claim.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(humanEvidenceType(c.classifiedType))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                if !c.summary.isEmpty {
                    Text(c.summary).font(EType.caption).foregroundStyle(palette.textSecondary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                let keyFields = c.extractedFields.compactMap { (k, v) -> String? in
                    guard let s = v.asString, !s.isEmpty else { return nil }
                    return "\(k.replacingOccurrences(of: "_", with: " ").capitalized): \(s)"
                }.sorted()
                if !keyFields.isEmpty {
                    ForEach(keyFields.prefix(4), id: \.self) { f in
                        Text(f).font(EType.caption).foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                ForEach(c.warnings.prefix(2), id: \.self) { w in
                    Text("⚠ \(w)").font(EType.caption).foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(palette.bgCard.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func humanEvidenceType(_ raw: String) -> String {
        switch raw {
        case "bill_of_lading": return "Bill of Lading"
        case "proof_of_delivery": return "Proof of Delivery"
        case "rate_confirmation": return "Rate Confirmation"
        case "weight_ticket", "scale_ticket": return "Weight Ticket"
        case "damage_photo", "cargo_damage", "damage": return "Damage Photo"
        case "inspection_report": return "Inspection Report"
        case "us_coi", "ca_coi": return "Insurance Certificate"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    @MainActor
    private func classifyEvidence(data: Data) async {
        classifying = true; classification = nil; classifyError = nil
        defer { classifying = false }
        // Compress oversized payloads to keep the wire light, mirroring
        // the upload's jpeg encoding.
        let payload: Data
        let mime: DocumentRouterAPI.MimeType
        if data.count > 900_000, let img = UIImage(data: data),
           let small = img.jpegData(compressionQuality: 0.7) {
            payload = small; mime = .jpeg
        } else {
            payload = data
            mime = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? .png : .jpeg
        }
        do {
            classification = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: payload.base64EncodedString(),
                mimeType: mime,
                callerContext: "freight claim evidence"
            )
        } catch {
            classifyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
