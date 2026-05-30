//
//  SparkBriefCard.swift
//  EusoTrip — Tier 1 #21/#23/#24 · ESANG brief
//
//  Shared Home-screen card for Shipper / Dispatcher / Catalyst.
//  Renders the headline + 3 role-specific count chips from the
//  ESANG brief. The brief AUTO-LOADS the moment the card appears
//  (.task → store.refresh) — there is no required first tap. A
//  subtle "Refresh" affordance re-pulls on demand; it is never the
//  first interaction the role has to make.
//
//  Per home-widget doctrine the brief sits between the topBar and
//  the weather card — "greeting → ESANG brief → Weather →
//  role-specific priority …".
//
//  Wires to the production tRPC surface:
//    spark.getShipperBrief    | spark.runShipperBrief
//    spark.getDispatcherBrief | spark.runDispatcherBrief
//    spark.getCatalystBrief   | spark.runCatalystBrief
//
//  Each card opens a SparkBriefDetailSheet on tap so the role can
//  drill into the structured findings (rate confirmation drafts /
//  HoS-aware assignments / settlement reconciliation queue).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Role

enum SparkRole: String, Codable, Hashable {
    case shipper, dispatcher, catalyst

    var eyebrow: String {
        switch self {
        case .shipper:    return "ESANG · SHIPPER BRIEF"
        case .dispatcher: return "ESANG · DISPATCH BRIEF"
        case .catalyst:   return "ESANG · CATALYST BRIEF"
        }
    }

    var sfSymbol: String {
        switch self {
        case .shipper:    return "shippingbox.fill"
        case .dispatcher: return "point.3.connected.trianglepath.dotted"
        case .catalyst:   return "chart.line.uptrend.xyaxis"
        }
    }

    /// Server tRPC path for the "read latest" query.
    var getPath: String {
        switch self {
        case .shipper:    return "spark.getShipperBrief"
        case .dispatcher: return "spark.getDispatcherBrief"
        case .catalyst:   return "spark.getCatalystBrief"
        }
    }

    /// Server tRPC path for the "regenerate now" mutation.
    var runPath: String {
        switch self {
        case .shipper:    return "spark.runShipperBrief"
        case .dispatcher: return "spark.runDispatcherBrief"
        case .catalyst:   return "spark.runCatalystBrief"
        }
    }
}

// MARK: - Wire models

/// Shared shape returned by `spark.{run,get}*Brief`. Every role
/// includes the same top-line trio (role / headline / sampledAt)
/// plus role-specific arrays. The arrays are intentionally untyped
/// here — the detail sheet decodes them lazily, so we don't have
/// to lockstep the iOS shape with three separate server schemas.
struct SparkBriefPayload: Decodable, Hashable {
    let role: String
    let headline: String?
    let sampledAt: String?

    // Role-specific buckets — all optional, only the matching role
    // populates its trio. Decoded as raw JSON arrays we count for
    // chip labels.
    let rateConfirmationDrafts:   [SparkAnyItem]?  // shipper
    let reconciliationHints:      [SparkAnyItem]?  // shipper
    let morningPriorities:        [SparkAnyItem]?  // shipper

    let assignments:              [SparkAnyItem]?  // dispatcher
    let scorecards:               [SparkAnyItem]?  // dispatcher + catalyst
    let exceptionQueue:           [SparkAnyItem]?  // dispatcher

    let settlementReconciliation: [SparkAnyItem]?  // catalyst
    let factoringDecisions:       [SparkAnyItem]?  // catalyst
}

/// Opaque item used purely for counting in chips. We don't model
/// the per-row schema here — the detail sheet renders them via
/// JSON-string fallback if no typed view exists. This decouples
/// iOS releases from per-role server schema tweaks.
struct SparkAnyItem: Decodable, Hashable {
    private let raw: String
    init(from decoder: Decoder) throws {
        // Decode anything to a normalized JSON string so SwiftUI
        // can render unknown shapes without crashing.
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { raw = str }
        else if let n = try? container.decode(Double.self) { raw = String(n) }
        else if let dict = try? container.decode([String: SparkAnyValue].self) {
            raw = SparkAnyItem.encodeDictionary(dict)
        } else {
            raw = "{}"
        }
    }
    private static func encodeDictionary(_ d: [String: SparkAnyValue]) -> String {
        let pairs = d.map { "\"\($0.key)\":\($0.value.asJSON())" }.sorted().joined(separator: ",")
        return "{\(pairs)}"
    }
    var jsonString: String { raw }
}

/// Lazy any-value used only inside SparkAnyItem.
private enum SparkAnyValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case nested(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let b = try? c.decode(Bool.self)   { self = .bool(b); return }
        // Fallback: stringify any deeper structure.
        self = .nested("…")
    }
    func asJSON() -> String {
        switch self {
        case .string(let s): return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
        case .number(let n): return String(n)
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return "null"
        case .nested(let p): return "\"\(p)\""
        }
    }
}

/// `spark.get*Brief` query envelope.
struct SparkGetBriefResponse: Decodable {
    let brief: SparkBriefPayload?
    let sampledAt: String?
    let source: String?
}

/// `spark.run*Brief` mutation envelope.
struct SparkRunBriefResponse: Decodable {
    let ok: Bool
    let brief: SparkBriefPayload?
    let auditId: Int?
    let reason: String?
}

// MARK: - Store

/// One ObservableObject per role. The Home screen owns it via
/// @StateObject. `autoLoad()` pulls the cached brief on appear and
/// self-generates one if none exists; the subtle "Refresh" affordance
/// re-pulls on demand while the existing brief stays on screen (no
/// spinner blank-out).
@MainActor
final class SparkBriefStore: ObservableObject {
    @Published var brief: SparkBriefPayload?
    @Published var sampledAt: String?
    @Published var loading: Bool = false
    @Published var running: Bool = false
    @Published var lastError: String?

    /// Guards the auto-load so it fires exactly once per store
    /// lifetime — `.task` re-runs on view identity changes, so this
    /// debounces against re-fetching on every redraw / tab switch.
    private var didAutoLoad: Bool = false

    let role: SparkRole
    init(role: SparkRole) { self.role = role }

    /// "Sampled X hours ago." — used in the eyebrow.
    var sampledAgeHuman: String? {
        guard let iso = sampledAt,
              let date = SparkBriefStore.iso.date(from: iso) else { return nil }
        let mins = max(1, Int(Date().timeIntervalSince(date) / 60))
        if mins < 60   { return "\(mins) min ago" }
        let hrs = mins / 60
        if hrs < 48    { return "\(hrs)h ago" }
        let days = hrs / 24
        return "\(days)d ago"
    }
    /// Stale when older than 18h — Spark cron runs ~03:00 UTC so
    /// anything older than the morning means the cron didn't fire for
    /// some reason. Retained for diagnostics; the card now auto-loads
    /// and self-refreshes rather than gating behind a manual run.
    var isStale: Bool {
        guard let iso = sampledAt,
              let date = SparkBriefStore.iso.date(from: iso) else { return true }
        return Date().timeIntervalSince(date) > (18 * 3600)
    }

    /// Auto-load entry point driven by the card's `.task`. Fetches the
    /// cached brief once on appear and — if none exists yet — silently
    /// generates one so the role never has to press a "Run now" button.
    /// Debounced via `didAutoLoad` so view-identity churn / redraws
    /// don't re-trigger the fanout.
    func autoLoad() async {
        guard !didAutoLoad else { return }
        didAutoLoad = true
        await refresh()
        if brief == nil && !running {
            await runNow()
        }
    }

    /// Fetch the current cached brief.
    func refresh() async {
        loading = true; defer { loading = false }
        do {
            let resp: SparkGetBriefResponse = try await EusoTripAPI.shared
                .spark.getLatest(role: role)
            self.brief = resp.brief
            self.sampledAt = resp.sampledAt ?? resp.brief?.sampledAt
            self.lastError = nil
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Fire the run mutation. Server fanout takes ~6-8s; we keep
    /// the existing brief on screen while running so the UI never
    /// flashes empty.
    func runNow() async {
        running = true; defer { running = false }
        do {
            let resp: SparkRunBriefResponse = try await EusoTripAPI.shared
                .spark.run(role: role)
            if let b = resp.brief {
                self.brief = b
                self.sampledAt = b.sampledAt
            } else if !resp.ok {
                self.lastError = resp.reason ?? "Spark refused to run."
            }
        } catch {
            self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Card

struct SparkBriefCard: View {
    let role: SparkRole
    @StateObject private var store: SparkBriefStore
    @State private var showDetail: Bool = false

    init(role: SparkRole) {
        self.role = role
        _store = StateObject(wrappedValue: SparkBriefStore(role: role))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Eyebrow
            HStack(spacing: 8) {
                Image(systemName: role.sfSymbol)
                    .font(.caption2.weight(.bold))
                Text(role.eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                Spacer()
                if let age = store.sampledAgeHuman {
                    Text(age)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.secondary)

            // Headline
            if let head = store.brief?.headline, !head.isEmpty {
                Text(head)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            } else if store.loading || store.running {
                ProgressView().controlSize(.small)
            } else {
                Text("No ESANG brief yet — refresh to generate one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Chips + Run button
            if store.brief != nil {
                ChipRow(role: role, brief: store.brief)
            }

            HStack(spacing: 12) {
                if store.brief != nil {
                    Button {
                        showDetail = true
                    } label: {
                        Label("Open Brief", systemImage: "doc.text.magnifyingglass")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Spacer()
                // Subtle refresh only — the brief already auto-loads on
                // appear (and self-generates if none exists), so this is
                // never a required first tap. It re-pulls on demand.
                Button {
                    Task { await store.runNow() }
                } label: {
                    if store.running {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .controlSize(.small)
                .disabled(store.running)
                .accessibilityLabel("Refresh ESANG brief")
            }

            if let err = store.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(Color.red)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .task { await store.autoLoad() }
        .sheet(isPresented: $showDetail) {
            SparkBriefDetailSheet(role: role, brief: store.brief)
        }
    }
}

// MARK: - Chip row

private struct ChipRow: View {
    let role: SparkRole
    let brief: SparkBriefPayload?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips, id: \.label) { chip in
                Label(chip.label, systemImage: chip.symbol)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
            }
        }
    }

    private var chips: [Chip] {
        guard let b = brief else { return [] }
        switch role {
        case .shipper:
            return [
                .init(label: "\(b.rateConfirmationDrafts?.count ?? 0) rate confirms", symbol: "doc.text"),
                .init(label: "\(b.reconciliationHints?.count ?? 0) reconcile",       symbol: "arrow.left.arrow.right"),
                .init(label: "\(b.morningPriorities?.count ?? 0) priorities",       symbol: "flag"),
            ]
        case .dispatcher:
            return [
                .init(label: "\(b.assignments?.count ?? 0) assignments",  symbol: "person.crop.circle.badge.checkmark"),
                .init(label: "\(b.scorecards?.count ?? 0) scorecards",   symbol: "chart.bar"),
                .init(label: "\(b.exceptionQueue?.count ?? 0) exceptions", symbol: "exclamationmark.triangle"),
            ]
        case .catalyst:
            return [
                .init(label: "\(b.settlementReconciliation?.count ?? 0) settle",  symbol: "creditcard"),
                .init(label: "\(b.factoringDecisions?.count ?? 0) factoring",     symbol: "banknote"),
                .init(label: "\(b.scorecards?.count ?? 0) scorecards",           symbol: "chart.bar"),
            ]
        }
    }

    private struct Chip { let label: String; let symbol: String }
}

// MARK: - Detail sheet

struct SparkBriefDetailSheet: View {
    let role: SparkRole
    let brief: SparkBriefPayload?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let head = brief?.headline {
                        Text(head)
                            .font(.title3.weight(.semibold))
                    }

                    switch role {
                    case .shipper:
                        Section(header: "Rate Confirmation Drafts", items: brief?.rateConfirmationDrafts)
                        Section(header: "Reconciliation Hints",     items: brief?.reconciliationHints)
                        Section(header: "Morning Priorities",       items: brief?.morningPriorities)
                    case .dispatcher:
                        Section(header: "Assignments",      items: brief?.assignments)
                        Section(header: "Driver Scorecards", items: brief?.scorecards)
                        Section(header: "Exception Queue",  items: brief?.exceptionQueue)
                    case .catalyst:
                        Section(header: "Settlement Reconciliation", items: brief?.settlementReconciliation)
                        Section(header: "Factoring Decisions",       items: brief?.factoringDecisions)
                        Section(header: "Scorecards",                items: brief?.scorecards)
                    }
                }
                .padding(16)
            }
            .navigationTitle("ESANG Brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private struct Section: View {
        let header: String
        let items: [SparkAnyItem]?
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(header.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                if let xs = items, !xs.isEmpty {
                    ForEach(Array(xs.enumerated()), id: \.offset) { _, item in
                        Text(item.jsonString)
                            .font(.footnote.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                } else {
                    Text("No items.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Shipper · Dark") {
    SparkBriefCard(role: .shipper)
        .padding(20)
        .preferredColorScheme(.dark)
}

#Preview("Dispatcher · Light") {
    SparkBriefCard(role: .dispatcher)
        .padding(20)
        .preferredColorScheme(.light)
}

#Preview("Catalyst · Dark") {
    SparkBriefCard(role: .catalyst)
        .padding(20)
        .preferredColorScheme(.dark)
}
