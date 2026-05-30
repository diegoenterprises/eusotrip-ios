//
//  006_RailCrossBorderCustoms.swift
//  EusoTrip — Rail · Shipper · Cross-Border Customs (brick 006).
//
//  Verbatim reconstruction of "05 Rail/Dark-SVG/006 Rail Cross-Border Customs.svg"
//  (canvas 440×956, Theme.dark). Read-only SHIPPER vantage on the southbound
//  customs clearance of a single intermodal rail load crossing US→MX at the
//  Laredo / Nuevo Laredo interchange. COMPLIANCE/checklist grammar:
//    detail TopBar (back-chevron + one ✦ eyebrow + mono ID caption + 28/700/-0.4
//    title) → gradient-rimmed clearance hero (interchange · est-crossing figure ·
//    USMCA-eligible badge) → REQUIRED-DOCS southbound checklist (green-check rows)
//    → COMPLIANCE result strip → ETA-at-interchange card → CTA pair.
//  Web parity: client/src/pages/shipper/CrossBorder.tsx (load.mode='rail', country=MX).
//
//  tRPC wiring — REAL contract (the-oath §47, 2026-05-30). The wireframe <desc>
//  said "rail routers NOT mounted (UNVERIFIED)"; that is STALE. Verified live:
//    routers.ts:3178  railShipments:     railShipmentsRouter
//    routers.ts:3051  crossBorderShipping: crossBorderRouter
//    routers.ts:3049  crossBorder:        crossBorderComplianceRouter
//  Anchors actually used by this screen:
//    • shippers.getCrossBorderClearance({ loadId, direction })   PRIMARY
//        → { loadId, direction, cleared, customsStatus, usmcaEligible,
//            interchange?, crossingEstimate?, laneLabel?, carCount?, etaDate?,
//            etaWindow?, docs:[{ name, detail, filed }], missingDocs:[String] }
//        Built + staged THIS fire (shippers.getCrossBorderClearance.patch.ts).
//        It is a single-load consolidation of the SHIPPED-TODAY, verified
//        shippers.getCrossBorderSummary (shippers.ts:2510) cross-referenced
//        against loads.getDocuments for filed-state. Read-only · isolated
//        shipper procedure (isolatedProcedure, trpc.ts:407). Re-check re-queries
//        it (NO write), matching the <desc> "re-check does not write".
//    • loads.getDocuments({ loadId })  (EXISTS · loads.ts:2369) — "View docs".
//  HONEST DEGRADE: every hero sub-field the resolver returns null for
//  (interchange / crossingEstimate / etaWindow when no linked rail row) renders
//  an em-dash — never the SVG's sample values ("~6.5 h", "Laredo IP-LRD").
//  No try?-collapse; the loader is a real do/catch surfacing actionError.
//
//  RBAC: SHIPPER / ADMIN / SUPER_ADMIN (isolated-shipper read). transportMode = rail.
//  Single-country screen rendered for the US→MX interchange (KCS/KCSM · USMCA ·
//  VUCEM · CARTA PORTE; SICT/Aduanas authority) · USD line-haul.
//  Nav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME (LOADS current,
//  supplied by the Shipper nav chrome — this detail screen renders content only,
//  matching 002_RailShipmentDetail).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shapes (decoded from the REAL getCrossBorderClearance payload)

private struct ClearanceDoc006: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let detail: String?
    let filed: Bool
}

private struct CrossBorderClearance006: Decodable {
    let loadId: String?
    let direction: String?         // "SB" | "NB"
    let cleared: Bool?
    let customsStatus: String?     // pending | in_transit | cleared | hold
    let usmcaEligible: Bool?
    let interchange: String?       // null → em-dash
    let crossingEstimate: String?  // null → em-dash
    let laneLabel: String?         // "Laredo TX → Nuevo Laredo MX" or country-level
    let carCount: Int?
    let etaDate: String?           // "05-24" or ISO
    let etaWindow: String?         // "06:00–12:30"
    let docs: [ClearanceDoc006]?
    let missingDocs: [String]?
    let railroad: String?          // "KCS" interline carrier label
}

// MARK: - Screen

struct RailCrossBorderCustoms_006: View {
    @Environment(\.palette) private var palette

    /// The shipper's load whose southbound clearance this screen shows.
    let loadId: Int
    /// Direction defaults to southbound (US→MX) for this interchange screen.
    var direction: String = "SB"

    // Real loading + error state (honest wiring; no try?-collapse).
    @State private var clearance: CrossBorderClearance006? = nil
    @State private var documents: [DocRow006] = []
    @State private var loading = true
    @State private var actionError: String? = nil
    @State private var rechecking = false
    @State private var showDocs = false

    private struct DocRow006: Decodable, Identifiable {
        let id: String
        let type: String?
        let name: String?
        let fileUrl: String?
        let status: String?
        let createdAt: String?
    }

    // MARK: Derived display

    private var isCleared: Bool { clearance?.cleared ?? false }
    private var statusWord: String {
        switch (clearance?.customsStatus ?? "").lowercased() {
        case "cleared":     return "CLEARED"
        case "hold":        return "HOLD"
        case "in_transit":  return "IN TRANSIT"
        case "":            return loading ? "…" : "—"
        default:            return "PENDING"
        }
    }
    private var statusColor: Color {
        switch statusWord {
        case "CLEARED":    return Brand.success
        case "HOLD":       return Brand.danger
        case "…", "—":     return palette.textTertiary
        default:           return Brand.warning
        }
    }
    private func dash(_ s: String?) -> String {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return "—" }
        return s
    }
    private var missingCount: Int { clearance?.missingDocs?.count ?? 0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if let err = actionError {
                        errorBanner(err)
                    }
                    heroCard
                    docsSection
                    complianceStrip
                    etaSection
                    ctaRow
                    Color.clear.frame(height: 96)   // Shipper nav chrome spacer
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showDocs) { docsSheet }
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · RAIL · CROSS-BORDER · US→MX")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(statusWord)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(statusColor)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Border clearance")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: Space.s2)
            }
            .padding(.top, Space.s4)
            Text(idCaption)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s1)
        }
        .padding(.top, Space.s5)
    }

    private var idCaption: String {
        let rr = dash(clearance?.railroad)
        let id = clearance?.loadId ?? "load_\(loadId)"
        return rr == "—" ? id : "\(id) · \(rr)"
    }

    // MARK: - Hero (gradient-rimmed clearance)

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.primary)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("INTERCHANGE · \(dash(clearance?.interchange).uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    Spacer()
                    if clearance?.usmcaEligible == true {
                        Text("USMCA ELIGIBLE")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(Color(hex: 0x00966B))
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(
                                Capsule().fill(Brand.success.opacity(0.16))
                            )
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(dash(clearance?.crossingEstimate))
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("est. crossing")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(carLine)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }
                .padding(.top, Space.s4)

                Text(dash(clearance?.laneLabel))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s3)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(20)
        }
        .frame(minHeight: 104)
    }

    private var carLine: String {
        let n = clearance?.carCount ?? 0
        let rr = dash(clearance?.railroad)
        if n <= 0 { return rr == "—" ? "intermodal · rail" : "intermodal · \(rr)" }
        let noun = n == 1 ? "intermodal car" : "intermodal cars"
        return rr == "—" ? "\(n) \(noun)" : "\(n) \(noun) · \(rr)"
    }

    // MARK: - Required docs checklist

    private var docsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("REQUIRED DOCS · \(direction == "NB" ? "NORTHBOUND" : "SOUTHBOUND")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            let rows = clearance?.docs ?? []
            VStack(spacing: 0) {
                if rows.isEmpty {
                    HStack {
                        Text(loading ? "Loading required documents…"
                                     : "No southbound documents required for this lane.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                    }
                    .padding(Space.s4)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, doc in
                        docRow(doc)
                        if idx < rows.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                .padding(.leading, Space.s4)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private func docRow(_ doc: ClearanceDoc006) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill((doc.filed ? Brand.success : Brand.warning).opacity(0.16))
                    .frame(width: 24, height: 24)
                Image(systemName: doc.filed ? "checkmark" : "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(doc.filed ? Brand.success : Brand.warning)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let d = doc.detail, !d.isEmpty {
                    Text(d)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: Space.s2)
            Text(doc.filed ? "FILED" : "MISSING")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(doc.filed ? Color(hex: 0x00966B) : Brand.warning)
        }
        .padding(Space.s4)
    }

    // MARK: - Compliance strip

    private var complianceStrip: some View {
        let ok = isCleared
        let tint = ok ? Brand.success : Brand.warning
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                Circle().fill(tint).frame(width: 24, height: 24)
                Image(systemName: ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ok ? "All elements met · no DG declared"
                        : "\(missingCount) document\(missingCount == 1 ? "" : "s") outstanding")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(ok ? "VUCEM filing accepted · clear to interchange"
                        : "Resolve in the yard before the car reaches the border")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            Text(ok ? "COMPLIANT" : "ACTION")
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                .foregroundStyle(ok ? Color(hex: 0x00966B) : Brand.warning)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(0.30), lineWidth: 1)
                )
        )
    }

    // MARK: - ETA at interchange

    private var etaSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ETA AT INTERCHANGE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Brand.blue.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "clock")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color(hex: 0x5AA0FF))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(etaArrivalLine)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("CARTA PORTE on car")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(dash(clearance?.etaWindow))
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("cleared window")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private var etaArrivalLine: String {
        let interchange = dash(clearance?.interchange)
        let date = dash(clearance?.etaDate)
        if interchange == "—" && date == "—" { return "Arrival window pending" }
        if date == "—" { return "Arrives \(interchange)" }
        if interchange == "—" { return "Arrives · \(date)" }
        return "Arrives \(interchange) · \(date)"
    }

    // MARK: - CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await recheck() } } label: {
                HStack(spacing: Space.s2) {
                    if rechecking { ProgressView().tint(.white) }
                    Text(rechecking ? "Re-checking…" : "Re-check compliance")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(LinearGradient.primary))
            }
            .disabled(rechecking)

            Button { showDocs = true } label: {
                Text("View docs")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(
                        Capsule()
                            .fill(Color(hex: 0x232932))   // verbatim SVG secondary fill
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    )
            }
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.warning)
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Brand.warning.opacity(0.10))
        )
    }

    // MARK: - Docs sheet (real loads.getDocuments)

    private var docsSheet: some View {
        NavigationStack {
            List {
                if documents.isEmpty {
                    Text("No documents on file for this load yet.")
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(documents) { d in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.name ?? d.type ?? "Document")
                                .font(.system(size: 14, weight: .semibold))
                            HStack(spacing: Space.s2) {
                                if let t = d.type { Text(t.uppercased()) }
                                if let s = d.status { Text("· \(s)") }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
            }
            .navigationTitle("Customs documents")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Loaders (single REAL endpoint each — honest do/catch)

    private func load() async {
        loading = true; actionError = nil
        struct ClearanceIn: Encodable { let loadId: String; let direction: String }
        struct DocsIn: Encodable { let loadId: String }
        let idStr = "load_\(loadId)"
        do {
            // PRIMARY · shippers.getCrossBorderClearance (staged §47).
            let c: CrossBorderClearance006 = try await EusoTripAPI.shared.query(
                "shippers.getCrossBorderClearance",
                input: ClearanceIn(loadId: idStr, direction: direction))
            self.clearance = c
        } catch {
            actionError = "Couldn’t load clearance status. " +
                ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        // Best-effort doc enrichment for the sheet (non-blocking; sheet shows its
        // own empty state). EXISTS · loads.getDocuments (loads.ts:2369).
        if let docs: [DocRow006] = try? await EusoTripAPI.shared.query(
            "loads.getDocuments", input: DocsIn(loadId: String(loadId))) {
            self.documents = docs
        }
        loading = false
    }

    private func recheck() async {
        rechecking = true
        await load()       // read-only re-query (NO write), per <desc>
        rechecking = false
    }
}

// MARK: - Previews

#Preview("006 · Rail Cross-Border Customs · Night") {
    RailCrossBorderCustoms_006(loadId: 66120)
        .preferredColorScheme(.dark)
}
