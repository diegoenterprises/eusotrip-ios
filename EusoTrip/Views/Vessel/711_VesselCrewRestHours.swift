//
//  711_VesselCrewRestHours.swift
//  EusoTrip — Vessel Operator · Crew Rest Hours
//  (MLC 2006 / STCW work-rest hours roster).
//
//  Verbatim port of wireframe "711 Vessel Crew Rest Hours · Dark".
//  Bespoke 24-HOUR REST/WORK BAR ROSTER archetype: a fleet compliance
//  strip hero plus a per-crew timeline where every row carries a full
//  24h rest(green)/work(neutral)/on-watch(blue) bar over a shared 00–24
//  hour grid, the 24h rest total, and a compliant/breach/on-watch pill.
//
//  Endpoints (REAL · server/routers/vesselShipments.ts):
//    · vesselShipments.getVesselCrew       :814  (vesselProcedure → crew roster)
//    · vesselShipments.getVesselCompliance :854  (→ aggregate status/failedCount)
//
//  RBAC vesselProcedure · transportMode=vessel · MLC 2006 (10h/24h · 77h/7d)
//  + STCW watchkeeping.
//
//  PORT-GAP (NOT invented — surfaced to the-oath per SVG <desc>):
//  the MLC 2006 work/rest-hours typing on the crew row
//  (restBlocks24h[] / restHours24h / restHours7d / violations / watch
//  station / status) is NOT returned by getVesselCrew — that query
//  returns the bare users roster {id,name,email,phone,role,isActive}.
//  We decode the proposed MLC shape as OPTIONAL fields so the row
//  lights up verbatim the moment the server adds them; until then the
//  timeline renders the real "no rest-hours log" empty state rather
//  than fabricated rest blocks. Logging rest is a separate mutation
//  CTA (not on this read surface).
//

import SwiftUI

struct VesselCrewRestHoursScreen: View {
    let theme: Theme.Palette
    var id: String = ""

    var body: some View {
        Shell(theme: theme) { VesselCrewRestHoursBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// getVesselCrew envelope. The server (:814) returns the bare users
/// roster plus certifications. The MLC rest-hours fields below
/// (restBlocks24h / restHours24h / restHours7d / station / status /
/// watchSince) are the proposed work/rest shape — decoded as OPTIONAL
/// so the row reconstructs verbatim once the server emits them and
/// falls back to real empty/error today. See PORT-GAP above.
private struct VesselCrewEnvelope711: Decodable {
    let crew: [VesselCrewRow711]
    let expiringCount: Int?
}

private struct VesselCrewRow711: Decodable, Identifiable {
    let id: String
    let name: String?
    let role: String?
    let isActive: Bool?

    // PORT-GAP: MLC 2006 work/rest-hours fields — not yet on getVesselCrew.
    let station: String?            // e.g. "bridge watch", "cargo watch"
    let rank: String?               // e.g. "Master", "2nd officer", "AB seaman"
    let restHours24h: Double?       // rest total in trailing 24h
    let restHours7d: Double?        // rest total in trailing 7d (STCW 77h/7d)
    let restBlocks24h: [RestBlock711]?
    let status: String?             // "compliant" | "breach" | "onwatch"
    let watchSince: String?         // "20:00" for on-watch rows

    enum CodingKeys: String, CodingKey {
        case id, name, role, isActive
        case station, rank, restHours24h, restHours7d, restBlocks24h, status, watchSince
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `users.id` is an Int on the server — decode defensively.
        if let s = try? c.decode(String.self, forKey: .id) {
            self.id = s
        } else if let n = try? c.decode(Int.self, forKey: .id) {
            self.id = String(n)
        } else {
            self.id = UUID().uuidString
        }
        self.name          = try? c.decode(String.self, forKey: .name)
        self.role          = try? c.decode(String.self, forKey: .role)
        self.isActive      = try? c.decode(Bool.self, forKey: .isActive)
        self.station       = try? c.decode(String.self, forKey: .station)
        self.rank          = try? c.decode(String.self, forKey: .rank)
        self.restHours24h  = try? c.decode(Double.self, forKey: .restHours24h)
        self.restHours7d   = try? c.decode(Double.self, forKey: .restHours7d)
        self.restBlocks24h = try? c.decode([RestBlock711].self, forKey: .restBlocks24h)
        self.status        = try? c.decode(String.self, forKey: .status)
        self.watchSince    = try? c.decode(String.self, forKey: .watchSince)
    }
}

/// One block on the 24h timeline. `startHr` 0–24, `hrs` duration,
/// `kind` rest|work|watch. PORT-GAP shape (not yet server-emitted).
private struct RestBlock711: Decodable {
    let startHr: Double
    let hrs: Double
    let kind: String   // "rest" | "work" | "watch"
}

private struct VesselCompliance711: Decodable {
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?
}

// MARK: - Body

private struct VesselCrewRestHoursBody: View {
    @Environment(\.palette) private var palette

    @State private var crew: [VesselCrewRow711] = []
    @State private var compliance: VesselCompliance711? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // MLC 2006 minimums (verbatim from wireframe hero).
    private let mlcMin24h = "10h / 24h"
    private let mlcMin7d  = "77h / 7d"

    /// Crew rows that carry the proposed MLC rest-hours timing — these
    /// are the only ones the per-crew bar roster can render verbatim.
    /// Today this is empty (PORT-GAP), so the timeline shows the real
    /// "no rest-hours log" state instead of fabricated bars.
    private var rosterRows: [VesselCrewRow711] {
        crew.filter { $0.restBlocks24h != nil || $0.restHours24h != nil }
    }

    /// Crew aboard = real roster count (active users with a vessel role).
    private var aboard: Int { crew.count }

    /// Crew within MLC rest min = those NOT in breach. Derived from the
    /// real per-crew status field when present; otherwise falls back to
    /// the getVesselCompliance aggregate failedCount (:854) so the hero
    /// reflects real backend compliance even before per-crew rest-hours
    /// logging lands.
    private var withinMin: Int {
        let perCrewBreaches = rosterRows.filter { ($0.status ?? "").lowercased() == "breach" }.count
        let breaches = perCrewBreaches > 0 ? perCrewBreaches : (compliance?.failedCount ?? 0)
        return max(aboard - breaches, 0)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleRow
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    heroStrip
                    rosterSection
                    if let breach = firstBreach {
                        breachBanner(breach)
                    }
                    ctaRow
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Eyebrow

    private var eyebrow: some View {
        HStack {
            Text("✦ VESSEL OPERATOR · CREW REST")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("MLC 2006 · STCW")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(alignment: .center) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Crew rest")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .rotationEffect(.degrees(90))
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
    }

    // MARK: - Hero strip (fleet compliance)

    private var heroStrip: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("CREW WITHIN MLC REST MIN")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(loading ? "—" : "\(withinMin)/\(aboard)")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(LinearGradient.diagonal)
                                .monospacedDigit()
                            Text("aboard")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("MINIMUM")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(mlcMin24h)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Text(mlcMin7d)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }
                }
                // 19-cell compliance strip: one cell per seafarer aboard.
                // Green = within rest min, faded = on-watch, red = breach.
                crewComplianceStrip
            }
        }
    }

    /// The 19-segment fleet bar from the wireframe. Each segment maps to
    /// one real aboard crew member; color is driven by real status when
    /// the row carries it, else "within min".
    private var crewComplianceStrip: some View {
        GeometryReader { geo in
            let count = max(aboard, 1)
            let gap: CGFloat = 2
            let cellW = (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(stripColor(at: i))
                        .frame(width: cellW, height: 10)
                }
            }
        }
        .frame(height: 10)
        .opacity(loading ? 0.4 : 1)
    }

    private func stripColor(at index: Int) -> Color {
        guard index < crew.count else { return Brand.success.opacity(0.45) }
        let s = (crew[index].status ?? "").lowercased()
        switch s {
        case "breach":  return Brand.danger
        case "onwatch", "on_watch", "watch": return Brand.success.opacity(0.45)
        case "compliant": return Brand.success
        default:        return Brand.success
        }
    }

    // MARK: - Roster section (per-crew 24h rest/work bars)

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("REST / WORK · LAST 24H")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getVesselCrew :814")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                hourGridHeader
                if loading {
                    ForEach(0..<3, id: \.self) { _ in skeletonRow }
                } else if let err = loadError {
                    Text(err)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .padding(.vertical, Space.s4)
                } else if rosterRows.isEmpty {
                    // PORT-GAP: no MLC rest-hours log on the crew roster yet.
                    // Real empty state — never fabricate rest bars.
                    EusoEmptyState(
                        systemImage: "clock.badge.exclamationmark",
                        title: aboard == 0 ? "No crew aboard" : "No rest-hours log yet",
                        subtitle: aboard == 0
                            ? "Vessel crew roster will appear here."
                            : "\(aboard) crew aboard. MLC 2006 work/rest-hours have not been logged for this watch — log rest to populate the 24h roster."
                    )
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(rosterRows.enumerated()), id: \.element.id) { idx, row in
                        crewRow(row)
                        if idx < rosterRows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.vertical, Space.s1)
                        }
                    }
                }

                footerLine
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// 00 · 06 · 12 · 18 · 24 axis labels + rest/work/watch legend.
    private var hourGridHeader: some View {
        HStack(spacing: 0) {
            ForEach(["00", "06", "12", "18", "24"], id: \.self) { h in
                Text(h)
                    .font(.system(size: 8))
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity,
                           alignment: h == "00" ? .leading : (h == "24" ? .trailing : .center))
            }
        }
        .overlay(alignment: .trailing) { legend }
        .padding(.bottom, Space.s2)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            legendChip(Brand.success, "rest")
            legendChip(Color.white.opacity(0.12), "work")
            legendChip(Brand.info, "watch")
        }
    }

    private func legendChip(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label).font(.system(size: 8)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Crew row

    private func crewRow(_ row: VesselCrewRow711) -> some View {
        let status = (row.status ?? "").lowercased()
        let accent: Color = {
            switch status {
            case "breach":  return Brand.danger
            case "onwatch", "on_watch", "watch": return Brand.info
            default:        return Brand.success
            }
        }()
        let pill: (String, Color) = {
            switch status {
            case "breach":  return ("BREACH", Brand.danger)
            case "onwatch", "on_watch", "watch": return ("ON WATCH", Brand.info)
            default:        return ("COMPLIANT", Brand.success)
            }
        }()
        let title = [row.rank ?? roleLabel(row.role), row.station].compactMap { $0 }.joined(separator: " · ")
        let restTotal = row.restHours24h.map { String(format: "%.1fh", $0) } ?? "—"

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                // Avatar glyph
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "person")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? "Crew" : title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(subline(row, status: status))
                        .font(EType.mono(.caption))
                        .tracking(0.4)
                        .foregroundStyle(status == "breach" ? Brand.danger : palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(pill.0)
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(pill.1)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(pill.1.opacity(0.22)))
                    Text(restTotal)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(status == "breach" ? Brand.danger : palette.textPrimary)
                        .monospacedDigit()
                }
            }
            // 24h rest/work/watch bar over the shared 00–24 grid.
            restBar(row, isBreach: status == "breach")
                .padding(.leading, 52)
        }
        .padding(.vertical, Space.s2)
    }

    private func subline(_ row: VesselCrewRow711, status: String) -> String {
        if status == "breach", let r24 = row.restHours24h {
            let short = max(0, 10.0 - r24)
            let d7 = row.restHours7d.map { String(format: "7d %.1fh", $0) } ?? ""
            return String(format: "%.1fh below 10h min · %@", short, d7)
        }
        if status == "onwatch" || status == "watch" || status == "on_watch" {
            let since = row.watchSince.map { "on watch since \($0)" } ?? "on watch"
            let d7 = row.restHours7d.map { String(format: " · 7d %.1fh", $0) } ?? ""
            return since + d7
        }
        let d7 = row.restHours7d.map { String(format: "7d %.1fh", $0) } ?? ""
        let station = row.station.map { "STCW \($0)" } ?? "STCW watch"
        return [d7, station].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 24h timeline bar. Track is the full 24h; each block paints over
    /// [startHr, startHr+hrs] in its kind color. A breach row gets a red
    /// outline around the whole track.
    private func restBar(_ row: VesselCrewRow711, isBreach: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 10)
                ForEach(Array((row.restBlocks24h ?? []).enumerated()), id: \.offset) { _, b in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(blockColor(b.kind, breach: isBreach))
                        .frame(width: max(w * CGFloat(b.hrs / 24.0), 2), height: 10)
                        .offset(x: w * CGFloat(b.startHr / 24.0))
                }
            }
            .overlay(
                Group {
                    if isBreach {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Brand.danger.opacity(0.55), lineWidth: 1.2)
                            .frame(height: 16)
                    }
                }
            )
        }
        .frame(height: 16)
    }

    private func blockColor(_ kind: String, breach: Bool) -> Color {
        switch kind.lowercased() {
        case "rest":  return breach ? Brand.hazmat : Brand.success
        case "watch": return Brand.info
        case "work":  return breach ? Brand.hazmat : Color.white.opacity(0.12)
        default:      return Color.white.opacity(0.12)
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.bgCardSoft).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(palette.bgCardSoft).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(palette.bgCardSoft).frame(width: 100, height: 10)
            }
            Spacer()
        }
        .padding(.vertical, Space.s2)
    }

    private var footerLine: some View {
        Text(loading
             ? "Loading crew roster…"
             : "\(rosterRows.count) logged · \(aboard) aboard · getVesselCompliance :854")
            .font(.system(size: 10))
            .foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s2)
    }

    // MARK: - Breach banner

    private var firstBreach: VesselCrewRow711? {
        rosterRows.first { ($0.status ?? "").lowercased() == "breach" }
    }

    private func breachBanner(_ row: VesselCrewRow711) -> some View {
        let rank = row.rank ?? roleLabel(row.role)
        let short = row.restHours24h.map { max(0, 10.0 - $0) } ?? 0
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%@ %.1fh short of 10h/24h", rank, short))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("log corrective rest before next \(row.station ?? "watch") · STCW record")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            // PORT-GAP: rest-hours logging is a vesselShipments crew-log
            // mutation not yet shipped — CTA present per wireframe; wiring
            // lands when the mutation exists.
            CTAButton(title: "Log rest hours")
                .frame(maxWidth: .infinity)
            Button {
                // Crew list → roster surface (handled by nav host).
            } label: {
                Text("Crew list")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Helpers

    private func roleLabel(_ role: String?) -> String {
        guard let role else { return "Crew" }
        switch role.uppercased() {
        case "SHIP_CAPTAIN":   return "Master"
        case "VESSEL_OPERATOR": return "Operator"
        case "PORT_MASTER":    return "Port master"
        case "VESSEL_SHIPPER": return "Shipper"
        case "VESSEL_BROKER":  return "Broker"
        case "CUSTOMS_BROKER": return "Customs broker"
        default:
            return role.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct CrewIn: Encodable { let search: String? }
        do {
            async let crewEnv: VesselCrewEnvelope711 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselCrew", input: CrewIn(search: nil))
            async let comp: VesselCompliance711 = EusoTripAPI.shared.queryNoInput(
                "vesselShipments.getVesselCompliance")
            let (env, c) = try await (crewEnv, comp)
            self.crew = env.crew
            self.compliance = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("711 · Vessel Crew Rest Hours · Night") {
    VesselCrewRestHoursScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("711 · Vessel Crew Rest Hours · Light") {
    VesselCrewRestHoursScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
