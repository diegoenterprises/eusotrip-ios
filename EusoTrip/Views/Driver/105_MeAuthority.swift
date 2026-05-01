//
//  105_MeAuthority.swift
//  EusoTrip — Me · Operating Authority + Lease-On.
//
//  Web-platform parity port of `pages/OperatingAuthority.tsx`. Drivers
//  who don't carry their own DOT/MC operate under another carrier's
//  authority via FMCSR Part 376 lease-on. This screen surfaces:
//
//    1. OWN AUTHORITY — the driver's own company DOT/MC (when they
//       own one) with insurance + compliance status.
//    2. ACTIVE LEASES (as lessee) — carriers the driver currently
//       operates under. Each row shows lessor name, MC/DOT, lease
//       type (full/trip/interline/seasonal), 4-point Part 376
//       compliance checklist, and status timeline.
//    3. ACTIVE LEASES (as lessor) — when the driver IS the carrier,
//       which other operators are under their authority.
//    4. BROWSE AUTHORITIES — search registered carriers willing to
//       accept lease-on operators. Tap to open the create-lease flow.
//    5. EQUIPMENT AUTHORITY — per-vehicle "own" vs "leased" with the
//       resolved MC/DOT each unit operates under.
//
//  Backed by `authorityRouter` (10 procedures wired through
//  `EusoTripAPI.shared.authority`).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Store

@MainActor
final class AuthorityStore: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case overview, browse, equipment
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview:  return "Overview"
            case .browse:    return "Browse"
            case .equipment: return "Equipment"
            }
        }
    }

    @Published var tab: Tab = .overview

    @Published private(set) var auth: AuthorityAPI.MyAuthority?
    @Published private(set) var browseResults: [AuthorityAPI.AuthorityListing] = []
    @Published var browseQuery: String = ""
    @Published private(set) var equipment: [AuthorityAPI.EquipmentAuthority] = []
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: String?

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) { self.api = api }

    func bootstrap() async {
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            switch tab {
            case .overview:
                auth = try await api.authority.getMyAuthority()
            case .browse:
                browseResults = try await api.authority.browseAuthorities(
                    search: browseQuery.isEmpty ? nil : browseQuery
                )
            case .equipment:
                equipment = try await api.authority.getEquipmentAuthority()
            }
            lastError = nil
        } catch {
            lastError = "Couldn't reach the authority service."
        }
    }

    func startLeaseOn(_ listing: AuthorityAPI.AuthorityListing,
                      type: String = "trip_lease") async -> Bool {
        do {
            _ = try await api.authority.createLease(
                .init(
                    lessorCompanyId: listing.companyId,
                    lesseeUserId: nil,
                    leaseType: type,
                    startDate: ISO8601DateFormatter().string(from: Date()),
                    endDate: nil,
                    revenueSharePercent: nil,
                    loadId: nil,
                    originCity: nil, originState: nil,
                    destinationCity: nil, destinationState: nil,
                    trailerTypes: nil,
                    notes: "iOS-initiated lease-on request"
                )
            )
            await refresh()
            return true
        } catch {
            lastError = "Couldn't start lease."
            return false
        }
    }

    func updateCompliance(
        leaseId: Int,
        written: Bool? = nil,
        exclusive: Bool? = nil,
        insurance: Bool? = nil,
        marking: Bool? = nil
    ) async {
        _ = try? await api.authority.updateCompliance(
            leaseId: leaseId,
            hasWrittenLease: written,
            hasExclusiveControl: exclusive,
            hasInsuranceCoverage: insurance,
            hasVehicleMarking: marking
        )
        await refresh()
    }

    func sign(leaseId: Int, role: String) async {
        _ = try? await api.authority.signLease(leaseId: leaseId, role: role)
        await refresh()
    }

    func terminate(leaseId: Int) async {
        _ = try? await api.authority.terminateLease(leaseId: leaseId, reason: "Driver terminated")
        await refresh()
    }
}

// MARK: - Screen

struct MeAuthority: View {
    @Environment(\.palette) var palette
    @StateObject private var store = AuthorityStore()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            tabs
            paneBody
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .task { await store.bootstrap() }
        .refreshable { await store.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Authority")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DOT · MC · lease-on · FMCSR Part 376")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            if let score = store.auth?.complianceScore {
                StatusPill(text: "Compliance \(score)%",
                           kind: score >= 90 ? .success : (score >= 60 ? .warning : .danger))
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: Space.s2) {
            ForEach(AuthorityStore.Tab.allCases) { t in
                Button {
                    store.tab = t
                    Task { await store.refresh() }
                } label: {
                    Text(t.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(t == store.tab ? .white : palette.textPrimary)
                        .padding(.horizontal, Space.s3).padding(.vertical, 8)
                        .background(t == store.tab
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.bgCardSoft))
                        .overlay(Capsule().stroke(palette.borderFaint, lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var paneBody: some View {
        switch store.tab {
        case .overview:  overviewPane
        case .browse:    browsePane
        case .equipment: equipmentPane
        }
    }

    // MARK: Overview

    @ViewBuilder
    private var overviewPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let own = store.auth?.ownAuthority {
                    ownAuthorityCard(own)
                } else {
                    EusoEmptyState(
                        systemImage: "building.2",
                        title: "No company authority on file",
                        subtitle: "Owner-operators with their own DOT/MC will see it here. If you operate under another carrier's authority, browse the directory to add a lease."
                    )
                }
                if let leases = store.auth?.activeLeasesAsLessee, !leases.isEmpty {
                    sectionHeader("OPERATING UNDER")
                    ForEach(leases) { l in leaseRow(l, role: "lessee") }
                }
                if let leases = store.auth?.activeLeasesAsLessor, !leases.isEmpty {
                    sectionHeader("OPERATORS UNDER YOU")
                    ForEach(leases) { l in leaseRow(l, role: "lessor") }
                }
                Color.clear.frame(height: Space.s8)
            }
        }
    }

    private func ownAuthorityCard(_ a: AuthorityAPI.OwnAuthority) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR AUTHORITY")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(a.companyName ?? "—")
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                if let legal = a.legalName, legal != a.companyName {
                    Text(legal)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: Space.s3) {
                    MetricTile(label: "DOT", value: a.dotNumber ?? "—")
                    MetricTile(label: "MC",  value: a.mcNumber ?? "—")
                }
                if let exp = a.insuranceExpiry?.prefix(10) {
                    Text("Insurance expires \(exp)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                StatusPill(
                    text: (a.complianceStatus ?? "—").capitalized,
                    kind: (a.complianceStatus ?? "").lowercased() == "compliant" ? .success : .warning
                )
            }
        }
    }

    private func leaseRow(_ l: AuthorityAPI.LeaseRow, role: String) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(role == "lessee"
                             ? (l.lessorCompanyName ?? "Carrier")
                             : (l.lesseeName ?? "Operator"))
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("\(l.leaseType.replacingOccurrences(of: "_", with: " ").capitalized) · MC \(l.lessorMcNumber ?? l.mcNumber ?? "—")")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    StatusPill(text: l.status.replacingOccurrences(of: "_", with: " ").capitalized,
                               kind: leaseStatusKind(l.status))
                }
                if l.originCity != nil || l.destinationCity != nil {
                    Text("\([l.originCity, l.originState].compactMap { $0 }.joined(separator: ", ")) → \([l.destinationCity, l.destinationState].compactMap { $0 }.joined(separator: ", "))")
                        .font(EType.caption.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                }
                Divider().overlay(palette.borderFaint)
                Text("FMCSR PART 376 COMPLIANCE")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                complianceToggle(label: "Written lease",        on: l.hasWrittenLease)      { v in Task { await store.updateCompliance(leaseId: l.id, written: v) } }
                complianceToggle(label: "Exclusive control",    on: l.hasExclusiveControl)  { v in Task { await store.updateCompliance(leaseId: l.id, exclusive: v) } }
                complianceToggle(label: "Insurance coverage",   on: l.hasInsuranceCoverage) { v in Task { await store.updateCompliance(leaseId: l.id, insurance: v) } }
                complianceToggle(label: "Vehicle marking",      on: l.hasVehicleMarking)    { v in Task { await store.updateCompliance(leaseId: l.id, marking: v) } }
                if l.status == "draft" || l.status == "pending_signatures" {
                    CTAButton(title: "Sign as \(role)") {
                        Task { await store.sign(leaseId: l.id, role: role) }
                    }
                }
                if l.status == "active" {
                    Button("Terminate lease") {
                        Task { await store.terminate(leaseId: l.id) }
                    }
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(Brand.danger)
                }
            }
        }
    }

    private func complianceToggle(
        label: String,
        on value: Bool?,
        update: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(
            get: { value ?? false },
            set: { update($0) }
        )) {
            Text(label)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
        }
        .toggleStyle(GradientToggleStyle())
    }

    private func leaseStatusKind(_ status: String) -> StatusPill.Kind {
        switch status {
        case "active":              return .success
        case "draft":               return .neutral
        case "pending_signatures":  return .warning
        case "expired", "terminated", "suspended":
            return .danger
        default:                    return .info
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(EType.micro).tracking(0.8)
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: Browse

    @ViewBuilder
    private var browsePane: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s3) {
                searchBar
                if store.isLoading && store.browseResults.isEmpty {
                    ProgressView().padding()
                } else if store.browseResults.isEmpty {
                    EusoEmptyState(
                        systemImage: "magnifyingglass",
                        title: "No carriers found",
                        subtitle: "Search by company name, MC, or DOT to find authorities accepting lease-on."
                    )
                    .padding(.top, Space.s4)
                } else {
                    ForEach(store.browseResults) { listing in
                        browseRow(listing)
                    }
                }
                Color.clear.frame(height: Space.s8)
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.textSecondary)
            TextField("Carrier name · DOT · MC", text: $store.browseQuery)
                .submitLabel(.search)
                .onSubmit { Task { await store.refresh() } }
            if !store.browseQuery.isEmpty {
                Button {
                    store.browseQuery = ""
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(palette.bgCardSoft)
        .clipShape(Capsule())
    }

    private func browseRow(_ a: AuthorityAPI.AuthorityListing) -> some View {
        ActiveCard {
            HStack(spacing: Space.s3) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(palette.bgCardSoft))
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.companyName ?? "—")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("MC \(a.mcNumber ?? "—") · DOT \(a.dotNumber ?? "—")")
                        .font(EType.caption.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                    HStack(spacing: 6) {
                        StatusPill(
                            text: (a.complianceStatus ?? "—").capitalized,
                            kind: (a.complianceStatus ?? "").lowercased() == "compliant" ? .success : .warning
                        )
                        if a.insuranceValid == true {
                            Text("Insurance OK")
                                .font(EType.micro.weight(.semibold))
                                .foregroundStyle(Brand.success)
                        } else {
                            Text("No insurance")
                                .font(EType.micro.weight(.semibold))
                                .foregroundStyle(Brand.danger)
                        }
                    }
                }
                Spacer()
                Button("Lease on") {
                    Task { _ = await store.startLeaseOn(a) }
                }
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s3).padding(.vertical, 6)
                .background(Capsule().fill(LinearGradient.diagonal))
            }
        }
    }

    // MARK: Equipment

    @ViewBuilder
    private var equipmentPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                if store.isLoading && store.equipment.isEmpty {
                    ProgressView().padding()
                } else if store.equipment.isEmpty {
                    EusoEmptyState(
                        systemImage: "truck.box",
                        title: "No equipment on file",
                        subtitle: "Vehicles in your fleet show up here with their authority source — own or leased."
                    )
                    .padding(.top, Space.s4)
                } else {
                    ForEach(store.equipment) { v in
                        equipmentRow(v)
                    }
                }
                Color.clear.frame(height: Space.s8)
            }
        }
    }

    private func equipmentRow(_ v: AuthorityAPI.EquipmentAuthority) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: v.authoritySource == "leased" ? "arrow.triangle.swap" : "checkmark.seal.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(v.authoritySource == "leased" ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(LinearGradient.diagonal))
                .frame(width: 32, height: 32)
                .background(Circle().fill(palette.bgCardSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(v.year.map(String.init) ?? "") \(v.make ?? "") \(v.model ?? "")".trimmingCharacters(in: .whitespaces))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("VIN \(v.vin ?? "—") · \(v.licensePlate ?? "—")")
                    .font(EType.caption.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                if v.authoritySource == "leased" {
                    Text("Leased · MC \(v.leaseMcNumber ?? "—")")
                        .font(EType.micro.weight(.semibold))
                        .foregroundStyle(Brand.warning)
                } else {
                    Text("Own authority")
                        .font(EType.micro.weight(.semibold))
                        .foregroundStyle(Brand.success)
                }
            }
            Spacer()
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }
}

// MARK: - Screen wrapper (registered in ContentView ScreenRegistry)

struct MeAuthorityScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeAuthority()
        } nav: {
            BottomNav(
                leading: driverNavLeading_105(),
                trailing: driverNavTrailing_105(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_105() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_105() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("105 · Authority · Night") {
    MeAuthorityScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("105 · Authority · Afternoon") {
    MeAuthorityScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
