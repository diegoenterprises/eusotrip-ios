//
//  341_LaneTemplatesList.swift
//  EusoTrip — Shipper · Lane templates list (Arc K).
//

import SwiftUI

struct LaneTemplatesListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { LaneTemplatesListBody() } nav: { shipperLifecycleNav() }
    }
}

private struct LaneTemplate: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let origin: String?
    let destination: String?
    let cargoType: String?
    let equipmentType: String?
    let isFavorite: Bool?
}

private struct LaneTemplatesListBody: View {
    @Environment(\.palette) private var palette
    @State private var templates: [LaneTemplate] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                addButton
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LANE TEMPLATES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Lane templates").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading templates…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if templates.isEmpty { EusoEmptyState(systemImage: "tray", title: "No templates", subtitle: "Save lanes from the post-a-load wizard to populate this list.") }
        else {
            ForEach(templates) { tpl in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "342", "templateId": tpl.id])
                } label: {
                    LifecycleCard(accentGradient: tpl.isFavorite == true) {
                        HStack {
                            Image(systemName: tpl.isFavorite == true ? "star.fill" : "doc.text")
                                .foregroundStyle(LinearGradient.diagonal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tpl.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                Text("\(dashIfEmpty(tpl.origin)) → \(dashIfEmpty(tpl.destination))").font(EType.caption).foregroundStyle(palette.textSecondary)
                                Text(dashIfEmpty(tpl.cargoType?.uppercased())).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var addButton: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "342", "templateId": "new"])
        } label: {
            Text("Create template").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [LaneTemplate] = try await EusoTripAPI.shared.queryNoInput("loadTemplates.list")
            templates = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("341 · Lane templates · Night") { LaneTemplatesListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("341 · Lane templates · Afternoon") { LaneTemplatesListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
