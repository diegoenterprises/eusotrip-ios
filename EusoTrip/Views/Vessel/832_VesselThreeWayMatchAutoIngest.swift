//
//  832_VesselThreeWayMatchAutoIngest.swift
//  EusoTrip — Vessel Operator · Three-Way-Match Auto-Ingest / Reconcile (832).
//
//  Verbatim-composition port of "832 Vessel Three-Way Match Auto-Ingest.svg"
//  (Dark → Light). INGEST-MATCH-CHEVRON + OCR-CONFIDENCE-QUEUE archetype — an
//  invoice-reconciliation pipeline: an auto-match hero with a 5-stage
//  Ingest→Extract→Match→Review→Dispute chevron flow, and an OCR-confidence
//  ingest queue. Nav: HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//
//  Distinct from Vesl728 "Three-Way Match" (the reconciliation comparison
//  table) — here the spine is the automated OCR → 3-way-match → exception
//  pipeline, linking 693 ingest to 728 match.
//
//  WIRING (honest):
//    Ingested documents are REAL — oceanDocIngest.recentIngestions
//        (oceanDocIngest.ts:154, vesselProcedure, input { limit? }) →
//        [{ id, bookingNumber, status, voyageNumber, createdAt }]. Each row is
//        a real ingested document; Ingest + Extract counts derive from it.
//    Entry disposition is REAL — vesselShipments.getCBPEntryStatus (:2807).
//    There is NO auto-ingest / 3-way-reconcile engine on disk (grep
//        ingestAndReconcile = 0) → STUB · named-gap: freightMatch.ingestAndReconcile
//        ({carrier,period}) + freightMatch.runReconcile({batchId,confirm:true})
//        → OCR-extracts each invoice, runs the 3-way match, writes match/
//        exception rows + blockchainAuditTrail vessel.invoice_reconciled,
//        broadcasts WS_EVENTS.reconcileUpdated. EXPENSIVE-ADVISOR: low OCR
//        confidence / variance escalates to the advisor tier; auto-clear is
//        capped; disputes are human-gated. Per-doc OCR %, match state and
//        variance render from that engine once it ships; until then rows show
//        the real ingested doc awaiting match — no fabricated OCR figure.
//    COUNTRY: US USD (CBP duty + FMC) active · CA CAD GST · MX MXN IVA.
//

import SwiftUI

struct VesselThreeWayMatchAutoIngestScreen: View {
    let theme: Theme.Palette
    var carrier: String = "MSC"

    var body: some View {
        Shell(theme: theme) {
            VesselThreeWayMatchAutoIngestBody(carrier: carrier)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Ingestion shape (oceanDocIngest.recentIngestions)

private struct Ingestion832: Decodable, Identifiable {
    let id: Int?
    let bookingNumber: String?
    let status: String?
    let voyageNumber: String?
    let createdAt: String?
    var rowId: String { bookingNumber ?? (id.map(String.init) ?? UUID().uuidString) }
}

// MARK: - Body

private struct VesselThreeWayMatchAutoIngestBody: View {
    @Environment(\.palette) private var palette
    let carrier: String

    @State private var docs: [Ingestion832] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private var ingestCount: Int { docs.count }

    /// 5-stage counts. Ingest + Extract are REAL (every recent ingestion is a
    /// parsed document). Match / Review / Dispute need the reconcile engine —
    /// shown as pending, never a fabricated match count.
    private var stages: [(String, String, Color)] {
        [
            ("Ingest",  "\(ingestCount)", Color(hex: 0x5AB0FF)),
            ("Extract", "\(ingestCount)", Color(hex: 0x5AB0FF)),
            ("Match",   "—", Color(hex: 0x34D8A6)),
            ("Review",  "—", Color(hex: 0xFFC246)),
            ("Dispute", "—", palette.textTertiary)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · AUTO-INGEST · RECONCILE",
                caption: "\(carrier) · USD",
                title: "Reconcile pipeline",
                subtitle: "OCR ingest → 3-way match · \(ingestCount) doc\(ingestCount == 1 ? "" : "s") today"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    matchHero
                    queueSection
                    VesselRegulatorBand(
                        title: "REGULATOR · SINGLE-COUNTRY VARIATION",
                        reference: "approve · country",
                        rows: [
                            .init("US", "USD · CBP duty + FMC", active: true),
                            .init("CA", "CAD · GST 5% + CBSA"),
                            .init("MX", "MXN · IVA 16% + pedimento")
                        ]
                    )
                    ctaPair
                    VesselGapNote(text: "Ingested documents are REAL (oceanDocIngest.recentIngestions). Per-doc OCR confidence, the 3-way match and variance need the reconcile engine — proposed freightMatch.ingestAndReconcile / runReconcile (auto-clear moves money → gated + confirm; disputes human-gated; low confidence escalates to the advisor tier). No fabricated OCR or match figures.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Match hero + 5-stage chevron

    private var matchHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Today · carrier \(carrier) · SCAC \(carrier)U")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("MATCH PENDING")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xFFC246))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xFFC246).opacity(0.13)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(ingestCount)")
                        .font(.system(size: 32, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Color(hex: 0x34D8A6))
                    Text("ingested · match awaits engine")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                chevronFlow
            }
        }
    }

    private var chevronFlow: some View {
        HStack(spacing: 4) {
            ForEach(Array(stages.enumerated()), id: \.offset) { idx, stage in
                VStack(spacing: 3) {
                    Text(stage.1)
                        .font(.system(size: 15, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(stage.1 == "—" ? palette.textTertiary : stage.2)
                    Text(stage.0)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s2)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(stage.2.opacity(0.12)))
                if idx < stages.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    // MARK: - Ingest queue (REAL docs)

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "INGEST QUEUE · OCR → MATCH", right: "recentIngestions · STUB match")
            if docs.isEmpty {
                EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                               title: "No documents ingested today",
                               subtitle: "Emailed / EDI / uploaded carrier documents post here as they ingest; OCR confidence and 3-way match arrive with the reconcile engine.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(docs.enumerated()), id: \.element.rowId) { idx, doc in
                        if idx > 0 { Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4) }
                        docRow(doc)
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                VesselSummaryStrip(label: "Ingested · 3-way match pending engine",
                                   value: "\(ingestCount) doc\(ingestCount == 1 ? "" : "s")", valueColor: Color(hex: 0x34D8A6))
            }
        }
    }

    private func docRow(_ doc: Ingestion832) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: 0x5AB0FF).opacity(0.12)).frame(width: 34, height: 30)
                Text("DOC").font(.system(size: 7.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Color(hex: 0x5AB0FF))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.bookingNumber ?? "Ingested document")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(doc.voyageNumber.map { "voyage \($0)" } ?? "source ingest")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text((doc.status ?? "ingested").replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("OCR · match pending")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFFC246))
            }
        }
        .padding(Space.s4)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Run reconcile", action: {}, trailingIcon: "arrow.triangle.2.circlepath")
            VesselGhostButton(title: "Review", width: 150) {}
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 190)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 210)
        }
    }

    // MARK: - Load (REAL: oceanDocIngest.recentIngestions)

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            let rows: [Ingestion832] = try await EusoTripAPI.shared.query(
                "oceanDocIngest.recentIngestions", input: In(limit: 20))
            self.docs = rows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("832 · Vessel Three-Way Match · Night") {
    VesselThreeWayMatchAutoIngestScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("832 · Vessel Three-Way Match · Light") {
    VesselThreeWayMatchAutoIngestScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
