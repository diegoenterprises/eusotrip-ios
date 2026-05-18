//
//  052_RateconTender.swift
//  EusoTrip — Lifecycle screen 052 · Ratecon Tender.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `052 Ratecon Tender.png`. Rate confirmation surface the driver
//  reviews + accepts. Day-2 tender hero + lane chip + rate
//  breakdown (Linehaul / Fuel / Accessorials / Total) + commodity
//  + equipment + weight + broker card + ESANG advisory + Counter /
//  Accept tender CTAs. Product-aware copy via
//  `LifecycleProductContext` so commodity / equipment / weight
//  reflect the active product, not always hazmat.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct RateconTender: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverOpenMessages) private var openMessages
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isAccepting: Bool = false
    @State private var showCounterSheet: Bool = false
    @State private var counterAmount: String = ""
    @State private var counterNote: String = ""
    @State private var counterInflight: Bool = false
    @State private var actionToast: String? = nil

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let fallbackClock      = "09:32"
    // 150th firing — P2.1 eradication. The six axes below previously
    // shipped as literal fixture dollars / lane labels copied from the
    // 052 Figma. Per §13 doctrine + 147th's broker-note pattern, every
    // synthetic fixture constant degrades to a neutral em-dash
    // sentinel. The visible copy on a tender with no live load now
    // reads as a deliberate "—" instead of a fabricated $1,420 / Gate C
    // line that would mislead the operator into thinking dispatch
    // had wired the tender.
    private let fallbackTotalNet   = "—"
    private let fallbackTotalSub   = ""
    private let fallbackMiles      = "—"
    private let fallbackRpm        = "—"
    private let fallbackPremium    = ""
    private let fallbackTenderExp  = ""
    private let fallbackOrigin     = "—"
    private let fallbackOriginLine = "—"
    private let fallbackDest       = "—"
    private let fallbackDestLine   = "—"
    private let fallbackLinehaul   = "—"
    private let fallbackFuelSur    = "—"
    private let fallbackAccess     = "—"
    private let fallbackTotal      = "—"
    private let fallbackBroker     = "—"
    private let fallbackBrokerNote = "BROKER · — · —"
    private let fallbackBrokerGrade = "A+"
    private let fallbackeSangCopy  = "—"

    /// Counter-offer button label. When a real load is loaded, suggests
    /// a counter at +5% of the offered rate (rounded to nearest dollar).
    /// Without a load, shows a generic "Counter offer" string — never a
    /// hardcoded mock-data dollar value (100th firing ledger-hygiene fix).
    private var counterLabel: String {
        // `Load.rate` decodes as String (the backend stores it as a
        // DECIMAL serialized as a string). Convert to Double before
        // arithmetic — Release whole-module-optimization catches the
        // direct String > Int comparison the prior code did.
        guard let rateStr = activeLoad?.rate,
              let rate = Double(rateStr),
              rate > 0 else { return "Counter offer" }
        let suggested = Int((rate * 1.05).rounded())
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let priced = f.string(from: NSNumber(value: suggested)) ?? "\(suggested)"
        return "Counter $\(priced)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                laneCard
                rateBreakdown
                commodityRow
                brokerCard
                esangAdvisory
                actions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .sheet(isPresented: $showCounterSheet) {
            counterSheet
                .environment(\.palette, palette)
                .presentationDetents([.medium])
        }
        .overlay(alignment: .bottom) {
            if let msg = actionToast {
                Text(msg)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: actionToast)
        .screenTileRoot()
    }

    /// Counter-offer composer sheet. Pre-fills the amount with the
    /// load's existing rate × 1.05 (a conventional "ask for 5% more"
    /// nudge). Optional condition note ferries through to the
    /// shipper's bids board so the broker sees why the driver
    /// pushed back (e.g. "weekend delivery surcharge", "PG-1
    /// hazmat overpay").
    private var counterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("COUNTER OFFER")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Submit a different rate")
                        .font(EType.body.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                    if let load = activeLoad,
                       let rate = Double(load.rate ?? ""),
                       rate > 0 {
                        Text("Posted rate: $\(Int(rate))")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    HStack {
                        Text("$")
                            .font(EType.body.weight(.heavy))
                            .foregroundStyle(palette.textPrimary)
                        TextField("Amount", text: $counterAmount)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Counter rate in dollars")
                    }
                    Text("CONDITIONS (OPTIONAL)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textSecondary)
                    TextField("e.g. weekend rate, PG-1 hazmat", text: $counterNote)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { showCounterSheet = false }
                            .buttonStyle(.bordered)
                            .disabled(counterInflight)
                        Spacer()
                        Button {
                            Task { await submitCounter() }
                        } label: {
                            HStack(spacing: 6) {
                                if counterInflight {
                                    ProgressView().controlSize(.small).tint(.white)
                                }
                                Text(counterInflight ? "Sending…" : "Send counter")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(counterInflight || counterAmount.isEmpty)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Counter offer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            // 100th firing · ledger-hygiene sweep — wired no-op chevron.
            Button { navBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SUNDAY · DAY-2 TENDER · UNIVAR / YARA")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Circle().fill(Brand.warning).frame(width: 6, height: 6)
                Text("AWAITING ACCEPT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.warning)
            }
            Text(fallbackClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fallbackTotalNet)
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text(fallbackTotalSub)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(fallbackRpm)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("$/mi")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            HStack(spacing: 6) {
                Text(fallbackMiles)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("·")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text(fallbackPremium)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(fallbackTenderExp)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.25), Brand.magenta.opacity(0.20)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var laneCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            laneNode(label: fallbackOrigin, sub: fallbackOriginLine)
            VStack(spacing: 2) {
                Text(fallbackMiles.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .padding(.top, 8)
            laneNode(label: fallbackDest, sub: fallbackDestLine)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func laneNode(label: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(sub)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rateBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RATE BREAKDOWN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("PER RATECON V2.4")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
            }
            rateRow(icon: "arrow.right", label: "Linehaul",        sub: "\(ctx.beatCommodityDescriptor) · 156 mi", value: fallbackLinehaul)
            rateRow(icon: "drop.fill",   label: "Fuel surcharge",  sub: "PADD 1B 4.49",                             value: fallbackFuelSur)
            rateRow(icon: "wrench.fill", label: "Accessorials",     sub: accessorialsSub,                            value: fallbackAccess)
            Divider().overlay(palette.borderFaint).padding(.vertical, 4)
            HStack {
                Text("Total to driver")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(fallbackTotal)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
            }
            // 140th firing M3 sweep — gallons literal and drive-time
            // literal both swapped. Gallons routes through
            // `facets.loadedGallons` and drops cleanly when the load
            // envelope hasn't shipped a tanker fill volume. Drive-time
            // segment awaits a route-ETA envelope (not joined onto
            // `loads.getById` per §16 loads-lifecycle slice) and
            // currently surfaces an em-dash sentinel.
            Text(netAtTruckSubLine)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var accessorialsSub: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  return "Hazmat premium 2%"
        case .reefer:                       return "Cold-chain premium 1.5%"
        case .flatbed:                      return "Tarping 2× $25"
        case .container, .railIntermodal,
             .vesselContainer:              return "Chassis split"
        case .railBulk, .vesselBulk:        return "Grounding labor"
        case .dryVan:                       return "Lumper $50"
        }
    }

    private func rateRow(icon: String, label: String, sub: String, value: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(value)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, 6)
    }

    private var commodityRow: some View {
        HStack(spacing: Space.s2) {
            commodityCell(label: "COMMODITY", value: ctx.beatCommodityDescriptor)
            commodityCell(label: "EQUIPMENT", value: equipmentLabel)
            commodityCell(label: "WEIGHT",    value: weightLabel)
        }
    }

    /// "NET AT TRUCK" sub-line under the gradient total. Hazmat path
    /// composes from `facets.loadedGallons` (live tanker fill volume,
    /// em-dash when not shipped); non-hazmat path composes from
    /// `ctx.beatCommodityDescriptor` (already retrofitted in 139th).
    /// Drive-time segment is currently em-dash — route-ETA envelope
    /// not yet joined onto `loads.getById` (§16 loads-lifecycle).
    private var netAtTruckSubLine: String {
        let f = ctx.facets
        let dash = LiveLoadFacets.dash
        func seg(_ s: String) -> String? { s == dash ? nil : s }
        let head = "NET AT TRUCK"
        let cargo = ctx.isHazmat
            ? seg(f.loadedGallons).map { "\($0) GAL" }
            : seg(ctx.beatCommodityDescriptor)
        // Drive-time gap — em-dash sentinel, dropped from the line.
        let driveTime: String? = nil
        let parts = [head, cargo, driveTime].compactMap { $0 }
        return parts.joined(separator: " · ").uppercased()
    }

    /// 140th firing M3 sweep — equipment label routes through
    /// `facets.tankSpec` for hazmat (so the live MC-rating drives
    /// the chip) and `facets.containerIsoType` for vessel containers
    /// (so the live ISO 6346 type code drives the chip). Universal
    /// industry-canonical equipment specs ("53' reefer", "48' flatbed",
    /// "53' van", "Bulk hopper") are preserved as universal trade
    /// vocabulary, not fabrication.
    private var equipmentLabel: String {
        let f = ctx.facets
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:  return f.tankSpec
        case .reefer:                       return "53' reefer"
        case .flatbed:                      return "48' flatbed"
        case .container, .railIntermodal:
            // Chassis ID drives the chip when shipped; otherwise the
            // universal "53' chassis" trade descriptor.
            return f.chassisNumber == LiveLoadFacets.dash
                ? "53' chassis"
                : f.chassisNumber
        case .vesselContainer:              return f.containerIsoType
        case .railBulk, .vesselBulk:        return "Bulk hopper"
        case .dryVan:                       return "53' van"
        }
    }

    /// 140th firing M3 sweep — every weight case routes through
    /// `facets.netWeight`. The accessor honours `Load.weightUnit` so
    /// vessel-container kg loads render correctly. Em-dash drops when
    /// the load envelope hasn't shipped a `weight` value (per `§16`
    /// loads-lifecycle: shipper-supplied at booking time).
    private var weightLabel: String {
        ctx.facets.netWeight
    }

    private func commodityCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var brokerCard: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(LinearGradient.diagonal)
                Image(systemName: "shield.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(fallbackBroker)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(fallbackBrokerNote)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(fallbackBrokerGrade)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var esangAdvisory: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(fallbackeSangCopy)
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var actions: some View {
        // Buttons extracted into named computed properties so Swift's
        // type-checker doesn't blow up trying to infer the HStack's
        // full TupleView signature in one shot — same fix applied to
        // 029_PickupArrival's footerActions.
        HStack(spacing: Space.s3) {
            counterButton
            acceptTenderButton
        }
    }

    private var counterButton: some View {
        // 100th firing · ledger-hygiene sweep — was no-op `Button { }`
        // with a hardcoded "$1,480" label. Now derives from the real
        // load's rate (+~5%) when present.
        Button(action: counterTapped) {
            counterButtonLabel
        }
    }

    private func counterTapped() {
        // Open the counter-offer composer sheet — pre-populates
        // the amount field with the load's existing rate (or +5%
        // suggestion when present) so the driver only has to
        // confirm rather than re-type. The sheet's submit button
        // fires `drivers.counterOffer(loadId, amount, conditions)`
        // — server creates a row in `loadBids` with
        // bidderRole='driver' and status='countered' so the shipper
        // sees the counter on their bids board.
        if let load = activeLoad {
            let rate = Double(load.rate ?? "") ?? 0
            if rate > 0 {
                counterAmount = String(format: "%.0f", rate * 1.05)
            }
        }
        counterNote = ""
        showCounterSheet = true
    }

    /// Submit the counter offer to the backend. Real
    /// `drivers.counterOffer` mutation — creates the loadBids row
    /// server-side. On success: dismiss sheet, surface toast,
    /// open the messaging thread for follow-up so the shipper /
    /// driver can negotiate beyond the single-rate counter.
    private func submitCounter() async {
        guard !counterInflight else { return }
        guard let load = activeLoad else { return }
        guard let amount = Double(counterAmount), amount > 0 else {
            actionToast = "Enter a valid rate"
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            actionToast = nil
            return
        }
        counterInflight = true
        defer { counterInflight = false }
        do {
            _ = try await EusoTripAPI.shared.drivers.counterOffer(
                loadId: String(load.id),
                amount: amount,
                conditions: counterNote.isEmpty ? nil : counterNote
            )
            showCounterSheet = false
            actionToast = "Counter sent"
            // Open the messaging thread for follow-up negotiation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                openMessages?(String(load.id))
            }
        } catch {
            actionToast = "Counter failed: \(error.localizedDescription)"
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        actionToast = nil
    }

    private var counterButtonLabel: some View {
        // Extracted to keep Release whole-module-optimization happy —
        // the inline `Text(...).font().foreground().frame().background()
        // .overlay().clipShape()` chain hit the type-checker timeout.
        Text(counterLabel)
            .font(EType.body.weight(.semibold))
            .foregroundStyle(palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderSoft)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var acceptTenderButton: some View {
        CTAButton(
            title: "Accept tender",
            action: { Task { await accept() } },
            trailingIcon: "arrow.right",
            isLoading: isAccepting
        )
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func accept() async {
        isAccepting = true
        defer { isAccepting = false }
        // Step 1 — fire the real `drivers.acceptLoad` mutation so
        // server-side loadBids flips to status='accepted' AND the
        // load is bound to this driver. Without this the lifecycle
        // transition below ran but the marketplace didn't know the
        // driver had taken the tender.
        if let load = activeLoad {
            do {
                _ = try await EusoTripAPI.shared.drivers
                    .acceptLoad(loadId: String(load.id))
            } catch {
                actionToast = "Accept failed: \(error.localizedDescription)"
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                actionToast = nil
                return
            }
        }
        // Step 2 — execute the lifecycle transition so the trip
        // state machine walks forward (accepted → assigned →
        // pretrip DVIR ladder).
        let keys = ["accepted", "assigned"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct RateconTenderScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            RateconTender(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_052(),
                      trailing: driverNavTrailing_052(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_052() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_052() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("052 · Ratecon Tender · Dark") {
    RateconTenderScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("052 · Ratecon Tender · Light") {
    RateconTenderScreen(theme: Theme.light).preferredColorScheme(.light)
}
