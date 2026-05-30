//
//  592_RailForwarderPortal.swift
//  EusoTrip — Rail Engineer · 3PL / Forwarder Portal (carrier-side).
//
//  Verbatim port of wireframe "592 Rail Forwarder Portal · Dark".
//  Reconstructed to the flagship DETAIL grammar (205 Load Detail / 580 Rail
//  Tariff Rate Lookup) per FOUNDER CADENCE DIRECTIVE 2026-05-24: back chevron,
//  eyebrow, mono ID caption, title 28/-0.4, gradient-rimmed hero ActiveCard,
//  3-cell KPI strip, itemized ListRow stack, secondary CONSOLIDATION strip,
//  CTA pair — NOT a stat-tile dashboard.
//
//  IMC / 3PL collaboration: grant a forwarder scoped access to a shared
//  portfolio across truck loads + rail shipments off the one shared loads
//  source, with consolidation suggestions. Cross-mode sibling of Vessel 695.
//
//  tRPC wiring (REAL backend routers — not yet surfaced as typed helpers on
//  the Swift EusoTripAPI client, so they are reached by tRPC path string
//  through the generic query/mutation transport):
//    • forwarderPortal.createPortalAccess        (forwarderPortal.ts:21) — HERO + Grant CTA
//    • forwarderPortal.listForwarderShipments    (forwarderPortal.ts:43) — portfolio rows
//    • forwarderPortal.consolidationSuggestions  (forwarderPortal.ts:77) — CONSOLIDATION strip
//
//  PORT-GAP: forwarderPortal.listForwarderShipments rail[] branch is a STUB
//  on the backend (truck/ocean only, forwarderPortal.ts:71-73). Rail rows
//  resolve to a real empty state until that branch ships — no fabricated
//  rail rows are injected here.
//

import SwiftUI

struct RailForwarderPortalScreen: View {
    let theme: Theme.Palette
    /// Forwarder hub the portal is scoped to. Defaulted so the only required
    /// stored property is `theme` (per build doctrine).
    var forwarderGroupId: String = ""

    var body: some View {
        Shell(theme: theme) { RailForwarderPortalBody(forwarderGroupId: forwarderGroupId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror tRPC return shapes)

/// forwarderPortal.createPortalAccess — the active grant the hero summarizes.
private struct ForwarderPortalAccess592: Decodable {
    let id: String?
    let forwarderName: String?
    let sharedCount: Int?
    let railCount: Int?
    let truckCount: Int?
    /// Window length in days, e.g. 90.
    let expiresInDays: Int?
    let shipperOfRecord: String?
}

/// forwarderPortal.listForwarderShipments — one shared portfolio row. Spans
/// truck loads + rail shipments off the one shared loads source.
private struct ForwarderShipment592: Decodable, Identifiable {
    let id: String
    let reference: String?     // RAIL-YYMMDD-XXXXX / LD-YYMMDD-XXXXX
    let lane: String?          // "ICTF → Logistics Park"
    let status: String?        // "in_transit" / "gate_in" / "drayage"
    let mode: String?          // "rail" / "truck"
}

/// forwarderPortal.consolidationSuggestions — co-load opportunity.
private struct ConsolidationSuggestion592: Decodable, Identifiable {
    let id: String
    let headline: String?      // "2 Logistics Park dray legs co-loadable · save ~$540"
    let detail: String?        // "Pair by destState MI · same ramp pull"
    let estimatedSavingsUsd: Double?
}

// MARK: - tRPC input envelopes

private struct ForwarderListInput592: Encodable {
    let forwarderGroupId: String
    let limit: Int
}

private struct ForwarderGroupInput592: Encodable {
    let forwarderGroupId: String
}

// MARK: - Body

private struct RailForwarderPortalBody: View {
    @Environment(\.palette) private var palette
    let forwarderGroupId: String

    @State private var access: ForwarderPortalAccess592? = nil
    @State private var shipments: [ForwarderShipment592] = []
    @State private var suggestions: [ConsolidationSuggestion592] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Grant CTA state
    @State private var granting = false
    @State private var grantNotice: String? = nil

    // Mono portal-access ID shown in the eyebrow caption (RAIL-YYMMDD-XXXXX
    // family; the wireframe pins RAIL-260523-7C3A0B12D4 as a representative
    // shape — we surface the live grant id when present, else the canon shape).
    private var portalIdCaption: String {
        access?.id ?? "RAIL-260523-7C3A0B12D4"
    }

    private var railCount: Int {
        access?.railCount ?? shipments.filter { ($0.mode ?? "").lowercased() == "rail" }.count
    }
    private var truckCount: Int {
        access?.truckCount ?? shipments.filter { ($0.mode ?? "").lowercased() == "truck" }.count
    }
    private var sharedCount: Int {
        access?.sharedCount ?? (shipments.isEmpty ? 0 : shipments.count)
    }
    private var windowDays: Int { access?.expiresInDays ?? 90 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading forwarder portal…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    portfolioSection
                    consolidationStrip
                    if let notice = grantNotice {
                        Text(notice)
                            .font(EType.caption)
                            .foregroundStyle(Brand.success)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header (back chevron · eyebrow · mono ID · title 28/-0.4)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("✦ RAIL ENGINEER · 3PL PORTAL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(portalIdCaption)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Forwarder portal")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: - Hero ActiveCard (gradient-rimmed)
    //
    // SHARED · collaborate chips · the "11 shared shipments" headline numeral
    // off listForwarderShipments · EXPIRES 90d portal window.

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text("SHARED")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color(hex: 0x5B9BFF))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.blue.opacity(0.12)))
                    Text("collaborate")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(sharedCount)")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("shared shipments")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("listForwarderShipments")
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.leading, Space.s4)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("EXPIRES")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(windowDays)d")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Text("portal")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - KPI strip (RAIL · TRUCK · WINDOW)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "RAIL",   value: "\(railCount)",     gradientNumeral: true)
            MetricTile(label: "TRUCK",  value: "\(truckCount)")
            MetricTile(label: "WINDOW", value: "\(windowDays)d")
        }
    }

    // MARK: - Shared portfolio (itemized ListRow stack)

    private var portfolioSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("SHARED PORTFOLIO")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("listForwarderShipments")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            if shipments.isEmpty {
                // PORT-GAP: rail[] branch of listForwarderShipments is a
                // backend STUB (truck/ocean only). Real empty state — no
                // fabricated rail rows.
                EusoEmptyState(systemImage: "shippingbox",
                               title: "No shared shipments",
                               subtitle: "Rail + truck shipments shared with this forwarder will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shipments.enumerated()), id: \.element.id) { idx, s in
                        portfolioRow(s)
                        if idx < shipments.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.vertical, Space.s2)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func portfolioRow(_ s: ForwarderShipment592) -> some View {
        let isRail = (s.mode ?? "").lowercased() == "rail"
        let modeColor: Color = isRail ? Brand.info : Brand.rail
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(modeColor.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: isRail ? "tram.fill" : "shippingbox.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(modeColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(s.reference ?? "—")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(s.lane ?? "—")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                statusPill(for: s.status ?? "")
                Text((s.mode ?? "—").lowercased())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    @ViewBuilder
    private func statusPill(for status: String) -> some View {
        let key = status.lowercased().replacingOccurrences(of: "_", with: " ")
        switch key {
        case "in transit", "intransit":
            StatusPill(text: "IN TRANSIT", kind: .info)
        case "gate in", "gatein":
            StatusPill(text: "GATE IN", kind: .warning)
        case "drayage":
            StatusPill(text: "DRAYAGE", kind: .neutral)
        default:
            StatusPill(text: status.replacingOccurrences(of: "_", with: " ").uppercased(),
                       kind: .neutral)
        }
    }

    // MARK: - Consolidation strip (secondary)

    private var consolidationStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CONSOLIDATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("consolidationSuggestions")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            if suggestions.isEmpty {
                Text("No consolidation suggestions right now.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(suggestions) { sug in
                    if let h = sug.headline {
                        Text(h).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                    if let d = sug.detail {
                        Text(d).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair (Grant portal access · Portfolio)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Grant portal access",
                      action: { Task { await grantPortalAccess() } },
                      leadingIcon: "plus",
                      isLoading: granting)
                .frame(maxWidth: .infinity)
            Button {
                // Secondary — open the full portfolio surface (Shipments tab).
                RailEngineerNavDispatcher.handle("shipments")
            } label: {
                Text("Portfolio")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 148, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        do {
            // forwarderPortal.createPortalAccess — the active grant the hero
            // summarizes (query-style read of the scoped access record).
            async let a: ForwarderPortalAccess592 = EusoTripAPI.shared.query(
                "forwarderPortal.createPortalAccess",
                input: ForwarderGroupInput592(forwarderGroupId: forwarderGroupId))
            // forwarderPortal.listForwarderShipments — shared portfolio rows.
            async let s: [ForwarderShipment592] = EusoTripAPI.shared.query(
                "forwarderPortal.listForwarderShipments",
                input: ForwarderListInput592(forwarderGroupId: forwarderGroupId, limit: 50))
            // forwarderPortal.consolidationSuggestions — co-load opportunities.
            async let c: [ConsolidationSuggestion592] = EusoTripAPI.shared.query(
                "forwarderPortal.consolidationSuggestions",
                input: ForwarderGroupInput592(forwarderGroupId: forwarderGroupId))

            let (acc, ships, sugs) = try await (a, s, c)
            self.access = acc
            self.shipments = ships
            self.suggestions = sugs
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Grant portal access (mutation)

    private func grantPortalAccess() async {
        granting = true; grantNotice = nil
        do {
            let acc: ForwarderPortalAccess592 = try await EusoTripAPI.shared.mutation(
                "forwarderPortal.createPortalAccess",
                input: ForwarderGroupInput592(forwarderGroupId: forwarderGroupId))
            self.access = acc
            grantNotice = "Portal access granted · expires in \(acc.expiresInDays ?? windowDays)d"
            await load()
        } catch {
            grantNotice = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        granting = false
    }
}

#Preview("592 · Rail Forwarder Portal · Night") { RailForwarderPortalScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("592 · Rail Forwarder Portal · Light") { RailForwarderPortalScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
