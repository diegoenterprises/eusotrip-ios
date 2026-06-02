//
//  223A_AgreementWizard.swift
//  EusoTrip — Shipper · Agreement Wizard (iOS port of web wizard).
//
//  Multi-step generator/signer that calls the canonical
//  `agreements.generate` mutation (Gemini-backed via
//  `esangAI.generateAgreementContent` server-side) and the
//  `agreements.sign` mutation. Uses `GradientSignaturePad` for the
//  signature step. Mirrors the 7 steps from the web
//  `ShipperAgreementWizard.tsx`:
//    1. Mode      — pick agreement type + duration + dates
//    2. Parties   — A + B names / companies / MC# / DOT#
//    3. Financial — rate / fuel / payment terms / insurance
//    4. Lanes     — optional commitment lanes
//    5. Review    — generated content + key terms
//    6. Sign      — GradientSignaturePad (real-time brand gradient ink)
//    7. Complete  — execution confirmation
//
//  Gemini parity with the web: server is the same `agreements.generate`
//  endpoint that returns `enhancedClauses + complianceNotes + risk
//  Flags + fmcsaVerification`. iOS just consumes the same envelope.
//

import SwiftUI

struct AgreementWizardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { AgreementWizardBody() } nav: { shipperLifecycleNav() }
    }
}

private enum WizardStep: String, CaseIterable {
    case mode, parties, financial, lanes, review, sign, complete
    var label: String {
        switch self {
        case .mode:       return "Method"
        case .parties:    return "Parties"
        case .financial:  return "Financial"
        case .lanes:      return "Lanes"
        case .review:     return "Review"
        case .sign:       return "Sign"
        case .complete:   return "Done"
        }
    }
}

private struct LaneInput: Identifiable, Hashable {
    let id = UUID()
    var oC: String = ""
    var oS: String = ""
    var dC: String = ""
    var dS: String = ""
    var rate: String = ""
    var rateType: String = "flat"
    var volume: String = ""
    var period: String = "monthly"
}

private struct AgreementGenerateAck: Decodable, Hashable {
    let id: Int
    let agreementNumber: String?
    let status: String?
    let generatedContent: String?
    let complianceNotes: [String]?
    let riskFlags: [String]?
}

private struct AgreementSignAck: Decodable, Hashable {
    let success: Bool?
    let fullyExecuted: Bool?
}

private struct AgreementWizardBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var step: WizardStep = .mode

    // Mode + type
    @State private var agType: String = "catalyst_shipper"
    @State private var dur: String = "short_term"
    @State private var effDate: Date = Date()
    @State private var expDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()

    // Parties
    @State private var aDisplayName: String = ""
    @State private var aSignerName: String = ""
    @State private var aCompanyName: String = ""
    @State private var aMc: String = ""
    @State private var aDot: String = ""
    @State private var bDisplayName: String = ""
    @State private var bSignerName: String = ""
    @State private var bCompanyName: String = ""
    @State private var bMc: String = ""
    @State private var bDot: String = ""
    @State private var jurisdiction: String = "Texas"
    @State private var nonCircumventMonths: String = "12"
    @State private var terminationNoticeDays: String = "30"
    @State private var noticePeriodDays: String = "3"

    // Financial
    @State private var rateType: String = "flat_rate"
    @State private var baseRate: String = ""
    @State private var fuelSurchargeType: String = "none"
    @State private var fuelSurchargeValue: String = ""
    @State private var paymentTermDays: String = "30"
    @State private var payFrequency: String = "per_load"
    @State private var quickPayDiscount: String = ""
    @State private var quickPayDays: String = ""
    @State private var insAmt: String = "1000000"
    @State private var liab: String = "1000000"
    @State private var cargo: String = "100000"

    // Equipment + hazmat
    @State private var equipmentTypes: Set<String> = ["dry_van"]
    @State private var hazmat: Bool = false

    // T-012 · 2026-05-20 — Canonical Vertical + TrailerCode for the
    // agreement wizard. Threaded into the `agreements.generate` Zod
    // input so the server can:
    //   1. Build the per-vertical document checklist (T-013).
    //   2. Apply the canonical FeeMultiplierEngine (T-024).
    //   3. Surface the correct compliance prompts on Driver / Dispatch.
    // Both nil-safe — older agreement drafts without these picks still
    // generate; the server falls back to .generalFreight / .dryVan when
    // the optional fields are absent.
    @State private var selectedVertical: Vertical? = nil
    @State private var selectedTrailer: TrailerCode? = nil

    /// T-013 · 2026-05-20 — Cross-border flag for the agreement. Drives
    /// the additional USMCA / pedimento / Carta Porte / CBP ACE / CARM
    /// document requirements in the canonical checklist. Defaults false;
    /// shipper toggles on for international lanes. (LaneInput city/state
    /// pairs don't carry an ISO-3166 country today so we capture this
    /// as an explicit toggle rather than inferring — refinement tracked
    /// when LaneInput grows a country field.)
    @State private var isCrossBorderAgreement: Bool = false

    // Lanes
    @State private var lanes: [LaneInput] = []

    // Notes
    @State private var notes: String = ""

    // Generated state
    @State private var ack: AgreementGenerateAck? = nil
    @State private var inflight: Bool = false
    @State private var error: String? = nil

    // Sign state
    @State private var showSignPad: Bool = false
    @State private var signed: AgreementSignAck? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                stepBar
                switch step {
                case .mode:      modeStep
                case .parties:   partiesStep
                case .financial: financialStep
                case .lanes:     lanesStep
                case .review:    reviewStep
                case .sign:      signStep
                case .complete:  completeStep
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .overlay(alignment: .top) {
            if let err = error {
                Text(err)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Brand.danger.opacity(0.92), in: Capsule())
                    .padding(.top, 12)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_500_000_000)
                            await MainActor.run { error = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showSignPad) {
            ZStack {
                Color.black.opacity(0.95).ignoresSafeArea()
                ScrollView {
                    GradientSignaturePad(
                        signerName: aSignerName.isEmpty ? aDisplayName : aSignerName,
                        documentTitle: "\(humanType(agType)) · \(ack?.agreementNumber ?? "—")"
                    ) { dataURL, _ in
                        Task { await signAgreement(dataURL: dataURL) }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("EUSOCONTRACT · WIZARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Agreement Wizard")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Generate \(humanType(agType)) · powered by ESANG AI")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var stepBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(WizardStep.allCases.enumerated()), id: \.offset) { idx, s in
                    let active = (s == step)
                    let done = (idx < currentStepIndex)
                    HStack(spacing: 4) {
                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .heavy))
                        } else {
                            Text("\(idx + 1)")
                                .font(.system(size: 9, weight: .heavy))
                        }
                        Text(s.label)
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(active
                                     ? AnyShapeStyle(.white)
                                     : done
                                       ? AnyShapeStyle(Brand.success)
                                       : AnyShapeStyle(palette.textTertiary))
                    .background(
                        Capsule().fill(
                            active
                            ? AnyShapeStyle(LinearGradient.diagonal)
                            : done
                              ? AnyShapeStyle(Brand.success.opacity(0.15))
                              : AnyShapeStyle(palette.bgCard)
                        )
                    )
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    if idx < WizardStep.allCases.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    private var currentStepIndex: Int {
        WizardStep.allCases.firstIndex(of: step) ?? 0
    }

    // MARK: - Step 1: Mode

    private var modeStep: some View {
        LifecycleCard {
            LifecycleSection(label: "AGREEMENT", icon: "doc.text")
            VStack(alignment: .leading, spacing: 10) {
                pickerField("Type", value: $agType, options: agreementTypes(for: session.user?.role))
                pickerField("Duration", value: $dur, options: [
                    ("spot", "Spot (Single Load)"),
                    ("short_term", "Short Term (1-6 mo)"),
                    ("long_term", "Long Term (6-24 mo)"),
                    ("evergreen", "Evergreen"),
                ])
                HStack(spacing: 12) {
                    DatePicker("Effective", selection: $effDate, displayedComponents: .date)
                        .font(EType.caption)
                    DatePicker("Expires", selection: $expDate, displayedComponents: .date)
                        .font(EType.caption)
                }
            }
            navRow(back: nil, next: "Continue") { step = .parties }
        }
    }

    // MARK: - Step 2: Parties

    private var partiesStep: some View {
        VStack(spacing: Space.s3) {
            LifecycleCard {
                LifecycleSection(label: "PARTY A", icon: "person.fill")
                fieldGroup([
                    ("Display name", $aDisplayName),
                    ("Signer name",  $aSignerName),
                    ("Company",      $aCompanyName),
                    ("MC #",         $aMc),
                    ("DOT #",        $aDot),
                ])
            }
            LifecycleCard {
                LifecycleSection(label: "PARTY B", icon: "building.2")
                fieldGroup([
                    ("Display name", $bDisplayName),
                    ("Signer name",  $bSignerName),
                    ("Company",      $bCompanyName),
                    ("MC #",         $bMc),
                    ("DOT #",        $bDot),
                ])
            }
            LifecycleCard {
                LifecycleSection(label: "JURISDICTION & TERMS", icon: "shield")
                fieldGroup([
                    ("Governing state",       $jurisdiction),
                    ("Termination notice (d)", $terminationNoticeDays),
                    ("Non-circumvent (mo)",   $nonCircumventMonths),
                    ("Notice effective (d)",  $noticePeriodDays),
                ])
            }
            navRow(back: "Back", next: "Continue",
                   onBack: { step = .mode },
                   onNext: { step = .financial })
        }
    }

    // MARK: - Step 3: Financial

    private var financialStep: some View {
        VStack(spacing: Space.s3) {
            LifecycleCard {
                LifecycleSection(label: "RATE & COMPENSATION", icon: "dollarsign.circle")
                pickerField("Rate type", value: $rateType, options: [
                    ("flat_rate",  "Flat Rate"),
                    ("per_mile",   "Per Mile"),
                    ("percentage", "Percentage"),
                    ("per_hour",   "Hourly"),
                ])
                fieldGroup([
                    ("Base rate ($)",       $baseRate),
                ])
                pickerField("Fuel surcharge", value: $fuelSurchargeType, options: [
                    ("none",      "None"),
                    ("doe_index", "DOE Index"),
                    ("fixed",     "Fixed %"),
                    ("variable",  "Variable"),
                ])
                if fuelSurchargeType != "none" {
                    fieldGroup([("Fuel value", $fuelSurchargeValue)])
                }
            }
            LifecycleCard {
                LifecycleSection(label: "PAYMENT TERMS", icon: "calendar")
                fieldGroup([("Days", $paymentTermDays)])
                pickerField("Frequency", value: $payFrequency, options: [
                    ("per_load",  "Per Load"),
                    ("weekly",    "Weekly"),
                    ("biweekly",  "Bi-Weekly"),
                    ("monthly",   "Monthly"),
                    ("net_30",    "Net 30"),
                    ("net_45",    "Net 45"),
                    ("net_60",    "Net 60"),
                ])
                fieldGroup([
                    ("Quick-pay discount (%)", $quickPayDiscount),
                    ("Quick-pay days",          $quickPayDays),
                ])
            }
            LifecycleCard {
                LifecycleSection(label: "INSURANCE", icon: "umbrella")
                fieldGroup([
                    ("General liability ($)", $insAmt),
                    ("Liability limit ($)",   $liab),
                    ("Cargo ($)",             $cargo),
                ])
            }
            // T-012 · 2026-05-20 — canonical Vertical + TrailerCode pickers.
            // These drive the per-vertical document checklist (T-013) and
            // the FeeMultiplierEngine breakdown. Above the legacy equipment
            // chips so the user picks the canonical pair first; the chips
            // below stay for backward-compat with existing draft agreements.
            LifecycleCard {
                LifecycleSection(label: "INDUSTRY VERTICAL", icon: "tag.square")
                Picker("Vertical", selection: $selectedVertical) {
                    Text("— Select vertical —").tag(Vertical?.none)
                    ForEach(Vertical.allCases) { v in
                        Text(v.displayName).tag(Vertical?.some(v))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedVertical) { _, v in
                    // Clear trailer if it no longer fits the new vertical.
                    if let v = v, let t = selectedTrailer,
                       !TrailerCode.filtered(by: v).contains(t) {
                        selectedTrailer = nil
                    }
                    // Auto-flip hazmat flag when the vertical implies it.
                    if v?.isHazmatVertical == true { hazmat = true }
                }

                LifecycleSection(label: "CANONICAL TRAILER", icon: "shippingbox")
                Picker("Trailer", selection: $selectedTrailer) {
                    Text("— Any trailer —").tag(TrailerCode?.none)
                    let pool = selectedVertical.map { TrailerCode.filtered(by: $0) } ?? TrailerCode.allCases
                    ForEach(pool) { t in
                        Text(t.displayName).tag(TrailerCode?.some(t))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedTrailer) { _, t in
                    // Mirror the canonical trailer into the legacy chip set
                    // so server-side parsers that key off equipmentTypes keep
                    // working. Also auto-flip hazmat when the trailer is
                    // intrinsically hazmat-eligible.
                    if let t = t {
                        equipmentTypes.insert(t.rawValue)
                        if t.isHazmatEligible { hazmat = true }
                        if selectedVertical == nil { selectedVertical = t.defaultVertical }
                    }
                }

                // T-013 — Cross-border toggle. Appends the USMCA / customs
                // document overlay to the per-vertical checklist surfaced
                // on the Review step (and downstream on every load posted
                // under this agreement).
                Toggle("Cross-border lane (USMCA / customs)", isOn: $isCrossBorderAgreement)
                    .toggleStyle(SwitchToggleStyle(tint: Brand.blue))
            }

            LifecycleCard {
                LifecycleSection(label: "EQUIPMENT (LEGACY CHIPS)", icon: "truck.box")
                FlowEquipmentChips(selection: $equipmentTypes, hazmat: $hazmat)
            }
            navRow(back: "Back", next: "Continue",
                   onBack: { step = .parties },
                   onNext: { step = .lanes },
                   nextDisabled: baseRate.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Step 4: Lanes

    private var lanesStep: some View {
        VStack(spacing: Space.s3) {
            LifecycleCard {
                LifecycleSection(label: "LANE COMMITMENTS", icon: "map")
                Text("Optional. Required for long-term / lane-commitment agreements.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                ForEach(Array(lanes.enumerated()), id: \.element.id) { idx, _ in
                    laneEditor(idx)
                }
                Button {
                    lanes.append(LaneInput())
                } label: {
                    Label("Add lane", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .buttonStyle(.plain)
            }
            LifecycleCard {
                LifecycleSection(label: "ADDITIONAL NOTES", icon: "text.alignleft")
                TextField("Special instructions, exceptions…", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .font(EType.body)
                    .padding(10)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
            navRow(back: "Back", next: inflight ? "Generating…" : "Generate with ESANG",
                   onBack: { step = .financial },
                   onNext: { Task { await generate() } },
                   nextDisabled: inflight)
        }
    }

    private func laneEditor(_ idx: Int) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("Lane \(idx + 1)").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer()
                Button {
                    lanes.remove(at: idx)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                TextField("From city", text: Binding(
                    get: { lanes[idx].oC },
                    set: { lanes[idx].oC = $0 }
                )).textFieldStyle(.roundedBorder)
                TextField("ST", text: Binding(
                    get: { lanes[idx].oS },
                    set: { lanes[idx].oS = $0 }
                )).textFieldStyle(.roundedBorder).frame(width: 50)
                TextField("To city", text: Binding(
                    get: { lanes[idx].dC },
                    set: { lanes[idx].dC = $0 }
                )).textFieldStyle(.roundedBorder)
                TextField("ST", text: Binding(
                    get: { lanes[idx].dS },
                    set: { lanes[idx].dS = $0 }
                )).textFieldStyle(.roundedBorder).frame(width: 50)
            }
            HStack(spacing: 6) {
                TextField("Rate $", text: Binding(
                    get: { lanes[idx].rate },
                    set: { lanes[idx].rate = $0 }
                )).textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
                TextField("Volume", text: Binding(
                    get: { lanes[idx].volume },
                    set: { lanes[idx].volume = $0 }
                )).textFieldStyle(.roundedBorder).keyboardType(.numberPad)
            }
        }
        .padding(8)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Step 5: Review

    private var reviewStep: some View {
        VStack(spacing: Space.s3) {
            if let a = ack {
                LifecycleCard(accentGradient: true) {
                    LifecycleSection(label: "AGREEMENT \(a.agreementNumber ?? "—")", icon: "doc.text")
                    LifecycleRow(label: "Type",     value: humanType(agType))
                    LifecycleRow(label: "Duration", value: humanDur(dur))
                    LifecycleRow(label: "Status",   value: (a.status ?? "draft").uppercased())
                    if let v = selectedVertical {
                        LifecycleRow(label: "Vertical", value: v.displayName)
                    }
                    if let t = selectedTrailer {
                        LifecycleRow(label: "Trailer", value: t.displayName)
                    }
                    if isCrossBorderAgreement {
                        LifecycleRow(label: "Cross-border", value: "Yes · USMCA / customs overlay")
                    }
                }
                // T-013 · 2026-05-20 — Canonical document checklist for
                // the chosen (vertical, isCrossBorder) tuple. Renders every
                // DocumentRequirement from DocumentRequirements.forShipment
                // so the parties see exactly which 49 CFR / USMCA / ERG /
                // securement / customs docs the agreement obligates them
                // to maintain. Empty when no vertical picked (the canonical
                // checklist requires a vertical anchor).
                let canonicalDocs = DocumentRequirements.forShipment(
                    vertical: selectedVertical ?? .generalFreight,
                    isCrossBorder: isCrossBorderAgreement
                )
                if !canonicalDocs.isEmpty {
                    LifecycleCard {
                        LifecycleSection(label: "DOCUMENT OBLIGATIONS", icon: "doc.text.fill")
                        Text("Both parties must maintain these documents on file for every load under this agreement. Pre-flight items must be uploaded before any load posts; later-state items are due before the FSM transitions to that state.")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(canonicalDocs, id: \.document) { req in
                            agreementDocRow(req)
                        }
                    }
                }
                LifecycleCard {
                    LifecycleSection(label: "CONTRACT TEXT", icon: "text.alignleft")
                    Text(a.generatedContent ?? "Generated content will appear here.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(palette.bgCardSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let notes = a.complianceNotes, !notes.isEmpty {
                    LifecycleCard {
                        LifecycleSection(label: "COMPLIANCE NOTES", icon: "checkmark.shield")
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, n in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundStyle(palette.textSecondary)
                                Text(n).font(EType.caption).foregroundStyle(palette.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let flags = a.riskFlags, !flags.isEmpty {
                    LifecycleCard(accentDanger: true) {
                        LifecycleSection(label: "RISK FLAGS", icon: "exclamationmark.triangle")
                        ForEach(Array(flags.enumerated()), id: \.offset) { _, f in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(Brand.warning)
                                Text(f).font(EType.caption).foregroundStyle(palette.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else {
                LifecycleCard {
                    Text("Generation pending — return to lanes step and tap Generate.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
            navRow(back: "Back", next: "Proceed to sign",
                   onBack: { step = .lanes },
                   onNext: { step = .sign })
        }
    }

    // T-013 (2026-05-20) — Inline doc-requirement row for the agreement
    // review. Shows the document label, regulatory citation, FSM stage,
    // and a BLOCKING pill for cases that must be on-file for the FSM
    // to advance. Read-only; uploads happen on the per-load review
    // (253) and on the agreement detail screen.
    @ViewBuilder
    private func agreementDocRow(_ req: DocumentRequirement) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: req.blocking ? "exclamationmark.shield.fill" : "doc.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(req.blocking ? Brand.warning : palette.textTertiary)
                Text(req.document.rawValue
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if req.blocking {
                    Text("BLOCKING")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Brand.warning)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 6) {
                Text("DUE AT \(req.requiredAt.rawValue)")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                if let ref = req.regulatoryRef {
                    Text(ref)
                        .font(.system(size: 9, weight: .semibold)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Step 6: Sign

    private var signStep: some View {
        VStack(spacing: Space.s3) {
            LifecycleCard(accentGradient: true) {
                LifecycleSection(label: "READY TO SIGN", icon: "signature")
                if let a = ack {
                    LifecycleRow(label: "Agreement", value: a.agreementNumber ?? "—")
                    LifecycleRow(label: "Counterparty",
                                 value: (bDisplayName.isEmpty ? bCompanyName : bDisplayName).isEmpty
                                        ? "—" : (bDisplayName.isEmpty ? bCompanyName : bDisplayName))
                    LifecycleRow(label: "Rate",
                                 value: baseRate.isEmpty ? "—" : "$\(baseRate) \(rateType)")
                }
                Button {
                    showSignPad = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "signature")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Open gradient sign pad")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            navRow(back: "Back", next: nil, onBack: { step = .review })
        }
    }

    // MARK: - Step 7: Complete

    private var completeStep: some View {
        VStack(spacing: Space.s3) {
            LifecycleCard(accentGradient: true) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(Brand.success)
                    Text("Agreement signed")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(signed?.fullyExecuted == true
                         ? "Both parties have signed. Contract fully executed."
                         : "Your gradient ink signature has been recorded. Awaiting counterparty signature.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill").font(.system(size: 10, weight: .heavy))
                        Text("ESIGN ACT COMPLIANT").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    }
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().strokeBorder(palette.borderFaint))
                }
                .frame(maxWidth: .infinity)
            }
            Button {
                NotificationCenter.default.post(
                    name: .eusoShipperNavSwap, object: nil,
                    userInfo: ["screenId": "223"]
                )
            } label: {
                Text("Back to agreements")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Mutations

    private func generate() async {
        guard !inflight else { return }
        inflight = true
        defer { Task { @MainActor in inflight = false } }
        let role = session.user?.role ?? "SHIPPER"
        let resolvedPartyBRole: String = {
            switch agType {
            case "catalyst_driver":  return "DRIVER"
            case "broker_shipper":   return "SHIPPER"
            case "factoring":        return "CATALYST"
            default:                 return roleConfig(for: role).partyBRole
            }
        }()
        struct Lane: Encodable {
            struct Loc: Encodable { let city: String; let state: String; let radius: Int }
            let origin: Loc
            let destination: Loc
            let rate: Double
            let rateType: String
            let volumeCommitment: Int?
            let volumePeriod: String?
        }
        let laneList: [Lane] = lanes.compactMap { l in
            guard !l.oC.isEmpty, !l.dC.isEmpty else { return nil }
            return Lane(
                origin: .init(city: l.oC, state: l.oS, radius: 50),
                destination: .init(city: l.dC, state: l.dS, radius: 50),
                rate: Double(l.rate) ?? 0,
                rateType: l.rateType,
                volumeCommitment: Int(l.volume),
                volumePeriod: l.period
            )
        }
        let strategicInputs: [String: AnyEncodable] = [
            "partyASignerName": AnyEncodable(aSignerName.isEmpty ? (session.user?.name ?? "") : aSignerName),
            "partyACompanyName": AnyEncodable(aCompanyName),
            "partyAName": AnyEncodable(aDisplayName.isEmpty ? (aCompanyName.isEmpty ? aSignerName : aCompanyName) : aDisplayName),
            "partyAMc": AnyEncodable(aMc),
            "partyADot": AnyEncodable(aDot),
            "partyARole": AnyEncodable(role),
            "partyBSignerName": AnyEncodable(bSignerName),
            "partyBCompanyName": AnyEncodable(bCompanyName),
            "partyBName": AnyEncodable(bDisplayName.isEmpty ? (bCompanyName.isEmpty ? bSignerName : bCompanyName) : bDisplayName),
            "partyBCompany": AnyEncodable(bCompanyName),
            "partyBMc": AnyEncodable(bMc),
            "partyBDot": AnyEncodable(bDot),
            "partyBRole": AnyEncodable(resolvedPartyBRole),
            "jurisdiction": AnyEncodable(jurisdiction),
            "payFrequency": AnyEncodable(payFrequency),
            "nonCircumventionMonths": AnyEncodable(nonCircumventMonths),
            "terminationNoticeDays": AnyEncodable(terminationNoticeDays),
            "noticePeriodDays": AnyEncodable(noticePeriodDays),
        ]
        struct In: Encodable {
            let agreementType: String
            let contractDuration: String
            let partyBUserId: Int
            let partyBRole: String
            let strategicInputs: [String: AnyEncodable]
            let rateType: String
            let baseRate: Double
            let fuelSurchargeType: String
            let fuelSurchargeValue: Double?
            let paymentTermDays: Int
            let quickPayDiscount: Double?
            let quickPayDays: Int?
            let minInsuranceAmount: Double?
            let liabilityLimit: Double?
            let cargoInsuranceRequired: Double?
            let equipmentTypes: [String]
            let hazmatRequired: Bool
            // T-012 · 2026-05-20 — Canonical vertical + trailer raw values.
            // The agreement generator routes these into the per-vertical
            // document checklist (DocumentRequirements.forVertical) and
            // FeeMultiplierEngine.compute(). Optional so older clients
            // still post; server defaults to .generalFreight / .dryVan.
            let vertical: String?
            let trailer: String?
            let lanes: [Lane]?
            let effectiveDate: String?
            let expirationDate: String?
            let autoRenew: Bool
            let notes: String?
        }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        do {
            let resp: AgreementGenerateAck = try await EusoTripAPI.shared.mutation(
                "agreements.generate",
                input: In(
                    agreementType: agType,
                    contractDuration: dur,
                    partyBUserId: 0,
                    partyBRole: resolvedPartyBRole,
                    strategicInputs: strategicInputs,
                    rateType: rateType,
                    baseRate: Double(baseRate) ?? 0,
                    fuelSurchargeType: fuelSurchargeType,
                    fuelSurchargeValue: Double(fuelSurchargeValue),
                    paymentTermDays: Int(paymentTermDays) ?? 30,
                    quickPayDiscount: Double(quickPayDiscount),
                    quickPayDays: Int(quickPayDays),
                    minInsuranceAmount: Double(insAmt),
                    liabilityLimit: Double(liab),
                    cargoInsuranceRequired: Double(cargo),
                    equipmentTypes: Array(equipmentTypes),
                    hazmatRequired: hazmat,
                    vertical: selectedVertical?.rawValue,
                    trailer: selectedTrailer?.rawValue,
                    lanes: laneList.isEmpty ? nil : laneList,
                    effectiveDate: isoFormatter.string(from: effDate),
                    expirationDate: isoFormatter.string(from: expDate),
                    autoRenew: dur == "evergreen",
                    notes: notes.isEmpty ? nil : notes
                )
            )
            await MainActor.run {
                ack = resp
                step = .review
            }
        } catch {
            await MainActor.run {
                self.error = "Generate failed: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
            }
        }
    }

    private func signAgreement(dataURL: String) async {
        guard let agreementId = ack?.id else {
            await MainActor.run { error = "Generate the agreement first" }
            return
        }

        // T-014 · 2026-05-20 — Ed25519 cryptographic signing.
        //
        // The base64 PNG signature alone is a visual artifact — anyone with
        // the PNG can claim to have signed it. To make the signing event
        // tamper-evident:
        //   1. SHA-256 of (agreement body + signature PNG + ISO timestamp)
        //   2. Sign the digest with the shipper's persistent Ed25519 key
        //      (Keychain-backed, generated on first sign, stable thereafter)
        //   3. Send (signatureBytes, publicKey, signedDigest, signedAt) so
        //      the server can verify the chain and append to
        //      Shipment.hashChainAnchor (T-015 wires the chain).
        // The PNG keeps flying as `signatureData` for ESIGN-act visual
        // compliance; the cryptographic payload rides alongside.
        let signedAtISO: String = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: Date())
        }()
        let agreementBody = ack?.generatedContent ?? ""
        let digest = ShipperSigningKey.canonicalDigest(
            agreementBody: agreementBody,
            signatureDataURL: dataURL,
            timestampISO: signedAtISO
        )
        let digestB64 = digest.base64EncodedString()
        let signatureBytesB64: String
        let publicKeyB64: String
        do {
            signatureBytesB64 = try ShipperSigningKey.sign(digest)
            publicKeyB64 = try ShipperSigningKey.currentPublicKeyB64()
        } catch {
            await MainActor.run {
                self.error = "Cryptographic sign failed: \(error.localizedDescription)"
            }
            return
        }

        struct In: Encodable {
            let agreementId: Int
            let signatureData: String       // base64 PNG (existing — ESIGN-act visual)
            let signatureRole: String
            let signerName: String
            let signerTitle: String
            // T-014 · 2026-05-20 — Ed25519 signing block. All optional so
            // older server builds without the verifier still accept the
            // signature; once the verifier ships, signatures without these
            // fields downgrade to "ESIGN visual only" status.
            let signedDigestB64: String?    // SHA-256 of (body + png + ts)
            let signatureBytesB64: String?  // Ed25519 signature of the digest
            let publicKeyB64: String?       // shipper's Curve25519 public key
            let signedAtISO: String?        // matches the digest's timestamp input
        }
        do {
            let resp: AgreementSignAck = try await EusoTripAPI.shared.mutation(
                "agreements.sign",
                input: In(
                    agreementId: agreementId,
                    signatureData: dataURL,
                    signatureRole: (session.user?.role ?? "shipper").lowercased(),
                    signerName: aSignerName.isEmpty ? (session.user?.name ?? "Shipper") : aSignerName,
                    signerTitle: "Authorized Representative",
                    signedDigestB64: digestB64,
                    signatureBytesB64: signatureBytesB64,
                    publicKeyB64: publicKeyB64,
                    signedAtISO: signedAtISO
                )
            )
            await MainActor.run {
                signed = resp
                showSignPad = false
                step = .complete
            }
        } catch {
            await MainActor.run {
                self.error = "Sign failed: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    private func navRow(
        back: String?, next: String?,
        onBack: (() -> Void)? = nil,
        onNext: (() -> Void)? = nil,
        nextDisabled: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            if let back, let onBack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .heavy))
                        Text(back).font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if let next, let onNext {
                Button(action: onNext) {
                    HStack(spacing: 4) {
                        Text(next).font(.system(size: 13, weight: .heavy))
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(nextDisabled)
                .opacity(nextDisabled ? 0.5 : 1)
            }
        }
    }

    private func fieldGroup(_ fields: [(String, Binding<String>)]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, pair in
                let (label, binding) = pair
                VStack(alignment: .leading, spacing: 3) {
                    Text(label.uppercased())
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    TextField("", text: binding)
                        .padding(8)
                        .font(EType.body)
                        .background(palette.bgCardSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
        }
    }

    private func pickerField(_ label: String, value: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Menu {
                ForEach(options, id: \.0) { opt in
                    Button(opt.1) { value.wrappedValue = opt.0 }
                }
            } label: {
                HStack {
                    Text(options.first(where: { $0.0 == value.wrappedValue })?.1 ?? value.wrappedValue)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(8)
                .background(palette.bgCardSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Catalogues

    private func agreementTypes(for role: String?) -> [(String, String)] {
        switch (role ?? "SHIPPER").uppercased() {
        case "SHIPPER":
            return [
                ("catalyst_shipper",      "Catalyst-Shipper"),
                ("broker_shipper",        "Broker-Shipper"),
                ("master_service",        "Master Service Agreement"),
                ("lane_commitment",       "Lane Commitment"),
                ("fuel_surcharge",        "Fuel Surcharge Schedule"),
                ("accessorial_schedule",  "Accessorial Schedule"),
                ("nda",                   "Non-Disclosure Agreement"),
            ]
        case "CATALYST":
            return [
                ("catalyst_shipper", "Catalyst-Shipper"),
                ("catalyst_driver",  "Catalyst-Driver (Owner-Op)"),
                ("broker_catalyst",  "Broker-Catalyst"),
                ("master_service",   "Master Service Agreement"),
                ("factoring",        "Factoring Agreement"),
                ("nda",              "NDA"),
            ]
        case "BROKER":
            return [
                ("broker_catalyst",  "Broker-Catalyst"),
                ("broker_shipper",   "Broker-Shipper"),
                ("master_service",   "Master Service Agreement"),
                ("lane_commitment",  "Lane Commitment"),
                ("nda",              "NDA"),
            ]
        case "DRIVER":
            return [
                ("catalyst_driver", "Catalyst-Driver"),
                ("nda",             "NDA"),
            ]
        default:
            return [
                ("catalyst_shipper", "Catalyst-Shipper"),
                ("master_service",   "Master Service Agreement"),
                ("nda",              "NDA"),
            ]
        }
    }

    private func roleConfig(for role: String) -> (partyALabel: String, partyBRole: String) {
        switch role.uppercased() {
        case "SHIPPER":   return ("Shipper", "CATALYST")
        case "CATALYST":  return ("Catalyst", "SHIPPER")
        case "BROKER":    return ("Broker", "CATALYST")
        case "DRIVER":    return ("Driver", "CATALYST")
        default:          return ("Party A", "CATALYST")
        }
    }

    private func humanType(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
           .capitalized
    }
    private func humanDur(_ key: String) -> String {
        switch key {
        case "spot":        return "Spot (Single Load)"
        case "short_term":  return "Short Term"
        case "long_term":   return "Long Term"
        case "evergreen":   return "Evergreen"
        default:            return key.capitalized
        }
    }
}

// MARK: - Equipment chip flow

private struct FlowEquipmentChips: View {
    @Binding var selection: Set<String>
    @Binding var hazmat: Bool
    @Environment(\.palette) private var palette

    private let all = [
        "dry_van", "reefer", "flatbed", "step_deck", "lowboy",
        "double_drop", "conestoga", "liquid_tank", "gas_tank",
        "cryogenic", "hazmat_van", "food_grade_tank", "auto_carrier",
        "livestock", "log_trailer", "grain_hopper", "bulk_hopper",
        "pneumatic", "dump_trailer", "intermodal", "curtainside",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlexibleHStack(spacing: 6) {
                ForEach(all, id: \.self) { eq in
                    Button {
                        if selection.contains(eq) { selection.remove(eq) } else { selection.insert(eq) }
                    } label: {
                        Text(eq.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundStyle(selection.contains(eq) ? Color.white : palette.textSecondary)
                            .background(
                                Capsule().fill(
                                    selection.contains(eq)
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.bgCardSoft)
                                )
                            )
                            .overlay(Capsule().strokeBorder(palette.borderFaint))
                    }
                    .buttonStyle(.plain)
                }
            }
            Toggle("Hazmat required", isOn: $hazmat)
                .font(EType.caption)
                .toggleStyle(SwitchToggleStyle(tint: Brand.magenta))
        }
    }
}

private struct FlexibleHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        // Simple wrapping HStack via SwiftUI's `Layout` is iOS 16+;
        // this falls back to a horizontal ScrollView for older OS.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content }
        }
    }
}

#Preview("223A · Agreement Wizard · Night") {
    AgreementWizardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("223A · Agreement Wizard · Light") {
    AgreementWizardScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
