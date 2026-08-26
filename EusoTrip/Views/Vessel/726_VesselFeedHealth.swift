//
//  726_VesselFeedHealth.swift
//  EusoTrip — Vessel Operator · DCSA Track & Trace Feed-Health.
//
//  Faithful 1:1 native port of "726 Vessel DCSA T&T Feed-Health · Dark/Light".
//  FEED-HEALTH MONITOR archetype: a carrier-feed activity monitor — feed status,
//  last-event age, a DCSA event-type coverage ring/strip, and a data-residency band.
//
//  HONEST BINDING (server/routers/vesselShipments.ts):
//    · vesselShipments.getVesselShipments   — resolves the booking to monitor.
//    · vesselShipments.getOceanTrackingBoard — REAL event stream for the booking's carrier feed
//                                              (last-event age, event count, event types present).
//  DCSA event-type COVERAGE is computed from the REAL event types actually
//  flowing. HONEST GAP (proposed to the-oath): a multi-carrier feed roster with
//  per-carrier uptime% + median latency (dcsa.getFeedHealth / subscribeFeed) has
//  no connector today — surfaced as explicit awaiting states, never fabricated
//  uptime/latency figures. RBAC vesselProcedure · transportMode=vessel.
//

import SwiftUI

private struct VesselShipmentList726: Decodable { let shipments: [VesselShipmentRow726]? }
private struct VesselShipmentRow726: Decodable { let id: Int?; let bookingNumber: String? }
private struct TrackingBoard726: Decodable {
    let found: Bool?
    let vessel: TBVessel726?
    let etaUtc: String?
    let events: [TBEvent726]?
    let containerCount: Int?
}
private struct TBVessel726: Decodable { let name: String?; let carrier: String? }
private struct TBEvent726: Decodable { let eventType: String?; let description: String?; let timestamp: String? }

private struct DcsaCode726: Identifiable { let id = UUID(); let code: String; let lit: Bool }

struct VesselFeedHealthScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselFeedHealthBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselFeedHealthBody: View {
    @Environment(\.palette) private var palette

    @State private var bookingNumber: String? = nil
    @State private var carrier: String = "Carrier feed"
    @State private var lastEventDate: Date? = nil
    @State private var eventCount = 0
    @State private var codes: [DcsaCode726] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil

    private let expectedCodes = ["CARG", "LOAD", "DEPA", "ARRI", "DISC", "GTOT"]
    private var coveragePct: Double {
        guard !codes.isEmpty else { return 0 }
        return Double(codes.filter(\.lit).count) / Double(codes.count)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if bookingNumber == nil {
                    EusoEmptyState(
                        systemImage: "dot.radiowaves.left.and.right",
                        title: "No booking to monitor",
                        subtitle: "The DCSA track-&-trace feed monitor activates once a vessel booking has a carrier event feed.")
                } else {
                    heroCard
                    carrierRoster
                    coverageStrip
                    residencyBand
                    ctaRow
                    if let actionMessage {
                        LifecycleCard { Text(actionMessage).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · T&T FEED")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("DCSA 2.2").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            Text("Feed health").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            ForEach([128, 120, 58], id: \.self) { h in
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: CGFloat(h))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    // Hero — coverage ring + last event age
    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(Color(hex: 0x141928)).padding(1.5)
            HStack(alignment: .top, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("DCSA T&T 2.2 · industry-feed monitor").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color(hex: 0xAAB2BB))
                    }
                    Text("1 carrier feed active").font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text("Last event \(lastEventAge) · \(eventCount) events tracked").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color(hex: 0xAAB2BB))
                    Text("Booking \(bookingNumber ?? "—")").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                }
                Spacer(minLength: 0)
                coverageRing
            }
            .padding(Space.s5)
        }
        .frame(minHeight: 128)
    }
    private var coverageRing: some View {
        ZStack {
            Circle().stroke(palette.bgCardSoft, lineWidth: 7).frame(width: 56, height: 56)
            Circle().trim(from: 0, to: CGFloat(coveragePct))
                .stroke(LinearGradient(colors: [Brand.success, Color(hex: 0x00966B)], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 56, height: 56)
            VStack(spacing: 0) {
                Text("\(Int(coveragePct * 100))%").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
                Text("COVERAGE").font(.system(size: 6.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    // Carrier roster (real single feed + awaiting roster)
    private var carrierRoster: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("CARRIER FEED ROSTER", ref: "LIVE CARRIER FEEDS", gap: false)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Circle().fill(Brand.success).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(carrier).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text("last \(lastEventAge) · \(eventCount) events").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    Text("LIVE").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.success)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16)
                HStack {
                    Text("Multi-carrier roster · per-feed uptime + latency")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("FEED HEALTH UNAVAILABLE").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.warning)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // DCSA event-type coverage strip (real types flowing)
    private var coverageStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DCSA EVENT-TYPE COVERAGE · flowing now", ref: "dcsa.feedHealth", gap: true)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(codes) { c in
                        Text(c.code)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(c.lit ? .white : palette.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Group { if c.lit { LinearGradient.primary } else { palette.bgCardSoft } })
                            .clipShape(Capsule())
                    }
                }
                Text(coverageNote).font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            .padding(14).background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private var coverageNote: String {
        let missing = codes.filter { !$0.lit }.map(\.code)
        if missing.isEmpty { return "All DCSA event types flowing on this feed." }
        return "\(missing.joined(separator: ", ")) not yet emitted on this feed — downstream clocks (LFD) at risk."
    }

    private var residencyBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FEED DATA-RESIDENCY · per discharge port", ref: "subscribeFeed·country", gap: false)
            CountryBand726(rows: [
                .init(code: "US", line: "US · USLGB · CBP ACE status events · FMC", active: true),
                .init(code: "CA", line: "CA · CAVAN · CBSA ACI · PIPEDA residency", active: false),
                .init(code: "MX", line: "MX · MXZLO · SAT VUCEM · LFPDPPP", active: false),
            ])
        }
    }

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Reconnect feed", action: {
                actionMessage = "This carrier connection does not expose an authorized reconnect action."
            })
            Button { actionMessage = "Detailed feed-event history is unavailable for this carrier connection." } label: {
                Text("Feed log").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 52)
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ title: String, ref: String, gap: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(gap ? "NOT AVAILABLE" : ref).font(EType.mono(.micro)).foregroundStyle(gap ? Brand.warning : palette.textTertiary)
        }
    }

    private var lastEventAge: String {
        guard let d = lastEventDate else { return "—" }
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return "\(max(secs, 1))s ago" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        if secs < 86400 { return "\(secs / 3600)h ago" }
        return "\(secs / 86400)d ago"
    }

    private func load() async {
        loading = true; loadError = nil; actionMessage = nil
        defer { loading = false }
        struct ListInput: Encodable { let limit: Int; let offset: Int }
        struct BoardInput: Encodable { let bookingNumber: String }
        do {
            let list: VesselShipmentList726 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipments", input: ListInput(limit: 5, offset: 0))
            guard let bn = list.shipments?.compactMap({ $0.bookingNumber }).first(where: { !$0.isEmpty }) else {
                bookingNumber = nil; return
            }
            bookingNumber = bn
            let board: TrackingBoard726 = try await EusoTripAPI.shared.query(
                "vesselShipments.getOceanTrackingBoard", input: BoardInput(bookingNumber: bn))
            let events = board.events ?? []
            eventCount = events.count
            carrier = firstNonEmpty(board.vessel?.carrier, board.vessel?.name) ?? "Carrier feed"
            lastEventDate = events.compactMap { parseDate($0.timestamp) }.max()
            codes = buildCoverage(from: events)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            bookingNumber = nil
        }
    }

    private func buildCoverage(from events: [TBEvent726]) -> [DcsaCode726] {
        let seen = Set(events.compactMap { dcsaBucket($0.eventType, $0.description) })
        return expectedCodes.map { DcsaCode726(code: $0, lit: seen.contains($0)) }
    }
    private func dcsaBucket(_ type: String?, _ desc: String?) -> String? {
        let k = ((type ?? "") + " " + (desc ?? "")).lowercased()
        if k.contains("gate") && (k.contains("out") || k.contains("gtot") || k.contains("pickup")) { return "GTOT" }
        if k.contains("discharg") { return "DISC" }
        if k.contains("arriv") || k.contains("berth") { return "ARRI" }
        if k.contains("depart") || k.contains("sail") { return "DEPA" }
        if k.contains("load") { return "LOAD" }
        if k.contains("cargo") || k.contains("gate") || k.contains("receiv") || k.contains("book") { return "CARG" }
        return nil
    }
    private func parseDate(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }
    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { v -> String? in
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty == false) ? t : nil
        }.first
    }
}

private struct CountryBand726: View {
    struct Row: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }
    let rows: [Row]
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                HStack(spacing: 10) {
                    Text(r.code).font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(r.active ? Color.white : palette.textSecondary)
                        .frame(width: 26, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(r.active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft)))
                    Text(r.line).font(.system(size: 10.5, weight: r.active ? .bold : .regular))
                        .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(r.active ? "ACTIVE" : "STANDBY").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(r.active ? Brand.success : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(r.active ? AnyShapeStyle(palette.bgCard) : AnyShapeStyle(Color.clear))
                if idx < rows.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
            }
        }
        .padding(6).background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("726 · Vessel Feed Health · Night") { VesselFeedHealthScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("726 · Vessel Feed Health · Light") { VesselFeedHealthScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
