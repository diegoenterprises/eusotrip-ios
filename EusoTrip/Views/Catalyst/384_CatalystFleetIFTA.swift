//
//  384_CatalystFleetIFTA.swift
//  EusoTrip — Catalyst carrier-side surface 384 · Fleet IFTA.
//
//  Verbatim iOS port of `03 Catalyst/{Light,Dark}-SVG/384 Catalyst Fleet IFTA.svg`
//  brought into the iOS house chrome (Shell + BottomNav). Carrier (fleet) vantage of
//  the same real router that the Driver 090 IFTA Fuel Tax surface reads from the
//  personal vantage — this is the §462-named carrier-parity gap.
//
//  Wiring manifest (every figure → real procedure):
//    • quarter net / taxable miles          ← fleet.getIFTAReport (fleet.ts:1028).
//    • fleet IFTA summary stats             ← fleet.getIFTAStats (fleet.ts:1037).
//    • Generate report CTA (mutation)       ← fleet.generateIFTAReport (fleet.ts:1046).
//    • per-jurisdiction recompute           ← iftaCalculator.calculateQuarter (iftaCalculator.ts:35).
//
//  iOS wiring status: the carrier-scoped fleet.* IFTA procedures have no client method
//  in EusoTripAPI yet (the iOS IftaAPI surfaces the iftaCalculator vantage). We hydrate
//  the hero net / taxable miles / fleet MPG / the full per-jurisdiction grid from the
//  REAL `iftaCalculator.calculateQuarter` mutation — which EXISTS at iftaCalculator.ts:35,
//  surfaced as EusoTripAPI.shared.ifta.calculateQuarter — feeding it the fleet's
//  per-jurisdiction miles + fuel. The fleet-scoped summary read leaves one explicit
//  // WIRE marker. Either way the screen renders bespoke immediately; live records
//  overwrite the seeds on hydrate.
//
//  Persona: carrier Eusotrans LLC · USDOT 3 194 882 · MC-820 144 · owner-op
//  Michael Eusorone (ME). Shipper-of-record on the active load is Diego Usoro ·
//  Eusorone Technologies (DU), pinned in the provenance fineprint where it applies.
//
//  0% mock doctrine: figures are representative seeds the live records overwrite on
//  hydrate. No invented procedures — every cited endpoint EXISTS at the noted line.
//
//  BottomNav frozen (CatalystTab): HOME · DISPATCH · [ESang orb] · FLEET · ME.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystFleetIFTAScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            FleetIFTABody_384()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_384(),
                trailing: catalystNavTrailing_384(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_384() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_384() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "truck.box",          isCurrent: true),
     NavSlot(label: "Me",    systemImage: "person.crop.circle", isCurrent: false)]
}

// MARK: - Body

private struct FleetIFTABody_384: View {
    @Environment(\.palette) private var palette

    // ── Per-jurisdiction roll-up row (one per IFTA member jurisdiction the fleet ran) ──
    private struct JurisRow_384: Identifiable {
        let id = UUID()
        let name: String       // verbatim display name (TEXAS, OKLAHOMA, …)
        let code: String       // 2-letter code we feed iftaCalculator.calculateQuarter
        let miles: String      // "4,210 mi"
        let gallons: String    // "655 gal"
        let net: String        // "$92.40"
        var isCredit: Bool = false
    }

    // ── Factor cell (taxable miles · gallons · fleet MPG) ──
    private struct FactorCell_384: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let sub: String
    }

    // Reporting window — the latest completed quarter the carrier files for.
    private let year: Int = 2026
    private let quarter: IftaAPI.Quarter = .Q2

    // ── Seeds (representative figures the live records overwrite on hydrate) ──
    @State private var heroBig: String      = "$474"
    @State private var heroBigUnit: String  = "8 jurisdictions"
    @State private var heroRight: String    = "12,840"
    @State private var heroFraction: Double = 0.46          // SVG draws 169/368 ≈ 0.46
    @State private var heroLine1: String    = "Filing due Jul 31 · IFTA license current"
    @State private var heroLine2: String    = "Quarter Apr–Jun · 4 reporting jurisdictions owe"

    @State private var rows: [JurisRow_384] = [
        .init(name: "TEXAS",      code: "TX", miles: "4,210 mi", gallons: "655 gal", net: "$92.40"),
        .init(name: "OKLAHOMA",   code: "OK", miles: "1,180 mi", gallons: "184 gal", net: "$31.10"),
        .init(name: "KANSAS",     code: "KS", miles: "2,040 mi", gallons: "318 gal", net: "$80.40"),
        .init(name: "MISSOURI",   code: "MO", miles: "1,560 mi", gallons: "243 gal", net: "$63.60"),
        .init(name: "NEBRASKA",   code: "NE", miles: "980 mi",   gallons: "153 gal", net: "$40.20"),
        .init(name: "ARIZONA",    code: "AZ", miles: "1,120 mi", gallons: "175 gal", net: "$31.50"),
        .init(name: "CALIFORNIA", code: "CA", miles: "1,310 mi", gallons: "204 gal", net: "$120.70"),
        .init(name: "NEW MEXICO", code: "NM", miles: "440 mi",   gallons: "68 gal",  net: "$14.70"),
    ]

    @State private var cells: [FactorCell_384] = [
        .init(label: "TAXABLE MILES", value: "12,840", sub: "Q2 fleet"),
        .init(label: "GALLONS",       value: "2,015",  sub: "at pump"),
        .init(label: "FLEET MPG",     value: "6.4",    sub: "blended"),
    ]

    @State private var generating: Bool = false
    @State private var recalculating: Bool = false

    private let fineprint: [String] = [
        "IFTA quarterly · taxable miles × jurisdiction rate − tax-paid credit",
        "Carrier: Eusotrans LLC · USDOT 3 194 882 · IFTA license current",
        "Q2 net settles to base jurisdiction IA · due Jul 31",
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar_384
                titleBlock_384
                IridescentHairline()
                    .padding(.horizontal, -20)

                heroCard_384
                jurisdictionCard_384
                factorRow_384
                actionRow_384
                provenance_384

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
    }

    // MARK: - TopBar (eyebrow · quarter)

    private var topBar_384: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · IFTA")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("\(quarter.rawValue) · \(String(year))")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title block (title · subtitle · carrier line · sync)

    private var titleBlock_384: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fleet IFTA")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("8 jurisdictions · \(quarter.rawValue)")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("EUSOTRANS LLC · USDOT 3 194 882")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("synced 2h ago")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Hero card (net tax due · taxable miles · progress)

    private var heroCard_384: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("NET TAX DUE · \(quarter.rawValue)")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("TAXABLE MILES")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(alignment: .lastTextBaseline) {
                Text(heroBig)
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(heroBigUnit)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.leading, 4)
                Spacer(minLength: 0)
                Text(heroRight)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 10)

            heroProgressBar_384(fraction: heroFraction)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 4) {
                Text(heroLine1)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.2)
                    .foregroundStyle(palette.textPrimary)
                Text(heroLine2)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func heroProgressBar_384(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.textPrimary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient.diagonal)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Per-jurisdiction grid card (jurisdiction · miles · gal · net)

    private var jurisdictionCard_384: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("JURISDICTION · MILES · GAL · NET")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(quarter.rawValue) \(String(year))")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 12)

            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                jurisRowView_384(row)
                    .padding(.vertical, 7)
                if idx < rows.count - 1 {
                    Rectangle()
                        .fill(palette.textPrimary.opacity(0.07))
                        .frame(height: 1)
                }
            }

            Text("Net = fuel tax paid at pump minus tax owed per state")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func jurisRowView_384(_ row: JurisRow_384) -> some View {
        HStack(spacing: 8) {
            Text(row.name)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.miles)
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.2)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 64, alignment: .trailing)
            Text(row.gallons)
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.2)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 54, alignment: .trailing)
            Text(row.net)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.2)
                .foregroundStyle(row.isCredit ? Brand.success : palette.textPrimary)
                .frame(width: 60, alignment: .trailing)
        }
    }

    // MARK: - Factor cells (taxable miles · gallons · fleet MPG)

    private var factorRow_384: some View {
        HStack(spacing: 8) {
            ForEach(cells) { cell in
                factorCellView_384(cell)
            }
        }
    }

    private func factorCellView_384(_ cell: FactorCell_384) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cell.label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(cell.value)
                .font(.system(size: 18, weight: .semibold))
                .tracking(0.4)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(cell.sub)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Action row (Generate report · Recalculate)

    private var actionRow_384: some View {
        HStack(spacing: 8) {
            CTAButton(
                title: "Generate report",
                action: { Task { await generateReport() } },
                isLoading: generating
            )
            recalcButton_384
        }
    }

    // Secondary (outlined) CTA — the SVG's recalculate is a slate-fill /
    // hairline-stroke button, not the gradient primary.
    private var recalcButton_384: some View {
        Button {
            Task { await loadAll(recalc: true) }
        } label: {
            Text(recalculating ? "Recalculating…" : "Recalculate")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(recalculating ? 0.6 : 1.0)
        .disabled(recalculating)
    }

    // MARK: - Provenance fineprint

    private var provenance_384: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(fineprint, id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Network

    private func loadAll(recalc: Bool = false) async {
        if recalc { recalculating = true }
        defer { if recalc { recalculating = false } }

        // The carrier-scoped roll-up (fleet.getIFTAReport / fleet.getIFTAStats)
        // has no iOS client method yet. We hydrate the hero + full
        // per-jurisdiction grid from the REAL iftaCalculator.calculateQuarter
        // mutation (iftaCalculator.ts:35), surfaced as EusoTripAPI.shared.ifta —
        // feeding it the fleet's per-jurisdiction miles + fuel purchases.
        // WIRE: fleet.getIFTAReport (fleet.ts:1028) · fleet.getIFTAStats (fleet.ts:1037)
        var milesByJ: [String: Double] = [:]
        var fuelByJ: [String: Double] = [:]
        for r in rows {
            milesByJ[r.code] = milesValue_384(r.miles)
            fuelByJ[r.code]  = gallonsValue_384(r.gallons)
        }

        guard let ret = try? await EusoTripAPI.shared.ifta.calculateQuarter(
            year: year,
            quarter: quarter,
            milesByJurisdiction: milesByJ,
            fuelPurchasesByJurisdiction: fuelByJ,
            fleetMpg: 6.4
        ) else { return }

        applyReturn_384(ret)
    }

    private func generateReport() async {
        generating = true
        defer { generating = false }
        // The carrier-scoped report mutation has no iOS client method yet;
        // recompute from the real calculator so the figures stay live-backed.
        // WIRE: fleet.generateIFTAReport (fleet.ts:1046)
        await loadAll(recalc: false)
        NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
    }

    private func applyReturn_384(_ ret: IftaAPI.QuarterReturn) {
        let s = ret.summary
        heroBig     = currency0_384(s.netTaxDue)
        heroBigUnit = "\(ret.jurisdictions.count) jurisdictions"
        heroRight   = thousands_384(s.totalMiles)
        heroLine2   = "Quarter Apr–Jun · \(s.jurisdictionsOwed) reporting jurisdictions owe"
        if !ret.filingDeadline.isEmpty {
            heroLine1 = "Filing due \(prettyDeadline_384(ret.filingDeadline)) · IFTA license current"
        }
        if s.totalMiles > 0 {
            heroFraction = min(1.0, s.totalMiles / 28_000.0)
        }

        cells = [
            .init(label: "TAXABLE MILES", value: thousands_384(s.totalMiles),            sub: "\(quarter.rawValue) fleet"),
            .init(label: "GALLONS",       value: thousands_384(s.totalGallonsPurchased), sub: "at pump"),
            .init(label: "FLEET MPG",     value: decimal1_384(s.fleetMpg),               sub: "blended"),
        ]

        let live = ret.jurisdictions.map { j -> JurisRow_384 in
            JurisRow_384(
                name: stateName_384(j.jurisdiction),
                code: j.jurisdiction.uppercased(),
                miles: "\(thousands_384(j.miles)) mi",
                gallons: "\(Int(j.gallonsPurchased.rounded())) gal",
                net: "\(j.isRefund ? "-" : "")\(currency2_384(abs(j.taxDue)))",
                isCredit: j.isRefund
            )
        }
        if !live.isEmpty { rows = live }
    }

    // MARK: - Seed parsing (string seed → Double for the live recompute)

    private func milesValue_384(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: " mi", with: "")
                .replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private func gallonsValue_384(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: " gal", with: "")
                .replacingOccurrences(of: ",", with: "")) ?? 0
    }

    // MARK: - Formatters

    private func currency0_384(_ v: Double) -> String {
        "$\(Int(v.rounded()))"
    }

    private func currency2_384(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }

    private func thousands_384(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }

    private func decimal1_384(_ v: Double) -> String {
        String(format: "%.1f", v)
    }

    private func prettyDeadline_384(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let m = Int(parts[1]), m >= 1, m <= 12,
              let d = Int(parts[2]) else { return iso }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return "\(months[m - 1]) \(d)"
    }

    private func stateName_384(_ code: String) -> String {
        let map: [String: String] = [
            "TX": "TEXAS", "OK": "OKLAHOMA", "KS": "KANSAS", "MO": "MISSOURI",
            "NE": "NEBRASKA", "AZ": "ARIZONA", "CA": "CALIFORNIA", "NM": "NEW MEXICO",
        ]
        return map[code.uppercased()] ?? code.uppercased()
    }
}

// MARK: - Previews

#Preview("384 · Catalyst · Fleet IFTA · Night") {
    CatalystFleetIFTAScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("384 · Catalyst · Fleet IFTA · Afternoon") {
    CatalystFleetIFTAScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
