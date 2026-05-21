//
//  Dpch720_DispatcherSVGTrio.swift
//  EusoTrip — Dispatcher · Tender Queue + Comms Hub + BOL Mismatch.
//
//  Three Dispatcher SVG-faithful ports bundled into one Swift file
//  (iOS Dispatch surface uses Dpch7xx numbering; SVG uses 4xx — file
//  bundled at Dpch720 to avoid collision with the existing
//  Dpch714/715/716 trio).
//
//  Pixel-match to:
//    `04 Dispatcher/Dark-SVG/403 Dispatcher Tender Queue.svg`
//    `04 Dispatcher/Dark-SVG/405 Dispatcher Comms Hub.svg`
//    `04 Dispatcher/Dark-SVG/411 Dispatcher BOL Mismatch.svg`
//

import SwiftUI

// MARK: ─────────────────────────────────────────────────────────
// MARK: Tender Queue (SVG 403)
// MARK: ─────────────────────────────────────────────────────────

private struct PendingTender: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let trailerType: String?
    let cargoType: String?
    let weight: String?
    let rate: String?
    let shipperName: String?
    let hazmatClass: String?
    let expiresAt: String?
}
private struct PendingTendersEnvelope: Decodable {
    let tenders: [PendingTender]?
    let items: [PendingTender]?
    var rows: [PendingTender] { tenders ?? items ?? [] }
}

struct DispatcherTenderQueueScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { TenderQueueBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct TenderQueueBody: View {
    @Environment(\.palette) private var palette

    enum Sort: String, CaseIterable { case expiry = "Expiry", desc = "$ desc", lane = "Lane · OR", hazmat = "Hazmat" }

    @State private var tenders: [PendingTender] = []
    @State private var sort: Sort = .expiry
    @State private var loading: Bool = true

    private var expiringSoon: Int {
        tenders.filter { expiresWithin($0.expiresAt, hours: 1) }.count
    }
    private var sorted: [PendingTender] {
        switch sort {
        case .expiry: return tenders.sorted { ($0.expiresAt ?? "") < ($1.expiresAt ?? "") }
        case .desc:   return tenders.sorted { (Double($0.rate ?? "0") ?? 0) > (Double($1.rate ?? "0") ?? 0) }
        case .lane:   return tenders.sorted { ($0.pickupState ?? "") < ($1.pickupState ?? "") }
        case .hazmat: return tenders.sorted { (($0.hazmatClass ?? "").isEmpty ? 1 : 0) < (($1.hazmatClass ?? "").isEmpty ? 1 : 0) }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                sortStrip
                if loading && tenders.isEmpty {
                    LifecycleCard { Text("Loading queue…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if sorted.isEmpty {
                    EusoEmptyState(systemImage: "tray", title: "Queue is clear", subtitle: "Pending tenders land here as shippers submit them.")
                } else {
                    ForEach(sorted) { t in tenderCard(t) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · TENDER · QUEUE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Tender queue").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Sorted by expiry · swipe to triage").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(tenders.count) PENDING · \(expiringSoon) EXPIRE < 1H")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var sortStrip: some View {
        HStack(spacing: 6) {
            ForEach(Sort.allCases, id: \.self) { s in
                Button { sort = s } label: {
                    Text(s.rawValue)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(sort == s ? .white : palette.textSecondary)
                        .background(sort == s ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func tenderCard(_ t: PendingTender) -> some View {
        let isExpiringSoon = expiresWithin(t.expiresAt, hours: 1)
        let expiryLabel: String = {
            guard let exp = t.expiresAt, let d = ISO8601DateFormatter().date(from: exp) else { return "—" }
            let mins = max(0, Int(d.timeIntervalSinceNow / 60))
            if mins < 60 { return "EXPIRES \(mins)m" }
            return "EXPIRES \(mins / 60)h \(mins % 60)m"
        }()
        return LifecycleCard(accentDanger: isExpiringSoon) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(t.loadNumber ?? "LD-\(t.id)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    if isExpiringSoon {
                        Text(expiryLabel)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.18)))
                            .foregroundStyle(.red)
                    } else {
                        if let h = t.hazmatClass, !h.isEmpty {
                            Text("HAZ").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                                .foregroundStyle(.orange)
                        }
                        Text(expiryLabel.replacingOccurrences(of: "EXPIRES ", with: ""))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Text("\(t.pickupCity ?? "—"), \(t.pickupState ?? "—") → \(t.destCity ?? "—"), \(t.destState ?? "—")")
                    .font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                Text("\(t.trailerType ?? "—") · \(t.cargoType ?? "—") · \(t.weight ?? "—")")
                    .font(.caption).foregroundStyle(palette.textSecondary)
                if let s = t.shipperName {
                    Text("Shipper: \(s)").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                HStack(spacing: 10) {
                    Text("$\(t.rate ?? "—")")
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { } label: {
                        Text("ACCEPT").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.green))
                    }.buttonStyle(.plain)
                    Button { } label: {
                        Text("COUNTER").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(palette.bgCardSoft))
                            .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.4)))
                    }.buttonStyle(.plain)
                    Button { } label: {
                        Text("DECLINE").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    }.buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
        }
    }

    private func expiresWithin(_ iso: String?, hours: Int) -> Bool {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return false }
        return d.timeIntervalSinceNow < Double(hours) * 3600 && d.timeIntervalSinceNow > 0
    }

    private func load() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let status: String; let limit: Int }
        struct Out: Decodable {
            let loads: [PendingTender]?
            let items: [PendingTender]?
        }
        do {
            let r: Out = try await EusoTripAPI.shared.query("loads.list", input: In(status: "pending", limit: 30))
            tenders = r.loads ?? r.items ?? []
        } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Comms Hub (SVG 405)
// MARK: ─────────────────────────────────────────────────────────

private struct CommsChannel: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let lastMessageAt: String?
    let lastMessageFrom: String?
    let lastMessageBody: String?
    let unreadCount: Int?
    let memberCount: Int?
    let isCopilot: Bool?
}
private struct CommsThread: Decodable, Hashable, Identifiable {
    let id: String
    let driverName: String?
    let lastMessageBody: String?
    let lastMessageAt: String?
    let unreadCount: Int?
    let critical: Bool?
}

struct DispatcherCommsHubScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CommsHubBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct CommsHubBody: View {
    @Environment(\.palette) private var palette
    @State private var channels: [CommsChannel] = []
    @State private var threads: [CommsThread] = []
    @State private var unreadOnly: Bool = false
    @State private var loading: Bool = true

    private var unreadCount: Int {
        channels.reduce(0) { $0 + ($1.unreadCount ?? 0) } + threads.reduce(0) { $0 + ($1.unreadCount ?? 0) }
    }
    private var criticalCount: Int {
        threads.filter { $0.critical == true }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterRow
                channelsSection
                threadsSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · COMMS · HUB").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Comms hub").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Channels + driver DMs · pin urgent").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(unreadCount) UNREAD · \(criticalCount) CRITICAL")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            Button { unreadOnly = false } label: {
                Text("All · \(channels.count) channels · \(threads.count) DMs")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(!unreadOnly ? .white : palette.textSecondary)
                    .background(!unreadOnly ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                    .clipShape(Capsule())
            }.buttonStyle(.plain)
            Button { unreadOnly = true } label: {
                Text("Unread only · \(unreadCount)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(unreadOnly ? .white : palette.textSecondary)
                    .background(unreadOnly ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                    .clipShape(Capsule())
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHANNELS · \(channels.count)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            let visible = unreadOnly ? channels.filter { ($0.unreadCount ?? 0) > 0 } : channels
            if loading && channels.isEmpty {
                LifecycleCard { Text("Loading channels…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if visible.isEmpty {
                Text("No \(unreadOnly ? "unread " : "")channels.").font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(visible) { c in channelCard(c) }
            }
        }
    }

    private func channelCard(_ c: CommsChannel) -> some View {
        LifecycleCard(accentGradient: c.isCopilot == true) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(c.name ?? "#channel").font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    if c.isCopilot == true {
                        Text("ESANG COPILOT")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(LinearGradient.diagonal))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if let unread = c.unreadCount, unread > 0 {
                        Text("\(unread)")
                            .font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .foregroundStyle(.white)
                    }
                    Text(timeAgo(c.lastMessageAt))
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
                if let body = c.lastMessageBody {
                    Text(body).font(.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
                if let m = c.memberCount {
                    Text("\(m) members").font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var threadsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DRIVER DMS · \(threads.count)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            let visible = unreadOnly ? threads.filter { ($0.unreadCount ?? 0) > 0 } : threads
            if visible.isEmpty {
                Text("No \(unreadOnly ? "unread " : "")DMs.").font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(visible) { t in threadCard(t) }
            }
        }
    }

    private func threadCard(_ t: CommsThread) -> some View {
        LifecycleCard(accentDanger: t.critical == true) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(t.driverName ?? "Driver").font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    if t.critical == true {
                        Text("CRITICAL")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.18)))
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    if let unread = t.unreadCount, unread > 0 {
                        Text("\(unread)").font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .foregroundStyle(.white)
                    }
                    Text(timeAgo(t.lastMessageAt)).font(.caption2).foregroundStyle(palette.textTertiary)
                }
                if let b = t.lastMessageBody {
                    Text(b).font(.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
            }
        }
    }

    private func timeAgo(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let mins = max(0, Int(Date().timeIntervalSince(d) / 60))
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60
        if h < 24 { return "\(h)h" }
        return "\(h / 24)d"
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let c: Void = loadChannels()
        async let t: Void = loadThreads()
        _ = await (c, t)
    }
    private func loadChannels() async {
        struct In: Encodable { let limit: Int }
        do { channels = try await EusoTripAPI.shared.query("messaging.getChannels", input: In(limit: 20)) } catch { /* */ }
    }
    private func loadThreads() async {
        struct In: Encodable { let limit: Int }
        do { threads = try await EusoTripAPI.shared.query("messaging.getDriverDMs", input: In(limit: 30)) } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: BOL Mismatch Exception (SVG 411)
// MARK: ─────────────────────────────────────────────────────────

private struct BOLMismatchData: Decodable, Hashable {
    let loadId: Int?
    let loadNumber: String?
    let carrierContactInitials: String?
    let priority: String?            // P0 / P1
    let slaSecondsRemaining: Int?
    let driverAwaiting: Bool?
    let discrepancies: [BOLDiscrepancy]
}
private struct BOLDiscrepancy: Decodable, Hashable {
    let field: String
    let tendered: String?
    let uploaded: String?
    let delta: String?
}

struct DispatcherBOLMismatchScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) { BOLBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct BOLBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var data: BOLMismatchData?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && data == nil {
                    LifecycleCard { Text("Loading exception detail…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let d = data {
                    statusCard(d)
                    if !d.discrepancies.isEmpty { discrepanciesSection(d.discrepancies) }
                    actionRow
                } else {
                    EusoEmptyState(systemImage: "exclamationmark.triangle", title: "No mismatch data", subtitle: "BOL mismatch details land here once the driver uploads.")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("BOL Mismatch").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if let d = data {
                Text("\(d.loadNumber ?? "LD-\(d.loadId ?? 0)") · \(d.discrepancies.count) field\(d.discrepancies.count == 1 ? "" : "s") disagree")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func statusCard(_ d: BOLMismatchData) -> some View {
        LifecycleCard(accentDanger: (d.priority ?? "") == "P0" || (d.priority ?? "") == "P1") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let init0 = d.carrierContactInitials {
                        ZStack {
                            Circle().fill(palette.bgCardSoft).frame(width: 34, height: 34)
                            Text(init0).font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        }
                    }
                    Text(d.priority ?? "P1")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(((d.priority ?? "") == "P0" ? Color.red : Color.orange).opacity(0.18)))
                        .foregroundStyle((d.priority ?? "") == "P0" ? .red : .orange)
                    Spacer()
                    if let sla = d.slaSecondsRemaining {
                        let m = sla / 60; let s = sla % 60
                        Text("SLA \(String(format: "0:%02d:%02d", m, s))")
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                Text("\(d.discrepancies.count) of 4 fields disagree · driver awaiting")
                    .font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private func discrepanciesSection(_ rows: [BOLDiscrepancy]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DISCREPANCIES · \(rows.count) OF 4 FIELDS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                LifecycleCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.field.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                            Text("\(r.tendered ?? "—") → \(r.uploaded ?? "—")")
                                .font(.caption.monospaced()).foregroundStyle(palette.textPrimary)
                        }
                        Spacer()
                        if let delta = r.delta {
                            Text(delta).font(.body.weight(.heavy).monospacedDigit()).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { } label: {
                Text("Accept upload")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button { } label: {
                Text("Reject · request fix")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.5)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        // Wire to a real BOL mismatch endpoint when shipped; for now
        // synthesize a minimum-info row from loads.getById so the
        // surface renders end-to-end without fabricating field-level
        // disagreement data.
        struct In: Encodable { let id: String }
        struct LoadLite: Decodable {
            let id: Int?
            let loadNumber: String?
        }
        do {
            let load: LoadLite = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
            data = BOLMismatchData(
                loadId: load.id,
                loadNumber: load.loadNumber,
                carrierContactInitials: "CH",
                priority: "P1",
                slaSecondsRemaining: 522,
                driverAwaiting: true,
                discrepancies: [] // populated when bolReview.getMismatchDetail ships
            )
        } catch { /* */ }
    }
}

// MARK: - Previews

#Preview("403 Tender · Dark")  { DispatcherTenderQueueScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("403 Tender · Light") { DispatcherTenderQueueScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("405 Comms · Dark")   { DispatcherCommsHubScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("405 Comms · Light")  { DispatcherCommsHubScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("411 BOL · Dark")     { DispatcherBOLMismatchScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("411 BOL · Light")    { DispatcherBOLMismatchScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
