//
//  646_RailRebookingOptions.swift
//  EusoTrip — Rail Engineer · Rebooking Options (disruption reroute decision cards).
//
//  ARCHETYPE = DECISION OPTION CARDS. A dangerWash disruption attention hero,
//  then full-width selectable reroute option cards — each with route, mode pill,
//  ETA-delta + cost-delta chips, a tradeoff line and a select chevron; the
//  recommended option gets a gradient cardRim + RECOMMENDED ribbon. Choose-one
//  decision surface, not a ledger.
//
//  Web parity: /rail/shipments/[id]/rebook (RailRebookingOptions.tsx).
//  Wiring:
//    • affected shipment + disruption → intermodal.getIntermodalTracking
//        (EXISTS · intermodal.ts:269)
//    • generated alternatives        → intermodal.rebookingOptions
//        (STUB — proposed, no endpoint yet). Tried best-effort; on failure
//        the option list renders a real empty state + // PORT-GAP. We never
//        fabricate the option cards from the wireframe sample copy.
//    • Commit reroute CTA            → intermodal.advanceSegment
//        (EXISTS · intermodal.ts:184) — writes intermodal_segment row +
//        blockchainAuditTrail row, broadcasts RAIL_INTERMODAL/ROUTING_CHANGED.
//  RBAC: protectedProcedure (rail carrier scope). transportMode=rail · US · USD · hrs.
//

import SwiftUI

struct RailRebookingOptionsScreen: View {
    let theme: Theme.Palette
    /// Affected intermodal shipment under disruption. Defaults to 0 so the
    /// screen instantiates with only `theme` required; real call-sites pass
    /// the shipment row id from the shipments surface.
    var shipmentId: Int = 0
    /// Display reference shown in the eyebrow/meta block.
    var shipmentRef: String = "RAIL-260522-3C7B0"

    var body: some View {
        Shell(theme: theme) {
            RailRebookingOptionsBody(shipmentId: shipmentId, shipmentRef: shipmentRef)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// Live disruption + affected-leg context for the hero. Sourced from
/// intermodal.getIntermodalTracking (EXISTS). Every field optional so a
/// thin server payload still renders the hero shell.
private struct RebookDisruption646: Decodable {
    let disruptionTitle: String?     // "Service disruption · BNSF Transcon"
    let carrier: String?             // "BNSF Intermodal"
    let detail: String?              // "Cajon Sub closed · est 26h · 1 car of yours blocked at Barstow"
    let lane: String?                // "CHI → LGB ICTF"
    let sinceLabel: String?          // "since 09:14 CDT"
    let status: String?              // "DISRUPTED"
    let currentSegmentId: Int?
    let nextSegmentId: Int?
}

/// A generated reroute alternative. Proposed shape:
///   { option, mode, etaDeltaHrs, costDeltaUsd, recommended }
/// plus optional route/tradeoff descriptors and the segment cursor the
/// commit needs. From intermodal.rebookingOptions (STUB — no endpoint yet).
private struct RebookOption646: Decodable, Identifiable {
    let option: String?              // "Reroute via UP Sunset"
    let mode: String?                // "all-rail · KCK → Tucson → LGB · 1 waybill"
    let etaDeltaHrs: Double?         // +14 → "ETA +14h"
    let costDeltaUsd: Double?        // 640  → "+$640"
    let recommended: Bool?
    let tradeoff: String?            // "keeps single carrier · lowest add"
    let fromSegmentId: Int?
    let toSegmentId: Int?

    // Synthesize a stable identity — the endpoint is a STUB, so it may not
    // ship an id. Fall back to the option label.
    let serverId: String?
    var id: String { serverId ?? option ?? UUID().uuidString }
}

// MARK: - Body

private struct RailRebookingOptionsBody: View {
    let shipmentId: Int
    let shipmentRef: String

    @Environment(\.palette) private var palette

    @State private var disruption: RebookDisruption646? = nil
    @State private var options: [RebookOption646] = []
    @State private var selectedId: String? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// True when the rebookingOptions endpoint is missing/empty (STUB).
    /// Drives the real empty state in place of fabricated option cards.
    @State private var optionsUnavailable = false
    @State private var committing = false
    @State private var commitAck: String? = nil
    @State private var commitError: String? = nil

    private var selectedOption: RebookOption646? {
        options.first { $0.id == selectedId }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                IridescentHairline()

                if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    heroDisruption
                    chooseHeader
                    optionsList
                    contextBand
                    commitFeedback
                    ctaRow
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow (✦ RAIL ENGINEER · REROUTE  ·  N OPTIONS)

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("RAIL ENGINEER · REROUTE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text("\(options.count) OPTIONS")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, 4)
    }

    // MARK: - Title block (Rebooking options · DISRUPTED · ref)

    private var titleBlock: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Rebooking options")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text((disruption?.status ?? "DISRUPTED").uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(shipmentRef)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - HERO · disruption attention card (dangerWash)

    private var heroDisruption: some View {
        let title  = disruption?.disruptionTitle ?? disruptionTitleFallback
        let detail = disruption?.detail
        let lane   = disruption?.lane
        let since  = disruption?.sinceLabel

        return VStack(alignment: .leading, spacing: 0) {
            // dangerWash header band — red→orange @ 0.16
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFF7A66))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Brand.danger.opacity(0.16), Brand.warning.opacity(0.16)],
                    startPoint: .leading, endPoint: .trailing
                )
            )

            VStack(alignment: .leading, spacing: 6) {
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .firstTextBaseline) {
                    if let lane {
                        Text(lane)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer()
                    if let since {
                        Text(since)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var disruptionTitleFallback: String { "Service disruption" }

    // MARK: - CHOOSE A REROUTE header

    private var chooseHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CHOOSE A REROUTE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("rebookingOptions")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Option list

    @ViewBuilder
    private var optionsList: some View {
        if optionsUnavailable || options.isEmpty {
            // PORT-GAP: intermodal.rebookingOptions is a proposed endpoint
            // (STUB · rail-rebooking-options). No live alternatives exist
            // yet — render a real empty state instead of fabricating the
            // three wireframe sample cards (UP Sunset / Hold / Truck dray).
            EusoEmptyState(
                systemImage: "arrow.triangle.branch",
                title: "No reroute options yet",
                subtitle: "Generated alternatives appear here once the rebooking engine is wired (intermodal.rebookingOptions)."
            )
        } else {
            VStack(spacing: Space.s3) {
                ForEach(options) { opt in
                    optionCard(opt)
                }
            }
        }
    }

    private func optionCard(_ opt: RebookOption646) -> some View {
        let isRecommended = opt.recommended ?? false
        let isSelected    = opt.id == selectedId

        let inner = VStack(alignment: .leading, spacing: 0) {
            // Title row + RECOMMENDED ribbon
            HStack(alignment: .center, spacing: 8) {
                Text(opt.option ?? "Reroute option")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                if isRecommended {
                    Text("RECOMMENDED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                }
            }
            // Route / mode mono line
            if let mode = opt.mode {
                Text(mode)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Delta chips + tradeoff + chevron
            HStack(alignment: .center, spacing: 8) {
                if let eta = opt.etaDeltaHrs {
                    deltaChip(text: etaDeltaLabel(eta), color: etaDeltaColor(eta))
                }
                if let cost = opt.costDeltaUsd {
                    deltaChip(text: costDeltaLabel(cost), color: costDeltaColor(cost))
                }
                VStack(alignment: .trailing, spacing: 0) {
                    if let tradeoff = opt.tradeoff {
                        Text(tradeoff)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(palette.textTertiary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)

        return Button {
            selectedId = isSelected ? nil : opt.id
        } label: {
            inner
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(
                            (isRecommended || isSelected)
                                ? AnyShapeStyle(LinearGradient.diagonal)
                                : AnyShapeStyle(palette.borderFaint),
                            lineWidth: (isRecommended || isSelected) ? 1.5 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func deltaChip(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    // ETA delta: positive (later) reads warning→danger; the SVG colors
    // +14h warm-amber, +2d danger-red, +6h success-green (sooner-ish).
    private func etaDeltaLabel(_ hrs: Double) -> String {
        if abs(hrs) >= 48 {
            let days = Int((abs(hrs) / 24).rounded())
            return "ETA \(hrs >= 0 ? "+" : "-")\(days)d"
        }
        return "ETA \(hrs >= 0 ? "+" : "")\(Int(hrs))h"
    }
    private func etaDeltaColor(_ hrs: Double) -> Color {
        if hrs <= 6 { return Brand.success }
        if hrs >= 48 { return Color(hex: 0xFF7A66) }
        return Brand.warning
    }

    private func costDeltaLabel(_ usd: Double) -> String {
        let n = Int(usd.rounded())
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let body = f.string(from: NSNumber(value: abs(n))) ?? "\(abs(n))"
        if n == 0 { return "+$0" }
        return "\(n >= 0 ? "+" : "-")$\(body)"
    }
    // Lower add = greener; a large add reads danger.
    private func costDeltaColor(_ usd: Double) -> Color {
        let n = Int(usd.rounded())
        if n == 0 { return palette.textPrimary }
        if abs(n) >= 1500 { return Color(hex: 0xFF7A66) }
        return Brand.success
    }

    // MARK: - Context band (COMMIT · advanceSegment)

    private var contextBand: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COMMIT · advanceSegment")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("Selecting writes the new segment + notifies the consignee portal")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Commit feedback

    @ViewBuilder
    private var commitFeedback: some View {
        if let ack = commitAck {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.success)
                Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let err = commitError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - CTA row (Commit reroute · Keep plan)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Commit reroute",
                action: { Task { await commit() } },
                isLoading: committing
            )
            .frame(maxWidth: .infinity)
            .opacity(selectedOption == nil ? 0.6 : 1.0)
            .allowsHitTesting(selectedOption != nil && !committing)

            Button {
                selectedId = nil
            } label: {
                Text("Keep plan")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 148, minHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Skeleton

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        commitAck = nil; commitError = nil

        struct TrackIn: Encodable { let intermodalShipmentId: Int }
        struct OptionsIn: Encodable { let shipmentId: String }

        // 1) Disruption / affected-leg context (EXISTS · best-effort).
        do {
            let d: RebookDisruption646 = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalTracking",
                input: TrackIn(intermodalShipmentId: shipmentId))
            self.disruption = d
        } catch {
            // Hero context is enrichment — surface a hard error only if the
            // whole screen has nothing to show (handled below).
            self.disruption = nil
        }

        // 2) Generated alternatives (STUB — proposed endpoint).
        do {
            let opts: [RebookOption646] = try await EusoTripAPI.shared.query(
                "intermodal.rebookingOptions",
                input: OptionsIn(shipmentId: shipmentRef))
            self.options = opts
            self.optionsUnavailable = opts.isEmpty
            if let rec = opts.first(where: { $0.recommended ?? false }) {
                self.selectedId = rec.id
            }
        } catch {
            // PORT-GAP: endpoint not deployed yet — show real empty state,
            // never the wireframe sample cards.
            self.options = []
            self.optionsUnavailable = true
        }

        // If BOTH context and options failed AND there's truly nothing on
        // screen, surface the disruption fetch error so the engineer isn't
        // staring at a blank surface.
        if disruption == nil && options.isEmpty {
            // Keep loadError nil so the dangerWash hero + empty state still
            // render their copy; the empty state already explains the gap.
        }

        loading = false
    }

    // MARK: - Commit reroute → intermodal.advanceSegment (EXISTS)

    private func commit() async {
        guard let opt = selectedOption else { return }
        committing = true; commitAck = nil; commitError = nil

        struct AdvIn: Encodable {
            let intermodalShipmentId: Int
            let fromSegmentId: Int
            let toSegmentId: Int
        }
        struct Empty: Decodable {}

        let from = opt.fromSegmentId ?? disruption?.currentSegmentId ?? 0
        let to   = opt.toSegmentId   ?? disruption?.nextSegmentId    ?? 0

        do {
            let _: Empty = try await EusoTripAPI.shared.mutation(
                "intermodal.advanceSegment",
                input: AdvIn(intermodalShipmentId: shipmentId,
                             fromSegmentId: from, toSegmentId: to))
            commitAck = "Reroute committed · \(opt.option ?? "new segment") · consignee notified"
            await reload()
        } catch {
            commitError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        committing = false
    }
}

#Preview("646 · Rail Rebooking Options · Night") {
    RailRebookingOptionsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("646 · Rail Rebooking Options · Light") {
    RailRebookingOptionsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
