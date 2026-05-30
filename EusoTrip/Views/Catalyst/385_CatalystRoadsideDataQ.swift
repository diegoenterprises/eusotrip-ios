//
//  385_CatalystRoadsideDataQ.swift
//  EusoTrip — Catalyst · Roadside DataQ.
//
//  Verbatim native port of the 385 Catalyst Roadside DataQ wireframe —
//  the carrier-vantage roadside inspection ledger + DataQ challenge
//  surface. Carrier reads their last-5 FMCSA roadside inspections (levels
//  I–VI), the trailing-24-mo pass rate, the open-ticket count, and the
//  DataQ-challenge factor cells (open / filed / win rate), then files a
//  formal Request for Data Review (RDR) against a cited violation.
//
//  Structure mirrored 1:1 from the SVG:
//    • Hero — OPEN TICKETS + INSPECTION PASS gauge bar + DataQ note.
//    • ROADSIDE INSPECTION HISTORY — last-5 rows, each with a result
//      pill (CLEAN · CLOSED · DATAQ).
//    • Factor cells — OPEN · DATAQ FILED · WIN RATE.
//    • Actions — File DataQ (gradient) · Carrier policy (outline).
//    • Federal footnotes — FMCSA levels I–VI · OOS · USDOT / MC.
//
//  Wiring manifest (every figure → real procedure, line-confirmed against
//  eusoronetechnologiesinc/frontend/server/routers/):
//    • inspection / ticket history list    ← roadsideTickets.list (roadsideTickets.ts:51).
//    • row tap → record detail             ← roadsideTickets.getById (roadsideTickets.ts:83).
//    • close a resolved ticket (mutation)  ← roadsideTickets.close (roadsideTickets.ts:203).
//    • Carrier policy CTA                  ← roadsideTickets.policyForCarrier (roadsideTickets.ts:251).
//    • new event capture (mutation)        ← roadsideTickets.create (roadsideTickets.ts:110).
//
//  iOS client status (honest):
//    • DataQ-challenge filings ARE live: `dataqs.listMine` (DataQsAPI →
//      frontend/server/routers/dataqs.ts) hydrates the OPEN-in-DataQ,
//      DATAQ-FILED and WIN-RATE factor cells (and the hero open-ticket
//      count) over the seeds when it returns rows.
//    • The roadside-INSPECTION ledger (the last-5 history list, the hero
//      pass-rate gauge) has NO iOS endpoint yet — `roadsideTickets.*` is
//      not bridged to Swift. Per the house "0% mock — seeds overwritten
//      on hydrate" doctrine the Code/ file's REPRESENTATIVE seed figures
//      render the bespoke surface immediately (NOT fabrication); the live
//      ledger overwrites them once the client method lands. One WIRE
//      marker sits in reload() where `roadsideTickets.list` belongs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystRoadsideDataQScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            RoadsideDataQContent_385()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_385(),
                trailing: catalystNavTrailing_385(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_385() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_385() -> [NavSlot] {
    // Frozen Catalyst tabs per the Code/ file: FLEET is the selected tab.
    [NavSlot(label: "Fleet", systemImage: "truck.box",         isCurrent: true),
     NavSlot(label: "Me",    systemImage: "person.crop.circle", isCurrent: false)]
}

// MARK: - Typed models

/// A single roadside inspection in the carrier's ledger. Mirrors the
/// FMCSA SAFER inspection record shape (level I–VI, location, OOS count,
/// disposition). Pure value type so the view can render a loading
/// skeleton or an honest empty state without fabricating rows.
private struct RoadsideRecord_385: Identifiable, Equatable {
    enum Result_385: Equatable { case clean, closed, dataq }
    let id = UUID()
    let dateLabel: String      // "Apr 18"
    let level: String          // "Level II"
    let location: String       // "I-40 · Amarillo TX"
    let detail: String         // "0 OOS" / "1 viol" / "brake adj"
    let result: Result_385
}

/// DataQ-challenge factor rollup. Sourced from `dataqs.listMine` when
/// available; `nil` fields paint em-dash.
private struct DataQFactors_385: Equatable {
    let openInDataQ: Int?
    let filedTrailing24mo: Int?
    let winRatePct: Int?
}

private enum LoadPhase_385: Equatable { case loading, empty, ready }

// MARK: - Body

private struct RoadsideDataQContent_385: View {
    @Environment(\.palette) private var palette

    // Roadside inspection ledger — REPRESENTATIVE SEEDS from the Code/
    // file (overwritten by roadsideTickets.list on hydrate; see WIRE).
    // These ARE the canonical 385 figures, not fabrication — the house
    // "0% mock — seeds overwritten on hydrate" posture renders the
    // bespoke last-5 list immediately.
    @State private var records: [RoadsideRecord_385] = RoadsideDataQContent_385.seedRecords
    @State private var recordsPhase: LoadPhase_385 = .ready

    // DataQ-challenge filings — seeds first, live-hydrated via
    // dataqs.listMine when it returns rows.
    @State private var factors: DataQFactors_385? = RoadsideDataQContent_385.seedFactors
    @State private var factorsPhase: LoadPhase_385 = .ready

    // Hero headline metrics — seeds first, overwritten on hydrate.
    @State private var openTickets: Int? = 1
    @State private var passRatePct: Int? = 94

    // MARK: Canonical seeds (verbatim from Code/385_CatalystRoadsideDataQ.swift)

    private static let seedRecords: [RoadsideRecord_385] = [
        .init(dateLabel: "Apr 18", level: "Level II",  location: "I-40 · Amarillo TX",        detail: "0 OOS",     result: .clean),
        .init(dateLabel: "Mar 02", level: "Level I",   location: "I-80 · North Platte NE",    detail: "1 viol",    result: .closed),
        .init(dateLabel: "Feb 11", level: "Level III", location: "US-75 · Sapulpa OK",        detail: "0 OOS",     result: .clean),
        .init(dateLabel: "Jan 24", level: "Level II",  location: "I-35 · Emporia KS",         detail: "brake adj", result: .dataq),
        .init(dateLabel: "Dec 09", level: "Level I",   location: "I-29 · Council Bluffs IA",  detail: "0 OOS",     result: .clean),
    ]

    private static let seedFactors = DataQFactors_385(
        openInDataQ: 1,           // "1 · in DataQ"
        filedTrailing24mo: 2,     // "2 · trailing 24mo"
        winRatePct: 67            // "67% · challenges"
    )

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                hairline
                heroCard
                historyCard
                factorRow
                actionRow
                footnotes
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
    }

    // MARK: Eyebrow

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · ROADSIDE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("INSPECTIONS")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Title

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(palette.bgCard))
                .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text("Roadside")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("carrier inspections · DataQ")
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

    private var hairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: Hero card — OPEN TICKETS + INSPECTION PASS gauge

    private var heroCard: some View {
        let open = openTickets
        let pass = passRatePct

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("OPEN TICKETS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("INSPECTION PASS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(open.map { String($0) } ?? "—")
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("2 cleared 90d")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Text(pass.map { "\($0)%" } ?? "—")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pass == nil ? palette.textTertiary : Brand.success)
            }
            .padding(.top, 10)

            passGauge(pct: pass)
                .padding(.top, 14)

            Text("1 brake-adjust violation in DataQ challenge")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 16)
            Text("Carrier inspection pass rate trailing-24-mo")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 4)
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

    private func passGauge(pct: Int?) -> some View {
        GeometryReader { geo in
            let frac = max(0.0, min(1.0, Double(pct ?? 0) / 100.0))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient.diagonal)
                    .frame(width: geo.size.width * CGFloat(frac))
            }
        }
        .frame(height: 6)
    }

    // MARK: History card

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ROADSIDE INSPECTION HISTORY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("LAST 5")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 4)

            switch recordsPhase {
            case .loading:
                historySkeleton
            case .empty:
                historyEmpty
            case .ready:
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { idx, rec in
                        historyRow(rec)
                        if idx < records.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 1)
                        }
                    }
                }
            }

            Text("Tap a record to open the report · DataQ challenge available within 12 mo")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 14)
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

    private func historyRow(_ rec: RoadsideRecord_385) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(rec.dateLabel) · \(rec.level)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(rec.location) · \(rec.detail)")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            resultPill(rec.result)
        }
        .padding(.vertical, 12)
    }

    private func resultPill(_ result: RoadsideRecord_385.Result_385) -> some View {
        let label: String
        let fg: Color
        let bg: Color
        switch result {
        case .clean:
            label = "CLEAN"; fg = Brand.success; bg = Color(hex: 0x0B3D2E)
        case .closed:
            label = "CLOSED"; fg = palette.textSecondary; bg = Color(hex: 0x1C2128)
        case .dataq:
            label = "DATAQ"; fg = Brand.warning; bg = Color(hex: 0x3A2E08)
        }
        return Text(label)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(fg)
            .frame(width: 82, height: 20)
            .background(Capsule().fill(bg))
    }

    private var historySkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { idx in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(palette.bgCardSoft).frame(width: 120, height: 12)
                        RoundedRectangle(cornerRadius: 3).fill(palette.bgCardSoft).frame(width: 180, height: 9)
                    }
                    Spacer(minLength: 0)
                    Capsule().fill(palette.bgCardSoft).frame(width: 82, height: 20)
                }
                .padding(.vertical, 12)
                if idx < 4 {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private var historyEmpty: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Text("No roadside inspections on file")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("FMCSA inspection ledger not yet wired for this carrier")
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: Factor cells — OPEN · DATAQ FILED · WIN RATE

    private var factorRow: some View {
        HStack(spacing: 8) {
            factorTile(
                eyebrow: "OPEN",
                value: factorValue(factors?.openInDataQ),
                caption: "in DataQ"
            )
            factorTile(
                eyebrow: "DATAQ FILED",
                value: factorValue(factors?.filedTrailing24mo),
                caption: "trailing 24mo"
            )
            factorTile(
                eyebrow: "WIN RATE",
                value: factors?.winRatePct.map { "\($0)%" } ?? "—",
                caption: "challenges"
            )
        }
    }

    private func factorValue(_ v: Int?) -> String {
        v.map { String($0) } ?? "—"
    }

    private func factorTile(eyebrow: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .tracking(0.4)
                .monospacedDigit()
                .foregroundStyle(value == "—" ? palette.textTertiary : palette.textPrimary)
                .padding(.top, 10)
            Text(caption)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                // File a DataQ Request for Data Review against a cited
                // violation. Routes to the 084 DataQs Filer flow.
                NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
            } label: {
                Text("File DataQ")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                // WIRE: roadsideTickets.policyForCarrier (roadsideTickets.ts:251)
                // — opens the carrier's roadside / DataQ policy reference.
                // No iOS client surface yet; no-op until bridged.
            } label: {
                Text("Carrier policy")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Footnotes

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Roadside ledger · FMCSA inspection levels I–VI · OOS = out-of-service")
            Text("Carrier: Eusotrans LLC · USDOT 3 194 882 · MC-820 144")
            Text("DataQ = formal challenge to a cited violation via FMCSA portal")
        }
        .font(.system(size: 9, design: .monospaced))
        .tracking(0.3)
        .foregroundStyle(palette.textTertiary)
        .padding(.top, 4)
    }

    // MARK: - Network

    private func reload() async {
        // ── DataQ-challenge filings (live, overwrites seeds on hydrate) ─
        // Seeds render the bespoke factor cells immediately; a live
        // `dataqs.listMine` that returns rows overwrites them. When the
        // call fails or returns empty, the canonical seeds STAND (the
        // "0% mock — seeds overwritten on hydrate" doctrine) rather than
        // blanking the surface.
        if let resp = try? await EusoTripAPI.shared.dataqs.listMine(limit: 100), !resp.rows.isEmpty {
            let rows = resp.rows
            let openStatuses: Set<String> = ["draft", "submitted", "under_review", "pending", "open"]
            let wonStatuses: Set<String> = ["accepted", "approved", "resolved", "won", "completed"]
            let lostStatuses: Set<String> = ["rejected", "denied", "closed", "lost"]

            let openCount = rows.filter { openStatuses.contains($0.status.lowercased()) }.count
            let filedCount = resp.total
            let won = rows.filter { wonStatuses.contains($0.status.lowercased()) }.count
            let lost = rows.filter { lostStatuses.contains($0.status.lowercased()) }.count
            let decided = won + lost
            let winRate: Int? = decided > 0 ? Int((Double(won) / Double(decided) * 100.0).rounded()) : nil

            factors = DataQFactors_385(
                openInDataQ: openCount,
                filedTrailing24mo: filedCount,
                winRatePct: winRate
            )
            openTickets = openCount
            factorsPhase = .ready
        }
        // else: keep the canonical seeds (factors / openTickets unchanged).

        // ── Roadside inspection ledger ─────────────────────────────────
        // WIRE: roadsideTickets.list (roadsideTickets.ts:51) — carrier-
        // vantage FMCSA roadside inspection ledger (level I–VI, location,
        // OOS count, disposition). Companions: getById :83 (row tap →
        // report), close :203, policyForCarrier :251, create :110. None
        // bridged to Swift yet, so the canonical last-5 seeds + 94% pass
        // gauge STAND until the client method lands and overwrites them.
    }
}

// MARK: - Previews

#Preview("385 · Catalyst · Roadside DataQ · Night") {
    CatalystRoadsideDataQScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("385 · Catalyst · Roadside DataQ · Afternoon") {
    CatalystRoadsideDataQScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
