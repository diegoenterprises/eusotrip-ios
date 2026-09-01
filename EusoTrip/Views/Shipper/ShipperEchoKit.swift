//
//  ShipperEchoKit.swift
//  EusoTrip — Shipper · shared vocabulary for the LIFECYCLE ECHO band
//             (wireframes 270–277 · M-04 tail + M-05 chain).
//
//  These eight screens are the shipper's REFLECTION of each load-lifecycle
//  stage — posted → bidding → awarded → pickup → in-transit → delivery →
//  paperwork → closed. They are genuinely distinct stage-screens (a bid
//  board, an award ledger, a live map, a settlement roster), so they ship
//  as eight individual files, NOT a folded composite. What they DO share is
//  this Kit: one 8-stage lifecycle ribbon, one snapshot state machine, one
//  header recipe, and the small echo primitives (party row, doc chip,
//  stat cell, roster row, settlement strip).
//
//  Wiring backbone (all on-disk confirmed):
//    • shippers.getLifecycleSnapshot  → ShipperAPI.LifecycleSnapshot
//      (shippers.ts — protectedProcedure, companyId-owned)
//    • per-screen secondary reads (getBidsForLoad / getSettlementForLoad /
//      pod.getPODForLoad) live in the individual screens.
//
//  Doctrine: 0 mock data. Every value renders from the live snapshot or an
//  honest em-dash sentinel. Bottom nav is the canonical shipper 5-slot via
//  `shipperLifecycleNav(currentSlot: .loads)` — the older SVGs drew a legacy
//  pill nav; real code wins, so the notched plate ships.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Lifecycle stage model

/// The canonical 8-stage shipper lifecycle the echo ribbon paints.
/// Ordinals drive the ribbon fill; `from(status:)` maps the live
/// `loads.status` enum onto the ribbon so the active node is never guessed.
enum ShipperEchoStage: Int, CaseIterable {
    case posted, bidding, awarded, pickup, inTransit, delivery, paperwork, closed

    var label: String {
        switch self {
        case .posted:     return "POSTED"
        case .bidding:    return "BIDDING"
        case .awarded:    return "AWARDED"
        case .pickup:     return "PICKUP"
        case .inTransit:  return "IN TRANSIT"
        case .delivery:   return "DELIVERY"
        case .paperwork:  return "PAPERWORK"
        case .closed:     return "CLOSED"
        }
    }

    /// Compact label for the narrow 7-node ribbon variant (276).
    var shortLabel: String {
        switch self {
        case .posted:     return "POSTED"
        case .bidding:    return "BID"
        case .awarded:    return "AWARD"
        case .pickup:     return "PICKUP"
        case .inTransit:  return "TRANSIT"
        case .delivery:   return "DELIV"
        case .paperwork:  return "DOCS"
        case .closed:     return "CLOSED"
        }
    }

    /// Map the live `loads.status` string onto a ribbon node. Unknown /
    /// missing status resolves to `.posted` (the honest floor) rather than
    /// fabricating downstream progress.
    static func from(status: String?) -> ShipperEchoStage {
        switch (status ?? "").lowercased() {
        case "pending", "draft", "posted", "open":
            return .posted
        case "bidding", "quoting", "in_bidding":
            return .bidding
        case "accepted", "awarded", "assigned", "tendered", "booked", "dispatched":
            return .awarded
        case "at_pickup", "arrived_pickup", "picked_up", "loading", "loaded":
            return .pickup
        case "in_transit", "en_route", "enroute", "rolling":
            return .inTransit
        case "at_delivery", "arrived_delivery", "delivered", "unloaded",
             "pod_pending", "pod_submitted", "pod_rejected":
            return .delivery
        case "invoiced", "paperwork", "pod_approved", "billing":
            return .paperwork
        case "paid", "completed", "closed", "settled", "complete":
            return .closed
        default:
            return .posted
        }
    }
}

// MARK: - 8-stage lifecycle ribbon (shared across all eight echo screens)

/// The signature echo ribbon: eight nodes on a hairline rail, completed
/// nodes filled + checked, the active node ringed with a soft glow, future
/// nodes hollow. The gradient rail runs from the first node to the active
/// node. A single caption line underneath carries the stage's plain-language
/// status. This is the one element every 270–277 screen shares.
struct ShipperEchoLifecycleStrip: View {
    @Environment(\.palette) private var palette
    let active: ShipperEchoStage
    var sectionLabel: String = "LIFECYCLE"
    var caption: String? = nil
    /// Narrow variant (276) drops label size and uses `shortLabel`.
    var compact: Bool = false

    private var stages: [ShipperEchoStage] { ShipperEchoStage.allCases }
    private var activeIdx: Int { active.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sectionLabel)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            GeometryReader { geo in
                let w = geo.size.width
                let n = stages.count
                let midY: CGFloat = 12
                Path { p in
                    p.move(to: CGPoint(x: nodeX(0, w), y: midY))
                    p.addLine(to: CGPoint(x: nodeX(n - 1, w), y: midY))
                }
                .stroke(palette.borderFaint, lineWidth: 2)

                Path { p in
                    p.move(to: CGPoint(x: nodeX(0, w), y: midY))
                    p.addLine(to: CGPoint(x: nodeX(activeIdx, w), y: midY))
                }
                .stroke(LinearGradient.primary, lineWidth: 2)

                ForEach(stages, id: \.self) { s in
                    node(for: s)
                        .position(x: nodeX(s.rawValue, w), y: midY)
                }
            }
            .frame(height: 24)

            HStack(spacing: 0) {
                ForEach(stages, id: \.self) { s in
                    Text(compact ? s.shortLabel : s.label)
                        .font(.system(size: compact ? 7 : 7.5, weight: .heavy))
                        .tracking(0.2)
                        .foregroundStyle(labelStyle(s))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }

            if let caption {
                Text(caption)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func nodeX(_ i: Int, _ w: CGFloat) -> CGFloat {
        let n = CGFloat(stages.count)
        return w * (CGFloat(i) + 0.5) / n
    }

    @ViewBuilder
    private func node(for s: ShipperEchoStage) -> some View {
        let i = s.rawValue
        if i < activeIdx {
            // Completed — filled gradient dot with a white check.
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 13, height: 13)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
            }
        } else if i == activeIdx {
            // Active — ringed node with a soft brand glow.
            ZStack {
                Circle().fill(LinearGradient.diagonal.opacity(0.25)).frame(width: 24, height: 24)
                Circle().strokeBorder(LinearGradient.primary, lineWidth: 2).frame(width: 22, height: 22)
                Circle().fill(LinearGradient.diagonal).frame(width: 15, height: 15)
                Circle().fill(Color.white).frame(width: 6, height: 6)
            }
        } else {
            // Future — hollow node.
            Circle()
                .fill(palette.bgCard)
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(palette.borderSoft, lineWidth: 1.4))
        }
    }

    private func labelStyle(_ s: ShipperEchoStage) -> AnyShapeStyle {
        let i = s.rawValue
        if i == activeIdx { return AnyShapeStyle(LinearGradient.diagonal) }
        if i < activeIdx { return AnyShapeStyle(palette.textPrimary) }
        return AnyShapeStyle(palette.textTertiary)
    }
}

// MARK: - Header (eyebrow + title + optional back chevron / trailing / disc)

/// The echo TopBar recipe. `✦ eyebrow` on the left, an optional right-side
/// caption (the SF-Mono load id, or a live "PINGING · 14s" pill), a 28pt
/// title, and an optional monospace subtitle. `showBack` renders the back
/// chevron the M-05 detail screens carry; `discInitials` renders the DU
/// founder disc the M-04 echoes carry instead.
struct ShipperEchoHeader: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let eyebrow: String
    var trailing: String? = nil
    var trailingTone: TrailingTone = .tertiary
    let title: String
    var subtitle: String? = nil
    var showBack: Bool = true
    var discInitials: String? = nil

    enum TrailingTone { case tertiary, live, brand }

    private var trailingColor: Color {
        switch trailingTone {
        case .tertiary: return palette.textTertiary
        case .live:     return Brand.success
        case .brand:    return Brand.blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(eyebrow)
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: Space.s2)
                if let trailing {
                    Text(trailing)
                        .font(EType.mono(.micro))
                        .foregroundStyle(trailingColor)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                if showBack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if let discInitials {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                        Circle()
                            .fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                                 center: .init(x: 0.35, y: 0.30),
                                                 startRadius: 0, endRadius: 20))
                            .frame(width: 30, height: 30)
                            .blendMode(.plusLighter)
                        Text(discInitials)
                            .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
                }
            }

            if let subtitle {
                Text(subtitle)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            IridescentHairline()
                .padding(.top, 2)
        }
    }
}

// MARK: - Snapshot state view (the echo scaffold each screen wraps its body in)

/// Owns one `ShipperLifecycleSnapshotStore` and folds its RemoteState into
/// loading / empty / error / loaded, handing the live snapshot to the body
/// closure. Mirrors the LifecycleScaffold contract but WITHOUT its fixed
/// loadNumber header + ShipperLoadCycleView, so each echo screen paints its
/// own faithful header + ribbon.
struct ShipperEchoSnapshotView<Content: View>: View {
    @Environment(\.palette) private var palette
    let loadId: String
    let eyebrow: String
    @ViewBuilder let content: (ShipperAPI.LifecycleSnapshot) -> Content

    @StateObject private var store = ShipperLifecycleSnapshotStore()

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                loadingHeader
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.s6)
            case .loaded(let optional):
                if let live = optional {
                    content(live)
                } else {
                    emptyState
                }
            case .empty:
                emptyState
            case .error(let err):
                errorCard(err)
            }
        }
        .task {
            store.loadId = loadId
            await store.refresh()
        }
        .eusoRefreshable { await store.refresh() }
    }

    private var loadingHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Loading…").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("Pulling the latest from the load record.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var emptyState: some View {
        EusoEmptyState(
            systemImage: "shippingbox",
            title: "Load not found",
            subtitle: "This load is no longer in the system. Pull to refresh or pick another from Loads."
        )
    }

    private func errorCard(_ err: Error) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.danger)
            }
            Text(err.eusoUserCopy).font(EType.caption).foregroundStyle(palette.textSecondary)
            Button { Task { await store.refresh() } } label: {
                Text("Retry").font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Echo primitives

/// Small labelled section eyebrow used above the echo body cards.
struct ShipperEchoSectionLabel: View {
    @Environment(\.palette) private var palette
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
    }
}

/// A carrier / catalyst party row — monogram disc + name + authority mono
/// line + optional right status pill. Used by the pickup / transit /
/// delivery / paperwork echoes for the assigned-carrier block.
struct ShipperEchoPartyRow: View {
    @Environment(\.palette) private var palette
    let monogram: String
    let title: String
    let authority: String
    var detail: String? = nil
    var pill: (text: String, kind: StatusPill.Kind)? = nil
    var accent: Color = Brand.escort

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text(monogram)
                        .font(.system(size: 13, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(authority)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                if let pill {
                    StatusPill(text: pill.text, kind: pill.kind)
                }
            }
            if let detail {
                Text(detail)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

/// A document chip (BOL / Rate-con / POD / Insurance) with an icon, title,
/// and a state caption. Tone drives the state color.
struct ShipperEchoDocChip: View {
    @Environment(\.palette) private var palette
    enum Tone { case done, pending, verified, feature }
    let icon: String
    let title: String
    let state: String
    var tone: Tone = .pending

    private var stateColor: Color {
        switch tone {
        case .done, .verified: return Brand.success
        case .pending:         return palette.textTertiary
        case .feature:         return Brand.blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone == .verified ? AnyShapeStyle(Brand.success) : AnyShapeStyle(LinearGradient.diagonal))
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text(state)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(stateColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tone == .feature ? AnyShapeStyle(LinearGradient.primary.opacity(0.55)) : AnyShapeStyle(palette.borderFaint), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

/// A vertical labelled numeric cell — the atom of the trip-pulse strip and
/// the settlement quartet. `gradient` paints the value in the brand ramp.
struct ShipperEchoStatCell: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    var sub: String? = nil
    var gradient: Bool = false
    var valueColor: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                if gradient {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(valueColor ?? palette.textPrimary)
                }
            }
            .font(.system(size: 20, weight: .bold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
            if let sub {
                Text(sub)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A blue-tinted rationale card (the "RATIONALE · DIEGO USORO" block on the
/// bid + award echoes). A small caps label and one-or-more plain lines.
struct ShipperEchoRationaleCard: View {
    @Environment(\.palette) private var palette
    let label: String
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.blue)
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                Text(line)
                    .font(.system(size: 11, weight: idx == 0 ? .semibold : .regular))
                    .foregroundStyle(idx == 0 ? palette.textPrimary : palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.blue.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.blue.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

/// A single mono label → value roster row (the paperwork / closed ledgers).
struct ShipperEchoRosterRow: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    var accent: Bool = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 8.5, weight: .heavy, design: .monospaced)).tracking(0.3)
                .foregroundStyle(accent ? Brand.blue : palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Shared CTA pair

/// The canonical echo CTA pair — a wide primary + a narrower secondary,
/// matching the SVG's 244/148 split. Actions default to no-op so a screen
/// can wire only the taps it truly has an endpoint for.
struct ShipperEchoCTAPair: View {
    @Environment(\.palette) private var palette
    let primaryTitle: String
    var primaryLoading: Bool = false
    let primaryAction: () -> Void
    let secondaryTitle: String
    var secondaryAction: () -> Void = {}

    var body: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: primaryTitle, action: primaryAction, isLoading: primaryLoading)
                .frame(maxWidth: .infinity)
            Button(action: secondaryAction) {
                Text(secondaryTitle)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 148, minHeight: 52)
                    .frame(maxWidth: .infinity)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 172)
        }
    }
}

/// The M-04 echo action ribbon — one wide primary + two equal secondaries,
/// matching the paperwork / closed SVGs' three-button footer.
struct ShipperEchoTripleCTA: View {
    @Environment(\.palette) private var palette
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryAction: () -> Void
    let tertiaryTitle: String
    let tertiaryAction: () -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.system(size: 14, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            secondary(secondaryTitle, action: secondaryAction, strong: true)
            secondary(tertiaryTitle, action: tertiaryAction, strong: false)
        }
    }

    private func secondary(_ title: String, action: @escaping () -> Void, strong: Bool) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(strong ? palette.textPrimary : palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 92)
    }
}

/// A three-cell settlement status strip (POD / INVOICE / SETTLE) — the
/// shipper-vantage at-a-glance the M-04 echoes lead with. No HOS/DVIR
/// internals; every value is real-or-em-dash.
struct ShipperEchoSettlementStrip: View {
    @Environment(\.palette) private var palette
    struct Cell { let label: String; let value: String; let sub: String }
    let cells: [Cell]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { idx, c in
                VStack(spacing: 3) {
                    Text(c.label).font(.system(size: 8, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                    Text(c.value).font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.magenta.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(c.sub).font(.system(size: 8, weight: .medium)).foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                if idx < cells.count - 1 {
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 30)
                }
            }
        }
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Helpers

/// Two-letter monogram from a company / person name; falls back to the
/// first two characters, else a neutral dash.
func echoMonogram(_ name: String?) -> String {
    guard let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return "—" }
    let parts = n.split(separator: " ")
    if parts.count >= 2 {
        return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
    }
    return String(n.prefix(2)).uppercased()
}

/// "USDOT … · MC-…" authority line from the snapshot carrier — only the
/// real parts present, honest fallback when authority is absent.
func echoAuthorityLine(dot: String?, mc: String?, place: String? = nil) -> String {
    var parts: [String] = []
    if let d = dot, !d.isEmpty { parts.append("USDOT \(d)") }
    if let m = mc, !m.isEmpty { parts.append("MC-\(m)") }
    if let p = place, !p.isEmpty { parts.append(p) }
    return parts.isEmpty ? "Authority pending" : parts.joined(separator: " · ")
}

/// Age of the last ping as a compact relative string ("14s" / "3m" / "1h").
/// Honest em-dash when there is no geofence timestamp yet.
func echoPingAge(_ iso: String?) -> String {
    guard let iso, !iso.isEmpty else { return "—" }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var d = f.date(from: iso)
    if d == nil { f.formatOptions = [.withInternetDateTime]; d = f.date(from: iso) }
    guard let date = d else { return "—" }
    let secs = max(0, -date.timeIntervalSinceNow)
    if secs < 90 { return "\(Int(secs))s" }
    let m = Int(secs / 60)
    if m < 90 { return "\(m)m" }
    return "\(m / 60)h"
}

/// Lane label "St. Louis → Louisville" style from the snapshot cities.
func echoLaneCities(_ snap: ShipperAPI.LifecycleSnapshot) -> String {
    let from = snap.pickup?.city ?? "—"
    let to = snap.delivery?.city ?? "—"
    return "\(from) → \(to)"
}

/// Route to a real registered shipper surface via the canonical nav-swap
/// channel (`ContentView` resolves the `screenId` against `shipperScreens`).
/// Same mechanism 260_PostedAwaitingBids uses for Edit / Cancel routing —
/// so every echo CTA lands on a real screen, never a dead tap.
func shipperEchoNavSwap(_ screenId: String, loadId: String? = nil, mode: String? = nil) {
    var info: [String: Any] = ["screenId": screenId]
    if let loadId { info["loadId"] = loadId }
    if let mode { info["mode"] = mode }
    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: info)
}

/// Per-mile rate from a total rate + distance, honest em-dash when either
/// is missing or the distance is zero.
func echoRatePerMile(rate: Double?, distance: Double?) -> String {
    guard let r = rate, r > 0, let d = distance, d > 0 else { return "—" }
    return String(format: "$%.2f/mi", r / d)
}
