//
//  224_ShipperPartnerDirectory.swift
//  EusoTrip 2027 UI — brick 224 (shipper · partner directory)
//
//  Catalyst rolodex. Mirrors the web `MyPartners.tsx` (`/partners`
//  page) — outbound + inbound partnerships, deduped, status-grouped,
//  with per-partner agreement-state enrichment.
//
//  Wires:
//    • `supplyChain.getMyPartners(status:toRole:)`
//    • Tap-row → `MeAction.fire("shipper.partner.detail", userInfo:
//      ["partnershipId":, "companyId":])` for the deep-link
//      Continuity hand-off (web partner-detail is heavyweight —
//      iOS surface stays list-first).
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperPartnerDirectoryStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded([SupplyChainAPI.Partner])
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var search: String = ""
    @Published var statusFilter: String? = nil

    static let statusFilters: [(String?, String)] = [
        (nil, "All"),
        ("active", "Active"),
        ("pending", "Pending"),
        ("declined", "Declined"),
        ("suspended", "Suspended"),
    ]

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let rows = try await api.supplyChain.getMyPartners(status: statusFilter)
            phase = .loaded(filtered(rows))
        } catch {
            phase = .error("Couldn't reach partner directory.")
        }
    }

    private func filtered(_ rows: [SupplyChainAPI.Partner]) -> [SupplyChainAPI.Partner] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return rows }
        return rows.filter { p in
            (p.companyName ?? "").lowercased().contains(q)
            || (p.companyDot ?? "").lowercased().contains(q)
            || (p.companyMc ?? "").lowercased().contains(q)
            || (p.companyState ?? "").lowercased().contains(q)
        }
    }
}

// MARK: - Brick

struct ShipperPartnerDirectory: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperPartnerDirectoryStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                statsHero
                searchAndFilter
                listSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.load() }
        .onChange(of: store.statusFilter) { _, _ in Task { await store.load() } }
        .refreshable { await store.load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.2.crop.square.stack").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · PARTNERS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Carrier rolodex").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("Catalysts you've onboarded · agreement state · MC/DOT lookup at a glance.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                MeAction.fire("shipper.partner.invite", userInfo: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.plus").font(.system(size: 11, weight: .heavy))
                    Text("Invite").font(.system(size: 11, weight: .heavy))
                }.foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }.padding(.top, 4)
    }

    private var statsHero: some View {
        let rows: [SupplyChainAPI.Partner] = {
            if case .loaded(let r) = store.phase { return r } else { return [] }
        }()
        let active = rows.filter { ($0.status ?? "").lowercased() == "active" }.count
        let pending = rows.filter { ($0.status ?? "").lowercased() == "pending" }.count
        let withAgreement = rows.filter { ($0.agreementStatus ?? "").lowercased() == "active" }.count
        return HStack(spacing: Space.s2) {
            statTile(label: "PARTNERS", value: "\(rows.count)", color: nil)
            statTile(label: "ACTIVE", value: "\(active)", color: Brand.success)
            statTile(label: "AGREEMENT", value: "\(withAgreement)", color: Brand.info)
            statTile(label: "PENDING", value: "\(pending)", color: Brand.warning)
        }
    }

    private func statTile(label: String, value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient.diagonal))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var searchAndFilter: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textTertiary)
                TextField("Search · name · MC# · DOT# · state", text: $store.search)
                    .textFieldStyle(.plain).font(EType.body).foregroundStyle(palette.textPrimary)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onChange(of: store.search) { _, _ in Task { await store.load() } }
                if !store.search.isEmpty {
                    Button { store.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                            .foregroundStyle(palette.textTertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ShipperPartnerDirectoryStore.statusFilters, id: \.1) { item in
                        chip(label: item.1, active: store.statusFilter == item.0) {
                            store.statusFilter = item.0
                        }
                    }
                }
            }
        }
    }

    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, Space.s3).padding(.vertical, 7)
                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                .background(Capsule().fill(active ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)) : AnyShapeStyle(palette.bgCard)))
                .overlay(Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var listSection: some View {
        switch store.phase {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Loading partners…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded(let rows):
            if rows.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        partnerRow(row)
                    }
                }
            }
        }
    }

    private func partnerRow(_ p: SupplyChainAPI.Partner) -> some View {
        let style = PartnerStatusStyle.from(p.status)
        return Button {
            MeAction.fire("shipper.partner.detail", userInfo: [
                "partnershipId": p.id,
                "companyId": p.partnerCompanyId ?? -1,
            ])
        } label: {
            HStack(alignment: .top, spacing: 10) {
                monogram(p.companyName ?? "?")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(p.companyName ?? "Unknown")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                        statusPill(style.label, color: style.color)
                        if let dir = p.direction, dir == "inbound" {
                            Image(systemName: "arrow.down.left").font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    HStack(spacing: 6) {
                        if let mc = p.companyMc, !mc.isEmpty {
                            miniPill("MC \(mc)")
                        }
                        if let dot = p.companyDot, !dot.isEmpty {
                            miniPill("DOT \(dot)")
                        }
                        if let st = p.companyState, !st.isEmpty {
                            miniPill(st.uppercased())
                        }
                    }
                    if let ag = p.agreementStatus, !ag.isEmpty {
                        Label(agreementLabel(ag), systemImage: agreementGlyph(ag))
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(agreementColor(ag))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func monogram(_ name: String) -> some View {
        let initials = name.split(separator: " ").compactMap { $0.first.map(String.init) }
            .prefix(2).joined().uppercased()
        return Text(initials.isEmpty ? "·" : initials)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(LinearGradient.diagonal)
            .clipShape(Circle())
    }

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private func miniPill(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.4)
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private func agreementLabel(_ s: String) -> String {
        switch s.lowercased() {
        case "active":             return "Agreement signed"
        case "pending_signature":  return "Awaiting signature"
        case "draft":              return "Agreement draft"
        case "expired":            return "Agreement expired"
        default:                   return "Agreement: \(s)"
        }
    }

    private func agreementGlyph(_ s: String) -> String {
        switch s.lowercased() {
        case "active":             return "checkmark.seal.fill"
        case "pending_signature":  return "signature"
        case "draft":              return "doc.text"
        case "expired":            return "clock.badge.exclamationmark"
        default:                   return "doc.plaintext"
        }
    }

    private func agreementColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "active":             return Brand.success
        case "pending_signature":  return Brand.warning
        case "expired":            return Brand.danger
        default:                   return palette.textTertiary
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No partners yet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Invite your first catalyst to start building your private rolodex.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                MeAction.fire("shipper.partner.invite", userInfo: nil)
            } label: {
                Text("Invite a partner").font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(Space.s4).frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - status style

private struct PartnerStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String?) -> PartnerStatusStyle {
        switch (raw ?? "").lowercased() {
        case "active":      return .init(label: "Active",     color: Brand.success)
        case "pending":     return .init(label: "Pending",    color: Brand.warning)
        case "declined":    return .init(label: "Declined",   color: Brand.danger)
        case "suspended":   return .init(label: "Suspended",  color: Brand.danger)
        case "terminated":  return .init(label: "Terminated", color: Brand.danger)
        default:            return .init(label: (raw ?? "Unknown").capitalized, color: .gray)
        }
    }
}

// MARK: - Previews

#Preview("Partners · Dark") {
    ShipperPartnerDirectory().preferredColorScheme(.dark)
}

#Preview("Partners · Light") {
    ShipperPartnerDirectory().preferredColorScheme(.light)
}
