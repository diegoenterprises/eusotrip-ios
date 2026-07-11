//
//  690_VesselTerminalStatus.swift
//  EusoTrip — Vessel Operator · Terminal Status (congestion gauge board).
//
//  Verbatim port of "690 Vessel Terminal Status.svg" (Dark + Light). Archetype =
//  BOARD. A radial overall-utilization gauge hero with live readouts, then a
//  ranked-terminal congestion board where every row is a utilization + dwell bar
//  with a HIGH/MED/LOW pill — a ranking board, not icon ListRows.
//
//  tRPC (verified live 2026-07):
//    portIntelligence.findByProduct (EXISTS :75, {product, apiGravity?, sulfur?,
//      hazmatClass?}) → [{ id, name, country, acceptedProducts[], utilizationPct,
//      avgDwellHours, basis('observed_traffic'|'capability') }] (≤20, null-safe,
//      never a fabricated %). The gauge (avg util), the readouts (terminals / dwell
//      / peak / low), and the ranked rows all bind to this real payload.
//  HONEST GAP (surfaced to the-oath): truck-gate queue depth + dual-transaction
//    restriction calendar have no procedure (proposed portOps.getGateQueue) — the
//    hero shows utilization + dwell (real), not a fabricated berth-wait/gate-turn.
//    Each row shows the ONE real utilization + a relative-dwell bar, not two
//    invented gate/yard numbers.
//
//  RBAC isolatedProcedure (tenant-scoped by ctx.isolation). transportMode =
//  vessel · US port. NAV (VesselOperator): HOME · SHIPMENTS(current) · [orb] ·
//  COMPLIANCE · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

private struct PortRow690: Decodable {
    let id: String?
    let name: String?
    let country: String?
    let utilizationPct: Double?
    let avgDwellHours: Double?
    let basis: String?
}

struct VesselTerminalStatusScreen: View {
    var theme: Theme.Palette = Theme.dark
    /// Product lens the congestion board is scoped to (default general container).
    var product: String = "container"

    var body: some View {
        Shell(theme: theme) {
            VesselTerminalStatusBody(product: product)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                  isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselTerminalStatusBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let product: String

    @State private var ports: [PortRow690] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil

    private var ranked: [PortRow690] {
        ports.filter { $0.utilizationPct != nil }
            .sorted { ($0.utilizationPct ?? 0) > ($1.utilizationPct ?? 0) }
    }
    private var overallUtil: Int {
        let vals = ranked.compactMap { $0.utilizationPct }
        guard !vals.isEmpty else { return 0 }
        return Int((vals.reduce(0, +) / Double(vals.count)).rounded())
    }
    private var avgDwellDays: Double {
        let vals = ranked.compactMap { $0.avgDwellHours }
        guard !vals.isEmpty else { return 0 }
        return (vals.reduce(0, +) / Double(vals.count)) / 24
    }
    private var peakUtil: Int { Int((ranked.first?.utilizationPct ?? 0).rounded()) }
    private var lowUtil: Int { Int((ranked.last?.utilizationPct ?? 0).rounded()) }
    private var maxDwell: Double { max(1, ranked.compactMap { $0.avgDwellHours }.max() ?? 1) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if let actionNote { noteBanner(actionNote) }

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    gaugeHero
                    rankedBoard
                    esang
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ VESSEL OPERATOR · TERMINAL STATUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(ranked.first.map { "\(shortName($0.name)) · \($0.country ?? "")" } ?? "LIVE")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Text("Terminal status")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Gauge hero

    private var gaugeHero: some View {
        HStack(spacing: Space.s5) {
            gauge
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    readout("TERMINALS", "\(ranked.count)")
                    Spacer()
                    liveChip
                }
                HStack {
                    readout("AVG DWELL", avgDwellDays > 0 ? String(format: "%.1fd", avgDwellDays) : "—")
                    Spacer()
                    readout("PEAK UTIL", "\(peakUtil)%", trailing: true)
                }
                HStack {
                    readout("BEST GATE", "\(lowUtil)%")
                    Spacer()
                    readout("PRODUCT", product.uppercased(), trailing: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.s5)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var gauge: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * CGFloat(overallUtil) / 100)
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(135))
            VStack(spacing: 1) {
                Text("\(overallUtil)%")
                    .font(.system(size: 30, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("OVERALL UTIL")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 108, height: 108)
    }

    private var liveChip: some View {
        HStack(spacing: 5) {
            Circle().fill(Brand.success)
                .frame(width: 6, height: 6)
                .opacity(reduceMotion ? 1 : livePulse)
            Text("LIVE")
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.success)
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(Brand.success.opacity(0.20)))
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    livePulse = 0.3
                }
            }
        }
    }
    @State private var livePulse: Double = 1

    private func readout(_ label: String, _ value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    // MARK: - Ranked congestion board

    private var rankedBoard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("TERMINALS · RANKED BY CONGESTION · LIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                if ranked.isEmpty {
                    EusoEmptyState(systemImage: "chart.bar",
                                   title: "No terminal congestion yet",
                                   subtitle: "Live utilization for your product lens will appear here.")
                        .padding(.vertical, Space.s2)
                } else {
                    ForEach(Array(ranked.prefix(6).enumerated()), id: \.offset) { idx, p in
                        if idx > 0 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
                        terminalRow(p)
                    }
                    if ranked.count > 6 {
                        Text("+ \(ranked.count - 6) more terminals · ranked by congestion")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, Space.s3)
                    }
                }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func terminalRow(_ p: PortRow690) -> some View {
        let util = Int((p.utilizationPct ?? 0).rounded())
        let dwellFrac = CGFloat((p.avgDwellHours ?? 0) / maxDwell)
        let (band, bandColor): (String, Color) = {
            if util >= 70 { return ("HIGH", Brand.danger) }
            if util >= 50 { return ("MED", Brand.warning) }
            return ("LOW", Brand.success)
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(shortName(p.name)) · \(p.country ?? "")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                Text("\(util)%")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
            HStack {
                Text(dwellLine(p))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                Text(band)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(bandColor)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(bandColor.opacity(0.20)))
            }
            // Twin real bars: UTIL (utilizationPct) + DWELL (relative dwell).
            barRow(label: "UTIL", frac: CGFloat(util) / 100, color: nil)
            barRow(label: "DWELL", frac: dwellFrac, color: Brand.warning)
        }
        .padding(.vertical, Space.s3)
    }

    private func barRow(label: String, frac: CGFloat, color: Color?) -> some View {
        HStack(spacing: Space.s3) {
            Text(label)
                .font(.system(size: 9, weight: .bold)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 40, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10)).frame(height: 6)
                    Capsule()
                        .fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient.primary))
                        .frame(width: geo.size.width * min(1, max(0, frac)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func dwellLine(_ p: PortRow690) -> String {
        var parts: [String] = []
        if let h = p.avgDwellHours, h > 0 { parts.append(String(format: "dwell %.1fd", h / 24)) }
        if let b = p.basis { parts.append(b == "observed_traffic" ? "observed" : "capability") }
        return parts.isEmpty ? "live utilization" : parts.joined(separator: " · ")
    }

    private func shortName(_ n: String?) -> String {
        guard let n, !n.isEmpty else { return "Terminal" }
        return n.replacingOccurrences(of: "Port of ", with: "")
    }

    // MARK: - ESANG

    private var esang: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .white.opacity(0)],
                                             center: .init(x: 0.35, y: 0.30),
                                             startRadius: 0, endRadius: 16))
                    .frame(width: 22, height: 22)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · GATE ADVISORY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(esangHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Empty-return restrictions & dual-txn — pending gate-queue feed")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var esangHeadline: String {
        if let best = ranked.last, let worst = ranked.first,
           let bu = best.utilizationPct, let wu = worst.utilizationPct, wu > bu {
            let faster = Int((((wu - bu) / wu) * 100).rounded())
            return "Route to \(shortName(best.name)) · \(faster)% lower utilization"
        }
        return "Book the least-congested gate slot"
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {
                actionNote = "Booking a gate slot at \(shortName(ranked.last?.name)) — the least-congested terminal."
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 15, weight: .bold))
                    Text("Book gate slot")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                actionNote = "Opening the full port directory."
            } label: {
                Text("Directory")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading + note

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 128)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 280)
        }
    }

    private func noteBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.info)
            Text(message).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Button { actionNote = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.info.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.info.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let product: String }
        do {
            let rows: [PortRow690]? = try await EusoTripAPI.shared.query(
                "portIntelligence.findByProduct", input: In(product: product))
            self.ports = rows ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("690 · Vessel Terminal Status · Night") {
    VesselTerminalStatusScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("690 · Vessel Terminal Status · Light") {
    VesselTerminalStatusScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
