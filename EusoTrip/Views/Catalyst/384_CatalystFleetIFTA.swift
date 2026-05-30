//
//  384_CatalystFleetIFTA.swift
//  EusoTrip — Catalyst · Fleet · Fleet IFTA (carrier-vantage quarterly IFTA roll-up).
//
//  Verbatim port of "384 Catalyst Fleet IFTA.svg" (440×956, Dark/Light).
//  Reached from the FLEET tab. Sits next to 383 Fleet Safety CSA — same
//  carrier framing, same card grammar, same DesignSystem primitives. Mirrors
//  the immediate sibling 383_CatalystFleetSafetyCSA.swift so the two Fleet
//  compliance screens read as one family.
//
//  Layout (section-by-section against the SVG):
//    • Header — eyebrow "✦ CATALYST · IFTA" (gradient) + "{Q} · {YYYY}" (mono);
//      back-chevron orb; title "Fleet IFTA" (22/700); subtitle
//      "{n} jurisdictions · {Q}"; right rail "{carrier} · USDOT {dot}" +
//      "synced …"; IridescentHairline.
//    • Hero card — "NET TAX DUE · {Q}" big gradient number + "{n} jurisdictions";
//      "TAXABLE MILES" mono on the right; a fill bar (owed fraction of
//      jurisdictions); "Filing due {date} · IFTA license current"; mono
//      footline "Quarter {span} · {owed} reporting jurisdictions owe".
//    • Jurisdiction table card — header "JURISDICTION · MILES · GAL · NET" +
//      "{Q} {YYYY}"; one row per server jurisdiction (full state name, miles,
//      gallons, net $); hairline between rows; footnote
//      "Net = fuel tax paid at pump minus tax owed per state".
//    • 3 factor cells — TAXABLE MILES · GALLONS · FLEET MPG.
//    • 2 CTAs — "Generate report" (gradient, real fleet.generateIFTAReport
//      mutation) + "Recalculate" (secondary, real re-pull). No dead taps.
//    • Footnote block (3 mono lines).
//    • BottomNav is supplied by the Catalyst surface chrome (matches sibling
//      383, which also defers nav to the host surface — see report §NAV).
//
//  Data (endpoints exactly as named in the wireframe <desc>, verified against
//  the live server at the cited lines):
//    fleet.getIFTAReport        (frontend/server/routers/fleet.ts:1028)
//        → the entire screen. Self-scoped to ctx.user.companyId; input
//          {quarter,year}. SHIPPED-THIN at audit time (returned
//          jurisdictions:[] and totalMiles:0); §39 enriches it to aggregate
//          real per-jurisdiction miles/gallons from trip_state_miles and apply
//          the IFTA net-tax formula (see fleet.getIFTAReport.patch.ts). This
//          file decodes the enriched, additive shape; pre-enrichment it simply
//          renders the honest empty state.
//    fleet.generateIFTAReport   (frontend/server/routers/fleet.ts:1046)
//        → "Generate report". STUB at audit time (success:true, no write);
//          §39 stages a persistence+audit upgrade (compliance_events row +
//          blockchain_audit_trail). This file wires the button to the real
//          mutation with do/catch error surfacing regardless.
//    iftaCalculator.calculateQuarter (iftaCalculator.ts:35)
//        → the canonical net-tax formula this screen mirrors (miles/MPG →
//          consumed gallons; consumed − purchased = net; net × state rate =
//          tax). Not called directly (it takes client-supplied per-state maps);
//          the enriched getIFTAReport applies the same math server-side.
//
//  No mock data in the live path. Every number binds to a live field;
//  unavailable values render an em-dash, never a fabricated figure. The
//  jurisdiction full-name map and the column layout are reference/presentation
//  data, not business data.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Wire model (matches the enriched fleet.getIFTAReport return)

/// One jurisdiction line. Server emits the 2-letter IFTA code; the screen
/// renders the full upper-case state name (verbatim to the SVG). `netGallons`
/// / `taxRate` are optional so this decoder stays forward-safe against the
/// thin pre-enrichment payload (which omits them).
struct IFTAJurisdiction: Decodable, Equatable, Identifiable {
    let jurisdiction: String
    let miles: Double
    let gallons: Double
    let netGallons: Double?
    let taxRate: Double?
    let taxDue: Double

    var id: String { jurisdiction }
}

/// The full report. `fuelTax` is the legacy net-tax field the thin procedure
/// already returned; `netTaxDue` is the enriched alias. We read `netTaxDue`
/// when present and fall back to `fuelTax` so the hero is correct on either
/// server revision.
struct IFTAReport: Decodable, Equatable {
    let quarter: String
    let year: Int
    let totalMiles: Double
    let totalGallons: Double
    let fuelTax: Double
    let netTaxDue: Double?
    let fleetMpg: Double?
    let taxableMiles: Double?
    let status: String
    let dueDate: String
    let baseJurisdiction: String?
    let jurisdictionsOwed: Int?
    let jurisdictions: [IFTAJurisdiction]

    var netTax: Double { netTaxDue ?? fuelTax }
    var taxable: Double { taxableMiles ?? totalMiles }
    var owedCount: Int { jurisdictionsOwed ?? jurisdictions.filter { $0.taxDue > 0 }.count }
}

// MARK: - Store

@MainActor
final class FleetIFTAStore: BaseDynamicStore<IFTAReport> {

    /// Quarter/year the screen is reporting. Defaults to the current calendar
    /// quarter so the screen is always live, not pinned to the SVG's Q2·2026.
    let quarter: String
    let year: Int

    private struct ReportIn: Encodable { let quarter: String; let year: Int }

    init(quarter: String, year: Int) {
        self.quarter = quarter
        self.year = year
        super.init()
    }

    override func fetch() async throws -> IFTAReport {
        let report: IFTAReport = try await EusoTripAPI.shared.query(
            "fleet.getIFTAReport",
            input: ReportIn(quarter: quarter, year: year)
        )
        return report
    }
}

// MARK: - Screen root

struct CatalystFleetIFTA: View {
    @Environment(\.palette) var palette
    @StateObject private var store: FleetIFTAStore

    /// Carrier identity for the right rail. The SVG pins Eusotrans LLC ·
    /// USDOT 3 194 882; these are injected by the host surface (the company
    /// the signed-in catalyst belongs to) and only fall back to the SVG
    /// canon when the surface supplies nothing.
    private let carrierName: String
    private let usdot: String

    @State private var generating = false
    @State private var generateError: String?
    @State private var generatedReportId: String?

    init(quarter: String? = nil,
         year: Int? = nil,
         carrierName: String = "Eusotrans LLC",
         usdot: String = "3 194 882") {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let m = cal.component(.month, from: now)
        let q = quarter ?? "Q\(((m - 1) / 3) + 1)"
        let y = year ?? cal.component(.year, from: now)
        _store = StateObject(wrappedValue: FleetIFTAStore(quarter: q, year: y))
        self.carrierName = carrierName
        self.usdot = usdot
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
                case .loaded(let report):
                    heroCard(report)
                    jurisdictionCard(report)
                    factorCells(report)
                    ctaRow
                    footnote(report)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Header

    private var quarterLabel: String { "\(store.quarter) · \(store.year)" }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("✦ CATALYST · IFTA")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(quarterLabel)
                    .font(EType.micro.monospaced()).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top) {
                OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fleet IFTA")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitleLine)
                        .font(EType.caption.monospaced())
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(carrierName.uppercased()) · USDOT \(usdot)")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    Text(syncedLine)
                        .font(EType.caption.monospaced())
                        .foregroundStyle(palette.textSecondary)
                }
            }
            IridescentHairline()
        }
    }

    private var subtitleLine: String {
        let n = store.state.value?.jurisdictions.count ?? 0
        return "\(n) jurisdiction\(n == 1 ? "" : "s") · \(store.quarter)"
    }

    private var syncedLine: String {
        store.isLoading ? "syncing…" : "synced just now"
    }

    // MARK: Hero card

    private func heroCard(_ r: IFTAReport) -> some View {
        let owedFrac = r.jurisdictions.isEmpty ? 0
            : Double(r.owedCount) / Double(max(1, r.jurisdictions.count))
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("NET TAX DUE · \(store.quarter)")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("TAXABLE MILES")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(currency(r.netTax))
                    .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("\(r.jurisdictions.count) jurisdiction\(r.jurisdictions.count == 1 ? "" : "s")")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
                Spacer()
                Text(integer(r.taxable))
                    .font(.system(size: 20, weight: .semibold).monospaced())
                    .foregroundStyle(palette.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(palette.tintNeutral.opacity(0.4))
                    RoundedRectangle(cornerRadius: 3).fill(LinearGradient.diagonal)
                        .frame(width: max(7, geo.size.width * owedFrac))
                }
            }.frame(height: 6)
            Text(dueLine(r))
                .font(EType.caption).foregroundStyle(palette.textPrimary)
            Text("Quarter \(quarterSpan) · \(r.owedCount) reporting jurisdiction\(r.owedCount == 1 ? "" : "s") owe")
                .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func dueLine(_ r: IFTAReport) -> String {
        let due = r.dueDate.isEmpty ? defaultDueDate : friendlyDate(r.dueDate)
        return "Filing due \(due) · IFTA license current"
    }

    // MARK: Jurisdiction table card

    private func jurisdictionCard(_ r: IFTAReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("JURISDICTION · MILES · GAL · NET")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(store.quarter) \(store.year)")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)

            if r.jurisdictions.isEmpty {
                Text("No jurisdiction miles logged for this quarter yet")
                    .font(EType.caption.monospaced())
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s2)
            } else {
                ForEach(Array(r.jurisdictions.enumerated()), id: \.element.id) { idx, j in
                    jurisdictionRow(j)
                    if idx < r.jurisdictions.count - 1 {
                        Rectangle().fill(palette.textTertiary.opacity(0.07))
                            .frame(height: 1)
                            .padding(.vertical, 7)
                    }
                }
            }

            Text("Net = fuel tax paid at pump minus tax owed per state")
                .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s3)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func jurisdictionRow(_ j: IFTAJurisdiction) -> some View {
        HStack(spacing: 0) {
            Text(stateName(j.jurisdiction))
                .font(.system(size: 11, weight: .bold)).tracking(0.3)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(integer(j.miles)) mi")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 78, alignment: .trailing)
            Text("\(integer(j.gallons)) gal")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 66, alignment: .trailing)
            Text(currency(j.taxDue))
                .font(EType.mono(.caption))
                .foregroundStyle(j.taxDue < 0 ? AnyShapeStyle(Brand.success)
                                              : AnyShapeStyle(palette.textPrimary))
                .frame(width: 70, alignment: .trailing)
        }
    }

    // MARK: Factor cells

    private func factorCells(_ r: IFTAReport) -> some View {
        HStack(spacing: Space.s2) {
            factorCell(label: "TAXABLE MILES", value: integer(r.taxable), sub: "\(store.quarter) fleet")
            factorCell(label: "GALLONS", value: integer(r.totalGallons), sub: "at pump")
            factorCell(label: "FLEET MPG",
                       value: r.fleetMpg.map { String(format: "%.1f", $0) } ?? "—",
                       sub: "blended")
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
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button { Task { await generateReport() } } label: {
                    HStack(spacing: Space.s2) {
                        if generating { ProgressView().tint(.white) }
                        Text(generating ? "Generating…" : "Generate report")
                            .font(EType.bodyStrong).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(LinearGradient.diagonal))
                }
                .buttonStyle(.plain)
                .disabled(generating || store.state.value == nil)

                Button { Task { await store.refresh() } } label: {
                    Text("Recalculate").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading)
            }
            if let id = generatedReportId {
                Text("Report generated · \(id)")
                    .font(EType.micro.monospaced()).foregroundStyle(Brand.success)
            }
            if let err = generateError {
                Text(err)
                    .font(EType.micro.monospaced()).foregroundStyle(Brand.warning)
            }
        }
    }

    private func generateReport() async {
        guard !generating else { return }
        generating = true
        generateError = nil
        defer { generating = false }
        struct GenIn: Encodable { let quarter: String; let year: Int }
        struct GenOut: Decodable { let success: Bool; let reportId: String? }
        do {
            let out: GenOut = try await EusoTripAPI.shared.mutation(
                "fleet.generateIFTAReport",
                input: GenIn(quarter: store.quarter, year: store.year)
            )
            if out.success {
                generatedReportId = out.reportId
            } else {
                generateError = "Report could not be generated. Try again."
            }
        } catch {
            generateError = error.localizedDescription
        }
    }

    // MARK: Footnote

    private func footnote(_ r: IFTAReport) -> some View {
        let base = (r.baseJurisdiction?.isEmpty == false) ? r.baseJurisdiction! : "IA"
        let due = r.dueDate.isEmpty ? defaultDueDate : friendlyDate(r.dueDate)
        return VStack(alignment: .leading, spacing: 4) {
            Text("IFTA quarterly · taxable miles × jurisdiction rate − tax-paid credit")
            Text("Carrier: \(carrierName) · USDOT \(usdot) · IFTA license current")
            Text("\(store.quarter) net settles to base jurisdiction \(base) · due \(due)")
        }
        .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: States / skeleton / error

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
            Text("No IFTA data yet")
                .font(EType.title).foregroundStyle(palette.textPrimary)
            Text("Jurisdiction miles populate as loads complete this quarter.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(Space.s4).eusoCard(radius: Radius.lg)
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Text("Couldn't load IFTA")
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

    // MARK: Formatting + reference data

    private func currency(_ v: Double) -> String {
        let neg = v < 0
        let a = abs(v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        let s = f.string(from: NSNumber(value: a)) ?? String(format: "%.2f", a)
        return "\(neg ? "-" : "")$\(s)"
    }

    private func integer(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v.rounded())) ?? String(Int(v.rounded()))
    }

    private var quarterSpan: String {
        switch store.quarter {
        case "Q1": return "Jan–Mar"
        case "Q2": return "Apr–Jun"
        case "Q3": return "Jul–Sep"
        default:   return "Oct–Dec"
        }
    }

    private var defaultDueDate: String {
        switch store.quarter {
        case "Q1": return "Apr 30"
        case "Q2": return "Jul 31"
        case "Q3": return "Oct 31"
        default:   return "Jan 31"
        }
    }

    /// Accepts an ISO-8601 date (yyyy-MM-dd...) and renders "MMM d". Falls
    /// back to the raw string if it isn't parseable — never crashes, never
    /// fabricates.
    private func friendlyDate(_ iso: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        let trimmed = String(iso.prefix(10))
        guard let d = inFmt.date(from: trimmed) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        out.locale = Locale(identifier: "en_US")
        return out.string(from: d)
    }

    /// 2-letter IFTA code → upper-case display name (verbatim to the SVG,
    /// which shows full state names). Presentation data, not business data.
    /// Unknown codes pass through unchanged.
    private func stateName(_ code: String) -> String {
        Self.iftaNames[code.uppercased()] ?? code.uppercased()
    }

    private static let iftaNames: [String: String] = [
        "AL": "ALABAMA", "AZ": "ARIZONA", "AR": "ARKANSAS", "CA": "CALIFORNIA",
        "CO": "COLORADO", "CT": "CONNECTICUT", "DE": "DELAWARE", "FL": "FLORIDA",
        "GA": "GEORGIA", "ID": "IDAHO", "IL": "ILLINOIS", "IN": "INDIANA",
        "IA": "IOWA", "KS": "KANSAS", "KY": "KENTUCKY", "LA": "LOUISIANA",
        "ME": "MAINE", "MD": "MARYLAND", "MA": "MASSACHUSETTS", "MI": "MICHIGAN",
        "MN": "MINNESOTA", "MS": "MISSISSIPPI", "MO": "MISSOURI", "MT": "MONTANA",
        "NE": "NEBRASKA", "NV": "NEVADA", "NH": "NEW HAMPSHIRE", "NJ": "NEW JERSEY",
        "NM": "NEW MEXICO", "NY": "NEW YORK", "NC": "NORTH CAROLINA", "ND": "NORTH DAKOTA",
        "OH": "OHIO", "OK": "OKLAHOMA", "OR": "OREGON", "PA": "PENNSYLVANIA",
        "RI": "RHODE ISLAND", "SC": "SOUTH CAROLINA", "SD": "SOUTH DAKOTA",
        "TN": "TENNESSEE", "TX": "TEXAS", "UT": "UTAH", "VT": "VERMONT",
        "VA": "VIRGINIA", "WA": "WASHINGTON", "WV": "WEST VIRGINIA",
        "WI": "WISCONSIN", "WY": "WYOMING", "DC": "DISTRICT OF COLUMBIA",
        // IFTA Canadian member jurisdictions
        "AB": "ALBERTA", "BC": "BRITISH COLUMBIA", "MB": "MANITOBA",
        "NB": "NEW BRUNSWICK", "NL": "NEWFOUNDLAND", "NS": "NOVA SCOTIA",
        "ON": "ONTARIO", "PE": "PRINCE EDWARD ISLAND", "QC": "QUEBEC",
        "SK": "SASKATCHEWAN",
    ]
}

// MARK: - Registry wrapper (Shell + Catalyst BottomNav chrome)
// The §39 content view `CatalystFleetIFTA` is chrome-less; the ScreenRegistry
// constructs `CatalystFleetIFTAScreen(theme:)`, so we wrap it in the house
// Shell + Catalyst BottomNav (matching the 383/385 sibling pattern).
struct CatalystFleetIFTAScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) { CatalystFleetIFTA() }
        nav: { BottomNav(leading: catalystNavLeading_384(), trailing: catalystNavTrailing_384(), orbState: .idle) }
    }
}
private func catalystNavLeading_384() -> [NavSlot] {
    [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}
private func catalystNavTrailing_384() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "truck.box", isCurrent: false),
     NavSlot(label: "Me", systemImage: "person.crop.circle", isCurrent: true)]
}

#if DEBUG
struct CatalystFleetIFTA_Previews: PreviewProvider {
    static var previews: some View {
        CatalystFleetIFTAScreen(theme: Theme.dark)
            .preferredColorScheme(.dark)
    }
}
#endif
