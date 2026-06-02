//
//  677_VesselCarrierTenderWorkflow.swift
//  EusoTrip — Vessel Operator · Carrier Tender Workflow (booking-quote inbox).
//
//  Verbatim port of "677 Vessel Carrier Tender Workflow.svg" (Dark). Docked
//  under HOME on VesselOperatorNavController.swift
//  (HOME(current) · SHIPMENTS · [orb] · COMPLIANCE · ME). Cross-mode sibling
//  of 05 Rail/569. Carrier-side booking-quote inbox.
//
//  NOTE: vessel has no dedicated tender-workflow router; the carrier-side
//  quote is modeled on the real vesselShipments procedures —
//    · getVesselShipmentDetail (server/routers/vesselShipments.ts:234) — active request
//    · getVesselSchedules      (server/routers/vesselShipments.ts:637) — sailing options
//    · createVesselBid         (server/routers/vesselShipments.ts:680, bid_submitted event)
//  The KPI strip (PENDING · WIN RATE · AVG REPLY) has no backing procedure —
//  see PORT-GAP below.
//

import SwiftUI

struct VesselCarrierTenderWorkflowScreen: View {
    let theme: Theme.Palette
    /// Active booking request the carrier is quoting. The SVG models
    /// VES-260523-9C1A77E2B0 (Shanghai CNSHA → Long Beach USLGB · 8 FEU dry).
    let shipmentId: Int
    var body: some View {
        Shell(theme: theme) { VesselCarrierTenderWorkflowBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror getVesselShipmentDetail + getVesselSchedules)

private struct PortRef677: Decodable {
    let name: String?
    let unlocode: String?
    let code: String?
}

private struct VesselTenderDetail677: Decodable {
    let id: Int
    let bookingNumber: String?
    let origin: String?
    let destination: String?
    let serviceName: String?
    let teuCount: Int?
    let containerSize: String?
    let targetRate: Double?
    let allInRate: Double?
    let shipperOfRecord: String?
    let originPort: PortRef677?
    let destinationPort: PortRef677?
}

private struct VesselVoyage677: Decodable, Identifiable {
    let id: Int
    let vesselName: String?
    let voyageNumber: String?
    let scheduledDeparture: String?
    let cutoffTime: String?
    let transitDays: Int?
    let status: String?
    let lastQuotedRate: Double?
}

// MARK: - Body

private struct VesselCarrierTenderWorkflowBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var detail: VesselTenderDetail677? = nil
    @State private var voyages: [VesselVoyage677] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Quote submission (createVesselBid).
    @State private var submitting = false
    @State private var declining = false
    @State private var actionError: String? = nil
    @State private var actionAck: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrowTitle
                IridescentHairline()
                    .padding(.top, Space.s4)

                if loading {
                    LifecycleCard {
                        Text("Loading tender inbox…").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.top, Space.s4)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.top, Space.s4)
                } else {
                    bookingRequestCard
                        .padding(.top, Space.s4)
                    kpiStrip
                        .padding(.top, Space.s3)
                    sailingOptions
                        .padding(.top, Space.s5)
                    if let ack = actionAck {
                        ackBanner(ack)
                            .padding(.top, Space.s3)
                    }
                    if let aerr = actionError {
                        LifecycleCard(accentDanger: true) {
                            Text(aerr).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                        .padding(.top, Space.s3)
                    }
                    dualCTA
                        .padding(.top, Space.s5)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Eyebrow + title

    private var eyebrowTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "ferry.fill")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("✦  VESSEL OPERATOR · TENDER WORKFLOW")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Text("Tender Workflow")
                .font(.system(size: 30, weight: .bold)).tracking(-0.5)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s4)
            Text("createVesselBid · inbox live")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
    }

    // MARK: - Active booking request card (getVesselShipmentDetail)

    private var bookingRequestCard: some View {
        let lane = laneString
        let teu = detail?.teuCount ?? 0
        let target = detail?.targetRate
        let allIn = detail?.allInRate
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("BOOKING REQUEST · getVesselShipmentDetail")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                // 42 MIN deadline chip (warning tint).
                Text(deadlineLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Color(hex: 0xF0A93B))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Brand.warning.opacity(0.2)).clipShape(Capsule())
            }
            Text(lane)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            Text("\(detail?.serviceName ?? "—") · \(teu) FEU dry · CY/CY")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s3)
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(target.map { rateString($0) } ?? "—")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("target / FEU\(allIn.map { " · \(rateString($0)) all-in" } ?? "")")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, Space.s3)
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.top, Space.s3)
            Text("\(detail?.bookingNumber ?? "—") · \(detail?.shipperOfRecord ?? "—") · quote to lock slot")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s3)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - KPI strip
    //
    // PORT-GAP: carrier tender-inbox stats (pending count · win rate ·
    // avg reply-to-quote) have NO backing procedure on
    // server/routers/vesselShipments.ts. The SVG shows PENDING 4 ·
    // WIN RATE 71% · AVG REPLY 31m — none of which are derivable from
    // getVesselShipmentDetail / getVesselSchedules / createVesselBid.
    // Rendered as a real empty/unavailable state instead of fabricating
    // numbers. See portGaps: vesselShipments.getCarrierTenderStats.

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiTile(label: "PENDING",  value: "—", caption: "awaiting quote", accent: Brand.warning)
            kpiTile(label: "WIN RATE", value: "—", caption: "trailing 30d",   gradient: true)
            kpiTile(label: "AVG REPLY", value: "—", caption: "to quote")
        }
    }

    private func kpiTile(label: String, value: String, caption: String,
                         accent: Color? = nil, gradient: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                if gradient {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else if let accent {
                    Text(value).foregroundStyle(accent)
                } else {
                    Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: 22, weight: .bold))
            .monospacedDigit()
            Text(caption)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Sailing options (getVesselSchedules)

    private var sailingOptions: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("SAILING OPTIONS · getVesselSchedules")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if voyages.isEmpty {
                EusoEmptyState(systemImage: "calendar.badge.clock",
                               title: "No sailing options",
                               subtitle: "Open voyages for this lane will appear here once schedules publish.")
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(voyages) { voyage in sailingRow(voyage) }
                }
            }
        }
    }

    private func sailingRow(_ voyage: VesselVoyage677) -> some View {
        let isOpen = isVoyageOpen(voyage)
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(voyage.vesselName ?? "—") · voy \(voyage.voyageNumber ?? "—")")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(scheduleLine(voyage))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            if isOpen {
                Text("OPEN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Color(hex: 0x3BD9A6))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Brand.success.opacity(0.2)).clipShape(Capsule())
            } else {
                Text("CLOSED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color.white.opacity(0.08)).clipShape(Capsule())
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Dual CTA (Decline · Submit quote → createVesselBid)

    private var dualCTA: some View {
        HStack(spacing: Space.s4) {
            Button(action: { Task { await decline() } }) {
                Text(declining ? "Declining…" : "Decline")
                    .font(EType.title)
                    .foregroundStyle(Color(hex: 0xFF6B70))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(declining ? 0.6 : 1.0)
            .disabled(declining || submitting)

            Button(action: { Task { await submitQuote() } }) {
                Text(submitting ? "Submitting…" : "Submit quote")
                    .font(EType.title)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .background(LinearGradient.primary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(submitting ? 0.6 : 1.0)
            .disabled(submitting || declining)
        }
    }

    private func ackBanner(_ text: String) -> some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(text).font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: - Derived display helpers

    private var laneString: String {
        if let o = detail?.originPort, let d = detail?.destinationPort {
            let oCode = o.unlocode ?? o.code ?? ""
            let dCode = d.unlocode ?? d.code ?? ""
            let oName = o.name ?? detail?.origin ?? "—"
            let dName = d.name ?? detail?.destination ?? "—"
            let lhs = oCode.isEmpty ? oName : "\(oName) \(oCode)"
            let rhs = dCode.isEmpty ? dName : "\(dName) \(dCode)"
            return "\(lhs) → \(rhs)"
        }
        return "\(detail?.origin ?? "—") → \(detail?.destination ?? "—")"
    }

    private var deadlineLabel: String {
        // Carrier quote deadline. No server-provided countdown on the
        // tender procedures — render a neutral "QUOTE" label rather than
        // fabricate "42 MIN" (the SVG mock value).
        "QUOTE"
    }

    private func rateString(_ value: Double) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.maximumFractionDigits = 0
        return "$" + (n.string(from: NSNumber(value: value)) ?? String(Int(value)))
    }

    private func scheduleLine(_ v: VesselVoyage677) -> String {
        var parts: [String] = []
        if let etd = v.scheduledDeparture { parts.append("ETD \(shortDate(etd))") }
        if let cut = v.cutoffTime { parts.append("cutoff \(shortDate(cut))") }
        else if !isVoyageOpen(v) { parts.append("cutoff passed") }
        if let t = v.transitDays { parts.append("\(t)d transit") }
        if !isVoyageOpen(v), let q = v.lastQuotedRate { parts.append("last-quoted \(rateString(q))") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func shortDate(_ iso: String) -> String {
        let inF = ISO8601DateFormatter()
        inF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let inF2 = ISO8601DateFormatter()
        let date = inF.date(from: iso) ?? inF2.date(from: iso)
        guard let date else {
            // Fall back to a yyyy-MM-dd parse for plain date strings.
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            if let d = f.date(from: String(iso.prefix(10))) {
                let out = DateFormatter(); out.dateFormat = "MMM d"
                return out.string(from: d)
            }
            return iso
        }
        let out = DateFormatter(); out.dateFormat = "MMM d"
        return out.string(from: date)
    }

    private func isVoyageOpen(_ v: VesselVoyage677) -> Bool {
        switch (v.status ?? "").lowercased() {
        case "open", "scheduled", "available": return true
        case "closed", "departed", "cancelled", "full": return false
        default:
            // No explicit status → infer from cutoff time if present.
            guard let cut = v.cutoffTime else { return true }
            let f = ISO8601DateFormatter()
            if let d = f.date(from: cut) { return d.timeIntervalSinceNow > 0 }
            return true
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct SchedulesIn: Encodable { let limit: Int }
        do {
            async let d: VesselTenderDetail677 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
            async let s: [VesselVoyage677] = EusoTripAPI.shared.query(
                "vesselShipments.getVesselSchedules", input: SchedulesIn(limit: 20))
            let (det, sch) = try await (d, s)
            self.detail = det
            self.voyages = sch
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Mutations

    private func submitQuote() async {
        submitting = true; actionError = nil; actionAck = nil
        struct BidIn: Encodable {
            let shipmentId: Int
            let amount: Double
            let rateType: String
        }
        struct Ack677: Decodable { let success: Bool? }
        // Quote the shipper's target / FEU at per-TEU rate type. No fabricated
        // amount — if the detail has no target rate we cannot quote.
        guard let amount = detail?.targetRate else {
            actionError = "No target rate on this booking request — cannot submit a quote."
            submitting = false
            return
        }
        do {
            let res: Ack677 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.createVesselBid",
                input: BidIn(shipmentId: shipmentId, amount: amount, rateType: "per_teu"))
            if res.success == true {
                actionAck = "Quote submitted · createVesselBid → bid_submitted"
            } else {
                actionError = "Quote was not accepted by the server."
            }
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }

    private func decline() async {
        declining = true; actionError = nil; actionAck = nil
        // PORT-GAP: there is no decline-tender procedure on
        // server/routers/vesselShipments.ts. updateVesselShipmentStatus
        // transitions a booking the carrier OWNS — it does not model a
        // carrier declining an inbound tender request. Surface the gap
        // honestly rather than firing a wrong mutation.
        actionError = "Decline is not yet wired — vesselShipments has no declineTender procedure. See portGaps."
        declining = false
    }
}

#Preview("677 · Vessel Carrier Tender Workflow · Night") {
    VesselCarrierTenderWorkflowScreen(theme: Theme.dark, shipmentId: 77410)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("677 · Vessel Carrier Tender Workflow · Light") {
    VesselCarrierTenderWorkflowScreen(theme: Theme.light, shipmentId: 77410)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
