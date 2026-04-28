//
//  203_ShipperBids.swift
//  EusoTrip — Shipper · Bids (brick 203).
//
//  Fourth brick on the Shipper role track (200s). Reached via
//  drill-in from 201 ShipperLoads / 205 ShipperLoadDetail (the
//  shipper bottom-nav doctrine — Home / Create Load / ESANG / Loads
//  / Me — does not promote Bids to a chrome slot; it lives one
//  level deeper). Presents every open bid the shipper's posted
//  loads are receiving — with single-tap Accept and Reject
//  gestures wired into real tRPC mutations.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §2 (gradient-only
//  accent — no flat Brand.info / Brand.blue fills, no .tint(.blue)),
//  §4 (tokenized spacing / radius / type — Space.s*, Radius.*,
//  EType.*), §5 (palette semantic only — no hard-coded Color.white /
//  Color.black / Color.gray fills outside the white-thumb on a
//  GradientToggleStyle, which this brick doesn't use), §7
//  (`AnyShapeStyle` wrapping for ternary shape-styles in fill / stroke),
//  §10 (previews compile in isolation — `.task` doesn't run in the
//  preview canvas, so each store stays in `.loading` and never hits
//  the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Load picker chip strip → reuses the existing
//      `ShipperActiveLoadsStore` (LiveDataStores.swift L3215 →
//      `shippers.getActiveLoads`). Each chip carries the load
//      number and a recommended-bid badge. MCP-verified at
//      `frontend/server/routers/shippers.ts:109`.
//    • Bids list → `ShipperBidsStore` →
//      `shippers.getBidsForLoad(loadId)` (shippers.ts:358). Fetches
//      every bid on the currently selected load. Server returns an
//      empty array (not an error) when no bids exist — the screen
//      surfaces `EusoEmptyState`.
//    • Accept Bid CTA → `shippers.acceptBid(loadId, bidId)`
//      (shippers.ts:392). Server-side this also rejects every other
//      pending bid on the same load and updates `loads.status` →
//      `assigned`. The screen refreshes both the bids list and the
//      active-loads chip strip so the just-assigned load drops out.
//    • Reject Bid CTA → `shippers.rejectBid(loadId, bidId, reason?)`
//      (shippers.ts:415). Reason is captured in a sheet text field;
//      empty / whitespace strings coalesce to `nil` so the wire
//      never carries a meaningless reason. The screen refreshes the
//      bids list on success — the rejected bid drops out (server
//      filters by `status = 'pending'` is handled by re-fetch
//      behaviour).
//    • Zero synthesised data. Empty / blank server fields surface as
//      em-dash sentinels ("—"). DOT, transit time, message, safety
//      score — all elide gracefully when the server hands back the
//      sentinel envelope.
//
//  Wired into `ContentView.ScreenRegistry` as id="203".
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

    /// The load the user is viewing bids for. Defaults to the first
    /// active load returned by the server when the loads list lands;
    /// nil before that.
    @State private var selectedLoadId: String? = nil

    /// Detail sheet — present a single bid with Accept / Reject CTAs.
    @State private var detailBid: ShipperAPI.Bid? = nil

    /// Reject-reason capture sheet (separate from detailBid because
    /// it presents on top of detailBid and carries its own state).
    @State private var rejectingBid: ShipperAPI.Bid? = nil
    @State private var rejectReason: String = ""

    /// In-flight mutation guards so the user can't double-tap Accept
    /// / Reject. Keyed by bid ID so we don't disable the entire
    /// sheet when only one bid is settling.
    @State private var settlingBidIds: Set<String> = []

    /// Most recent mutation error surfaces as a transient banner at
    /// the top of the body so failures aren't swallowed silently.
    @State private var mutationError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let err = mutationError {
                    mutationErrorBanner(err)
                }
                loadPicker
                bidsCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            await refreshAll()
        }
        .refreshable { await refreshAll() }
        .sheet(item: $detailBid) { bid in
            bidDetailSheet(for: bid)
        }
        .sheet(item: $rejectingBid) { bid in
            rejectReasonSheet(for: bid)
        }
        .onChange(of: selectedLoadId) { _, newValue in
            // When the chip strip selection moves, rebind the store
            // and re-fetch. The `setLoadId` call clears the cached
            // rows so we don't briefly flash the prior load's bids.
            bidsStore.setLoadId(newValue)
            Task { await bidsStore.refresh() }
        }
        // Observe `items.count` instead of the whole RemoteState — the
        // generic isn't Equatable so SwiftUI rejects `onChange(of:)`
        // against it. Count-of-items is enough to trigger the
        // first-active-load auto-pick the moment the list lands.
        .onChange(of: loadsStore.items.count) { _, _ in
            // Auto-pick the first active load once the list lands so
            // the body has something to render. We never inject a
            // synthetic loadId — if the shipper has no active loads,
            // selectedLoadId stays nil and the screen surfaces the
            // canonical "post a load" empty state.
            if selectedLoadId == nil {
                if let first = loadsStore.items.first {
                    selectedLoadId = first.id
                }
            }
        }
        .screenTileRoot()
    }

    private func refreshAll() async {
        async let a: Void = loadsStore.refresh()
        async let b: Void = bidsStore.refresh()
        _ = await (a, b)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · BIDS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Awaiting your decision")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(headerSubhead)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var headerSubhead: String {
        if !loadsStore.state.isSettled {
            return "Loading bid fabric…"
        }
        let activeCount = loadsStore.items.count
        let bidsCount   = bidsStore.items.count
        if activeCount == 0 {
            return "Post a load to start receiving bids."
        }
        guard let _ = selectedLoadId else {
            return "\(activeCount) active load\(activeCount == 1 ? "" : "s") · pick one to see bids"
        }
        if !bidsStore.state.isSettled {
            return "Loading bids…"
        }
        return "\(bidsCount) bid\(bidsCount == 1 ? "" : "s") on this load · \(activeCount) load\(activeCount == 1 ? "" : "s") active"
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
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Load picker chip strip

    @ViewBuilder
    private var loadPicker: some View {
        switch loadsStore.state {
        case .loading:
            chipsSkeleton
        case .empty:
            // Shipper has no active loads — no point showing chips.
            // Body renders its own empty state below.
            EmptyView()
        case .loaded:
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
        case .error(let e):
            inlineError(e) { Task { await loadsStore.refresh() } }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(
                on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)
            )
        )
        .overlay(
            Capsule().strokeBorder(
                on ? AnyShapeStyle(Color.clear) : AnyShapeStyle(palette.borderFaint),
                lineWidth: 1
            )
        )
    }

    private var chipsSkeleton: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(palette.bgCard)
                    .frame(width: 92, height: 30)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .opacity(0.6)
            }
        }
    }

    // MARK: - Bids card

    @ViewBuilder
    private var bidsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fingers.spread")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("OPEN BIDS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded = bidsStore.state {
                    Text("\(bidsStore.items.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            bidsContent
        }
    }

    @ViewBuilder
    private var bidsContent: some View {
        // SwiftUI @ViewBuilder bodies cannot use `return` to early-exit
        // — the killer agent's earlier draft used `if … { x; return }`
        // chains which the compiler refused (non-void return + result
        // builder disabled). Rewritten as a single if/else-if chain so
        // every branch yields a View expression directly.
        if case .empty = loadsStore.state {
            postLoadEmptyState
        } else if case .loaded = loadsStore.state, loadsStore.items.isEmpty {
            postLoadEmptyState
        } else if selectedLoadId == nil && loadsStore.state.isSettled {
            pickLoadEmptyState
        } else {
            switch bidsStore.state {
            case .loading:
                bidsSkeleton
            case .empty:
                noBidsEmptyState
            case .loaded(let bids):
                VStack(spacing: Space.s2) {
                    ForEach(bids) { bid in
                        Button {
                            detailBid = bid
                        } label: { bidRow(bid) }
                            .buttonStyle(.plain)
                    }
                }
            case .error(let e):
                inlineError(e) { Task { await bidsStore.refresh() } }
            }
        }
    }

    private func bidRow(_ bid: ShipperAPI.Bid) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName(for: bid))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if bid.recommended {
                        Text("RECOMMENDED")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(LinearGradient.diagonal)
                            .clipShape(Capsule())
                    }
                }
                bidRowSubmeta(bid)
                if !bid.message.isEmpty {
                    Text(bid.message)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(bid.amount > 0 ? dollars(bid.amount) : "—")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                if !bid.transitTime.isEmpty {
                    Text(bid.transitTime)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                Text(submittedRelative(bid.submittedAt))
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func bidRowSubmeta(_ bid: ShipperAPI.Bid) -> some View {
        HStack(spacing: 8) {
            if !bid.dotNumber.isEmpty {
                Image(systemName: "number")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text("DOT \(bid.dotNumber)")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            if bid.safetyScore > 0 {
                if !bid.dotNumber.isEmpty {
                    Text("·").foregroundStyle(palette.textTertiary)
                }
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text(safetyScoreFormat(bid.safetyScore))
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: - Bid detail sheet

    private func bidDetailSheet(for bid: ShipperAPI.Bid) -> some View {
        let isSettling = settlingBidIds.contains(bid.id)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                bidDetailHeader(bid)
                bidDetailSummary(bid)
                if !bid.message.isEmpty {
                    bidDetailMessage(bid)
                }
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
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("CATALYST BID")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
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
            bidDetailRow(
                label: "Bid amount",
                value: bid.amount > 0 ? dollars(bid.amount) : "—",
                isHero: true
            )
            bidDetailRow(
                label: "Transit time",
                value: bid.transitTime.isEmpty ? "—" : bid.transitTime
            )
            bidDetailRow(
                label: "DOT",
                value: bid.dotNumber.isEmpty ? "—" : bid.dotNumber
            )
            bidDetailRow(
                label: "Safety score",
                value: bid.safetyScore > 0 ? safetyScoreFormat(bid.safetyScore) : "—"
            )
            bidDetailRow(
                label: "Submitted",
                value: submittedAbsolute(bid.submittedAt)
            )
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func bidDetailRow(label: String, value: String, isHero: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(isHero
                      ? .system(size: 22, weight: .heavy)
                      : EType.bodyStrong)
                .foregroundStyle(isHero
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textPrimary))
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
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
            }
            Text(bid.message)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func bidDetailActions(_ bid: ShipperAPI.Bid, isSettling: Bool) -> some View {
        VStack(spacing: Space.s2) {
            Button {
                Task { await acceptBid(bid) }
            } label: {
                HStack(spacing: 8) {
                    if isSettling {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .heavy))
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
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Reject")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s3)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSettling)
        }
    }

    // MARK: - Reject reason sheet

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
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
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
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    TextEditor(text: $rejectReason)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(Space.s2)
                        .background(palette.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }

                Button {
                    Task { await rejectBid(bid) }
                } label: {
                    HStack(spacing: 8) {
                        if isSettling {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .controlSize(.small)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13, weight: .heavy))
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

    // MARK: - Mutations

    private func acceptBid(_ bid: ShipperAPI.Bid) async {
        guard let loadId = selectedLoadId, !loadId.isEmpty else { return }
        settlingBidIds.insert(bid.id)
        defer { settlingBidIds.remove(bid.id) }
        do {
            _ = try await EusoTripAPI.shared.shipper.acceptBid(
                loadId: loadId,
                bidId: bid.id
            )
            // Server-side this assigned the load and rejected every
            // other bid. Refresh both lists so the chip strip drops
            // the assigned load and the bid list reflects rejections.
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
            _ = try await EusoTripAPI.shared.shipper.rejectBid(
                loadId: loadId,
                bidId: bid.id,
                reason: reason
            )
            // Refresh the bids list so the rejected row drops out.
            await bidsStore.refresh()
            mutationError = nil
            rejectingBid = nil
            detailBid = nil
            rejectReason = ""
        } catch {
            mutationError = readableError(error)
        }
    }

    // MARK: - Empty / skeleton states

    private var bidsSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .opacity(0.6)
            }
        }
    }

    @ViewBuilder
    private var noBidsEmptyState: some View {
        EusoEmptyState(
            systemImage: "hand.raised",
            title: "No bids yet",
            subtitle: "When a catalyst bids on this load, it'll show up here for accept or reject."
        )
    }

    @ViewBuilder
    private var pickLoadEmptyState: some View {
        EusoEmptyState(
            systemImage: "shippingbox",
            title: "Pick a load",
            subtitle: "Tap any load chip above to see open bids."
        )
    }

    @ViewBuilder
    private var postLoadEmptyState: some View {
        EusoEmptyState(
            systemImage: "shippingbox",
            title: "Post your first load",
            subtitle: "Bids land here the moment a catalyst bids on a posted load."
        )
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.danger)
                Text("Couldn't load bid fabric")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text(readableError(error))
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: retry) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    /// Catalyst display name. Server falls back to the literal
    /// "Catalyst" string when the companies row has no `name` —
    /// the screen elides that to em-dash sentinel rather than
    /// claiming a generic brand.
    private func displayName(for bid: ShipperAPI.Bid) -> String {
        let trimmed = bid.catalystName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "—" }
        if trimmed == "Catalyst" { return "—" }
        return trimmed
    }

    /// Format a 0…100-style safety score with one decimal. The
    /// server currently returns 0 for every row (TODO on the
    /// shippers.ts side); we honor that with em-dash sentinel
    /// elsewhere — this helper only fires when score > 0.
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

    /// "5m ago" / "2h ago" / "Apr 26" — relative when recent,
    /// absolute when older than a day. Empty server string surfaces
    /// as em-dash sentinel.
    private func submittedRelative(_ iso: String) -> String {
        guard !iso.isEmpty else { return "—" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        guard let date = d else { return iso }
        let interval = Date().timeIntervalSince(date)
        if interval < 0 { return "just now" }
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let absFormatter = DateFormatter()
        absFormatter.dateFormat = "MMM d"
        return absFormatter.string(from: date)
    }

    /// Absolute "Apr 26 · 10:14 AM" form for the detail sheet.
    private func submittedAbsolute(_ iso: String) -> String {
        guard !iso.isEmpty else { return "—" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
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
// from Loads / Load Detail; no chrome slot is highlighted.
private func shipperNavLeading_203() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_203() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the skeleton without hitting the network.
// Compiles in isolation per doctrine §10.

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
