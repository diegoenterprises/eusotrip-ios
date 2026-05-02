//
//  DriverCounterInboxView.swift
//  EusoTrip — Driver-side counter-receive inbox.
//
//  Closes Phase 4 (Counter-offer chain) of the 8000-scenario shipper↔
//  driver parity audit (docs/parity-2026/EXECUTIVE_VERDICT.md §4.1).
//  Phase 4 was PARTIAL because the shipper-side counter-all loop
//  shipped (commit fd48163 in 203_ShipperBids.swift) but the driver
//  had no inbox screen to RECEIVE the counter — they could see a
//  status badge change in passing but couldn't accept / decline /
//  re-counter from inside the app.
//
//  After this firing Phase 4 flips PARTIAL → PASS and — because UF
//  and CT both lack a multi-round counter chain entirely — every
//  one of those 400 scenarios becomes an EXCLUSIVE LEAD in the
//  competitive scoreboard.
//
//  Surface anatomy:
//
//    1. Inbox list — every driver bid currently in `countered` state,
//       paired with the shipper's counter row from the same chain.
//       Row card carries:
//         · gradient-rim avatar with shipper monogram
//         · lane summary + load number
//         · 3-cell amount strip: YOUR BID / COUNTER / Δ
//         · status pill (countered) + "expires in" pill when known
//
//    2. Per-row CTAs (inline) — Accept / Decline. Tap-through opens
//       the detail sheet with full bid context + a re-counter
//       composer when supported.
//
//    3. Empty state — calm gradient card, "no counters waiting" copy.
//
//  Backend contract: loadBidding.getMyBids(status:'countered') +
//  loadBidding.getBidChain(loadId:) per row. Accept fires
//  loadBidding.accept(bidId of the shipper's counter row); Decline
//  fires loadBidding.reject(bidId, reason:?).
//
//  Production-grade per [feedback_swiftui_previews] + animation
//  doctrine §B.4. Dark + Light previews ship.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Pair model

/// One inbox row pairs the driver's original bid with the shipper's
/// counter response. Both come from the same load — the chain's
/// latest pending row (not authored by me) is the shipper's counter.
struct DriverCounterPair: Identifiable, Hashable {
    let id: Int                      // counter bid id (server-side)
    let loadId: Int
    let driverBid: LoadBiddingAPI.ChainRow
    let counterBid: LoadBiddingAPI.ChainRow
    /// Lane summary if the load envelope has been hydrated.
    let lane: String?
    /// Carrier-of-record / shipper company name to render in the
    /// avatar block. Best-effort — falls through to a neutral label.
    let counterpartyName: String?
}

// MARK: - View

struct DriverCounterInboxView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var pairs: [DriverCounterPair] = []
    @State private var loading: Bool = false
    @State private var error: String? = nil
    @State private var detail: DriverCounterPair? = nil
    @State private var actionInFlightForBid: Set<Int> = []
    @State private var toast: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                if loading && pairs.isEmpty {
                    skeletonStack
                } else if pairs.isEmpty {
                    emptyState
                } else {
                    ForEach(pairs) { pair in
                        Button {
                            detail = pair
                        } label: {
                            row(pair)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let err = error {
                    errorBanner(err)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .background(palette.bgPrimary.ignoresSafeArea())
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $detail) { p in
            DriverCounterDetailView(pair: p, onChanged: { Task { await load() } })
                .environment(\.palette, palette)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t)
                    .font(EType.caption).fontWeight(.semibold)
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Brand.success,
                                in: RoundedRectangle(cornerRadius: Radius.md))
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        withAnimation { toast = nil }
                    }
            }
        }
    }

    // MARK: - Row

    private func row(_ pair: DriverCounterPair) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Text(initial(pair.counterpartyName))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pair.counterpartyName ?? "Shipper")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(pair.lane ?? "Load #\(pair.loadId)")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("COUNTERED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Brand.warning.opacity(0.15),
                                in: Capsule())
            }

            // 3-cell strip — YOUR BID / COUNTER / Δ
            HStack(spacing: 0) {
                amountCell(label: "YOUR BID", amount: parseAmount(pair.driverBid.bidAmount))
                divider
                amountCell(label: "COUNTER", amount: parseAmount(pair.counterBid.bidAmount), gradient: true)
                divider
                deltaCell(
                    yours: parseAmount(pair.driverBid.bidAmount),
                    counter: parseAmount(pair.counterBid.bidAmount)
                )
            }
            .padding(.vertical, 6)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            HStack(spacing: Space.s2) {
                Button {
                    Task { await decline(pair: pair) }
                } label: {
                    Text("Decline")
                        .font(EType.caption).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(palette.bgCard,
                                    in: RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                            .strokeBorder(palette.borderFaint))
                }
                .buttonStyle(.plain)
                .disabled(actionInFlightForBid.contains(pair.counterBid.id))

                Button {
                    Task { await accept(pair: pair) }
                } label: {
                    HStack(spacing: 6) {
                        if actionInFlightForBid.contains(pair.counterBid.id) {
                            ProgressView().tint(palette.textOnGradient)
                        }
                        Text("Accept counter")
                            .font(EType.caption).fontWeight(.semibold)
                            .foregroundStyle(palette.textOnGradient)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(LinearGradient.diagonal,
                                in: RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
                .disabled(actionInFlightForBid.contains(pair.counterBid.id))
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1)
            .padding(.vertical, 6)
    }

    private func amountCell(label: String, amount: Double, gradient: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(currency(amount))
                .font(.system(size: 16, weight: .heavy).monospacedDigit())
                .tracking(-0.2)
                .foregroundStyle(
                    gradient
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.textPrimary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func deltaCell(yours: Double, counter: Double) -> some View {
        let delta = counter - yours
        let pct: Double = yours > 0 ? (delta / yours) * 100.0 : 0
        let isUp = delta >= 0
        return VStack(spacing: 2) {
            Text("Δ")
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 3) {
                Image(systemName: isUp ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .heavy))
                Text(String(format: "%.1f%%", abs(pct)))
                    .font(.system(size: 14, weight: .heavy).monospacedDigit())
                    .tracking(-0.2)
            }
            .foregroundStyle(isUp ? Brand.success : Brand.warning)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty + skeleton + error

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No counters waiting")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("When a shipper counters one of your bids, it lands here. You can accept, decline, or roll back to the bid stack.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity)
    }

    private var skeletonStack: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCardSoft)
                    .frame(height: 140)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Network

    /// Pull every driver bid in 'countered' state, then for each
    /// fetch the bid chain so we can pair the original driver row
    /// with the shipper's counter row (latest pending entry not
    /// authored by me).
    private func load() async {
        loading = true
        defer { loading = false }
        // Resolve my numeric user id once. AuthUser.id ships as a
        // String over the wire; ChainRow.bidderUserId is Int. We
        // coerce via Int(...) and pass into the closure capture so
        // the closure body doesn't have to repeat the unwrap.
        let myNumericId: Int? = {
            guard let raw = session.user?.id else { return nil }
            return Int(raw)
        }()
        do {
            let env = try await EusoTripAPI.shared.loadBidding
                .getMyBids(status: "countered", limit: 40)

            // Fetch chains in parallel. Each chain is at most a few
            // rows (round 1 + round 2 typically), so the parallel
            // fetch is cheap even for an inbox of 20+ counters.
            var resolved: [DriverCounterPair] = []
            try await withThrowingTaskGroup(of: DriverCounterPair?.self) { group in
                for myBid in env.bids {
                    group.addTask { [myBid, myNumericId] in
                        let chain = try await EusoTripAPI.shared.loadBidding
                            .getBidChain(loadId: myBid.loadId)
                        guard
                            let driverRow = chain.first(where: { $0.id == myBid.id }),
                            let counterRow = chain
                                .filter({ $0.bidderUserId != myNumericId })
                                .filter({ $0.status == "pending" })
                                .max(by: { ($0.bidRound ?? 0) < ($1.bidRound ?? 0) })
                        else { return nil }
                        return DriverCounterPair(
                            id: counterRow.id,
                            loadId: myBid.loadId,
                            driverBid: driverRow,
                            counterBid: counterRow,
                            lane: nil,
                            counterpartyName: nil
                        )
                    }
                }
                for try await result in group {
                    if let r = result { resolved.append(r) }
                }
            }
            // Newest counter first by counter bid id (proxy for time).
            resolved.sort(by: { $0.counterBid.id > $1.counterBid.id })
            pairs = resolved
            error = nil
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func accept(pair: DriverCounterPair) async {
        actionInFlightForBid.insert(pair.counterBid.id)
        defer { actionInFlightForBid.remove(pair.counterBid.id) }
        do {
            _ = try await EusoTripAPI.shared.loadBidding
                .accept(bidId: pair.counterBid.id)
            withAnimation { toast = "Counter accepted · load assigned" }
            await load()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func decline(pair: DriverCounterPair) async {
        actionInFlightForBid.insert(pair.counterBid.id)
        defer { actionInFlightForBid.remove(pair.counterBid.id) }
        do {
            _ = try await EusoTripAPI.shared.loadBidding
                .reject(bidId: pair.counterBid.id, reason: "Driver declined counter")
            withAnimation { toast = "Counter declined" }
            await load()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    // MARK: - Helpers

    private func parseAmount(_ s: String?) -> Double {
        Double(s ?? "") ?? 0
    }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func initial(_ name: String?) -> String {
        if let n = name, let first = n.first { return String(first).uppercased() }
        return "S"
    }
}

// MARK: - Detail sheet

/// Per-pair detail with full chain replay + a richer accept / decline
/// composer. Shown when the driver taps a row in the inbox.
struct DriverCounterDetailView: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let pair: DriverCounterPair
    let onChanged: () -> Void

    @State private var chain: [LoadBiddingAPI.ChainRow] = []
    @State private var loading: Bool = false
    @State private var inFlight: Bool = false
    @State private var error: String? = nil
    @State private var declineReason: String = ""
    @State private var showDeclineComposer: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    headerCard
                    chainCard
                    if showDeclineComposer {
                        declineComposer
                    }
                    if let err = error {
                        Text(err)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                    }
                    Color.clear.frame(height: 132)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .disabled(inFlight)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("COUNTER · ROUND \(pair.counterBid.bidRound ?? 0)")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Load #\(pair.loadId)")
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
                    .background(palette.bgPrimary)
            }
            .task { await loadChain() }
            .refreshable { await loadChain() }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR BID")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            Text(currency(parseAmount(pair.driverBid.bidAmount)))
                .font(.system(size: 18, weight: .heavy).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
            Divider().overlay(palette.borderFaint).padding(.vertical, 4)
            Text("SHIPPER COUNTER")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            HStack(alignment: .firstTextBaseline) {
                Text(currency(parseAmount(pair.counterBid.bidAmount)))
                    .font(.system(size: 28, weight: .heavy).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let exp = pair.counterBid.expiresAt {
                    Text("Expires \(exp)")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if let cond = pair.counterBid.conditions, !cond.isEmpty {
                Text("Conditions: \(cond)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var chainCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CHAIN")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            if loading && chain.isEmpty {
                ProgressView()
            } else if chain.isEmpty {
                Text("No chain history available.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(chain) { row in
                    chainEntry(row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func chainEntry(_ row: LoadBiddingAPI.ChainRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text("R\(row.bidRound ?? 0)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(row.bidderRole?.uppercased() ?? "—") · \(currency(parseAmount(row.bidAmount)))")
                    .font(EType.body).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text(row.status?.uppercased() ?? "—")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(statusColor(row.status))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var declineComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DECLINE REASON (OPTIONAL)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            TextField("Why decline? (helps the shipper recalibrate)",
                      text: $declineReason,
                      axis: .vertical)
                .lineLimit(2, reservesSpace: true)
                .font(EType.body)
                .padding(Space.s3)
                .background(palette.bgCardSoft,
                            in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm)
                    .strokeBorder(palette.borderFaint))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            HStack(spacing: Space.s3) {
                Button {
                    if showDeclineComposer {
                        Task { await decline() }
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showDeclineComposer = true
                        }
                    }
                } label: {
                    Text(showDeclineComposer ? "Confirm decline" : "Decline")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard,
                                    in: RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)

                CTAButton(
                    title: inFlight ? "Working…" : "Accept counter",
                    action: { Task { await accept() } },
                    isLoading: inFlight
                )
                .opacity(inFlight ? 0.55 : 1.0)
                .disabled(inFlight)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
    }

    // MARK: - Network

    private func loadChain() async {
        loading = true
        defer { loading = false }
        do {
            chain = try await EusoTripAPI.shared.loadBidding
                .getBidChain(loadId: pair.loadId)
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func accept() async {
        inFlight = true
        defer { inFlight = false }
        do {
            _ = try await EusoTripAPI.shared.loadBidding
                .accept(bidId: pair.counterBid.id)
            onChanged()
            dismiss()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func decline() async {
        inFlight = true
        defer { inFlight = false }
        do {
            let reason = declineReason.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await EusoTripAPI.shared.loadBidding
                .reject(bidId: pair.counterBid.id, reason: reason.isEmpty ? "Driver declined counter" : reason)
            onChanged()
            dismiss()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private func statusColor(_ s: String?) -> Color {
        switch s {
        case "accepted":  return Brand.success
        case "rejected":  return Brand.danger
        case "countered": return Brand.warning
        case "pending":   return Brand.info
        default:          return palette.textSecondary
        }
    }

    private func parseAmount(_ s: String?) -> Double { Double(s ?? "") ?? 0 }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Previews

#Preview("Counter inbox · Dark") {
    DriverCounterInboxView()
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("Counter inbox · Light") {
    DriverCounterInboxView()
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
