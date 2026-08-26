//
//  216D_ShipperUSMCACertificate.swift
//  EusoTrip 2027 - Shipper USMCA certificate of origin (drill-down of 216B Cross-Border Customs).
//
//  ARCHETYPE: DETAIL / CERT. A USMCA origin claim is a duty claim. The server
//  evaluates it from four inputs; two of them (origin countries, whether a
//  certificate of origin is on file) come from the load's own record, and two
//  (Regional Value Content, whether the HTS line is covered) have NO source in
//  the load row. Those two are entered by the shipper in an explicit sheet —
//  the same pattern 216G already ships for customs value — and every figure on
//  screen is labelled with where it came from. Nothing is asserted on the
//  shipper's behalf.
//
//  SwiftUI twin of:
//    02 Shipper/Light-SVG/216D Shipper USMCA Certificate.svg
//    02 Shipper/Dark-SVG/216D Shipper USMCA Certificate.svg
//
//  ── WIRING MANIFEST (line-confirmed on disk frontend/server/routers/) ──
//    loads.getById                             EXISTS · loads.ts:1225
//    shippers.getCrossBorderClearance          EXISTS · shippers.ts:3424
//        supplies hasOriginCert — the "USMCA certificate of origin" row's
//        `filed` flag, matched against the load's real document rows.
//    crossBorderShipping.checkUSMCAEligibility  EXISTS · crossBorder.ts:3569
//        input {rvcPercent, originCountries, hasOriginCert, htsCovered}
//        → {eligible, checks[{rule,status,detail}]}
//        NOTE ON NAMESPACE: routers.ts:3214-3216 mounts crossBorderCompliance.ts
//        at `crossBorder` and crossBorder.ts at `crossBorderShipping`. The
//        wireframe header called this `crossBorder.*`; that path resolves to a
//        DIFFERENT router which has no such procedure. The mounted name is used.
//  NOT CALLED — no such procedure exists tree-wide:
//    crossBorder.issueUSMCACertificate  MISSING · the SVG's "Re-certify" CTA
//      has no backing mutation, so the screen shows a named unavailable state
//      instead of a control that cannot do anything.
//
//  DELIBERATE OMISSIONS (each would have required inventing data):
//    · Duty saved is NOT rendered. No procedure returns a duty amount for a
//      load, and a saved-dollars figure is the single most tempting fabrication
//      on this screen.
//    · Steel & aluminium melt-and-pour content is NOT rendered. checkUSMCA-
//      Eligibility does not evaluate it and nothing else on the wire reports it.
//    · Criterion letter, net-cost vs transaction-value method, and the nine
//      CBP/SAT certificate data elements are NOT rendered as record data —
//      the server returns four named rule checks, and those four are shown.
//
//  §W OFFLINE POLICY: ONLINE_ONLY(an origin determination backs a preferential
//  duty claim and is re-evaluated server-side on every submission; a cached
//  ELIGIBLE could be used to defend a claim the current inputs no longer
//  support). Nothing is persisted client-side, and the evaluation is cleared
//  whenever the inputs change.
//
//  — Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoded models

private struct USMCALocation216D: Decodable {
    let city: String?
    let state: String?
}

private struct USMCALoad216D: Decodable {
    let id: String
    let loadNumber: String
    let status: String
    let commodity: String?
    let commodityName: String?
    let originCountry: String?
    let destCountry: String?
    let pickupLocation: USMCALocation216D?
    let deliveryLocation: USMCALocation216D?

    var lane: String {
        "\(location(pickupLocation)) -> \(location(deliveryLocation))"
    }

    private func location(_ value: USMCALocation216D?) -> String {
        let parts = [value?.city, value?.state]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Location not recorded" : parts.joined(separator: ", ")
    }
}

private struct USMCAClearanceDoc216D: Decodable {
    let name: String
    let filed: Bool
}

private struct USMCAClearance216D: Decodable {
    let usmcaEligible: Bool
    let docs: [USMCAClearanceDoc216D]

    /// The clearance matrix names this row "USMCA certificate of origin"
    /// (shippers.ts:3507). Matched case-insensitively so a server-side copy
    /// edit degrades to "not on file" rather than to a silent true.
    var originCertificateOnFile: Bool {
        docs.contains { $0.name.lowercased().contains("usmca") && $0.filed }
    }

    var originCertificateRowPresent: Bool {
        docs.contains { $0.name.lowercased().contains("usmca") }
    }
}

private struct USMCARuleCheck216D: Decodable, Identifiable {
    var id: String { rule }
    let rule: String
    /// "pass" | "fail" | "warning"
    let status: String
    let detail: String
}

private struct USMCAEligibility216D: Decodable {
    let eligible: Bool
    let checks: [USMCARuleCheck216D]
}

/// Shipper-entered origin-claim inputs. These exist because the load row does
/// not carry them — they are never defaulted to a passing value.
private struct USMCAClaimDraft216D {
    var rvcPercent = ""
    var htsCovered = false
}

// MARK: - Store

@MainActor
private final class USMCAOriginStore216D: ObservableObject {
    @Published private(set) var load: USMCALoad216D?
    @Published private(set) var clearance: USMCAClearance216D?
    @Published private(set) var eligibility: USMCAEligibility216D?
    @Published private(set) var evaluatedRvcPercent: Double?
    @Published private(set) var evaluatedHtsCovered: Bool?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isEvaluating = false

    let loadId: String
    private let api: EusoTripAPI

    /// USMCA Regional Value Content threshold quoted by the server's own rule
    /// text ("threshold: 75% TV or NC method", crossBorderHardening.ts:157).
    /// Used only to draw the gauge tick; it is labelled as the statutory
    /// threshold, never as a value read from this load.
    static let rvcThresholdPercent: Double = 75

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    private func clear() {
        load = nil
        clearance = nil
        eligibility = nil
        evaluatedRvcPercent = nil
        evaluatedHtsCovered = nil
    }

    /// Origin countries the claim will be evaluated against. Nil when the load
    /// does not record both sides — the claim is not evaluated on a guess.
    var originCountries: [String]? {
        guard let origin = load?.originCountry?.uppercased(),
              let destination = load?.destCountry?.uppercased(),
              ["US", "CA", "MX"].contains(origin),
              ["US", "CA", "MX"].contains(destination) else { return nil }
        return origin == destination ? [origin] : [origin, destination]
    }

    var canEvaluate: Bool {
        originCountries != nil && clearance != nil
    }

    func refresh() async {
        guard !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clear()
            errorMessage = "Open the USMCA origin claim from a cross-border load to evaluate it."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        eligibility = nil
        evaluatedRvcPercent = nil
        evaluatedHtsCovered = nil

        do {
            struct LoadInput: Encodable { let id: String }
            let result: USMCALoad216D? = try await api.query(
                "loads.getById",
                input: LoadInput(id: loadId)
            )
            guard let resolved = result else {
                clear()
                errorMessage = "This load is no longer available. Return to Loads and choose another one."
                return
            }
            load = resolved

            struct ClearanceInput: Encodable {
                let loadId: String
                let direction: String?
            }
            do {
                clearance = try await api.query(
                    "shippers.getCrossBorderClearance",
                    input: ClearanceInput(loadId: loadId, direction: nil)
                )
            } catch {
                clearance = nil
                errorMessage = error.eusoUserCopy
            }
        } catch {
            clear()
            errorMessage = error.eusoUserCopy
        }
    }

    func evaluate(_ draft: USMCAClaimDraft216D) async -> Bool {
        guard let countries = originCountries else {
            errorMessage = "A USMCA origin claim needs recorded US, Canada, or Mexico country codes on both ends of this load."
            return false
        }
        guard let clearance else {
            errorMessage = "The clearance record has not loaded, so whether a certificate of origin is on file is unknown. Refresh and try again."
            return false
        }
        guard let rvc = Double(draft.rvcPercent.trimmingCharacters(in: .whitespacesAndNewlines)),
              rvc >= 0, rvc <= 100 else {
            errorMessage = "Enter the Regional Value Content as a percentage from 0 to 100."
            return false
        }

        struct Input: Encodable {
            let rvcPercent: Double
            let originCountries: [String]
            let hasOriginCert: Bool
            let htsCovered: Bool
        }

        isEvaluating = true
        defer { isEvaluating = false }
        errorMessage = nil
        do {
            eligibility = try await api.query(
                "crossBorderShipping.checkUSMCAEligibility",
                input: Input(
                    rvcPercent: rvc,
                    originCountries: countries,
                    hasOriginCert: clearance.originCertificateOnFile,
                    htsCovered: draft.htsCovered
                )
            )
            evaluatedRvcPercent = rvc
            evaluatedHtsCovered = draft.htsCovered
            return true
        } catch {
            eligibility = nil
            evaluatedRvcPercent = nil
            evaluatedHtsCovered = nil
            errorMessage = error.eusoUserCopy
            return false
        }
    }
}

// MARK: - Screen

struct ShipperUSMCACertificate: View {
    let loadId: String
    @StateObject private var store: USMCAOriginStore216D
    @State private var showingClaimSheet = false
    @State private var claimDraft = USMCAClaimDraft216D()
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: USMCAOriginStore216D(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · USMCA · CERT OF ORIGIN",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "USMCA origin"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Loading origin record")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    loadCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    SectionLabel("ORIGIN CLAIM")
                        .padding(.top, Space.s5)
                    claimCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    if let eligibility = store.eligibility {
                        SectionLabel("RULE CHECKS · \(eligibility.checks.count)")
                            .padding(.top, Space.s5)
                        ruleList(eligibility.checks)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    }

                    SectionLabel("CERTIFICATE ON FILE")
                        .padding(.top, Space.s5)
                    certificateCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("USMCA STATUTE · NOT LOAD DATA")
                        .padding(.top, Space.s5)
                    statuteCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    issuanceGapNote
                        .padding(.top, Space.s5)
                }

                if !loadId.isEmpty {
                    AddendaCTAPair(
                        primary: "Refresh record",
                        secondary: "Message ESang",
                        primaryLoading: store.isLoading,
                        onPrimary: { Task { await store.refresh() } }
                    )
                    .padding(.top, Space.s5)
                }

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .eusoRefreshable { await store.refresh() }
        .sheet(isPresented: $showingClaimSheet) {
            USMCAClaimSheet216D(draft: $claimDraft) { draft in
                await store.evaluate(draft)
            }
        }
    }

    // MARK: Load identity

    private func loadCard(_ load: USMCALoad216D) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AddendaIconChip(systemImage: "checkmark.seal", tint: Brand.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text(load.commodityName ?? load.commodity ?? "Goods not recorded")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(load.lane)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                AddendaChip(
                    text: load.status.replacingOccurrences(of: "_", with: " ").uppercased(),
                    color: Brand.info
                )
            }
            Divider().overlay(palette.borderFaint)
            factRow("COUNTRIES", countryLane(load))
            factRow("ORIGIN SET", store.originCountries?.joined(separator: " / ") ?? "Not evaluable")
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Claim

    private var claimCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let eligibility = store.eligibility,
               let rvc = store.evaluatedRvcPercent,
               let htsCovered = store.evaluatedHtsCovered {
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 6) {
                        AddendaChip(
                            text: eligibility.eligible ? "QUALIFIES" : "DOES NOT QUALIFY",
                            color: eligibility.eligible ? Brand.success : Brand.danger
                        )
                        Text(eligibility.eligible ? "Preferential origin supported" : "Preferential origin not supported")
                            .font(EType.title)
                            .foregroundStyle(eligibility.eligible ? Brand.success : Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Evaluated against the inputs below. This is a rules check, not a customs ruling, a filed certificate, or a duty determination.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    rvcGauge(rvc)
                }
                Divider().overlay(palette.borderFaint)
                factRow("RVC · ENTERED BY YOU", String(format: "%.1f%%", rvc))
                factRow("RVC THRESHOLD · STATUTE", String(format: "%.0f%%", USMCAOriginStore216D.rvcThresholdPercent))
                factRow("HTS COVERED · ENTERED BY YOU", htsCovered ? "Yes" : "No")
                factRow("CERT ON FILE · FROM RECORD", certificateStateLabel)
            } else {
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(store.canEvaluate ? Brand.info : Brand.warning)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.canEvaluate ? "Enter the origin-claim inputs" : "This lane cannot carry a USMCA claim")
                            .font(EType.title)
                            .foregroundStyle(palette.textPrimary)
                        Text(store.canEvaluate
                             ? "The load supplies the origin countries and whether a certificate of origin is already filed. Regional Value Content and HTS coverage are yours to state — EusoTrip will not assume a qualifying percentage."
                             : "A USMCA origin claim requires recorded US, Canada, or Mexico country codes on both ends of this load, and a clearance record for it.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            Button {
                showingClaimSheet = true
            } label: {
                Label(
                    store.eligibility == nil ? "Evaluate origin claim" : "Re-evaluate",
                    systemImage: "function"
                )
                .font(EType.title)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient.primary)
                )
            }
            .buttonStyle(.plain)
            .opacity(store.canEvaluate && !store.isEvaluating ? 1 : 0.55)
            .disabled(!store.canEvaluate || store.isEvaluating)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private var certificateStateLabel: String {
        guard let clearance = store.clearance else { return "Unknown" }
        if !clearance.originCertificateRowPresent { return "Not required on this lane" }
        return clearance.originCertificateOnFile ? "Filed" : "Not filed"
    }

    /// Gauge is driven by the value the shipper entered and is labelled as
    /// such. The statutory tick sits at the threshold the server's rule text
    /// quotes, so the reader can see the claim against the bar it must clear.
    private func rvcGauge(_ rvcPercent: Double) -> some View {
        let clamped = max(0, min(100, rvcPercent))
        let clears = clamped >= USMCAOriginStore216D.rvcThresholdPercent
        return ZStack {
            Circle().stroke(palette.textPrimary.opacity(0.08), lineWidth: 9)
            Circle()
                .trim(from: 0, to: CGFloat(clamped / 100))
                .stroke(
                    clears ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(Brand.warning),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Rectangle()
                .fill(palette.textPrimary)
                .frame(width: 2, height: 10)
                .offset(y: -32)
                .rotationEffect(.degrees(USMCAOriginStore216D.rvcThresholdPercent / 100 * 360))
            VStack(spacing: 0) {
                Text(String(format: "%.0f%%", clamped))
                    .font(.system(size: 20, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("RVC")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 80, height: 80)
        .accessibilityLabel(String(format: "Entered regional value content %.0f percent against a %.0f percent threshold", clamped, USMCAOriginStore216D.rvcThresholdPercent))
    }

    // MARK: Rule checks

    private func ruleList(_ checks: [USMCARuleCheck216D]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaIconChip(
                        systemImage: statusIcon(check.status),
                        tint: statusColor(check.status)
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(check.rule)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Space.s2)
                            AddendaChip(
                                text: check.status.uppercased(),
                                color: statusColor(check.status)
                            )
                        }
                        Text(check.detail)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s4)
                if index < checks.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, 56)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "pass": return Brand.success
        case "fail": return Brand.danger
        case "warning", "warn": return Brand.warning
        default: return Brand.neutral
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "pass": return "checkmark"
        case "fail": return "xmark"
        case "warning", "warn": return "exclamationmark"
        default: return "questionmark"
        }
    }

    // MARK: Certificate on file

    private var certificateCard: some View {
        let onFile = store.clearance?.originCertificateOnFile == true
        let required = store.clearance?.originCertificateRowPresent == true
        return HStack(alignment: .top, spacing: Space.s3) {
            AddendaIconChip(
                systemImage: onFile ? "doc.badge.checkmark" : "doc.badge.ellipsis",
                tint: onFile ? Brand.success : (required ? Brand.danger : Brand.neutral)
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(certificateStateLabel)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text(onFile
                     ? "A document matching the USMCA certificate of origin is attached to this load. Its contents are not inspected here — only its presence."
                     : (required
                        ? "This lane's required-filing matrix includes a USMCA certificate of origin and no matching document is attached to the load."
                        : "This lane's required-filing matrix does not include a USMCA certificate of origin, or the clearance record has not loaded."))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Statute

    private var statuteCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            factRow("RVC THRESHOLD", String(format: "%.0f%%", USMCAOriginStore216D.rvcThresholdPercent))
            Divider().overlay(palette.borderFaint)
            Text("The Regional Value Content threshold above is the figure the server's own rule text quotes when it evaluates a claim. It is a statutory constant, not a value read from this load. Certificate validity periods, blanket periods, and the nine certificate data elements are set by USMCA and CBP guidance and are not held on this record — this screen does not restate them as if they were.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Named backend gap

    private var issuanceGapNote: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            SectionLabel("ISSUING A CERTIFICATE")
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Issuing or re-certifying here is unavailable")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("Producing a signed USMCA certificate from this screen would need a mutation that does not exist on the server (crossBorder.issueUSMCACertificate is not implemented). Attach the certificate through the load's document flow; the certificate-on-file state above re-derives on the next refresh.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .addendaPanel(palette)
            .padding(.horizontal, Space.s5)
        }
    }

    // MARK: Shared parts

    private func countryLane(_ load: USMCALoad216D) -> String {
        "\(load.originCountry?.uppercased() ?? "Not recorded") -> \(load.destCountry?.uppercased() ?? "Not recorded")"
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text(value)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Claim input sheet

private struct USMCAClaimSheet216D: View {
    @Binding var draft: USMCAClaimDraft216D
    let onEvaluate: (USMCAClaimDraft216D) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isEvaluating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Regional value content") {
                    TextField("RVC (%)", text: $draft.rvcPercent)
                        .keyboardType(.decimalPad)
                }

                Section("Tariff classification") {
                    Toggle("HTS line covered by a USMCA product-specific rule", isOn: $draft.htsCovered)
                }

                Section {
                    Text("These two values are not held on the load record. Enter the content percentage your bill of materials actually supports and state honestly whether the HTS line is covered — the origin determination is only as sound as they are. Whether a certificate of origin is already filed is read from the load, not entered here.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Origin claim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isEvaluating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEvaluating ? "Evaluating…" : "Evaluate") {
                        Task {
                            isEvaluating = true
                            let evaluated = await onEvaluate(draft)
                            isEvaluating = false
                            if evaluated { dismiss() }
                        }
                    }
                    .disabled(isEvaluating)
                }
            }
        }
    }
}

#Preview("216D · USMCA Certificate · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperUSMCACertificate()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("216D · USMCA Certificate · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperUSMCACertificate()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
