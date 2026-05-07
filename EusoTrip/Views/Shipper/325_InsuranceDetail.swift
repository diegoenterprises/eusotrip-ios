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

/// Result envelope from `insurance.scanDocument` (Gemini Vision).
/// Surfaces the AI extraction + confidence + warnings on screen so
/// the founder can review before persisting.
private struct COIScanResult: Hashable {
    let carrier: String?
    let policyNumber: String?
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
    /// COI scan state — driver picks a PDF / photo, the bytes are
    /// base64'd and sent to `insurance.scanDocument` (Gemini Vision)
    /// which returns structured carrier / policy / limit / expiry.
    @State private var showCOIPicker: Bool = false
    @State private var scanInflight: Bool = false
    @State private var scanResult: COIScanResult? = nil
    @State private var scanError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                scanCOIRibbon
                if loading { LifecycleCard { Text("Loading insurance…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let c = cert { coiCard(c); ctaRow(c) }
                else { LifecycleCard { Text("No insurance certificate on file.").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                if let s = scanResult { scanResultCard(s) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
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

    /// "Scan COI" CTA — Gemini Vision extracts carrier, policy
    /// number, coverage limits, effective + expiration dates from
    /// any uploaded PDF / image so the founder doesn't have to
    /// re-key them. Replaces the prior "no scan affordance" gap
    /// flagged in the 2026-05-05 Gemini parity audit.
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
                        Text(scanInflight ? "Scanning COI with Gemini Vision…" : "Scan COI with AI")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("Auto-extracts carrier, policy, limits + expiry")
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
        LifecycleCard {
            LifecycleSection(label: "AI EXTRACTED · \(Int((s.confidence ?? 0) * 100))% CONFIDENCE", icon: "sparkles")
            LifecycleRow(label: "Carrier",     value: dashIfEmpty(s.carrier))
            LifecycleRow(label: "Policy",      value: dashIfEmpty(s.policyNumber))
            LifecycleRow(label: "Limit",       value: usd(s.limitUsd))
            LifecycleRow(label: "Effective",   value: humanISO(s.effectiveDate, format: "MMM d, yyyy"))
            LifecycleRow(label: "Expires",     value: humanISO(s.expirationDate, format: "MMM d, yyyy"))
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
                let mime: String = {
                    let ext = url.pathExtension.lowercased()
                    if ext == "pdf" { return "application/pdf" }
                    if ext == "png" { return "image/png" }
                    return "image/jpeg"
                }()
                struct In: Encodable {
                    let fileBase64: String
                    let mimeType: String
                    let filename: String
                }
                struct Out: Decodable {
                    let success: Bool?
                    let carrier: String?
                    let policyNumber: String?
                    let coverageLimits: CoverageLimits?
                    let effectiveDate: String?
                    let expirationDate: String?
                    let confidence: Double?
                    let warnings: [String]?
                    struct CoverageLimits: Decodable {
                        let combinedSingleLimit: Double?
                        let bodilyInjuryPerPerson: Double?
                        let propertyDamage: Double?
                        let cargo: Double?
                    }
                }
                let resp: Out = try await EusoTripAPI.shared.mutation(
                    "insurance.scanDocument",
                    input: In(
                        fileBase64: base64,
                        mimeType: mime,
                        filename: url.lastPathComponent
                    )
                )
                let limit = resp.coverageLimits?.combinedSingleLimit
                    ?? resp.coverageLimits?.bodilyInjuryPerPerson
                    ?? resp.coverageLimits?.propertyDamage
                await MainActor.run {
                    scanResult = COIScanResult(
                        carrier: resp.carrier,
                        policyNumber: resp.policyNumber,
                        limitUsd: limit,
                        effectiveDate: resp.effectiveDate,
                        expirationDate: resp.expirationDate,
                        confidence: resp.confidence,
                        warnings: resp.warnings
                    )
                }
            } catch {
                await MainActor.run {
                    scanError = "Scan failed: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
                }
            }
        }
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
                if let u = URL(string: pdf) { UIApplication.shared.open(u) }
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
}

#Preview("325 · Insurance · Night") { InsuranceDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("325 · Insurance · Afternoon") { InsuranceDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
