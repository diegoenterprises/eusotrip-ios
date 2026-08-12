//
//  392_CatalystCargoInsurance.swift
//  EusoTrip — Catalyst · Cargo Insurance (CARRIER-side fleet coverage + per-load compliance).
//
//  Verbatim iOS-house port of "03 Catalyst/Code/392_CatalystCargoInsurance.swift"
//  (cross-checked against Dark-SVG "392 Catalyst Cargo Insurance.svg").
//
//  CARRIER vantage. Fleet coverage + per-load compliance: a cargo-limit hero
//  (cargo $250K · auto $1M · MCS-90), a getCoverage detail card (limits · reefer
//  breakdown · MCS-90 · expiry · verifyCarrierCoverage line), a per-load
//  checkLoadCompliance strip, a COI-on-file tie, and the generateCOI CTA.
//  Cross-mode parity gap fill — Rail (606) and Vessel (733) had cargo-insurance
//  surfaces; the Truck Catalyst band had none against the mode-agnostic insurance
//  router. Carrier vantage (own cover, verify per load) is distinct from the
//  shipper per-load buy. Docked under FLEET.
//
//  LIVE WIRING (zero-fallback purge · 2026-06-09 · audit B16):
//    • hero cargo limit + coverage rows ← insurance.getPolicies (insurance.ts:93)
//      — raw insurancePolicies rows (policyType / perOccurrenceLimit /
//        providerName / expirationDate / status), same bridge shape 308 ships.
//    • COI tie                          ← insurance.getCertificates (insurance.ts:451)
//      — raw certificatesOfInsurance rows (holderName / expirationDate / status).
//    • per-load compliance strip        — needs a load context this screen
//      doesn't carry (insurance.checkLoadCompliance takes a loadId) → honest
//      "not yet connected" copy, never an invented "met" verdict.
//    • generateCOI CTA                  — insurance.requestCertificate
//      (insurance.ts:734) with active policyIds, audit, and company fan-out.
//  NO invented $250k/$1M/MCS-90/expiry figures remain: live policy rows or
//  honest "No policy on file" + em-dash.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystCargoInsuranceScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            CargoInsuranceBody_392()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_392(),
                trailing: catalystNavTrailing_392(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_392() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_392() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "truck.box",          isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.crop.circle", isCurrent: true)]
}

// MARK: - Body

private struct CargoInsuranceBody_392: View {
    @Environment(\.palette) private var palette

    // Live state — empty until insurance.getPolicies / getCertificates answer.
    @State private var policies: [InsurancePolicy_392] = []
    @State private var certificates: [Certificate_392] = []
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var showCOIRequest: Bool = false
    @State private var coiMessage: String? = nil
    @State private var coiError: String? = nil

    // MARK: Live derivations

    private var activePolicies: [InsurancePolicy_392] {
        policies.filter { ($0.status ?? "").lowercased() == "active" }
    }
    private var cargoPolicy: InsurancePolicy_392? {
        activePolicies.first { ($0.policyType ?? "").lowercased().contains("cargo") }
            ?? policies.first { ($0.policyType ?? "").lowercased().contains("cargo") }
    }
    private var heroLimitDisplay: String {
        guard let raw = cargoPolicy?.perOccurrenceLimit, let v = Double(raw), v > 0 else { return "—" }
        return money_392(v)
    }
    private var hasActivePolicy: Bool { !activePolicies.isEmpty }

    private var coverageRows_392: [CoverageRow_392] {
        // One row per live policy — type · limit · expiry. No invented rows.
        policies.map { p in
            let limit = p.perOccurrenceLimit.flatMap(Double.init).map { money_392($0) } ?? "—"
            let expiry = p.expirationDate.map { shortDate_392($0) } ?? "—"
            return CoverageRow_392(
                label: (p.policyType ?? "Policy").replacingOccurrences(of: "_", with: " ").capitalized,
                value: "\(limit) · exp \(expiry)"
            )
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                IridescentHairline()
                    .padding(.horizontal, -20)

                heroCard
                provenanceLine("COVERAGE · LIVE POLICIES")
                coverageDetailCard
                perLoadStrip
                coiTieStrip
                generateCTA
                ctaSchemaFootnote
                coiFeedback

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        .sheet(isPresented: $showCOIRequest) {
            RequestCOISheet_392(policyIds: activePolicies.map(\.id)) { result in
                coiMessage = "COI requested · \(result.certificateNumber ?? "pending")"
                coiError = nil
                Task { await loadAll() }
            }
            .environment(\.palette, palette)
        }
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · CARGO INSURANCE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("FLEET COVER")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Cargo Insurance")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("fleet coverage · \(policies.count) polic\(policies.count == 1 ? "y" : "ies") on file")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Hero (cargo limit · live policy state)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CARGO LIMIT · POLICY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // Badge is earned, never asserted: green "in force" only when a
                // live active policy exists; honest neutral otherwise.
                Text(hasActivePolicy ? "in force" : (loading ? "loading" : "no policy"))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(hasActivePolicy ? Brand.success : palette.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(hasActivePolicy
                        ? Brand.success.opacity(0.14)
                        : palette.bgCardSoft))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(heroLimitDisplay)
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("cargo")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(heroSubline)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue, Brand.magenta],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Coverage detail (live insurance.getPolicies rows)

    private var coverageDetailCard: some View {
        VStack(spacing: 0) {
            if loading && policies.isEmpty {
                Text("Loading policies…")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else if policies.isEmpty {
                EusoEmptyState(
                    systemImage: "shield.lefthalf.filled",
                    title: "No policy on file",
                    subtitle: loadError ?? "Insurance policies registered to your company appear here with limits and expiry."
                )
            } else {
                ForEach(coverageRows_392) { row in
                    HStack {
                        Text(row.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                        Text(row.value)
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                    }
                    .padding(.vertical, 7)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Per-load strip (honest: needs a load context this screen lacks)

    private var perLoadStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PER-LOAD COMPLIANCE")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("Per-load coverage checks aren't connected to this view yet — open a load to verify its insurance requirements.")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - COI tie (live insurance.getCertificates rows)

    private var coiTieStrip: some View {
        let active = certificates.filter { ($0.status ?? "").lowercased() == "active" }
        let expiringSoon = active.filter { expiresWithin_392($0.expirationDate, days: 30) }
        return VStack(alignment: .leading, spacing: 4) {
            Text(certificates.isEmpty
                 ? "No COIs on file"
                 : "\(active.count) active COI\(active.count == 1 ? "" : "s") on file\(expiringSoon.isEmpty ? "" : " · \(expiringSoon.count) expiring in 30d")")
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            if let holder = active.first?.holderName ?? certificates.first?.holderName {
                Text("Latest holder \(holder)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text(loading ? "Loading certificates…" : "Certificates issued for your company appear here.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.info.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.info.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA (live insurance.requestCertificate)

    private var generateCTA: some View {
        CTAButton(
            title: "Generate certificate (COI)",
            action: openCOIRequest,
            leadingIcon: "doc.badge.plus"
        )
    }

    private var ctaSchemaFootnote: some View {
        Text("Requests use your active policy rows and create a pending certificate for compliance review.")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var coiFeedback: some View {
        if let coiMessage {
            Text(coiMessage)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(Brand.success)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        if let coiError {
            Text(coiError)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(Brand.warning)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private func openCOIRequest() {
        coiMessage = nil
        if loading {
            coiError = "Coverage is still loading. Try again in a moment."
            return
        }
        guard hasActivePolicy else {
            coiError = "Add or activate a cargo policy before requesting a COI."
            return
        }
        coiError = nil
        showCOIRequest = true
    }

    // MARK: - Provenance eyebrow

    private func provenanceLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: - Hero subline (live-derived, never invented)

    private var heroSubline: String {
        guard !policies.isEmpty else {
            return loading ? "Checking coverage…" : "No coverage data — policies registered to your company appear here."
        }
        let auto = activePolicies.first { ($0.policyType ?? "").lowercased().contains("auto") || ($0.policyType ?? "").lowercased().contains("liability") }
        let autoPart = auto?.perOccurrenceLimit.flatMap(Double.init).map { "auto liability \(money_392($0))" } ?? "auto liability —"
        let expiry = cargoPolicy?.expirationDate.map { "cargo exp \(shortDate_392($0))" } ?? "cargo exp —"
        return "\(autoPart) · \(expiry)"
    }

    // MARK: - Network (live bridge — same decode shape 308 ships against)

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }

        struct LimitInput: Encodable { let limit: Int }

        async let policiesTask: [InsurancePolicy_392] =
            EusoTripAPI.shared.query("insurance.getPolicies", input: LimitInput(limit: 20))
        async let certsTask: [Certificate_392] =
            EusoTripAPI.shared.query("insurance.getCertificates", input: LimitInput(limit: 20))

        do {
            let (p, c) = try await (policiesTask, certsTask)
            policies = p
            certificates = c
        } catch {
            policies = []
            certificates = []
            loadError = "Couldn't reach the insurance service - pull to retry."
        }
    }

    // MARK: - Formatting

    private func money_392(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func shortDate_392(_ iso: String) -> String {
        iso.count >= 10 ? String(iso.prefix(10)) : (iso.isEmpty ? "—" : iso)
    }

    private func expiresWithin_392(_ iso: String?, days: Int) -> Bool {
        guard let iso, !iso.isEmpty else { return false }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? {
            let g = ISO8601DateFormatter()
            g.formatOptions = [.withInternetDateTime]
            return g.date(from: iso)
        }()
        guard let date = d else { return false }
        return date.timeIntervalSinceNow < Double(days) * 86400 && date.timeIntervalSinceNow > 0
    }
}

// MARK: - Request COI sheet (insurance.requestCertificate)

private struct RequestCertificateResult_392: Decodable, Equatable {
    let success: Bool
    let certificateId: Int?
    let certificateNumber: String?
}

private struct RequestCOISheet_392: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let policyIds: [Int]
    let onRequested: (RequestCertificateResult_392) -> Void

    @State private var holderName = ""
    @State private var holderEmail = ""
    @State private var holderAddress = ""
    @State private var additionalInsured = false
    @State private var waiverOfSubrogation = false
    @State private var loading = false
    @State private var errorText: String? = nil

    private var canSubmit: Bool {
        !holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !loading
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Text("Request certificate")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Close")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("A certificate of insurance will be issued from your active Catalyst policy rows and marked pending for compliance review.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)

                field("CERTIFICATE HOLDER NAME") {
                    TextField("Certificate holder name", text: $holderName)
                        .foregroundStyle(palette.textPrimary)
                }
                field("HOLDER EMAIL") {
                    TextField("Holder email", text: $holderEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(palette.textPrimary)
                }
                field("HOLDER ADDRESS") {
                    TextField("Street, city, ST", text: $holderAddress)
                        .foregroundStyle(palette.textPrimary)
                }

                Toggle(isOn: $additionalInsured) {
                    Text("Additional insured endorsement")
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                }
                .tint(Brand.success)

                Toggle(isOn: $waiverOfSubrogation) {
                    Text("Waiver of subrogation")
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                }
                .tint(Brand.success)

                if let errorText {
                    Text(errorText)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                }

                Button { Task { await submit() } } label: {
                    HStack(spacing: 6) {
                        if loading { ProgressView().scaleEffect(0.8) }
                        Text(loading ? "Requesting…" : "Request COI")
                            .font(EType.bodyStrong)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(canSubmit ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary.opacity(0.4)))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(Space.s4)
        }
        .background(palette.bgPrimary)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            content()
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func submit() async {
        loading = true
        errorText = nil
        defer { loading = false }

        struct Input: Encodable {
            let holderName: String
            let holderAddress: String?
            let holderEmail: String?
            let policyIds: [Int]?
            let additionalInsuredEndorsement: Bool
            let waiverOfSubrogation: Bool
        }

        do {
            let result: RequestCertificateResult_392 = try await EusoTripAPI.shared.mutation(
                "insurance.requestCertificate",
                input: Input(
                    holderName: holderName.trimmingCharacters(in: .whitespacesAndNewlines),
                    holderAddress: holderAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : holderAddress,
                    holderEmail: holderEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : holderEmail,
                    policyIds: policyIds.isEmpty ? nil : policyIds,
                    additionalInsuredEndorsement: additionalInsured,
                    waiverOfSubrogation: waiverOfSubrogation
                )
            )
            if result.success {
                onRequested(result)
                dismiss()
            } else {
                errorText = "Request did not complete. Please try again."
            }
        } catch {
            errorText = certificateFailureCopy_392(error)
        }
    }
}

// MARK: - Models

private struct CoverageRow_392: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

/// Raw `insurancePolicies` row off `insurance.getPolicies` (insurance.ts:93) —
/// DECIMAL columns arrive as JSON strings, dates as ISO strings. Identical
/// bridge contract to 308 Authority + Insurance.
private struct InsurancePolicy_392: Decodable, Identifiable {
    let id: Int
    let policyType: String?
    let policyNumber: String?
    let providerName: String?
    let perOccurrenceLimit: String?
    let aggregateLimit: String?
    let effectiveDate: String?
    let expirationDate: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, policyType, policyNumber, providerName, perOccurrenceLimit,
             aggregateLimit, effectiveDate, expirationDate, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try c.decode(Int.self, forKey: .id)
        policyType         = try c.decodeIfPresent(String.self, forKey: .policyType)
        policyNumber       = try c.decodeIfPresent(String.self, forKey: .policyNumber)
        providerName       = try c.decodeIfPresent(String.self, forKey: .providerName)
        perOccurrenceLimit = try c.decodeIfPresent(String.self, forKey: .perOccurrenceLimit)
        aggregateLimit     = try c.decodeIfPresent(String.self, forKey: .aggregateLimit)
        effectiveDate      = try c.decodeIfPresent(String.self, forKey: .effectiveDate)
        expirationDate     = try c.decodeIfPresent(String.self, forKey: .expirationDate)
        status             = try c.decodeIfPresent(String.self, forKey: .status)
    }
}

/// Raw `certificatesOfInsurance` row off `insurance.getCertificates`
/// (insurance.ts:451) — only the fields this surface renders.
private struct Certificate_392: Decodable, Identifiable {
    let id: Int
    let certificateNumber: String?
    let holderName: String?
    let issuedDate: String?
    let expirationDate: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, certificateNumber, holderName, issuedDate, expirationDate, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(Int.self, forKey: .id)
        certificateNumber = try c.decodeIfPresent(String.self, forKey: .certificateNumber)
        holderName        = try c.decodeIfPresent(String.self, forKey: .holderName)
        issuedDate        = try c.decodeIfPresent(String.self, forKey: .issuedDate)
        expirationDate    = try c.decodeIfPresent(String.self, forKey: .expirationDate)
        status            = try c.decodeIfPresent(String.self, forKey: .status)
    }
}

// MARK: - Previews

#Preview("392 · Catalyst · Cargo Insurance · Night") {
    CatalystCargoInsuranceScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("392 · Catalyst · Cargo Insurance · Afternoon") {
    CatalystCargoInsuranceScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

// MARK: - Operator-facing failure copy

/// Operator-language reason a certificate-of-insurance request failed.
///
/// The caught error is still available for logging; the requester sees a
/// sentence that names what to do next instead of a raw `NSError` string.
fileprivate func certificateFailureCopy_392(_ error: Error) -> String {
    if let api = error as? EusoTripAPIError {
        switch api {
        case .unauthenticated:
            return "Your session expired. Sign in again to request the certificate."
        case .forbidden(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "This account isn't cleared to issue certificates on this policy."
                : trimmed
        case .trpcError(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "The certificate request was rejected. Check the holder details and try again."
                : trimmed
        case .httpStatus(let code, _):
            return "The certificate request didn't go through (code \(code)). Try again in a moment."
        case .decodingFailed:
            return "The certificate came back in a form this build can't read. Update the app, then request it again."
        case .empty:
            return "No certificate came back. Request it again in a moment."
        case .notConfigured, .badURL:
            return "This device isn't set up to request certificates yet. Restart the app and try again."
        case .queuedForOfflineReplay:
            return "You're offline — the certificate request is queued and sends when you reconnect."
        }
    }
    if (error as NSError).domain == NSURLErrorDomain {
        return "No connection right now. The certificate wasn't requested — retry once you're back online."
    }
    return "The certificate request didn't complete. Try again in a moment."
}
