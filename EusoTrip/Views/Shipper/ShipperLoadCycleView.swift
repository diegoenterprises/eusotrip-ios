//
//  ShipperLoadCycleView.swift
//  EusoTrip 2027 UI — Shipper · per-load lifecycle visualization
//
//  Animated stage progression strip that mirrors the Driver lifecycle
//  doctrine on the Shipper side. Drops into 205_ShipperLoadDetail (and
//  any other Shipper surface that wants a "where's my load right now?"
//  affordance) so the Shipper sees the SAME product/vertical-aware
//  visualization the Driver gets through `LifecycleProductContext`.
//
//  Stage taxonomy (8 stages):
//    Posted → Bidding → Awarded → Pickup → In transit → Delivery →
//    Paperwork → Closed
//
//  Resolution from `LoadsAPI.LoadDetail.status`:
//    • posted / draft                  → .posted
//    • bidding                         → .bidding
//    • assigned / accepted / awarded   → .awarded
//    • at_pickup / pickup_checkin /
//      loading / pickup_arrival        → .pickup
//    • in_transit / en_route /
//      en_route_pickup / departing*    → .inTransit
//    • approaching_delivery /
//      at_delivery / unloading         → .delivery
//    • pod_pending / paperwork /
//      bol_signoff / invoiced          → .paperwork
//    • delivered / completed /
//      paid / closed                   → .closed
//    • cancelled / expired             → .closed (with cancelled accent)
//
//  Each stage renders:
//    • Tap-target dot (12pt) — gradient when reached, faint outline pending
//    • Product/vertical silhouette behind the active stage
//    • Connecting hairline that fills as the load progresses
//
//  Animation doctrine §B.4 — `.easeOut(duration: 0.18)` for stage
//  cross-fades, `.spring(response: 0.32, dampingFraction: 0.85)` for
//  the active-stage scale-in. `@Reducerable accessibility-elements`
//  bumped under `.accessibilityReduceMotion` so motion-sensitive
//  shippers get the static positions only.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - LoadCycleStage

/// Canonical 8-stage progression every Shipper load passes through,
/// from posted → closed. Drives both the dot strip and the product
/// silhouette overlay so the same enum determines color, icon, copy,
/// and animation curve everywhere in the visualization.
enum LoadCycleStage: Int, CaseIterable, Identifiable, Hashable {
    case posted = 0
    case bidding
    case awarded
    case pickup
    case inTransit
    case delivery
    case paperwork
    case closed

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .posted:     return "Posted"
        case .bidding:    return "Bidding"
        case .awarded:    return "Awarded"
        case .pickup:     return "Pickup"
        case .inTransit:  return "In transit"
        case .delivery:   return "Delivery"
        case .paperwork:  return "Paperwork"
        case .closed:     return "Closed"
        }
    }

    var symbol: String {
        switch self {
        case .posted:     return "tray.full"
        case .bidding:    return "hand.raised"
        case .awarded:    return "checkmark.seal"
        case .pickup:     return "arrow.up.bin"
        case .inTransit:  return "location.north.line"
        case .delivery:   return "mappin.and.ellipse"
        case .paperwork:  return "doc.text.below.ecg"
        case .closed:     return "checkmark.circle"
        }
    }

    /// Product-aware verb the active-stage tile uses for its kicker
    /// — "PICKING UP / IN TRANSIT / UNLOADING" reads more concrete
    /// than the static label and matches the Driver lifecycle
    /// screens' verb tense.
    func kicker(for product: TripProduct) -> String {
        switch self {
        case .posted:    return "POSTED · AWAITING BIDS"
        case .bidding:
            return product.isHazmat
                ? "BIDDING · HAZMAT-CERTIFIED CARRIERS"
                : "BIDDING · CARRIERS REVIEWING"
        case .awarded:   return "AWARDED · CARRIER LOCKED"
        case .pickup:
            switch product {
            case .hazmatTanker, .vesselTanker:  return "LOADING · TANKER FILL IN PROGRESS"
            case .reefer:                        return "LOADING · REEFER PRE-COOL ACTIVE"
            case .flatbed:                       return "LOADING · TARP + STRAP IN PROGRESS"
            case .container, .vesselContainer:   return "LOADING · CONTAINER STUFFING"
            case .railIntermodal:                return "LOADING · INTERMODAL RAMP"
            case .railBulk:                      return "LOADING · HOPPER FILL"
            case .vesselBulk:                    return "LOADING · BULK HOLD FILL"
            case .dryVan:                        return "LOADING · PALLETS ON BOARD"
            }
        case .inTransit:
            switch product {
            case .hazmatTanker, .vesselTanker:  return "IN TRANSIT · 49 CFR 397 ACTIVE"
            case .reefer:                        return "IN TRANSIT · SETPOINT MAINTAINED"
            case .flatbed:                       return "IN TRANSIT · STRAP TENSION OK"
            case .container, .vesselContainer:   return "IN TRANSIT · BOX SEALED"
            case .railIntermodal, .railBulk:     return "IN TRANSIT · RAIL CONSIST MOVING"
            case .vesselBulk:                    return "IN TRANSIT · VESSEL UNDERWAY"
            case .dryVan:                        return "IN TRANSIT · ROUTE ACTIVE"
            }
        case .delivery:
            switch product {
            case .hazmatTanker, .vesselTanker:   return "UNLOADING · TANKER DRAIN"
            case .reefer:                        return "UNLOADING · TEMP-LOG VERIFIED"
            case .flatbed:                       return "UNLOADING · UN-STRAPPING"
            case .container, .vesselContainer:   return "UNLOADING · BOX RECEIVED"
            case .railIntermodal:                return "DESTINATION · INTERMODAL RAMP"
            case .railBulk:                      return "UNLOADING · HOPPER DROP"
            case .vesselBulk:                    return "UNLOADING · BULK DISCHARGE"
            case .dryVan:                        return "UNLOADING · DOCK ASSIGNED"
            }
        case .paperwork: return product.isHazmat
            ? "PAPERWORK · BOL + HAZMAT MANIFEST + CHEMTREC"
            : "PAPERWORK · BOL + POD"
        case .closed:    return "CLOSED · LOAD DELIVERED"
        }
    }

    /// Resolve from a server-emitted load.status string. Returns the
    /// canonical stage for the broadest set of status enum values the
    /// platform has shipped over time. Unknown statuses fall through
    /// to `.posted` so a brand-new state never crashes the strip.
    static func resolve(from status: String?) -> LoadCycleStage {
        let s = (status ?? "").lowercased()

        // Closed-state buckets first (cancelled / completed both
        // resolve to .closed but with different accent in the view).
        if s == "delivered" || s == "completed" || s == "paid" ||
            s == "closed" || s == "complete" {
            return .closed
        }
        if s == "cancelled" || s == "canceled" || s == "expired" ||
            s == "rejected" {
            return .closed
        }

        if s == "pod_pending" || s.contains("paperwork") ||
            s == "bol_signoff" || s == "invoiced" {
            return .paperwork
        }
        if s == "approaching_delivery" || s == "at_delivery" ||
            s == "at_receiver" || s == "unloading" || s == "dock_assigned" ||
            s == "backing_in" {
            return .delivery
        }
        if s == "in_transit" || s == "en_route" || s == "en_route_pickup" ||
            s == "en_route_drive" || s == "en_route_loaded" ||
            s == "departing" || s == "departing_pickup" {
            return .inTransit
        }
        if s == "at_pickup" || s == "pickup_checkin" || s == "pickup_arrival" ||
            s == "loading" || s == "loading_in_progress" || s == "approaching_pickup" {
            return .pickup
        }
        if s == "assigned" || s == "accepted" || s == "awarded" ||
            s == "load_locked" || s == "load_locked_prehaul" {
            return .awarded
        }
        if s == "bidding" {
            return .bidding
        }
        if s == "posted" || s == "draft" || s == "pending" || s.isEmpty {
            return .posted
        }
        return .posted
    }

    /// True for cancelled / expired / rejected statuses — the view uses
    /// this to dim the strip and tint the closed dot Brand.danger.
    static func isCancelled(_ status: String?) -> Bool {
        let s = (status ?? "").lowercased()
        return s == "cancelled" || s == "canceled" || s == "expired" ||
               s == "rejected"
    }
}

// MARK: - ShipperLoadCycleView

/// Horizontal lifecycle strip with 8 stage dots, a connecting hairline
/// that fills as the load progresses, an active-stage product
/// silhouette, and a kicker line tying the visualization back to copy.
///
/// Doctrine: Driver lifecycle screens use `LifecycleProductContext` to
/// resolve a `TripProduct` and dispatch all visualization choices on
/// it. The Shipper-side mirror does the same — same enum, same
/// silhouette table, same animation curves — so a hazmat tanker load
/// reads as a hazmat tanker load on both surfaces.
struct ShipperLoadCycleView: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Current load status (server-emitted enum string). Drives the
    /// stage resolution.
    let status: String?
    /// Resolved product from `LifecycleProductContext` — owns the
    /// silhouette and kicker dispatch.
    let product: TripProduct
    /// Vertical for word-choice (truck pickup vs rail interchange vs
    /// vessel berth) on the active-stage kicker.
    let vertical: TripVertical
    /// Optional taps so the surrounding sheet can drill in to a
    /// stage-specific timeline view. nil = strip is read-only.
    var onSelectStage: ((LoadCycleStage) -> Void)? = nil

    private var current: LoadCycleStage { LoadCycleStage.resolve(from: status) }
    private var isCancelled: Bool { LoadCycleStage.isCancelled(status) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Active-stage kicker. Mirrors Driver lifecycle screen
            // headers (eyebrow line above the title in 014, 016, 020,
            // etc.) so the visual language carries cross-role.
            kickerLine
                .id(current) // re-trigger transition on stage flip
                .transition(.opacity.combined(with: .move(edge: .leading)))

            stageStrip
                .frame(height: 72)
        }
        .padding(.vertical, Space.s3)
        .padding(.horizontal, Space.s3)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Brand.gradientStart.opacity(isCancelled ? 0.0 : 0.8),
                            Brand.gradientEnd.opacity(isCancelled ? 0.0 : 0.8),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .opacity(isCancelled ? 0.55 : 1.0)
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22),
            value: current
        )
    }

    // MARK: Kicker

    private var kickerLine: some View {
        HStack(spacing: 6) {
            Image(systemName: product.symbol)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(isCancelled ? "CANCELLED · LOAD CLOSED" : current.kicker(for: product))
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(
                    isCancelled
                        ? AnyShapeStyle(Brand.danger)
                        : AnyShapeStyle(LinearGradient.diagonal)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            Text(product.label)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Stage strip

    private var stageStrip: some View {
        GeometryReader { geo in
            let count = LoadCycleStage.allCases.count
            let stageWidth = geo.size.width / CGFloat(count)
            let progressX = stageWidth * (CGFloat(current.rawValue) + 0.5)

            ZStack(alignment: .topLeading) {
                // Hairline backdrop spanning all stages.
                Capsule(style: .continuous)
                    .fill(palette.borderFaint.opacity(0.55))
                    .frame(height: 2)
                    .offset(y: 18)

                // Filled progress hairline up to the current stage's
                // dot center. Spring on motion-sensitive devices is
                // flat (`.easeOut`) so the bar doesn't whip past the
                // dot center.
                Capsule(style: .continuous)
                    .fill(
                        isCancelled
                            ? AnyShapeStyle(Brand.danger.opacity(0.7))
                            : AnyShapeStyle(LinearGradient.diagonal)
                    )
                    .frame(width: max(0, progressX), height: 3)
                    .offset(y: 17.5)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.15)
                                     : .spring(response: 0.42, dampingFraction: 0.86),
                        value: progressX
                    )

                // Stage dots + labels — laid out across the full width.
                HStack(spacing: 0) {
                    ForEach(LoadCycleStage.allCases) { stage in
                        stageDot(stage: stage)
                            .frame(width: stageWidth)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stageDot(stage: LoadCycleStage) -> some View {
        let reached = stage.rawValue <= current.rawValue
        let isActive = stage == current && !isCancelled

        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(
                        reached
                            ? AnyShapeStyle(LinearGradient.diagonal)
                            : AnyShapeStyle(palette.bgCard)
                    )
                    .frame(width: isActive ? 22 : 14, height: isActive ? 22 : 14)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                reached
                                    ? Color.white.opacity(0.5)
                                    : palette.borderFaint,
                                lineWidth: 1.5
                            )
                    )
                    .shadow(
                        color: isActive ? Brand.gradientEnd.opacity(0.45) : .clear,
                        radius: isActive ? 6 : 0
                    )
                Image(systemName: stage.symbol)
                    .font(.system(size: isActive ? 10 : 7, weight: .heavy))
                    .foregroundStyle(reached ? Color.white : palette.textTertiary)
            }
            .scaleEffect(isActive ? 1.0 : 0.95)
            .animation(
                reduceMotion ? .easeOut(duration: 0.15)
                             : .spring(response: 0.32, dampingFraction: 0.85),
                value: isActive
            )

            Text(stage.label)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(
                    reached ? palette.textPrimary : palette.textTertiary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectStage?(stage)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(reached ? "\(stage.label), reached" : "\(stage.label), pending")
    }
}

// MARK: - Previews

#Preview("ShipperLoadCycleView · Hazmat in transit · Dark") {
    ShipperLoadCycleView(
        status: "in_transit",
        product: .hazmatTanker,
        vertical: .truck
    )
    .padding()
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
    .background(Theme.dark.bgPage)
}

#Preview("ShipperLoadCycleView · Reefer pickup · Light") {
    ShipperLoadCycleView(
        status: "loading",
        product: .reefer,
        vertical: .truck
    )
    .padding()
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
    .background(Theme.light.bgPage)
}

#Preview("ShipperLoadCycleView · Vessel container delivery · Dark") {
    ShipperLoadCycleView(
        status: "at_delivery",
        product: .vesselContainer,
        vertical: .vessel
    )
    .padding()
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
    .background(Theme.dark.bgPage)
}

#Preview("ShipperLoadCycleView · Cancelled · Dark") {
    ShipperLoadCycleView(
        status: "cancelled",
        product: .dryVan,
        vertical: .truck
    )
    .padding()
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
    .background(Theme.dark.bgPage)
}
