//
//  317_CarrierAuthority.swift
//  EusoTrip — Carrier · Authority (FMCSA self-view).
//

import SwiftUI

struct CarrierAuthorityScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { AuthorityBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct AuthorityRecord: Decodable, Hashable {
    let dotNumber: String?
    let mcNumber: String?
    let legalName: String?
    let dbaName: String?
    let physicalAddress: String?
    let mailingAddress: String?
    let safetyRating: String?
    let outOfServiceDate: String?
    let driverCount: Int?
    let powerUnits: Int?
    let basicScores: [String: Double]?
    let insuranceFiling: String?
    let crashes24mo: Int?
    let inspections24mo: Int?
}

private struct AuthorityBody: View {
    @Environment(\.palette) private var palette
    @State private var data: AuthorityRecord? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Pulling FMCSA…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let d = data { authority(d); fleet(d); basic(d); inspections(d) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · AUTHORITY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(data?.legalName ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func authority(_ d: AuthorityRecord) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "AUTHORITY", icon: "doc.text")
            LifecycleRow(label: "USDOT",            value: dashIfEmpty(d.dotNumber))
            LifecycleRow(label: "MC",               value: dashIfEmpty(d.mcNumber))
            LifecycleRow(label: "DBA",              value: dashIfEmpty(d.dbaName))
            LifecycleRow(label: "Safety rating",    value: dashIfEmpty(d.safetyRating))
            LifecycleRow(label: "OOS date",         value: humanISO(d.outOfServiceDate, format: "MMM d, yyyy"))
            LifecycleRow(label: "Insurance filing", value: dashIfEmpty(d.insuranceFiling))
        }
    }

    private func fleet(_ d: AuthorityRecord) -> some View {
        LifecycleCard {
            LifecycleSection(label: "FLEET", icon: "truck.box")
            LifecycleRow(label: "Power units",  value: "\(d.powerUnits ?? 0)")
            LifecycleRow(label: "Drivers",      value: "\(d.driverCount ?? 0)")
        }
    }

    @ViewBuilder
    private func basic(_ d: AuthorityRecord) -> some View {
        if let scores = d.basicScores, !scores.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "BASIC SCORES", icon: "chart.bar")
                ForEach(scores.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    LifecycleRow(label: k, value: String(format: "%.1f", v))
                }
            }
        }
    }

    private func inspections(_ d: AuthorityRecord) -> some View {
        LifecycleCard {
            LifecycleSection(label: "24-MONTH HISTORY", icon: "calendar")
            LifecycleRow(label: "Crashes",      value: "\(d.crashes24mo ?? 0)")
            LifecycleRow(label: "Inspections",   value: "\(d.inspections24mo ?? 0)")
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let d: AuthorityRecord = try await EusoTripAPI.shared.queryNoInput("catalysts.getAuthority")
            data = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("317 · Authority · Night") { CarrierAuthorityScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("317 · Authority · Afternoon") { CarrierAuthorityScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
