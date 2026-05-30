//
//  685_VesselBunkerFSCSchedule.swift
//  EusoTrip — Vessel Operator · Bunker FSC Schedule.
//
//  Verbatim port of wireframe "685 Vessel Bunker FSC Schedule · Dark".
//  Bespoke archetype: a STEP-FUNCTION SURCHARGE STAIRCASE. The body plots
//  the bunker fuel-surcharge as an actual step chart — Singapore VLSFO
//  index ($/MT) on the x-axis, the stepped surcharge percent rising
//  left-to-right, the live bracket lit under a gradient riser with a
//  marker dropped at the current index reading. The hero shows the live
//  bracket + the index with its weekly move; the strip shows the dollar
//  it adds to this booking; the ESANG row reads how near the index sits
//  to the next step.
//
//  RBAC: vesselProcedure (VESSEL_OPERATOR). transportMode VESSEL.
//  Index: Singapore VLSFO (settles in USD; bracket math currency-neutral).
//
//  ENDPOINTS
//    • agreements.getById EXISTS — agreement fuel-surcharge terms
//      (fuelSurchargeType ENUM none|fixed|doe_index|percentage|custom,
//       fuelSurchargeValue; agreements.ts:1190). The scalar surcharge
//       type/value lives on the agreement row.
//    • vesselShipments.getVesselShipmentDetail EXISTS — the applied
//      amount derives from the active booking loadRate (vessel detail,
//      vesselShipments.ts:234).
//    • getBunkerFSCSchedule — PORT-GAP. The live VLSFO Singapore index
//      feed + stepped bracket table the staircase needs has no procedure
//      yet (the agreement row stores only a scalar surcharge type/value).
//      Surfaced to the-oath. Falls back to a real empty/error state.
//

import SwiftUI

struct VesselBunkerFSCScheduleScreen: View {
    let theme: Theme.Palette
    /// Active vessel booking the FSC bracket is applied to. Defaults to
    /// empty so the screen is constructable as
    /// `VesselBunkerFSCScheduleScreen(theme: p)` from ScreenRegistry.
    var bookingRef: String = ""
    /// Agreement whose fuel-surcharge terms anchor the schedule. Defaults
    /// to 0 so the screen needs only `theme` to construct.
    var agreementId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselBunkerFSCScheduleBody(bookingRef: bookingRef, agreementId: agreementId)
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

// MARK: - Data shapes

/// `getBunkerFSCSchedule` row (PORT-GAP — not on server). Shape mirrors
/// the named gap in the wireframe <desc>: a VLSFO Singapore index reading
/// plus the stepped bracket table the staircase renders.
private struct BunkerFSCSchedule: Decodable {
    let index: String?              // 'VLSFO_SINGAPORE'
    let indexUsdPerMt: Double?
    let weekChangePct: Double?
    let settleCadence: String?      // 'weekly'
    let brackets: [FSCBracket]?
    let currentBracketIdx: Int?
    let nextSettleAt: String?       // ISO
}

private struct FSCBracket: Decodable, Identifiable {
    var id: String { "\(minUsdMt)-\(maxUsdMt ?? -1)" }
    let minUsdMt: Double
    let maxUsdMt: Double?            // null = open-ended top bracket
    let surchargePct: Double
}

/// `agreements.getById` — only the fuel-surcharge scalar terms are read
/// here (the agreement row anchors the schedule). Full row also returns
/// party / signature / amendment data we don't surface on this screen.
private struct AgreementFSCTerms: Decodable {
    let fuelSurchargeType: String?  // none | fixed | doe_index | percentage | custom
    let fuelSurchargeValue: Double?
}

/// `vesselShipments.getVesselShipmentDetail` — the active booking the FSC
/// bracket is applied to. Only the rate + carrier the strip prints are
/// read here.
private struct VesselBookingFSC: Decodable {
    let bookingNumber: String?
    let loadRate: Double?
    let carrierName: String?
}

// MARK: - Body

private struct VesselBunkerFSCScheduleBody: View {
    @Environment(\.palette) private var palette
    let bookingRef: String
    let agreementId: Int

    @State private var schedule: BunkerFSCSchedule? = nil
    @State private var terms: AgreementFSCTerms? = nil
    @State private var booking: VesselBookingFSC? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var scheduleGap = false   // true → getBunkerFSCSchedule unavailable

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)
                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingPlaceholder
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if let s = schedule {
                        hero(s)
                        staircaseCard(s)
                        appliedStrip(s)
                        esangInsight(s)
                        ctaPair
                    } else {
                        scheduleEmptyState
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (DETAIL)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · BUNKER FSC")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("VLSFO · WEEKLY")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Bunker FSC")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.leading, 4)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s3)
        }
    }

    // MARK: - Hero: live bracket + index

    private func hero(_ s: BunkerFSCSchedule) -> some View {
        let idx = s.currentBracketIdx ?? 0
        let bracket = (s.brackets ?? []).indices.contains(idx) ? s.brackets?[idx] : nil
        let pct = bracket?.surchargePct
        let week = s.weekChangePct ?? 0
        let up = week >= 0
        return ZStack {
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("LIVE SURCHARGE BRACKET")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(s.indexUsdPerMt.map { "$\(Int($0.rounded()))" } ?? "—")
                            .font(.system(size: 22, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text(String(format: "%@ %+.1f%% wk", up ? "▲" : "▼", week))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(up ? Brand.warning : Brand.success)
                        Text("$/MT index")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 12) {
                    Text(pct.map { String(format: "%.1f%%", $0) } ?? "—")
                        .font(.system(size: 40, weight: .bold)).tracking(-1.0)
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bracketLabel(bracket))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(appliedLine(s))
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                }
                Text("Singapore VLSFO · diesel-index anchored")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 6)
            }
            .padding(Space.s5)
        }
        .frame(height: 100)
    }

    private func bracketLabel(_ b: FSCBracket?) -> String {
        guard let b else { return "—" }
        let lo = "$\(Int(b.minUsdMt.rounded()))"
        let hi = b.maxUsdMt.map { "$\(Int($0.rounded()))" } ?? "+"
        return "\(lo) – \(hi) / MT"
    }

    private func appliedLine(_ s: BunkerFSCSchedule) -> String {
        let cadence = (s.settleCadence ?? "weekly").lowercased()
        let day: String = cadence == "weekly" ? "Mon" : cadence.capitalized
        return "applied this week · settles \(day)"
    }

    // MARK: - Step-function staircase chart

    private func staircaseCard(_ s: BunkerFSCSchedule) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("STEPPED LADDER · VLSFO $/MT → SURCHARGE")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.bottom, Space.s3)
            StaircaseChart(schedule: s, palette: palette)
                .frame(height: 252)
                .background(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - Applied-charge strip

    private func appliedStrip(_ s: BunkerFSCSchedule) -> some View {
        let idx = s.currentBracketIdx ?? 0
        let bracket = (s.brackets ?? []).indices.contains(idx) ? s.brackets?[idx] : nil
        let pct = bracket?.surchargePct ?? 0
        let base = booking?.loadRate ?? 0
        let applied = base * pct / 100.0
        let carrier = booking?.carrierName ?? "—"
        let bn = booking?.bookingNumber ?? bookingRef
        return HStack(spacing: 0) {
            Rectangle().fill(LinearGradient.diagonal).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("APPLIED TO BOOKING")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(String(format: "base %@ × %.1f%% bracket", currency(base), pct))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(bn.isEmpty ? "—" : bn) · \(carrier)")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.leading, Space.s4)
            .padding(.vertical, Space.s3)
            Spacer()
            Text("+" + currency(applied))
                .font(.system(size: 20, weight: .bold)).monospacedDigit()
                .foregroundStyle(Brand.success)
                .padding(.trailing, Space.s5)
        }
        .frame(height: 72)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - ESANG insight

    private func esangInsight(_ s: BunkerFSCSchedule) -> some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(esangHeadline(s))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text(esangSub(s))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .frame(height: 56)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func esangHeadline(_ s: BunkerFSCSchedule) -> String {
        let idx = s.currentBracketIdx ?? 0
        let brackets = s.brackets ?? []
        guard let cur = s.indexUsdPerMt,
              brackets.indices.contains(idx),
              let top = brackets[idx].maxUsdMt else {
            return "ESang: tracking the VLSFO step ladder"
        }
        let gap = max(0, top - cur)
        let nextPct = brackets.indices.contains(idx + 1) ? brackets[idx + 1].surchargePct : nil
        if let nextPct {
            return String(format: "ESang: index $%.0f from the %.0f%% step at this pace", gap, nextPct)
        }
        return String(format: "ESang: index $%.0f from the top step at this pace", gap)
    }

    private func esangSub(_ s: BunkerFSCSchedule) -> String {
        let idx = s.currentBracketIdx ?? 0
        let brackets = s.brackets ?? []
        let base = booking?.loadRate ?? 0
        guard brackets.indices.contains(idx),
              let top = brackets[idx].maxUsdMt,
              brackets.indices.contains(idx + 1) else {
            return "lock the rate before the next settle"
        }
        let curPct = brackets[idx].surchargePct
        let nextPct = brackets[idx + 1].surchargePct
        let delta = base * (nextPct - curPct) / 100.0
        return String(format: "a settle above $%.0f adds %@ to this booking — lock the rate now",
                      top, currency(delta))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await load() }
            } label: {
                Text("Regenerate schedule")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(LinearGradient.primary)
            .clipShape(Capsule())

            Button { } label: {
                Text("Index history")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 136, height: 48)
            }
            .background(palette.bgCardSoft)
            .overlay(Capsule().strokeBorder(palette.borderSoft))
            .clipShape(Capsule())
        }
    }

    // MARK: - Loading / empty

    private var loadingPlaceholder: some View {
        VStack(spacing: Space.s4) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: i == 1 ? 252 : (i == 0 ? 100 : 72))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    @ViewBuilder
    private var scheduleEmptyState: some View {
        if scheduleGap {
            LifecycleCard {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("BUNKER FSC SCHEDULE UNAVAILABLE")
                            .font(EType.micro).tracking(0.8)
                            .foregroundStyle(palette.textPrimary)
                    }
                    Text("The live Singapore VLSFO index feed and stepped bracket table aren't wired to a server procedure yet. The agreement stores only a scalar surcharge type/value.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    if let t = terms, let type = t.fuelSurchargeType {
                        Text("Agreement term · \(type)\(t.fuelSurchargeValue.map { String(format: " · %.4g", $0) } ?? "")")
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        } else {
            EusoEmptyState(systemImage: "chart.line.uptrend.xyaxis",
                           title: "No bunker FSC schedule",
                           subtitle: "The stepped VLSFO surcharge ladder will appear here.")
        }
    }

    // MARK: - Format

    private func currency(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: n) ?? "\(Int(v))")
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil; scheduleGap = false
        // Agreement fuel-surcharge terms + active booking detail are real
        // server reads; the stepped VLSFO bracket feed is the named gap.
        struct IdIn: Encodable { let id: Int }

        // Agreement terms (best-effort — scalar surcharge type/value).
        if agreementId > 0 {
            do {
                terms = try await EusoTripAPI.shared.query(
                    "agreements.getById", input: IdIn(id: agreementId))
            } catch { terms = nil }
        }

        // Active booking the bracket is applied to (best-effort). The
        // server keys getVesselShipmentDetail on a numeric id, so only
        // fire when the booking ref resolves to one (the human VES-… ref
        // still prints on the strip regardless).
        if let bookingId = Int(bookingRef) {
            do {
                booking = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail", input: IdIn(id: bookingId))
            } catch { booking = nil }
        }

        // PORT-GAP: getBunkerFSCSchedule not on server — the live VLSFO
        // Singapore index feed + stepped bracket table the staircase needs
        // has no procedure yet (agreement stores only a scalar surcharge
        // type/value). Surface a real "unavailable" state, never mock data.
        do {
            schedule = try await EusoTripAPI.shared.queryNoInput("vesselShipments.getBunkerFSCSchedule")
        } catch {
            schedule = nil
            scheduleGap = true
        }
        loading = false
    }
}

// MARK: - Staircase chart (the bespoke step-function archetype)

private struct StaircaseChart: View {
    let schedule: BunkerFSCSchedule
    let palette: Theme.Palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Plot insets mirror the SVG's 400×252 card geometry, scaled to
            // the live width. SVG: x 40..360 (of 400), baseline y=214,
            // top y=70 (of 252).
            let plotLeft   = w * (40.0 / 400.0)
            let plotRight  = w * (360.0 / 400.0)
            let baselineY  = h * (214.0 / 252.0)
            let topY       = h * (70.0 / 252.0)
            let plotW = plotRight - plotLeft
            let plotH = baselineY - topY

            let brackets = schedule.brackets ?? []
            let curIdx = schedule.currentBracketIdx ?? 0

            // Percent range for the y-axis. Anchor to the bracket table so
            // the steps land where the data says (not the SVG's frozen
            // 2/3.5/5/6/8 example).
            let pcts = brackets.map { $0.surchargePct }
            let minPct = (pcts.min() ?? 2) * 0.6
            let maxPct = (pcts.max() ?? 8) * 1.1
            let pctSpan = max(maxPct - minPct, 0.0001)

            // $/MT range for the x-axis derived from the bracket thresholds.
            let lows = brackets.map { $0.minUsdMt }
            let highs = brackets.compactMap { $0.maxUsdMt }
            let xMin = (lows.min() ?? 450) - 50
            let xMax = (highs.max() ?? 750) + 50
            let xSpan = max(xMax - xMin, 0.0001)

            let yFor: (Double) -> CGFloat = { pct in
                baselineY - CGFloat((pct - minPct) / pctSpan) * plotH
            }
            let xFor: (Double) -> CGFloat = { usd in
                plotLeft + CGFloat((usd - xMin) / xSpan) * plotW
            }

            ZStack {
                // Gridlines + y-axis % labels at each bracket level.
                ForEach(Array(brackets.enumerated()), id: \.offset) { _, b in
                    let y = yFor(b.surchargePct)
                    Path { p in
                        p.move(to: CGPoint(x: plotLeft, y: y))
                        p.addLine(to: CGPoint(x: plotRight, y: y))
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    Text(String(format: b.surchargePct.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f%%" : "%.1f", b.surchargePct))
                        .font(.system(size: 9)).monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                        .position(x: plotLeft - 14, y: y)
                }

                // Active bracket fill — gradient riser under the live step.
                if brackets.indices.contains(curIdx) {
                    let b = brackets[curIdx]
                    let x0 = xFor(b.minUsdMt)
                    let x1 = xFor(b.maxUsdMt ?? xMax)
                    let yTop = yFor(b.surchargePct)
                    Path { p in
                        p.addRect(CGRect(x: x0, y: yTop, width: x1 - x0, height: baselineY - yTop))
                    }
                    .fill(LinearGradient(
                        colors: [Brand.magenta.opacity(0.26), Brand.blue.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom))
                }

                // Neutral staircase (all steps) + active step in gradient.
                stairPath(brackets: brackets, active: false, curIdx: curIdx,
                          xFor: xFor, yFor: yFor)
                    .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                stairPath(brackets: brackets, active: true, curIdx: curIdx,
                          xFor: xFor, yFor: yFor)
                    .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                // Current index marker + dashed drop + flag.
                if let cur = schedule.indexUsdPerMt, brackets.indices.contains(curIdx) {
                    let mx = xFor(cur)
                    let my = yFor(brackets[curIdx].surchargePct)
                    Path { p in
                        p.move(to: CGPoint(x: mx, y: my))
                        p.addLine(to: CGPoint(x: mx, y: baselineY))
                    }
                    .stroke(Brand.magenta, style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.4))
                        .frame(width: 9, height: 9)
                        .position(x: mx, y: my)
                    Text("$\(Int(cur.rounded()))")
                        .font(.system(size: 9, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient.primary))
                        .position(x: mx, y: my - 18)
                }

                // X-axis baseline + threshold labels.
                Path { p in
                    p.move(to: CGPoint(x: plotLeft, y: baselineY))
                    p.addLine(to: CGPoint(x: plotRight, y: baselineY))
                }
                .stroke(palette.textSecondary.opacity(0.5), lineWidth: 1.4)
                ForEach(Array(brackets.enumerated()), id: \.offset) { _, b in
                    Text("\(Int(b.minUsdMt.rounded()))")
                        .font(.system(size: 9)).monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                        .position(x: xFor(b.minUsdMt), y: baselineY + 16)
                }
                Text("VLSFO BUNKER INDEX · $/MT")
                    .font(.system(size: 8.5)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .position(x: (plotLeft + plotRight) / 2, y: baselineY + 32)
            }
        }
        .padding(.leading, 4)
    }

    /// Build the stepped ladder polyline. When `active` is true only the
    /// riser into the current bracket is drawn (gradient); when false the
    /// rest of the ladder is drawn neutral.
    private func stairPath(brackets: [FSCBracket], active: Bool, curIdx: Int,
                           xFor: (Double) -> CGFloat, yFor: (Double) -> CGFloat) -> Path {
        Path { p in
            guard !brackets.isEmpty else { return }
            for (i, b) in brackets.enumerated() {
                let x0 = xFor(b.minUsdMt)
                let x1 = xFor(b.maxUsdMt ?? (b.minUsdMt + 100))
                let y  = yFor(b.surchargePct)
                let isActiveRiser = (i == curIdx)

                // Riser from the previous step's height up to this step.
                if i > 0 {
                    let prevY = yFor(brackets[i - 1].surchargePct)
                    if isActiveRiser == active {
                        p.move(to: CGPoint(x: x0, y: prevY))
                        p.addLine(to: CGPoint(x: x0, y: y))
                        p.addLine(to: CGPoint(x: x1, y: y))
                    }
                } else if !active {
                    // First tread (no riser) belongs to the neutral pass.
                    p.move(to: CGPoint(x: x0, y: y))
                    p.addLine(to: CGPoint(x: x1, y: y))
                }
            }
        }
    }
}

#Preview("685 · Vessel Bunker FSC Schedule · Night") {
    VesselBunkerFSCScheduleScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("685 · Vessel Bunker FSC Schedule · Light") {
    VesselBunkerFSCScheduleScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
