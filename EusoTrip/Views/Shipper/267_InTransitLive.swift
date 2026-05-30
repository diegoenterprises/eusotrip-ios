//
//  267_InTransitLive.swift
//  EusoTrip — Shipper · Stage 5 · IN TRANSIT · live (refactored).
//
//  BESPOKE RE-SKIN (2026-05-30): the consolidated in-transit screen now
//  renders three bespoke per-mode VISUAL STATES derived from
//  `live.load.relationship` — head_haul (base), backhaul, matrix —
//  matched to wireframes 254 (BH In-Transit Echo) and 268 (In Transit
//  Echo M04). The wiring, flow, and consolidation are unchanged: the
//  same Shell → LifecycleScaffold(loadId:) → InTransitBody. The mode
//  only changes accent color, eyebrow text, and adds a bespoke context
//  card built from REAL snapshot data (or honest-empty). The
//  map/telemetry/comms sections are untouched.
//

import SwiftUI

/// Per-mode bespoke visual identity for the in-transit echo surface.
/// Derived from the server's `relationship` string; nil / unknown ⇒
/// `.headHaul` so the existing thin payloads keep today's exact look.
private enum TransitMode {
    case headHaul   // base — Brand.blue accent, current behavior
    case backhaul   // wireframe 254 — teal #00E5A2 accent
    case matrix     // wireframe 268 — violet #C9A7FF accent

    init(relationship: String?) {
        switch relationship?.lowercased() {
        case "backhaul": self = .backhaul
        case "matrix":   self = .matrix
        default:         self = .headHaul   // nil / "head_haul" / unknown
        }
    }

    /// Eyebrow chip text fed into `LifecycleScaffold(... eyebrow:)`.
    var eyebrow: String {
        switch self {
        case .headHaul: return "SHIPPER · IN TRANSIT · LIVE · STAGE 5 OF 8"
        case .backhaul: return "ECHO · DOWNSTREAM BACKHAUL · IN-TRANSIT"
        case .matrix:   return "§11.4 IN-TRANSIT ECHO · MATRIX"
        }
    }

    /// Bespoke accent color pulled from the canonical SVGs.
    /// head_haul keeps the brand blue; backhaul = teal #00E5A2;
    /// matrix = violet #C9A7FF. (Both hexes exist as `Color(hex:)`
    /// inits in DesignSystem.)
    var accent: Color {
        switch self {
        case .headHaul: return Brand.blue
        case .backhaul: return Color(hex: 0x00E5A2)
        case .matrix:   return Color(hex: 0xC9A7FF)
        }
    }

    /// Badge / pill label shown above the body for the non-base modes.
    /// nil for head_haul — no extra chrome, identical to today.
    var badge: String? {
        switch self {
        case .headHaul: return nil
        case .backhaul: return "BACKHAUL · §327"
        case .matrix:   return "MATRIX · §11.4 ECHO"
        }
    }
}

struct InTransitLiveScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            // The eyebrow is mode-derived, but the snapshot lands inside
            // the scaffold — so the scaffold gets the base eyebrow and the
            // body re-states the mode eyebrow as a bespoke pill once the
            // relationship is known. (Scaffold wiring unchanged.)
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · IN TRANSIT · LIVE · STAGE 5 OF 8", cycleStatus: "in_transit") { live in
                InTransitBody(live: live)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct InTransitBody: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot

    private var mode: TransitMode { TransitMode(relationship: live.load.relationship) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            modeBanner            // bespoke per-mode pill + eyebrow (nil-render for head_haul)
            etaStrip
            backhaulContext       // bespoke downstream-chain card (backhaul only)
            matrixCarrierCard     // bespoke awarded-carrier card (matrix only)
            LifecycleAnimationStrip(live: live, label: "EQUIPMENT", height: 200)
            LifecycleMapCard(live: live, label: "LIVE TRACK", mode: .full, height: 260)
            telemetryCard
            commsRow
        }
    }

    // MARK: - Bespoke per-mode banner (eyebrow + pill)

    @ViewBuilder
    private var modeBanner: some View {
        if let badge = mode.badge {
            HStack(spacing: Space.s2) {
                // Bespoke chip — pill treatment matching the SVG's gradient
                // capsule, but tinted to the per-mode accent with a check
                // glyph (the SVGs' "echo closed / rolling" pill).
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(mode.accent)
                    Text(badge)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(mode.accent)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(mode.accent.opacity(0.12))
                .overlay(Capsule().strokeBorder(mode.accent.opacity(0.45), lineWidth: 1))
                .clipShape(Capsule())

                Text(mode.eyebrow)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
    }

    private var etaStrip: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ETA",      value: humanISO(live.load.estimatedDeliveryDate, format: "MMM d · HH:mm"), icon: "clock")
            LifecycleStatTile(label: "DISTANCE", value: live.load.distance.map { "\(Int($0)) mi" } ?? "—", icon: "ruler")
            LifecycleStatTile(label: "STATUS",   value: live.load.status.uppercased(), icon: "flag")
        }
    }

    // MARK: - Backhaul bespoke context (wireframe 254 · "DOWNSTREAM CHAIN")

    /// Honest re-skin of the 254 "DOWNSTREAM CHAIN" treatment: a teal
    /// left-rail card with the real load number, carrier, and distance.
    /// Does NOT fabricate the SVG's mock "5 quartets / 72/72" numbers —
    /// only shows real snapshot values. If we have nothing real beyond
    /// the load row, the rows below collapse to honest em-dash sentinels.
    @ViewBuilder
    private var backhaulContext: some View {
        if mode == .backhaul {
            LifecycleCard {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(mode.accent)
                        .frame(width: 3, height: 14)
                    Text("DOWNSTREAM CHAIN")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(mode.accent)
                    Spacer(minLength: 0)
                    Text("BACKHAUL")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                LifecycleRow(label: "Backhaul load", value: live.load.loadNumber)
                LifecycleRow(label: "Carrier",
                             value: live.carrier?.name ?? "—")
                LifecycleRow(label: "Distance remaining",
                             value: live.load.distance.map { "\(Int($0)) mi" } ?? "—")
            }
        }
    }

    // MARK: - Matrix bespoke awarded-carrier card (wireframe 268 · "CEL · JR Reyes")

    /// Honest re-skin of the 268 carrier-identity block ("CEL · JR Reyes").
    /// Built ENTIRELY from real snapshot fields — carrier name, DOT/MC, and
    /// driver name. The miles-progress line renders ONLY when we can compute
    /// it from real data (distance + a real truck position via lastGeofence);
    /// otherwise it is omitted (no hardcoded "80/245 · 33%").
    @ViewBuilder
    private var matrixCarrierCard: some View {
        if mode == .matrix {
            LifecycleCard(accentGradient: false) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(mode.accent)
                        .frame(width: 3, height: 14)
                    Text("AWARDED CARRIER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(mode.accent)
                    Spacer(minLength: 0)
                    Text("§11.4 ECHO")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }

                // Carrier identity block — monogram disc + name + DOT/MC,
                // styled per the 268 "CEL · JR Reyes" row with the violet
                // accent. All real-or-empty.
                HStack(alignment: .center, spacing: 10) {
                    Text(carrierMonogram)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(
                                LinearGradient(colors: [mode.accent, mode.accent.opacity(0.55)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(live.carrier?.name ?? "Carrier pending")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(carrierAuthorityLine)
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }

                LifecycleRow(label: "Driver", value: live.driver?.name ?? "—")

                // Real miles-progress line — ONLY if computable.
                if let milesLine = matrixMilesLine {
                    LifecycleRow(label: "Progress", value: milesLine)
                }
            }
        }
    }

    /// First-two-letters monogram from the carrier name, else "CR".
    private var carrierMonogram: String {
        guard let name = live.carrier?.name, !name.isEmpty else { return "CR" }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// "USDOT … · MC-…" — only the real parts we have; honest em-dash
    /// when the carrier authority is not on the snapshot.
    private var carrierAuthorityLine: String {
        var parts: [String] = []
        if let dot = live.carrier?.dotNumber, !dot.isEmpty { parts.append("USDOT \(dot)") }
        if let mc = live.carrier?.mcNumber, !mc.isEmpty { parts.append("MC-\(mc)") }
        return parts.isEmpty ? "Authority pending" : parts.joined(separator: " · ")
    }

    /// "{done}/{total} mi · {pct}%" computed ONLY from real data.
    /// We need: a total distance (load.distance) AND a real truck position
    /// expressed as remaining-distance signal. The snapshot doesn't carry a
    /// numeric "miles done", so we only synthesize this line when the
    /// geofence carries an honest dwell/position we can turn into progress.
    /// Today the snapshot exposes no real "miles completed" scalar, so this
    /// returns nil and the line is omitted — no fabricated 80/245.
    private var matrixMilesLine: String? {
        // Guard: requires both a total and a real, computable "done".
        // The lifecycle snapshot does not expose a server-side
        // milesCompleted / percentComplete scalar, and a single geofence
        // lat/lng cannot be honestly converted to road-miles here without
        // a routing call. Omit until a real progress scalar exists.
        return nil
    }

    private var telemetryCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LATEST TELEMETRY", icon: "antenna.radiowaves.left.and.right")
            if let g = live.lastGeofence {
                LifecycleRow(label: "Last event",  value: g.type.uppercased())
                LifecycleRow(label: "Recorded at", value: humanISO(g.eventTimestamp))
                LifecycleRow(label: "GPS",         value: String(format: "%.4f, %.4f", g.latitude, g.longitude))
                if let dwell = g.dwellSeconds {
                    LifecycleRow(label: "Dwell", value: "\(dwell / 60) min")
                }
            } else {
                Text("Truck en route — no geofence event in this window yet.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LifecycleRow(label: "Pickup window",   value: humanISO(live.load.pickupDate))
            LifecycleRow(label: "Delivery window", value: humanISO(live.load.deliveryDate))
        }
    }

    private var commsRow: some View {
        HStack(spacing: 8) {
            commsButton(icon: "phone.fill", label: "Driver",  phone: live.driver?.phone)
            commsButton(icon: "phone.fill", label: "Carrier", phone: nil) // carrier dispatch line — future endpoint
            commsButton(icon: "map.fill",   label: "Map",     phone: nil)
        }
    }

    private func commsButton(icon: String, label: String, phone: String?) -> some View {
        let mapDeepLink: URL? = {
            guard icon == "map.fill" else { return nil }
            // Truck's current pin first; fall back to delivery
            // facility coords; finally the destination address.
            if let g = live.lastGeofence {
                return URL(string: "maps://?ll=\(g.latitude),\(g.longitude)&q=Truck")
            }
            if let lat = live.delivery?.lat, let lng = live.delivery?.lng {
                return URL(string: "maps://?ll=\(lat),\(lng)&q=Delivery")
            }
            if let addr = live.delivery?.address, !addr.isEmpty {
                let q = addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                return URL(string: "maps://?q=\(q)")
            }
            return nil
        }()
        let enabled = (phone?.isEmpty == false) || (icon == "map.fill" && mapDeepLink != nil)
        return Button {
            if let p = phone, let url = URL(string: "tel://\(p.filter(\.isNumber))") {
                UIApplication.shared.open(url)
            } else if let url = mapDeepLink {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(enabled ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

#Preview("267 · In transit · Live · Night") {
    InTransitLiveScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("267 · In transit · Live · Afternoon") {
    InTransitLiveScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
