//
//  753_VesselTransitTimeComparison.swift
//  EusoTrip — Vessel Operator · Transit Time Comparison.
//
//  Faithful 1:1 port of "753 Vessel Transit Time Comparison.svg" (Light + Dark).
//  RANKED-BAR COMPARISON-BOARD archetype (deliberately distinct from 754's cost
//  number-line and 755's portfolio composition): every mode is a full-width row
//  whose bar length encodes avg transit days on a 0–21d axis, so the ocean
//  penalty reads at a glance instead of as a number you decode. Detail header
//  (✦ eyebrow + mono lane caption + 28/700 title), a decision hero (ocean avg
//  vs fastest mode + reliability range bar), the ranked transit-day board, a
//  CTA pair, and the ESANG trade-off row. Real Vessel-Operator BottomNav with
//  HOME inked, anchored to the shared Shell + BottomNav wrapper the registered
//  siblings ship.
//
//  Wiring (endpoint confirmed on disk this fire):
//    multiModal.getTransitTimeComparison — EXISTS frontend/server/routers/multiModal.ts:1861
//      · protectedProcedure · query · input {origin?,destination?}
//      · returns {comparison:[{mode,avgDays,minDays,maxDays,reliability,samples}], topLanes:[]}
//      grouped from real delivered loads (pickupDate → actualDeliveryDate).
//    ESANG trade-off row → esangCoach.forScreen (esangCoach.ts) recommendation surface.
//    "Compare lane" re-queries getTransitTimeComparison with {origin,destination}.
//    "Export" → STUB · named-gap exportTransitComparison (no render mutation yet) — re-runs load().
//
//  0 mock data on load · honest empty/degraded states. This is a historical
//  delivered-load aggregate (not a live position tick), so the four-system
//  map/geofence fusion does not apply — only the ESANG card is live.
//

import SwiftUI

// MARK: - Model

private struct TransitMode753: Identifiable {
    let mode: String            // ocean | intermodal | rail | truck
    let avgDays: Double
    let reliability: Double      // 0–100
    let samples: Int
    var id: String { mode }
}

private struct TransitBoard753 {
    let modes: [TransitMode753]
    var ocean: TransitMode753? { modes.first { $0.mode == "ocean" } }
    var withData: [TransitMode753] { modes.filter { $0.samples > 0 } }
    var fastest: TransitMode753? { withData.min { $0.avgDays < $1.avgDays } }
    var axisMax: Double { max(21, (modes.map(\.avgDays).max() ?? 0) * 1.05) }
}

private struct TransitQuery753: Encodable { let origin: String?; let destination: String? }

// MARK: - Wrapper

struct VesselTransitTimeComparisonScreen: View {
    let theme: Theme.Palette
    let origin: String
    let destination: String
    init(theme: Theme.Palette, origin: String = "CNSHA", destination: String = "USLGB") {
        self.theme = theme; self.origin = origin; self.destination = destination
    }
    var body: some View {
        Shell(theme: theme) {
            VesselTransitBody753(origin: origin, destination: destination)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselTransitBody753: View {
    let origin: String
    let destination: String
    @Environment(\.palette) private var palette

    @State private var board: TransitBoard753? = nil
    @State private var esangTip: String? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var degraded = false

    private let ocean = Brand.info                 // #2196F3
    private let intermodal = Brand.escort          // #9C27B0
    private let rail = Color(hex: 0x2FBE82)
    private let truck = Brand.warning              // #FFA726

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if let b = board, !b.withData.isEmpty {
                    heroCard(b)
                    boardSection(b)
                    ctaPair
                    esangRow(b)
                } else {
                    EusoEmptyState(systemImage: "chart.bar.xaxis",
                                   title: "No transit history in range",
                                   subtitle: "getTransitTimeComparison returned no delivered-load samples for \(origin) → \(destination). There is no transit to compare yet.")
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · TRANSIT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("\(origin) → \(destination)").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("Transit by mode").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    private var subline: String {
        guard let b = board, let o = b.ocean, let f = b.fastest else {
            return "Avg transit days by mode · delivered-load aggregate"
        }
        let gap = Int((o.avgDays - f.avgDays).rounded())
        return "Ocean is \(gap)d slower than \(f.mode) — and \(Int(o.reliability.rounded()))% reliable here"
    }

    // MARK: Hero — decision card

    private func heroCard(_ b: TransitBoard753) -> some View {
        let o = b.ocean
        let f = b.fastest
        return RimCard753 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("OCEAN AVG TRANSIT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(o?.samples ?? 0) SAILINGS").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                HStack(alignment: .top) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(days(o?.avgDays ?? 0)).font(.system(size: 44, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        Text("d").font(.system(size: 22, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        miniStat("FASTEST · \(f?.mode.uppercased() ?? "—")", "\(days(f?.avgDays ?? 0))d", truck)
                        miniStat("RELIABLE", "\(Int((o?.reliability ?? 0).rounded()))%", rail)
                    }
                }
                // reliability range bar — brand fill with fastest marker
                GeometryReader { g in
                    let w = g.size.width
                    let oceanFrac = min(1, (o?.avgDays ?? 0) / b.axisMax)
                    let fastFrac  = min(1, (f?.avgDays ?? 0) / b.axisMax)
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(0.10)).frame(height: 6)
                        Capsule().fill(LinearGradient.primary).frame(width: max(6, oceanFrac * w), height: 6)
                        RoundedRectangle(cornerRadius: 1).fill(truck)
                            .frame(width: 2, height: 10)
                            .offset(x: max(0, fastFrac * w - 1))
                    }
                }
                .frame(height: 10)
            }
        }
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(0.4).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(color)
        }
    }

    // MARK: Ranked transit-day board

    private func boardSection(_ b: TransitBoard753) -> some View {
        let rows = b.modes.filter { $0.samples > 0 }.sorted { $0.avgDays > $1.avgDays }
        return VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("BY MODE · AVG TRANSIT DAYS · 0–\(Int(b.axisMax))d")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, m in
                    TransitRow753(mode: m, axisMax: b.axisMax, accent: accent(m.mode),
                                  tag: tag(for: m, board: b))
                    if idx < rows.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, 16) }
                }
            }
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func tag(for m: TransitMode753, board: TransitBoard753) -> (String, Color)? {
        if m.mode == "ocean" { return ("YOURS", ocean) }
        if m.id == board.fastest?.id { return ("FASTEST", truck) }
        return nil
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: 8) {
            CTAButton(title: "Compare lane", action: { Task { await load() } })
            secondaryButton("Export") { Task { await load() } }.frame(width: 128)
        }
    }

    // MARK: ESANG trade-off

    private func esangRow(_ b: TransitBoard753) -> some View {
        let title: String
        let detail: String
        if let tip = esangTip, !tip.isEmpty {
            title = tip; detail = "Sail the non-urgent FEU · hold truck for the rush"
        } else if let o = b.ocean, let f = b.fastest {
            let gap = Int((o.avgDays - f.avgDays).rounded())
            title = "Ocean is \(gap)d slower but \(Int(o.reliability.rounded()))% reliable"
            detail = "Sail the non-urgent FEU · hold \(f.mode) for the \(days(f.avgDays))-day rush"
        } else {
            title = "Match mode to urgency"; detail = "Reserve the fast lane for time-critical cargo"
        }
        return ESangRow753(title: title, detail: detail)
    }

    // MARK: Primitives

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            .padding(.top, 4)
    }

    private func secondaryButton(_ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private var loadingCard: some View {
        LifecycleCard { Text("Loading transit comparison…").font(EType.caption).foregroundStyle(palette.textSecondary) }
    }
    private func errorCard(_ e: String) -> some View {
        LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
    }

    private func accent(_ mode: String) -> Color {
        switch mode {
        case "ocean": return ocean
        case "intermodal": return intermodal
        case "rail": return rail
        default: return truck
        }
    }
    private func days(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil; degraded = false
        do {
            struct Row: Decodable { let mode: String?; let avgDays: Double?; let reliability: Double?; let samples: Int? }
            struct Resp: Decodable { let comparison: [Row]? }
            let r: Resp = try await EusoTripAPI.shared.query(
                "multiModal.getTransitTimeComparison",
                input: TransitQuery753(origin: origin, destination: destination)
            )
            let modes = (r.comparison ?? []).compactMap { row -> TransitMode753? in
                guard let m = row.mode else { return nil }
                return TransitMode753(mode: m, avgDays: row.avgDays ?? 0,
                                      reliability: row.reliability ?? 0, samples: row.samples ?? 0)
            }
            board = TransitBoard753(modes: modes)
            // Live advisory (real tip or hidden). Screen enum key = "haul".
            struct CoachIn: Encodable { let screen: String }
            struct CoachOut: Decodable { let tip: String? }
            if let c: CoachOut = try? await EusoTripAPI.shared.query("esangCoach.forScreen", input: CoachIn(screen: "haul")),
               let t = c.tip, !t.isEmpty { esangTip = t } else { esangTip = nil }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - File-scoped bespoke helpers

private struct RimCard753<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

/// One ranked mode row — icon chip + name + samples sub + full-width day bar +
/// right tabular day figure + YOURS/FASTEST tag.
private struct TransitRow753: View {
    @Environment(\.palette) private var palette
    let mode: TransitMode753
    let axisMax: Double
    let accent: Color
    let tag: (String, Color)?

    private var glyph: String {
        switch mode.mode {
        case "ocean": return "ferry"
        case "intermodal": return "arrow.left.arrow.right"
        case "rail": return "tram.fill"
        default: return "box.truck.fill"
        }
    }
    private func days(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.opacity(0.20)))
            VStack(alignment: .leading, spacing: 6) {
                Text(mode.mode.capitalized).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(mode.samples) samples · \(Int(mode.reliability.rounded()))% on-time")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(0.10)).frame(height: 6)
                        Capsule().fill(accent).frame(width: max(6, min(1, mode.avgDays / axisMax) * g.size.width), height: 6)
                    }
                }.frame(height: 6)
            }
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(days(mode.avgDays))d").font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                if let tag { Text(tag.0).font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(tag.1) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

private struct ESangRow753: View {
    @Environment(\.palette) private var palette
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 16)).frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG: \(title)").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

#Preview("753 · Vessel Transit Time Comparison · Night") { VesselTransitTimeComparisonScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("753 · Vessel Transit Time Comparison · Light") { VesselTransitTimeComparisonScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
