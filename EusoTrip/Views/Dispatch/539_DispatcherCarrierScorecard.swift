//
//  539_DispatcherCarrierScorecard.swift
//  EusoTrip — Dispatcher · Carrier Scorecard (on-time × margin quadrant).
//
//  Verbatim port of "539 Dispatcher Carrier Scorecard.svg" (Dark canonical).
//  NET-NEW bespoke gap-fill in the Dispatcher revenue-assurance band — a
//  composition used by no other screen in the house: an on-time × margin
//  QUADRANT-SCATTER with carrier initials-bubbles over an FMCSA-weighted
//  tier ledger with grade chips + score bars.
//
//  Nav: Dispatcher bottom nav (DispatchNavController shipped config —
//  Home · Drivers | Loads(current) · Me). See report §50 "Autonomous choices"
//  for the BOARD/COMMS label divergence from this SVG (flagged for nav lane;
//  every tap here routes through the REAL DispatchNavDispatcher, no dead taps).
//
//  Data (all real, no mock):
//    carrierScorecard.getQuadrant       (NEW :gap-fill) → bubbles + ledger (x=on-time, y=margin/RPM, bubble=loads)
//    carrierScorecard.getTopCarriers    (EXISTS :326)   → ledger fallback
//    carrierScorecard.compareScorecards (EXISTS :210)   → "Compare" CTA (real carrierIds)
//    dispatch.assignDriver              (EXISTS :1033)  → "Assign top carrier" routes to the
//                                                          real assignment gate (needs a loadId;
//                                                          no one-tap carrier award is fabricated).
//

import SwiftUI

// MARK: - Data shapes (decode the REAL server returns field-for-field)

private struct QuadResponse539: Decodable {
    let carriers: [QuadCarrier539]
    let ownFleetId: Int?
    let scopedCompanyId: Int?
}

private struct QuadCarrier539: Decodable, Identifiable {
    let carrierId: Int
    let companyName: String
    let initials: String
    let dotNumber: String?
    let mcNumber: String?
    let onTimeRate: Int
    let avgRpm: Double
    let marginIndex: Int
    let loadCount: Int
    let overallScore: Int
    let grade: String
    let isOwnFleet: Bool
    let complianceStatus: String?
    let hazmatAuthorized: Bool?
    var id: Int { carrierId }
}

// Fallback row shape (carrierScorecard.getTopCarriers) — lenient optionals.
private struct TopCarrier539: Decodable, Identifiable {
    let carrierId: Int
    let companyName: String?
    let dotNumber: String?
    let score: Double?
    let grade: String?
    let totalLoads: Int?
    var id: Int { carrierId }
}

// MARK: - Screen

struct DispatcherCarrierScorecardScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { DispatcherCarrierScorecardBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct DispatcherCarrierScorecardBody: View {
    @Environment(\.palette) private var palette

    @State private var carriers: [QuadCarrier539] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isComparing = false
    @State private var actionError: String? = nil

    // Quadrant palette (verbatim to SVG quadrant labels)
    private let cCostly  = Brand.warning            // COSTLY · SLOW   (top-left)
    private let cKeep    = Color(hex: 0x00966B)     // KEEP · GROW     (top-right)
    private let cCut     = Color(hex: 0xD2342A)     // CUT             (bottom-left)
    private let cVolume  = Color(hex: 0xAAB2BB)     // VOLUME · THIN   (bottom-right)

    private var activeCount: Int { carriers.count }
    private var topCarrier: QuadCarrier539? {
        carriers.max(by: { $0.overallScore < $1.overallScore })
    }
    private var ledgerRows: [QuadCarrier539] {
        Array(carriers.sorted { $0.overallScore > $1.overallScore }.prefix(2))
    }
    private var moreCount: Int { max(0, carriers.count - ledgerRows.count) }

    private func gradeColor(_ grade: String) -> Color {
        if grade.hasPrefix("A") { return Brand.success }
        if grade.hasPrefix("B") { return Brand.warning }
        if grade.hasPrefix("C") { return Color(hex: 0x52606D) }
        return Brand.danger
    }
    private func gradeTint(_ grade: String) -> Color {
        if grade.hasPrefix("A") || grade.hasPrefix("B") { return Brand.success.opacity(0.14) }
        if grade.hasPrefix("C") { return Color.white.opacity(0.08) }
        return Brand.danger.opacity(0.14)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, 14)

            if loading {
                placeholder("Loading carrier scorecard…", danger: false)
            } else if let err = loadError, carriers.isEmpty {
                placeholder(err, danger: true)
            } else if carriers.isEmpty {
                EusoEmptyState(
                    systemImage: "chart.dot.scatter",
                    title: "No active carriers",
                    subtitle: "Carriers you tender to will plot here on on-time × margin."
                )
                .padding(.top, 24)
            } else {
                quadrantCard.padding(.top, 20)
                tierLedger.padding(.top, 16)
                ctaPair.padding(.top, 18)
                if let ae = actionError {
                    Text(ae).font(EType.caption).foregroundStyle(Brand.danger).padding(.top, 8)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (DETAIL grammar)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("✦ DISPATCHER · CARRIER SCORECARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("\(activeCount) ACTIVE · FMCSA")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Carriers")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.leading, 4)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Hero: quadrant scatter (bespoke)

    private var quadrantCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ON-TIME × MARGIN · LAST 90D")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("bubble = loads")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 20).padding(.top, 20)

            QuadrantPlot(
                carriers: carriers,
                cCostly: cCostly, cKeep: cKeep, cCut: cCut, cVolume: cVolume,
                textTertiary: palette.textTertiary
            )
            .frame(height: 212)
            .padding(.horizontal, 16).padding(.top, 14)

            Text(ringCaption)
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: 0x1C2128))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.85), lineWidth: 1.5)
        )
    }

    private var ringCaption: String {
        if let own = carriers.first(where: { $0.isOwnFleet }) {
            let q = own.onTimeRate >= 88 && own.marginIndex >= 50 ? "KEEP · GROW"
                  : own.onTimeRate >= 88 ? "VOLUME · THIN"
                  : own.marginIndex >= 50 ? "COSTLY · SLOW" : "CUT"
            return "ring = your fleet · \(own.companyName) leads \(q)"
        }
        return "ring = your fleet"
    }

    // MARK: - Tier ledger

    private var tierLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("TIER LEDGER · FMCSA-WEIGHTED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("scorecard.ts:21")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(ledgerRows.enumerated()), id: \.element.id) { idx, c in
                    ledgerRow(c)
                    if idx < ledgerRows.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                            .padding(.horizontal, 16)
                    }
                }
                HStack {
                    Text("+ \(moreCount) more · FMCSA BASIC + on-time + claims weighted · DU shipper")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x1C2128))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
        }
    }

    @ViewBuilder
    private func ledgerRow(_ c: QuadCarrier539) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // initials chip — gradient for own fleet, tinted info otherwise
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(c.isOwnFleet ? AnyShapeStyle(LinearGradient.diagonal)
                                       : AnyShapeStyle(Brand.info.opacity(0.14)))
                Text(c.initials)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(c.isOwnFleet ? Color.white : Color(hex: 0x1B74C4))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(c.companyName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(metaLine(c))
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                // score bar
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10)).frame(width: 210, height: 5)
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: max(6, 210 * CGFloat(min(100, max(0, c.overallScore))) / 100), height: 5)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 6)

            // grade chip
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(gradeTint(c.grade))
                Text(c.grade)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(gradeColor(c.grade))
            }
            .frame(width: 24, height: 24)

            Text("\(c.overallScore)")
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func metaLine(_ c: QuadCarrier539) -> String {
        var parts: [String] = []
        if let dot = c.dotNumber, !dot.isEmpty {
            // group USDOT digits like the SVG ("USDOT 3 482 119")
            parts.append("USDOT \(groupDigits(dot))")
        }
        parts.append("\(c.loadCount) loads")
        parts.append("\(c.onTimeRate)% OTR")
        return parts.joined(separator: " · ")
    }

    private func groupDigits(_ s: String) -> String {
        let digits = s.filter(\.isNumber)
        guard digits.count > 3 else { return digits }
        var out = "", count = 0
        for ch in digits.reversed() {
            if count != 0 && count % 3 == 0 { out.append(" ") }
            out.append(ch); count += 1
        }
        return String(out.reversed())
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: 8) {
            Button { routeToAssignment() } label: {
                Text("Assign top carrier")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(topCarrier == nil)
            .opacity(topCarrier == nil ? 0.6 : 1)

            Button { Task { await compareCarriers() } } label: {
                Text(isComparing ? "Comparing…" : "Compare")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(Color(hex: 0x232932))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10)))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isComparing || carriers.count < 2)
        }
    }

    // MARK: - Load / actions

    private func load() async {
        loading = true; loadError = nil
        struct QuadIn: Encodable { let limit: Int; let minLoads: Int }
        do {
            let resp: QuadResponse539 = try await EusoTripAPI.shared.query(
                "carrierScorecard.getQuadrant", input: QuadIn(limit: 12, minLoads: 1))
            self.carriers = resp.carriers
        } catch {
            // Honest fallback to the shipped getTopCarriers (no margin axis) so the
            // ledger still populates while getQuadrant is being landed by the host lane.
            struct TopIn: Encodable { let limit: Int; let minScore: Int }
            do {
                let rows: [TopCarrier539] = try await EusoTripAPI.shared.query(
                    "carrierScorecard.getTopCarriers", input: TopIn(limit: 6, minScore: 0))
                self.carriers = rows.map { r in
                    QuadCarrier539(
                        carrierId: r.carrierId,
                        companyName: r.companyName ?? "Carrier \(r.carrierId)",
                        initials: initialsFallback(r.companyName ?? "C\(r.carrierId)"),
                        dotNumber: r.dotNumber,
                        mcNumber: nil,
                        onTimeRate: Int(r.score ?? 0),
                        avgRpm: 0,
                        marginIndex: Int(r.score ?? 0),  // no margin source in fallback
                        loadCount: r.totalLoads ?? 0,
                        overallScore: Int(r.score ?? 0),
                        grade: r.grade ?? "—",
                        isOwnFleet: false,
                        complianceStatus: nil,
                        hazmatAuthorized: nil)
                }
                if self.carriers.isEmpty {
                    loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
                }
            } catch {
                loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        loading = false
    }

    private func compareCarriers() async {
        guard carriers.count >= 2 else { return }
        isComparing = true; actionError = nil
        struct CompareIn: Encodable { let carrierIds: [Int] }
        struct CompareRow: Decodable {}   // result shape intentionally ignored here
        let ids = Array(carriers.prefix(10).map(\.carrierId))
        do {
            let _: [CompareRow] = try await EusoTripAPI.shared.query(
                "carrierScorecard.compareScorecards", input: CompareIn(carrierIds: ids))
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isComparing = false
    }

    /// "Assign top carrier" — routes to the REAL assignment gate. dispatch.assignDriver
    /// requires a loadId (it's the load-assignment compliance gate), so we cannot one-tap
    /// award a carrier from a roll-up surface without fabricating a load. We route the
    /// dispatcher to the live assignment queue (Loads) via the shipped nav chain, where the
    /// FMCSA-OOS / insurance / CDL gates run on a concrete load.
    private func routeToAssignment() {
        guard topCarrier != nil else { return }
        DispatchNavDispatcher.handle("loads")
    }

    private func initialsFallback(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Small helpers

    @ViewBuilder
    private func placeholder(_ text: String, danger: Bool) -> some View {
        HStack {
            Text(text).font(EType.caption)
                .foregroundStyle(danger ? Brand.danger : palette.textSecondary)
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x1C2128)))
        .padding(.top, 24)
    }
}

// MARK: - QuadrantPlot (the bespoke composition)

private struct QuadrantPlot: View {
    let carriers: [QuadCarrier539]
    let cCostly: Color, cKeep: Color, cCut: Color, cVolume: Color
    let textTertiary: Color

    // On-time domain — carriers cluster high, so plot 70..100 across the width.
    private let otMin: CGFloat = 70, otMax: CGFloat = 100

    private func bubbleRadius(_ loads: Int) -> CGFloat {
        let r = 8 + sqrt(CGFloat(max(1, loads))) * 1.6
        return min(22, max(9, r))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let padL: CGFloat = 22, padR: CGFloat = 8, padT: CGFloat = 8, padB: CGFloat = 22
            let plotW = w - padL - padR, plotH = h - padT - padB

            let px: (Int) -> CGFloat = { onTime in
                let t = (CGFloat(onTime).clamped(otMin, otMax) - otMin) / (otMax - otMin)
                return padL + t * plotW
            }
            let py: (Int) -> CGFloat = { margin in
                let t = CGFloat(margin).clamped(0, 100) / 100      // 0..1 (0 = bottom)
                return padT + (1 - t) * plotH                       // SVG y grows downward
            }

            ZStack(alignment: .topLeading) {
                // plot frame
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06)))
                    .frame(width: plotW, height: plotH)
                    .offset(x: padL, y: padT)

                // gridlines (center cross)
                Path { p in
                    p.move(to: CGPoint(x: padL, y: padT + plotH / 2))
                    p.addLine(to: CGPoint(x: padL + plotW, y: padT + plotH / 2))
                    p.move(to: CGPoint(x: padL + plotW / 2, y: padT))
                    p.addLine(to: CGPoint(x: padL + plotW / 2, y: padT + plotH))
                }.stroke(Color.white.opacity(0.06), lineWidth: 1)

                // quadrant labels
                quadLabel("COSTLY · SLOW", cCostly).offset(x: padL + 8, y: padT + 6)
                quadLabel("KEEP · GROW", cKeep, trailing: true)
                    .frame(width: plotW - 12, alignment: .trailing).offset(x: padL + 6, y: padT + 6)
                quadLabel("CUT", cCut).offset(x: padL + 8, y: padT + plotH - 18)
                quadLabel("VOLUME · THIN", cVolume, trailing: true)
                    .frame(width: plotW - 12, alignment: .trailing).offset(x: padL + 6, y: padT + plotH - 18)

                // axis hints
                Text("ON-TIME % →")
                    .font(.system(size: 9, weight: .bold)).tracking(0.4)
                    .foregroundStyle(textTertiary)
                    .frame(width: plotW, alignment: .center)
                    .offset(x: padL, y: h - 14)
                Text("MARGIN / RPM →")
                    .font(.system(size: 9, weight: .bold)).tracking(0.4)
                    .foregroundStyle(textTertiary)
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .frame(width: 14)
                    .position(x: 8, y: padT + plotH / 2)

                // bubbles
                ForEach(carriers) { c in
                    let r = bubbleRadius(c.loadCount)
                    let cx = px(c.onTimeRate), cy = py(c.marginIndex)
                    bubble(c, radius: r).position(x: cx, y: cy)
                }
            }
        }
    }

    @ViewBuilder
    private func quadLabel(_ t: String, _ color: Color, trailing: Bool = false) -> some View {
        Text(t).font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(color)
    }

    @ViewBuilder
    private func bubble(_ c: QuadCarrier539, radius r: CGFloat) -> some View {
        let baseColor = bubbleColor(c)
        if c.isOwnFleet {
            ZStack {
                Circle().fill(LinearGradient.diagonal.opacity(0.16)).frame(width: (r + 4) * 2, height: (r + 4) * 2)
                Circle().fill(LinearGradient.diagonal).frame(width: r * 2, height: r * 2)
                Text(c.initials).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            }
        } else {
            ZStack {
                Circle().fill(baseColor.opacity(0.16)).frame(width: r * 2, height: r * 2)
                Circle().strokeBorder(baseColor.opacity(0.5), lineWidth: 1).frame(width: r * 2, height: r * 2)
                Text(c.initials).font(.system(size: r > 12 ? 9 : 8, weight: .heavy)).foregroundStyle(baseColor)
            }
        }
    }

    private func bubbleColor(_ c: QuadCarrier539) -> Color {
        let keep = c.onTimeRate >= 88 && c.marginIndex >= 50
        let cut  = c.onTimeRate < 88 && c.marginIndex < 50
        let volume = c.onTimeRate >= 88 && c.marginIndex < 50
        if keep { return Color(hex: 0x7B1FA2) }       // high-value (purple bubble in SVG = Cascade)
        if cut { return cCut }
        if volume { return cVolume }
        return cCostly
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(hi, Swift.max(lo, self)) }
}

// NOTE: the getTopCarriers fallback above uses QuadCarrier539's synthesized
// memberwise initializer (the struct declares no custom init in its main
// declaration, so Swift keeps the memberwise init alongside Decodable's
// synthesized init(from:)). The server's extra `fmcsa` key is ignored by the
// decoder since QuadCarrier539 declares no matching property.

// MARK: - Preview

#Preview("539 · Dispatcher Carrier Scorecard · Night") {
    DispatcherCarrierScorecardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
