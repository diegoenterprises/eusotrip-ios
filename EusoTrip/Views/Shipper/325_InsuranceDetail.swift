//
//  325_InsuranceDetail.swift
//  EusoTrip — Shipper · Insurance detail (Arc J).
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct InsuranceDetailScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { InsuranceBody() } nav: { shipperLifecycleNav() }
    }
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
    @State private var cert: InsuranceCert? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
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
                    detail: "It was identified as “\(detectedTypeLabel(s.classifiedType))”. Pre-filled fields below may not apply — please re-upload your COI."
                )
            } else if lowConfidence {
                classifierNotice(
                    icon: "questionmark.circle.fill",
                    tint: Brand.warning,
                    title: "Couldn't confidently identify this — please confirm",
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
    /// isn't a number so we honestly render "—" instead of 0.
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
            return "Insurance service is offline — try again"
        }
        return "Couldn't load insurance"
    }
}

#Preview("325 · Insurance · Night") { InsuranceDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("325 · Insurance · Afternoon") { InsuranceDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
