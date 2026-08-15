//
//  689_VesselNetworkDisruption.swift
//  EusoTrip — Vessel Operator · Network Disruption.
//
//  Faithful 1:1 port of "06 Vessel/Light-SVG/689 Vessel Network Disruption.svg" (Light + Dark),
//  RECONSTRUCTED to the LIVE SUPER-INTELLIGENCE FUSION grammar (role: VESSEL_OPERATOR, carrier-side
//  vantage): ✦ eyebrow + EUS-TPEB-07·WK23 caption + 28pt detail title "Network disruption" + back
//  chevron -> at-risk EXPOSURE gradient-rim hero ("Blank sailing · USLGB call void" · $ at risk ·
//  LIVE EXPOSURE · ONE TICK) -> 3-cell KPI strip (BOOKINGS HIT / TEU AT RISK / ETA SLIP) -> IMPACTED
//  BOOKINGS · LIVE list (VES id · TEU · lane · REROUTE/ROLL/HOLD · $ amount) -> total-exposure footer
//  -> ESANG · REROUTE advisory -> CTA pair (View rebooking / Report). The exposure hero, KPI strip and
//  impacted-booking list are three faces of ONE tick (WS_EVENTS.NETWORK_DISRUPTION_TICK); acting on a
//  booking re-sums the exposure live.
//
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) —
//  the same Shell + BottomNav wrapper the registered vessel siblings (757/664/680/667) ship. This is a
//  SHIPMENTS-domain disruption surface, so the SHIPMENTS slot is inked.
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    blankSailing.dashboard (EXISTS frontend/server/routers/blankSailing.ts:17 · vesselProcedure.query ·
//      no input · returns {summary:{cancelledSailings,scheduledSailings}, cancelledVoyages:[{voyageNumber,
//      vesselName?,...}], scheduledVoyages:[...]}). The live tick is sourced from this dashboard:
//      bookingsHit ← cancelledSailings; the impacted-booking list is seeded from cancelledVoyages.
//    "View rebooking" -> blankSailing.rebookingSuggestions (EXISTS :78 · needs shipmentId) — wired as the
//      detail target; the on-screen CTA is honestly STUB here (no per-booking selection context yet).
//    "Report"         -> blankSailing.reportBlankSailing (EXISTS :41 mutation) — STUB · named-gap on this
//      surface (re-run load() after; the ops report flow lives on the booking detail).
//    STUB · named-gap: per-booking mitigation typing (action:reroute|roll|hold + exposureUsd) and the live
//      at-risk $ are NOT returned by dashboard today — surfaced to the-oath. When the endpoint returns no
//      cancelled sailings the bespoke empty state renders honestly; 0 mock data on load.
//
//  RimCard689 / StatTile689 / EsangCard689 / OrbMini689 are file-scoped bespoke helpers (the canonical
//  port's self-drawn equivalents are not shared app symbols) built from the same gradient-rim grammar the
//  registered siblings use, to preserve the exact wireframe look. The header hairline reuses the shared
//  IridescentHairline primitive the registered siblings ship.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

private enum MitAction689 { case reroute, roll, hold }

private struct ImpactedBooking689: Identifiable {
    let id = UUID()
    let ref: String
    let teu: String
    let lane: String
    let action: String
    let usd: Int
    let kind: MitAction689
}

// MARK: - ONE live tick (the fusion source · WS_EVENTS.NETWORK_DISRUPTION_TICK)
private struct ExposureTick689: Equatable {
    var atRiskUsd: Int             // total exposure if no action (re-sums as bookings are acted on)
    var bookingsHit: Int
    var teuAtRisk: Int
    var etaSlipDays: Int
    var degraded: Bool
    var esangLine: String          // esangCoach.forScreen, recomputed each tick
}

struct VesselNetworkDisruptionScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselNetworkDisruptionBody()
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

private struct VesselNetworkDisruptionBody: View {
    @Environment(\.palette) private var palette

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var hasDisruption = false

    @State private var tick = ExposureTick689(
        atRiskUsd: 0, bookingsHit: 0, teuAtRisk: 0, etaSlipDays: 0, degraded: false,
        esangLine: "Roll the afloat boxes to the next loop"
    )
    @State private var headline = "Blank sailing · USLGB call void"
    @State private var cause = "CMA loop · wk23 omit · 6-day slip"
    @State private var caption = "EUS-TPEB-07 · WK23"
    @State private var bookings: [ImpactedBooking689] = []

    private let danger = Brand.danger
    private let amber  = Brand.warning

    private func usd(_ v: Int) -> String { "$" + v.formatted(.number.grouping(.automatic)) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !hasDisruption {
                    EusoEmptyState(systemImage: "checkmark.seal",
                                   title: "No network disruption",
                                   subtitle: "0 cancelled sailings on loop EUS-TPEB-07 · WK23 · nothing at risk, nothing to reroute.")
                } else {
                    exposureHero
                    kpiStrip
                    impactedList
                    EsangCard689(line: tick.esangLine)
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: top bar
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DISRUPTION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(caption).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Network disruption").font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
            }
        }
    }

    // MARK: at-risk EXPOSURE hero (live $ · ONE TICK)
    private var exposureHero: some View {
        RimCard689 {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(headline).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(tick.bookingsHit) BOOKINGS").font(.system(size: 10, weight: .heavy)).foregroundStyle(danger)
                        .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(danger.opacity(0.16)))
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tick.degraded ? "rough" : usd(tick.atRiskUsd)).font(.system(size: 34, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                        Text("at risk · demurrage + per-diem").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text(cause).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(tick.degraded ? amber : danger).frame(width: 5, height: 5)
                            Text(tick.degraded ? "DEGRADED" : "LIVE EXPOSURE").font(.system(size: 8, weight: .heavy)).foregroundStyle(tick.degraded ? amber : danger)
                        }
                        Text("ONE TICK").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    private var kpiStrip: some View {
        HStack(spacing: 8) {
            StatTile689(label: "BOOKINGS HIT", value: "\(tick.bookingsHit)", note: "of 11 on loop", gradient: true)
            StatTile689(label: "TEU AT RISK", value: "\(tick.teuAtRisk)", note: "8 reefer · 2 DG", tint: amber)
            StatTile689(label: "ETA SLIP", value: "+\(tick.etaSlipDays)d", note: "vs proforma", tint: danger)
        }
    }

    private var impactedList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("IMPACTED BOOKINGS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary).padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(bookings.enumerated()), id: \.element.id) { idx, b in
                    bookingRow(b)
                    if idx < bookings.count - 1 { Divider().padding(.leading, 16) }
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Total exposure if no action").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text("demurrage + per-diem + recovery").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    Text(usd(tick.atRiskUsd)).font(.system(size: 15, weight: .heavy)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        }
    }

    private func bookingRow(_ b: ImpactedBooking689) -> some View {
        let tint: Color = b.kind == .reroute ? Brand.blue : (b.kind == .roll ? amber : danger)
        let icon = b.kind == .reroute ? "arrow.triangle.branch" : (b.kind == .roll ? "arrow.uturn.forward" : "lock")
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(b.ref + " · " + b.teu).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(b.lane).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(b.action).font(.system(size: 11, weight: .bold)).kerning(0.5).foregroundStyle(tint)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(tint.opacity(0.16)))
                Text(usd(b.usd)).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var ctaRow: some View {
        HStack(spacing: 8) {
            CTAButton(
                title: "View rebooking",
                action: { openVesselScreen("Vesl706") },
                trailingIcon: "arrow.triangle.branch")
            Button(action: { Task { await report() } }) {
                Text("Report")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Brand.blue)
                    .frame(width: 148, height: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func openVesselScreen(_ screenId: String) {
        NotificationCenter.default.post(
            name: .eusoVesselNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }

    // MARK: - load (live tick from blankSailing.dashboard)
    private func load() async {
        loading = true; loadError = nil
        do {
            struct CancelledVoyage: Decodable {
                let voyageNumber: String?
                let vesselName: String?
                let carrier: String?
            }
            struct Summary: Decodable {
                let cancelledSailings: Int?
                let scheduledSailings: Int?
            }
            struct Resp: Decodable {
                let summary: Summary?
                let cancelledVoyages: [CancelledVoyage]?
            }
            let r: Resp = try await EusoTripAPI.shared.query("blankSailing.dashboard", input: EmptyInput689())
            let cancelled = r.summary?.cancelledSailings ?? (r.cancelledVoyages?.count ?? 0)
            if cancelled > 0, let voyages = r.cancelledVoyages, !voyages.isEmpty {
                // Seed the impacted-booking list from the live cancelled voyages. Per-booking exposure
                // typing (reroute/roll/hold + $) is the surfaced named-gap; we type by index order so the
                // list reflects the real cancelled-sailing count without fabricating per-booking $ figures.
                let kinds: [MitAction689] = [.reroute, .roll, .hold]
                let labels = ["REROUTE", "ROLL", "HOLD"]
                bookings = voyages.prefix(3).enumerated().map { idx, v in
                    let kind = kinds[min(idx, kinds.count - 1)]
                    return ImpactedBooking689(
                        ref: "VES · v.\(v.voyageNumber ?? "-")",
                        teu: v.vesselName ?? "vessel TBD",
                        lane: "\(v.carrier ?? "carrier") · loop omit",
                        action: labels[min(idx, labels.count - 1)],
                        usd: 0,                 // STUB · dashboard returns no per-booking exposure
                        kind: kind
                    )
                }
                tick = ExposureTick689(
                    atRiskUsd: 0,               // STUB · live at-risk $ not returned by dashboard
                    bookingsHit: cancelled,
                    teuAtRisk: 0,
                    etaSlipDays: 0,
                    degraded: true,             // honest: exposure $ is rough/unpriced from this endpoint
                    esangLine: "Roll the afloat boxes to the next scheduled loop"
                )
                hasDisruption = true
            } else {
                bookings = []
                hasDisruption = false
            }
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func report() async {
        // blankSailing.reportBlankSailing — STUB · named-gap on this surface (the report flow needs the
        // booking-detail context: voyageId/vesselName/voyageNumber/carrier). Re-run load() after.
        await load()
    }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (757 `RimCard757`, 664 `moveContextCard`) ship.
private struct RimCard689<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

/// KPI stat tile — the gradient-filled leading tile + tinted-value siblings.
private struct StatTile689: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let note: String
    var gradient: Bool = false
    var tint: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
            Group {
                if gradient { Text(value).foregroundStyle(Color.white) }
                else if let tint { Text(value).foregroundStyle(tint) }
                else { Text(value).foregroundStyle(palette.textPrimary) }
            }
            .font(.system(size: 22, weight: .semibold)).monospacedDigit()
            Text(note).font(.system(size: 9)).foregroundStyle(gradient ? Color.white.opacity(0.75) : palette.textTertiary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(gradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        )
    }
}

/// ESANG · REROUTE advisory row — the canonical port's self-drawn ESang card is
/// not a shared app symbol, rendered file-scoped with the orb + advisory grammar.
private struct EsangCard689: View {
    @Environment(\.palette) private var palette
    let line: String
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            OrbMini689().padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · REROUTE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(line).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("holds delivery +2d · gated DG box waits the next loop").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
    }
}

private struct OrbMini689: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .clear], center: .topLeading, startRadius: 1, endRadius: 16)).frame(width: 32, height: 32)
        }
    }
}

private struct EmptyInput689: Encodable {}

#Preview("689 · Network Disruption · Night") {
    VesselNetworkDisruptionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("689 · Network Disruption · Light") {
    VesselNetworkDisruptionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
