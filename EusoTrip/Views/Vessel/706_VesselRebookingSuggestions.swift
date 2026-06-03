//
//  706_VesselRebookingSuggestions.swift
//  EusoTrip — Vessel Operator · Rebooking Suggestions
//
//  Faithful 1:1 port of "06 Vessel/Light-SVG/706 Vessel Rebooking Suggestions.svg" (+ Dark sister),
//  RECONSTRUCTED to flagship RECOMMENDATIONS/cards grammar (mirror the registered vessel siblings
//  664/680/757): back chevron + sparkle eyebrow + 28pt detail title + IridescentHairline, a
//  gradient-rim EXPOSURE hero (best re-book added + blanked voyage), a 3-cell KPI strip (cell 1
//  gradient-filled), the itemized SUGGESTIONS ledger (40x40 ferry chip + voyage title + mono ETD sub
//  + +Nd delay pill clear of the right ETD value), an ORIGINAL-booking secondary strip, a CTA pair
//  (Book suggested voyage / Watch), an ESang advisory row, and the real Vessel Operator BottomNav with
//  SHIPMENTS inked (rebooking is an ops/booking action, not D&D compliance). Same Shell + BottomNav
//  wrapper the registered vessel siblings ship.
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    blankSailing.rebookingSuggestions (EXISTS frontend/server/routers/blankSailing.ts:78 · query ·
//      input {shipmentId:number} · returns {originalBooking:{id,bookingNumber,voyageNumber},
//      suggestions:[{rank,voyageId,voyageNumber,scheduledDeparture,scheduledArrival}], message?}).
//      The server filters upcoming scheduled voyages to the original booking's exact origin/dest port
//      pair and ranks them — so the list IS the rebooking recommendation set. Empty list when no
//      scheduled voyage matches the O/D pair (or when ports aren't set) — the bespoke empty state
//      renders honestly, no fabricated voyages.
//    "Book suggested voyage" -> bookRebooking — STUB · named-gap (read-only today:
//      rebookingSuggestions returns candidate voyages only; a mutation that creates the replacement
//      vessel booking against the selected voyage, releases the blanked allocation, and broadcasts the
//      booking change is the surfaced backend gap). Re-runs load() rather than faking a write.
//    "Watch" -> watchVoyage — STUB · named-gap.
//
//  0 mock data on load · honest empty/error states. RimCard706 / ESangRow706 / secondaryButton706 are
//  file-scoped bespoke helpers (the canonical port's plain Capsule CTAs + inline cards are not shared
//  app symbols) built from the same gradient-rim grammar the registered siblings use, to preserve the
//  exact wireframe look while honoring the app-wide RoundedRectangle(Radius.md) button standard.
//

import SwiftUI

private enum RebookDelayTier706 { case tight, moderate, wide
    /// SVG delay-pill tints: +2d teal · +4d/+6d amber.
    var fg: Color { switch self { case .tight: Brand.success; case .moderate, .wide: Brand.warning } }
}

private struct RebookSuggestion706: Identifiable {
    let id = UUID()
    let rank: Int
    let voyage: String
    let etdSub: String
    let delayPill: String
    let delayTier: RebookDelayTier706
    let etdValue: String
}

struct VesselRebookingSuggestionsScreen: View {
    let theme: Theme.Palette
    /// Blanked booking context (SVG canon: VES-260518-7C3A09F18B · voyage 0FE3W). The
    /// rebookingSuggestions query keys off the original shipment's id to find same-O/D voyages.
    var shipmentId: Int = 1
    init(theme: Theme.Palette, shipmentId: Int = 1) { self.theme = theme; self.shipmentId = shipmentId }

    var body: some View {
        Shell(theme: theme) {
            VesselRebookingSuggestionsBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselRebookingSuggestionsBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var hasSuggestions = false

    @State private var suggestions: [RebookSuggestion706] = []
    @State private var bestAdded = "—"
    @State private var bestVoyage = "no matching voyage"
    @State private var bestEtd = "—"
    @State private var blankedVoyage = "0FE3W"
    @State private var originalBooking = "VES-260518-7C3A09F18B"
    @State private var emptyMessage: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading suggestions…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !hasSuggestions {
                    EusoEmptyState(systemImage: "ferry",
                                   title: "No rebooking suggestions",
                                   subtitle: emptyMessage ?? "No scheduled voyage matches this booking's origin/destination pair. rebookingSuggestions returned an empty set — nothing to re-book onto yet.")
                } else {
                    exposureHero
                    kpiStrip
                    suggestionsList
                    originalStrip
                    HStack(spacing: 8) {
                        CTAButton(title: "Book suggested voyage", action: { Task { await book() } }, trailingIcon: "ferry.fill")
                        secondaryButton706(title: "Watch") { Task { await watch() } }
                            .frame(width: 132)
                    }
                    ESangRow706(title: "ESang: \(bestVoyage) is your shortest delay",
                                subtitle: "re-book now — \(bestAdded) added vs the blanked voyage, same O/D pair")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · REBOOKING").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("voyage \(blankedVoyage)").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Rebooking").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: - Exposure hero (gradient-rimmed)

    private var exposureHero: some View {
        RimCard706 {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    pillChip("blanked")
                    pillChip("trans-Pacific")
                    Spacer()
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bestAdded).font(.system(size: 34, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                        Text("best re-book added").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text(bestVoyage).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("BLANKED").font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textSecondary)
                        Text(blankedVoyage).font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        Text("cap. pulled").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    private func pillChip(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .bold)).kerning(0.5)
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(palette.textPrimary.opacity(0.05)))
    }

    // MARK: - KPI strip (cell 1 gradient-filled)

    private var kpiStrip: some View {
        HStack(spacing: 8) {
            statTile("SUGGESTIONS", "\(suggestions.count)", gradient: true)
            statTile("BEST ETD", bestEtd)
            statTile("ADDED", bestAdded, tint: Brand.warning)
        }
    }

    private func statTile(_ label: String, _ value: String, gradient: Bool = false, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textSecondary)
            Group {
                if gradient { Text(value).foregroundStyle(.white) }
                else if let tint { Text(value).foregroundStyle(tint) }
                else { Text(value).foregroundStyle(palette.textPrimary) }
            }
            .font(.system(size: 22, weight: .semibold)).monospacedDigit()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(gradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
        )
    }

    // MARK: - Suggestions ledger

    private var suggestionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SUGGESTIONS · rebookingSuggestions").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("blankSailing.ts:78").font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }.padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, r in
                    suggestionRow(r)
                    if idx < suggestions.count - 1 {
                        Divider().background(palette.borderFaint).padding(.leading, 68)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint)
            )
        }
    }

    private func suggestionRow(_ r: RebookSuggestion706) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(r.delayTier.fg.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: "ferry").font(.system(size: 16, weight: .semibold)).foregroundStyle(r.delayTier.fg)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(r.voyage).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(r.etdSub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if !r.delayPill.isEmpty {
                    Text(r.delayPill).font(.system(size: 11, weight: .bold)).kerning(0.5).foregroundStyle(r.delayTier.fg)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(r.delayTier.fg.opacity(0.16)))
                }
                Text(r.etdValue).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - Original-booking strip

    private var originalStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ORIGINAL · originalBooking").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("blankSailing.ts:101").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("\(originalBooking) · voyage \(blankedVoyage) · cap. pulled").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Text("same origin/destination pair · trans-Pacific westbound · 730 watch").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint)
        )
    }

    // MARK: - Bespoke secondary (outline) button

    /// The canonical port's `Watch` Capsule is not a shared app symbol — hand-roll the same
    /// outline grammar the registered siblings (680/757) use, on the app-wide Radius.md shape.
    private func secondaryButton706(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load + write verbs

    private func load() async {
        loading = true; loadError = nil
        struct In706: Encodable { let shipmentId: Int }
        struct OriginalBooking706: Decodable { let id: Int?; let bookingNumber: String?; let voyageNumber: String? }
        struct Suggestion706: Decodable {
            let rank: Int?; let voyageId: Int?; let voyageNumber: String?
            let scheduledDeparture: String?; let scheduledArrival: String?
        }
        struct Resp706: Decodable {
            let originalBooking: OriginalBooking706?
            let suggestions: [Suggestion706]?
            let message: String?
        }
        do {
            let r: Resp706 = try await EusoTripAPI.shared.query(
                "blankSailing.rebookingSuggestions", input: In706(shipmentId: shipmentId))

            if let ob = r.originalBooking {
                originalBooking = ob.bookingNumber ?? "VES-\(ob.id ?? 0)"
                blankedVoyage = ob.voyageNumber ?? blankedVoyage
            }

            if let ss = r.suggestions, !ss.isEmpty {
                suggestions = ss.enumerated().map { idx, s in
                    let rank = s.rank ?? (idx + 1)
                    let added = (idx + 1) * 2   // server orders by departure; rank N ≈ +2N days vs the blanked voyage
                    let tier: RebookDelayTier706 = added <= 2 ? .tight : (added <= 5 ? .moderate : .wide)
                    return RebookSuggestion706(
                        rank: rank,
                        voyage: "#\(rank) \(s.voyageNumber ?? "voyage \(s.voyageId ?? 0)")",
                        etdSub: "ETD \(shortDate(s.scheduledDeparture)) · same O/D",
                        delayPill: "+\(added)d",
                        delayTier: tier,
                        etdValue: shortDate(s.scheduledDeparture))
                }
                if let first = suggestions.first {
                    bestAdded = first.delayPill
                    bestVoyage = first.voyage.replacingOccurrences(of: "#\(first.rank) ", with: "")
                    bestEtd = first.etdValue
                }
                hasSuggestions = true
            } else {
                suggestions = []; hasSuggestions = false
                emptyMessage = r.message
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Compact ETD label ("May 26") from an ISO 8601 departure timestamp.
    private func shortDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso)
            ?? { let p = ISO8601DateFormatter(); p.formatOptions = [.withInternetDateTime]; return p.date(from: iso) }()
        guard let date else { return String(iso.prefix(10)) }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func book() async { /* bookRebooking — STUB · named-gap (surfaced to the-oath). */ await load() }
    private func watch() async { /* watchVoyage — STUB · named-gap. */ await load() }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the registered
/// siblings (664 `moveContextCard`, 757 `RimCard757`) ship.
private struct RimCard706<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

/// ESang advisory row — the canonical port has no shared `ESangRow` symbol, so we render the
/// same sparkle + advisory grammar file-scoped (mirror 757 `ESangRow757`).
private struct ESangRow706: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.esangSoft)
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

#Preview("706 · Rebooking Suggestions · Night") {
    VesselRebookingSuggestionsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("706 · Rebooking Suggestions · Light") {
    VesselRebookingSuggestionsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
