//
//  393_CatalystDocumentIngest.swift
//  EusoTrip — Catalyst · Document Ingest (carrier-side AI document intake).
//
//  Verbatim iOS port of "03 Catalyst/Code/393_CatalystDocumentIngest.swift"
//  into the house Shell + BottomNav chrome. CARRIER-SIDE.
//
//  AI document intake: an auto-classified-rate hero (% of docs today
//  auto-extracted), a classifyDocument ingest-queue card of rows by type
//  (BOL · RATECON · POD · LUMPER · SCALE) with per-doc confidence, a
//  bulkExtractLoads source strip, and the classifyDocument CTA. Cross-mode
//  parity gap fill — Rail (590) and Vessel (693) had Document Ingest
//  surfaces; the Truck Catalyst band had none against the mode-agnostic
//  aiDocProcessor router. Docked under DISPATCH.
//
//  PERSONA: CATALYST — Aurora Freight Lines · USDOT 3 482 119. Source docs
//  from shipper Eusorone Technologies (DU) and driver Michael Eusorone (ME)
//  at the dock.
//
//  WIRING MANIFEST (Code/ spec · aiDocProcessor.ts):
//    • aiDocProcessor.classifyDocument (aiDocProcessor.ts:15) — queue rows
//      + mutation · CTA.
//    • aiDocProcessor.bulkExtractLoads (aiDocProcessor.ts:45) — extraction
//      strip.
//    • aiDocProcessor.enhanceBolPhoto (aiDocProcessor.ts:80) — POD/BOL row.
//
//  LIVE WIRING (zero-fallback purge · 2026-06-09 · audit M6): the queue
//  rows AND the hero counters both hydrate from the real
//  `documentManagement.getDocuments` (EusoTripAPI.swift:7830) with do/catch
//  + a surfaced loadError and honest empty states. NO seed rows remain.
//  Per-row OCR confidence has no live source on mobile (aiDocProcessor.*
//  unbound) — the right column shows the document's REAL status instead,
//  and the classify CTA is honestly disabled until that namespace binds.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystDocumentIngestScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            DocumentIngestBody_393()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_393(),
                trailing: catalystNavTrailing_393(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_393() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_393() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "truck.box",          isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.crop.circle", isCurrent: true)]
}

// MARK: - Body

private struct DocumentIngestBody_393: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    // Live state — empty/zero until documentManagement.getDocuments answers.
    // No seed rows, no seeded hero figures (zero-fallback purge · audit M6).
    @State private var rows: [IngestRow_393] = []
    @State private var autoPct: Int = 0
    @State private var totalDocs: Int = 0
    @State private var autoExtracted: Int = 0
    @State private var needsReview: Int = 0
    @State private var failed: Int = 0
    @State private var syncedAgo: String = "—"

    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var hydrated: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            topBar_393
            titleBlock_393
            IridescentHairline()
                .padding(.horizontal, -20)

            if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    HStack {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        Spacer(minLength: 0)
                        Button { Task { await loadAll() } } label: {
                            Text("Retry").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                        }.buttonStyle(.plain)
                    }
                }
            }

            heroCard_393

            sectionEyebrow_393("INGEST QUEUE · LIVE DOCUMENTS")
            queueCard_393

            sourceStrip_393

            // Honestly disabled — aiDocProcessor.classifyDocument is not
            // bridged on the mobile client; no fake in-flight spinner.
            CTAButton(
                title: "Classify new upload",
                action: {},
                trailingIcon: "wand.and.stars",
                subtitle: "Not yet available on mobile"
            )
            .disabled(true)
            .opacity(0.5)

            provenanceFootnote_393

            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
    }

    // MARK: TopBar

    private var topBar_393: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DOCUMENT INGEST")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("AI OCR")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock_393: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Document Ingest")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("AI document intake · live queue")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Hero — auto-classified rate today

    private var heroCard_393: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AUTO-CLASSIFIED · TODAY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // "live" badge is earned: only after a real hydrate succeeds.
                Text(hydrated ? "live" : (loading ? "loading" : "offline"))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(hydrated ? Brand.success : palette.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(hydrated ? Brand.success.opacity(0.14) : palette.bgCardSoft))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(hydrated && totalDocs > 0 ? "\(autoPct)%" : "—")
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(hydrated ? "of \(totalDocs) docs" : "of — docs")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(hydrated
                 ? "\(autoExtracted) auto-extracted · \(needsReview) needs review · \(failed) failed"
                 : "—")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
            Text(syncedAgo)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Ingest queue card

    private var queueCard_393: some View {
        VStack(spacing: 0) {
            if loading && rows.isEmpty {
                Text("Loading documents…")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else if rows.isEmpty {
                EusoEmptyState(
                    systemImage: "doc.viewfinder",
                    title: "No documents in the queue",
                    subtitle: "Uploaded BOLs, rate cons, PODs and receipts appear here with their intake status."
                )
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, d in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(d.type)
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 78, alignment: .leading)
                        Text(d.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Text(d.confidence)
                            .font(.system(size: 10.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(d.ok ? Brand.success : Brand.warning)
                    }
                    .padding(.vertical, 9)
                    if idx != rows.count - 1 {
                        Rectangle()
                            .fill(palette.borderFaint)
                            .frame(height: 1)
                    }
                }
                HStack {
                    Text("Live document records · per-row OCR confidence not yet connected")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.top, 6)
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

    // MARK: Source strip — bulkExtractLoads

    private var sourceStrip_393: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SOURCES")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("Driver camera captures at the dock + portal uploads feed this queue")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Bulk extraction (bulkExtractLoads) isn't connected on mobile yet")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.blue.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.blue.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Provenance footnote

    private var provenanceFootnote_393: some View {
        Text("documentManagement.getDocuments · live")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Section eyebrow helper

    private func sectionEyebrow_393(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: Network — live documentManagement.getDocuments, surfaced errors

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }

        do {
            let resp = try await EusoTripAPI.shared.documentManagement.getDocuments(page: 1, pageSize: 50)
            let docs = resp.documents
            let total = resp.total > 0 ? resp.total : docs.count

            let pendingStates: Set<String> = ["pending", "uploaded", "processing", "review"]
            let needs = docs.filter { pendingStates.contains($0.status.lowercased()) }.count
            let fail = docs.filter { ["rejected", "failed"].contains($0.status.lowercased()) }.count
            let extracted = max(0, total - needs - fail)
            let pct = total > 0 ? Int((Double(extracted) / Double(total) * 100.0).rounded()) : 0

            self.rows = docs.prefix(8).map { mapRow_393($0) }
            self.totalDocs = total
            self.autoExtracted = extracted
            self.needsReview = needs
            self.failed = fail
            self.autoPct = pct
            self.syncedAgo = "synced just now"
            self.hydrated = true
        } catch {
            self.rows = []
            self.hydrated = false
            self.syncedAgo = "—"
            self.loadError = "Couldn't reach the document service - retry."
        }
    }

    /// Map one live `documentManagement.getDocuments` record to a queue row.
    /// Right column is the document's real status — per-row OCR confidence
    /// has no live source on mobile, so it is never invented.
    private func mapRow_393(_ d: DocumentManagementAPI.Document) -> IngestRow_393 {
        let status = d.status.lowercased()
        let ok = !["pending", "uploaded", "processing", "review", "rejected", "failed"].contains(status)
        let typeTag = String(d.type.replacingOccurrences(of: "_", with: " ").uppercased().prefix(9))
        return IngestRow_393(
            type: typeTag.isEmpty ? "DOC" : typeTag,
            detail: d.name,
            confidence: status.isEmpty ? "—" : status,
            ok: ok
        )
    }
}

// MARK: - Ingest queue row model (built from live records only)

private struct IngestRow_393: Identifiable, Equatable {
    let id = UUID()
    let type: String
    let detail: String
    let confidence: String
    let ok: Bool
}

// MARK: - Previews

#Preview("393 · Catalyst · Document Ingest · Night") {
    CatalystDocumentIngestScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("393 · Catalyst · Document Ingest · Afternoon") {
    CatalystDocumentIngestScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
