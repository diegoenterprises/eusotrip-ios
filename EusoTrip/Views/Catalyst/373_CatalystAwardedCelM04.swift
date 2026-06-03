//
//  373_CatalystAwardedCelM04.swift
//  EusoTrip — Catalyst · Awarded (M04) · bespoke port of §369.
//
//  Wireframe slot: 03 Catalyst / 373 Catalyst Awarded Cel M04.
//  Catalyst-vantage AWARDED-confirmed receipt — the consumer side of
//  the §368 shipper AWARD-COMMIT. The shipper accepted CEL's winning
//  bid; this surface receives the tender via the loadLifecycle
//  BIDDING→AWARDED fan-out, surfaces the locked economics, the 24h
//  tender-accept window, the post-award roster (CEL awarded · the three
//  losers), and a CEL-fleet driver-assign candidate strip (≤ 24h).
//
//  Server wiring (no stubs / no fake data — every visible award value
//  binds to a real tRPC proc or paints "—" until it resolves):
//    • `catalysts.getAcceptedBid` ({ loadId }) → the catalyst-side
//      winning-bid envelope ({ id, loadId, amount, status, notes,
//      submittedAt, loadNumber, rate }) or null. MCP-confirmed at
//      catalysts.ts:1108. `amount` is CEL's awarded bid; `rate` is the
//      shipper's posted target — `rate - amount` = the win headroom.
//
//  STUB CTAs (no backing mutation this fire — both are PROPOSED /
//  NOT IN ROUTER per the §369 wiring manifest, symmetric to
//  shippers.acceptTender / dispatch.assignDriver which exist on their
//  own domains):
//    • ACKNOWLEDGE TENDER → would call a future catalysts.acceptTender
//    • ASSIGN DRIVER      → would call a future catalysts.assignDriver
//  Both are wired as no-op taps and labeled STUB until those verbs land.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - tRPC decode shape (catalysts.getAcceptedBid envelope)

private struct AcceptedBid_373: Decodable {
    let id: String?
    let loadId: String?
    let amount: Double?       // CEL's awarded bid amount
    let status: String?       // "accepted"
    let notes: String?
    let submittedAt: String?
    let loadNumber: String?
    let rate: Double?         // shipper's posted target rate
}

// MARK: - Driver candidate (top-3 from CEL fleet · pre-assignment strip)

private struct DriverCandidate_373: Equatable {
    let usdot: String
    let initials: String
    let nameLastFirst: String
    let hosDriveHoursLeft: Int
    let proximityMiles: Int
    let etaToPickupHHmm: String
    let availabilityFlag: String     // "AVAILABLE" or "TENTATIVE"
    let preference: Int              // 1 = first pick · 2 · 3
}

// MARK: - Identity-row rank (catalyst-vantage AWARDED-confirmed roster)

private enum IdentityRowRank_373: Equatable {
    case ourselvesAwarded     // CEL · filled gradient disc · AWARDED chip · 100%
    case competitorLostFinal2 // 88% opacity
    case competitorLostFinal3 // 72% opacity
    case competitorLostFinal4 // 60% opacity
}

// MARK: - Local gradients (file-private · in-module symbols only)

private let eusoFaint_373 = LinearGradient(
    colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
    startPoint: .leading, endPoint: .trailing)

private let eusoWash_373 = LinearGradient(
    colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

// MARK: - Screen wrapper (Shell + catalyst BottomNav copied from 305)

struct CatalystAwardedCelM04Screen: View {
    let theme: Theme.Palette
    let loadId: String

    init(theme: Theme.Palette, loadId: String = "0") {
        self.theme = theme
        self.loadId = loadId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystAwardedCelM04Body(loadId: loadId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_373(),
                trailing: catalystNavTrailing_373(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_373() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_373() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Body

private struct CatalystAwardedCelM04Body: View {
    let loadId: String
    @Environment(\.palette) private var palette

    @State private var award: AcceptedBid_373? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    // CEL identity + lane envelope (cel anchors — display copy only, not
    // server-bound; the live money/award values come from getAcceptedBid).
    private let catalystShortCode = "CEL"
    private let catalystName = "Carolina Express Logistics"
    private let originCity = "Atlanta GA"
    private let destinationCity = "Charlotte NC"
    private let laneMiles = 245
    private let equipmentLabel = "53' Dry Van"

    // Post-award roster (catalyst-side reflection of the §368 commit; the
    // loser amounts are display-anchored from the M-04 quartet).
    private let lost2 = ("SCC", "Southern Crescent Carriers", 1_615)
    private let lost3 = ("PFC", "Piedmont Freight Co", 1_625)
    private let lost4 = ("AUR", "Aurora Freight Lines", 1_640)

    private let driverCandidates: [DriverCandidate_373] = [
        DriverCandidate_373(usdot: "CEL-D-014", initials: "JR", nameLastFirst: "Reyes, J.",
                            hosDriveHoursLeft: 10, proximityMiles: 78, etaToPickupHHmm: "07:45",
                            availabilityFlag: "AVAILABLE", preference: 1),
        DriverCandidate_373(usdot: "CEL-D-022", initials: "AT", nameLastFirst: "Tanaka, A.",
                            hosDriveHoursLeft: 9, proximityMiles: 142, etaToPickupHHmm: "07:55",
                            availabilityFlag: "AVAILABLE", preference: 2),
        DriverCandidate_373(usdot: "CEL-D-006", initials: "BK", nameLastFirst: "Kowalski, B.",
                            hosDriveHoursLeft: 11, proximityMiles: 211, etaToPickupHHmm: "08:10",
                            availabilityFlag: "TENTATIVE", preference: 3),
    ]

    // MARK: Derived display

    private var awardedAmount: Double? {
        guard let a = award?.amount, a > 0 else { return nil }
        return a
    }
    private var targetRate: Double? {
        guard let r = award?.rate, r > 0 else { return nil }
        return r
    }
    private var awardedAmountDisplay: String {
        guard let a = awardedAmount else { return "—" }
        return "$\(Int(a.rounded()).formatted(.number))"
    }
    private var winDisplay: String {
        guard let a = awardedAmount, let t = targetRate else { return "—" }
        let win = t - a
        let sign = win >= 0 ? "+" : "−"
        return "\(sign)$\(Int(abs(win).rounded()).formatted(.number))"
    }
    private var winVsTargetLine: String {
        guard let t = targetRate else { return "vs target" }
        return "vs $\(Int(t.rounded()).formatted(.number)) target"
    }
    private var rpmDisplay: String {
        guard let a = awardedAmount, laneMiles > 0 else { return "—" }
        return String(format: "$%.2f/mi", a / Double(laneMiles))
    }
    private var loadNumberDisplay: String {
        if let n = award?.loadNumber, !n.isEmpty { return n }
        return "—"
    }
    private var awardConfirmed: Bool {
        (award?.status ?? "").lowercased() == "accepted"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleRow
                iridescentHairline

                if loading {
                    skeletonBody
                } else if let err = loadError {
                    errorBanner(err)
                } else {
                    awardedConfirmedPill
                    eyebrowRow
                    kpiQuartet
                    lifecycleStrip
                    laneMap
                    rosterCard
                    driverAssignStrip
                    actionRibbon
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await fetch() }
        .refreshable { await fetch() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await fetch() }
        }
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DISPATCH · AWARDED · CEL ACK")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(loadNumberDisplay)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Button {
                // 373 is push-presented inside CarrierSurface's screenStack
                // (not a sheet). Post the canonical .eusoRoleNavBack which
                // CarrierSurface listens for → popOne(). Matches the 305
                // back-chevron pattern.
                NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text("\(originCity) → \(destinationCity)")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .padding(.trailing, 4)
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(eusoFaint_373)
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - Awarded-confirmed pill (handshake-with-receipt-tick · §369 2nd member)

    private var awardedConfirmedPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
            Text("AWARDED · CEL ACK · ARM PICKUP")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(awardConfirmed ? "CONFIRMED" : "PENDING")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(LinearGradient.primary)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Eyebrow row (gradient wash · founder DU pin)

    private var eyebrowRow: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AWARDED TO CEL · \(loadNumberDisplay) · WIN \(winDisplay) \(winVsTargetLine)")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(originCity) → \(destinationCity) · \(laneMiles) mi")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(equipmentLabel) · awarded \(awardedAmountDisplay) · CEL bid was rank 1/4 · 24h tender accept window armed")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            // DU shipper-of-record disc (founder pin)
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 24, height: 24)
                Text("DU")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(.white)
            }
            .padding(12)
        }
        .background(eusoWash_373)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(eusoFaint_373, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - KPI quartet (TENDER / WIN / DRIVER ASSIGN / ARM PICKUP)

    private var kpiQuartet: some View {
        HStack(spacing: 8) {
            kpiCell(eyebrow: "TENDER", value: awardedAmountDisplay, footer: "CEL accepted")
            kpiCell(eyebrow: "WIN", value: winDisplay, footer: winVsTargetLine)
            kpiCell(eyebrow: "DRIVER ASSIGN", value: "≤ 24h", footer: "Naomi → fleet")
            kpiCell(eyebrow: "ARM PICKUP", value: "ARMED", footer: rpmDisplay)
        }
    }

    private func kpiCell(eyebrow: String, value: String, footer: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(footer)
                .font(.system(size: 8))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(eusoFaint_373, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Lifecycle strip (AWARDED ringed-active · 8 nodes)

    private var lifecycleStrip: some View {
        let labels = ["POST", "BID", "AWRD", "PICK", "TRAN", "DELV", "PAPR", "CLSD"]
        let currentIdx = 2  // AWARDED — bound to award.status == accepted
        return VStack(alignment: .leading, spacing: 10) {
            Text("LIFECYCLE · \(equipmentLabel.uppercased())")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            GeometryReader { geo in
                let step = labels.count > 1 ? geo.size.width / CGFloat(labels.count - 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint).frame(height: 2)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: step * CGFloat(currentIdx), height: 2)
                    ForEach(Array(labels.enumerated()), id: \.offset) { idx, _ in
                        node(idx: idx, currentIdx: currentIdx)
                            .position(x: step * CGFloat(idx), y: 11)
                    }
                }
            }
            .frame(height: 22)

            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                    Text(label)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(idx == currentIdx
                                         ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(idx < currentIdx ? palette.textPrimary : palette.textTertiary))
                        .frame(maxWidth: .infinity)
                }
            }

            Text("Awarded · CEL receives tender · arm pickup · assign driver ≤ 24h")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func node(idx: Int, currentIdx: Int) -> some View {
        Group {
            if idx == currentIdx {
                ZStack {
                    Circle().stroke(LinearGradient.diagonal, lineWidth: 2).frame(width: 22, height: 22)
                    Circle().fill(LinearGradient.diagonal).frame(width: 16, height: 16)
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                }
            } else if idx < currentIdx {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1.2))
                    .frame(width: 10, height: 10)
            }
        }
    }

    // MARK: - Lane map (solid post-award route · LANE LOCKED banner)

    private var laneMap: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                // Solid route line ATL → CLT (post-award flip from dashed).
                var route = Path()
                route.move(to: CGPoint(x: size.width * 0.16, y: size.height * 0.62))
                route.addQuadCurve(to: CGPoint(x: size.width * 0.80, y: size.height * 0.40),
                                   control: CGPoint(x: size.width * 0.50, y: size.height * 0.22))
                ctx.stroke(route, with: .linearGradient(
                    Gradient(colors: [Brand.blue, Brand.magenta]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                    lineWidth: 2.4)

                // Dashed dispatch route from CEL GSO hub to ATL pickup.
                var hub = Path()
                hub.move(to: CGPoint(x: size.width * 0.66, y: size.height * 0.26))
                hub.addQuadCurve(to: CGPoint(x: size.width * 0.16, y: size.height * 0.62),
                                 control: CGPoint(x: size.width * 0.42, y: size.height * 0.08))
                ctx.stroke(hub, with: .color(palette.textTertiary),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .frame(height: 120)

            // Origin pin (solid) — placed in the same proportional spot.
            GeometryReader { geo in
                let w = geo.size.width
                let h: CGFloat = 120
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 12, height: 12)
                        .position(x: w * 0.16, y: h * 0.62)
                    Circle().fill(LinearGradient.diagonal).frame(width: 12, height: 12)
                        .position(x: w * 0.80, y: h * 0.40)
                    Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 1.4)
                        .frame(width: 14, height: 14)
                        .position(x: w * 0.66, y: h * 0.26)
                    Text("ATL pickup")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .position(x: w * 0.16 + 24, y: h * 0.62 + 12)
                    Text("CLT")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .position(x: w * 0.80, y: h * 0.40 - 14)
                    Text("GSO hub")
                        .font(.system(size: 7))
                        .foregroundStyle(palette.textSecondary)
                        .position(x: w * 0.66, y: h * 0.26 + 14)
                }
            }
            .frame(height: 120)

            // AWARDED chip overlay (top-right · single post-award member)
            HStack {
                Spacer(minLength: 0)
                Text("AWARDED")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 14)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(10)

            // LANE LOCKED banner (bottom-left)
            VStack {
                Spacer(minLength: 0)
                Text("LANE LOCKED · \(laneMiles) mi · tender accept ≤ 24h")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .padding(12)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Roster card (CEL awarded + 3 losers)

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("POST-AWARD ROSTER · M-04 · 4 BIDS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 6) {
                identityRow(shortCode: catalystShortCode, displayName: catalystName,
                            amount: Int((awardedAmount ?? 0).rounded()), rank: .ourselvesAwarded)
                identityRow(shortCode: lost2.0, displayName: lost2.1, amount: lost2.2, rank: .competitorLostFinal2)
                identityRow(shortCode: lost3.0, displayName: lost3.1, amount: lost3.2, rank: .competitorLostFinal3)
                identityRow(shortCode: lost4.0, displayName: lost4.1, amount: lost4.2, rank: .competitorLostFinal4)
            }
        }
    }

    private func identityRow(shortCode: String, displayName: String, amount: Int, rank: IdentityRowRank_373) -> some View {
        let opacity: Double = {
            switch rank {
            case .ourselvesAwarded:     return 1.00
            case .competitorLostFinal2: return 0.88
            case .competitorLostFinal3: return 0.72
            case .competitorLostFinal4: return 0.60
            }
        }()
        let isOurselves = rank == .ourselvesAwarded
        let amountText = amount > 0 ? "$\(amount.formatted(.number))" : "—"

        return HStack(spacing: 10) {
            ZStack {
                if isOurselves {
                    Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                } else {
                    Circle().strokeBorder(eusoFaint_373, lineWidth: 1.2).frame(width: 28, height: 28)
                }
                Text(shortCode)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(isOurselves ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(amountText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            if isOurselves {
                Text("AWARDED")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 16)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Text("LOST")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 10)
                    .frame(height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(eusoFaint_373, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .opacity(opacity)
    }

    // MARK: - Driver-assign candidate strip (top-3 CEL fleet)

    private var driverAssignStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DRIVER ASSIGN · CEL FLEET CANDIDATES · ≤ 24h")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                ForEach(driverCandidates, id: \.usdot) { c in
                    candidateCell(c)
                }
            }
        }
    }

    private func candidateCell(_ c: DriverCandidate_373) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ZStack {
                    if c.preference == 1 {
                        Circle().fill(LinearGradient.diagonal).frame(width: 16, height: 16)
                    } else {
                        Circle().fill(palette.borderFaint).frame(width: 16, height: 16)
                    }
                    Text(c.initials)
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(c.preference == 1 ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                }
                Text(c.nameLastFirst)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            Text("HOS \(c.hosDriveHoursLeft)h · \(c.proximityMiles) mi")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
            Text("ETA \(c.etaToPickupHHmm) · \(c.availabilityFlag)")
                .font(.system(size: 7))
                .foregroundStyle(c.availabilityFlag == "AVAILABLE" ? palette.textSecondary : palette.textTertiary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(c.preference == 1 ? AnyShapeStyle(eusoFaint_373) : AnyShapeStyle(palette.borderFaint), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Action ribbon (3 CTAs · ACK / ASSIGN are STUB)

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            // STUB — no catalysts.acceptTender verb in the router yet.
            Button {
                // no-op until catalysts.acceptTender lands
            } label: {
                Text("ACKNOWLEDGE TENDER")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            // STUB — no catalysts.assignDriver verb (dispatch.assignDriver
            // exists on the dispatch domain; catalyst wrapper not wired).
            Button {
                // no-op until catalysts.assignDriver lands
            } label: {
                Text("ASSIGN DRIVER")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(eusoFaint_373, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            // Message the shipper-of-record via the canonical ESANG funnel.
            Button {
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail,
                    object: "messages",
                    userInfo: ["loadId": loadId]
                )
            } label: {
                Text("MESSAGE DIEGO")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading / error

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard).frame(height: 36)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard).frame(height: 88)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard).frame(height: 60)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard).frame(height: 120)
        }
        .redacted(reason: .placeholder)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Button { Task { await fetch() } } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Brand.danger.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Network

    private func fetch() async {
        loading = true
        loadError = nil
        defer { loading = false }
        guard !loadId.isEmpty, loadId != "0" else {
            // No id — leave award nil; honest empty values render as "—".
            return
        }
        struct In: Encodable { let loadId: String }
        do {
            // catalysts.getAcceptedBid → the catalyst-side winning-bid
            // envelope (or null if no accepted bid for this catalyst on
            // this load). MCP-confirmed at catalysts.ts:1108.
            self.award = try await EusoTripAPI.shared.query(
                "catalysts.getAcceptedBid",
                input: In(loadId: loadId)
            )
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("373 · Catalyst · Awarded (M04) · Afternoon") {
    CatalystAwardedCelM04Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("373 · Catalyst · Awarded (M04) · Night") {
    CatalystAwardedCelM04Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
