//
//  080_MeTaxDocuments.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · tax documents)
//
//  Screen 080 · Me · Tax Documents — the driver's IRS + state
//  filings vault. Year filter (All · current year · prior year · 2
//  back), grouped-by-year list with per-row type chip (1099-NEC /
//  1099-K / W-9 / state-1099), status chip (Available / Pending),
//  download action that resolves against `EusoTripAPI.baseURL`.
//
//  Closes the wallet-management chain (077 Methods → 078 Schedule
//  → 079 Breakdown → 080 Tax).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Rows come from `wallet.getTaxDocuments` — MCP-verified at
//      `frontend/server/routers/wallet.ts:758`. Server currently
//      ships 1099-NEC for current + prior year; iOS decodes `type`
//      as a freeform string so state / W-9 additions on the server
//      render immediately without a mobile release.
//
//    • Download URLs are resolved against the app's baseURL so
//      relative server paths (`/api/tax/...pdf`) still open in the
//      signed-in session.
//
//    • Empty state is server-confirmed. A brand-new driver whose
//      first tax year isn't closed yet sees the "No filings yet"
//      hero — which tells them what to expect, not what to do.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on active year pill + Download
//         CTA. Brand.warning only when a filing is pending past
//         IRS issuance deadline.
//    §4   Tokenized spacing, radii, type.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews land in `.error` under the no-baseURL runtime.
//         No fixtures.
//

import SwiftUI

// MARK: - Year filter

private enum TaxYearFilter: Hashable, Identifiable {
    case all
    case year(Int)
    var id: String {
        switch self {
        case .all: return "all"
        case .year(let y): return String(y)
        }
    }
    var label: String {
        switch self {
        case .all: return "All"
        case .year(let y): return String(y)
        }
    }
    /// Convert to the server's optional `year` param.
    var serverValue: Int? {
        if case .year(let y) = self { return y }
        return nil
    }
}

// MARK: - Screen root

struct MeTaxDocuments: View {
    @Environment(\.palette) var palette
    @StateObject private var store = TaxDocumentsStore()

    @State private var selected: TaxYearFilter = .all
    /// Options — [All, current, current-1, current-2].
    private var options: [TaxYearFilter] {
        let year = Calendar.current.component(.year, from: Date())
        return [.all, .year(year), .year(year - 1), .year(year - 2)]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                yearFilter
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let rows):
                    summaryStrip(rows)
                    documentsSection(rows)
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .onChange(of: selected) { _, newValue in
            store.year = newValue.serverValue
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Tax Documents")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("1099-NEC · W-9 · state filings")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Year filter

    private var yearFilter: some View {
        HStack(spacing: Space.s2) {
            ForEach(options) { opt in
                Button {
                    selected = opt
                } label: {
                    let on = opt == selected
                    Text(opt.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                if on {
                                    Capsule().fill(LinearGradient.diagonal)
                                } else {
                                    Capsule().fill(palette.bgCard.opacity(0.85))
                                }
                            }
                        )
                        .overlay(
                            Capsule().strokeBorder(on ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.4))
                .frame(height: 72)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 72)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "doc.text",
            title: "No filings yet",
            subtitle: "1099-NEC forms are issued by January 31 for the prior tax year. Come back after your first settled year to download them."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load tax documents")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
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
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Summary strip

    private func summaryStrip(_ rows: [WalletAPI.TaxDocument]) -> some View {
        let available = rows.filter { $0.status.lowercased() == "available" }.count
        let pending = rows.filter { $0.status.lowercased() != "available" }.count
        return HStack(spacing: Space.s2) {
            summaryTile(label: "AVAILABLE",
                        value: "\(available)",
                        emphasis: available > 0)
            summaryTile(label: "PENDING",
                        value: "\(pending)",
                        emphasis: false)
            summaryTile(label: "TOTAL",
                        value: "\(rows.count)",
                        emphasis: false)
        }
    }

    private func summaryTile(label: String, value: String, emphasis: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .monospacedDigit()
                .foregroundStyle(emphasis
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textPrimary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: Documents grouped by year

    @ViewBuilder
    private func documentsSection(_ rows: [WalletAPI.TaxDocument]) -> some View {
        if rows.isEmpty {
            emptyHero
        } else {
            let groups = Dictionary(grouping: rows, by: { $0.year })
                .sorted { $0.key > $1.key }
            VStack(alignment: .leading, spacing: Space.s4) {
                ForEach(groups, id: \.key) { year, docs in
                    VStack(alignment: .leading, spacing: Space.s2) {
                        HStack {
                            Text(String(year))
                                .font(EType.micro).tracking(1.4)
                                .foregroundStyle(palette.textTertiary)
                            Spacer()
                            Text("\(docs.count)")
                                .font(EType.micro).tracking(1.1)
                                .foregroundStyle(palette.textTertiary)
                        }
                        VStack(spacing: Space.s2) {
                            ForEach(docs) { doc in
                                docRow(doc)
                            }
                        }
                    }
                }
            }
        }
    }

    private func docRow(_ doc: WalletAPI.TaxDocument) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: iconFor(type: doc.type))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.bgCard.opacity(0.8))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(friendlyTitle(for: doc))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle(for: doc))
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            downloadButton(doc: doc)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func downloadButton(doc: WalletAPI.TaxDocument) -> some View {
        if doc.status.lowercased() == "available",
           let url = resolveURL(doc.downloadUrl) {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("DOWNLOAD")
                        .font(EType.micro).tracking(1.2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 8)
                .background(Capsule().fill(LinearGradient.diagonal))
            }
        } else {
            Text("PENDING")
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, 8)
                .background(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    // MARK: Footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "building.columns")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("IRS issuance calendar")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("1099-NEC forms are issued by January 31 for income earned in the prior calendar year. State 1099s and Schedule C supporting documents follow the state's own filing calendar. Each PDF here is signed + archived — safe to forward to your CPA.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Helpers

    private func iconFor(type: String) -> String {
        let t = type.lowercased()
        if t.contains("w-9") || t.contains("w9")  { return "person.text.rectangle" }
        if t.contains("1099-k") || t.contains("1099k") { return "creditcard" }
        if t.contains("state")                    { return "map" }
        if t.contains("schedule")                 { return "list.clipboard" }
        return "doc.text"
    }

    private func friendlyTitle(for doc: WalletAPI.TaxDocument) -> String {
        "\(doc.type) · \(doc.year)"
    }

    private func subtitle(for doc: WalletAPI.TaxDocument) -> String {
        let status = doc.status.replacingOccurrences(of: "_", with: " ").capitalized
        let t = doc.type.lowercased()
        if t.contains("1099-nec") { return "\(status) · Non-employee comp" }
        if t.contains("1099-k")   { return "\(status) · Payment-card" }
        if t.contains("w-9") || t.contains("w9") { return "\(status) · Tax-ID on file" }
        if t.contains("state")    { return "\(status) · State filing" }
        return status
    }

    /// Resolve a relative server path against baseURL; pass absolute
    /// URLs through. Returns nil when the path is empty or baseURL
    /// isn't configured (preview runtime).
    private func resolveURL(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        guard let base = EusoTripAPI.shared.baseURL else { return nil }
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }
}

// MARK: - Screen wrapper

struct MeTaxDocumentsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeTaxDocuments()
        } nav: {
            BottomNav(
                leading: driverNavLeading_080(),
                trailing: driverNavTrailing_080(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_080() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_080() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person.fill",      isCurrent: false)]
}

// MARK: - Previews

#Preview("080 · Me Tax Documents · Night") {
    MeTaxDocumentsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("080 · Me Tax Documents · Afternoon") {
    MeTaxDocumentsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
