//
//  226_ShipperDocumentCenter.swift
//  EusoTrip 2027 UI — Shipper · Document Center (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/226_ShipperDocumentCenter.swift. Persona: Diego
//  Usoro / Eusorone Technologies (companyId 1) per §11. Recent doc
//  rows surface the §11.2 MATRIX-50 audit-trail hex tails when
//  present (LD-260427-A38FB12C7E Houston→Dallas tanker BOL,
//  Eusotrans LLC USDOT 3 194 882 COI, LD-260427-7C3A09F18B LA→Phoenix
//  reefer rate-con).
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · DOCUMENT CENTER / "{N} DOCS · {C} CATEGORIES"
//    2. Title block      Documents (34pt) / "Eusorone Technologies · master library by category"
//    3. IridescentHairline
//    4. KPI summary      3-cell · TOTAL DOCS (gradient) · EXPIRES SOON (warn) · STORAGE
//    5. Search row       "Search by load ID, partner, or type…" + gradient + capsule (upload)
//    6. Filter chips     All / BOL / COI / Rate Con / Tax with derived counts
//    7. RECENT section   eyebrow + 3-row recent card (last 3 by uploadedAt)
//    8. BY CATEGORY      eyebrow + 2x2 status-rimmed tile grid (gradient/warn/success/info)
//    9. Retention footer
//
//  Real wiring preserved: `documents.getAll(search:category:)` +
//  `documents.getStats()` + `documents.getCategories()` +
//  `documents.delete(id:)` via `ShipperDocumentCenterStore`. Tap-row
//  fires `MeAction.fire("shipper.document.preview")` for the
//  Continuity hand-off to the web PDF viewer.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2139 — No `isFavorite` flag on Document. Favorite star
//                paints conditionally for COI / insurance / contract
//                rows as a pinning proxy until backend adds the flag.
//    EUSO-2140 — `Document` envelope ships `size: Int` but no
//                version, expirationDate, or last-modified-by. Meta
//                line surfaces only size + uploadedAt; expiry copy
//                is inferred from `status == "expiring"`.
//    EUSO-2141 — No storage-usage aggregate on `documents.getStats`.
//                STORAGE KPI cell paints "—" placeholder until
//                backend ships `storageBytes` + `planUsedPct`.
//
//  Doctrine refs: §2 ME-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §11 / §11.2
//  Diego canon + audit-trail; §15.2 status-rimmed category tiles;
//  §16 KPI summary card; §17.2 download-pill grammar; §19.2 file-
//  scoped paint extensions; §20.4 no dead buttons; §22.2 textTertiary
//  informational counter.
//

import SwiftUI

// MARK: - Filter (wireframe canon)

private enum DocFilter: String, CaseIterable, Identifiable {
    case all
    case bol
    case coi
    case rateCon
    case tax

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:     return "All"
        case .bol:     return "BOL"
        case .coi:     return "COI"
        case .rateCon: return "Rate Con"
        case .tax:     return "Tax"
        }
    }

    /// Server-side category id (or nil for All). Server emits free-form
    /// category names so we match keywords client-side as well.
    var serverCategory: String? { nil }

    var matchKeywords: [String] {
        switch self {
        case .all:     return []
        case .bol:     return ["bol", "pod", "shipping"]
        case .coi:     return ["coi", "insurance", "liability"]
        case .rateCon: return ["rate_con", "rate", "rc", "rate confirmation"]
        case .tax:     return ["tax", "w9", "1099"]
        }
    }
}

// MARK: - Status helpers

private struct DocumentStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String) -> DocumentStatusStyle {
        switch raw.lowercased() {
        case "active":     return .init(label: "Active",   color: Brand.success)
        case "valid":      return .init(label: "Valid",    color: Brand.success)
        case "expiring":   return .init(label: "Expiring", color: Brand.warning)
        case "expired":    return .init(label: "Expired",  color: Brand.danger)
        case "pending":    return .init(label: "Pending",  color: Brand.info)
        case "rejected":   return .init(label: "Rejected", color: Brand.danger)
        default:           return .init(label: raw.capitalized, color: .gray)
        }
    }
}

// MARK: - Store (preserved + extended)

@MainActor
final class ShipperDocumentCenterStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var search: String = ""
    @Published var filter: DocFilter = .all {
        didSet {
            if oldValue != filter { Task { await load() } }
        }
    }
    @Published private(set) var documents: [DocumentsAPI.Document] = []
    @Published private(set) var stats: DocumentsAPI.Stats? = nil
    @Published private(set) var categories: [DocumentsAPI.Category] = []
    @Published private(set) var deleting: Set<String> = []

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        async let docs = api.documents.getAll(search: search.isEmpty ? nil : search,
                                              category: nil)
        async let stats: DocumentsAPI.Stats? = (try? await api.documents.getStats()) ?? nil
        async let cats: [DocumentsAPI.Category] = (try? await api.documents.getCategories()) ?? []
        do {
            self.documents  = try await docs
            self.stats      = await stats
            self.categories = await cats
            self.phase      = .loaded
        } catch {
            self.phase = .error("Couldn't load documents.")
        }
    }

    func filtered() -> [DocumentsAPI.Document] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let searched: [DocumentsAPI.Document]
        if q.isEmpty {
            searched = documents
        } else {
            searched = documents.filter { d in
                d.name.lowercased().contains(q) || d.category.lowercased().contains(q)
            }
        }
        guard !filter.matchKeywords.isEmpty else { return searched }
        return searched.filter { d in
            let cat = d.category.lowercased()
            let name = d.name.lowercased()
            return filter.matchKeywords.contains { k in
                cat.contains(k) || name.contains(k)
            }
        }
    }

    func count(for filter: DocFilter) -> Int {
        if filter == .all { return documents.count }
        return documents.filter { d in
            let cat = d.category.lowercased()
            let name = d.name.lowercased()
            return filter.matchKeywords.contains { k in
                cat.contains(k) || name.contains(k)
            }
        }.count
    }

    func delete(id: String) async {
        deleting.insert(id)
        defer { deleting.remove(id) }
        _ = try? await api.documents.delete(id: id)
        await load()
    }
}

// MARK: - Screen root

struct ShipperDocumentCenter: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperDocumentCenterStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · DOCUMENT CENTER")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s5)
    }

    private var counterEyebrow: String {
        let total = store.stats?.total ?? store.documents.count
        let cats = store.categories.count
        return "\(total) DOCS · \(cats) CATEGORIES"
    }

    private var counterAccessibility: String {
        let total = store.stats?.total ?? store.documents.count
        return "\(total) total documents in the master library"
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Documents")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · master library by category")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 92)
                }
            }
            .padding(.horizontal, Space.s5)
        case .error(let m):
            errorCard(m)
                .padding(.horizontal, Space.s5)
        case .loaded:
            VStack(alignment: .leading, spacing: 0) {
                kpiSummaryStrip
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                searchRow
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)

                chipRow
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                let filtered = store.filtered()
                let recent = recentRows(filtered)

                if !recent.isEmpty {
                    sectionLabel("RECENT · LAST UPLOADS · \(recent.count) OF \(filtered.count)")
                        .padding(.top, Space.s5)
                    recentCard(recent)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                }

                if !store.categories.isEmpty {
                    sectionLabel("BY CATEGORY · \(store.categories.count) LIBRARIES · STATUS-RIMMED")
                        .padding(.top, Space.s5)
                    categoryGrid
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                }

                if filtered.isEmpty && recent.isEmpty {
                    emptyCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)
                }

                retentionFooter
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
            }
        }
    }

    private func recentRows(_ docs: [DocumentsAPI.Document]) -> [DocumentsAPI.Document] {
        Array(docs.sorted(by: { $0.uploadedAt > $1.uploadedAt }).prefix(3))
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }

    // MARK: KPI summary strip (3-cell · TOTAL DOCS / EXPIRES SOON / STORAGE)

    private var kpiSummaryStrip: some View {
        HStack(spacing: 0) {
            kpiCell(label: "TOTAL DOCS",
                    value: "\(store.stats?.total ?? store.documents.count)",
                    valueStyle: .gradient,
                    sub: nil)
            verticalSeparator
            kpiCell(label: "EXPIRES SOON",
                    value: "\(store.stats?.expiring ?? 0)",
                    valueStyle: (store.stats?.expiring ?? 0) > 0 ? .warn : .neutral,
                    sub: (store.stats?.expiring ?? 0) > 0 ? "in 30d" : "all clean")
            verticalSeparator
            // EUSO-2141 — storage aggregate not on API.
            kpiCell(label: "STORAGE",
                    value: "—",
                    valueStyle: .neutral,
                    sub: "plan pending")
        }
        .frame(minHeight: 72)
        .padding(.vertical, Space.s2)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 36)
    }

    private enum KpiValueStyle { case gradient, warn, neutral }

    @ViewBuilder
    private func kpiCell(label: String, value: String, valueStyle: KpiValueStyle, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .warn:     Text(value).foregroundStyle(Brand.warning)
                    case .neutral:  Text(value).foregroundStyle(palette.textPrimary)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                if let sub {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4)
    }

    // MARK: Search row

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            TextField("Search by load ID, partner, or type…", text: $store.search)
                .textFieldStyle(.plain)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { Task { await store.load() } }
            if !store.search.isEmpty {
                Button {
                    store.search = ""
                    Task { await store.load() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            // §17.2 trailing gradient `+` capsule for upload (no dead buttons).
            Button(action: tapUpload) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Upload document")
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func tapUpload() {
        MeAction.fire("shipper.document.upload", userInfo: nil)
        NotificationCenter.default.post(
            name: .eusoShipperDocumentUpload,
            object: nil,
            userInfo: [
                "source": "226_ShipperDocumentCenter",
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Chip row

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DocFilter.allCases) { f in
                    chip(f, count: store.count(for: f))
                }
                Color.clear.frame(width: 16, height: 1)
            }
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [palette.bgPage.opacity(0), palette.bgPage],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }

    private func chip(_ f: DocFilter, count: Int) -> some View {
        let isActive = (store.filter == f)
        let label = "\(f.label) · \(count)"
        return Button(action: { tapFilter(f) }) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.white : palette.textPrimary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 7)
                .background {
                    if isActive {
                        Capsule().fill(LinearGradient.primary)
                    } else {
                        Capsule().fill(palette.bgCard)
                    }
                }
                .overlay {
                    if !isActive {
                        Capsule().strokeBorder(palette.borderFaint)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.label) filter")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func tapFilter(_ f: DocFilter) {
        store.filter = f
        NotificationCenter.default.post(
            name: .eusoShipperDocumentFilter,
            object: nil,
            userInfo: [
                "source": "226_ShipperDocumentCenter",
                "filter": f.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Recent card

    private func recentCard(_ rows: [DocumentsAPI.Document]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, doc in
                recentRow(doc)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                if idx < rows.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func recentRow(_ d: DocumentsAPI.Document) -> some View {
        let style = DocumentStatusStyle.from(d.status)
        let isFav = isFavoriteHeuristic(d)
        return Button(action: { tapRow(d) }) {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(palette.bgCardSoft)
                    Image(systemName: categoryGlyph(d.category))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(palette.borderFaint)
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(d.name)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        if isFav {
                            DocStarShape().fill(Brand.hazmat).frame(width: 10, height: 10)
                        }
                        statusPill(style.label, color: style.color)
                    }
                    Text(metaSubtitle(d))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: { tapDownload(d) }) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Download \(d.name)")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DocRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(d.name), \(style.label), \(d.category)")
    }

    private func metaSubtitle(_ d: DocumentsAPI.Document) -> String {
        var parts: [String] = []
        parts.append(d.category.replacingOccurrences(of: "_", with: " ").capitalized)
        parts.append(formatBytes(d.size))
        if !d.uploadedAt.isEmpty {
            parts.append(relativeShort(d.uploadedAt))
        }
        if d.status.lowercased() == "expiring" {
            parts.append("expiring")
        }
        return parts.joined(separator: " · ")
    }

    private func formatBytes(_ b: Int) -> String {
        if b >= 1_048_576 {
            return String(format: "%.1f MB", Double(b) / 1_048_576.0)
        }
        if b >= 1024 {
            return String(format: "%.0f KB", Double(b) / 1024.0)
        }
        return "\(b) B"
    }

    private func relativeShort(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s/60))m ago" }
        if s < 86400 { return "\(Int(s/3600))h ago" }
        return "\(Int(s/86400))d ago"
    }

    private func isFavoriteHeuristic(_ d: DocumentsAPI.Document) -> Bool {
        // EUSO-2139 — no isFavorite flag on envelope. Pin COI / contract /
        // master-agreement docs as a relationship-grade-core heuristic.
        let cat = d.category.lowercased()
        let name = d.name.lowercased()
        return cat.contains("insurance") || cat.contains("coi")
            || cat.contains("contract") || cat.contains("master")
            || name.contains("coi") || name.contains("master")
    }

    private func categoryGlyph(_ c: String) -> String {
        switch c.lowercased() {
        case let s where s.contains("permit"):    return "lock.shield.fill"
        case let s where s.contains("insurance"): return "checkmark.shield.fill"
        case let s where s.contains("compliance"):return "checkmark.seal.fill"
        case let s where s.contains("contract"):  return "doc.text.fill"
        case let s where s.contains("invoice"):   return "creditcard.fill"
        case let s where s.contains("bol"):       return "shippingbox.fill"
        case let s where s.contains("ticket"):    return "ticket.fill"
        case let s where s.contains("rate"):      return "doc.richtext.fill"
        case let s where s.contains("tax") || s.contains("w9"): return "dollarsign.square.fill"
        default:                                   return "doc.fill"
        }
    }

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    // MARK: Category grid (2x2 status-rimmed)

    private var categoryGrid: some View {
        let cats = Array(store.categories.prefix(4))
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s2),
                GridItem(.flexible(), spacing: Space.s2),
            ],
            spacing: Space.s2
        ) {
            ForEach(Array(cats.enumerated()), id: \.element.id) { idx, c in
                categoryTile(c, family: tileFamily(for: idx, category: c))
            }
        }
    }

    private enum TileFamily { case gradient, warn, success, info }

    private func tileFamily(for index: Int, category: DocumentsAPI.Category) -> TileFamily {
        // First tile is the gradient anchor (highest count typically).
        // Insurance/COI categories paint warn (renewal-driven attention).
        // Contracts/agreements paint success. Everything else paints info.
        let n = category.name.lowercased()
        if index == 0 { return .gradient }
        if n.contains("insurance") || n.contains("coi") || n.contains("permit") { return .warn }
        if n.contains("contract") || n.contains("agreement") || n.contains("compliance") { return .success }
        return .info
    }

    @ViewBuilder
    private func categoryTile(_ c: DocumentsAPI.Category, family: TileFamily) -> some View {
        Button(action: { tapCategory(c) }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.name.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(eyebrowColor(for: family))
                Text(c.name.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(c.count)")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(valuePaint(for: family))
                    Text("docs")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(rimPaint(for: family), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(DocRowStyle())
    }

    private func eyebrowColor(for family: TileFamily) -> Color {
        switch family {
        case .gradient: return palette.textSecondary
        case .warn:     return Brand.warning
        case .success:  return Brand.success
        case .info:     return Brand.info
        }
    }

    private func rimPaint(for family: TileFamily) -> AnyShapeStyle {
        switch family {
        case .gradient: return AnyShapeStyle(LinearGradient.diagonal.opacity(0.55))
        case .warn:     return AnyShapeStyle(Brand.warning.opacity(0.55))
        case .success:  return AnyShapeStyle(Brand.success.opacity(0.55))
        case .info:     return AnyShapeStyle(Brand.info.opacity(0.55))
        }
    }

    private func valuePaint(for family: TileFamily) -> AnyShapeStyle {
        switch family {
        case .gradient: return AnyShapeStyle(LinearGradient.diagonal)
        case .warn:     return AnyShapeStyle(Brand.warning)
        case .success:  return AnyShapeStyle(Brand.success)
        case .info:     return AnyShapeStyle(Brand.info)
        }
    }

    // MARK: Retention footer

    private var retentionFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RETENTION")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("S3-versioned · 7-year retention · `documents.delete` is soft-archive (recoverable for 30 days)")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Notification posts (§20.4)

    private func tapRow(_ d: DocumentsAPI.Document) {
        MeAction.fire("shipper.document.preview", userInfo: ["documentId": d.id])
        NotificationCenter.default.post(
            name: .eusoShipperDocumentRow,
            object: nil,
            userInfo: [
                "source": "226_ShipperDocumentCenter",
                "documentId": d.id,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapDownload(_ d: DocumentsAPI.Document) {
        NotificationCenter.default.post(
            name: .eusoShipperDocumentDownload,
            object: nil,
            userInfo: [
                "source": "226_ShipperDocumentCenter",
                "documentId": d.id,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapCategory(_ c: DocumentsAPI.Category) {
        NotificationCenter.default.post(
            name: .eusoShipperDocumentCategoryTile,
            object: nil,
            userInfo: [
                "source": "226_ShipperDocumentCenter",
                "categoryId": c.id,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Empty / error

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.fill")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No documents yet")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Tap the gradient + capsule above to add your first BOL, insurance cert, or W9.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.info)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Press feedback

private struct DocRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - File-scoped Star (§19.2)

private struct DocStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [CGPoint] = [
            CGPoint(x: 5,   y: 0),
            CGPoint(x: 6.2, y: 3.6),
            CGPoint(x: 10,  y: 3.6),
            CGPoint(x: 7,   y: 5.8),
            CGPoint(x: 8.2, y: 9.4),
            CGPoint(x: 5,   y: 7.2),
            CGPoint(x: 1.8, y: 9.4),
            CGPoint(x: 3,   y: 5.8),
            CGPoint(x: 0,   y: 3.6),
            CGPoint(x: 3.8, y: 3.6),
        ]
        let sx = rect.width / 10.0
        let sy = rect.height / 9.4
        var path = Path()
        for (i, p) in pts.enumerated() {
            let x = rect.minX + p.x * sx
            let y = rect.minY + p.y * sy
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Filter chip tap (All / BOL / COI / Rate Con / Tax).
    static let eusoShipperDocumentFilter       = Notification.Name("eusoShipperDocumentFilter")
    /// Recent row tap — Continuity preview hand-off.
    static let eusoShipperDocumentRow          = Notification.Name("eusoShipperDocumentRow")
    /// Per-row download chevron tap.
    static let eusoShipperDocumentDownload     = Notification.Name("eusoShipperDocumentDownload")
    /// Category tile tap.
    static let eusoShipperDocumentCategoryTile = Notification.Name("eusoShipperDocumentCategoryTile")
    /// Search-row trailing `+` upload capsule tap.
    static let eusoShipperDocumentUpload       = Notification.Name("eusoShipperDocumentUpload")
}

// MARK: - Previews

#Preview("226 · Documents · Dark") {
    ShipperDocumentCenter()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("226 · Documents · Light") {
    ShipperDocumentCenter()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
