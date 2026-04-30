//
//  425_PortIntelligence.swift
//  EusoTrip — Shipper · Port intelligence (ports / refineries / terminals by product grade).
//

import SwiftUI

struct PortIntelligenceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { PortIntelBody() } nav: { shipperLifecycleNav() }
    }
}

private struct PortRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let country: String?
    let acceptedProducts: [String]?
    let utilizationPct: Int?
    let avgDwellHours: Double?
}

private struct PortIntelBody: View {
    @Environment(\.palette) private var palette
    @State private var product: String = ""
    @State private var ports: [PortRow] = []
    @State private var loading = false
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                productInput
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ferry.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · PORT INTELLIGENCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Ports + terminals by product").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var productInput: some View {
        TextField("Product grade (e.g. 'WTI 0.4% sulfur')", text: $product)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onSubmit { Task { await search() } }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Searching…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if ports.isEmpty { LifecycleCard { Text("Enter a product grade to find ports / refineries / terminals that accept it.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true) } }
        else {
            ForEach(ports) { p in
                LifecycleCard {
                    LifecycleSection(label: p.name.uppercased(), icon: "ferry")
                    LifecycleRow(label: "Country",     value: dashIfEmpty(p.country))
                    LifecycleRow(label: "Utilization", value: p.utilizationPct.map { "\($0)%" } ?? "—")
                    LifecycleRow(label: "Avg dwell",   value: p.avgDwellHours.map { String(format: "%.1f hr", $0) } ?? "—")
                    LifecycleRow(label: "Accepts",     value: (p.acceptedProducts ?? []).joined(separator: ", ").isEmpty ? "—" : (p.acceptedProducts ?? []).joined(separator: ", "))
                }
            }
        }
    }

    private func search() async {
        loading = true; loadError = nil
        struct In: Encodable { let product: String }
        do {
            let r: [PortRow] = try await EusoTripAPI.shared.query("portIntelligence.findByProduct", input: In(product: product))
            ports = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("425 · Port intel · Night") { PortIntelligenceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("425 · Port intel · Afternoon") { PortIntelligenceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
