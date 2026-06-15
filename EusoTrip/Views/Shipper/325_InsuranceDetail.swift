//
//  325_InsuranceDetail.swift
//  EusoTrip — Shipper · Insurance detail (Arc J).
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct InsuranceDetailScreen: View {
    let theme: Theme.Palette
    /// Optional load context. When this certificate is reached FROM a load
    /// (a lifecycle drill-in), the loadId lets us tag the load's PERIL
    /// EXPOSURE (named-storm corridor / freeze) via `insurance.getLoadPerilExposure`
    /// and bind a weather event to a claim. nil at the account-level COI
    /// entry (ContentView) → the peril ribbon stays hidden, never fabricated.
    var loadId: String? = nil
    var body: some View {
        Shell(theme: theme) { InsuranceBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

// MARK: - Load peril exposure (insurance.getLoadPerilExposure envelope)

/// `insurance.getLoadPerilExposure({loadId})` 1:1. The proc tags a load's
/// weather PERIL EXPOSURE — a named-storm corridor or a freeze window that
/// the cargo's lane crosses — so the shipper can see coverage-relevant
/// weather risk before it becomes a claim. Enterprise-gated (Tomorrow.io
/// severe-alert + named-event tier): until the key lands it returns
/// `available:false` / `peril:"none"`, so every field is optional and the
/// ribbon stays hidden rather than inventing a storm. When the key lands
/// and a real corridor/freeze overlaps the lane, the same view lights with
/// the cited title + severity + window.
private struct LoadPerilExposure: Decodable {
    let available: Bool?
    /// "none" | "named_storm" | "freeze" — the peril class. "none" (or a
    /// nil/unknown value) keeps the ribbon hidden. NEVER a fabricated storm.
    let peril: String?
    /// Human title for the cited peril — "Tropical Storm Imelda corridor",
    /// "Hard freeze · I-35 lane". Surfaced verbatim; nil → hidden.
    let title: String?
    /// CAP-style severity string ("moderate"/"severe"/"extreme") → tints the
    /// ribbon via the shared `WeatherSnapshot.AlertSeverity` mapping.
    let severity: String?
    /// The exposure window phrase ("Jun 14 06:00 – Jun 16 18:00 CDT").
    let window: String?

    /// True only when the enterprise feed answered AND a real peril overlaps
    /// the lane — the single gate the ribbon renders on.
    var isExposed: Bool {
        guard available == true else { return false }
        let p = (peril ?? "none").lowercased()
        return p == "named_storm" || p == "freeze"
    }

    /// "none" | "named_storm" | "freeze" normalized; defaults to none.
    var kind: String { (peril ?? "none").lowercased() }
}

private struct InsuranceCert: Decodable, Hashable {
    let carrier: String?
    let policyNumber: String?
    let coverageType: String?
    let limitUsd: Double?
    let effectiveDate: String?
    let expirationDate: String?
    let pdfUrl: String?
}

/// Result envelope from the homegrown document-intelligence vision
/// spine (`documentRouter.classifyAndRoute`). The classifier first
/// tells us *what the document actually is* (`classifiedType`) and how
/// sure it is (`confidence`) before we trust any extracted field — so
/// the screen can confirm the upload is genuinely a Certificate of
/// Insurance rather than silently mapping a random doc into COI slots.
/// Surfaces the detected type + extraction + warnings on screen so the
/// founder can review before persisting.
private struct COIScanResult: Hashable {
    /// Raw classifier verdict (e.g. "us_coi", "ca_coi", "bill_of_lading",
    /// "unknown"). Drives the honest "is this actually a COI?" banner.
    let classifiedType: String
    /// Plain-language one-liner from the classifier.
    let summary: String
    /// True only when the classifier identified a COI/insurance doc.
    let isCOI: Bool
    let carrier: String?
    let policyNumber: String?
    let coverageType: String?
    let limitUsd: Double?
    let effectiveDate: String?
    let expirationDate: String?
    let confidence: Double?
    let warnings: [String]?
}

private struct InsuranceBody: View {
    @Environment(\.palette) private var palette
    /// Load context for the peril-exposure tag + claim binding. nil at the
    /// account-level COI entry → the peril ribbon never renders.
    var loadId: String? = nil
    @State private var cert: InsuranceCert? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Load peril exposure (named-storm corridor / freeze). nil until the
    /// per-load lookup resolves; the envelope is itself honest (available:false
    /// / peril:none until the enterprise feed is licensed). Fetched only when
    /// a loadId is in scope.
    @State private var peril: LoadPerilExposure? = nil
    /// Set once a coverage-event bind lands ("Bound to claim CLM-… ").
    @State private var perilBindNote: String? = nil
    @State private var binding: Bool = false
    /// COI scan state — user picks a PDF / photo, the bytes are
    /// base64'd and run through the document-intelligence vision spine
    /// (`documentRouter.classifyAndRoute`). The router first classifies
    /// *what the document is*, then returns the COI's structured
    /// carrier / policy / coverage limit / effective + expiry fields.
    @State private var showCOIPicker: Bool = false
    @State private var scanInflight: Bool = false
    @State private var scanResult: COIScanResult? = nil
    @State private var scanError: String? = nil
    @State private var presentedPDF: EusoPDFPresentation? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let p = peril, p.isExposed { perilExposureRibbon(p) }
                scanCOIRibbon
                if loading {
                    LifecycleCard {
                        HStack(spacing: 8) {
                            ProgressView().tint(LinearGradient.diagonal).scaleEffect(0.8)
                            Text("Loading insurance certificate…").font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                } else if let err = loadError {
                    // Friendly error + retry. Maps common server
                    // strings ('UNAUTHORIZED' / 'authentication
                    // required') into actionable copy.
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Brand.danger)
                                Text(friendlyInsuranceError(err))
                                    .font(EType.bodyStrong)
                                    .foregroundStyle(palette.textPrimary)
                            }
                            Text(err)
                                .font(EType.caption)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(2)
                            Button { Task { await load() } } label: {
                                Text("Retry")
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(LinearGradient.diagonal))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if let c = cert { coiCard(c); ctaRow(c) }
                else { LifecycleCard { Text("No insurance certificate on file.").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                if let s = scanResult { scanResultCard(s) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .task(id: loadId) { await loadPeril() }
        .fullScreenCover(item: $presentedPDF) { p in
            EusoPDFViewer(title: p.title, subtitle: p.subtitle, source: .url(p.url))
        }
        .fileImporter(
            isPresented: $showCOIPicker,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleCOIPick(result) }
        }
        .overlay(alignment: .top) {
            if let err = scanError {
                Text(err)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.red.opacity(0.92), in: Capsule())
                    .padding(.top, 12)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 3_500_000_000)
                            await MainActor.run { scanError = nil }
                        }
                    }
            }
        }
    }

    /// "Scan COI" CTA — runs the upload through the document-
    /// intelligence vision spine, which classifies the doc *and*
    /// extracts carrier, policy number, coverage limits, effective +
    /// expiration dates from any uploaded PDF / image so the founder
    /// doesn't have to re-key them. Because it classifies first, we
    /// only pre-fill COI fields when the doc is genuinely a COI.
    private var scanCOIRibbon: some View {
        Button {
            showCOIPicker = true
        } label: {
            LifecycleCard(accentGradient: true) {
                HStack(spacing: 10) {
                    if scanInflight {
                        ProgressView().progressViewStyle(.circular)
                            .tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(LinearGradient.diagonal, in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scanInflight ? "Identifying & reading the document…" : "Scan COI with AI")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("Detects the doc type, then extracts carrier, policy, limits + expiry")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .disabled(scanInflight)
    }

    // MARK: - Peril exposure ribbon (bespoke · WeatherIcons, zero SF Symbols)

    /// Tags the load's weather PERIL EXPOSURE — a named-storm corridor or a
    /// freeze window the cargo's lane crosses — drawn ONLY when the enterprise
    /// feed has answered with a real peril (`available && peril != none`). The
    /// glyph is bespoke: a storm glyph for a named storm, a sleet glyph for a
    /// freeze (WeatherIcons, never an SF Symbol). When the peril binds to a
    /// coverage event/claim, the bind affordance surfaces below. HONEST: the
    /// caller only ever reaches this with a real `LoadPerilExposure.isExposed`
    /// envelope — no fabricated storm, no fabricated window.
    private func perilExposureRibbon(_ p: LoadPerilExposure) -> some View {
        let sev = WeatherSnapshot.AlertSeverity(capString: p.severity)
        // Named storm → the storm glyph (code 8000); freeze → the sleet/ice
        // glyph (code 6001). Both route through the bespoke WeatherIcons set.
        let glyphCode = p.kind == "freeze" ? 6001 : 8000
        let perilLabel = p.kind == "freeze" ? "FREEZE EXPOSURE" : "NAMED-STORM CORRIDOR"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(sev.color.opacity(0.14))
                        .frame(width: 40, height: 40)
                    WeatherIcons.symbolView(for: glyphCode, size: 24)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        WeatherIcons.utility(.alert, size: 11, tint: sev.color)
                        Text(perilLabel)
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(sev.color)
                    }
                    Text(dashIfEmpty(p.title))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let w = p.window, !w.isEmpty {
                        Text(w)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Text(sev.label)
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(sev.color)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(sev.color.opacity(0.14)))
            }

            Text("This load's lane crosses an active \(p.kind == "freeze" ? "freeze window" : "named-storm corridor"). If cargo is impacted, bind the event to a freight claim so the carrier-insurance file carries the cited coverage trigger.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Coverage-event bind affordance. After a successful bind the
            // confirmation replaces the button (honest, server-acknowledged).
            if let note = perilBindNote {
                HStack(spacing: 6) {
                    WeatherIcons.utility(.alert, size: 12, tint: Brand.success)
                    Text(note)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.success)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Button { Task { await bindPerilToClaim(p) } } label: {
                    HStack(spacing: 6) {
                        if binding { ProgressView().tint(.white).controlSize(.small) }
                        Text(binding ? "Binding…" : "Bind to coverage event")
                            .font(.system(size: 12, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(binding || loadId == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(sev.color.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Pull `insurance.getLoadPerilExposure({loadId})` — the load's weather
    /// peril tag. Enterprise-gated: today it returns `available:false` /
    /// `peril:"none"`, so the ribbon stays hidden (the honest state that lights
    /// the instant the key lands and a real corridor/freeze overlaps the lane).
    /// Skipped entirely with no load in scope — never queries a guessed load.
    private func loadPeril() async {
        guard let loadId, !loadId.isEmpty else { peril = nil; return }
        struct PerilIn: Encodable { let loadId: String }
        do {
            let p: LoadPerilExposure = try await EusoTripAPI.shared.query(
                "insurance.getLoadPerilExposure", input: PerilIn(loadId: loadId))
            peril = p
        } catch {
            // Keep the ribbon hidden; never invent a peril.
            peril = nil
        }
    }

    /// Bind the cited peril to a coverage event/claim via
    /// `insurance.bindWeatherEventToClaim`. The server links the weather
    /// trigger to the load's claim so the carrier-insurance file carries the
    /// contemporaneous coverage cause. On success the ribbon shows the
    /// server-returned reference; on failure the button stays so it can retry.
    private func bindPerilToClaim(_ p: LoadPerilExposure) async {
        guard let loadId, !loadId.isEmpty else { return }
        binding = true
        defer { binding = false }
        struct BindIn: Encodable { let loadId: String; let peril: String }
        struct BindOut: Decodable { let success: Bool?; let claimId: String?; let eventId: String? }
        do {
            let out: BindOut = try await EusoTripAPI.shared.mutation(
                "insurance.bindWeatherEventToClaim",
                input: BindIn(loadId: loadId, peril: p.kind))
            if out.success == true {
                if let c = out.claimId, !c.isEmpty {
                    perilBindNote = "Bound to claim \(c)"
                } else {
                    perilBindNote = "Coverage event bound to this load"
                }
            } else {
                scanError = "Couldn't bind the coverage event. No claim was changed."
            }
        } catch {
            scanError = "Bind failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func scanResultCard(_ s: COIScanResult) -> some View {
        // Confidence buckets drive honest copy: high → trust it,
        // mid/low → ask the founder to confirm, never assert.
        let conf = s.confidence ?? 0
        let lowConfidence = conf < 0.6
        let confColor: Color = conf >= 0.85 ? Brand.success : conf >= 0.6 ? Brand.warning : Brand.danger
        return LifecycleCard {
            // Detected document type — surfaced verbatim from the
            // classifier so we never claim a type the doc isn't.
            LifecycleSection(
                label: "DETECTED · \(detectedTypeLabel(s.classifiedType).uppercased())",
                icon: s.isCOI ? "doc.text.viewfinder" : "questionmark.circle"
            )

            // Honesty banner: only proceed to confirm a COI when the
            // classifier actually said so AND it was reasonably sure.
            if !s.isCOI {
                classifierNotice(
                    icon: "exclamationmark.triangle.fill",
                    tint: Brand.warning,
                    title: "This doesn't look like a Certificate of Insurance",
                    detail: "It was identified as “\(detectedTypeLabel(s.classifiedType))”. Pre-filled fields below may not apply. Please re-upload your COI."
                )
            } else if lowConfidence {
                classifierNotice(
                    icon: "questionmark.circle.fill",
                    tint: Brand.warning,
                    title: "Couldn't confidently identify this - please confirm",
                    detail: "We think it's a COI, but only at \(Int(conf * 100))% confidence. Double-check the extracted values before saving."
                )
            }

            // Classifier summary (one-liner) when present.
            if !s.summary.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text(s.summary)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 2)
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(confColor)
                Text("EXTRACTED · \(Int(conf * 100))% CONFIDENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(confColor)
            }
            .padding(.vertical, 2)

            // Grouped so the card's ViewBuilder stays within its
            // 10-child limit; Group is layout-transparent so the rows
            // inherit the card VStack's spacing unchanged.
            Group {
                LifecycleRow(label: "Carrier",       value: dashIfEmpty(s.carrier))
                LifecycleRow(label: "Policy",        value: dashIfEmpty(s.policyNumber))
                LifecycleRow(label: "Coverage type", value: dashIfEmpty(s.coverageType))
                LifecycleRow(label: "Limit",         value: usd(s.limitUsd))
                LifecycleRow(label: "Effective",     value: humanISO(s.effectiveDate, format: "MMM d, yyyy"))
                LifecycleRow(label: "Expires",       value: humanISO(s.expirationDate, format: "MMM d, yyyy"))
            }
            if let warnings = s.warnings, !warnings.isEmpty {
                Divider().overlay(palette.borderFaint).padding(.vertical, 4)
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Brand.warning)
                        Text(w).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    /// Inline honesty notice used for not-a-COI / low-confidence cases.
    private func classifierNotice(icon: String, tint: Color, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(tint)
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detail)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.45))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.vertical, 2)
    }

    /// Human-facing label for a classifier verdict. Mirrors the
    /// canonical naming used in DocumentClassifierSheet.
    private func detectedTypeLabel(_ raw: String) -> String {
        switch raw {
        case "us_coi", "ca_coi", "insurance_certificate", "certificate_of_insurance":
            return "Certificate of Insurance"
        case "bill_of_lading": return "Bill of Lading"
        case "rate_confirmation": return "Rate Confirmation"
        case "proof_of_delivery": return "Proof of Delivery"
        case "load_tender": return "Load Tender"
        case "us_cdl": return "CDL"
        case "us_medical_card": return "Medical Card"
        case "w9": return "W-9"
        case "unknown", "": return "Unidentified document"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// True when the classifier verdict denotes an insurance / COI doc.
    private func isCOIType(_ raw: String) -> Bool {
        let t = raw.lowercased()
        return t.contains("coi")
            || t.contains("insurance")
            || t.contains("certificate_of_insurance")
    }

    /// Pick → classify → pre-fill. Runs the picked PDF / image through
    /// the document-intelligence vision spine
    /// (`documentRouter.classifyAndRoute`) with the "insurance COI"
    /// caller context. The router first identifies *what the document
    /// is*, then hands back doc-type-specific extracted fields; we pull
    /// carrier / policy / coverage limit / effective + expiration only
    /// when it's genuinely a COI, and surface the detected type +
    /// confidence honestly when it isn't.
    private func handleCOIPick(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let err):
            await MainActor.run { scanError = "Pick failed: \(err.localizedDescription)" }
        case .success(let urls):
            guard let url = urls.first else { return }
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            scanInflight = true
            defer { Task { @MainActor in scanInflight = false } }
            do {
                let data = try Data(contentsOf: url)
                let base64 = data.base64EncodedString()
                let mime: DocumentRouterAPI.MimeType = {
                    switch url.pathExtension.lowercased() {
                    case "pdf": return .pdf
                    case "png": return .png
                    case "webp": return .webp
                    case "heic": return .heic
                    default: return .jpeg
                    }
                }()

                let resp = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                    documentBase64: base64,
                    mimeType: mime,
                    callerContext: "insurance COI"
                )

                // Flatten heterogeneous field values to display strings.
                let fields: [String: String] = resp.extractedFields.compactMapValues { $0.asString }
                let isCOI = isCOIType(resp.classifiedType)

                await MainActor.run {
                    scanResult = COIScanResult(
                        classifiedType: resp.classifiedType,
                        summary: resp.summary,
                        isCOI: isCOI,
                        carrier: pick(fields, "carrierName", "carrier", "insurer", "insurerName", "underwriter"),
                        policyNumber: pick(fields, "policyNumber", "policyNo", "policy", "policyNum"),
                        coverageType: pick(fields, "coverageType", "coverage", "lineOfCoverage", "policyType"),
                        limitUsd: parseLimit(pick(
                            fields,
                            "coverageLimit", "limit", "limitUsd", "combinedSingleLimit",
                            "liabilityLimit", "eachOccurrence", "generalAggregate", "cargoLimit"
                        )),
                        effectiveDate: pick(fields, "effectiveDate", "policyEffectiveDate", "startDate", "effective"),
                        expirationDate: pick(fields, "expirationDate", "policyExpirationDate", "expiryDate", "expiresAt", "endDate", "expiration"),
                        confidence: resp.confidence,
                        warnings: resp.warnings
                    )
                }
            } catch {
                await MainActor.run {
                    scanError = "Scan failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                }
            }
        }
    }

    /// First non-empty value among the candidate keys. The router's
    /// COI field keys aren't guaranteed, so we try the common aliases.
    private func pick(_ fields: [String: String], _ keys: String...) -> String? {
        for k in keys {
            if let v = fields[k], !v.trimmingCharacters(in: .whitespaces).isEmpty {
                return v
            }
        }
        return nil
    }

    /// Parse a coverage-limit string that may arrive as "$1,000,000",
    /// "1000000", or "1,000,000.00" into a Double. Returns nil when it
    /// isn't a number so we honestly render "-" instead of 0.
    private func parseLimit(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let cleaned = raw.filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "umbrella.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · INSURANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Insurance certificate").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func coiCard(_ c: InsuranceCert) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "COI", icon: "shield.checkered")
            LifecycleRow(label: "Carrier",        value: dashIfEmpty(c.carrier))
            LifecycleRow(label: "Policy",         value: dashIfEmpty(c.policyNumber))
            LifecycleRow(label: "Coverage type",  value: dashIfEmpty(c.coverageType))
            LifecycleRow(label: "Limit",          value: usd(c.limitUsd))
            LifecycleRow(label: "Effective",      value: humanISO(c.effectiveDate, format: "MMM d, yyyy"))
            LifecycleRow(label: "Expires",        value: humanISO(c.expirationDate, format: "MMM d, yyyy"))
        }
    }

    private func ctaRow(_ c: InsuranceCert) -> some View {
        if let pdf = c.pdfUrl, !pdf.isEmpty {
            return AnyView(Button {
                if let u = URL(string: pdf) {
                    presentedPDF = EusoPDFPresentation(
                        url: u,
                        title: "Certificate of insurance",
                        subtitle: c.carrier
                    )
                }
            } label: {
                Text("Open COI PDF").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain))
        }
        return AnyView(EmptyView())
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let c: InsuranceCert = try await EusoTripAPI.shared.queryNoInput("compliance.getInsurance")
            cert = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Convert raw backend error strings into friendly heading copy.
    /// 'authentication required' / 'UNAUTHORIZED' → re-auth hint.
    /// Everything else → 'Couldn't load insurance' with the raw
    /// string surfaced underneath as detail.
    private func friendlyInsuranceError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("auth") || lower.contains("unauthorized") || lower.contains("401") {
            return "Sign in again to view this certificate"
        }
        if lower.contains("404") || lower.contains("not found") {
            return "No insurance certificate on file"
        }
        if lower.contains("offline") || lower.contains("network") {
            return "Insurance service is offline - try again"
        }
        return "Couldn't load insurance"
    }
}

#Preview("325 · Insurance · Night") { InsuranceDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("325 · Insurance · Afternoon") { InsuranceDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
