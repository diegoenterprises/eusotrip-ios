//
//  217_ShipperContracts.swift
//  EusoTrip 2027 UI — brick 217 (shipper · contracts / agreements)
//
//  Volume-commitment & agreement lifecycle viewer. Mirrors web
//  `/shipper/contracts` (`ShipperContracts.tsx`) backed by the
//  `contractsRouter` server module. Same design language as 056
//  Driver Profile + 202 Shipper Profile + 215 Shipper RFP — gradient
//  eyebrow + tier hero + KPI strip + status-pilled list rows + tap
//  detail sheet.
//
//  Cohort B day-1 — fully dynamic. No fixtures.
//
//    • Stats hero        → `contracts.getStats`
//    • List              → `contracts.getAll(search?, status?)`
//    • Detail (tap row)  → `contracts.getById(id)`
//
//  Authoring (create / submit / approve / renew / terminate) is
//  intentionally NOT wired on this brick — the form work is heavy
//  enough to deserve its own brick (217b ShipperContractsCreate).
//  The list + detail viewer is the high-leverage shipper read.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Filter chips

private enum ContractFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case expiring
    case expired
    case pending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return "All"
        case .active:   return "Active"
        case .expiring: return "Expiring"
        case .expired:  return "Expired"
        case .pending:  return "Pending"
        }
    }

    var icon: String {
        switch self {
        case .all:      return "square.grid.2x2"
        case .active:   return "checkmark.seal.fill"
        case .expiring: return "clock.badge.exclamationmark.fill"
        case .expired:  return "xmark.seal.fill"
        case .pending:  return "hourglass"
        }
    }

    /// Server-side status string (or nil for "all"). The server
    /// accepts the lower-cased status enum.
    var serverStatus: String? {
        switch self {
        case .all:      return nil
        case .active:   return "active"
        case .expiring: return "active"  // expiring is a derived view of active
        case .expired:  return "expired"
        case .pending:  return "pending_review"
        }
    }
}

// MARK: - Store

@MainActor
final class ShipperContractsStore: ObservableObject {
    enum LoadState {
        case loading
        case empty
        case error(String)
        case loaded(stats: ContractsAPI.Stats, rows: [ContractsAPI.ContractRow])
    }

    @Published private(set) var state: LoadState = .loading
    @Published var filter: ContractFilter = .all {
        didSet {
            if oldValue != filter { Task { await refresh() } }
        }
    }
    @Published var searchTerm: String = ""

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let s = api.contracts.getStats()
            async let r = api.contracts.getAll(
                search: searchTerm.isEmpty ? nil : searchTerm,
                status: filter.serverStatus
            )
            let (stats, rows) = try await (s, r)
            // Apply the "expiring" sub-filter client-side since the
            // server returns all "active" contracts for that bucket.
            let final: [ContractsAPI.ContractRow] = {
                guard filter == .expiring else { return rows }
                let now = Date()
                let cutoff = now.addingTimeInterval(30 * 86400)
                return rows.filter { row in
                    guard let s = row.endDate, !s.isEmpty,
                          let d = parseDateYMD(s) else { return false }
                    return d >= now && d <= cutoff
                }
            }()
            if final.isEmpty && stats.total == 0 {
                state = .empty
            } else {
                state = .loaded(stats: stats, rows: final)
            }
        } catch {
            state = .error("Couldn't reach contracts service.")
        }
    }
}

private func parseDateYMD(_ s: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: s)
}

// MARK: - Screen root

struct ShipperContracts: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ShipperContractsStore()
    @State private var selectedId: String?
    @State private var detail: ContractsAPI.ContractDetail?
    @State private var detailLoading: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: Binding(
            get: { selectedId.map { IdentifiedContractId(id: $0) } },
            set: { newValue in
                selectedId = newValue?.id
                if newValue == nil { detail = nil }
            }
        )) { ident in
            ContractDetailSheet(
                contractId: ident.id,
                detail: $detail,
                loading: $detailLoading,
                palette: palette
            )
            .presentationDragIndicator(.visible)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: store.filter
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · CONTRACTS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Volume commitments")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Master agreements, lane contracts, RFP follow-ons — every paper an awarded carrier signs to lock you in.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 84)
                }
            }
        case .empty:
            emptyHero
        case .error(let msg):
            errorBanner(msg)
        case .loaded(let stats, let rows):
            statsHero(stats)
            filterChipRow
            if rows.isEmpty {
                noFilteredResults
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        contractRow(row)
                    }
                }
            }
        }
    }

    // MARK: Stats hero

    private func statsHero(_ s: ContractsAPI.Stats) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("PORTFOLIO")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(formatMoney(s.totalValue))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(LinearGradient.diagonal.opacity(0.18)))
            }
            HStack(spacing: Space.s2) {
                statTile(value: "\(s.total)",     label: "TOTAL",     accent: nil)
                statTile(value: "\(s.active)",    label: "ACTIVE",    accent: Brand.success)
                statTile(value: "\(s.expiring)",  label: "EXPIRING",  accent: Brand.warning)
                statTile(value: "\(s.expired)",   label: "EXPIRED",   accent: Brand.danger)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func statTile(value: String, label: String, accent: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(accent ?? palette.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Filter chips

    private var filterChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ContractFilter.allCases) { f in
                    filterChip(f)
                }
            }
        }
    }

    private func filterChip(_ f: ContractFilter) -> some View {
        let active = (store.filter == f)
        return Button {
            store.filter = f
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        } label: {
            HStack(spacing: 4) {
                Image(systemName: f.icon)
                    .font(.system(size: 10, weight: .heavy))
                Text(f.label)
                    .font(.system(size: 11, weight: .heavy))
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
            .background(
                Capsule().fill(active
                               ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                               : AnyShapeStyle(palette.bgCard))
            )
            .overlay(
                Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Contract row

    private func contractRow(_ row: ContractsAPI.ContractRow) -> some View {
        let style = contractStatusStyle(row.status, palette: palette)
        return Button {
            selectedId = row.id
            Task {
                detailLoading = true
                detail = try? await EusoTripAPI.shared.contracts.getContract(id: row.id)
                detailLoading = false
            }
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(LinearGradient.diagonal.opacity(0.15))
                    Image(systemName: contractTypeIcon(row.type))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.number ?? "—")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        statusPill(style)
                    }
                    HStack(spacing: 6) {
                        if let t = row.type, !t.isEmpty {
                            Text(prettifyType(t))
                                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(palette.textTertiary)
                        }
                        if let end = row.endDate, !end.isEmpty {
                            Text("· EXPIRES \(end)")
                                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(expiryColor(end))
                        }
                    }
                    if let customer = row.customer, !customer.isEmpty {
                        Text(customer)
                            .font(EType.micro).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(row.value > 0 ? formatMoney(row.value) : "—")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(ContractRowStyle())
    }

    private func statusPill(_ s: ContractStatusStyle) -> some View {
        Text(s.label.uppercased())
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(s.color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(s.color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(s.color.opacity(0.4), lineWidth: 0.75))
    }

    private func contractTypeIcon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "lease":          return "key.fill"
        case "owner_op":       return "person.fill"
        case "shipper":        return "shippingbox.fill"
        case "broker_carrier": return "person.2.fill"
        case "service":        return "wrench.and.screwdriver.fill"
        default:                return "doc.text.fill"
        }
    }

    private func prettifyType(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func expiryColor(_ ymd: String) -> Color {
        guard let date = parseDateYMD(ymd) else { return palette.textTertiary }
        let now = Date()
        let daysLeft = Int(date.timeIntervalSince(now) / 86400)
        if daysLeft < 0       { return Brand.danger }
        if daysLeft <= 30     { return Brand.warning }
        return palette.textTertiary
    }

    // MARK: States

    private var emptyHero: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "doc.text")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No contracts yet")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text("Once an RFP is awarded, the resulting carrier contract lands here. You can also draft direct master agreements on web.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s4)
                .fixedSize(horizontal: false, vertical: true)
            Text("eusotrip.com/shipper/contracts")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s5)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var noFilteredResults: some View {
        Text("No contracts match this filter.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(palette.bgCard.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Contracts service offline")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func formatMoney(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "$%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "$%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0          { return "—" }
        return "$\(n)"
    }
}

// MARK: - Status style helper

private struct ContractStatusStyle {
    let label: String
    let color: Color
}

private func contractStatusStyle(_ status: String?, palette: Theme.Palette) -> ContractStatusStyle {
    switch (status ?? "").lowercased() {
    case "active":          return ContractStatusStyle(label: "Active",   color: Brand.success)
    case "draft":           return ContractStatusStyle(label: "Draft",    color: palette.textSecondary)
    case "pending_review":  return ContractStatusStyle(label: "Pending",  color: Brand.warning)
    case "approved":        return ContractStatusStyle(label: "Approved", color: Brand.info)
    case "expired":         return ContractStatusStyle(label: "Expired",  color: Brand.danger)
    case "terminated":      return ContractStatusStyle(label: "Terminated", color: Brand.danger)
    default:                 return ContractStatusStyle(label: status?.capitalized ?? "—", color: palette.textTertiary)
    }
}

// MARK: - Press feedback

private struct ContractRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Identifiable wrapper for sheet binding

private struct IdentifiedContractId: Identifiable {
    let id: String
}

// MARK: - Detail sheet

private struct ContractDetailSheet: View {
    let contractId: String
    @Binding var detail: ContractsAPI.ContractDetail?
    @Binding var loading: Bool
    let palette: Theme.Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if loading && detail == nil {
                    skeleton
                } else if let d = detail {
                    heroCard(d)
                    if let t = d.terms       { termsCard(t) }
                    if let p = d.pricing     { pricingCard(p) }
                    if let v = d.volume      { volumeCard(v) }
                    if let n = d.notes, !n.isEmpty { notesCard(n) }
                }
                Color.clear.frame(height: 48)
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
    }

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 80)
            }
        }
    }

    private func heroCard(_ d: ContractsAPI.ContractDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CONTRACT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            Text(d.contractNumber ?? "—")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: 6) {
                if let t = d.type, !t.isEmpty {
                    chip(label: t.replacingOccurrences(of: "_", with: " ").uppercased(),
                         color: Brand.info)
                }
                let style = contractStatusStyle(d.status, palette: palette)
                chip(label: style.label.uppercased(), color: style.color)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func chip(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.75))
    }

    private func termsCard(_ t: ContractsAPI.ContractDetail.Terms) -> some View {
        sectionCard(title: "TERMS") {
            VStack(spacing: 6) {
                kvRow("Effective", value: t.startDate?.isEmpty == false ? t.startDate! : "—")
                kvRow("Expires", value: t.endDate?.isEmpty == false ? t.endDate! : "—")
                kvRow("Auto-renew", value: t.autoRenew ? "Enabled" : "Disabled")
            }
        }
    }

    private func pricingCard(_ p: ContractsAPI.ContractDetail.Pricing) -> some View {
        sectionCard(title: "PRICING") {
            VStack(spacing: 6) {
                kvRow("Base rate", value: formatMoney(p.baseRate))
                kvRow("Rate type", value: p.rateType.isEmpty ? "—" : p.rateType.capitalized)
                kvRow("Fuel surcharge", value: p.fuelSurcharge.isEmpty ? "—" : p.fuelSurcharge.capitalized)
            }
        }
    }

    private func volumeCard(_ v: ContractsAPI.ContractDetail.Volume) -> some View {
        sectionCard(title: "VOLUME COMMITMENT") {
            VStack(spacing: 6) {
                kvRow("Commitment", value: v.commitment > 0 ? "\(v.commitment) loads" : "—")
                kvRow("Period", value: v.period.isEmpty ? "—" : v.period.capitalized)
            }
        }
    }

    private func notesCard(_ notes: String) -> some View {
        sectionCard(title: "NOTES") {
            Text(notes)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            content()
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func kvRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func formatMoney(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "$%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "$%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "$%.1fk", Double(n) / 1_000) }
        if n == 0          { return "—" }
        return "$\(n)"
    }
}

// MARK: - Previews

#Preview("217 · Shipper Contracts · Night") {
    ShipperContracts()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("217 · Shipper Contracts · Afternoon") {
    ShipperContracts()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
