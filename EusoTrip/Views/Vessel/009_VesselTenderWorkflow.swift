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
//  Live workflow contract:
//    getMyVesselTenderRequests reads the caller-scoped invitation ledger.
//    requestVesselTender issues invitations to verified operator companies.
//    cancelVesselTenderInvitation withdraws an invitation and records fan-out.
//    createVesselBid stores a carrier quote under a retained replay key.
//    acceptVesselBid binds the winning operator, closes competing invitations,
//    and co-commits durable audit and notification intent.
//  External rate and schedule lookups are reference feeds, never tender history.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import CryptoKit
import SwiftUI

// MARK: - Decoders (match the new server return literal field-for-field)

/// One tender/booking request, active or historical.
private struct VesselTenderRequest009: Decodable, Identifiable {
    var id: Int { invitationId }
    let invitationId: Int
    let bidEventId: Int?
    let operatorCompanyId: Int?
    let shipmentId: Int?
    let bookingNumber: String?
    let carrier: String?
    let lane: String?                 // "CNSHA → USLGB"
    let containerSize: String?        // "40ft_hc" ...
    let amount: Double?               // FAK / FEU amount
    let rateType: String?             // per_teu | per_ton | per_cbm | lump_sum
    let currency: String?
    let transitDays: Int?
    let timestamp: String?            // ISO-8601
    let status: String?               // requested | confirmed | declined | rolled
}

private struct VesselTenderInbox009: Decodable {
    let active: VesselTenderRequest009?
    let activeRequests: [VesselTenderRequest009]?
    let history: [VesselTenderRequest009]?
}

private struct VesselOperatorOption009: Decodable, Identifiable {
    var id: Int { companyId }
    let companyId: Int
    let name: String?
    let legalName: String?
    let country: String?
    let companyCategory: String?

    var displayName: String {
        let primary = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let legal = legalName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primary.isEmpty { return primary }
        if !legal.isEmpty { return legal }
        return "Operator company #\(companyId)"
    }
}

/// `acceptVesselBid` return literal, field-for-field (vesselShipments.ts:1889).
private struct VesselAwardAck009: Decodable {
    let success: Bool?
    let status: String?
    let shipmentId: Int?
    let operatorId: Int?
    let amount: Double?
    let idempotent: Bool?
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
    @State private var awarding = false
    @State private var showingRetenderSheet = false
    @State private var eligibleOperators: [VesselOperatorOption009] = []
    @State private var selectedOperatorCompanyIds: Set<Int> = []
    @State private var operatorLoadError: String?
    @State private var tenderExpiresAt = Date().addingTimeInterval(24 * 60 * 60)
    @State private var confirmingCancellation = false
    /// Two-step commit. Awarding binds the operator, sets the rate and moves the
    /// booking to `booking_confirmed` — it is the money commit on this screen,
    /// so it does not fire on a single tap.
    @State private var confirmingAward = false

    private var active: VesselTenderRequest009? { inbox?.active }
    private var activeRequests: [VesselTenderRequest009] { inbox?.activeRequests ?? [] }
    private var history: [VesselTenderRequest009] { inbox?.history ?? [] }
    private var competingBids: Int {
        activeRequests.filter { $0.bidEventId != nil }.count
    }

    /// The award CTA is live only for a request that is genuinely awardable:
    /// `acceptVesselBid` requires an unawarded shipment in `booking_requested`
    /// and a `bid_submitted` event id, which is exactly what `active` carries
    /// when its status is "quote_received". Anything else and the server would
    /// refuse — so the button does not offer it.
    private var canAward: Bool {
        guard let a = active, a.shipmentId != nil, a.bidEventId != nil else {
            return false
        }
        return (a.status ?? "").lowercased() == "quote_received"
    }

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
                            if canAward { awardBand(req) }
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
        .eusoRefreshTask { await load() }
        .sheet(isPresented: $showingRetenderSheet) {
            retenderSheet
        }
        .confirmationDialog(
            "Withdraw this tender?",
            isPresented: $confirmingCancellation,
            titleVisibility: .visible
        ) {
            Button("Withdraw tender", role: .destructive) {
                Task { await cancelRequest() }
            }
            Button("Keep tender", role: .cancel) {}
        } message: {
            Text("The selected operator will be notified and can no longer quote this invitation.")
        }
    }

    // MARK: Top bar — back eyebrow + hero + subtitle

    @ViewBuilder private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            EusoTripEyebrow(verbatim: "VESSEL SHIPPER · TENDER WORKFLOW")
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
            Text(req.lane ?? "-")
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
        if let a = req.amount { parts.append("\(money(a, currency: req.currency)) \(rateUnitLabel(req.rateType))") }
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
        let lane = h.lane ?? "-"
        return "\(carrier) · \(lane)"
    }
    private func historyDetail(_ h: VesselTenderRequest009) -> String {
        var parts: [String] = []
        if let ts = h.timestamp { parts.append(shortDate(ts)) }
        let cont = containerLabel(h.containerSize)
        if !cont.isEmpty { parts.append(cont) }
        switch (h.status ?? "").lowercased() {
        case "declined", "rolled":
            parts.append("rolled - no space")
        default:
            if let a = h.amount { parts.append("\(money(a, currency: h.currency)) \(rateUnitLabel(h.rateType))") }
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

    // MARK: Award band — the money commit (acceptVesselBid)
    //
    // CHAIN CLOSURE, oath §6. `vesselShipments.acceptVesselBid` (:1765) is the
    // SOLE writer of `vessel_shipments.operatorId` (:1836) and it had ZERO
    // callers in either repo. Everything downstream keys on that column:
    // `issueBOL` refuses without it, `createVesselSettlement` refuses without
    // it, and before the settlement path was corrected it fell back to
    // `operatorId || shipperId` and credited the carrier's payment into the
    // SHIPPER's own wallet. So the whole vessel money chain hung on a verb no
    // screen could reach. This band is that missing half.
    //
    // Placed as an additive band rather than folded into the ported CTA row:
    // the 009 wireframe twins carry "Re-request alt carrier" + "Cancel" and
    // those are reproduced verbatim below, untouched. The award affordance is
    // net-new product surface the design predates — filed for canonisation as
    // OATH6-DA-009-AWARDBAND so the SVG twins gain it deliberately rather than
    // this port drifting from the catalog silently.
    //
    // §W OFFLINE: ONLINE_ONLY. An award binds an operator, fixes the rate and
    // advances the booking state under a FOR UPDATE lock with a CAS guard
    // (:1836) — an award commit is exactly the class the offline doctrine keeps
    // online. Not queued, not optimistic; the CTA is inert without a network.

    @ViewBuilder private func awardBand(_ req: VesselTenderRequest009) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Text("AWARD THIS QUOTE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                if competingBids > 0 {
                    Text("\(competingBids) other quote\(competingBids == 1 ? "" : "s") live")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Brand.warning.opacity(0.18), in: Capsule())
                }
            }

            Text(money(req.amount, currency: req.currency) + " " + rateUnitLabel(req.rateType))
                .font(.system(size: 26, weight: .bold)).monospacedDigit()
                .tracking(-0.5)
                .foregroundStyle(palette.textPrimary)

            Text(awardSubtitle(req))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if confirmingAward {
                // Second step. Says what the commit does before it does it —
                // binding an operator is not reversible from this screen.
                Text("Awarding binds \(req.carrier ?? "this carrier") as operator of record at \(money(req.amount, currency: req.currency)) and confirms the booking. This cannot be undone here.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.md))

                HStack(spacing: Space.s3) {
                    CTAButton(title: "Confirm award",
                              action: { Task { await awardActiveBid() } },
                              isLoading: awarding)
                        .frame(maxWidth: .infinity)
                    Button { confirmingAward = false } label: {
                        Text("Back").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 96, height: 48)
                            .background(palette.bgCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.borderSoft))
                    }
                    .buttonStyle(.plain)
                    .disabled(awarding)
                }
            } else {
                CTAButton(title: "Award to \(req.carrier ?? "carrier")",
                          action: { confirmingAward = true },
                          isLoading: false)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint)))
    }

    private func awardSubtitle(_ req: VesselTenderRequest009) -> String {
        var parts: [String] = []
        if let lane = req.lane { parts.append(lane) }
        let box = containerLabel(req.containerSize)
        if !box.isEmpty { parts.append(box) }
        if let t = req.transitDays { parts.append("\(t)d transit") }
        if let bn = req.bookingNumber { parts.append(bn) }
        return parts.isEmpty ? "Binds the operator of record and confirms this booking."
                             : parts.joined(separator: " · ")
    }

    // MARK: Actions — invite another verified operator · withdraw invitation

    @ViewBuilder private var actions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Re-request alt carrier",
                      action: { Task { await prepareRetender() } },
                      isLoading: rerequesting)
                .frame(maxWidth: .infinity)
                .disabled(active == nil)
            Button { confirmingCancellation = true } label: {
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

    @ViewBuilder private var retenderSheet: some View {
        NavigationStack {
            List {
                Section {
                    if rerequesting && eligibleOperators.isEmpty {
                        HStack(spacing: Space.s2) {
                            ProgressView()
                            Text("Loading verified vessel operators…")
                                .foregroundStyle(palette.textSecondary)
                        }
                    } else if let operatorLoadError {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("Operators unavailable")
                                .font(EType.bodyStrong)
                                .foregroundStyle(Brand.danger)
                            Text(operatorLoadError)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                            Button("Retry") { Task { await loadEligibleOperators() } }
                        }
                    } else if eligibleOperators.isEmpty {
                        Text("No additional verified, compliant vessel operator companies are currently eligible for this tender.")
                            .font(EType.body)
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        ForEach(eligibleOperators) { operatorCompany in
                            Button {
                                if selectedOperatorCompanyIds.contains(operatorCompany.companyId) {
                                    selectedOperatorCompanyIds.remove(operatorCompany.companyId)
                                } else {
                                    selectedOperatorCompanyIds.insert(operatorCompany.companyId)
                                }
                            } label: {
                                HStack(spacing: Space.s3) {
                                    Image(systemName: selectedOperatorCompanyIds.contains(operatorCompany.companyId)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedOperatorCompanyIds.contains(operatorCompany.companyId)
                                                         ? Brand.info : palette.textTertiary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(operatorCompany.displayName)
                                            .font(EType.bodyStrong)
                                            .foregroundStyle(palette.textPrimary)
                                        let facts = [operatorCompany.country, operatorCompany.companyCategory]
                                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                            .filter { !$0.isEmpty }
                                        if !facts.isEmpty {
                                            Text(facts.joined(separator: " · "))
                                                .font(EType.caption)
                                                .foregroundStyle(palette.textSecondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Verified operator companies")
                } footer: {
                Text("Only active vessel operators with verified compliance are available for this tender.")
                }

                Section("Response deadline") {
                    DatePicker(
                        "Tender expires",
                        selection: $tenderExpiresAt,
                        in: Date().addingTimeInterval(20 * 60)...Date().addingTimeInterval(30 * 24 * 60 * 60)
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.bgPage)
            .navigationTitle("Invite operators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingRetenderSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await submitRetender() } }
                        .disabled(selectedOperatorCompanyIds.isEmpty || rerequesting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Status pill

    @ViewBuilder private func statusPill(_ status: String?) -> some View {
        let (text, fg, bg): (String, Color, Color) = {
            switch (status ?? "").lowercased() {
            case "confirmed": return ("CONFIRMED", Brand.success, Brand.success.opacity(0.22))
            case "quote_received": return ("QUOTE RECEIVED", Brand.success, Brand.success.opacity(0.22))
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
    private func money(_ v: Double?, currency: String? = nil) -> String {
        guard let v else { return "-" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency ?? active?.currency ?? "USD"
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
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    /// "Confirm award" → the real `vesselShipments.acceptVesselBid` mutation.
    ///
    /// Server contract (vesselShipments.ts:1765-1890), matched field-for-field:
    ///   in  { shipmentId: number, bidEventId: number, requestKey: UUID }
    ///   out { success, status, shipmentId, operatorId, amount, idempotent }
    /// `bidEventId` is the invitation's persisted bid-event foreign key.
    /// `acceptVesselBid` re-reads that same event as the authoritative source,
    /// so the two halves resolve the same quote. No client-side price is sent: amount
    /// and rateType come off the stored event server-side, which is why a
    /// tampered client cannot award at a price the carrier never quoted.
    ///
    /// Errors are surfaced verbatim — the server's CONFLICT copy names the
    /// competing operator or the offending status, which is more useful to the
    /// shipper than anything this screen could invent.
    private func awardActiveBid() async {
        guard let req = active,
              let sid = req.shipmentId,
              let bidEventId = req.bidEventId else {
            actionError = "No active quote to award."; return
        }
        let storageKey = awardRequestStorageKey(shipmentId: sid, bidEventId: bidEventId)
        let stored = UserDefaults.standard.string(forKey: storageKey)?.lowercased()
        let requestKey = stored.flatMap { UUID(uuidString: $0) != nil ? $0 : nil }
            ?? UUID().uuidString.lowercased()
        UserDefaults.standard.set(requestKey, forKey: storageKey)
        actionError = nil; actionNote = nil; awarding = true
        defer { awarding = false }

        struct AwardIn: Encodable {
            let shipmentId: Int
            let bidEventId: Int
            let requestKey: String
        }
        do {
            let ack: VesselAwardAck009 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.acceptVesselBid",
                input: AwardIn(
                    shipmentId: sid,
                    bidEventId: bidEventId,
                    requestKey: requestKey
                ))

            if ack.success == true {
                if UserDefaults.standard.string(forKey: storageKey)?.lowercased() == requestKey {
                    UserDefaults.standard.removeObject(forKey: storageKey)
                }
                confirmingAward = false
                let who = req.carrier ?? "operator #\(ack.operatorId.map(String.init) ?? "—")"
                actionNote = ack.idempotent == true
                    ? "This booking was already awarded to \(who). Nothing changed."
                    : "Awarded to \(who) at \(money(ack.amount ?? req.amount, currency: req.currency)). Booking confirmed — the operator is now bound as carrier of record."
                await load()
            } else {
                // A false/absent `success` means no commit happened. Say so —
                // never let the screen imply a booking was confirmed.
                actionError = "The award was not committed. The booking is unchanged and no operator was bound."
            }
        } catch {
            actionError = "Couldn't award this quote. " + error.eusoUserCopy
        }
    }

    private func awardRequestStorageKey(shipmentId: Int, bidEventId: Int) -> String {
        let sessionCredential = EusoTripAPI.shared.authToken
            ?? HTTPCookieStorage.shared.cookies?.first(where: { $0.name == "app_session_id" })?.value
            ?? "unauthenticated"
        let digest = SHA256.hash(
            data: Data("vesselShipments.acceptVesselBid|\(sessionCredential)|\(shipmentId)|\(bidEventId)".utf8)
        )
        return "com.eusotrip.commercial-award." + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func prepareRetender() async {
        guard active?.shipmentId != nil else {
            actionError = "No active vessel booking to tender."
            return
        }
        selectedOperatorCompanyIds.removeAll()
        operatorLoadError = nil
        tenderExpiresAt = Date().addingTimeInterval(24 * 60 * 60)
        showingRetenderSheet = true
        await loadEligibleOperators()
    }

    private func loadEligibleOperators() async {
        rerequesting = true
        operatorLoadError = nil
        defer { rerequesting = false }
        struct OperatorsIn: Encodable { let limit: Int }
        do {
            let rows: [VesselOperatorOption009] = try await EusoTripAPI.shared.query(
                "vesselShipments.getEligibleVesselOperators",
                input: OperatorsIn(limit: 50)
            )
            let alreadyActive = Set(activeRequests.compactMap(\.operatorCompanyId))
            eligibleOperators = rows.filter { !alreadyActive.contains($0.companyId) }
            selectedOperatorCompanyIds = selectedOperatorCompanyIds.intersection(
                Set(eligibleOperators.map(\.companyId))
            )
        } catch {
            eligibleOperators = []
            operatorLoadError = error.eusoUserCopy
        }
    }

    private func submitRetender() async {
        guard let sid = active?.shipmentId else {
            operatorLoadError = "No active vessel booking to tender."
            return
        }
        let companyIds = selectedOperatorCompanyIds.sorted()
        guard !companyIds.isEmpty else {
            operatorLoadError = "Choose at least one verified operator company."
            return
        }
        guard tenderExpiresAt.timeIntervalSinceNow >= 15 * 60 else {
            operatorLoadError = "The response deadline must be at least 15 minutes from now."
            return
        }
        rerequesting = true
        operatorLoadError = nil
        defer { rerequesting = false }
        struct TenderIn: Encodable {
            let shipmentId: Int
            let operatorCompanyIds: [Int]
            let expiresAt: String
        }
        struct TenderAck: Decodable { let success: Bool? }
        do {
            let formatter = ISO8601DateFormatter()
            let ack: TenderAck = try await EusoTripAPI.shared.mutation(
                "vesselShipments.requestVesselTender",
                input: TenderIn(
                    shipmentId: sid,
                    operatorCompanyIds: companyIds,
                    expiresAt: formatter.string(from: tenderExpiresAt)
                )
            )
            guard ack.success == true else {
                operatorLoadError = "The tender invitation was not committed. No operator was notified."
                return
            }
            showingRetenderSheet = false
            selectedOperatorCompanyIds.removeAll()
            actionNote = "Tender sent to \(companyIds.count) verified operator \(companyIds.count == 1 ? "company" : "companies")."
            await load()
        } catch {
            operatorLoadError = error.eusoUserCopy
        }
    }

    /// Withdraws the persisted invitation. The mutation updates invitation state,
    /// records the event and audit row, and notifies the operator company.
    private func cancelRequest() async {
        guard let invitationId = active?.invitationId else {
            actionError = "No active tender invitation to withdraw."
            return
        }
        actionError = nil; actionNote = nil; cancelling = true
        defer { cancelling = false }
        struct CancelIn: Encodable {
            let invitationId: Int
            let reason: String
        }
        struct CancelAck: Decodable {
            let success: Bool?
            let status: String?
            let idempotent: Bool?
        }
        do {
            let ack: CancelAck = try await EusoTripAPI.shared.mutation(
                "vesselShipments.cancelVesselTenderInvitation",
                input: CancelIn(
                    invitationId: invitationId,
                    reason: "Withdrawn by the vessel shipper from the tender workflow"
                )
            )
            guard ack.success == true, ack.status == "cancelled" else {
                actionError = "The withdrawal was not committed. This tender remains active."
                return
            }
            actionNote = ack.idempotent == true
                ? "This tender invitation was already withdrawn."
                : "Tender withdrawn. The operator company has been notified."
            await load()
        } catch {
            actionError = "Couldn't withdraw this tender. " + error.eusoUserCopy
        }
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
