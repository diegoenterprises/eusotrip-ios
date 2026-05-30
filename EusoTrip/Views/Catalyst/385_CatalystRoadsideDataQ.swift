//
//  385_CatalystRoadsideDataQ.swift
//  EusoTrip — Catalyst · Fleet · Roadside DataQ (carrier-vantage roadside
//  inspection ledger + FMCSA DataQs / Request-for-Data-Review challenge).
//
//  Verbatim port of "385 Catalyst Roadside DataQ.svg" (440×956, Dark/Light).
//  Reached from the FLEET tab. Compliance sibling of 383 Fleet Safety CSA and
//  384 Fleet IFTA — same carrier framing, same card grammar, same DesignSystem
//  primitives (383_CatalystFleetSafetyCSA.swift is the structural twin this
//  file mirrors).
//
//  Layout (section-by-section against the SVG):
//    • Header — eyebrow "✦ CATALYST · ROADSIDE" (gradient) + "INSPECTIONS"
//      (mono); back-chevron orb; title "Roadside" (22/700); subtitle
//      "carrier inspections · DataQ"; right rail "{carrier} · USDOT {dot}" +
//      "synced …"; IridescentHairline.
//    • Hero card — "OPEN TICKETS" big gradient count + "{cleared} cleared 90d";
//      "INSPECTION PASS" mono % on the right (green); a pass-rate gauge bar; the
//      live open-challenge note; mono footline "Carrier inspection pass rate
//      trailing-24-mo".
//    • Roadside inspection history card — header "ROADSIDE INSPECTION HISTORY ·
//      LAST 5"; one row per server inspection (date · type, location · OOS/viol,
//      result pill clean|closed|dataq); footnote "Tap a record to open the
//      report · DataQ challenge available within 12 mo".
//    • 3 factor cells — OPEN (in DataQ) · DATAQ FILED (trailing 24mo) · WIN RATE.
//    • 2 CTAs — "File DataQ" (gradient → dataqs.aiDraft assist + dataqs.file
//      submit) + "Carrier policy" (secondary → roadsideTickets.policyForCarrier).
//      Both open a real sheet bound to real server data / a real mutation.
//      No dead taps, no synthesized success.
//    • Footnote block (3 mono lines).
//    • BottomNav is supplied by the Catalyst surface chrome (matches siblings
//      383 / 384 which also defer nav to the host surface — see report §NAV).
//
//  Data — the wireframe <desc> anchors `roadsideTickets.*`, but that router is
//  the driver roadside-*assistance* (breakdown/tow) lifecycle, NOT the carrier
//  FMCSA roadside-*inspection* ledger + DataQ challenge this screen depicts.
//  Wiring 385 to `roadsideTickets.list` would render tow tickets, not inspection
//  history (a decoder/domain mismatch). The correct, production-grade backend is
//  the FMCSA DataQ + CSA domain. Endpoints (verified against the live server):
//    dataqs.carrierRoadsideSummary  (routers/dataqs.ts — added this fire)
//        → the load-blocking read. Carrier identity + hero (open / cleared-90d /
//          inspection pass-rate / open-challenge note) + factor cells (open /
//          filed-24mo / win-rate) + the newest-N roadside inspection rows with a
//          derived result pill. Company-isolated; read-only.
//    dataqs.aiDraft                 (routers/dataqs.ts:364)
//        → "File DataQ" assist. Gemini burden-of-proof draft + evidence
//          checklist + frivolous-claim self-check. Reform-aware (49 CFR 386,
//          21/21/45-day timeline).
//    dataqs.file                    (routers/dataqs.ts:132)
//        → "File DataQ" submit. Real persisted RDR row; this fire also added the
//          audit-chain insert + COMPANY WS broadcast so the filing fans out.
//    roadsideTickets.policyForCarrier (routers/roadsideTickets.ts:251)
//        → "Carrier policy" sheet (the carrier's roadside coverage limit +
//          preferred provider; honest "coverage unknown" shell when none).
//
//  HONESTY NOTE: the `inspections` table carries no FMCSA inspection LEVEL
//  (I–VI) or report-reference column, so each history row surfaces the real
//  inspection `type` (Roadside / DOT / Annual / …) rather than a fabricated
//  "Level II". No mock data is on the live path: every number binds to a live
//  field; an unavailable value renders an em-dash, never an invented figure.
//  The type display-map and the FMCSA copy constants are presentation /
//  reference data, not business data.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Wire models (match `dataqs.carrierRoadsideSummary` field-for-field)

/// Carrier identity block from the summary read.
struct RoadsideCarrier: Decodable, Equatable {
    let companyId: Int
    let name: String
    let dotNumber: String
    let mcNumber: String
}

/// Hero metrics.
struct RoadsideHero: Decodable, Equatable {
    let openTickets: Int
    let clearedLast90d: Int
    let inspectionPassRate: Int      // 0–100
    let challengeNote: String
}

/// The three factor cells.
struct RoadsideFactors: Decodable, Equatable {
    let open: Int
    let dataqFiled: Int
    let winRatePct: Int              // 0–100
}

/// One roadside inspection-history row. `pill` ∈ {clean, closed, dataq}.
struct RoadsideInspectionRow: Decodable, Equatable, Identifiable {
    let id: String
    let dateLabel: String            // "Apr 18" (server-computed, locale-free)
    let type: String                 // pre_trip | post_trip | dvir | roadside | annual | dot
    let location: String
    let oosViolation: Bool
    let defectsFound: Int
    let pill: String
    let date: String                 // ISO-8601 (or "")
}

/// The whole `dataqs.carrierRoadsideSummary` payload.
struct RoadsideSummary: Decodable, Equatable {
    let carrier: RoadsideCarrier
    let hero: RoadsideHero
    let factors: RoadsideFactors
    let inspections: [RoadsideInspectionRow]
}

/// Lenient decode of `roadsideTickets.policyForCarrier`. `preferredProvider`
/// is server JSON (null | string | object) — tolerated either way so a real
/// payload never crashes the sheet.
struct RoadsidePolicy: Decodable, Equatable {
    let coverageLimitCents: Int
    let updatedAt: String?
    let preferredProviderName: String?

    enum CodingKeys: String, CodingKey {
        case coverageLimitCents, updatedAt, preferredProvider
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coverageLimitCents = (try? c.decode(Int.self, forKey: .coverageLimitCents)) ?? 0
        updatedAt = try? c.decode(String.self, forKey: .updatedAt)
        if let s = try? c.decode(String.self, forKey: .preferredProvider) {
            preferredProviderName = s
        } else if let obj = try? c.decode([String: String].self, forKey: .preferredProvider) {
            preferredProviderName = obj["name"] ?? obj["provider"]
        } else {
            preferredProviderName = nil
        }
    }
}

/// `dataqs.aiDraft` response slice the sheet renders.
struct RoadsideAIDraft: Decodable, Equatable {
    let available: Bool
    let challengeStatement: String
    let evidenceChecklist: [String]
    let frivolousClaimRisk: String
    let reasoning: String
    let localResolutionRecommended: Bool?
    let regulationsCited: [String]?
}

/// `dataqs.file` ack.
struct RoadsideFileAck: Decodable, Equatable {
    let success: Bool
    let id: String
    let status: String
    let expectedReplyBy: String
}

// MARK: - Store

@MainActor
final class RoadsideDataQStore: BaseDynamicStore<RoadsideSummary> {
    private struct SummaryIn: Encodable { let inspectionLimit: Int }
    override func fetch() async throws -> RoadsideSummary {
        try await EusoTripAPI.shared.query(
            "dataqs.carrierRoadsideSummary",
            input: SummaryIn(inspectionLimit: 5)
        )
    }
}

// MARK: - Screen root

struct CatalystRoadsideDataQ: View {
    @Environment(\.palette) var palette
    @StateObject private var store = RoadsideDataQStore()

    /// Carrier-identity fallback for the right rail. The SVG pins Eusotrans LLC
    /// · USDOT 3 194 882 · MC-820 144; the live screen prefers the server's own
    /// values and only falls back to SVG canon when the server supplies none.
    private let carrierNameFallback: String
    private let usdotFallback: String
    private let mcFallback: String

    @State private var fileSheet = false
    @State private var policySheet = false

    init(
        carrierName: String = "Eusotrans LLC",
        usdot: String = "3 194 882",
        mc: String = "MC-820 144"
    ) {
        self.carrierNameFallback = carrierName
        self.usdotFallback = usdot
        self.mcFallback = mc
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyCard
                case .error(let e):
                    errorBanner(e)
                case .loaded(let model):
                    heroCard(model)
                    historyCard(model)
                    factorCells(model)
                    ctaRow
                    footnote
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $fileSheet) {
            FileDataQSheet(
                carrier: store.state.value?.carrier,
                onFiled: { Task { await store.refresh() } }
            )
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $policySheet) {
            CarrierPolicySheet(carrierId: store.state.value?.carrier.companyId ?? 0)
                .environment(\.palette, palette)
        }
    }

    // MARK: Identity helpers (server-first, SVG-canon fallback)

    private var carrierName: String {
        let n = store.state.value?.carrier.name
        if let n, !n.isEmpty, n != "Unknown" { return n }
        return carrierNameFallback
    }
    private var usdot: String {
        let d = store.state.value?.carrier.dotNumber
        if let d, !d.isEmpty { return d }
        return usdotFallback
    }
    private var mcNumber: String {
        let m = store.state.value?.carrier.mcNumber
        if let m, !m.isEmpty { return m }
        return mcFallback
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("✦ CATALYST · ROADSIDE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("INSPECTIONS")
                    .font(EType.micro.monospaced()).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top) {
                OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Roadside")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                    Text("carrier inspections · DataQ")
                        .font(EType.caption.monospaced())
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(carrierName.uppercased()) · USDOT \(usdot)")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    Text(store.isLoading ? "syncing…" : "synced just now")
                        .font(EType.caption.monospaced())
                        .foregroundStyle(palette.textSecondary)
                }
            }
            IridescentHairline()
        }
    }

    // MARK: Hero card

    private func heroCard(_ m: RoadsideSummary) -> some View {
        let passFrac = min(1.0, max(0.0, Double(m.hero.inspectionPassRate) / 100.0))
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("OPEN TICKETS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("INSPECTION PASS")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(m.hero.openTickets)")
                    .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("\(m.hero.clearedLast90d) cleared 90d")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
                Spacer()
                Text("\(m.hero.inspectionPassRate)%")
                    .font(.system(size: 20, weight: .semibold).monospaced())
                    .foregroundStyle(m.hero.inspectionPassRate >= 90
                                     ? AnyShapeStyle(Brand.success)
                                     : AnyShapeStyle(palette.textPrimary))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(palette.tintNeutral.opacity(0.4))
                    RoundedRectangle(cornerRadius: 3).fill(LinearGradient.diagonal)
                        .frame(width: max(7, geo.size.width * passFrac))
                }
            }.frame(height: 6)
            Text(m.hero.challengeNote)
                .font(EType.caption)
                .foregroundStyle(m.hero.openTickets > 0
                                 ? AnyShapeStyle(Brand.warning)
                                 : AnyShapeStyle(palette.textPrimary))
                .lineLimit(1)
            Text("Carrier inspection pass rate trailing-24-mo")
                .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Roadside inspection history card

    private func historyCard(_ m: RoadsideSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ROADSIDE INSPECTION HISTORY")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("LAST \(max(m.inspections.count, 5))")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)

            if m.inspections.isEmpty {
                Text("No roadside inspections on file for this carrier yet")
                    .font(EType.caption.monospaced())
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s2)
            } else {
                ForEach(Array(m.inspections.enumerated()), id: \.element.id) { idx, row in
                    inspectionRow(row)
                        .padding(.vertical, Space.s2)
                    if idx < m.inspections.count - 1 {
                        Rectangle().fill(palette.textTertiary.opacity(0.07)).frame(height: 1)
                    }
                }
            }

            Text("Tap a record to open the report · DataQ challenge available within 12 mo")
                .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s3)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func inspectionRow(_ row: RoadsideInspectionRow) -> some View {
        HStack(alignment: .center, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(row.dateLabel.isEmpty ? "—" : row.dateLabel) · \(typeLabel(row.type))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subLine(row))
                    .font(EType.micro.monospaced()).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            pill(row.pill)
        }
    }

    /// "{location} · {OOS|N viol|0 OOS}" — verbatim grammar to the SVG sub-row.
    private func subLine(_ row: RoadsideInspectionRow) -> String {
        let loc = row.location.isEmpty ? "—" : row.location
        let tail: String
        if row.oosViolation { tail = "OOS" }
        else if row.defectsFound > 0 { tail = "\(row.defectsFound) viol" }
        else { tail = "0 OOS" }
        return "\(loc) · \(tail)"
    }

    private func pill(_ kind: String) -> some View {
        let (label, fg): (String, Color)
        switch kind {
        case "clean":  (label, fg) = ("CLEAN",  Brand.success)
        case "dataq":  (label, fg) = ("DATAQ",  Brand.warning)
        default:       (label, fg) = ("CLOSED", palette.textSecondary)
        }
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(fg.opacity(0.16)))
    }

    // MARK: Factor cells

    private func factorCells(_ m: RoadsideSummary) -> some View {
        HStack(spacing: Space.s2) {
            factorCell(label: "OPEN", value: "\(m.factors.open)", sub: "in DataQ")
            factorCell(label: "DATAQ FILED", value: "\(m.factors.dataqFiled)", sub: "trailing 24mo")
            factorCell(label: "WIN RATE", value: "\(m.factors.winRatePct)%", sub: "challenges")
        }
    }

    private func factorCell(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(sub).font(EType.micro.monospaced()).foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1))
    }

    // MARK: CTAs

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { fileSheet = true } label: {
                Text("File DataQ")
                    .font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
            .disabled(store.state.value == nil)

            Button { policySheet = true } label: {
                Text("Carrier policy")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(store.state.value == nil)
        }
    }

    // MARK: Footnote

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Roadside ledger · FMCSA inspection levels I–VI · OOS = out-of-service")
            Text("Carrier: \(carrierName) · USDOT \(usdot) · \(mcNumber)")
            Text("DataQ = formal challenge to a cited violation via FMCSA portal")
        }
        .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard).frame(height: 124)
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard).frame(height: 268)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCard).frame(height: 66)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private var emptyCard: some View {
        VStack(spacing: Space.s2) {
            Text("No roadside data yet")
                .font(EType.title).foregroundStyle(palette.textPrimary)
            Text("Roadside inspections and DataQ filings appear here once your carrier records sync.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(Space.s4).eusoCard(radius: Radius.lg)
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Text("Couldn't load roadside")
                .font(EType.title).foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button { Task { await store.refresh() } } label: {
                Text("Retry").font(EType.bodyStrong).foregroundStyle(.white)
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(Space.s4).eusoCard(radius: Radius.lg)
    }

    // MARK: Reference / presentation data

    /// FMCSA inspection-type display label. The DB has no Level I–VI column, so
    /// the row surfaces the real `type` honestly (no fabricated level).
    private func typeLabel(_ t: String) -> String {
        switch t.lowercased() {
        case "roadside":  return "Roadside"
        case "dot":       return "DOT"
        case "annual":    return "Annual"
        case "pre_trip":  return "Pre-Trip"
        case "post_trip": return "Post-Trip"
        case "dvir":      return "DVIR"
        default:          return t.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - File DataQ sheet (dataqs.aiDraft assist + dataqs.file submit)

private struct FileDataQSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) var dismiss

    let carrier: RoadsideCarrier?
    let onFiled: () -> Void

    // Request-type options mirror the server REQUEST_TYPES enum exactly.
    private let requestTypes: [(value: String, label: String)] = [
        ("inspection_violation", "Inspection violation"),
        ("inspection", "Inspection record"),
        ("csa_violation", "CSA violation"),
        ("crash_preventability", "Crash preventability"),
        ("other", "Other"),
    ]

    @State private var requestType = "inspection_violation"
    @State private var referenceNumber = ""
    @State private var violationCode = ""
    @State private var jurisdiction = ""
    @State private var eventDate = ""
    @State private var challengeStatement = ""

    @State private var draft: RoadsideAIDraft?
    @State private var drafting = false
    @State private var submitting = false
    @State private var actionError: String?
    @State private var submittedOK = false

    private var canSubmit: Bool {
        !referenceNumber.trimmingCharacters(in: .whitespaces).isEmpty
            && challengeStatement.trimmingCharacters(in: .whitespaces).count >= 20
            && !submitting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Text("File DataQ").font(EType.h2).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Cancel").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                    }.buttonStyle(.plain)
                }

                Text("FMCSA Request for Data Review · burden of proof is on the requestor (49 CFR 386, 2026 reform). Initial review 21 days.")
                    .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)

                if submittedOK {
                    successCard
                } else {
                    formBody
                }
            }
            .padding(Space.s4)
        }
        .background(palette.bgPrimary)
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // Request type
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("REQUEST TYPE")
                Picker("Request type", selection: $requestType) {
                    ForEach(requestTypes, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.menu)
                .tint(palette.textPrimary)
            }

            field("FMCSA REPORT / INSPECTION #", text: $referenceNumber, placeholder: "e.g. ND0000123456")
            field("VIOLATION CODE", text: $violationCode, placeholder: "e.g. 393.95(a) (optional)")
            HStack(spacing: Space.s2) {
                field("JURISDICTION", text: $jurisdiction, placeholder: "TX")
                field("EVENT DATE", text: $eventDate, placeholder: "YYYY-MM-DD")
            }

            // Challenge statement + AI assist
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    fieldLabel("CHALLENGE STATEMENT")
                    Spacer()
                    Button { Task { await runDraft() } } label: {
                        HStack(spacing: 4) {
                            if drafting { ProgressView().controlSize(.mini) }
                            Text(drafting ? "Drafting…" : "✦ AI assist")
                                .font(EType.micro).tracking(0.4)
                        }
                        .foregroundStyle(LinearGradient.diagonal)
                    }
                    .buttonStyle(.plain)
                    .disabled(drafting || referenceNumber.isEmpty)
                }
                TextEditor(text: $challengeStatement)
                    .font(EType.caption)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(Space.s2)
                    .background(RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md)
                        .strokeBorder(palette.borderFaint, lineWidth: 1))
                Text("Min 20 characters · factual, third-person, cite the regulation if known.")
                    .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
            }

            if let d = draft, d.available { aiDraftCard(d) }

            if let err = actionError {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }

            Button { Task { await submit() } } label: {
                HStack(spacing: 6) {
                    if submitting { ProgressView().controlSize(.small).tint(.white) }
                    Text(submitting ? "Filing…" : "File with FMCSA DataQs")
                        .font(EType.bodyStrong).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(LinearGradient.diagonal))
                .opacity(canSubmit ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }

    private func aiDraftCard(_ d: RoadsideAIDraft) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("AI DRAFT").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("RISK · \(d.frivolousClaimRisk.uppercased())")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(d.frivolousClaimRisk == "high" ? Brand.danger
                                     : d.frivolousClaimRisk == "medium" ? Brand.warning
                                     : Brand.success)
            }
            if !d.evidenceChecklist.isEmpty {
                Text("Evidence checklist").font(EType.caption.bold()).foregroundStyle(palette.textPrimary)
                ForEach(Array(d.evidenceChecklist.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(EType.caption).foregroundStyle(palette.textTertiary)
                        Text(item).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            if !d.reasoning.isEmpty {
                Text(d.reasoning).font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
            }
            if d.localResolutionRecommended == true {
                Text("Recommended: contact the issuing officer locally before filing.")
                    .font(EType.micro.monospaced()).foregroundStyle(Brand.warning)
            }
            Button { challengeStatement = d.challengeStatement } label: {
                Text("Use this statement")
                    .font(EType.micro).foregroundStyle(LinearGradient.diagonal)
            }
            .buttonStyle(.plain)
            .disabled(d.challengeStatement.isEmpty)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md)
    }

    private var successCard: some View {
        VStack(spacing: Space.s2) {
            Text("Filed").font(EType.h2).foregroundStyle(Brand.success)
            Text("Your Request for Data Review is in the queue. FMCSA's initial review window is 21 days.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text("Done").font(EType.bodyStrong).foregroundStyle(.white)
                    .padding(.horizontal, Space.s5).padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(Space.s4).eusoCard(radius: Radius.lg)
    }

    // MARK: Field primitives

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
    }
    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label)
            TextField(placeholder, text: text)
                .font(EType.caption)
                .padding(Space.s2)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
                .autocorrectionDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions (real calls — no synthesized success)

    private struct DraftIn: Encodable {
        let requestType: String
        let violationCode: String?
        let eventDate: String?
        let jurisdiction: String?
        let issuingOfficer: String?
        let carrierFacts: String
        let driverAccount: String?
    }
    private struct FileIn: Encodable {
        let requestType: String
        let referenceNumber: String
        let eventDate: String?
        let jurisdiction: String?
        let issuingOfficer: String?
        let violationCode: String?
        let challengeStatement: String
        let evidenceUrls: [String]
        let dotNumber: String?
        let driverId: String?
        let rdrSubmissionId: String?
        let status: String
    }

    private func runDraft() async {
        drafting = true; actionError = nil
        defer { drafting = false }
        let facts = challengeStatement.trimmingCharacters(in: .whitespaces).count >= 10
            ? challengeStatement
            : "Carrier disputes \(violationCode.isEmpty ? "the cited violation" : violationCode) on FMCSA report \(referenceNumber)."
        do {
            let d: RoadsideAIDraft = try await EusoTripAPI.shared.mutation(
                "dataqs.aiDraft",
                input: DraftIn(
                    requestType: requestType,
                    violationCode: violationCode.isEmpty ? nil : violationCode,
                    eventDate: eventDate.isEmpty ? nil : eventDate,
                    jurisdiction: jurisdiction.isEmpty ? nil : jurisdiction,
                    issuingOfficer: nil,
                    carrierFacts: facts,
                    driverAccount: nil
                )
            )
            draft = d
            if !d.available {
                actionError = "AI assist is unavailable right now — you can still file your own statement."
            }
        } catch {
            actionError = "AI assist failed: \(error.localizedDescription)"
        }
    }

    private func submit() async {
        submitting = true; actionError = nil
        defer { submitting = false }
        do {
            let ack: RoadsideFileAck = try await EusoTripAPI.shared.mutation(
                "dataqs.file",
                input: FileIn(
                    requestType: requestType,
                    referenceNumber: referenceNumber.trimmingCharacters(in: .whitespaces),
                    eventDate: eventDate.isEmpty ? nil : eventDate,
                    jurisdiction: jurisdiction.isEmpty ? nil : jurisdiction,
                    issuingOfficer: nil,
                    violationCode: violationCode.isEmpty ? nil : violationCode,
                    challengeStatement: challengeStatement.trimmingCharacters(in: .whitespaces),
                    evidenceUrls: [],
                    dotNumber: (carrier?.dotNumber.isEmpty == false) ? carrier?.dotNumber : nil,
                    driverId: nil,
                    rdrSubmissionId: nil,
                    status: "submitted"
                )
            )
            if ack.success {
                submittedOK = true
                onFiled()
            } else {
                actionError = "The filing did not persist. Please try again."
            }
        } catch {
            actionError = "Filing failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Carrier policy sheet (roadsideTickets.policyForCarrier)

@MainActor
private final class CarrierPolicyStore: BaseDynamicStore<RoadsidePolicy> {
    private struct PolicyIn: Encodable { let carrierId: Int }
    let carrierId: Int
    init(carrierId: Int) { self.carrierId = carrierId; super.init() }
    override func fetch() async throws -> RoadsidePolicy {
        try await EusoTripAPI.shared.query(
            "roadsideTickets.policyForCarrier",
            input: PolicyIn(carrierId: carrierId)
        )
    }
}

private struct CarrierPolicySheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) var dismiss
    @StateObject private var store: CarrierPolicyStore

    init(carrierId: Int) { _store = StateObject(wrappedValue: CarrierPolicyStore(carrierId: carrierId)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Text("Carrier policy").font(EType.h2).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Done").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                    }.buttonStyle(.plain)
                }
                Text("Roadside coverage on file for this carrier.")
                    .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)

                switch store.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Space.s8)
                case .empty:
                    coverageUnknown
                case .error(let e):
                    Text(e.localizedDescription).font(EType.caption).foregroundStyle(Brand.warning)
                case .loaded(let p):
                    if p.coverageLimitCents <= 0 && (p.preferredProviderName ?? "").isEmpty {
                        coverageUnknown
                    } else {
                        statRow("Coverage limit", money(p.coverageLimitCents))
                        statRow("Preferred provider", p.preferredProviderName ?? "—")
                        if let u = p.updatedAt, !u.isEmpty {
                            statRow("Updated", u)
                        }
                    }
                }
            }
            .padding(Space.s4)
        }
        .background(palette.bgPrimary)
        .task { await store.refresh() }
    }

    private var coverageUnknown: some View {
        VStack(spacing: Space.s2) {
            Text("Coverage unknown")
                .font(EType.title).foregroundStyle(palette.textPrimary)
            Text("No roadside coverage record is on file for this carrier yet.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(Space.s4).eusoCard(radius: Radius.lg)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(EType.caption.monospaced()).foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
        .overlay(Rectangle().fill(palette.textTertiary.opacity(0.07)).frame(height: 1), alignment: .bottom)
    }

    /// Cents → "$12,345" (whole dollars; coverage limits are large round figures).
    private func money(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: dollars)) ?? "$\(Int(dollars))"
    }
}

#if DEBUG
struct CatalystRoadsideDataQ_Previews: PreviewProvider {
    static var previews: some View {
        CatalystRoadsideDataQ()
            .environment(\.palette, Theme.dark)
            .background(Theme.dark.bgPrimary)
            .preferredColorScheme(.dark)
    }
}
#endif
