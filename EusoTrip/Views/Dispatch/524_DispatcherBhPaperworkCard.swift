//
//  524_DispatcherBhPaperworkCard.swift
//  EusoTrip — Dispatcher · BH lifecycle 524 · Paperwork (delivery-packet assembly).
//
//  Wireframe slot: 04 Dispatcher / 524 Dispatcher BH Paperwork Card (Light+Dark SVG,
//  golden re-port 2026-06-25 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition (SVG-verbatim): document-packet tray hero (completion ring + 2×3 grid of
//  document tiles with ready/pending badges) → DOCS / READY / MISSING KPI triple →
//  packet-detail card → lock-status strip → CTA pair (Request missing doc / Download).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                          — load + parties.
//    READ  documentManagement.getDocuments        — every document filed on this load;
//                                                   the six packet tiles bind to presence.
//    READ  documentManagement.getComplianceVault  — vault sync state row.
//    WRITE dispatch.sendDriverMessage             — Request the missing document.
//    WRITE documentManagement.bulkDownload        — Download the attached packet.
//    READ  dispatch.getDriverStatuses             — drivers.id for the request message.
//  Honest gaps (no server proc — rendered as data-absence states, never faked):
//    · single packet-completeness rollup (the 6-tile packet is composed client-side
//      from the live document list — every tile still binds to a real filed document)
//    · accessorial amounts on the load projection (row renders the absence)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens only.
//

import SwiftUI

// MARK: - Screen

struct DispatcherBHPaperwork524Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH524Body(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                    isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                  isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Packet definition (labels only — readiness binds to filed documents)

private struct BH524Tile {
    let label: String
    let matches: (BH524Doc) -> Bool
}

// MARK: - Body

private struct BH524Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var docs: [BH524Doc] = []
    @State private var docsLoaded = false
    @State private var vaultSynced: Bool?
    @State private var loadFailed = false
    @State private var driverRow: BH524DriverRow?
    @State private var margin: BH524Margin?
    @State private var requestInFlight = false
    @State private var downloadInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?

    private let tiles: [BH524Tile] = [
        BH524Tile(label: "BOL")        { $0.type == "bol" },
        BH524Tile(label: "POD")        { $0.type == "pod" || $0.type == "delivery_receipt" },
        BH524Tile(label: "Temp trace") { ($0.name ?? "").localizedCaseInsensitiveContains("temp") },
        BH524Tile(label: "Weight")     { $0.type == "scale_ticket" },
        BH524Tile(label: "Lumper")     { $0.type == "lumper_receipt" },
        BH524Tile(label: "Rate conf")  { $0.type == "rate_confirmation" },
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrowRow
                titleRow
                Rectangle().fill(palette.iridescentHairline).frame(height: 1)
                heroCard
                kpiTriple
                sectionLabel("PACKET DETAIL")
                packetDetail
                lockStrip
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(Brand.success) }
                }
                if let err = actionError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                }
                if loadFailed {
                    LifecycleCard(accentWarning: true) {
                        Text("Couldn't reach the document vault for this load. Everything shown is the last loaded state — pull to refresh.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BACKHAUL · PAPERWORK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("\(load?.loadNumber ?? "—") · \(load?.rateDisplay ?? "—")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
        }
    }

    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Button { navHandler?("board") } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text("Paperwork").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — packet tray

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DELIVERY PACKET")
                        .font(.system(size: 11, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(heroSubline)
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(palette.borderSoft, lineWidth: 5).frame(width: 44, height: 44)
                    Circle().trim(from: 0, to: CGFloat(readyCount) / CGFloat(tiles.count))
                        .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                    Text(docsLoaded ? "\(Int((Double(readyCount) / Double(tiles.count)) * 100))%" : "—")
                        .font(.system(size: 10, weight: .heavy).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                }
            }
            let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    tileView(tile)
                }
            }
            Text(missingLine)
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }

    private func tileView(_ tile: BH524Tile) -> some View {
        let ready = isReady(tile)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ready ? Brand.success : palette.textTertiary)
                Spacer()
                Image(systemName: ready ? "checkmark" : "hourglass")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(ready ? Brand.success : Brand.warning)
            }
            Text(tile.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(ready ? Brand.success.opacity(0.35) : palette.borderFaint, lineWidth: 1))
    }

    // MARK: KPI triple — DOCS / READY / MISSING

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH524Kpi(label: "DOCS", value: "\(tiles.count)", sub: "in the delivery packet", tint: nil)
            BH524Kpi(label: "READY",
                     value: docsLoaded ? "\(readyCount)" : "—",
                     sub: "filed on this load",
                     tint: Brand.success)
            BH524Kpi(label: "MISSING",
                     value: docsLoaded ? "\(tiles.count - readyCount)" : "—",
                     sub: docsLoaded && readyCount == tiles.count ? "packet complete" : "holding up the close",
                     tint: docsLoaded && readyCount < tiles.count ? Brand.warning : Brand.success)
        }
    }

    // MARK: Packet detail

    private var packetDetail: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                BH524DetailRow(title: firstMissingLabel.map { "\($0)" } ?? "All documents",
                               value: firstMissingLabel != nil ? "awaiting upload" : (docsLoaded ? "filed" : "—"),
                               valueTint: firstMissingLabel != nil ? Brand.warning : Brand.success)
                Divider().overlay(palette.borderFaint)
                BH524DetailRow(title: "Accessorials",
                               value: accessorialText,
                               valueTint: (margin?.accessorialTotal ?? 0) > 0 ? Brand.warning : nil)
                Divider().overlay(palette.borderFaint)
                BH524DetailRow(title: "Compliance vault",
                               value: vaultSynced == true ? "synced" : (vaultSynced == false ? "not reachable" : "—"),
                               valueTint: vaultSynced == true ? Brand.success : nil)
            }
        }
    }

    // MARK: Lock strip

    private var lockStrip: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: Space.s2) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(readyCount == tiles.count && docsLoaded ? "Packet complete" : "Packet locks when every document attaches")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(docsLoaded
                         ? "\(readyCount)/\(tiles.count) attached · bundle download covers what's filed"
                         : "the packet state loads with the document vault")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                BH524Chip(text: docsLoaded ? (readyCount == tiles.count ? "READY" : "PENDING") : "—",
                          tint: docsLoaded ? (readyCount == tiles.count ? Brand.success : Brand.warning) : Brand.neutral)
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await requestMissing() } } label: {
                HStack(spacing: 6) {
                    if requestInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: "square.and.arrow.down").font(.system(size: 13, weight: .bold)) }
                    Text(requestInFlight ? "Asking…" : requestCtaLabel).font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(requestInFlight)

            Button { Task { await downloadPacket() } } label: {
                HStack(spacing: 6) {
                    if downloadInFlight { ProgressView().scaleEffect(0.8) }
                    Text(downloadInFlight ? "Preparing…" : "Download").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(palette.textPrimary)
                .background(Capsule().fill(palette.bgCard))
                .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(downloadInFlight)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Derived display

    private func isReady(_ tile: BH524Tile) -> Bool {
        docs.contains(where: tile.matches)
    }

    private var readyCount: Int {
        tiles.filter { isReady($0) }.count
    }

    private var firstMissingLabel: String? {
        guard docsLoaded else { return nil }
        return tiles.first(where: { !isReady($0) })?.label
    }

    private var requestCtaLabel: String {
        if let missing = firstMissingLabel { return "Request \(missing.lowercased())" }
        return "Request update"
    }

    private var heroSubline: String {
        guard docsLoaded else { return "loading the document vault" }
        return "\(load?.loadNumber ?? "this load") · \(readyCount) of \(tiles.count) documents ready"
    }

    private var accessorialText: String {
        guard let m = margin?.accessorialTotal, m > 0 else { return "not on this load record" }
        return String(format: "$%.0f recorded", m)
    }

    private var missingLine: String {
        guard docsLoaded else { return "—" }
        if let missing = firstMissingLabel {
            return "\(missing) is the next item before the packet completes."
        }
        return "Every packet document is filed."
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s1)
    }

    // MARK: Data

    private func refresh() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
            loadFailed = false
        } catch { loadFailed = load == nil }
        await fetchDocs()
        await fetchVault()
        await fetchDriverRow()
        await fetchMargin()
    }

    private func fetchDocs() async {
        struct In: Encodable { let entityType: String; let entityId: String; let page: Int; let pageSize: Int }
        struct Out: Decodable { let documents: [BH524Doc]? }
        let numericId = (load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")
        do {
            let out: Out = try await EusoTripAPI.shared.query(
                "documentManagement.getDocuments",
                input: In(entityType: "load", entityId: numericId, page: 1, pageSize: 100))
            docs = out.documents ?? []
            docsLoaded = true
        } catch { docsLoaded = false }
    }

    private func fetchVault() async {
        struct In: Encodable { let entityType: String; let entityId: String }
        struct Out: Decodable { let overallScore: Double? }
        let numericId = (load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")
        do {
            let _: Out = try await EusoTripAPI.shared.query(
                "documentManagement.getComplianceVault",
                input: In(entityType: "load", entityId: numericId))
            vaultSynced = true
        } catch { vaultSynced = false }
    }

    private func fetchDriverRow() async {
        struct In: Encodable { let limit: Int }
        do {
            let rows: [BH524DriverRow] = try await EusoTripAPI.shared.query("dispatch.getDriverStatuses", input: In(limit: 50))
            let ln = load?.loadNumber
            let dn = load?.driver?.name
            driverRow = rows.first(where: { $0.load != nil && $0.load == ln })
                ?? rows.first(where: { dn != nil && $0.name == dn })
        } catch { driverRow = nil }
    }

    private func fetchMargin() async {
        struct In: Encodable { let loadId: String }
        let numericId = loadId.replacingOccurrences(of: "load_", with: "")
        do {
            margin = try await EusoTripAPI.shared.query("dispatch.getLoadMargin", input: In(loadId: numericId))
        } catch { margin = nil }
    }

    private func requestMissing() async {
        guard !requestInFlight else { return }
        requestInFlight = true; actionAck = nil; actionError = nil
        defer { requestInFlight = false }
        guard let missing = firstMissingLabel else {
            actionAck = "Every packet document is already filed — nothing to chase."
            return
        }
        guard let driverId = driverRow?.id else {
            actionError = "No driver row for this load is on the company board, so the document ask wasn't sent."
            return
        }
        struct In: Encodable { let driverId: String; let message: String; let priority: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.sendDriverMessage",
                input: In(driverId: driverId,
                          message: "Paperwork check on \(load?.loadNumber ?? "your load") — the \(missing.lowercased()) is the last item before the packet completes. Snap and upload it when you can.",
                          priority: "normal"))
            if out.success == true {
                actionAck = "Ask sent to \(driverRow?.name ?? "the driver") for the \(missing.lowercased()) — their upload lands in this packet."
            } else {
                actionError = "The document ask didn't send. The packet state stays live — try again."
            }
        } catch {
            actionError = "The document ask didn't send. The packet state stays live — check the connection and try again."
        }
    }

    private func downloadPacket() async {
        guard !downloadInFlight else { return }
        downloadInFlight = true; actionAck = nil; actionError = nil
        defer { downloadInFlight = false }
        let ids = docs.compactMap { $0.id }
        guard !ids.isEmpty else {
            actionError = "Nothing is filed on this load yet, so there's no packet to bundle."
            return
        }
        struct In: Encodable { let documentIds: [String]; let format: String }
        struct Out: Decodable { let success: Bool?; let downloadUrl: String?; let documentsIncluded: Int?; let error: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "documentManagement.bulkDownload",
                input: In(documentIds: ids, format: "zip"))
            if out.success == true {
                let n = out.documentsIncluded ?? ids.count
                actionAck = "Packet bundle prepared — \(n) document\(n == 1 ? "" : "s") in the download."
                if let path = out.downloadUrl,
                   let url = URL(string: path, relativeTo: EusoTripAPI.shared.baseURL)?.absoluteURL {
                    openURL(url)
                }
            } else {
                actionError = "The bundle didn't prepare. Every filed document stays in the vault — try again."
            }
        } catch {
            actionError = "The bundle didn't prepare. Every filed document stays in the vault — check the connection and try again."
        }
    }
}

// MARK: - Small primitives

private struct BH524Chip: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }
}

private struct BH524Kpi: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let sub: String
    let tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

private struct BH524DetailRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let value: String
    let valueTint: Color?
    var body: some View {
        HStack {
            Text(title).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value).font(EType.mono(.caption))
                .foregroundStyle(valueTint ?? palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - File-local decode + helpers

private struct BH524Doc: Decodable {
    let id: String?
    let name: String?
    let type: String?
    let status: String?
    let url: String?
    let uploadedAt: String?
}

private struct BH524DriverRow: Decodable {
    let id: String?
    let name: String?
    let status: String?
    let load: String?
    let hoursRemaining: Double?
}

private struct BH524Margin: Decodable {
    let accessorialTotal: Double?
}

// MARK: - Previews

#Preview("524 Paperwork · Dark") {
    DispatcherBHPaperwork524Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("524 Paperwork · Light") {
    DispatcherBHPaperwork524Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
