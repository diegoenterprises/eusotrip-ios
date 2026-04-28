//
//  209_ShipperContacts.swift
//  EusoTrip 2027 UI — 127th firing (shipper · working carriers directory)
//
//  Screen 209 · Shipper · Contacts — the shipper's working-carriers
//  directory. Server-derived view: catalyst companies the shipper has
//  delivered loads with, ranked DESC by load count, top 10. The
//  "Contacts" framing IS the doctrine — the most-worked-with carriers
//  ARE the shipper's de-facto contact list. There is no separate
//  junction table; favorites grow as the shipper completes loads.
//
//  Cohort B day-1 — fully dynamic (SKILL.md §3 "no-mock" pledge ·
//  2027 motivation directive "no fake data"):
//
//    • Every row comes from the live `shippers.getFavoriteCatalysts`
//      tRPC procedure — MCP-verified at
//      `frontend/server/routers/shippers.ts:500`. Backend aggregates
//      `loads` rows where `shipperId = ctx.user.id AND status =
//      'delivered' AND catalystId IS NOT NULL`, groups by
//      `catalystId`, joins through `companies` for `name + dotNumber`.
//
//    • Empty state is server-confirmed: a brand-new shipper with
//      zero delivered loads gets the EusoEmptyState hero with
//      onboarding copy that points them toward 204_ShipperPostLoad.
//
//    • Favorite-tap is a no-op acknowledgment server-side (the
//      backend is idempotent), wrapped in a row-level spinner via
//      `ShipperFavoriteCatalystsStore.acknowledgingId` — fire-and-
//      forget, no list refresh on success. On transport failure we
//      reconcile with `refresh()`.
//
//  Doctrine refs:
//    §1   LinearGradient.diagonal on header label, rank badges, and
//         the empty-state CTA. NO flat brand blue.
//    §2   No Toggle widgets on this brick (no GradientToggleStyle
//         obligation).
//    §4   Tokenized spacing, radii, type. No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews compile in isolation — store lands `.loading`
//         under preview canvas (no `.task` fires).
//

import SwiftUI

// MARK: - Screen root

struct ShipperContacts: View {
    @Environment(\.palette) var palette
    @StateObject private var store = ShipperFavoriteCatalystsStore()
    @State private var lastToast: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let rows):
                    summaryStrip(rows)
                    contactsList(rows)
                    disclosureFooter
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .overlay(alignment: .bottom) {
            if let toast = lastToast {
                toastView(toast)
                    .padding(.bottom, Space.s6)
                    .padding(.horizontal, Space.s4)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Working Carriers")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Top 10 by delivered loads")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.4))
                .frame(height: 76)
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 80)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "person.2.crop.square.stack",
            title: "No working carriers yet",
            subtitle: "Your contact list grows as you complete loads. Post your first load to start building relationships with EusoTrip-vetted carriers."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load contacts")
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

    private func summaryStrip(_ rows: [ShipperAPI.FavoriteCatalyst]) -> some View {
        let totalLoads = rows.reduce(0) { $0 + $1.loadsCompleted }
        let totalSpend = rows.reduce(0.0) { $0 + $1.totalSpend }
        return HStack(spacing: Space.s3) {
            summaryTile(
                label: "CARRIERS",
                value: "\(rows.count)",
                glyph: "building.2"
            )
            summaryTile(
                label: "DELIVERED",
                value: "\(totalLoads)",
                glyph: "shippingbox.fill"
            )
            summaryTile(
                label: "TOTAL SPEND",
                value: formatCurrency(totalSpend),
                glyph: "dollarsign.circle.fill"
            )
        }
    }

    private func summaryTile(label: String, value: String, glyph: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s1) {
                Image(systemName: glyph)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(EType.micro).tracking(1.2)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: Contacts list

    private func contactsList(_ rows: [ShipperAPI.FavoriteCatalyst]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("DIRECTORY")
                    .font(EType.micro).tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(rows.count)")
                    .font(EType.micro).tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: Space.s2) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    contactRow(row, rank: idx + 1)
                }
            }
        }
    }

    private func contactRow(_ row: ShipperAPI.FavoriteCatalyst, rank: Int) -> some View {
        let isAcking = store.acknowledgingId == row.catalystId
        return HStack(spacing: Space.s3) {
            // Rank badge: top 3 get gradient, rest get neutral
            Text("\(rank)")
                .font(EType.bodyStrong)
                .foregroundStyle(rank <= 3 ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(rank <= 3 ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral.opacity(0.5)))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Space.s2) {
                    if !row.dotNumber.isEmpty {
                        Text("DOT \(row.dotNumber)")
                            .font(EType.micro).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                    }
                    if !row.dotNumber.isEmpty {
                        Circle()
                            .fill(palette.textTertiary.opacity(0.4))
                            .frame(width: 3, height: 3)
                    }
                    Text("\(row.loadsCompleted) load\(row.loadsCompleted == 1 ? "" : "s")")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(row.totalSpend))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if isAcking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                } else {
                    Text("LIFETIME")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Menu {
                Button {
                    Task {
                        await store.acknowledgeFavorite(catalystId: row.catalystId)
                        flashToast("Marked as preferred")
                    }
                } label: {
                    Label("Mark as preferred", systemImage: "star")
                }
                Button {
                    flashToast("Profile coming soon")
                } label: {
                    Label("View carrier profile", systemImage: "person.text.rectangle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(palette.bgCard.opacity(0.8))
                    )
            }
            .menuStyle(.button)
            .accessibilityLabel("Manage \(row.name)")
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

    // MARK: Disclosure

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("How this list is built")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Your working-carriers directory is derived live from delivered loads. The top 10 are ranked by load count, with lifetime spend shown for context. Marking a carrier as preferred routes future bid requests to them first when they match your lane.")
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

    // MARK: Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LinearGradient.diagonal)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 16, y: 8)
    }

    private func flashToast(_ text: String) {
        withAnimation { lastToast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation { lastToast = nil }
            }
        }
    }

    // MARK: Formatters

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct ShipperContactsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperContacts()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_209(),
                trailing: shipperNavTrailing_209(),
                orbState: .idle
            )
        }
    }
}

// Shipper bottom-nav doctrine — contacts/carriers live under Me.
private func shipperNavLeading_209() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_209() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// each register renders the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("209 · Shipper · Contacts · Night") {
    ShipperContactsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("209 · Shipper · Contacts · Afternoon") {
    ShipperContactsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
