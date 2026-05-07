//
//  092_MePermits.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Permits)
//
//  Screen 092 · Me · Permits — trip / oversize / IRP / IFTA permit
//  cockpit for owner-operators. Summary counters at the top, then a
//  "Needs attention" section for permits expiring within 45 days
//  with one-tap renewal, then the active-permits list sorted by
//  expiration. Every row shows the real permit number, type,
//  covered states, and days-until-expiration.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Summary + active + expiring all ship from
//      `permits.getSummary` / `getActive` / `getExpiring` —
//      MCP-verified at `frontend/server/routers/permits.ts`.
//    • Renew fires `permits.renew` with the driver's chosen
//      end date; server may flip the permit back to `pending` for
//      re-approval depending on type. Refresh picks up the new
//      state in-place.
//    • No fabricated permit numbers, no fake expirations, no
//      hardcoded state lists.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on summary + renew CTA.
//         Brand.warning on expiring <14 days, red stroke <7 days.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MePermits: View {
    @Environment(\.palette) var palette
    @StateObject private var store = PermitsStore()

    @State private var renewing: PermitsAPI.Permit?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                summaryStrip
                needsAttentionSection
                activeSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $renewing) { permit in
            RenewSheet(permit: permit, store: store)
                .eusoSheetX()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Permits")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Trip · oversize · IRP · IFTA renewals")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Summary strip

    private var summaryStrip: some View {
        let s = store.summary
        return HStack(spacing: Space.s2) {
            summaryTile(label: "ACTIVE",   value: "\(s?.active ?? 0)",   gradient: true)
            summaryTile(label: "EXPIRING", value: "\(s?.expiring ?? 0)", gradient: false)
            summaryTile(label: "EXPIRED",  value: "\(s?.expired ?? 0)",  gradient: false)
        }
    }

    private func summaryTile(label: String, value: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .foregroundStyle(gradient
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Needs attention

    private var needsAttentionSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !store.expiring.isEmpty {
                Text("NEEDS ATTENTION")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                ForEach(store.expiring) { e in
                    expiringRow(e)
                }
            }
        }
    }

    private func expiringRow(_ e: PermitsAPI.ExpiringPermit) -> some View {
        let urgent = e.daysRemaining <= 7
        let warning = e.daysRemaining <= 14
        let tint: Color = urgent ? Brand.magenta : (warning ? Brand.warning : palette.textSecondary)
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(tint.opacity(0.18))
                Text("\(e.daysRemaining)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(e.permitNumber ?? "Permit #\(e.id)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text([e.type?.capitalized, statesChip(e.states)]
                     .compactMap { $0 }.joined(separator: " · "))
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                Text("Expires \(humanizeDate(e.expirationDate))")
                    .font(EType.micro)
                    .foregroundStyle(tint)
            }

            Spacer()
            Button {
                // Find the corresponding Permit in active (expiring rows
                // carry a narrower shape, but renew needs more context).
                // Fall back to a synthesized Permit with the id when a
                // matching active row isn't cached.
                let match = store.active.first { $0.id == e.id }
                    ?? PermitsAPI.Permit(
                        id: e.id,
                        permitNumber: e.permitNumber,
                        type: e.type,
                        status: nil,
                        states: e.states,
                        origin: nil,
                        destination: nil,
                        commodity: nil,
                        weight: nil,
                        expirationDate: e.expirationDate,
                        fees: nil,
                        createdAt: nil
                    )
                renewing = match
            } label: {
                Text("Renew")
                    .font(EType.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Active list

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACTIVE")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if store.active.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No active permits",
                    subtitle: "Permits you've pulled for oversize runs, IRP renewals, or hazmat specialty hauls land here."
                )
            } else {
                ForEach(store.active) { p in
                    activeRow(p)
                }
            }
        }
    }

    private func activeRow(_ p: PermitsAPI.Permit) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: permitIcon(p.type))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.5))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(p.permitNumber ?? "Permit #\(p.id)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: 4) {
                    if let type = p.type, !type.isEmpty {
                        Text(type.capitalized)
                    }
                    if let states = statesChip(p.states), !states.isEmpty {
                        Text("·")
                        Text(states)
                    }
                }
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                if let exp = p.expirationDate {
                    Text("Expires \(humanizeDate(exp))")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            if let fees = p.fees, fees > 0 {
                Text(currency(fees))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Footer

    private var footer: some View {
        Text("Permit renewals submit the request. Some permits (IRP, trip) still route through the state's DMV after EusoTrip pre-validates the form.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func permitIcon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "oversize", "overweight": return "arrow.up.left.and.arrow.down.right"
        case "trip":                   return "road.lanes"
        case "irp":                    return "car.2"
        case "ifta":                   return "fuelpump"
        case "hazmat":                 return "exclamationmark.triangle"
        default:                       return "doc.text"
        }
    }

    private func statesChip(_ states: [String]?) -> String? {
        guard let states, !states.isEmpty else { return nil }
        if states.count <= 3 { return states.joined(separator: ", ") }
        return "\(states.prefix(3).joined(separator: ", ")) +\(states.count - 3)"
    }

    private func humanizeDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd"
        inFormatter.locale = Locale(identifier: "en_US_POSIX")
        let altFormatter = ISO8601DateFormatter()
        let date = inFormatter.date(from: String(iso.prefix(10)))
            ?? altFormatter.date(from: iso)
        guard let date else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: date)
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

// MARK: - Renew sheet

private struct RenewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let permit: PermitsAPI.Permit
    @ObservedObject var store: PermitsStore

    @State private var endDate: Date = Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date()

    private let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Permit") {
                    Text(permit.permitNumber ?? "Permit #\(permit.id)")
                        .font(EType.bodyStrong)
                    if let type = permit.type {
                        Text(type.capitalized)
                            .foregroundStyle(.secondary)
                            .font(EType.caption)
                    }
                }
                Section("Renew through") {
                    DatePicker(
                        "End date",
                        selection: $endDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("Renew permit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await store.renew(
                                permitId: permit.id,
                                toEndDate: isoFormatter.string(from: endDate)
                            )
                            dismiss()
                        }
                    } label: {
                        if store.renewingId == permit.id {
                            ProgressView()
                        } else {
                            Text("Submit").fontWeight(.semibold)
                        }
                    }
                    .disabled(store.renewingId == permit.id)
                }
            }
        }
    }
}

// MARK: - Screen wrapper

struct MePermitsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MePermits()
        } nav: {
            BottomNav(
                leading: driverNavLeading_092(),
                trailing: driverNavTrailing_092(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_092() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_092() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("092 · Permits · Night") {
    MePermitsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("092 · Permits · Afternoon") {
    MePermitsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
