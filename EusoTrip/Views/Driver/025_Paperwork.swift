//
//  025_Paperwork.swift
//  EusoTrip — Lifecycle screen 025 · Paperwork (Load Closed).
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `025 Paperwork.png` (Dark + Light). Fires when the last unit is
//  offloaded and the BOL is signed off. Anchored by a full BOL-
//  SIGNED card (shipper + consignee + pieces + seal before → after
//  + signed by + OS&D), a 4-metric strip (START / END / DOOR TIME
//  / DETENTION $), and a "10-hour break starts now" info card with
//  overflow-lot guidance.
//
//  Bottom CTAs: View BOL outline + Start 10-hour break gradient.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct Paperwork: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var showBol: Bool = false
    @State private var isStartingBreak: Bool = false

    // MARK: - POD desync auto-advance (FSM owns pod_pending now)
    //
    // BLOCKER fix (2026-06-13): after `pod.submitPOD` the load lands at
    // `unloaded` and the server no longer force-sets `pod_pending` (the
    // FSM owns that hop). Without an explicit nudge the POD flow dead-ends
    // here with the driver stuck at `unloaded`. On hydrate we detect that
    // status and fire UNLOADED_TO_POD_PENDING once via the live lifecycle
    // path (which auto-captures GPS), so the close-out advances on its own.

    /// One-shot guard so the auto-advance fires at most once per screen
    /// mount and only against the `unloaded` status. Flips true the moment
    /// we attempt the transition (success or fail) so a re-entrant `.task`
    /// or a refresh can't double-fire it.
    @State private var didAttemptPodAdvance: Bool = false

    /// Honest failure surface for the auto-advance. nil when the hop
    /// succeeded or was never needed; carries the real server/transport
    /// reason when UNLOADED_TO_POD_PENDING is rejected — never swallowed,
    /// never faked into a "done" state.
    @State private var podAdvanceError: String?

    // MARK: - Live close-out sources (real procs only; honest em-dash otherwise)
    //
    // De-fabrication (2026-06-07): the BOL header (#, shipper/consignee,
    // seal), the trip START / END pair, the "SIGNED BY" row, and the
    // close-out "DETENTION $" charge were Figma literals that leaked onto
    // the live path. They now resolve from one real backend proc —
    // `loads.getCloseoutSummary` — which composes BOL #, shipper/consignee
    // name + address, the real trip departed/arrived stamps, the recorded
    // detention claim total, and the POD-derived signer server-side. The
    // detention $/hr · free-time CAPTION still draws from the richer live
    // `detentionAccessorials.calculateDetention` calc (the summary carries
    // only the flat charge). Anything without a live source renders the
    // honest em-dash sentinel the file already uses ("-") — never a seeded
    // figure.

    /// Closed, server-calculated detention row for this load. Paperwork never
    /// recalculates a settled event from client assumptions; it displays only
    /// the persisted verified calculation and provenance returned by history.
    @State private var detentionHistory: DetentionAPI.HistoryEvent?
    @State private var detentionHistoryError: String?

    /// Live close-out packet for this load (`loads.getCloseoutSummary`).
    /// The single source of truth for the BOL header (#, shipper/consignee
    /// name + address), the trip START / END wall-clock pair (departedAt /
    /// arrivedAt ?? actualDeliveryDate), the seal numbers, the detention $
    /// charge, and the SIGNED-BY row. Every field on it is nullable and the
    /// screen renders the honest em-dash sentinel for any nil. Stays nil
    /// (try? → nil) until the proc returns — never a seeded Figma literal.
    @State private var closeout: LoadsAPI.CloseoutSummary?
    /// Driver rates the shipper after delivery. Closes Phase 18
    /// (Rating / review) of the 8000-scenario parity audit
    /// (docs/parity-2026/EXECUTIVE_VERDICT.md §4.5). Backend
    /// `ratings.submit` has shipped since the 90th firing — the
    /// missing piece was the iOS prompt screen.
    @State private var showRateShipper: Bool = false
    /// Tier 3 #10 (2026-05-21) — present the dock-worker POD sheet
    /// so the receiver's worker can sign off on the same screen
    /// the driver lands on after offload. Server chains the row
    /// off the driver POD, closing the cross-role action loop.
    @State private var showDockPod: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    /// Transport mode of the active load (truck fallback) — drives the
    /// mode-aware close-out document + charge labels (BOL/Detention).
    private var resolvedMode: TransportMode {
        TransportMode(rawValue: activeLoad?.transportMode ?? "truck") ?? .truck
    }

    // MARK: - Honest sentinels + reference constants
    //
    // De-fabrication (2026-06-07): every value that was a seeded Figma
    // literal on a RENDERED path is now either a live computed getter
    // (when a real proc/model backs it — see the getters below) or the
    // honest em-dash sentinel "-" the file already uses. None of these
    // emit a fabricated figure.
    //
    // LIVE (from `loads.getCloseoutSummary`): BOL #, shipper/consignee
    // name + address, trip START (departedAt) / END (arrivedAt ??
    // actualDeliveryDate), seal numbers, detention $, and SIGNED-BY. Each
    // renders the honest em-dash below when the matching field is null.
    //
    // EM-DASH (no live source on the wire today — server returns null):
    //   • dock door / DOOR TIME — no billed door-time projection or dock
    //     column reaches this close-out screen (proc returns null).
    //   • pieces delivered — the load envelope ships no granular
    //     unloaded-unit column (LiveLoadFacets.palletCount is a backend
    //     gap), so neither the "N of N" header nor the "N / N" BOL row can
    //     assert a real count (proc returns null).
    //   • break / overflow-lot guidance — there is no yard-occupancy /
    //     overflow-slot / next-brief feed; the entire string was authored
    //     (proc returns null).
    private let dash               = "-"
    private let fallbackTrailer    = "-"
    /// BOL # — real `loads.bolNumber` off the close-out packet; em-dash
    /// until the proc returns or when the column is null.
    private var fallbackBolNumber: String { nonEmpty(closeout?.bolNumber) ?? dash }
    /// SHIPPER name / address — real `users.name` (shipperId JOIN) +
    /// composed `loads.pickupLocation` address off the close-out packet.
    private var fallbackShipperN: String { nonEmpty(closeout?.shipperName) ?? dash }
    private var fallbackShipperA: String { nonEmpty(closeout?.shipperAddress) ?? dash }
    /// CONSIGNEE name / address — name is ALWAYS null server-side (no
    /// consignee column on loads → honest em-dash); address composes from
    /// the real `loads.deliveryLocation` JSON.
    private var fallbackConsignN: String { nonEmpty(closeout?.consigneeName) ?? dash }
    private var fallbackConsignA: String { nonEmpty(closeout?.consigneeAddress) ?? dash }
    // M2 doctrine (110th→111th hygiene firing): seal IDs are PII and must
    // hydrate from the live close-out packet. The server types `sealNumbers`
    // as `string | null` and currently always returns null (no
    // `loads.sealNumbers` column), so sealFactValue collapses the row to "-"
    // rather than fabricating an identifier. Same PII-collapse pattern landed
    // on 018_ActiveEnrouteLoaded.swift:75 (fallbackSealID).
    private var sealFactValue: String {
        guard let seal = nonEmpty(closeout?.sealNumbers) else { return "-" }
        return "\(seal) intact"
    }
    private let fallbackDoor       = "-"
    /// Trip START — real `departedAt` (first load_stops.departedAt ??
    /// loads.pickupDate) off the close-out packet, formatted local; em-dash
    /// until the proc returns or when null.
    private var fallbackStart: String { closeoutTime(closeout?.departedAt) }
    /// Trip END — real `arrivedAt` (last load_stops.arrivedAt ??
    /// loads.actualDeliveryDate), falling back to `actualDeliveryDate`;
    /// em-dash until either resolves.
    private var fallbackEnd: String {
        closeoutTime(closeout?.arrivedAt ?? closeout?.actualDeliveryDate)
    }
    /// DOOR TIME — no billed door-time projection reaches this screen
    /// (server returns null — no source). Honest em-dash.
    private let fallbackDoorTime   = "-"

    /// "N of N delivered" + the BOL "PIECES DELIVERED" row. No live
    /// unloaded-unit count reaches this screen, so the count collapses to
    /// the honest em-dash sentinel rather than a seeded "26".
    private var piecesDeliveredText: String { dash }

    // MARK: - Live computed getters (real proc/model → honest em-dash)

    /// BOL "SIGNED BY" — the real receiver who signed the POD at the dock
    /// (`loads.getCloseoutSummary.signedBy`, sourced from the latest POD
    /// document meta server-side), with the delivered timestamp
    /// (`signedAt`, formatted local) appended when present. Honest "-"
    /// until the close-out proc returns a signer — no authored persona,
    /// no baked time.
    private var signedByValue: String {
        guard let name = nonEmpty(closeout?.signedBy) else { return dash }
        if let raw = nonEmpty(closeout?.signedAt),
           let stamp = Self.formatPODTime(raw) {
            return "\(name) · \(stamp)"
        }
        return name
    }

    /// Close-out detention amount from the verified calculation history. The
    /// legacy closeout sum has no currency field, so it cannot truthfully back
    /// a money label by itself.
    private var detChargeValue: String {
        guard let event = detentionHistory,
              event.commercialState == "verified_calculation",
              let charge = event.totalCharge,
              let currency = event.currency else { return dash }
        return money(charge, currency: currency)
    }

    /// Verified free/billable minutes plus source reference. A rate-per-hour
    /// is not part of this history projection and is never reverse-engineered.
    private var detDetailValue: String {
        guard let event = detentionHistory,
              event.commercialState == "verified_calculation" else {
            return detentionHistoryError == nil ? dash : "Calculation unavailable"
        }
        var parts: [String] = []
        if let freeMins = event.freeTimeMinutes {
            parts.append("\(freeMins) min free")
        }
        if let billable = event.billableMinutes {
            parts.append("\(billable) min billed")
        }
        if let source = nonEmpty(event.sourceReference) {
            parts.append(source)
        }
        return parts.isEmpty ? dash : parts.joined(separator: " · ")
    }

    /// Break / overflow-lot guidance. The yard-occupancy, overflow-slot,
    /// and next-brief feeds do not exist on the wire, so the only honest
    /// rendering is the static doctrine line — the authored figures
    /// ("row C · 14 open slots · 06:55 · 17:03") are dropped entirely.
    private var breakInfoText: String {
        "Your 10-hour break starts now."
    }

    /// Trim + nil-collapse a nullable server string: returns nil for nil,
    /// empty, or whitespace-only values so every close-out getter renders
    /// the honest em-dash sentinel rather than a blank/whitespace string.
    private func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else { return nil }
        return t
    }

    /// Parse a nullable ISO-8601 close-out timestamp → a short local time
    /// (e.g. "4:48 PM"); honest em-dash when nil/empty/unparseable. Drives
    /// the trip START / END metric values.
    private func closeoutTime(_ iso: String?) -> String {
        guard let raw = nonEmpty(iso), let out = Self.formatPODTime(raw) else { return dash }
        return out
    }

    private func money(
        _ value: Double,
        currency: TruckDetentionNegotiatedTerms.Currency
    ) -> String {
        value.formatted(.currency(code: currency.rawValue))
    }

    /// Parse the server ISO-8601 `submittedAt` → a short local time
    /// (e.g. "4:48 PM"). Returns nil when unparseable so the SIGNED-BY
    /// row stays honest rather than echoing raw text. Mirrors 111.
    private static func formatPODTime(_ iso: String) -> String? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let d = withFrac.date(from: iso) ?? plain.date(from: iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "h:mm a"
        return out.string(from: d)
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                podAdvanceBanner
                bolCard
                metricStrip
                breakCard
                nrcCardIfHazmat7
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .eusoRefreshTask { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    // MARK: - NRC compliance card (Hazmat-7 closure)

    /// Driver-side NRC card. Renders only on hazmat-7 loads. Driver
    /// gets the "Log reading" CTA — this is the natural moment to
    /// log a final dosimetry reading at the consignee before the
    /// load closes. Server captures the entire chain alongside POD.
    @ViewBuilder
    private var nrcCardIfHazmat7: some View {
        if isHazmat7Load {
            NRCComplianceCard(loadId: lifecycle.loadId, driverSide: true)
                .environmentObject(session)
        }
    }

    private var isHazmat7Load: Bool {
        let h = (activeLoad?.hazmatClass ?? "").lowercased()
        let c = (activeLoad?.cargoType ?? "").lowercased()
        if h.contains("7") || h == "class_7" || h == "class 7" { return true }
        if c.contains("radioactive") || c.contains("hazmat-7") || c.contains("class-7") { return true }
        return false
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
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
                    Text("LOAD CLOSED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.success)
                    Text("· \(TransportLexicon.short(.detention, mode: resolvedMode).uppercased()) BILLED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    // 2026-05-17 — Mode chip on paperwork close-out
                    // header. POD / BOL / mate's-receipt close-out
                    // differs by mode; the chip surfaces which legal
                    // shape applies to the documents being filed.
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("\(piecesDeliveredText) delivered · door \(fallbackDoor)")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(fallbackTrailer)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(Brand.success.opacity(0.2))
                    .frame(width: 38, height: 38)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Brand.success)
            }
        }
        .padding(.top, 4)
    }

    // MARK: POD auto-advance banner (honest failure surface)

    /// Renders only when the UNLOADED → POD PENDING auto-advance failed.
    /// Carries the real server/transport reason so the driver knows the
    /// close-out is stalled rather than silently believing it advanced.
    @ViewBuilder
    private var podAdvanceBanner: some View {
        if let msg = podAdvanceError {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text("POD STEP STALLED")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(msg)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    Task {
                        didAttemptPodAdvance = false
                        podAdvanceError = nil
                        await lifecycle.refresh()
                        await advancePodIfUnloaded()
                    }
                } label: {
                    Text("Retry")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(Brand.warning)
                }
                .buttonStyle(.plain)
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Brand.warning.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: BOL card

    private var bolCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(TransportLexicon.short(.billOfLading, mode: resolvedMode).uppercased()) · SIGNED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("BOL #\(fallbackBolNumber)")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Shipper → Consignee
            HStack(alignment: .top, spacing: Space.s3) {
                partyBlock(label: "SHIPPER", name: fallbackShipperN, address: fallbackShipperA)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.top, 18)
                partyBlock(label: "CONSIGNEE", name: fallbackConsignN, address: fallbackConsignA)
            }

            // Facts grid
            VStack(spacing: 0) {
                factRow(
                    label: "PIECES DELIVERED",
                    value: piecesDeliveredText == dash
                        ? dash
                        : "\(piecesDeliveredText) \(ctx.unloadUnitLabel)",
                    affirm: piecesDeliveredText != dash
                )
                divider
                factRow(
                    label: "SEAL BEFORE → AFTER",
                    value: sealFactValue,
                    affirm: sealFactValue != "-"
                )
                divider
                factRow(label: "SIGNED BY", value: signedByValue, affirm: false)
                divider
                factRow(label: "OS&D", value: "No over / short / damage", affirm: true)
            }
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var divider: some View {
        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s3)
    }

    private func partyBlock(label: String, name: String, address: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(name)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(address)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func factRow(label: String, value: String, affirm: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(affirm ? Brand.success : palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
    }

    // MARK: Metric strip

    private var metricStrip: some View {
        HStack(spacing: Space.s2) {
            metric(label: "START",      value: fallbackStart,      color: palette.textPrimary)
            metric(label: "END",        value: fallbackEnd,        color: palette.textPrimary)
            metric(label: "DOOR TIME",  value: fallbackDoorTime,   color: palette.textPrimary)
            metric(label: TransportLexicon.short(.detention, mode: resolvedMode).uppercased(), value: detChargeValue, color: Brand.warning, caption: detDetailValue)
        }
    }

    private func metric(label: String, value: String, color: Color, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let cap = caption {
                Text(cap)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    // MARK: Break card

    private var breakCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 40, height: 40)
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(breakInfoText)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        VStack(spacing: Space.s3) {
            // Counterparty rating CTA — only renders once. Skipping
            // is fine; the prompt re-fires on the next delivered
            // load. Server rejects duplicate ratings per
            // (fromUserId × toUserId × loadId).
            Button { showRateShipper = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Rate this shipper")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 12)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.4))
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showRateShipper) {
                RatingPromptView(
                    direction: .driverRatesShipper,
                    counterpartyId: String(activeLoad?.shipperId ?? 0),
                    counterpartyName: nil,
                    loadId: lifecycle.loadId.isEmpty ? "0" : lifecycle.loadId,
                    laneSummary: paperworkLaneSummary
                )
                .environment(\.palette, palette)
            }

            // Dock-worker counter-party POD — Tier 3 #10. Driver hands
            // the phone to the receiver's dock worker; the sheet
            // chains their signature off the driver's POD row.
            Button { showDockPod = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.shield.checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Receiver sign-off")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 12)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.4))
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDockPod) {
                DockWorkerPodSheet(
                    loadId: lifecycle.loadId.isEmpty ? "0" : lifecycle.loadId,
                    osdReportRef: nil,
                    onSigned: { _ in showDockPod = false }
                )
            }

            HStack(spacing: Space.s3) {
                Button { showBol = true } label: {
                    Text("View \(TransportLexicon.short(.billOfLading, mode: resolvedMode))")
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
                .sheet(isPresented: $showBol) {
                    PickupBolSigning()
                        .environment(\.palette, palette)
                        .eusoSheetX()
                }

                CTAButton(
                    title: "Start 10-hour break",
                    action: { Task { await startBreak() } },
                    isLoading: isStartingBreak
                )
            }
        }
    }

    // MARK: - Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)

        // Live close-out packet (`loads.getCloseoutSummary`) — the single
        // source for BOL #, shipper/consignee name + address, trip
        // START / END, seal numbers, detention $, and SIGNED-BY. Every
        // field is nullable; try? → nil keeps the screen on honest em-dash
        // sentinels until the proc returns real values.
        closeout = try? await EusoTripAPI.shared.loads.getCloseoutSummary(loadId: n)

        do {
            let events = try await EusoTripAPI.shared.detention.getHistory(limit: 100).events
            detentionHistory = events.first {
                $0.loadId == n && $0.commercialState == "verified_calculation"
            }
            detentionHistoryError = nil
        } catch {
            detentionHistory = nil
            detentionHistoryError = error.eusoUserCopy
        }

        // POD desync fix — once the load + its lifecycle have hydrated,
        // auto-advance off `unloaded` so the close-out doesn't dead-end.
        await advancePodIfUnloaded()
    }

    /// If the hydrated load is sitting at `unloaded`, fire the
    /// UNLOADED_TO_POD_PENDING lifecycle transition once so the POD flow
    /// advances without the driver manually nudging it. The FSM now owns
    /// `pod_pending` (the server stopped force-setting it after
    /// `pod.submitPOD`), so this screen is responsible for the hop.
    ///
    /// Guarded twice over: `didAttemptPodAdvance` makes it one-shot, and
    /// the status check makes it fire ONLY for `unloaded` — never for a
    /// load already at `pod_pending`/`delivered`/etc. The transition goes
    /// through `lifecycle.execute(...)`, which auto-captures the device GPS
    /// fix. On failure we surface the real reason on `podAdvanceError`
    /// rather than pretending the load advanced.
    private func advancePodIfUnloaded() async {
        guard !didAttemptPodAdvance else { return }

        // Resolve the live status, preferring the lifecycle's last-applied
        // state over the load envelope's column (they should agree, but the
        // FSM is the source of truth for the current hop).
        let status = (lifecycle.currentState ?? activeLoad?.status ?? "").lowercased()
        guard status == "unloaded" else { return }

        // Mark the attempt before firing so a re-entrant `.task` (the screen
        // re-runs hydration on re-appear) can't double-issue the transition.
        didAttemptPodAdvance = true

        // Find the server-offered UNLOADED_TO_POD_PENDING hop. The FSM
        // exposes it in `availableTransitions` for a load at `unloaded`;
        // matching by `transitionId` keeps us aligned with the canonical
        // name (DriverNavController issues the same id for 024 → 025).
        let target = lifecycle.availableTransitions.first {
            $0.transitionId.uppercased() == "UNLOADED_TO_POD_PENDING"
        }
        guard let transition = target else {
            // No legal hop on the wire — honestly say so instead of forging
            // an advance. This means the FSM doesn't yet offer it (e.g. a
            // server-side guard hasn't cleared), which is the truth.
            podAdvanceError = "POD step couldn't auto-advance — the lifecycle did not offer UNLOADED → POD PENDING for this load. Pull to refresh or contact dispatch."
            return
        }

        // `execute(...)` auto-captures GPS and refreshes the lifecycle on
        // success. On failure it sets `lifecycle.lastError`; mirror that
        // honestly so the driver sees a real reason, not a dead-end.
        let ok = await lifecycle.execute(transition)
        if ok {
            podAdvanceError = nil
        } else {
            let reason = lifecycle.lastError?.localizedDescription
            podAdvanceError = "POD step couldn't auto-advance" +
                (reason.map { " — \($0)" } ?? " — the lifecycle transition was rejected. Pull to refresh or contact dispatch.")
        }
    }

    /// Origin → Destination shorthand for the rating prompt. Falls
    /// through to nil so the prompt's header card collapses cleanly
    /// when neither side of the lane is hydrated yet.
    private var paperworkLaneSummary: String? {
        guard let load = activeLoad else { return nil }
        let parts: [String] = {
            var out: [String] = []
            if let p = load.pickupLocation, !p.city.isEmpty {
                out.append("\(p.city), \(p.state)")
            }
            if let d = load.deliveryLocation, !d.city.isEmpty {
                out.append("\(d.city), \(d.state)")
            }
            return out
        }()
        return parts.isEmpty ? nil : parts.joined(separator: " → ")
    }

    private func startBreak() async {
        isStartingBreak = true
        defer { isStartingBreak = false }
        let forwardKeys = ["off_duty", "break", "completed", "closed"]
        let candidate = lifecycle.availableTransitions.first { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        } ?? lifecycle.availableTransitions.first
        if let transition = candidate {
            _ = await lifecycle.execute(transition)
        }
        advance?()
    }
}

struct PaperworkScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            Paperwork(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_025(),
                      trailing: driverNavTrailing_025(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_025() -> [NavSlot] {
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_025() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("025 · Paperwork · Dark") {
    PaperworkScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("025 · Paperwork · Light") {
    PaperworkScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
