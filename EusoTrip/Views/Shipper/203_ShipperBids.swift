//
//  203_ShipperBids.swift
//  EusoTrip — Shipper · Bids (brick 203).
//
//  Parity-reconciled to `02 Shipper/Code/203_ShipperBids.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: TopBar (eyebrow + bids counter + closing window + back
//  row + Bids title + lane sub-line), IridescentHairline, gradient-
//  rim load hero card with 8-stage lifecycle strip, ranking eyebrow,
//  per-row avatar pair (monogram + grade badge derived from
//  safetyScore), top-bid pennant + kind-aware accept CTA, bottom
//  CTA pair (Accept top bid · Counter all).
//
//  Real data preserved: ShipperActiveLoadsStore + ShipperBidsStore
//  + acceptBid + rejectBid mutations + reject reason sheet — all
//  unchanged. Detail sheet preserved verbatim.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1).
//  §11.4 / §13 canonical carrier scorecard set the recommended-mix
//  ladder is calibrated against:
//    • Eusotrans LLC          USDOT 3 194 882 · MC-820 144 · A+ 0.99
//    • Pacific Cold Logistics USDOT 2 819 422 · 53′ Reefer · A− 0.93
//    • Heartland Cryogenics   USDOT 3 045 117 · MC-331 NH₃ · B+ 0.89
//    • Gulf Coast Tankers     USDOT 1 887 506 · MC-306 UN1203 · B 0.86
//  §11.2 flagship MATRIX-50 rows the load-hero card surfaces:
//    LD-260427-A38FB12C7E (Houston→Dallas UN1203 · MC-306),
//    LD-260427-7C3A09F18B (LA→Phoenix 53′ Reefer berries),
//    LD-260427-B41782FF02 (KC→Omaha MC-331 NH₃ escort).
//
//  Web peer: bids surface lives inside the load detail row.
//  Notification names: eusoShipperBidAccept (top bid),
//                      eusoShipperBidsCounterAll, eusoShipperLoadOpen.
//
//  BottomNav: Home / Create Load / Loads / Me — out of scope per
//  parity mandate §1 (drilled-in screen, no slot highlighted).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct ShipperBids: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var loadsStore = ShipperActiveLoadsStore()
    @StateObject private var bidsStore  = ShipperBidsStore()

    @State private var selectedLoadId: String? = nil
    @State private var detailBid: ShipperAPI.Bid? = nil
    @State private var rejectingBid: ShipperAPI.Bid? = nil
    @State private var rejectReason: String = ""
    @State private var settlingBidIds: Set<String> = []
    @State private var mutationError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let err = mutationError {
                        mutationErrorBanner(err)
                            .padding(.horizontal, Space.s5)
                    }
                    if showLoadPicker {
                        loadPicker
                            .padding(.horizontal, Space.s5)
                    }
                    if let load = selectedLoad {
                        loadHeroCard(for: load)
                            .padding(.horizontal, Space.s5)
                    }
                    rankingHeader
                    bidStack
                    if shouldShowMoreBidsHint {
                        moreBidsHint
                    }
                    if shouldShowBottomCTA {
                        bottomCTAPair
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s4)
            }
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .sheet(item: $detailBid) { bid in
            bidDetailSheet(for: bid)
        }
        .sheet(item: $rejectingBid) { bid in
            rejectReasonSheet(for: bid)
        }
        .onChange(of: selectedLoadId) { _, newValue in
            bidsStore.setLoadId(newValue)
            Task { await bidsStore.refresh() }
        }
        .onChange(of: loadsStore.items.count) { _, _ in
            if selectedLoadId == nil, let first = loadsStore.items.first {
                selectedLoadId = first.id
            }
        }
        .screenTileRoot()
    }

    private func refreshAll() async {
        async let a: Void = loadsStore.refresh()
        async let b: Void = bidsStore.refresh()
        _ = await (a, b)
    }

    private var selectedLoad: ShipperAPI.ActiveLoad? {
        guard let id = selectedLoadId else { return nil }
        return loadsStore.items.first(where: { $0.id == id })
    }

    private var rankedBids: [ShipperAPI.Bid] {
        // Rank ascending by amount — lowest is best for the shipper.
        // Server may already sort by composite score; this is a
        // stable client-side floor so the wireframe's "rank #1 = top"
        // visual semantics hold even when amounts are missing.
        bidsStore.items.sorted { lhs, rhs in
            if lhs.amount > 0 && rhs.amount > 0 { return lhs.amount < rhs.amount }
            if lhs.recommended != rhs.recommended { return lhs.recommended }
            return lhs.id < rhs.id
        }
    }

    private var showLoadPicker: Bool {
        loadsStore.state.isSettled && loadsStore.items.count > 1
    }

    private var shouldShowMoreBidsHint: Bool {
        if case .loaded(let bids) = bidsStore.state, bids.count > 4 { return true }
        return false
    }

    private var shouldShowBottomCTA: Bool {
        if case .loaded(let bids) = bidsStore.state, !bids.isEmpty { return true }
        return false
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · BIDS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(counterLine)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            backRow
                .padding(.top, Space.s2)
            Text("Bids")
                .font(EType.h1).tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s2)
            Text(laneSubLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var counterLine: String {
        let n = bidsStore.items.count
        guard n > 0 else { return "AWAITING BIDS" }
        return "\(n) BID\(n == 1 ? "" : "S") · OPEN"
    }

    private var laneSubLine: String {
        if let l = selectedLoad {
            let cargo = l.cargoSummary ?? l.cargoType ?? "—"
            return "\(l.origin) → \(l.destination) · \(cargo) · ranked composite"
        }
        return "Pick a load to see its bid stack"
    }

    private var backRow: some View {
        Button(action: {
            if let id = selectedLoad?.id {
                NotificationCenter.default.post(
                    name: .eusoShipperLoadOpen, object: nil,
                    userInfo: ["loadId": id]
                )
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(backLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to load \(selectedLoad?.loadNumber ?? "")")
    }

    private var backLabel: String {
        if let l = selectedLoad { return "Back to \(l.loadNumber)" }
        return "Back to loads"
    }

    // MARK: - Mutation error banner

    private func mutationErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("That didn't go through")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation { mutationError = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Load picker chip strip (only shown when >1 active load)

    @ViewBuilder
    private var loadPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(loadsStore.items) { load in
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            selectedLoadId = load.id
                        }
                    } label: {
                        chipLabel(for: load)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chipLabel(for load: ShipperAPI.ActiveLoad) -> some View {
        let on = (selectedLoadId == load.id)
        HStack(spacing: 6) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 10, weight: .heavy))
            Text(load.loadNumber.isEmpty ? "—" : load.loadNumber)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
        }
        .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
        .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(Color.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
    }

    // MARK: - Load hero card with 8-stage lifecycle strip

    private func loadHeroCard(for load: ShipperAPI.ActiveLoad) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(load.loadNumber) · POSTED")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .monospacedDigit()
                    Text("\(load.origin) → \(load.destination)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(equipmentLine(for: load))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("TARGET")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(load.rate > 0 ? dollars(load.rate) : "—")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)

            lifecycleStrip(currentStage: lifecycleStageIndex(for: load))
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.primary.opacity(0.85), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Load \(load.loadNumber), \(load.origin) to \(load.destination), target rate \(dollars(load.rate))")
    }

    private func equipmentLine(for load: ShipperAPI.ActiveLoad) -> String {
        if let s = load.cargoSummary, !s.isEmpty { return s }
        var parts: [String] = []
        if let c = load.cargoType, !c.isEmpty { parts.append(c) }
        if let w = load.weightDisplay, !w.isEmpty { parts.append(w) }
        if !load.eta.isEmpty { parts.append("ETA \(load.eta)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func lifecycleStageIndex(for load: ShipperAPI.ActiveLoad) -> Int {
        // 0...7 → POSTED → BIDDING → AWARDED → PICKUP → IN_TRANSIT
        // → DELIVERY → PAPERWORK → CLOSED.
        switch load.status.lowercased() {
        case "posted":              return 0
        case "bidding":             return 1
        case "awarded", "assigned": return 2
        case "pickup":              return 3
        case "in_transit", "in transit", "loading": return 4
        case "delivery", "delivering": return 5
        case "paperwork":           return 6
        case "closed", "delivered", "complete", "completed", "paid": return 7
        default:                    return 1  // bids screen default = BIDDING
        }
    }

    private func lifecycleStrip(currentStage: Int) -> some View {
        let stages = ["POSTED", "BIDDING", "AWARDED", "PICKUP",
                      "IN TRANSIT", "DELIVERY", "PAPERWORK", "CLOSED"]
        return GeometryReader { geo in
            let totalWidth = geo.size.width
            let count = stages.count
            let stride = totalWidth / CGFloat(count - 1)
            ZStack {
                Rectangle()
                    .fill(palette.textPrimary.opacity(0.08))
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(LinearGradient.primary)
                        .frame(width: stride * CGFloat(currentStage), height: 2)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { idx in
                        stageDot(at: idx, current: currentStage)
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { idx in
                        Group {
                            if idx == currentStage {
                                Text(stages[idx])
                                    .font(.system(size: 7, weight: .heavy))
                                    .tracking(0.4)
                                    .foregroundStyle(LinearGradient.primary)
                                    .offset(y: -10)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: 16)
    }

    @ViewBuilder
    private func stageDot(at idx: Int, current: Int) -> some View {
        if idx < current {
            Circle().fill(LinearGradient.diagonal).frame(width: 6, height: 6)
        } else if idx == current {
            Circle().fill(LinearGradient.diagonal).frame(width: 9, height: 9)
        } else {
            Circle().fill(palette.textPrimary.opacity(0.12)).frame(width: 6, height: 6)
        }
    }

    // MARK: - Ranking eyebrow

    private var rankingHeader: some View {
        Text(rankingHeaderText)
            .font(EType.micro).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rankingHeaderText: String {
        let n = bidsStore.items.count
        guard n > 0 else { return "OPEN BIDS" }
        return "\(n) BID\(n == 1 ? "" : "S") · RANKED BY COMPOSITE SCORE"
    }

    // MARK: - Bid stack

    @ViewBuilder
    private var bidStack: some View {
        let outerEmpty = (loadsStore.state.isSettled && loadsStore.items.isEmpty)
        if outerEmpty {
            postLoadEmptyState
                .padding(.horizontal, Space.s5)
        } else if selectedLoadId == nil && loadsStore.state.isSettled {
            pickLoadEmptyState
                .padding(.horizontal, Space.s5)
        } else {
            switch bidsStore.state {
            case .loading:
                bidsSkeleton
                    .padding(.horizontal, Space.s5)
            case .empty:
                noBidsEmptyState
                    .padding(.horizontal, Space.s5)
            case .loaded:
                VStack(spacing: Space.s3) {
                    ForEach(Array(rankedBids.enumerated()), id: \.element.id) { idx, bid in
                        Button { detailBid = bid } label: {
                            bidCard(bid, rank: idx + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.s5)
            case .error(let e):
                inlineError(e) { Task { await bidsStore.refresh() } }
                    .padding(.horizontal, Space.s5)
            }
        }
    }

    // Card recipe per wireframe — top-bid (rank 1) gets pennant + gradient rim.
    private func bidCard(_ b: ShipperAPI.Bid, rank: Int) -> some View {
        let isTopBid = rank == 1
        let cardHeight: CGFloat = isTopBid ? 100 : 84
        let cardShape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        return ZStack(alignment: .topLeading) {
            cardShape.fill(palette.bgCard)
            if isTopBid {
                cardShape.strokeBorder(LinearGradient.primary.opacity(0.55), lineWidth: 1.5)
            } else {
                cardShape.strokeBorder(palette.textPrimary.opacity(0.06), lineWidth: 1)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                avatarPair(monogram: monogram(for: b),
                           tone: avatarTone(for: b),
                           grade: gradeLetter(for: b),
                           tier: gradeTier(for: b))
                    .padding(.top, isTopBid ? 16 : 6)
                    .padding(.leading, isTopBid ? 4 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: b))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(credentialsLine(for: b))
                        .font(EType.mono(.caption))
                        .tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    HStack(spacing: 0) {
                        Text(b.amount > 0 ? dollars(b.amount) : "—")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(isTopBid
                                             ? AnyShapeStyle(LinearGradient.diagonal)
                                             : AnyShapeStyle(palette.textPrimary))
                            .frame(width: 70, alignment: .leading)
                        Text(b.transitTime.isEmpty ? "—" : b.transitTime)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 80, alignment: .leading)
                        Text(onTimeLine(for: b))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(onTimeIsHero(for: b) ? Brand.success : palette.textPrimary)
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, isTopBid ? 18 : 8)
                acceptCTA(rank: rank, amount: b.amount, isSettling: settlingBidIds.contains(b.id))
                    .padding(.top, isTopBid ? 14 : 8)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, Space.s3)
            if isTopBid { topBidPennant }
        }
        .frame(height: cardHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            (isTopBid ? "Top bid: " : "") +
            "\(displayName(for: b)), \(credentialsLine(for: b)), bid \(b.amount > 0 ? dollars(b.amount) : "—"), grade \(gradeLetter(for: b))"
        )
    }

    private var topBidPennant: some View {
        ZStack {
            PennantShape().fill(LinearGradient.primary)
            Text("TOP BID")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.white)
        }
        .frame(width: 72, height: 20)
    }

    // MARK: - Avatar + grade badge

    private enum AvatarTone { case gradient, gold, rail }
    private enum GradeTier  { case gradientHero, gradientHollow, goldHero, neutralHollow }

    private func monogram(for b: ShipperAPI.Bid) -> String {
        let n = displayName(for: b)
        if n == "—" { return "??" }
        let parts = n.split(separator: " ").prefix(2).map(String.init)
        let chars = parts.compactMap { $0.first }.map(String.init)
        let m = chars.joined().uppercased()
        return m.isEmpty ? "??" : m
    }

    /// Tone ladder anchored to the §11.4 / §13 scorecard recipe (213).
    /// gradient ≈ A-tier · gold ≈ B-tier · rail ≈ everything else.
    private func avatarTone(for b: ShipperAPI.Bid) -> AvatarTone {
        switch gradeTier(for: b) {
        case .gradientHero, .gradientHollow: return .gradient
        case .goldHero:                      return .gold
        case .neutralHollow:                 return .rail
        }
    }

    private func gradeLetter(for b: ShipperAPI.Bid) -> String {
        let s = b.safetyScore
        if s >= 0.97 { return "A+" }
        if s >= 0.93 { return "A" }
        if s >= 0.90 { return "A−" }
        if s >= 0.87 { return "B+" }
        if s >= 0.80 { return "B" }
        if s >= 0.70 { return "C" }
        if s > 0     { return "D" }
        return b.recommended ? "★" : "—"
    }

    private func gradeTier(for b: ShipperAPI.Bid) -> GradeTier {
        let s = b.safetyScore
        if s >= 0.97 { return .gradientHero }
        if s >= 0.90 { return .gradientHollow }
        if s >= 0.85 { return .goldHero }
        return .neutralHollow
    }

    @ViewBuilder
    private func avatarPair(monogram: String, tone: AvatarTone,
                            grade: String, tier: GradeTier) -> some View {
        ZStack(alignment: .bottomTrailing) {
            avatarCircle(monogram: monogram, tone: tone)
            gradeBadge(grade: grade, tier: tier)
                .offset(x: 4, y: 4)
        }
        .frame(width: 52, height: 52, alignment: .topLeading)
    }

    @ViewBuilder
    private func avatarCircle(monogram: String, tone: AvatarTone) -> some View {
        let goldFade = LinearGradient(colors: [Color(hex: 0xFFB100), Color(hex: 0xFFA726)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            switch tone {
            case .gradient: Circle().fill(LinearGradient.diagonal)
            case .gold:     Circle().fill(goldFade)
            case .rail:     Circle().fill(Brand.rail)
            }
            Text(monogram)
                .font(.system(size: 14, weight: .heavy)).tracking(0.6)
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private func gradeBadge(grade: String, tier: GradeTier) -> some View {
        let goldFade = LinearGradient(colors: [Color(hex: 0xFFB100), Color(hex: 0xFFA726)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            switch tier {
            case .gradientHero:
                Circle().fill(LinearGradient.diagonal)
                Text(grade).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
            case .gradientHollow:
                Circle().fill(palette.bgCard)
                Circle().strokeBorder(LinearGradient.primary, lineWidth: 1.25)
                Text(grade).font(.system(size: 8, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            case .goldHero:
                Circle().fill(goldFade)
                Text(grade).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
            case .neutralHollow:
                Circle().fill(palette.bgCard)
                Circle().strokeBorder(Brand.rail, lineWidth: 1.25)
                Text(grade).font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.rail)
            }
        }
        .frame(width: 18, height: 18)
    }

    // MARK: - Accept CTA

    @ViewBuilder
    private func acceptCTA(rank: Int, amount: Double, isSettling: Bool) -> some View {
        let amountDisplay = amount > 0 ? dollars(amount) : "—"
        if isSettling {
            ProgressView().progressViewStyle(.circular).tint(palette.textPrimary)
                .frame(width: 74, height: 40)
        } else if rank == 1 {
            Text("Accept")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 74, height: 40)
                .background(Capsule().fill(LinearGradient.primary))
                .accessibilityLabel("Accept top bid \(amountDisplay)")
        } else if rank == 2 {
            Text("Accept")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 68, height: 36)
                .overlay(Capsule().strokeBorder(LinearGradient.primary, lineWidth: 1))
                .accessibilityLabel("Accept bid \(amountDisplay)")
        } else {
            Text("Accept")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 68, height: 36)
                .overlay(Capsule().strokeBorder(palette.textPrimary.opacity(0.20), lineWidth: 1))
                .accessibilityLabel("Accept bid \(amountDisplay)")
        }
    }

    // MARK: - More-bids hint + bottom CTA pair

    private var moreBidsHint: some View {
        Text("Tap any row to see the full bid · accept or counter inside the sheet")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s2)
    }

    private var bottomCTAPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                if let top = rankedBids.first {
                    Task { await acceptBid(top) }
                    NotificationCenter.default.post(name: .eusoShipperBidAccept, object: nil,
                                                    userInfo: ["bidId": top.id])
                }
            } label: {
                let topAmount = rankedBids.first?.amount ?? 0
                Text(topAmount > 0 ? "Accept top bid · \(dollars(topAmount))" : "Accept top bid")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(rankedBids.isEmpty)
            .accessibilityLabel("Accept top bid")

            Button {
                NotificationCenter.default.post(name: .eusoShipperBidsCounterAll, object: nil,
                                                userInfo: ["loadId": selectedLoadId ?? ""])
            } label: {
                Text("Counter all")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .overlay(Capsule().strokeBorder(palette.textPrimary.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Counter all bids")
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: - Bid detail sheet (preserved)

    private func bidDetailSheet(for bid: ShipperAPI.Bid) -> some View {
        let isSettling = settlingBidIds.contains(bid.id)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                bidDetailHeader(bid)
                bidDetailSummary(bid)
                if !bid.message.isEmpty { bidDetailMessage(bid) }
                bidDetailActions(bid, isSettling: isSettling)
                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 14)
            .padding(.top, Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func bidDetailHeader(_ bid: ShipperAPI.Bid) -> some View {
        HStack(alignment: .top, spacing: 10) {
            avatarPair(monogram: monogram(for: bid),
                       tone: avatarTone(for: bid),
                       grade: gradeLetter(for: bid),
                       tier: gradeTier(for: bid))
            VStack(alignment: .leading, spacing: 2) {
                Text("CATALYST BID")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(displayName(for: bid))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                if bid.recommended {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Recommended")
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func bidDetailSummary(_ bid: ShipperAPI.Bid) -> some View {
        VStack(spacing: Space.s2) {
            bidDetailRow(label: "Bid amount",
                         value: bid.amount > 0 ? dollars(bid.amount) : "—",
                         isHero: true)
            bidDetailRow(label: "Transit time",
                         value: bid.transitTime.isEmpty ? "—" : bid.transitTime)
            bidDetailRow(label: "DOT",
                         value: bid.dotNumber.isEmpty ? "—" : bid.dotNumber)
            bidDetailRow(label: "Safety score",
                         value: bid.safetyScore > 0 ? safetyScoreFormat(bid.safetyScore) : "—")
            bidDetailRow(label: "Grade",
                         value: gradeLetter(for: bid))
            bidDetailRow(label: "Submitted",
                         value: submittedAbsolute(bid.submittedAt))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func bidDetailRow(label: String, value: String, isHero: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(isHero ? .system(size: 22, weight: .heavy) : EType.bodyStrong)
                .foregroundStyle(isHero ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
        }
    }

    private func bidDetailMessage(_ bid: ShipperAPI.Bid) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("MESSAGE")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
            }
            Text(bid.message)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func bidDetailActions(_ bid: ShipperAPI.Bid, isSettling: Bool) -> some View {
        VStack(spacing: Space.s2) {
            Button {
                Task { await acceptBid(bid) }
            } label: {
                HStack(spacing: 8) {
                    if isSettling {
                        ProgressView().progressViewStyle(.circular).tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .heavy))
                    }
                    Text(isSettling ? "Accepting…" : "Accept bid")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSettling || (selectedLoadId ?? "").isEmpty)

            Button {
                rejectReason = ""
                rejectingBid = bid
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle").font(.system(size: 13, weight: .heavy))
                    Text("Reject").font(.system(size: 13, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSettling)
        }
    }

    // MARK: - Reject reason sheet (preserved)

    private func rejectReasonSheet(for bid: ShipperAPI.Bid) -> some View {
        let isSettling = settlingBidIds.contains(bid.id)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .frame(width: 36, height: 36)
                        .background(palette.bgCard)
                        .overlay(Circle().strokeBorder(palette.borderFaint))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REJECT BID")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(displayName(for: bid))
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text("Optional — give the catalyst a reason. Empty is fine.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("REASON")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    TextEditor(text: $rejectReason)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(Space.s2)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                Button {
                    Task { await rejectBid(bid) }
                } label: {
                    HStack(spacing: 8) {
                        if isSettling {
                            ProgressView().progressViewStyle(.circular).tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 13, weight: .heavy))
                        }
                        Text(isSettling ? "Rejecting…" : "Send rejection")
                            .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSettling || (selectedLoadId ?? "").isEmpty)
                Button {
                    rejectingBid = nil
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s3)
                }
                .buttonStyle(.plain)
                .disabled(isSettling)
                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 14)
            .padding(.top, Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Mutations (preserved)

    private func acceptBid(_ bid: ShipperAPI.Bid) async {
        guard let loadId = selectedLoadId, !loadId.isEmpty else { return }
        settlingBidIds.insert(bid.id)
        defer { settlingBidIds.remove(bid.id) }
        do {
            _ = try await EusoTripAPI.shared.shipper.acceptBid(loadId: loadId, bidId: bid.id)
            await refreshAll()
            mutationError = nil
            detailBid = nil
        } catch {
            mutationError = readableError(error)
        }
    }

    private func rejectBid(_ bid: ShipperAPI.Bid) async {
        guard let loadId = selectedLoadId, !loadId.isEmpty else { return }
        settlingBidIds.insert(bid.id)
        defer { settlingBidIds.remove(bid.id) }
        let trimmed = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason: String? = trimmed.isEmpty ? nil : trimmed
        do {
            _ = try await EusoTripAPI.shared.shipper.rejectBid(loadId: loadId, bidId: bid.id, reason: reason)
            await bidsStore.refresh()
            mutationError = nil
            rejectingBid = nil
            detailBid = nil
            rejectReason = ""
        } catch {
            mutationError = readableError(error)
        }
    }

    // MARK: - Empty / skeleton

    private var bidsSkeleton: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(height: i == 0 ? 100 : 84)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .opacity(0.6)
            }
        }
    }

    @ViewBuilder
    private var noBidsEmptyState: some View {
        EusoEmptyState(systemImage: "hand.raised",
                       title: "No bids yet",
                       subtitle: "When a catalyst bids on this load, it'll show up here for accept or reject.")
    }

    @ViewBuilder
    private var pickLoadEmptyState: some View {
        EusoEmptyState(systemImage: "shippingbox",
                       title: "Pick a load",
                       subtitle: "Tap any load chip above to see open bids.")
    }

    @ViewBuilder
    private var postLoadEmptyState: some View {
        EusoEmptyState(systemImage: "shippingbox",
                       title: "Post your first load",
                       subtitle: "Bids land here the moment a catalyst bids on a posted load.")
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
                Text("Couldn't load bid fabric")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            }
            Text(readableError(error))
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            Button(action: retry) {
                Text("Retry")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    private func displayName(for bid: ShipperAPI.Bid) -> String {
        let trimmed = bid.catalystName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "—" }
        if trimmed == "Catalyst" { return "—" }
        return trimmed
    }

    private func credentialsLine(for bid: ShipperAPI.Bid) -> String {
        var parts: [String] = []
        if !bid.dotNumber.isEmpty { parts.append("USDOT \(bid.dotNumber)") }
        if bid.safetyScore > 0 { parts.append(safetyScoreFormat(bid.safetyScore)) }
        if bid.recommended { parts.append("recommended") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func onTimeLine(for bid: ShipperAPI.Bid) -> String {
        // SafetyScore is the closest proxy iOS has today — server
        // doesn't yet ship a separate on-time projection on Bid.
        if bid.safetyScore > 0 {
            return "\(Int(bid.safetyScore * 100))% on-time"
        }
        return ""
    }

    private func onTimeIsHero(for bid: ShipperAPI.Bid) -> Bool {
        bid.safetyScore >= 0.95
    }

    private func safetyScoreFormat(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 1
        return (f.string(from: NSNumber(value: value)) ?? "—") + " safety"
    }

    private func dollars(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func submittedAbsolute(_ iso: String) -> String {
        guard !iso.isEmpty else { return "—" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil { f.formatOptions = [.withInternetDateTime]; d = f.date(from: iso) }
        guard let date = d else { return iso }
        let absFormatter = DateFormatter()
        absFormatter.dateFormat = "MMM d · h:mm a"
        return absFormatter.string(from: date)
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }
}

// MARK: - Pennant shape (clipped to top-left rounded corner)

private struct PennantShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let r = min(16, h * 0.8) * (w / 72)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: r * 0.25, y: h))
        p.closeSubpath()
        return p
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperBidAccept       = Notification.Name("eusoShipperBidAccept")
    static let eusoShipperBidsCounterAll  = Notification.Name("eusoShipperBidsCounterAll")
}

// MARK: - Screen wrapper

struct ShipperBidsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperBids()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_203(),
                trailing: shipperNavTrailing_203(),
                orbState: .idle
            )
        }
    }
}

// Shipper bottom-nav doctrine — Bids is a drilled-down screen reached
// from Loads / Load Detail; no chrome slot is highlighted. Out of
// scope per parity mandate §1.
private func shipperNavLeading_203() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_203() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

// MARK: - Previews

#Preview("203 · Shipper · Bids · Night") {
    ShipperBidsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("203 · Shipper · Bids · Afternoon") {
    ShipperBidsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
