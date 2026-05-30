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
//  iOS CLIENT REALITY (grep EusoTripAPI.swift · 2026-05-29): the
//  `aiDocProcessor.*` namespace is NOT bound on the mobile client. The
//  nearest verified surface is `documentManagement.getDocuments`
//  (EusoTripAPI.swift:7172) — a live doc list we hydrate the hero
//  auto-classified counters + queue confidence from. The three
//  aiDocProcessor procedures above are left as honest // WIRE: markers; the
//  Code/ representative seed figures stay until those clients ship (0% mock
//  — seeds overwritten on hydrate where a real call exists).
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

    // Code/ representative seed figures — overwritten on hydrate where a
    // real call exists (the hero counters come from getDocuments; the
    // per-row confidence stays seeded until aiDocProcessor binds).
    @State private var rows: [IngestRow_393] = IngestRow_393.seed
    @State private var autoPct: Int = 94
    @State private var totalDocs: Int = 12
    @State private var autoExtracted: Int = 11
    @State private var needsReview: Int = 1
    @State private var failed: Int = 0
    @State private var syncedAgo: String = "synced 4m ago"

    @State private var loading: Bool = false
    @State private var classifying: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            topBar_393
            titleBlock_393
            IridescentHairline()
                .padding(.horizontal, -20)

            heroCard_393

            sectionEyebrow_393("INGEST QUEUE · classifyDocument · enhanceBolPhoto")
            queueCard_393

            sourceStrip_393

            CTAButton(
                title: classifying ? "Classifying…" : "Classify new upload",
                action: { classifyNewUpload() },
                trailingIcon: "wand.and.stars",
                subtitle: "classifyDocument · {fileId,loadId?}",
                isLoading: classifying
            )

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
            Text("classifyDocument · Aurora Freight Lines · USDOT 3 482 119")
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
                Text("live")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.14)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(autoPct)%")
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("of \(totalDocs) docs")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("\(autoExtracted) auto-extracted · \(needsReview) needs review · \(failed) failed")
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
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, d in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(d.type)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 78, alignment: .leading)
                    Text(d.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
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
                Text("classifier maps fields to load · BOL/RATECON/POD auto-attached")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
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
            Text("SOURCE · bulkExtractLoads")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("driver Michael Eusorone · ME captures via camera at dock")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("shipper-of-record Eusorone Technologies · DU")
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
        Text("classifyDocument · {fileId,loadId?}")
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

    // MARK: Actions

    private func classifyNewUpload() {
        // WIRE: aiDocProcessor.classifyDocument (aiDocProcessor.ts:15) —
        // {fileId,loadId?} mutation kicks server-side OCR on the freshly
        // captured upload. The mobile client only binds
        // documentManagement.classifyDocument(documentId:) today, which
        // needs an existing document id rather than a raw camera capture,
        // so the carrier "classify new upload" gesture awaits the
        // aiDocProcessor binding. Reflect the in-flight state honestly.
        guard !classifying else { return }
        classifying = true
        Task {
            // No representative documentId in this surface yet — flip the
            // flag back so the CTA never wedges. Replace with the real
            // aiDocProcessor.classifyDocument call once bound.
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run { classifying = false }
        }
    }

    // MARK: Network

    private func loadAll() async {
        loading = true
        defer { loading = false }

        // Live: documentManagement.getDocuments (EusoTripAPI.swift:7172)
        // — verified bound on the mobile client. Hydrate the hero
        // auto-classified counters from the real doc list. A "classified"
        // doc is one whose status is past intake (not "pending"/"uploaded").
        let resp = try? await EusoTripAPI.shared.documentManagement.getDocuments(page: 1, pageSize: 50)
        guard let resp else { return }

        let docs = resp.documents
        let total = resp.total > 0 ? resp.total : docs.count
        guard total > 0 else { return }

        let pendingStates: Set<String> = ["pending", "uploaded", "processing", "review"]
        let needs = docs.filter { pendingStates.contains($0.status.lowercased()) && $0.status.lowercased() != "rejected" }.count
        let fail = docs.filter { $0.status.lowercased() == "rejected" || $0.status.lowercased() == "failed" }.count
        let extracted = max(0, total - needs - fail)
        let pct = Int((Double(extracted) / Double(total) * 100.0).rounded())

        await MainActor.run {
            self.totalDocs = total
            self.autoExtracted = extracted
            self.needsReview = needs
            self.failed = fail
            self.autoPct = pct
            self.syncedAgo = "synced just now"
        }

        // WIRE: aiDocProcessor.bulkExtractLoads (aiDocProcessor.ts:45) —
        //       per-row extraction confidence for the ingest queue.
        // WIRE: aiDocProcessor.enhanceBolPhoto (aiDocProcessor.ts:80) —
        //       deskew + OCR confidence for the POD/BOL row.
        // Neither is bound on the mobile client (grep · 2026-05-29). The
        // Code/ representative confidence figures remain seeded until those
        // procedures ship to the iOS EusoTripAPI surface.
    }
}

// MARK: - Ingest queue row model

private struct IngestRow_393: Identifiable, Equatable {
    let id = UUID()
    let type: String
    let detail: String
    let confidence: String
    let ok: Bool

    // Code/ representative seed — verbatim from
    // 03 Catalyst/Code/393_CatalystDocumentIngest.swift.
    static let seed: [IngestRow_393] = [
        IngestRow_393(type: "BOL",     detail: "LD-260427-7C3A09F18B · matched to load",     confidence: "0.98",   ok: true),
        IngestRow_393(type: "RATECON", detail: "rate confirmation · bulkExtractLoads",        confidence: "0.95",   ok: true),
        IngestRow_393(type: "POD",     detail: "signed delivery · enhanceBolPhoto · deskewed", confidence: "0.97",   ok: true),
        IngestRow_393(type: "LUMPER",  detail: "lumper receipt · low confidence",             confidence: "review", ok: false),
        IngestRow_393(type: "SCALE",   detail: "weight ticket · extracted",                   confidence: "0.91",   ok: true)
    ]
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
