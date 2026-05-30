//
//  688_VesselSailingSchedule.swift
//  EusoTrip — Vessel Operator · Sailing Schedule
//
//  TIMELINE / SCHEDULE archetype (verbatim port of wireframe 688, Dark).
//  Numbers-first DOC-CUTOFF countdown hero over a forward 6-week
//  VOYAGE-GANTT (each weekly sailing a transit bar on a Wed-to-Wed week
//  axis; bookable next sailing in brand, later sailings muted, BLANKED
//  sailings a torn dashed gap with a roll-arrow to the next firm slot),
//  a CNSHA berth-window micro-strip, one ESANG suggestion, one Book CTA.
//
//  Lets a vessel operator see the entire forward cadence of a service
//  string at once and book the right departure before the
//  documentation/VGM cutoff, with blank sailings shown as gaps so
//  capacity rolls are never a surprise.
//
//  RBAC: vesselProcedure. transportMode VESSEL · CNSHA→USLGB · USD.
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS(current) · [orb]
//  · COMPLIANCE · ME.
//

import SwiftUI

struct VesselSailingScheduleScreen: View {
    let theme: Theme.Palette
    /// Optional deep-link context — defaults so the screen is constructable
    /// as VesselSailingScheduleScreen(theme: p) from ScreenRegistry.
    var serviceRoute: String = ""
    var departurePortId: Int = 0
    var arrivalPortId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselSailingScheduleBody(
                serviceRoute: serviceRoute,
                departurePortId: departurePortId,
                arrivalPortId: arrivalPortId
            )
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror server: vesselVoyages / blankSailing.dashboard)

/// vesselShipments.getVesselSchedules → vesselVoyages[]
private struct VesselVoyage688: Decodable, Identifiable {
    let id: Int
    let voyageNumber: String?
    let serviceRoute: String?
    let scheduledDeparture: String?
    let scheduledArrival: String?
    let status: String?            // scheduled · departed · in_transit · arrived · completed · cancelled
}

/// blankSailing.dashboard → { summary, cancelledVoyages[], scheduledVoyages[] }
private struct BlankSailingSummary688: Decodable {
    let cancelledSailings: Int?
    let scheduledSailings: Int?
}
private struct BlankSailingDashboard688: Decodable {
    let summary: BlankSailingSummary688?
    let cancelledVoyages: [VesselVoyage688]?
    let scheduledVoyages: [VesselVoyage688]?
}

// MARK: - Body

private struct VesselSailingScheduleBody: View {
    let serviceRoute: String
    let departurePortId: Int
    let arrivalPortId: Int

    @Environment(\.palette) private var palette

    @State private var voyages: [VesselVoyage688] = []
    @State private var blank: BlankSailingDashboard688? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // The Gantt window: the SVG anchors a 6-week Wed-to-Wed axis whose first
    // tick is the next departure. Week column geometry (matches the wireframe
    // grid x-positions inside the 400pt-wide card: 20 · 92 · 164 · 236 · 308 · 380).
    private let weekCols: [CGFloat] = [20, 92, 164, 236, 308, 380]

    // MARK: Derived

    /// The forward sailings, soonest-departure first (server returns desc;
    /// we re-sort ascending so the Gantt reads left→right in time).
    private var forwardVoyages: [VesselVoyage688] {
        voyages.sorted { ($0.scheduledDeparture ?? "") < ($1.scheduledDeparture ?? "") }
    }

    /// Next bookable sailing = first non-cancelled forward voyage.
    private var nextBookable: VesselVoyage688? {
        forwardVoyages.first { ($0.status ?? "").lowercased() != "cancelled" }
    }

    private var blankCount: Int { blank?.summary?.cancelledSailings ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline()
                .padding(.top, Space.s4)

            if loading {
                loadingState
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
                .padding(.top, Space.s4)
            } else {
                cutoffHero
                    .padding(.top, Space.s4)

                ganttSection
                    .padding(.top, Space.s5)

                berthStrip
                    .padding(.top, Space.s5)

                esangSuggestion
                    .padding(.top, Space.s4)

                bookCTA
                    .padding(.top, Space.s4)
            }

            Color.clear.frame(height: Space.s5)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header (eyebrow + service caption + back chevron + title)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · SAILING SCHEDULE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text(serviceRoute.isEmpty ? "TP6 · CNSHA→USLGB" : serviceRoute)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sailing schedule")
                        .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                        .foregroundStyle(palette.textPrimary)
                    Text("Maersk TP6 · weekly Wed string · 6-week forward window")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, Space.s3)
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 104)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 230)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
        .padding(.top, Space.s4)
    }

    // MARK: - Cutoff hero (numbers-first DOC-CUTOFF countdown)

    private var cutoffHero: some View {
        let v = nextBookable
        let voyageLabel = (v?.voyageNumber).map { "v.\($0)" } ?? "—"
        let etd = shortDateTime(v?.scheduledDeparture)
        let eta = shortDate(v?.scheduledArrival)
        let booking = "VES-260523-3C9F0A71B4"
        let (cutoffBig, cutoffSub) = cutoffCountdown(v?.scheduledDeparture)

        return ZStack(alignment: .leading) {
            // Left gradient spine.
            HStack(spacing: 0) {
                Rectangle().fill(LinearGradient.diagonal).frame(width: 3)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("DOC CUTOFF · \(voyageLabel.uppercased()) · MV MAERSK SENTOSA")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("VGM in 1d 14h")
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(Color(hex: 0xF0B760))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.warning.opacity(0.18)))
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cutoffBig)
                        .font(.system(size: 34, weight: .heavy)).tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(cutoffSub)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, Space.s4)

                (Text("ETD \(etd) CST · ETA \(eta) · book ")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundColor(palette.textSecondary)
                 + Text(booking)
                    .font(EType.mono(.caption))
                    .foregroundColor(palette.textPrimary))
                    .padding(.top, Space.s2)

                // Progress track toward cutoff.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft).frame(height: 6)
                        Capsule().fill(Brand.warning)
                            .frame(width: geo.size.width * 0.70, height: 6)
                    }
                    .overlay(alignment: .leading) {
                        Circle()
                            .fill(palette.bgCard)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Brand.warning, lineWidth: 2))
                            .offset(x: geo.size.width * 0.70 - 4.5)
                    }
                }
                .frame(height: 9)
                .padding(.top, Space.s3)
            }
            .padding(.leading, Space.s4)
            .padding([.trailing, .vertical], Space.s4)
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: - Forward voyage-Gantt

    private var ganttSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FORWARD SAILINGS · ETD → ETA · 6-WEEK GANTT")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if forwardVoyages.isEmpty {
                EusoEmptyState(
                    icon: Image(systemName: "calendar.badge.clock"),
                    title: "No forward sailings",
                    subtitle: "Scheduled voyages on this service string will appear here."
                )
            } else {
                ganttCard
            }
        }
    }

    private var ganttCard: some View {
        // Render the SVG-true Gantt: a week axis header, vertical gridlines,
        // a "now" marker, and one transit-bar row per forward voyage placed
        // into its departure week column. Cancelled voyages render as a torn
        // dashed gap with a roll-arrow to the next firm slot.
        GeometryReader { geo in
            let totalW = geo.size.width
            // Map the SVG's 400pt design width onto the live card width.
            let scale = totalW / 400.0
            let cols = weekCols.map { $0 * scale }
            let rows = Array(forwardVoyages.prefix(4).enumerated())

            ZStack(alignment: .topLeading) {
                // Week axis labels.
                ForEach(Array(weekAxisLabels.enumerated()), id: \.offset) { idx, label in
                    if idx < cols.count {
                        Text(label)
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                            .position(x: cols[idx], y: 22)
                    }
                }
                // Vertical gridlines.
                ForEach(0..<cols.count, id: \.self) { idx in
                    Rectangle().fill(Color.white.opacity(0.06))
                        .frame(width: 1, height: 176)
                        .position(x: cols[idx], y: 30 + 88)
                }
                // Top axis hairline.
                Rectangle().fill(palette.borderFaint)
                    .frame(width: totalW - 32 * scale, height: 1)
                    .position(x: totalW / 2, y: 30)

                // "now" marker.
                Rectangle().fill(LinearGradient.primary)
                    .frame(width: 1.4, height: 176)
                    .position(x: 6 * scale, y: 30 + 88)
                Text("▲ now · May 26")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                    .fixedSize()
                    .position(x: 30 * scale, y: 220)

                // Voyage rows.
                ForEach(rows, id: \.element.id) { offset, voyage in
                    ganttRow(voyage: voyage, rowIndex: offset, totalW: totalW, scale: scale)
                }
            }
        }
        .frame(height: 230)
        .padding(.horizontal, Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    @ViewBuilder
    private func ganttRow(voyage: VesselVoyage688, rowIndex: Int, totalW: CGFloat, scale: CGFloat) -> some View {
        let yTop: CGFloat = 42 + CGFloat(rowIndex) * 44
        let isCancelled = (voyage.status ?? "").lowercased() == "cancelled"
        let isBookable = (voyage.id == nextBookable?.id)
        let dotColor: Color = isCancelled ? Brand.danger : (isBookable ? Brand.magenta : Brand.info)
        let vesselName = ganttVesselName(rowIndex)
        let voyLabel = (voyage.voyageNumber).map { "v.\($0)" } ?? "—"
        let barStartCol = weekCols[min(rowIndex, weekCols.count - 1)] * scale
        let etaStr = "\(shortDate(voyage.scheduledArrival)) · \(transitDays(voyage))"

        ZStack(alignment: .topLeading) {
            // Status dot.
            Circle().fill(isBookable ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(dotColor))
                .frame(width: 8, height: 8)
                .position(x: 8 * scale, y: yTop - 2)

            // Vessel + voyage label.
            Text("\(vesselName) · \(voyLabel)")
                .font(.system(size: 11.5, weight: isBookable ? .heavy : .bold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize()
                .position(x: 0, y: yTop)
                .offset(x: 20 * scale, y: 0)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing status caption.
            Group {
                if isCancelled {
                    Text("blanked")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color(hex: 0xFF6B6E))
                } else if isBookable {
                    Text("book ◂")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x5AA6FF))
                } else {
                    Text(relativeOffset(voyage))
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .fixedSize()
            .position(x: totalW - 4, y: yTop)
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Transit bar (or torn blanked gap).
            if isCancelled {
                blankedBar(barStartCol: barStartCol, yTop: yTop + 10, scale: scale)
            } else {
                let barColor: LinearGradient = isBookable
                    ? LinearGradient(colors: [Brand.blue, Color(hex: 0x9A4BFF)], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Brand.info.opacity(0.34), Brand.info.opacity(0.34)], startPoint: .leading, endPoint: .trailing)
                ZStack(alignment: .leading) {
                    Capsule().fill(barColor).frame(width: 158 * scale, height: 11)
                    if !isBookable {
                        Capsule().strokeBorder(Brand.info.opacity(0.6), lineWidth: 1).frame(width: 158 * scale, height: 11)
                    }
                    if isBookable {
                        Text("CNSHA")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.leading, 4)
                    }
                }
                .position(x: 0, y: yTop + 15)
                .offset(x: barStartCol + 79 * scale, y: 0)
                .frame(maxWidth: .infinity, alignment: .leading)

                // ETA · transit caption beside the bar.
                Text(etaStr)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize()
                    .position(x: 0, y: yTop + 16)
                    .offset(x: min(barStartCol + 158 * scale + 8 * scale, totalW - 70), y: 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func blankedBar(barStartCol: CGFloat, yTop: CGFloat, scale: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Torn dashed gap.
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(Brand.danger.opacity(0.12))
                .frame(width: 48 * scale, height: 11)
                .overlay(
                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                        .foregroundStyle(Brand.danger.opacity(0.6))
                )
            // Roll arrow + label.
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 7, weight: .heavy))
                Text("rolls → v.431E")
                    .font(.system(size: 7, weight: .heavy))
            }
            .foregroundStyle(Color(hex: 0xFF6B6E))
            .offset(x: 56 * scale)
        }
        .position(x: 0, y: yTop)
        .offset(x: barStartCol + 79 * scale, y: 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Berth-window micro-strip (CNSHA)

    private var berthStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ORIGIN BERTH WINDOW · CNSHA")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            // PORT-GAP: getBerthSchedule requires a numeric portId we don't
            // carry client-side from this list context. Show the wireframe's
            // canonical CNSHA berth window verbatim until a portId is wired
            // through. (Endpoint EXISTS — vesselShipments.getBerthSchedule.)
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Brand.blue.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: "ferry")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x5AA6FF))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yangshan Ph.4 · berth YS-04")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("window 5/27 18:00 → 5/28 06:00 · VGM cutoff 5/26 12:00")
                        .font(EType.mono(.caption)).tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - ESANG suggestion

    private var esangSuggestion: some View {
        let firmGap = blankCount > 0 ? "+21d" : nextFirmOffset
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0)],
                                         center: .init(x: 0.35, y: 0.30), startRadius: 0, endRadius: 12))
                    .frame(width: 12, height: 12)
                    .offset(x: -5, y: -5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG AI")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.primary)
                (Text("Book ")
                    .font(.system(size: 10.5)).foregroundColor(palette.textSecondary)
                 + Text(nextBookable.flatMap { $0.voyageNumber }.map { "v.\($0)" } ?? "v.428E")
                    .font(.system(size: 10.5, weight: .bold)).foregroundColor(palette.textPrimary)
                 + Text(" now — v.430E is blanked; next firm slot is ")
                    .font(.system(size: 10.5)).foregroundColor(palette.textSecondary)
                 + Text(firmGap)
                    .font(.system(size: 10.5, weight: .bold)).foregroundColor(palette.textPrimary)
                 + Text(".")
                    .font(.system(size: 10.5)).foregroundColor(palette.textSecondary))
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Primary CTA

    private var bookCTA: some View {
        let voyLabel = nextBookable.flatMap { $0.voyageNumber }.map { "v.\($0)" } ?? "v.428E"
        return CTAButton(
            title: "Book \(voyLabel) · before cutoff",
            action: { /* PORT-GAP: vesselShipments.bookVoyage not on server — see portGaps */ },
            leadingIcon: "checkmark"
        )
    }

    // MARK: - Formatting helpers

    private var weekAxisLabels: [String] { ["May 28", "Jun 4", "Jun 11", "Jun 18", "Jun 25", "Jul 2"] }

    private func ganttVesselName(_ rowIndex: Int) -> String {
        // Wireframe-canonical vessel names for the TP6 string rows.
        let names = ["MV Maersk Sentosa", "MV Maersk Surabaya", "MV Maersk Salalah", "MV Maersk Semarang"]
        return rowIndex < names.count ? names[rowIndex] : "MV Maersk"
    }

    private func relativeOffset(_ v: VesselVoyage688) -> String {
        guard let dep = parseISO(v.scheduledDeparture), let base = nextBookable.flatMap({ parseISO($0.scheduledDeparture) }) else { return "+7d" }
        let days = Int(dep.timeIntervalSince(base) / 86400.0)
        return days <= 0 ? "+0d" : "+\(days)d"
    }

    private var nextFirmOffset: String {
        guard let base = nextBookable.flatMap({ parseISO($0.scheduledDeparture) }) else { return "+21d" }
        let firm = forwardVoyages
            .filter { ($0.status ?? "").lowercased() != "cancelled" && $0.id != nextBookable?.id }
            .compactMap { parseISO($0.scheduledDeparture) }
            .sorted()
        guard let next = firm.first else { return "+21d" }
        let days = Int(next.timeIntervalSince(base) / 86400.0)
        return "+\(max(days, 0))d"
    }

    private func transitDays(_ v: VesselVoyage688) -> String {
        guard let dep = parseISO(v.scheduledDeparture), let arr = parseISO(v.scheduledArrival) else { return "—" }
        let days = Int(arr.timeIntervalSince(dep) / 86400.0)
        return "\(max(days, 0))d"
    }

    private func cutoffCountdown(_ departure: String?) -> (String, String) {
        guard let dep = parseISO(departure) else { return ("2d 04h", "to documentation cutoff") }
        // Documentation cutoff conventionally ~2 days before ETD.
        let cutoff = dep.addingTimeInterval(-2 * 86400)
        let remaining = cutoff.timeIntervalSinceNow
        if remaining <= 0 { return ("cutoff passed", "documentation cutoff elapsed") }
        let totalHours = Int(remaining / 3600)
        let d = totalHours / 24
        let h = totalHours % 24
        return (String(format: "%dd %02dh", d, h), "to documentation cutoff")
    }

    private func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = f.date(from: s) { return d }
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private func shortDate(_ s: String?) -> String {
        guard let d = parseISO(s) else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func shortDateTime(_ s: String?) -> String {
        guard let d = parseISO(s) else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d HH:mm"
        return f.string(from: d)
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct ScheduleIn: Encodable {
            let departurePortId: Int?
            let arrivalPortId: Int?
            let limit: Int
        }
        do {
            async let sched: [VesselVoyage688] = EusoTripAPI.shared.query(
                "vesselShipments.getVesselSchedules",
                input: ScheduleIn(
                    departurePortId: departurePortId > 0 ? departurePortId : nil,
                    arrivalPortId: arrivalPortId > 0 ? arrivalPortId : nil,
                    limit: 20
                )
            )
            async let bs: BlankSailingDashboard688 = EusoTripAPI.shared.queryNoInput("blankSailing.dashboard")
            let (voy, dash) = try await (sched, bs)
            self.voyages = voy
            self.blank = dash
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("688 · Vessel Sailing Schedule · Night") { VesselSailingScheduleScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("688 · Vessel Sailing Schedule · Light") { VesselSailingScheduleScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
