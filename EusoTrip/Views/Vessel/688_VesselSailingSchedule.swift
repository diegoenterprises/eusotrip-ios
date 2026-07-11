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

// MARK: - Port-call UN/LOCODE source (REAL catalog join, not geocoding)
//
// `vesselShipments.getVesselSchedules` returns raw `vessel_voyages` rows that
// carry only the integer `departurePortId`/`arrivalPortId` FKs — NO UN/LOCODE
// strings — so it can't anchor a port map by itself. The sibling proc
// `multiModal.getVesselSchedules` (protectedProcedure) DOES join the `ports`
// table and emits `port.code = ports.unlocode` per row (multiModal.ts:648-653):
// a real UN/LOCODE pulled straight from the DB. We decode those, resolve each
// against the static `PortDirectory` (NGA Pub 150 World Port Index) via
// `find(unlocode:)`, and skip any code not in the catalog. That is a pure
// catalog lookup — never a place-name geocode and never a hardcoded literal.

/// multiModal.getVesselSchedules → { vessels: [...], total, shippingLines }
private struct MMSchedulePort688: Decodable, Hashable {
    let code: String?          // ports.unlocode (e.g. "USLGB", "CNSHA→ catalog-only)
    let name: String?
}
private struct MMScheduleRow688: Decodable, Identifiable, Hashable {
    let id: String
    let voyage: String?
    let service: String?
    let port: MMSchedulePort688?     // destination port (joined ports row)
}
private struct MMScheduleResponse688: Decodable {
    let vessels: [MMScheduleRow688]?
}

/// A schedule row whose UN/LOCODE resolved to a real catalog port. Carries the
/// looked-up coordinate (`PortDirectory.Port`) so the map can pin/leg it.
private struct ResolvedPortCall688: Identifiable, Hashable {
    let id: String             // the schedule row id (stable, tappable)
    let unlocode: String
    let name: String
    let lat: Double
    let lng: Double
}

// MARK: - Documentation cutoffs (L03-3)
//
// vesselShipments.getCutoffs → the ERD/VGM/SI/cargo(CY)/DG/reefer cutoff set for
// a real booking. `derived` is true when the carrier supplied none and the set
// was computed from ETD (surfaced as a "Derived" badge — never presented as a
// carrier-confirmed cutoff). Decoded leniently — an absent cutoff renders "—".
private struct VesselCutoffs688: Decodable {
    let shipmentId: Int?
    let bookingNumber: String?
    let etd: String?
    let erdAt: String?
    let vgmCutoffAt: String?
    let siCutoffAt: String?
    let cargoCutoffAt: String?
    let dgCutoffAt: String?
    let reeferCutoffAt: String?
    let derived: Bool?
}

/// getVesselShipments row (minimal) — the source of a real booking id/ETD to
/// bind the cutoff set to; the schedule itself is voyage-scoped, not booking-scoped.
private struct VesselShipmentLite688: Decodable, Identifiable {
    let id: Int
    let bookingNumber: String?
    let etd: String?
    let status: String?
}
private struct VesselShipmentsEnvelope688: Decodable {
    let shipments: [VesselShipmentLite688]
}

// MARK: - Body

private struct VesselSailingScheduleBody: View {
    let serviceRoute: String
    let departurePortId: Int
    let arrivalPortId: Int

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    @State private var voyages: [VesselVoyage688] = []
    @State private var blank: BlankSailingDashboard688? = nil
    /// Schedule rows from `multiModal.getVesselSchedules` carrying real port
    /// UN/LOCODEs (ports.unlocode). Source for the ocean map's port calls.
    @State private var scheduleRows: [MMScheduleRow688] = []
    /// Real cutoff set for the operator's soonest upcoming booking (kills the
    /// hero's fabricated ETD−2d countdown + hardcoded booking ref). Nil when the
    /// caller has no accessible upcoming booking.
    @State private var cutoffs: VesselCutoffs688? = nil
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

    /// REAL port calls for the ocean map: every schedule row's destination
    /// UN/LOCODE (ports.unlocode, surfaced by multiModal.getVesselSchedules)
    /// resolved against the static `PortDirectory` catalog via
    /// `find(unlocode:)`. Rows whose code isn't in the ~50-port catalog are
    /// SKIPPED (no fabricated coords). Consecutive duplicate ports collapse so
    /// a string that calls the same port twice doesn't draw a zero-length leg;
    /// order is preserved so voyage legs read along the service string.
    private var resolvedPortCalls: [ResolvedPortCall688] {
        var out: [ResolvedPortCall688] = []
        for row in scheduleRows {
            guard let code = row.port?.code, !code.isEmpty,
                  let p = PortDirectory.find(unlocode: code) else { continue }   // catalog miss → skip
            if out.last?.unlocode == p.unlocode { continue }                     // collapse consecutive repeat
            out.append(ResolvedPortCall688(
                id: row.id, unlocode: p.unlocode, name: p.name, lat: p.lat, lng: p.lng))
        }
        return out
    }

    /// How many schedule rows carried a UN/LOCODE we couldn't resolve in the
    /// catalog — surfaced honestly in the map caption rather than hidden.
    private var unresolvedPortCount: Int {
        scheduleRows.reduce(into: 0) { acc, row in
            if let code = row.port?.code, !code.isEmpty,
               PortDirectory.find(unlocode: code) == nil { acc += 1 }
        }
    }

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

                cutoffsSection
                    .padding(.top, Space.s5)

                ganttSection
                    .padding(.top, Space.s5)

                sailingMapSection
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
        // Real values from getCutoffs — bound to the operator's soonest upcoming
        // booking. When there is none, the hero renders honest em-dashes (no
        // fabricated booking ref, no ETD−2d guess).
        let booking = cutoffs?.bookingNumber ?? "—"
        let etd = shortDateTime(cutoffs?.etd)
        let derived = cutoffs?.derived == true
        let soonest = soonestUpcomingCutoff()
        let cutoffBig = soonest?.countdown ?? "—"
        let cutoffSub = soonest.map { "to \($0.name) cutoff" } ?? "no upcoming cutoff"
        let fraction = cutoffProgressFraction()

        return ZStack(alignment: .leading) {
            // Left gradient spine.
            HStack(spacing: 0) {
                Rectangle().fill(LinearGradient.diagonal).frame(width: 3)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("DOC CUTOFFS · \(booking)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    if cutoffs != nil {
                        Text(derived ? "Derived" : "Carrier-set")
                            .font(.system(size: 9.5, weight: .heavy))
                            .foregroundStyle(derived ? Color(hex: 0xF0B760) : Color(hex: 0x5AA6FF))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill((derived ? Brand.warning : Brand.info).opacity(0.18)))
                    }
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

                (Text("ETD \(etd) · book ")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundColor(palette.textSecondary)
                 + Text(booking)
                    .font(EType.mono(.caption))
                    .foregroundColor(palette.textPrimary))
                    .padding(.top, Space.s2)

                // Progress track toward the soonest cutoff (real fraction over a
                // 7-day window; 0 when there is no upcoming cutoff).
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft).frame(height: 6)
                        Capsule().fill(Brand.warning)
                            .frame(width: geo.size.width * fraction, height: 6)
                    }
                    .overlay(alignment: .leading) {
                        Circle()
                            .fill(palette.bgCard)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Brand.warning, lineWidth: 2))
                            .offset(x: geo.size.width * fraction - 4.5)
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
        let voyLabel = (voyage.voyageNumber).map { "v.\($0)" } ?? "-"
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

    // MARK: - Sailing / port map (ocean register · real catalog coords)
    //
    // Renders the service string as port pins + voyage legs on the bespoke
    // OCEAN basemap (BespokeMapCanvas style: .ocean — the Vessel 003 great-
    // circle register: AIS-orb cartography, hollow port pins, latitude grid,
    // coast hints). Every coordinate is a `PortDirectory` catalog lookup on a
    // real ports.unlocode from the schedule; ports not in the catalog are
    // skipped. No geocoding, no hardcoded lat/lng.

    private var sailingMapSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SAILING MAP · PORT CALLS · VOYAGE LEGS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            let calls = resolvedPortCalls
            if calls.count < 1 {
                // Honest empty/awaiting state: the schedule carried no port
                // UN/LOCODE that resolves to a catalog coordinate. Never frame
                // an ocean on null island; show why instead.
                EusoEmptyState(
                    icon: Image(systemName: "point.topleft.down.to.point.bottomright.curvepath"),
                    title: "No mappable port calls",
                    subtitle: scheduleRows.isEmpty
                        ? "Port-call coordinates resolve from each sailing's UN/LOCODE; none are on this string yet."
                        : "None of this string's \(scheduleRows.count) sailing port UN/LOCODEs are in the port catalog."
                )
            } else {
                sailingMapCard(calls: calls)
            }
        }
    }

    private func sailingMapCard(calls: [ResolvedPortCall688]) -> some View {
        // Port pins: hollow ocean port markers (kind .stop) at each real call;
        // the first call is the live origin (kind .pickup) so the ocean
        // register draws its gradient origin ring. Voyage legs: a single route
        // polyline through the consecutive real port coords — the canvas paints
        // it as the great-circle leg chain under Mercator.
        let coords: [HereLatLng] = calls.map { HereLatLng($0.lat, $0.lng) }
        let pins: [HereMarker] = calls.enumerated().map { idx, c in
            HereMarker(
                at: HereLatLng(c.lat, c.lng),
                kind: idx == 0 ? .pickup : (idx == calls.count - 1 ? .delivery : .stop),
                label: c.unlocode,
                id: c.id)              // schedule-row id → tappable handler pin
        }
        var layers: [HereMapLayer] = []
        if coords.count >= 2 {
            layers.append(.route(polyline: coords, colorHex: "#1473FF"))
        }
        layers.append(.markers(pins))

        // Camera: center on the leg-chain midpoint (or the single port).
        let center = coords[coords.count / 2]

        return VStack(alignment: .leading, spacing: 0) {
            BespokeMapCanvas(
                center: center,
                zoom: coords.count >= 2 ? 3 : 5,
                interactive: true,
                tilt: 0,
                isDark: colorScheme == .dark,
                layers: layers,
                style: .ocean,
                onSelectMarker: { _ in /* pin tap → branded port detail card */ }
            )
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))

            // Caption: real resolved count + honest skip note when a code
            // wasn't in the catalog.
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x5AA6FF))
                Text(captionText(resolved: calls.count))
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.top, Space.s2)
        }
    }

    private func captionText(resolved: Int) -> String {
        let legs = max(resolved - 1, 0)
        let base = "\(resolved) port call\(resolved == 1 ? "" : "s") · \(legs) leg\(legs == 1 ? "" : "s") · PortDirectory / UN/LOCODE"
        return unresolvedPortCount > 0 ? "\(base) · \(unresolvedPortCount) off-catalog skipped" : base
    }

    // MARK: - Documentation cutoffs (ERD / VGM / SI / CY / DG / reefer)

    /// One cutoff line: label + real datetime (or "—"). The "Derived" provenance
    /// lives on the section header, not per-row.
    private struct CutoffLine688: Identifiable {
        let id = UUID()
        let name: String
        let iso: String?
    }

    private var cutoffLines: [CutoffLine688] {
        guard let c = cutoffs else { return [] }
        return [
            CutoffLine688(name: "Earliest return (ERD)", iso: c.erdAt),
            CutoffLine688(name: "VGM cutoff",            iso: c.vgmCutoffAt),
            CutoffLine688(name: "SI cutoff",             iso: c.siCutoffAt),
            CutoffLine688(name: "Cargo (CY) cutoff",     iso: c.cargoCutoffAt),
            CutoffLine688(name: "DG cutoff",             iso: c.dgCutoffAt),
            CutoffLine688(name: "Reefer cutoff",         iso: c.reeferCutoffAt),
        ]
    }

    @ViewBuilder
    private var cutoffsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("DOCUMENTATION CUTOFFS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                if cutoffs?.derived == true {
                    Text("Derived")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xF0B760))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Brand.warning.opacity(0.18)))
                }
            }

            if cutoffs == nil {
                EusoEmptyState(
                    icon: Image(systemName: "calendar.badge.clock"),
                    title: "No booking cutoffs",
                    subtitle: "ERD, VGM, SI, CY, DG and reefer cutoffs appear once you have an upcoming booking."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(cutoffLines.enumerated()), id: \.element.id) { idx, line in
                        if idx > 0 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                        }
                        HStack {
                            Text(line.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Spacer(minLength: 8)
                            Text(line.iso.map { shortDateTime($0) } ?? "—")
                                .font(EType.mono(.caption)).tracking(0.2)
                                .foregroundStyle(line.iso == nil ? palette.textTertiary : palette.textPrimary)
                        }
                        .padding(.vertical, Space.s3)
                    }
                }
                .padding(.horizontal, Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            }
        }
    }

    /// The soonest still-future cutoff among the set, with a formatted countdown.
    private func soonestUpcomingCutoff() -> (name: String, countdown: String)? {
        let now = Date()
        let upcoming: [(String, Date)] = cutoffLines.compactMap { line in
            guard let iso = line.iso, let d = parseISO(iso), d > now else { return nil }
            return (line.name, d)
        }.sorted { $0.1 < $1.1 }
        guard let first = upcoming.first else { return nil }
        return (first.0, countdownString(to: first.1))
    }

    /// Fraction of a 7-day window elapsed toward the soonest cutoff (clamped).
    private func cutoffProgressFraction() -> CGFloat {
        let now = Date()
        let upcoming: [Date] = cutoffLines.compactMap { line in
            guard let iso = line.iso, let d = parseISO(iso), d > now else { return nil }
            return d
        }.sorted()
        guard let target = upcoming.first else { return 0 }
        let window: TimeInterval = 7 * 86400
        let remaining = target.timeIntervalSince(now)
        let frac = 1.0 - min(max(remaining / window, 0), 1)
        return CGFloat(frac)
    }

    private func countdownString(to date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "due" }
        let totalHours = Int(remaining / 3600)
        let d = totalHours / 24
        let h = totalHours % 24
        return d > 0 ? String(format: "%dd %02dh", d, h) : String(format: "%dh", h)
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
                    Text(berthVgmLine)
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

    /// Real VGM cutoff for the bound booking (the berth-schedule window itself is
    /// a documented PORT-GAP until getBerthSchedule carries a portId here).
    private var berthVgmLine: String {
        let vgm = cutoffs?.vgmCutoffAt.map { shortDateTime($0) }
        return "berth window pending · VGM cutoff \(vgm ?? "—")"
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
                 + Text(" now, v.430E is blanked; next firm slot is ")
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
        guard let dep = parseISO(v.scheduledDeparture), let arr = parseISO(v.scheduledArrival) else { return "-" }
        let days = Int(arr.timeIntervalSince(dep) / 86400.0)
        return "\(max(days, 0))d"
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
        guard let d = parseISO(s) else { return "-" }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func shortDateTime(_ s: String?) -> String {
        guard let d = parseISO(s) else { return "-" }
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
        // multiModal.getVesselSchedules surfaces ports.unlocode per row (real
        // catalog join); used only to anchor the sailing map's port calls.
        // serviceRoute (when deep-linked) filters by shipping line so the map
        // shows this string's calls. All inputs optional on the proc.
        struct MMScheduleIn688: Encodable {
            let shippingLine: String?
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
            async let mm: MMScheduleResponse688 = EusoTripAPI.shared.query(
                "multiModal.getVesselSchedules",
                input: MMScheduleIn688(shippingLine: serviceRoute.isEmpty ? nil : serviceRoute)
            )
            let (voy, dash, mmResp) = try await (sched, bs, mm)
            self.voyages = voy
            self.blank = dash
            self.scheduleRows = mmResp.vessels ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        // Secondary (non-fatal): bind the real cutoff set to the soonest upcoming
        // booking. A failure here never blanks the schedule.
        await loadCutoffs()
        loading = false
    }

    /// getVesselShipments → pick the soonest upcoming accessible booking → its
    /// getCutoffs. Non-fatal; nil cutoffs render honest em-dashes in the hero.
    private func loadCutoffs() async {
        struct ShipmentsIn688: Encodable { let limit: Int; let offset: Int }
        struct CutoffsIn688: Encodable { let shipmentId: Int }
        guard let env: VesselShipmentsEnvelope688 = try? await EusoTripAPI.shared.query(
            "vesselShipments.getVesselShipments", input: ShipmentsIn688(limit: 20, offset: 0)) else {
            cutoffs = nil; return
        }
        let terminal: Set<String> = ["delivered", "invoiced", "settled", "cancelled", "gate_out"]
        let dated = env.shipments
            .filter { !terminal.contains(($0.status ?? "").lowercased()) }
            .compactMap { s -> (VesselShipmentLite688, Date)? in
                guard let etd = s.etd, let d = parseISO(etd) else { return nil }
                return (s, d)
            }
            .sorted { $0.1 < $1.1 }
        // Prefer the soonest ETD still in the future; else the latest booking.
        let now = Date()
        let nearest = dated.first(where: { $0.1 >= now })?.0 ?? dated.last?.0
        guard let sid = nearest?.id else { cutoffs = nil; return }
        cutoffs = try? await EusoTripAPI.shared.query(
            "vesselShipments.getCutoffs", input: CutoffsIn688(shipmentId: sid))
    }
}

#Preview("688 · Vessel Sailing Schedule · Night") { VesselSailingScheduleScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("688 · Vessel Sailing Schedule · Light") { VesselSailingScheduleScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
