//
//  241_ShipperCounterReview.swift
//  EusoTrip — Shipper · Counter Review (brick 241).
//
//  Pixel-match to `02 Shipper/Dark-SVG/241 Shipper Counter Review.svg`.
//  Shipper's view of a §11.4 counter from a Catalyst — Aurora counters
//  $2,200 RFP up to $2,425, 23h to accept.
//
//  Wire bindings (all real, no stubs):
//    loads.getById(loadId)            — load context (lane, equipment)
//    loadBidding.getBidChain(loadId)  — current counter chain
//

import SwiftUI

struct ShipperCounterReviewScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) { CounterReviewBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Post",  systemImage: "plus.rectangle",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CounterReviewBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: LoadsAPI.LoadDetail?
    @State private var chain: [LoadBiddingAPI.ChainRow] = []
    @State private var counter: LoadBiddingAPI.ChainRow?
    @State private var loading: Bool = true
    @State private var actionInFlight: String? = nil
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var showCounterSheet: Bool = false
    @State private var counterAmountText: String = ""
    @State private var pendingAcceptBidId: Int?
    @State private var pendingAcceptRequestKey: String?
    @State private var proposesDetentionOverride = false
    @State private var detentionDraft = TruckDetentionTermsDraft()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && counter == nil {
                    LifecycleCard { Text("Loading counter…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    contextBanner
                    if let c = counter { carrierCard(c) }
                    if let c = counter { kpiGrid(c) }
                    actionRow
                    if let ack = actionAck {
                        LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(.green) }
                    }
                    if let err = actionError {
                        LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .sheet(isPresented: $showCounterSheet) { counterBackSheet }
    }

    private var counterBackSheet: some View {
        NavigationStack {
            Form {
                Section("Your counter-offer") {
                    TextField("Counter amount (e.g. 2425)", text: $counterAmountText)
                        .keyboardType(.decimalPad)
                    if let amount = counter?.bidAmount {
                        Text("Current round: \(money(amount)).")
                            .font(.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                if isTruckLoad {
                    Section("Truck detention") {
                        if let inherited = counter?.truckDetentionTerms {
                            TruckDetentionTermsSummary(terms: inherited, context: "INHERITED IF UNCHANGED")
                            Toggle("Propose different detention terms", isOn: $proposesDetentionOverride)
                                .frame(minHeight: 44)
                        } else {
                            Text("This truck counter has no effective detention authority. Complete every term before sending.")
                                .font(.caption)
                                .foregroundStyle(Brand.warning)
                            TruckDetentionTermsEditor(draft: $detentionDraft)
                        }
                        if proposesDetentionOverride, counter?.truckDetentionTerms != nil {
                            TruckDetentionTermsEditor(draft: $detentionDraft)
                        }
                        if let mismatch = detentionCurrencyMismatch {
                            Text(mismatch).font(.caption).foregroundStyle(Brand.danger)
                        }
                    }
                } else if load == nil {
                    Section {
                        Text("Load mode is unavailable. Refresh before countering so detention terms cannot be dropped or attached to the wrong mode.")
                            .font(.caption)
                            .foregroundStyle(Brand.warning)
                    }
                }
            }
            .navigationTitle("Counter back")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCounterSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        showCounterSheet = false
                        Task { await sendCounterBack() }
                    }
                    .disabled(Double(counterAmountText) == nil || !counterContractReady)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LOADS · COUNTER · REVIEW").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Review counter").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if let c = counter {
                let amt = money(c.bidAmount)
                let delta = computeDelta(counter: c.bidAmount, original: priorBid?.bidAmount)
                Text("COUNTER \(amt) · DELTA \(delta) · \(expiresAgo(c.expiresAt))")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var contextBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SHIPPER · COUNTER REVIEW")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if let l = load {
                    Text("\(l.loadNumber) · \(laneLabel(l)) · \(l.equipmentType ?? "Equipment unavailable")")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func carrierCard(_ c: LoadBiddingAPI.ChainRow) -> some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text(initialsFor(c.bidderRole)).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.bidderRole?.capitalized ?? "Counterparty")
                        .font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    if let companyId = c.bidderCompanyId {
                        Text("Company #\(companyId)").font(.caption.monospaced()).foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
            }
            if let terms = c.truckDetentionTerms {
                TruckDetentionTermsSummary(
                    terms: terms,
                    context: detentionRoundContext(terms)
                )
            }
        }
    }

    private func kpiGrid(_ c: LoadBiddingAPI.ChainRow) -> some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        let counterAmt = money(c.bidAmount)
        let delta = computeDelta(counter: c.bidAmount, original: priorBid?.bidAmount)
        let rpm: String = {
            guard let raw = c.bidAmount, let amt = Double(raw), amt > 0,
                  let mi = load?.distance, mi > 0 else { return "-" }
            return money(String(amt / mi))
        }()
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("COUNTER",  counterAmt, "to accept", .green)
            kpi("DELTA",    delta,            "vs RFP",    delta.hasPrefix("+") ? .orange : .green)
            kpi("EXPIRES",  expiresAgo(c.expiresAt), "auto-revert", .red)
            kpi("RPM",      rpm,              "per mile",  .blue)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { Task { await acceptCounter() } } label: {
                HStack(spacing: 6) {
                    if actionInFlight == "accept" { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(actionInFlight == "accept" ? "Accepting…" : "Accept counter")
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight != nil || counter?.id == nil)

            Button { prepareCounterBack() } label: {
                HStack(spacing: 6) {
                    if actionInFlight == "counter" { ProgressView().scaleEffect(0.8) }
                    Text(actionInFlight == "counter" ? "Sending…" : "Counter back")
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(palette.textPrimary)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight != nil || counter?.id == nil)
        }
    }

    private func acceptCounter() async {
        guard let bidId = counter?.id else { return }
        let requestKey: String
        if pendingAcceptBidId == bidId, let pendingAcceptRequestKey {
            requestKey = pendingAcceptRequestKey
        } else {
            requestKey = UUID().uuidString.lowercased()
            pendingAcceptBidId = bidId
            pendingAcceptRequestKey = requestKey
        }
        actionInFlight = "accept"; actionAck = nil; actionError = nil
        defer { actionInFlight = nil }
        struct In: Encodable { let bidId: Int; let requestKey: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "loadBidding.accept",
                input: In(bidId: bidId, requestKey: requestKey)
            )
            if resp.success == true {
                pendingAcceptBidId = nil
                pendingAcceptRequestKey = nil
                actionAck = "Counter accepted · bid #\(bidId) awarded · carrier notified · load locked."
                await self.load()
            } else {
                actionError = "Accept returned no success flag. Reload and try again."
            }
        } catch let err {
            actionError = EusoTripAPIError.bidActionMessage(for: err, noun: "acceptance")
        }
    }

    private func sendCounterBack() async {
        // `loadBidding.counter` keys the new round on the PARENT bid + the
        // numeric loadId and returns `{ id, round, status }` — the build-755
        // contract fix, now carried by the typed `loadBidding.counter` wrapper.
        guard let bidId = counter?.id,
              let amount = Double(counterAmountText),
              let numericLoadId = Int(load?.id ?? loadId) else { return }
        actionInFlight = "counter"; actionAck = nil; actionError = nil
        defer { actionInFlight = nil }
        do {
            let resp = try await EusoTripAPI.shared.loadBidding.counter(
                parentBidId: bidId,
                loadId: numericLoadId,
                counterAmount: amount,
                conditions: "Shipper countered via SH241",
                truckDetentionTerms: proposedDetentionTerms
            )
            guard let confirmedStatus = resp.confirmedStatus else {
                actionError = "The counter was not confirmed. The bid chain remains unchanged."
                return
            }
            actionAck = "Counter sent · \(money(String(amount))) back to carrier · round status \(confirmedStatus)."
            counterAmountText = ""
            await self.load()
        } catch let err {
            actionError = EusoTripAPIError.bidActionMessage(for: err, noun: "counter")
        }
    }

    private func computeDelta(counter: String?, original: String?) -> String {
        guard let c = Double(counter ?? "0"), let o = Double(original ?? "0"), o > 0 else { return "-" }
        let d = c - o
        let formatted = money(String(abs(d)))
        return (d >= 0 ? "+" : "-") + formatted
    }

    private func expiresAgo(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "-" }
        let mins = max(0, Int(d.timeIntervalSinceNow / 60))
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        return "\(h)h \(mins % 60)m"
    }

    private func initialsFor(_ name: String?) -> String {
        guard let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return "-" }
        let parts = n.split(separator: " ").map(String.init)
        let f = parts.first?.first.map(String.init) ?? ""
        let l = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (f + l).uppercased()
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let l: Void = loadCtx()
        async let c: Void = loadCounter()
        _ = await (l, c)
    }
    private func loadCtx() async {
        do {
            load = try await EusoTripAPI.shared.loads.getDetail(id: loadId)
        } catch {
            actionError = "Couldn't verify the load mode or commercial currency."
        }
    }
    private func loadCounter() async {
        do {
            guard let numericLoadId = Int(loadId) else {
                actionError = "Load identity is invalid."
                return
            }
            chain = try await EusoTripAPI.shared.loadBidding.getBidChain(loadId: numericLoadId)
            counter = chain.last(where: { ($0.status ?? "").lowercased() == "pending" }) ?? chain.last
        } catch {
            actionError = "Couldn't load the counter chain."
        }
    }

    private var priorBid: LoadBiddingAPI.ChainRow? {
        guard let counter, let index = chain.firstIndex(where: { $0.id == counter.id }), index > 0 else {
            return nil
        }
        return chain[index - 1]
    }

    private var isTruckLoad: Bool {
        if counter?.truckDetentionTerms != nil { return true }
        return load?.transportMode?.lowercased() == "truck"
    }

    private var proposedDetentionTerms: TruckDetentionNegotiatedTerms? {
        guard isTruckLoad else { return nil }
        let mustSupply = counter?.truckDetentionTerms == nil
        return (mustSupply || proposesDetentionOverride) ? detentionDraft.negotiatedTerms : nil
    }

    private var counterContractReady: Bool {
        guard counter?.id != nil else { return false }
        guard let mode = load?.transportMode?.lowercased() else {
            if counter?.truckDetentionTerms == nil { return false }
            return !proposesDetentionOverride || proposedDetentionTerms != nil
        }
        guard mode == "truck" else { return true }
        if counter?.truckDetentionTerms == nil || proposesDetentionOverride {
            return proposedDetentionTerms != nil && detentionCurrencyMismatch == nil
        }
        return true
    }

    private var detentionCurrencyMismatch: String? {
        guard let terms = proposedDetentionTerms,
              let authoritativeCurrency = load?.currency?.uppercased()
                ?? counter?.truckDetentionTerms?.currency.rawValue,
              terms.currency.rawValue != authoritativeCurrency else { return nil }
        return "Detention currency must match the inherited load currency (\(authoritativeCurrency))."
    }

    private func prepareCounterBack() {
        if let terms = counter?.truckDetentionTerms {
            detentionDraft = TruckDetentionTermsDraft(terms: terms)
            proposesDetentionOverride = false
        } else {
            detentionDraft = TruckDetentionTermsDraft()
            detentionDraft.currency = load?.currency
                .flatMap { TruckDetentionNegotiatedTerms.Currency(rawValue: $0) }
            proposesDetentionOverride = isTruckLoad
        }
        showCounterSheet = true
    }

    private func detentionRoundContext(_ terms: TruckDetentionNegotiatedTerms) -> String {
        guard let previousTerms = priorBid?.truckDetentionTerms else { return "OPENING DETENTION TERMS" }
        return previousTerms == terms ? "UNCHANGED FROM PRIOR ROUND" : "UPDATED THIS ROUND"
    }

    private func money(_ raw: String?) -> String {
        guard let raw,
              let amount = Double(raw),
              let code = counter?.truckDetentionTerms?.currency.rawValue ?? load?.currency else {
            return "—"
        }
        return amount.formatted(
            .currency(code: code)
                .precision(.fractionLength(0...2))
        )
    }

    private func laneLabel(_ load: LoadsAPI.LoadDetail) -> String {
        let origin = load.pickupLocation.map { [$0.city, $0.state].compactMap { $0 }.joined(separator: ", ") }
            ?? load.origin.map { [$0.city, $0.state].compactMap { $0 }.joined(separator: ", ") }
        let destination = load.deliveryLocation.map { [$0.city, $0.state].compactMap { $0 }.joined(separator: ", ") }
            ?? load.destination.map { [$0.city, $0.state].compactMap { $0 }.joined(separator: ", ") }
        guard let origin, !origin.isEmpty, let destination, !destination.isEmpty else {
            return "Lane unavailable"
        }
        return "\(origin) → \(destination)"
    }
}

#Preview("241 · Dark")  { ShipperCounterReviewScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("241 · Light") { ShipperCounterReviewScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
