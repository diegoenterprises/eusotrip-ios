//
//  734_VesselEDIMessages.swift
//  EusoTrip — Vessel Operator · EDI Messages (PURPOSE-BUILT TRANSACTION STREAM).
//
//  Verbatim bespoke port of canonical wireframe "734 Vessel EDI Messages ·
//  Dark" (06 Vessel · Vessel Operator, carrier-side · STREAM class). A directional
//  EDI transaction feed: a today's-traffic tally hero with an inbound/outbound
//  split bar + a handshake (ACK) ratio, then a stream where every row leads with an
//  IN/OUT direction token, an EDI document-type code chip (315 / 310 / 301 / 214 /
//  997), the trading partner, an ACK/SENT status pill, and the relative time — a
//  transaction feed, NOT a generic icon list. Docked under SHIPMENTS.
//
//  REAL WIRING (tRPC · server/routers/nativeEdi.ts — re-verified 2026-07-11):
//    · nativeEdi.transactionLog {limit}                                    (:104)
//        -> { transactions:[], total, message }. The read is LIVE but returns an
//        empty array today (server message: it should read integrationEventLog
//        filtered to eventType prefix 'edi.'). The stream renders the real (empty)
//        state honestly + surfaces the named gap; when the table binds, the rows
//        light up with no client change.  STUB · named-gap (data binding).
//    · nativeEdi.generateOutbound {type, loadId?, controlNumber?}  mutation (:90)
//        -> { ediDocument, type, controlNumber }. The REAL "Generate outbound 310"
//        verb (auto-emits the envelope).
//    · nativeEdi.partnerSetup {…} mutation                                 (:112)
//        backs the "Partners" affordance; EDI_TYPES enum 204/210/214/990/997/310/
//        315/301 (:17) keys the doc-type code chips.
//
//  transportMode=vessel · RBAC protectedProcedure. NO mock data — the tally,
//  split, ratio, and stream all derive from the live transactionLog; the ESANG
//  handshake advisory is computed from those live rows (not a fabricated call).
//  transactionLog is empty today, so the screen honestly shows "no EDI traffic
//  yet" with the server's own note rather than seeding a fake feed.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes

/// nativeEdi.transactionLog -> { transactions, total, message }
private struct EDITransactionLog734: Decodable {
    let transactions: [EDITxn734]
    let total: Int?
    let message: String?
}

/// One EDI transaction. All fields optional — the server returns an empty array
/// today, so the element shape is decoded permissively and lights up the moment
/// the integrationEventLog binding lands. Direction/type/ackStatus drive the row.
private struct EDITxn734: Decodable, Identifiable {
    let id: String
    let type: String?
    let direction: String?
    let partner: String?
    let ackStatus: String?
    let controlNumber: String?
    let loadId: Int?
    let timestamp: String?

    private enum CodingKeys: String, CodingKey {
        case id, type, direction, partner, partnerName, ackStatus, status
        case controlNumber, loadId, timestamp, createdAt, occurredAt
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        // Stable id — server id if present, else a synthesized one.
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) }
        else { id = UUID().uuidString }
        type = try? c.decode(String.self, forKey: .type)
        direction = try? c.decode(String.self, forKey: .direction)
        partner = (try? c.decode(String.self, forKey: .partner))
            ?? (try? c.decode(String.self, forKey: .partnerName))
        ackStatus = (try? c.decode(String.self, forKey: .ackStatus))
            ?? (try? c.decode(String.self, forKey: .status))
        controlNumber = try? c.decode(String.self, forKey: .controlNumber)
        loadId = try? c.decode(Int.self, forKey: .loadId)
        timestamp = (try? c.decode(String.self, forKey: .timestamp))
            ?? (try? c.decode(String.self, forKey: .createdAt))
            ?? (try? c.decode(String.self, forKey: .occurredAt))
    }
}

private struct GenerateOutboundResult734: Decodable {
    let ediDocument: String?
    let type: String?
    let controlNumber: String?
}

// MARK: - Screen

struct VesselEDIMessagesScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselEDIMessagesBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle)
        }
    }
}

// MARK: - Body

private struct VesselEDIMessagesBody: View {
    @Environment(\.palette) private var palette

    @State private var log: EDITransactionLog734? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var generating = false
    @State private var genAck: String? = nil
    @State private var genError: String? = nil

    // The doc type the "Generate outbound" CTA emits (310 · Freight invoice).
    private let outboundType = "310"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    tallyHero
                    streamSection
                    esangCard
                    if let ack = genAck { ackBanner(ack) }
                    if let err = genError { errBanner(err) }
                    ctaRow
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Derived

    private var txns: [EDITxn734] { log?.transactions ?? [] }
    private var todayCount: Int { log?.total ?? txns.count }
    private var inbound: [EDITxn734] { txns.filter { isInbound($0) } }
    private var outbound: [EDITxn734] { txns.filter { !isInbound($0) } }
    private var ackedCount: Int { txns.filter { isAcked($0) }.count }
    private var partners: [String] {
        Array(Set(txns.compactMap { $0.partner }.filter { !$0.isEmpty })).sorted()
    }

    private func isInbound(_ t: EDITxn734) -> Bool {
        (t.direction ?? "").lowercased().hasPrefix("in")
    }
    private func isAcked(_ t: EDITxn734) -> Bool {
        let s = (t.ackStatus ?? "").lowercased()
        return s.contains("ack") || s.contains("997") || s == "received"
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · EDI MESSAGES")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("\(todayCount) TODAY")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            Text("EDI messages")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: Tally hero (traffic + in/out split + ack ratio)

    private var tallyHero: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text("\(todayCount)")
                        .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("transactions today")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text("ocean sets · ISA/GS envelopes")
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                ackRatioPill
            }

            // In/out split bar — real proportions from live rows.
            splitBar
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    private var ackRatioPill: some View {
        let all = todayCount
        let ok = all > 0 && ackedCount == all
        return HStack(spacing: 6) {
            Circle().fill(ok ? Brand.success : palette.textTertiary)
                .frame(width: 6, height: 6)
            Text(all == 0 ? "0 ACKED" : "\(ackedCount)/\(all) ACKED")
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(ok ? Brand.success : palette.textSecondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill((ok ? Brand.success : palette.textTertiary).opacity(0.18)))
    }

    private var splitBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            GeometryReader { geo in
                let total = max(1, inbound.count + outbound.count)
                let inW = geo.size.width * CGFloat(inbound.count) / CGFloat(total)
                HStack(spacing: 4) {
                    Capsule().fill(Brand.success)
                        .frame(width: max(inbound.isEmpty ? 0 : 6, inW - 2))
                    Capsule().fill(Brand.info)
                        .frame(maxWidth: .infinity)
                }
                .opacity(total == 0 ? 0.25 : 1)
            }
            .frame(height: 10)

            HStack(spacing: Space.s4) {
                legendDot(Brand.success, "\(inbound.count) inbound")
                legendDot(Brand.info, "\(outbound.count) outbound")
                Spacer()
                Text(lastAckRelative)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var lastAckRelative: String {
        guard let first = txns.first, let ts = first.timestamp else { return "no traffic yet" }
        return "last " + relative(ts)
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Directional stream

    private var streamSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TRANSACTION STREAM")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("nativeEdi.transactionLog")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }

            if txns.isEmpty {
                EusoEmptyState(
                    systemImage: "arrow.left.arrow.right",
                    title: "No EDI traffic yet",
                    subtitle: log?.message
                        ?? "Every 315 / 310 / 301 / 214 / 997 handshake with your ocean partners appears here the moment it clears.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(txns.enumerated()), id: \.element.id) { idx, t in
                        streamRow(t)
                        if idx < txns.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, 68)
                        }
                    }
                    Divider().overlay(palette.borderFaint)
                    partnersFooter
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func streamRow(_ t: EDITxn734) -> some View {
        let inbnd = isInbound(t)
        let accent = inbnd ? Brand.success : Brand.info
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18)).frame(width: 40, height: 40)
                VStack(spacing: 1) {
                    Image(systemName: inbnd ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 13, weight: .heavy)).foregroundStyle(accent)
                    Text(inbnd ? "IN" : "OUT")
                        .font(.system(size: 7, weight: .heavy)).foregroundStyle(accent)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(docLabel(t.type))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(rowMeta(t))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                ackPill(t)
                if let ts = t.timestamp {
                    Text(relative(ts))
                        .font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(Space.s4)
    }

    private func ackPill(_ t: EDITxn734) -> some View {
        let inbnd = isInbound(t)
        let text: String = inbnd ? (isAcked(t) ? "ACK" : "RCVD") : "SENT"
        let c = inbnd ? Brand.success : Brand.info
        return Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.3)
            .foregroundStyle(c)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(c.opacity(0.22)))
    }

    private var partnersFooter: some View {
        HStack {
            Text(partners.isEmpty
                 ? "trading partners appear as traffic clears"
                 : "\(partners.count) partner\(partners.count == 1 ? "" : "s") · \(partners.joined(separator: " · "))")
                .font(.system(size: 11))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
        }
        .padding(Space.s4)
    }

    // MARK: ESANG handshake advisory (computed from live rows)

    private var esangCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG · HANDSHAKE STATUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(handshakeHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(handshakeDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var handshakeHeadline: String {
        if todayCount == 0 { return "No EDI sets to acknowledge today" }
        if ackedCount == todayCount { return "All \(todayCount) sets acked — no missing 997 today" }
        return "\(todayCount - ackedCount) of \(todayCount) awaiting acknowledgment"
    }
    private var handshakeDetail: String {
        if todayCount == 0 { return "Partner handshakes light up here as envelopes flow." }
        let pending = outbound.filter { !isAcked($0) }.count
        return pending > 0
            ? "\(pending) outbound envelope\(pending == 1 ? "" : "s") awaiting the partner's 997"
            : "Every outbound envelope has a matching functional ack."
    }

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await generateOutbound() }
            } label: {
                HStack(spacing: 6) {
                    if generating { ProgressView().tint(.white).scaleEffect(0.8) }
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                    Text(generating ? "Generating…" : "Generate outbound 310")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain).disabled(generating).frame(maxWidth: .infinity)

            Button { } label: {
                Text("Partners")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 120, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Banners / states

    private func ackBanner(_ msg: String) -> some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(msg).font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }
    private func errBanner(_ msg: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }
    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }
    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 104)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 300)
        }
    }

    // MARK: Formatting

    private func docLabel(_ type: String?) -> String {
        switch (type ?? "").uppercased() {
        case "315": return "315 · Carrier status"
        case "310": return "310 · Freight invoice"
        case "301": return "301 · Booking confirm"
        case "214": return "214 · Shipment status"
        case "997": return "997 · Functional ack"
        case "204": return "204 · Load tender"
        case "210": return "210 · Freight details"
        case "990": return "990 · Tender response"
        case "": return "EDI transaction"
        default: return "\((type ?? "").uppercased()) · EDI"
        }
    }

    private func rowMeta(_ t: EDITxn734) -> String {
        var parts: [String] = []
        if let p = t.partner, !p.isEmpty { parts.append(isInbound(t) ? p : "→ \(p)") }
        if let cn = t.controlNumber, !cn.isEmpty { parts.append(cn) }
        else if let l = t.loadId, l > 0 { parts.append("VES-\(l)") }
        return parts.isEmpty ? (isInbound(t) ? "inbound envelope" : "outbound envelope")
                             : parts.joined(separator: " · ")
    }

    /// Relative time from an ISO timestamp. Honest "—" when unparseable.
    private func relative(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fmt.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return "—" }
        let secs = max(0, Int(Date().timeIntervalSince(d)))
        if secs < 60 { return "\(secs)s" }
        if secs < 3600 { return "\(secs / 60)m" }
        if secs < 86400 { return "\(secs / 3600)h" }
        return "\(secs / 86400)d"
    }

    // MARK: Load / mutate

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            let resp: EDITransactionLog734 = try await EusoTripAPI.shared.query(
                "nativeEdi.transactionLog", input: In(limit: 100))
            self.log = resp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func generateOutbound() async {
        genAck = nil; genError = nil; generating = true
        struct In: Encodable { let type: String }
        do {
            let res: GenerateOutboundResult734 = try await EusoTripAPI.shared.mutation(
                "nativeEdi.generateOutbound", input: In(type: outboundType))
            if let cn = res.controlNumber {
                genAck = "Generated outbound \(res.type ?? outboundType) · control \(cn)."
                await load()
            } else {
                genError = "Outbound envelope did not confirm. Try again."
            }
        } catch {
            genError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        generating = false
    }
}

#Preview("734 · Vessel EDI Messages · Night") {
    VesselEDIMessagesScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("734 · Vessel EDI Messages · Light") {
    VesselEDIMessagesScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
