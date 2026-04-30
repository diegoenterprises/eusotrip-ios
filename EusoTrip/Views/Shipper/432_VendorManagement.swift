//
//  432_VendorManagement.swift
//  EusoTrip — Shipper · Vendor management.
//

import SwiftUI

struct VendorManagementScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VendorBody() } nav: { shipperLifecycleNav() }
    }
}

private struct VendorRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String?
    let contractStatus: String?
    let spendYtd: Double?
    let lastInvoiceISO: String?
}

private struct VendorBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [VendorRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · VENDORS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Vendor management").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading vendors…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "building.columns", title: "No vendors", subtitle: "Add vendors via web or `vendorManagement.create`.") }
        else {
            ForEach(rows) { v in
                LifecycleCard {
                    LifecycleSection(label: v.name.uppercased(), icon: "building")
                    LifecycleRow(label: "Category",  value: dashIfEmpty(v.category))
                    LifecycleRow(label: "Contract",  value: dashIfEmpty(v.contractStatus?.uppercased()))
                    LifecycleRow(label: "Spend YTD", value: usd(v.spendYtd))
                    LifecycleRow(label: "Last invoice", value: humanISO(v.lastInvoiceISO))
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [VendorRow] = try await EusoTripAPI.shared.queryNoInput("vendors.list")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("432 · Vendors · Night") { VendorManagementScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("432 · Vendors · Afternoon") { VendorManagementScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
