//
//  434_PartnerDetail.swift
//  EusoTrip — Shipper · Partner detail (deepens 224 directory).
//

import SwiftUI

struct PartnerDetailScreen: View {
    let theme: Theme.Palette
    let partnerId: String
    var body: some View {
        Shell(theme: theme) { PartnerDetailBody(partnerId: partnerId) } nav: { shipperLifecycleNav() }
    }
}

private struct Partner: Decodable, Hashable {
    let id: String
    let name: String
    let kind: String?            // "carrier" / "broker" / "facility" / "factoring"
    let dotNumber: String?
    let mcNumber: String?
    let relationshipSince: String?
    let activeLoads: Int?
    let lifetimeSpend: Double?
    let agreementsCount: Int?
}

private struct PartnerDetailBody: View {
    @Environment(\.palette) private var palette
    let partnerId: String
    @State private var partner: Partner? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading partner…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let p = partner { detailCard(p); subscreenLinks(p) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · PARTNER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(partner?.name ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func detailCard(_ p: Partner) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: dashIfEmpty(p.kind?.uppercased()), icon: "person.2")
            LifecycleRow(label: "USDOT",          value: dashIfEmpty(p.dotNumber))
            LifecycleRow(label: "MC",             value: dashIfEmpty(p.mcNumber))
            LifecycleRow(label: "Partner since",   value: humanISO(p.relationshipSince, format: "MMM d, yyyy"))
            LifecycleRow(label: "Active loads",    value: "\(p.activeLoads ?? 0)")
            LifecycleRow(label: "Lifetime spend",  value: usd(p.lifetimeSpend))
            LifecycleRow(label: "Agreements",      value: "\(p.agreementsCount ?? 0)")
        }
    }

    private func subscreenLinks(_ p: Partner) -> some View {
        VStack(spacing: 8) {
            link(icon: "doc.append", label: "Partner agreements", screen: "435", id: p.id)
            link(icon: "list.bullet", label: "Loads with this partner", screen: "282", id: p.id)
            link(icon: "checkmark.shield", label: "Compliance peek", screen: "284", id: p.id)
        }
    }

    private func link(icon: String, label: String, screen: String, id: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screen, "partnerId": id, "catalystId": id])
        } label: {
            LifecycleCard {
                HStack {
                    Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                    Text(label).font(EType.body).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
            }
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let id: String }
        do {
            let p: Partner = try await EusoTripAPI.shared.api.query("partners.getById", input: In(id: partnerId))
            partner = p
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("434 · Partner · Night") { PartnerDetailScreen(theme: Theme.dark, partnerId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("434 · Partner · Afternoon") { PartnerDetailScreen(theme: Theme.light, partnerId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
