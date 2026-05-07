//
//  084_MeDataQsFiler.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · DataQs challenge filer)
//
//  Screen 084 · Me · DataQs Challenge Filer — the iOS entry point
//  for filing a Request for Data Review (RDR) with FMCSA against a
//  specific CSA-reported violation. Closes the compliance triangle:
//  081 ELD Logs Detail (driver self-certification) → 082 Violations
//  Manager (internal carrier resolution) → 084 DataQs (federal
//  record correction).
//
//  DataQs (dataqs.fmcsa.dot.gov) is the canonical path under
//  49 CFR §386 for a carrier / driver to contest an FMCSA-reported
//  safety event — incorrect vehicle id on a roadside inspection,
//  misattributed hazmat violation, expired data, etc. 084 collects
//  the RDR payload, lets the driver attach supporting documents
//  from their 083 Documents Hub, and round-trips through
//  `csaScores.submitDataQsChallenge` — MCP-verified at
//  `frontend/server/routers/csaScores.ts:310`.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Violation picker sources rows from the same live
//      `compliance.getViolations` call the Violations Manager uses
//      (via `ViolationsStore`) — both surfaces stay in sync.
//
//    • Supporting-docs picker sources rows from the live
//      `documentManagement.getDocuments` call 083 / 072 use (via
//      `DriverDocumentsStore`), multi-select with checkbox toggle.
//
//    • Submit round-trips through the real procedure; the response's
//      `challengeId` + estimated 60-day FMCSA response window are
//      surfaced to the driver exactly as the server returned them.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on Submit CTA + confirmation seal.
//         Brand.warning only for reason-tile selected state when
//         "not_responsible" or similar escalatory reason is chosen.
//    §4   Tokenized spacing, radii, type.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews land in `.error` under the preview runtime. No
//         fixtures.
//

import SwiftUI

// MARK: - Reason enum (matches server)

private enum DataQsReason: String, CaseIterable, Identifiable {
    case incorrectData    = "incorrect_data"
    case notResponsible   = "not_responsible"
    case documentationErr = "documentation_error"
    case other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .incorrectData:    return "Incorrect data"
        case .notResponsible:   return "Not responsible"
        case .documentationErr: return "Documentation error"
        case .other:            return "Other"
        }
    }
    var blurb: String {
        switch self {
        case .incorrectData:
            return "The underlying FMCSA record contains wrong facts (vehicle id, date, violation code)."
        case .notResponsible:
            return "Carrier / driver was not responsible for this event (e.g. misattributed to the wrong carrier at roadside)."
        case .documentationErr:
            return "Supporting documentation exists that wasn't reviewed — this filing submits it."
        case .other:
            return "Another reason not covered above. Explain in detail below."
        }
    }
}

// MARK: - Screen root

struct MeDataQsFiler: View {
    @Environment(\.palette) var palette
    @StateObject private var violations = ViolationsStore()
    @StateObject private var documents = DriverDocumentsStore()

    @State private var selectedViolation: UnifiedViolation?
    @State private var reason: DataQsReason = .incorrectData
    @State private var explanation: String = ""
    @State private var selectedDocIds: Set<String> = []

    @State private var isSubmitting: Bool = false
    @State private var submittedResult: CsaScoresAPI.DataQsChallengeResponse?
    @State private var lastToast: String?

    // ESANG-assisted draft (Gemini via dataqs.aiDraft).
    @State private var isDrafting: Bool = false
    @State private var draftRisk: String?
    @State private var draftReasoning: String?
    @State private var draftChecklist: [String] = []
    @State private var draftRegulations: [String] = []

    // Recent filings (dataqs.listMine).
    @State private var recentFilings: [DataQsAPI.Filing] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                if let result = submittedResult {
                    submittedConfirmation(result)
                } else {
                    violationPicker
                    reasonPicker
                    explanationEditor
                    aiAssistRibbon
                    aiDraftCard
                    supportingDocsPicker
                    submitCTA
                }
                recentFilingsSection
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await loadEverything() }
        .refreshable { await loadEverything() }
        .overlay(alignment: .bottom) {
            if let toast = lastToast {
                toastView(toast)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s6)
                    .transition(.opacity)
            }
        }
    }

    private func loadEverything() async {
        // Show open inspection-backed violations only — the only
        // kind that can actually be challenged with DataQs. HOS
        // violations are engine-computed from the driver's own logs
        // and aren't DataQs-contestable.
        violations.status = "open"
        async let a: Void = violations.refresh()
        async let b: Void = documents.refresh()
        async let c: Void = loadRecentFilings()
        _ = await (a, b, c)
    }

    /// Pull the last 25 RDR filings for this user/company so the
    /// driver can see what's already in flight without leaving 084.
    private func loadRecentFilings() async {
        do {
            let resp = try await EusoTripAPI.shared.dataqs.listMine(limit: 25)
            await MainActor.run { self.recentFilings = resp.rows }
        } catch {
            await MainActor.run { self.recentFilings = [] }
        }
    }

    /// Fire ESANG (Gemini) to draft the challenge statement. Reform-aware:
    /// the server prompt cites 49 CFR 386 + the 2026 burden-of-proof rule
    /// + Missouri/Nebraska state-trooper guidance against frivolous
    /// filings. Returns a structured draft we surface here.
    private func runAIDraft() async {
        guard let v = selectedViolation, !isDrafting else { return }
        isDrafting = true
        defer { Task { @MainActor in self.isDrafting = false } }
        let driverFacts = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        let carrierFacts = "\(v.title) — \(v.subtitle). Severity: \(v.severity)."
        do {
            let draft = try await EusoTripAPI.shared.dataqs.aiDraft(
                .init(
                    requestType: reason == .notResponsible ? "csa_violation" : "inspection_violation",
                    violationCode: nil,
                    eventDate: nil,
                    jurisdiction: nil,
                    issuingOfficer: nil,
                    carrierFacts: carrierFacts,
                    driverAccount: driverFacts.isEmpty ? nil : driverFacts
                )
            )
            await MainActor.run {
                if draft.available && !draft.challengeStatement.isEmpty {
                    self.explanation = draft.challengeStatement
                }
                self.draftRisk = draft.frivolousClaimRisk
                self.draftReasoning = draft.reasoning
                self.draftChecklist = draft.evidenceChecklist
                self.draftRegulations = draft.regulationsCited ?? []
            }
        } catch {
            await MainActor.run {
                self.flashToast("ESANG draft unavailable")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("DataQs RDR")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("49 CFR §386 · FMCSA record correction")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: isSubmitting ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Violation picker

    @ViewBuilder
    private var violationPicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("VIOLATION TO CHALLENGE")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            switch violations.state {
            case .loading:
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 72)
            case .empty, .error:
                emptyViolationsCard
            case .loaded(let rows):
                // Filter to inspection-backed rows only — HOS can't
                // be DataQs-challenged.
                let eligible = rows.filter {
                    if case .compliance = $0.kind { return true }
                    return false
                }
                if eligible.isEmpty {
                    emptyViolationsCard
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(eligible) { v in
                            violationOption(v)
                        }
                    }
                }
            }
        }
    }

    private var emptyViolationsCard: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text("No open inspection violations on your record. DataQs only accepts challenges against specific FMCSA-reported events.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            Spacer()
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    private func violationOption(_ v: UnifiedViolation) -> some View {
        let selected = selectedViolation?.id == v.id
        return Button {
            selectedViolation = v
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textSecondary))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.s2) {
                        Text(v.kindLabel)
                            .font(EType.micro).tracking(1.2)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
                            )
                        Text(v.severity.uppercased())
                            .font(EType.micro).tracking(1.2)
                            .foregroundStyle(v.severity == "critical" ? Brand.warning : palette.textTertiary)
                    }
                    Text(v.title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                    Text(v.subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Reason picker

    private var reasonPicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CHALLENGE REASON")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(DataQsReason.allCases) { r in
                    reasonTile(r)
                }
            }
        }
    }

    private func reasonTile(_ r: DataQsReason) -> some View {
        let on = r == reason
        return Button {
            reason = r
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textSecondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(r.blurb)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(on ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Explanation editor

    private var explanationEditor: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("EXPLANATION")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            TextEditor(text: $explanation)
                .frame(minHeight: 140)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCardSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
            Text("Be specific. FMCSA reviewers look for concrete facts — dates, location, ELD record id, names. Vague narratives usually result in denial.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: ESANG AI assist (Gemini-backed draft)

    @ViewBuilder
    private var aiAssistRibbon: some View {
        let canDraft = selectedViolation != nil && !isDrafting
        Button {
            Task { await runAIDraft() }
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(isDrafting ? "ESANG drafting…" : "ESANG · draft challenge statement")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if isDrafting {
                    ProgressView().progressViewStyle(.circular).controlSize(.small)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canDraft)
        .opacity(canDraft ? 1.0 : 0.5)
    }

    @ViewBuilder
    private var aiDraftCard: some View {
        let hasDraft = (draftRisk != nil) || !draftChecklist.isEmpty
        if hasDraft {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Text("ESANG GUIDANCE")
                        .font(EType.micro).tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if let risk = draftRisk {
                        let isHighRisk = risk.lowercased() == "high"
                        Text("FRIVOLOUS RISK · \(risk.uppercased())")
                            .font(EType.micro).tracking(1.1)
                            .foregroundStyle(isHighRisk ? Brand.warning : palette.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().strokeBorder(
                                    isHighRisk ? Brand.warning.opacity(0.6) : palette.borderFaint,
                                    lineWidth: 1
                                )
                            )
                    }
                }
                if let reasoning = draftReasoning, !reasoning.isEmpty {
                    Text(reasoning)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !draftChecklist.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("EVIDENCE CHECKLIST")
                            .font(EType.micro).tracking(1.2)
                            .foregroundStyle(palette.textTertiary)
                        ForEach(Array(draftChecklist.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: Space.s2) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(LinearGradient.diagonal)
                                Text(item)
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                if !draftRegulations.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textTertiary)
                        Text(draftRegulations.joined(separator: " · "))
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        }
    }

    // MARK: Recent filings (history of RDRs already filed)

    @ViewBuilder
    private var recentFilingsSection: some View {
        if !recentFilings.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("RECENT FILINGS")
                        .font(EType.micro).tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(recentFilings.count)")
                        .font(EType.micro).tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(spacing: Space.s2) {
                    ForEach(recentFilings.prefix(8)) { f in
                        recentFilingRow(f)
                    }
                }
            }
        }
    }

    private func recentFilingRow(_ f: DataQsAPI.Filing) -> some View {
        let statusUpper = f.status.replacingOccurrences(of: "_", with: " ").uppercased()
        let isResolved = f.resolvedAt != nil
        let isApproved = f.status.lowercased() == "approved"
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text(f.requestType.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(EType.micro).tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
                    Text("#\(f.referenceNumber)")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Text(f.challengeStatement)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if let dueIso = f.expectedReplyBy, let due = shortDate(dueIso) {
                    Text(isResolved ? "Resolved" : "FMCSA reply by \(due)")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: Space.s2)
            Text(statusUpper)
                .font(EType.micro).tracking(1.1)
                .foregroundStyle(
                    isApproved
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.textSecondary)
                )
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(
                    Capsule().strokeBorder(
                        isApproved ? Color.white.opacity(0.25) : palette.borderFaint,
                        lineWidth: 1
                    )
                )
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: Supporting docs

    @ViewBuilder
    private var supportingDocsPicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("SUPPORTING DOCS")
                    .font(EType.micro).tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(selectedDocIds.count) selected")
                    .font(EType.micro).tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }
            switch documents.state {
            case .loading:
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 64)
            case .empty, .error:
                noDocsHint
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { doc in
                        docRow(doc)
                    }
                }
            }
        }
    }

    private var noDocsHint: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "doc")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text("No documents in your vault. Upload supporting evidence from 083 Documents Hub before submitting.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            Spacer()
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    private func docRow(_ doc: DocumentManagementAPI.Document) -> some View {
        let on = selectedDocIds.contains(doc.id)
        return Button {
            if on { selectedDocIds.remove(doc.id) } else { selectedDocIds.insert(doc.id) }
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textSecondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if let exp = shortDate(doc.expiresAt) {
                        Text("Expires \(exp)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    } else if let up = shortDate(doc.uploadedAt) {
                        Text("Uploaded \(up)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(on ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Submit CTA

    @ViewBuilder
    private var submitCTA: some View {
        let canSubmit = selectedViolation != nil &&
            !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(isSubmitting ? "Submitting…" : "File DataQs challenge")
                    .font(EType.bodyStrong)
                Spacer()
                if isSubmitting {
                    ProgressView().progressViewStyle(.circular).controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isSubmitting)
        .opacity((!canSubmit || isSubmitting) ? 0.5 : 1.0)
    }

    private func submit() async {
        guard let v = selectedViolation else { return }
        // Strip the "cmp::" prefix UnifiedViolation adds — server
        // expects the bare inspection violation id.
        let rawId: String = {
            if v.id.hasPrefix("cmp::") { return String(v.id.dropFirst(5)) }
            return v.id
        }()
        let explanationTrimmed = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        let docs = selectedDocIds.isEmpty ? nil : Array(selectedDocIds)

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let result = try await EusoTripAPI.shared.csaScores.submitDataQsChallenge(
                violationId: rawId,
                reason: reason.rawValue,
                explanation: explanationTrimmed,
                supportingDocs: docs
            )
            submittedResult = result
            flashToast("Challenge filed")
        } catch {
            flashToast("Couldn't submit — try again")
        }
    }

    // MARK: Submitted confirmation

    private func submittedConfirmation(_ result: CsaScoresAPI.DataQsChallengeResponse) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("Challenge submitted")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)

            VStack(alignment: .leading, spacing: Space.s2) {
                confirmRow(label: "CHALLENGE ID", value: result.challengeId)
                confirmRow(label: "VIOLATION", value: result.violationId)
                confirmRow(label: "STATUS", value: result.status.replacingOccurrences(of: "_", with: " ").capitalized)
                if let exp = prettyDate(result.estimatedResponse) {
                    confirmRow(label: "FMCSA RESPONSE BY", value: exp)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)

            Button {
                resetForm()
            } label: {
                Text("File another challenge")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func confirmRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func resetForm() {
        submittedResult = nil
        selectedViolation = nil
        reason = .incorrectData
        explanation = ""
        selectedDocIds = []
    }

    // MARK: Footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "building.columns")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("What happens next")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("FMCSA reviewers pull the original inspection record, the carrier's state-issuer report, and any attached documents. Typical decision window is 60 days. Your carrier's compliance officer is notified and can add supporting materials if needed. You'll see the status land here and in Violations Manager as soon as FMCSA responds.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LinearGradient.diagonal)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 14, y: 6)
    }

    private func flashToast(_ text: String) {
        withAnimation { lastToast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run { withAnimation { lastToast = nil } }
        }
    }

    // MARK: Helpers

    private func shortDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d, yyyy"
            return out.string(from: d)
        }
        return iso
    }

    private func prettyDate(_ iso: String?) -> String? {
        shortDate(iso)
    }
}

// MARK: - Screen wrapper

struct MeDataQsFilerScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeDataQsFiler()
        } nav: {
            BottomNav(
                leading: driverNavLeading_084(),
                trailing: driverNavTrailing_084(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_084() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_084() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("084 · DataQs Filer · Night") {
    MeDataQsFilerScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("084 · DataQs Filer · Afternoon") {
    MeDataQsFilerScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
