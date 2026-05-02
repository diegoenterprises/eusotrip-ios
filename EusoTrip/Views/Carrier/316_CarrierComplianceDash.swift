//
//  316_CarrierComplianceDash.swift
//  EusoTrip — Carrier · Compliance dashboard.
//

import SwiftUI

struct CarrierComplianceDashScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ComplianceBody() } nav: {
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

private struct CarrierCompliance: Decodable, Hashable {
    let safetyRating: String?
    let oosViolations: Int?
    let docsExpiring: Int?
    let docsExpired: Int?
    let lastInspection: String?
    let driversCount: Int?
    let driversWithExpiringMedical: Int?
    let driversWithCdlIssues: Int?
}

private struct ComplianceBody: View {
    @Environment(\.palette) private var palette
    @State private var data: CarrierCompliance? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let d = data {
                    HStack(spacing: Space.s2) {
                        LifecycleStatTile(label: "OOS", value: "\(d.oosViolations ?? 0)", icon: "exclamationmark.octagon", danger: (d.oosViolations ?? 0) > 0)
                        LifecycleStatTile(label: "EXPIRING", value: "\(d.docsExpiring ?? 0)", icon: "calendar.badge.exclamationmark", danger: (d.docsExpiring ?? 0) > 0)
                        LifecycleStatTile(label: "EXPIRED", value: "\(d.docsExpired ?? 0)", icon: "xmark.circle", danger: (d.docsExpired ?? 0) > 0)
                    }
                    LifecycleCard(accentGradient: true) {
                        LifecycleSection(label: "AUTHORITY", icon: "checkmark.shield.fill")
                        LifecycleRow(label: "Safety rating",   value: dashIfEmpty(d.safetyRating))
                        LifecycleRow(label: "Last inspection", value: humanISO(d.lastInspection, format: "MMM d, yyyy"))
                    }
                    LifecycleCard {
                        LifecycleSection(label: "DRIVERS", icon: "person.3.fill")
                        LifecycleRow(label: "Total drivers",        value: "\(d.driversCount ?? 0)")
                        LifecycleRow(label: "Medical expiring",      value: "\(d.driversWithExpiringMedical ?? 0)")
                        LifecycleRow(label: "CDL issues",            value: "\(d.driversWithCdlIssues ?? 0)")
                    }
                    cellLinks
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · COMPLIANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Compliance dashboard").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var cellLinks: some View {
        VStack(spacing: 8) {
            link(icon: "checkmark.shield", label: "Authority (FMCSA)", screen: "317")
            link(icon: "antenna.radiowaves.left.and.right", label: "ELD fleet status", screen: "318")
            link(icon: "person.3", label: "Drivers list", screen: "319")
            link(icon: "truck.box", label: "Vehicles list", screen: "320")
        }
    }

    private func link(icon: String, label: String, screen: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoCarrierNavSwap, object: nil, userInfo: ["screenId": screen])
        } label: {
            LifecycleCard {
                HStack {
                    Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                    Text(label).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
            }
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let d: CarrierCompliance = try await EusoTripAPI.shared.queryNoInput("catalysts.getComplianceSnapshot")
            data = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("316 · Compliance · Night") { CarrierComplianceDashScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("316 · Compliance · Afternoon") { CarrierComplianceDashScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
