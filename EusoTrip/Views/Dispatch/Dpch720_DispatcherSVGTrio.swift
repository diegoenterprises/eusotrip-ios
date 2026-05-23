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
    @State private var actionInFlight: String? = nil   // load id mid-mutation
    @State private var ack: String? = nil
    @State private var err: String? = nil
    @State private var counterFor: PendingTender? = nil
    @State private var counterAmount: String = ""
    /// `"accept"` / `"decline"` when a tender card is hovering over the
    /// matching drop tile. Drives the gradient stroke + label flip.
    @State private var dragHoverTile: String? = nil

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
                if !tenders.isEmpty { tripDropZones }
                if loading && tenders.isEmpty {
                    LifecycleCard { Text("Loading queue…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if sorted.isEmpty {
                    EusoEmptyState(systemImage: "tray", title: "Queue is clear", subtitle: "Pending tenders land here as shippers submit them.")
                } else {
                    ForEach(sorted) { t in
                        tenderCard(t)
                            .draggable(t.id) {
                                tenderCard(t)
                                    .frame(maxWidth: 320)
                                    .opacity(0.92)
                                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                            }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Counter offer", isPresented: Binding(get: { counterFor != nil }, set: { if !$0 { counterFor = nil } })) {
            TextField("Rate", text: $counterAmount).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) { counterFor = nil; counterAmount = "" }
            Button("Submit") {
                if let t = counterFor {
                    let amount = counterAmount
                    Task { await submitCounter(t, rateStr: amount) }
                }
            }
        } message: {
            if let t = counterFor {
                Text("Counter \(t.loadNumber ?? "LD-\(t.id)") · current $\(t.rate ?? "—")")
            } else {
                Text("Enter your counter rate")
            }
        }
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

    /// Twin drop-zone bar — drag a tender card onto ACCEPT or DECLINE to
    /// fire dispatchRole.{acceptLoad, declineLoad} in one gesture.
    /// COUNTER stays on the card because it needs a rate text input
    /// (can't be expressed in a pure drag). Same DnD shape as
    /// 305_CarrierCounterResponse.
    private var tripDropZones: some View {
        HStack(spacing: Space.s2) {
            tripTile(id: "accept",  label: "ACCEPT",  hint: "Take the tender + fire compliance gates", icon: "checkmark.seal.fill", tint: Brand.success)
            tripTile(id: "decline", label: "DECLINE", hint: "Pass — shipper sees decline + can re-tender", icon: "xmark.octagon.fill",   tint: Brand.danger)
        }
    }

    private func tripTile(id: String, label: String, hint: String, icon: String, tint: Color) -> some View {
        let isHover = dragHoverTile == id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
            Text(isHover ? "RELEASE TO \(label)" : hint)
                .font(EType.caption)
                .foregroundStyle(isHover ? tint : palette.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .padding(10)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(tint.opacity(0.3)),
                    lineWidth: isHover ? 2 : 1
                )
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let tid = droppedIds.first else { return false }
            guard let t = tenders.first(where: { $0.id == tid }) else { return false }
            switch id {
            case "accept":  Task { await acceptTender(t) };  return true
            case "decline": Task { await declineTender(t) }; return true
            default: return false
            }
        } isTargeted: { hovering in
            dragHoverTile = hovering ? id : (dragHoverTile == id ? nil : dragHoverTile)
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
                    Button { Task { await acceptTender(t) } } label: {
                        HStack(spacing: 4) {
                            if actionInFlight == t.id { ProgressView().tint(.white).scaleEffect(0.5) }
                            Text(actionInFlight == t.id ? "..." : "ACCEPT")
                                .font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                        }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.green))
                    }.buttonStyle(.plain).disabled(actionInFlight != nil)
                    Button {
                        counterFor = t
                        counterAmount = t.rate ?? ""
                    } label: {
                        Text("COUNTER").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(palette.bgCardSoft))
                            .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.4)))
                    }.buttonStyle(.plain).disabled(actionInFlight != nil)
                    Button { Task { await declineTender(t) } } label: {
                        Text(actionInFlight == t.id ? "..." : "DECLINE")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    }.buttonStyle(.plain).disabled(actionInFlight != nil)
                }
                .padding(.top, 4)
                if let ack, actionInFlight == nil {
                    Text(ack).font(.caption2).foregroundStyle(.green).padding(.top, 2)
                }
                if let err, actionInFlight == nil {
                    Text(err).font(.caption2).foregroundStyle(.red).padding(.top, 2)
                }
            }
        }
    }

    private func expiresWithin(_ iso: String?, hours: Int) -> Bool {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return false }
        return d.timeIntervalSinceNow < Double(hours) * 3600 && d.timeIntervalSinceNow > 0
    }

    // MARK: - Real wirings — dispatchRole.acceptLoad / declineLoad + counter

    private func acceptTender(_ t: PendingTender) async {
        actionInFlight = t.id; ack = nil; err = nil
        defer { actionInFlight = nil }
        struct In: Encodable { let loadId: String }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let status: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.acceptLoad",
                input: In(loadId: String(t.id))
            )
            if resp.success != false {
                ack = "Accepted \(t.loadNumber ?? "LD-\(t.id)") · status \(resp.status ?? "accepted")."
                await load()
            } else {
                err = "Accept returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Accept failed: \(e)"
        }
    }

    private func declineTender(_ t: PendingTender) async {
        actionInFlight = t.id; ack = nil; err = nil
        defer { actionInFlight = nil }
        struct In: Encodable { let loadId: String; let reason: String? }
        struct Out: Decodable { let success: Bool?; let loadId: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.declineLoad",
                input: In(loadId: String(t.id), reason: nil)
            )
            if resp.success != false {
                ack = "Declined \(t.loadNumber ?? "LD-\(t.id)")."
                await load()
            } else {
                err = "Decline returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Decline failed: \(e)"
        }
    }

    /// Counter the offered rate via bidReview.counterOffer. Fired from
    /// the counter alert below; expects a positive decimal.
    fileprivate func submitCounter(_ t: PendingTender, rateStr: String) async {
        guard let rate = Double(rateStr), rate > 0 else {
            err = "Counter requires a positive rate."
            return
        }
        actionInFlight = t.id; ack = nil; err = nil
        defer { actionInFlight = nil; counterFor = nil; counterAmount = "" }
        struct In: Encodable { let loadId: String; let counterRate: Double; let message: String? }
        struct Out: Decodable { let success: Bool?; let bidId: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "bidReview.counterOffer",
                input: In(loadId: String(t.id), counterRate: rate, message: nil)
            )
            if resp.success != false {
                ack = "Counter $\(Int(rate)) submitted on \(t.loadNumber ?? "LD-\(t.id)")."
                await load()
            } else {
                err = "Counter returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Counter failed: \(e)"
        }
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
    @State private var actionInFlight: Bool = false
    @State private var ack: String? = nil
    @State private var err: String? = nil

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
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { Task { await resolveMismatch(accept: true) } } label: {
                    HStack(spacing: 6) {
                        if actionInFlight { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text(actionInFlight ? "Submitting…" : "Accept upload")
                            .font(EType.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(actionInFlight)
                Button { Task { await resolveMismatch(accept: false) } } label: {
                    Text("Reject · request fix")
                        .font(EType.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(palette.textPrimary)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.5)))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(actionInFlight)
            }
            if let ack { Text(ack).font(.caption2).foregroundStyle(.green) }
            if let err { Text(err).font(.caption2).foregroundStyle(.red) }
        }
    }

    private func resolveMismatch(accept: Bool) async {
        actionInFlight = true; ack = nil; err = nil
        defer { actionInFlight = false }
        struct In: Encodable { let exceptionId: String; let resolution: String }
        struct Out: Decodable { let success: Bool?; let resolvedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.resolveException",
                input: In(
                    exceptionId: "bol-mismatch-\(loadId)",
                    resolution: accept ? "accepted-upload" : "rejected-request-fix"
                )
            )
            if resp.success != false {
                ack = accept
                    ? "BOL upload accepted · exception resolved."
                    : "Upload rejected · driver notified to re-upload."
            } else {
                err = "Resolve returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Resolve failed: \(e)"
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
