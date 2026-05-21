//
//  257_PostLoadHazmatSubform.swift
//  EusoTrip — Shipper · Post-a-Load · Hazmat sub-form.
//
//  UN # · class · packing group · proper shipping name · ERG · CHEMTREC.
//  Country-aware regulatory frame chips: 49 CFR (US) · NOM (MX) · ADR (EU)
//  · IMDG (vessel) · TDG (CA). Cross-border shows the trusted-trader
//  programs (CTPAT / FAST / OEA) the load may qualify for.
//

import SwiftUI

struct PostLoadHazmatSubformScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { HazmatBody(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

private struct HazmatBody: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    private let classes = ["1", "2.1", "2.2", "2.3", "3", "4.1", "4.2", "4.3", "5.1", "5.2", "6.1", "6.2", "7", "8", "9"]
    private let pgs = ["I", "II", "III"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                regulatoryChips
                idCard
                classificationCard
                psnCard
                ergCard
                // 2026-05-20 · IO 2026 P0-8 — ERG copilot + segregation.
                ergCopilotCard
                segregationCard
                chemtrecCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    // ─── 2026-05-20 · IO 2026 P0-8 · ERG copilot panel ──────────────
    //
    // Multi-turn conversation grounded in the canonical ERG guide.
    // Reuses `ERGLookupService.askFollowUp` shipped in P0-7 — same
    // thought-signature cache keyed by UN number, same dialect-aware
    // reply (P0-4). Surfaces directly under the existing ergCard so
    // the shipper composing the load can ask "What if it spills?",
    // "Can I haul with class 3?", etc. without leaving the wizard.

    @State private var copilotQuestion: String = ""
    @State private var copilotAnswer: String? = nil
    @State private var copilotAsking: Bool = false
    @State private var copilotError: String? = nil

    @State private var segregationPartnerClass: String = ""
    @State private var segregationResult: SegregationVerdict? = nil
    @State private var segregationChecking: Bool = false

    private struct SegregationVerdict: Hashable {
        let verdict: String
        let reason: String
        let citation: String?
        let classA: String?
        let classB: String?
    }

    @ViewBuilder
    private var ergCopilotCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ESANG ERG COPILOT", icon: "sparkles")
            Text("Ask anything about UN \(draft.unNumber.isEmpty ? "—" : draft.unNumber).")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            HStack(spacing: 8) {
                TextField("e.g. \"What if it spills?\"", text: $copilotQuestion, axis: .horizontal)
                    .textFieldStyle(.plain).autocorrectionDisabled(true)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .submitLabel(.send)
                    .onSubmit { Task { await askCopilot() } }
                Button {
                    Task { await askCopilot() }
                } label: {
                    Group {
                        if copilotAsking {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(draft.unNumber.trimmingCharacters(in: .whitespaces).isEmpty || copilotQuestion.trimmingCharacters(in: .whitespaces).isEmpty || copilotAsking)
            }
            if let err = copilotError {
                Text(err).font(.system(size: 11)).foregroundStyle(.red)
            }
            if let answer = copilotAnswer {
                Text(answer)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.tintNeutral, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var segregationCard: some View {
        LifecycleCard {
            LifecycleSection(label: "SEGREGATION CHECK · 49 CFR 177.848", icon: "rectangle.split.2x1")
            Text("Pick a partner class to verify it can ride with class \(draft.hazmatClass.isEmpty ? "—" : draft.hazmatClass) on the same trailer.")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(classes, id: \.self) { c in
                        Button { Task { await runSegregationCheck(partnerClass: c) } } label: {
                            Text(c).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(segregationPartnerClass == c ? .white : palette.textPrimary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(segregationPartnerClass == c
                                            ? AnyShapeStyle(LinearGradient.diagonal)
                                            : AnyShapeStyle(palette.tintNeutral))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if segregationChecking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
            if let result = segregationResult {
                segregationVerdictView(result)
            }
        }
    }

    @ViewBuilder
    private func segregationVerdictView(_ result: SegregationVerdict) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                let (sym, color) = segregationSymbol(verdict: result.verdict)
                Image(systemName: sym).foregroundStyle(color)
                Text(result.verdict.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(color)
            }
            Text(result.reason)
                .font(.system(size: 12))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let citation = result.citation {
                Text(citation)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintNeutral, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func segregationSymbol(verdict: String) -> (String, Color) {
        switch verdict {
        case "compatible":           return ("checkmark.seal.fill", .green)
        case "separation_required":  return ("rectangle.split.2x1.fill", .orange)
        case "incompatible":         return ("xmark.octagon.fill", .red)
        default:                     return ("questionmark.circle.fill", .yellow)
        }
    }

    @MainActor
    private func askCopilot() async {
        let un = draft.unNumber.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "UN", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "NA", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        let q  = copilotQuestion.trimmingCharacters(in: .whitespaces)
        guard !un.isEmpty, !q.isEmpty else { return }
        copilotAsking = true
        copilotError = nil
        defer { copilotAsking = false }
        do {
            let reply = try await ERGLookupService.shared.askFollowUp(
                unNumber: un, question: q
            )
            copilotAnswer = reply.answer
            copilotQuestion = ""
        } catch {
            copilotError = "Couldn't reach ESang: \((error as NSError).localizedDescription)"
        }
    }

    @MainActor
    private func runSegregationCheck(partnerClass: String) async {
        let primary = draft.hazmatClass.trimmingCharacters(in: .whitespaces)
        guard !primary.isEmpty else {
            segregationResult = SegregationVerdict(
                verdict: "unknown",
                reason: "Pick a primary class first, then a partner class.",
                citation: nil, classA: nil, classB: nil
            )
            return
        }
        segregationPartnerClass = partnerClass
        segregationChecking = true
        defer { segregationChecking = false }
        do {
            struct In: Encodable { let classA: String; let classB: String }
            struct Out: Decodable {
                let verdict: String
                let reason: String
                let citation: String?
                let classA: String?
                let classB: String?
            }
            let reply: Out = try await EusoTripAPI.shared.mutation(
                "compliance.segregationCheck",
                input: In(classA: primary, classB: partnerClass)
            )
            segregationResult = SegregationVerdict(
                verdict: reply.verdict,
                reason: reply.reason,
                citation: reply.citation,
                classA: reply.classA,
                classB: reply.classB
            )
        } catch {
            segregationResult = SegregationVerdict(
                verdict: "unknown",
                reason: "Couldn't reach segregation service: \((error as NSError).localizedDescription)",
                citation: nil, classA: primary, classB: partnerClass
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "triangle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("SHIPPER · POST A LOAD · HAZMAT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.warning)
            }
            Text("Hazmat fields").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var regulatoryChips: some View {
        let frames = applicableFrames
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(frames, id: \.self) { frame in
                    Text(frame).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }
            }
        }
    }

    private var applicableFrames: [String] {
        var f: [String] = []
        if [PostLoadDraft.Country.US].contains(draft.originCountry) || [PostLoadDraft.Country.US].contains(draft.destinationCountry) {
            f.append("US 49 CFR 172/173/177")
        }
        if [PostLoadDraft.Country.CA].contains(draft.originCountry) || [PostLoadDraft.Country.CA].contains(draft.destinationCountry) {
            f.append("CA TDG")
        }
        if [PostLoadDraft.Country.MX].contains(draft.originCountry) || [PostLoadDraft.Country.MX].contains(draft.destinationCountry) {
            f.append("MX NOM-002-SCT")
        }
        if [PostLoadDraft.Country.EU, .UK].contains(draft.originCountry) || [PostLoadDraft.Country.EU, .UK].contains(draft.destinationCountry) {
            f.append("EU ADR")
        }
        if draft.mode == .vessel {
            f.append("IMDG")
        }
        if draft.mode == .rail {
            f.append("US 49 CFR 174 (rail)")
        }
        if draft.isUSMCA {
            f.append("USMCA · CTPAT-eligible")
        }
        return f
    }

    private var idCard: some View {
        LifecycleCard(accentWarning: true) {
            LifecycleSection(label: "UN NUMBER", icon: "number")
            TextField("e.g. UN1203", text: $draft.unNumber)
                .textFieldStyle(.plain).autocorrectionDisabled(true)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var classificationCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CLASS + PG", icon: "tag")
            Text("CLASS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(classes, id: \.self) { c in
                        Button { draft.hazmatClass = c } label: {
                            Text(c).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(draft.hazmatClass == c ? .white : palette.textPrimary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(draft.hazmatClass == c ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            Text("PACKING GROUP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 6)
            HStack(spacing: 6) {
                ForEach(pgs, id: \.self) { pg in
                    Button { draft.packingGroup = pg } label: {
                        Text(pg).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(draft.packingGroup == pg ? .white : palette.textPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(draft.packingGroup == pg ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var psnCard: some View {
        LifecycleCard {
            LifecycleSection(label: "PROPER SHIPPING NAME", icon: "doc.text")
            TextField("e.g. Gasoline", text: $draft.properShippingName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ergCard: some View {
        LifecycleCard {
            LifecycleSection(label: "ERG GUIDE #", icon: "book")
            TextField("e.g. 128", value: $draft.ergGuide, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var chemtrecCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CHEMTREC PHONE", icon: "phone")
            TextField("e.g. 1-800-424-9300", text: $draft.chemtrecPhone)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "251"])
        } label: {
            Text("Done").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }
}

#Preview("257 · Hazmat · Night") {
    PostLoadHazmatSubformScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("257 · Hazmat · Afternoon") {
    PostLoadHazmatSubformScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
