//
//  404_CatalystAssetProcurement.swift
//  EusoTrip 2027 UI — Catalyst track · 404 Catalyst Asset Procurement
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Production contracts:
//  - vendorSupplier.getProcurementPipeline returns tenant-owned procurement
//    RFQs and purchase orders from their canonical tables.
//  - vendorSupplier.createRfq commits the RFQ and durable audit intent in one
//    transaction, with a client-retained idempotency key.
//  - companies.getMyCompany and assetTracking.getAssetLifecycleStatus provide
//    company identity and current-fleet context without substituting freight
//    loads for procurement records.
//

import SwiftUI

// MARK: - Domain

/// Stages preserve the distinction between a request, an active solicitation,
/// a purchase order, and a received order.
enum ProcurementStage: String, CaseIterable, Identifiable {
    case request, sourcing, order, received, other

    var id: String { rawValue }

    /// Section-label stem — row + unit counts are appended live by the store.
    var label: String {
        switch self {
        case .request:  return "REQUEST DRAFTS"
        case .sourcing: return "OPEN RFQS"
        case .order:    return "PURCHASE ORDERS"
        case .received: return "RECEIVED"
        case .other:    return "OTHER RECORDS"
        }
    }

    /// Chip / pill tint. Attention lines override with `Brand.warning`.
    var hue: Color {
        switch self {
        case .request:  return Brand.rail
        case .sourcing: return Brand.info
        case .order:    return Brand.escort
        case .received: return Brand.success
        case .other:    return Brand.warning
        }
    }
}

/// Equipment glyph on a row's icon chip. SF Symbols only — no hand-drawn
/// silhouettes (see the FUSION note in the header).
enum ProcurementGlyph: String, Codable {
    case asset, tractor, dryVan, reefer

    var systemImage: String {
        switch self {
        case .asset:   return "wrench.and.screwdriver"
        case .tractor: return "truck.box"
        case .dryVan:  return "shippingbox"
        case .reefer:  return "snowflake"
        }
    }
}

/// One dense pipeline row. `title` is the multi-unit line item
/// ("2× Cascadia 126 sleeper"); `spec` is the mono sub carrying spec, dealer and
/// the RFQ/PO id; the right cluster is `pill` + `money` + `etaNote`.
struct ProcurementLine: Identifiable, Equatable {
    let id: String                 // rfqNumber or poNumber — the server key
    let glyph: ProcurementGlyph
    let title: String
    let spec: String
    let pill: String
    let money: String
    let etaNote: String
    /// True for the single line whose dealer price-hold is lapsing. Drives the
    /// dangerWash attention treatment and the warning hue.
    let needsDecision: Bool
}

/// One stage card: header (label · row count · unit count · subtotal) + lines.
struct ProcurementStageGroup: Identifiable, Equatable {
    let stage: ProcurementStage
    let countCaption: String       // "2 RFQS · 6 UNITS"
    let subtotal: String           // "$681,200"
    let lines: [ProcurementLine]

    var id: String { stage.rawValue }
}

/// Everything the board draws. Composed by `AssetProcurementStore` from the
/// procedures in the wiring manifest — never constructed inside the view.
struct AssetProcurementVM: Equatable {
    // Identity register
    let carrierLine: String        // "Aurora Freight Lines · USDOT 3 482 119"
    let cacheCaption: String       // "updated · 12m ago"
    let cacheIsStale: Bool         // true once the last successful read is old
    // Summary band
    let committedCapital: String   // "$962K"
    let committedNote: String      // "4 open POs · net-30"
    let pipelineUnits: String      // "11"
    let pipelineUnitWord: String   // "units"
    let pipelineSplit: String      // "5 on order · 6 quoted"
    let nextDeliveryRelative: String  // "in 9 d"
    let nextDeliveryUnit: String   // "TRL-0871"
    // Pipeline
    let groups: [ProcurementStageGroup]
    // Measured context from the current fleet roster.
    let contextTitle: String
    let contextSub: String
}

enum AssetRfqCategory: String, CaseIterable, Identifiable {
    case parts
    case trailerLeasing = "trailer_leasing"
    case technology
    case safetyEquipment = "safety_equipment"
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .parts: return "Parts"
        case .trailerLeasing: return "Trailer leasing"
        case .technology: return "Technology"
        case .safetyEquipment: return "Safety equipment"
        case .other: return "Other asset"
        }
    }
}

// MARK: - Store

/// Composes the board from the real routers and labels the age of the latest
/// successful in-memory refresh. Draft creation requires a live connection.
@MainActor
final class AssetProcurementStore: ObservableObject {

    @Published private(set) var vm: AssetProcurementVM?
    @Published private(set) var loading = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var offline = false
    @Published private(set) var loadError: String?
    @Published private(set) var actionError: String?
    @Published private(set) var createdRfqNumber: String?
    @Published private(set) var isSubmitting = false
    @Published private(set) var hasCompanyContext = false
    @Published private(set) var pipelineLoaded = false
    @Published private(set) var pipelineHasMore = false

    static let freshnessWindow: TimeInterval = 60 * 60

    // MARK: Wire DTOs — shapes taken verbatim from the routers on disk.

    private struct CompanyWire: Decodable {
        let id: Int
        let name: String
        let dotNumber: String?
    }

    private struct CreateRfqIn: Encodable {
        struct Item: Encodable {
            let description: String
            let quantity: Int
            let unit: String
            let specifications: String?
        }
        let idempotencyKey: String
        let title: String
        let description: String
        let category: String
        let items: [Item]
        let deadline: String
        let deliveryDate: String?
    }

    private struct ProcurementPipelineIn: Encodable {
        let limitPerRecordType: Int
    }

    private struct ProcurementPipelineWire: Decodable {
        struct Entry: Decodable {
            let id: String
            let recordId: String
            let recordType: String
            let stage: String
            let referenceNumber: String
            let title: String
            let description: String?
            let category: String?
            let status: String
            let itemDescription: String?
            let specifications: String?
            let unitCount: Int?
            let amount: Double?
            let vendorName: String?
            let invitedVendorCount: Int?
            let deadline: String?
            let targetDeliveryDate: String?
            let orderedAt: String?
            let receivedAt: String?
            let createdAt: String
            let updatedAt: String?
        }

        struct Summary: Decodable {
            let activeRfqCount: Int
            let openOrderCount: Int
            let committedOrderValue: Double
            let nextTargetDate: String?
            let nextTargetReference: String?
        }

        let companyId: Int
        let generatedAt: String
        let entries: [Entry]
        let hasMore: Bool
        let summary: Summary
    }

    /// assetTracking.getAssetLifecycleStatus — assetTracking.ts:910
    private struct LifecycleWire: Decodable {
        struct Stage: Decodable {
            let stage: String
            let label: String
            let count: Int
        }
        let stages: [Stage]
        let totalAssets: Int
    }


    // MARK: Read

    func refresh() async {
        loading = true
        loadError = nil
        defer { loading = false }
        let api = EusoTripAPI.shared
        var company: CompanyWire?
        var lifecycle: LifecycleWire?
        var pipeline: ProcurementPipelineWire?
        var failures: [String] = []

        do {
            company = try await api.queryNoInput("companies.getMyCompany")
        } catch {
            failures.append("Company identity could not load: \(error.eusoUserCopy)")
        }
        do {
            lifecycle = try await api.queryNoInput("assetTracking.getAssetLifecycleStatus")
        } catch {
            failures.append("Fleet context could not load: \(error.eusoUserCopy)")
        }
        do {
            pipeline = try await api.query(
                "vendorSupplier.getProcurementPipeline",
                input: ProcurementPipelineIn(limitPerRecordType: 100))
        } catch {
            failures.append("Procurement records could not load: \(error.eusoUserCopy)")
        }

        let reachable = company != nil || lifecycle != nil || pipeline != nil
        hasCompanyContext = (company?.id ?? pipeline?.companyId ?? 0) > 0
        pipelineLoaded = pipeline != nil
        pipelineHasMore = pipeline?.hasMore ?? false
        offline = !reachable
        if reachable { lastSyncedAt = Date() }
        loadError = failures.isEmpty ? nil : failures.joined(separator: " ")
        vm = Self.compose(
            company: company,
            lifecycle: lifecycle,
            pipeline: pipeline,
            syncedAt: lastSyncedAt)
    }

    // MARK: Write — ONLINE_ONLY (money movement never queues)

    /// CTA "New procurement request" → vendorSupplier.createRfq
    /// Refuses offline rather than latching an RFQ
    /// that would later commit capital the operator can no longer price.
    @discardableResult
    func createProcurementRequest(
        title: String,
        description: String,
        category: AssetRfqCategory,
        itemDescription: String,
        quantity: Int,
        specifications: String?,
        deadline: Date,
        deliveryDate: Date?,
        idempotencyKey: UUID
    ) async -> Bool {
        guard !offline else {
            actionError = "A live connection is required to create a procurement RFQ."
            return false
        }
        guard hasCompanyContext else {
            actionError = "A company profile is required before a procurement RFQ can be created."
            return false
        }
        isSubmitting = true
        actionError = nil
        createdRfqNumber = nil
        defer { isSubmitting = false }
        struct RfqOut: Decodable {
            let id: String
            let rfqNumber: String
            let status: String
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        let trimmedSpecifications = specifications?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = CreateRfqIn(
            idempotencyKey: idempotencyKey.uuidString.lowercased(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.rawValue,
            items: [.init(
                description: itemDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                quantity: quantity,
                unit: "each",
                specifications: trimmedSpecifications?.isEmpty == false ? trimmedSpecifications : nil)],
            deadline: formatter.string(from: deadline),
            deliveryDate: deliveryDate.map { formatter.string(from: $0) })
        do {
            let out: RfqOut = try await EusoTripAPI.shared.mutation(
                "vendorSupplier.createRfq", input: payload)
            createdRfqNumber = out.rfqNumber
            await refresh()
            return true
        } catch {
            actionError = "The procurement RFQ was not created. \(error.eusoUserCopy)"
            return false
        }
    }

    // MARK: Composition

    private static func freshnessCaption(_ syncedAt: Date?) -> (String, Bool) {
        guard let syncedAt else { return ("not updated", true) }
        let age = Date().timeIntervalSince(syncedAt)
        let stale = age > freshnessWindow
        if age < 60   { return ("updated · just now", stale) }
        if age < 3600 { return ("updated · \(Int(age / 60))m ago", stale) }
        return ("updated · \(Int(age / 3600))h ago", stale)
    }

    private static func compose(
        company: CompanyWire?,
        lifecycle: LifecycleWire?,
        pipeline: ProcurementPipelineWire?,
        syncedAt: Date?
    ) -> AssetProcurementVM {
        let (caption, stale) = freshnessCaption(syncedAt)
        var identityParts: [String] = []
        if let name = company?.name, !name.isEmpty { identityParts.append(name) }
        if let dot = company?.dotNumber, !dot.isEmpty { identityParts.append("USDOT \(dot)") }
        let identity = identityParts.joined(separator: " · ")
        let entries = pipeline?.entries ?? []
        let groups = ProcurementStage.allCases.compactMap { stage -> ProcurementStageGroup? in
            let stageEntries = entries.filter {
                (ProcurementStage(rawValue: $0.stage) ?? .other) == stage
            }
            guard !stageEntries.isEmpty else { return nil }
            let unitCount = stageEntries.compactMap(\.unitCount).reduce(0, +)
            let lines = stageEntries.map(makeLine)
            let amounts = stageEntries.compactMap(\.amount)
            let recordName = stage == .request || stage == .sourcing ? "RFQ" : "PO"
            let countCaption = "\(stageEntries.count) \(recordName)\(stageEntries.count == 1 ? "" : "S")"
                + (unitCount > 0 ? " · \(unitCount) UNITS" : "")
            return ProcurementStageGroup(
                stage: stage,
                countCaption: countCaption,
                subtotal: amounts.isEmpty ? "NOT PRICED" : money(amounts.reduce(0, +)),
                lines: lines)
        }
        let recordedUnits = entries.compactMap(\.unitCount).reduce(0, +)
        let summary = pipeline?.summary
        let nextTarget = relativeDate(summary?.nextTargetDate)

        return AssetProcurementVM(
            carrierLine: identity.isEmpty ? "Company identity unavailable" : identity,
            cacheCaption: caption,
            cacheIsStale: stale,
            committedCapital: summary.map { compactMoney($0.committedOrderValue) } ?? "—",
            committedNote: summary.map {
                "\($0.openOrderCount) active PO\($0.openOrderCount == 1 ? "" : "s")"
            } ?? "Pipeline not loaded",
            pipelineUnits: pipeline == nil ? "—" : "\(recordedUnits)",
            pipelineUnitWord: recordedUnits == 1 ? "unit" : "units",
            pipelineSplit: summary.map {
                "\($0.activeRfqCount) active RFQs · \($0.openOrderCount) open POs"
            } ?? "Pipeline not loaded",
            nextDeliveryRelative: nextTarget,
            nextDeliveryUnit: summary?.nextTargetReference ?? "No requested date",
            groups: groups,
            contextTitle: "Current fleet context",
            contextSub: lifecycle.map { "\($0.totalAssets) assets across \($0.stages.count) lifecycle states" }
                ?? "Fleet lifecycle data is unavailable")
    }

    private static func makeLine(_ entry: ProcurementPipelineWire.Entry) -> ProcurementLine {
        var details: [String] = []
        if let item = entry.itemDescription, item != entry.title { details.append(item) }
        if let specification = entry.specifications { details.append(specification) }
        if let vendor = entry.vendorName { details.append(vendor) }
        if let count = entry.unitCount { details.append("\(count) unit\(count == 1 ? "" : "s")") }
        details.append(entry.referenceNumber)

        let timing: String
        if let target = entry.targetDeliveryDate {
            timing = "target \(displayDate(target))"
        } else if let deadline = entry.deadline {
            timing = "quotes due \(displayDate(deadline))"
        } else if let receivedAt = entry.receivedAt {
            timing = "received \(displayDate(receivedAt))"
        } else if let orderedAt = entry.orderedAt {
            timing = "ordered \(displayDate(orderedAt))"
        } else {
            timing = "recorded \(displayDate(entry.createdAt))"
        }

        let deadline = parseDate(entry.deadline)
        let needsDecision = entry.recordType == "rfq"
            && ["draft", "open"].contains(entry.status)
            && deadline.map { $0.timeIntervalSinceNow <= 24 * 60 * 60 } == true

        return ProcurementLine(
            id: entry.id,
            glyph: glyph(for: entry),
            title: entry.title,
            spec: details.joined(separator: " · "),
            pill: entry.status.replacingOccurrences(of: "_", with: " ").uppercased(),
            money: entry.amount.map(money) ?? "Not priced",
            etaNote: timing,
            needsDecision: needsDecision)
    }

    private static func glyph(for entry: ProcurementPipelineWire.Entry) -> ProcurementGlyph {
        let text = [entry.title, entry.itemDescription, entry.category]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if text.contains("reefer") || text.contains("refriger") { return .reefer }
        if text.contains("trailer") || text.contains("dry van") { return .dryVan }
        if text.contains("tractor") || text.contains("truck") { return .tractor }
        return .asset
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(value.prefix(10)))
    }

    private static func displayDate(_ value: String) -> String {
        guard let date = parseDate(value) else { return value }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func relativeDate(_ value: String?) -> String {
        guard let date = parseDate(value) else { return "—" }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: date)).day ?? 0
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        if days > 1 { return "in \(days) d" }
        return "\(-days) d overdue"
    }

    private static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    private static func compactMoney(_ value: Double) -> String {
        if abs(value) >= 1_000_000 {
            return "$\((value / 1_000_000).formatted(.number.precision(.fractionLength(0...1))))M"
        }
        if abs(value) >= 1_000 {
            return "$\((value / 1_000).formatted(.number.precision(.fractionLength(0...1))))K"
        }
        return money(value)
    }
}

// MARK: - Screen

/// The single `✦` eyebrow for this surface. Extracted so the board and its
/// degraded skeleton share one literal — the sparkle appears exactly once,
/// whichever branch is on screen.
private struct ProcurementEyebrow: View {
    @Environment(\.palette) var palette
    var showRegister: Bool = true
    var body: some View {
        HStack {
            EusoTripEyebrow(verbatim: "CATALYST · PROCUREMENT")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            if showRegister {
                Text("ASSET REQUESTS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}

struct CatalystAssetProcurement: View {
    @Environment(\.palette) private var palette
    @ObservedObject var store: AssetProcurementStore
    let vm: AssetProcurementVM
    @State private var showingNewRequest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s4) {
                summaryBand
                ForEach(vm.groups) { stageGroup($0) }
                if vm.groups.isEmpty { pipelineState }
                if store.pipelineHasMore {
                    statusLine(
                        "Showing the 100 most recent RFQs and 100 most recent purchase orders.",
                        color: palette.textSecondary)
                }
                ctaPair
                contextRow
                if let number = store.createdRfqNumber {
                    statusLine("Draft request \(number) was created.", color: Brand.success)
                }
                if let error = store.actionError ?? store.loadError {
                    statusLine(error, color: Brand.warning)
                }
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .task { await store.refresh() }
        .eusoRefreshable { await store.refresh() }
        .sheet(isPresented: $showingNewRequest) {
            ProcurementRequestSheet(store: store)
        }
    }

    // MARK: Top bar — BOARD-class tab landing: no back chevron, plain title

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ProcurementEyebrow()
            Text("Asset procurement")
                .font(EType.display).tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            HStack(alignment: .firstTextBaseline) {
                Text(vm.carrierLine)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                // Age of the last successful in-memory refresh.
                Text(vm.cacheCaption)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(vm.cacheIsStale ? Brand.warning : palette.textTertiary)
                    .accessibilityLabel("Pipeline \(vm.cacheCaption)")
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: Hero — summary BAND (three cells; deliberately not an ActiveCard)

    private var summaryBand: some View {
        HStack(alignment: .top, spacing: 0) {
            bandCell(.leading) {
                Text("COMMITTED").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(vm.committedCapital)
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                Text(vm.committedNote).font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
            bandDivider
            bandCell(.leading) {
                Text("RECORDED UNITS").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(vm.pipelineUnits)
                        .font(.system(size: 28, weight: .semibold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.pipelineUnitWord)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
                Text(vm.pipelineSplit).font(.system(size: 10.5))
                    .foregroundStyle(palette.textSecondary)
            }
            bandDivider
            bandCell(.trailing) {
                Text("NEXT TARGET").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(vm.nextDeliveryRelative)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text(vm.nextDeliveryUnit)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, Space.s3)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Committed orders \(vm.committedCapital), \(vm.committedNote). "
            + "Recorded procurement units \(vm.pipelineUnits) \(vm.pipelineUnitWord), \(vm.pipelineSplit). "
            + "Next requested target \(vm.nextDeliveryRelative), \(vm.nextDeliveryUnit)."
        )
    }

    @ViewBuilder
    private func bandCell<C: View>(_ alignment: HorizontalAlignment,
                                   @ViewBuilder _ cell: () -> C) -> some View {
        VStack(alignment: alignment, spacing: 4) { cell() }
            .frame(maxWidth: .infinity,
                   alignment: alignment == .trailing ? .trailing : .leading)
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    private var bandDivider: some View {
        Rectangle().fill(palette.borderFaint)
            .frame(width: 1, height: 46)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Stage group — header (count + subtotal) over a card of dense rows

    private func stageGroup(_ group: ProcurementStageGroup) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("\(group.stage.label) · \(group.countCaption)")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(group.subtotal)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(group.lines.enumerated()), id: \.element.id) { index, line in
                    lineRow(line, stage: group.stage)
                    if index < group.lines.count - 1 && !line.needsDecision {
                        Rectangle().fill(palette.borderFaint)
                            .frame(height: 1)
                            .padding(.leading, 66)
                            .padding(.trailing, 14)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func lineRow(_ line: ProcurementLine, stage: ProcurementStage) -> some View {
        let hue = line.needsDecision ? Brand.warning : stage.hue
        return Group {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm + 2, style: .continuous)
                        .fill(hue.opacity(0.16))
                    Image(systemName: line.glyph.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(hue)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(line.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(line.spec)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.85)

                Spacer(minLength: Space.s2)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(line.pill)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(hue)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(hue.opacity(0.18)))
                    Text(line.money)
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text(line.etaNote)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                }
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(attentionWash(line.needsDecision))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(stage.label). \(line.title). \(line.spec). \(line.pill). "
            + "\(line.money). \(line.etaNote)."
        )
    }

    /// dangerWash — the ONE attention treatment on this screen.
    @ViewBuilder
    private func attentionWash(_ on: Bool) -> some View {
        if on {
            RoundedRectangle(cornerRadius: Radius.md + 2, style: .continuous)
                .fill(LinearGradient(colors: [Brand.danger.opacity(0.12),
                                              Brand.warning.opacity(0.12)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md + 2, style: .continuous)
                        .strokeBorder(Brand.warning.opacity(0.38), lineWidth: 1))
                .padding(.horizontal, 4)
        } else {
            Color.clear
        }
    }

    private var pipelineState: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(store.pipelineLoaded ? "PROCUREMENT PIPELINE" : "PIPELINE READ")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(store.pipelineLoaded
                 ? "No active procurement RFQs or purchase orders have been recorded for this company."
                 : "Procurement records did not load. Retry to restore the live company pipeline.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            if !store.pipelineLoaded {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(EType.bodyStrong)
                        .foregroundStyle(Brand.info)
                }
                .buttonStyle(.plain)
                .disabled(store.loading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: CTA — createRfq requires a complete request form

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Button { showingNewRequest = true } label: {
                    Text("New procurement RFQ")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textOnGradient)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(store.offline || !store.hasCompanyContext || store.isSubmitting)
            .opacity(store.offline || !store.hasCompanyContext || store.isSubmitting ? 0.45 : 1)
            if store.offline {
                Text("A live connection is required to create an RFQ.")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.warning)
            } else if !store.hasCompanyContext {
                Text("Complete the company profile before creating a procurement RFQ.")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.warning)
            }
        }
    }

    private var contextRow: some View {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                 center: .init(x: 0.35, y: 0.30),
                                                 startRadius: 0, endRadius: 16))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.contextTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.contextSub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.85)
                Spacer()
            }
            .padding(Space.s3)
            .frame(minHeight: 56)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func statusLine(_ text: String, color: Color) -> some View {
        Text(text)
            .font(EType.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProcurementRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AssetProcurementStore

    @State private var title = ""
    @State private var description = ""
    @State private var category: AssetRfqCategory = .other
    @State private var itemDescription = ""
    @State private var quantity = 1
    @State private var specifications = ""
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var hasDeliveryDate = false
    @State private var deliveryDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var idempotencyKey = UUID()

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quantity > 0
            && deadline > Date()
            && (!hasDeliveryDate || deliveryDate >= deadline)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    TextField("Title", text: $title)
                    TextField("Business need", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("Category", selection: $category) {
                        ForEach(AssetRfqCategory.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                }
                Section("Item") {
                    TextField("Asset or item", text: $itemDescription)
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...10_000)
                    TextField("Specifications (optional)", text: $specifications, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Timing") {
                    DatePicker("Quote deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                    Toggle("Set requested delivery date", isOn: $hasDeliveryDate)
                    if hasDeliveryDate {
                        DatePicker("Delivery date", selection: $deliveryDate,
                                   in: deadline..., displayedComponents: .date)
                    }
                }
                if let error = store.actionError {
                    Text(error).foregroundStyle(Brand.warning)
                }
            }
            .navigationTitle("Procurement RFQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isSubmitting ? "Creating…" : "Create RFQ") {
                        Task {
                            let success = await store.createProcurementRequest(
                                title: title,
                                description: description,
                                category: category,
                                itemDescription: itemDescription,
                                quantity: quantity,
                                specifications: specifications,
                                deadline: deadline,
                                deliveryDate: hasDeliveryDate ? deliveryDate : nil,
                                idempotencyKey: idempotencyKey)
                            if success { dismiss() }
                        }
                    }
                    .disabled(!canSubmit || store.isSubmitting)
                }
            }
        }
    }
}

// MARK: - Shell wrapper + real Catalyst BottomNav (FLEET current)

/// Catalyst chrome for this fire: HOME · DISPATCH · [orb] · FLEET · ME.
/// Every slot routes through the real `CarrierNavDispatcher`, so "fleet"
/// resolves through `CarrierNavRoute.map["fleet"]` (CarrierNavController.swift:87).
private func catalystNav404() -> ([NavSlot], [NavSlot]) {
    let leading = CarrierNavRoute.leading(current: .drivers)
    let trailing = CarrierNavRoute.trailing(current: .drivers)
    return (leading, trailing)
}

struct CatalystAssetProcurementScreen: View {
    let theme: Theme.Palette
    @StateObject private var store = AssetProcurementStore()

    var body: some View {
        let (lead, trail) = catalystNav404()
        Shell(theme: theme) {
            if let vm = store.vm {
                CatalystAssetProcurement(store: store, vm: vm)
            } else {
                ProcurementBoardSkeleton()
            }
        } nav: {
            BottomNav(leading: lead, trailing: trail, orbState: .idle,
                      onTapOrb: { CarrierNavDispatcher.handle("esang") })
        }
    }
}

/// Degraded state before the first successful read. A capital board must never
/// imply "nothing on order" while it is still loading, so it says so plainly.
private struct ProcurementBoardSkeleton: View {
    @Environment(\.palette) var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ProcurementEyebrow(showRegister: false)
            Text("Asset procurement")
                .font(EType.display).tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            IridescentHairline()
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("LOADING PIPELINE").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text("Committed capital is not shown until the read completes.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }
}

#Preview("404 Catalyst Asset Procurement · Light") {
    CatalystAssetProcurementScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}

#Preview("404 Catalyst Asset Procurement · Dark") {
    CatalystAssetProcurementScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}
