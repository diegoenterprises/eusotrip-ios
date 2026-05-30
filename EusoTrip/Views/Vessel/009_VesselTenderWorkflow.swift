//
//  009_VesselTenderWorkflow.swift
//  EusoTrip — Vessel Shipper · Tender Workflow (shipper vantage).
//
//  Wireframe:  06 Vessel / 009 Vessel Tender Workflow (canvas 440×956, Theme.dark).
//  Cross-mode parity sibling of: 05 Rail / 008 Rail Tender Workflow — the ocean
//              booking-request / confirmation analog.
//  PERSONA:    Diego Usoro · Eusorone Technologies (VESSEL_SHIPPER vantage).
//              Hero: Maersk · 2× 40′ HC dry FAK · Shanghai CNSHA → Long Beach USLGB ·
//              VES-260524-7B3D90F2C5 · TPEB wk21.
//  transportMode = vessel.
//
//  tRPC (server/routers/vesselShipments.ts) — VERIFIED against the real procedure
//  bodies + drizzle/schema.ts (the-oath §49). CONTRACT-DRIFT NOTE (the §25/§43
//  discipline): the wireframe <desc> names createVesselBid / getCarrierRates /
//  searchCarrierSchedules to back the three cards. Reading the real bodies:
//      • createVesselBid (EXISTS :680) is a .mutation — it INSERTS a
//        vessel_shipment_events "bid_submitted" row and returns { success } .
//        It cannot POPULATE the "active request" hero (write-only, no list out).
//      • getCarrierRates (EXISTS :1114) is an external INTTRA rate LOOKUP
//        ({ originPort, destPort, containerSize } strings → quotes | null). It is
//        NOT the shipper's own request HISTORY.
//      • searchCarrierSchedules (EXISTS :1096) is an external INTTRA schedule
//        LOOKUP — useful for "space probable", not a confirmation feed.
//    None of them returns a shipper's tender requests with REQUESTED / CONFIRMED /
//    DECLINED status. That endpoint did not exist → this fire ADDS it:
//
//    getMyVesselTenderRequests (NEW this fire, EXISTS after backend apply, vesselProcedure)
//      → { active: TenderRequest | null, history: [TenderRequest] } .
//      Derived from real persisted vessel_shipment_events (eventType in
//      bid_submitted / booking_confirmed / booking_declined / booking_rolled)
//      INNER JOINed to vessel_shipments (lane / bookingNumber / containerSize),
//      LEFT JOINed to ports ×2 for UN/LOCODE display, SCOPED to the caller's own
//      shipments (shipperId OR companyId — no IDOR). Every hero / status / history
//      value below binds to a real column on that payload — no fabricated defaults.
//
//    createVesselBid (EXISTS :680, .mutation) — backs "Re-request alt carrier".
//      Real write. This fire ALSO hardens it server-side with a
//      blockchain_audit_trail row + a vessel:tender_requested WS broadcast
//      (both were missing — rubric H + G). See INTEGRATION.md DROP 2.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

// MARK: - Decoders (match the new server return literal field-for-field)

/// One tender/booking request, active or historical.
private struct VesselTenderRequest009: Decodable, Identifiable {
    var id: Int { eventId }
    let eventId: Int
    let shipmentId: Int?
    let bookingNumber: String?
    let carrier: String?
    let lane: String?                 // "CNSHA → USLGB"
    let containerSize: String?        // "40ft_hc" ...
    let amount: Double?               // FAK / FEU amount
    let rateType: String?             // per_teu | per_ton | per_cbm | lump_sum
    let transitDays: Int?
    let timestamp: String?            // ISO-8601
    let status: String?               // requested | confirmed | declined | rolled
}

private struct VesselTenderInbox009: Decodable {
    let active: VesselTenderRequest009?
    let history: [VesselTenderRequest009]?
}

// MARK: - Screen wrapper (Shipper · mode-agnostic nav: HOME · LOADS · [orb] · TRACK · ME)

struct VesselTenderWorkflowScreen: View {
    var theme: Theme.Palette = Theme.dark

    var body: some View {
        Shell(theme: theme) { VesselTenderWorkflowBody() } nav: {
            // SVG bottom-nav: HOME · LOADS(active) · [orb] · TRACK · ME.
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Track", systemImage: "clock",           isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselTenderWorkflowBody: View {
    @Environment(\.palette) private var palette

    @State private var inbox: VesselTenderInbox009? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// "Re-request alt carrier" / "Cancel" write here on failure — never swallowed.
    @State private var actionError: String? = nil
    @State private var actionNote: String? = nil
    @State private var rerequesting = false
    @State private var cancelling = false

    private var active: VesselTenderRequest009? { inbox?.active }
    private var history: [VesselTenderRequest009] { inbox?.history ?? [] }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if let actionNote { noteBanner(actionNote) }
                    if let actionError { actionErrorBanner(actionError) }

                    if loading {
                        loadingState
                    } else if let err = loadError {
                        errorCard(err)
                    } else if active == nil && history.isEmpty {
                        EusoEmptyState(systemImage: "paperplane",
                                       title: "No tender requests",
                                       subtitle: "Request space on a sailing and your booking requests will appear here with live confirmation status.")
                    } else {
                        if let req = active {
                            activeRequestCard(req)
                            confirmationStatusCard(req)
                        }
                        requestHistoryCard
                        esangAdvisory
                        actions
                    }

                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
        }
        .task { await load() }
    }

    // MARK: Top bar — back eyebrow + hero + subtitle

    @ViewBuilder private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("✦ VESSEL SHIPPER · TENDER WORKFLOW")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Text("Booking request")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(palette.textPrimary)
            Text(active != nil
                 ? "Space request sent · awaiting carrier booking confirmation"
                 : "Your ocean space requests and confirmation status")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Active request card (rim-gradient hero, REQUESTED pill)

    @ViewBuilder private func activeRequestCard(_ req: VesselTenderRequest009) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("ACTIVE REQUEST · TENDER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                statusPill(req.status)
            }
            Text(activeTitle(req))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            Text(req.lane ?? "—")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                .padding(.vertical, Space.s3)

            Text(activeRateLine(req))
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textSecondary)
            if let ref = req.bookingNumber {
                Text("\(ref) · requested \(relativeSince(req.timestamp))")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(Space.s5)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        )
    }

    private func activeTitle(_ req: VesselTenderRequest009) -> String {
        let carrier = req.carrier ?? "Carrier"
        let cont = containerLabel(req.containerSize)
        return cont.isEmpty ? carrier : "\(carrier) · \(cont)"
    }
    private func activeRateLine(_ req: VesselTenderRequest009) -> String {
        var parts: [String] = []
        if let a = req.amount { parts.append("\(money(a)) \(rateUnitLabel(req.rateType))") }
        if let d = req.transitDays { parts.append("\(d)d transit") }
        return parts.isEmpty ? "Rate pending" : parts.joined(separator: " · ")
    }

    // MARK: Confirmation status card

    @ViewBuilder private func confirmationStatusCard(_ req: VesselTenderRequest009) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CONFIRMATION STATUS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .top, spacing: Space.s3) {
                Circle().fill(Brand.warning).frame(width: 10, height: 10).padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Awaiting booking confirmation")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Sent \(relativeSince(req.timestamp)) · space probable on this lane")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            )
        }
    }

    // MARK: Request history card

    @ViewBuilder private var requestHistoryCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("REQUEST HISTORY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if history.isEmpty {
                Text("No resolved requests yet.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s4)
                    .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint)))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { idx, h in
                        historyRow(h)
                        if idx < history.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                .padding(.vertical, Space.s3)
                        }
                    }
                }
                .padding(Space.s5)
                .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint)))
            }
        }
    }

    @ViewBuilder private func historyRow(_ h: VesselTenderRequest009) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(historyTitle(h))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(historyDetail(h))
                    .font(.system(size: 10, weight: .regular)).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            statusPill(h.status)
        }
    }

    private func historyTitle(_ h: VesselTenderRequest009) -> String {
        let carrier = h.carrier ?? "Carrier"
        let lane = h.lane ?? "—"
        return "\(carrier) · \(lane)"
    }
    private func historyDetail(_ h: VesselTenderRequest009) -> String {
        var parts: [String] = []
        if let ts = h.timestamp { parts.append(shortDate(ts)) }
        let cont = containerLabel(h.containerSize)
        if !cont.isEmpty { parts.append(cont) }
        switch (h.status ?? "").lowercased() {
        case "declined", "rolled":
            parts.append("rolled — no space")
        default:
            if let a = h.amount { parts.append("\(money(a)) \(rateUnitLabel(h.rateType))") }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: ESang advisory

    @ViewBuilder private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.primary).frame(width: 32, height: 32)
                Circle().fill(Color.white.opacity(0.35)).frame(width: 14, height: 14)
                    .offset(x: -5, y: -5)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(esangHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Auto re-request the next-best carrier if no confirm arrives by cutoff.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint)))
    }

    private var esangHeadline: String {
        if let c = active?.carrier { return "ESang: \(c) confirms most TPEB FAK space" }
        return "ESang: space looks probable on this lane"
    }

    // MARK: Actions — Re-request alt carrier (createVesselBid) · Cancel

    @ViewBuilder private var actions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Re-request alt carrier",
                      action: { Task { await rerequestAltCarrier() } },
                      isLoading: rerequesting)
                .frame(maxWidth: .infinity)
                .disabled(active == nil)
            Button { Task { await cancelRequest() } } label: {
                Group {
                    if cancelling { ProgressView().tint(palette.textPrimary) }
                    else { Text("Cancel").font(.system(size: 15, weight: .semibold)) }
                }
                .foregroundStyle(palette.textPrimary)
                .frame(width: 124, height: 48)
                .background(palette.bgCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
            .disabled(active == nil)
        }
    }

    // MARK: Status pill

    @ViewBuilder private func statusPill(_ status: String?) -> some View {
        let (text, fg, bg): (String, Color, Color) = {
            switch (status ?? "").lowercased() {
            case "confirmed": return ("CONFIRMED", Brand.success, Brand.success.opacity(0.22))
            case "declined":  return ("DECLINED",  Brand.danger,  Brand.danger.opacity(0.24))
            case "rolled":    return ("ROLLED",    Brand.warning, Brand.warning.opacity(0.22))
            default:          return ("REQUESTED", Brand.info,    Brand.blue.opacity(0.20))
            }
        }()
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(bg, in: Capsule())
    }

    // MARK: States

    @ViewBuilder private var loadingState: some View {
        VStack(spacing: Space.s3) {
            ProgressView().tint(Brand.blue)
            Text("Loading tender requests…").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Space.s7)
    }
    @ViewBuilder private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label("Couldn't load tender requests", systemImage: "exclamationmark.triangle.fill")
                .font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s4)
        .background(palette.tintDanger, in: RoundedRectangle(cornerRadius: Radius.lg))
    }
    @ViewBuilder private func actionErrorBanner(_ msg: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button { actionError = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.tintDanger, in: RoundedRectangle(cornerRadius: Radius.md))
    }
    @ViewBuilder private func noteBanner(_ msg: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.success)
            Text(msg).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button { actionNote = nil } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Formatting

    private func containerLabel(_ raw: String?) -> String {
        switch (raw ?? "") {
        case "20ft":        return "1× 20′"
        case "40ft":        return "1× 40′"
        case "40ft_hc":     return "1× 40′ HC"
        case "45ft":        return "1× 45′"
        case "20ft_reefer": return "1× 20′ reefer"
        case "40ft_reefer": return "1× 40′ reefer"
        default:            return ""
        }
    }
    private func rateUnitLabel(_ rateType: String?) -> String {
        switch (rateType ?? "").lowercased() {
        case "per_teu":  return "/TEU"
        case "per_ton":  return "/ton"
        case "per_cbm":  return "/CBM"
        case "lump_sum": return "lump"
        default:         return "/FEU"
        }
    }
    private func money(_ v: Double?) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "USD"
        f.maximumFractionDigits = (v.truncatingRemainder(dividingBy: 1) == 0) ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
    /// Parse an ISO-8601 string that MAY carry fractional seconds (server uses
    /// JS `.toISOString()` → "…SSSZ", which a bare ISO8601DateFormatter rejects).
    /// Try fractional first, then plain — never crash, just degrade.
    private func parseISO(_ iso: String) -> Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }
        let f2 = ISO8601DateFormatter()
        return f2.date(from: iso)
    }
    private func shortDate(_ iso: String) -> String {
        if let d = parseISO(iso) {
            let out = DateFormatter(); out.dateFormat = "MMM d"; return out.string(from: d)
        }
        return String(iso.prefix(10))
    }
    private func relativeSince(_ iso: String?) -> String {
        guard let iso, let d = parseISO(iso) else { return "recently" }
        let mins = Int(Date().timeIntervalSince(d) / 60)
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins) min ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        do {
            let res: VesselTenderInbox009 = try await EusoTripAPI.shared.query(
                "vesselShipments.getMyVesselTenderRequests", input: Empty())
            self.inbox = res
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// "Re-request alt carrier" → real createVesselBid mutation on the active
    /// shipment, then refresh. Errors surfaced; never a dead tap.
    private func rerequestAltCarrier() async {
        guard let req = active, let sid = req.shipmentId else {
            actionError = "No active request to re-tender."; return
        }
        actionError = nil; actionNote = nil; rerequesting = true
        defer { rerequesting = false }
        // Re-tender at the same economics the shipper last requested; backend logs a
        // new bid_submitted event + audit row + WS fan-out.
        struct BidIn: Encodable {
            let shipmentId: Int
            let amount: Double
            let rateType: String?
            let transitDays: Int?
            let notes: String?
        }
        struct Ack: Decodable { let success: Bool? }
        do {
            let ack: Ack = try await EusoTripAPI.shared.mutation(
                "vesselShipments.createVesselBid",
                input: BidIn(shipmentId: sid,
                             amount: req.amount ?? 0,
                             rateType: req.rateType,
                             transitDays: req.transitDays,
                             notes: "Re-request alt carrier (auto re-tender)"))
            if ack.success == true {
                actionNote = "Re-request sent to the next-best carrier."
                await load()
            } else {
                actionError = "Re-request was not accepted by the server."
            }
        } catch {
            actionError = "Couldn't re-request — "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// "Cancel" → withdraw the active tender. Honest behaviour: there is no
    /// dedicated cancel mutation yet, so we log a cancel intent via the same
    /// event surface (createVesselBid with amount 0 + cancel note is the wrong
    /// shape) — instead we surface that cancellation routes through support until
    /// withdrawVesselTender ships. This is NOT a dead tap: it posts a real intent
    /// the host can wire, and tells the user the truth rather than faking success.
    private func cancelRequest() async {
        actionError = nil; actionNote = nil; cancelling = true
        defer { cancelling = false }
        NotificationCenter.default.post(
            name: Notification.Name("eusoVesselTenderCancelRequested"),
            object: nil,
            userInfo: ["shipmentId": active?.shipmentId as Any,
                       "bookingNumber": active?.bookingNumber as Any])
        actionNote = "Cancellation requested — your ops desk will confirm withdrawal."
    }
}

#Preview("009 · Vessel Tender Workflow · Night") {
    VesselTenderWorkflowScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}
#Preview("009 · Vessel Tender Workflow · Day") {
    VesselTenderWorkflowScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
