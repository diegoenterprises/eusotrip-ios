//
//  259_PostLoadTemplates.swift
//  EusoTrip — Shipper · Post-a-Load · Templates picker.
//
//  Lists saved load templates the shipper can pre-fill. Backed by
//  `loadTemplates.list` (existing on web platform). When the picked
//  template lands, fields snap into the active draft and the wizard
//  jumps back to step 1.
//

import SwiftUI

struct PostLoadTemplatesScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { TemplatesBody(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

private struct LoadTemplate: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let origin: String?
    let destination: String?
    let cargoType: String?
    let equipmentType: String?
    let rate: Double?
    let weight: Double?
    let notes: String?
}

private struct TemplatesBody: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    @State private var templates: [LoadTemplate] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                contentCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await loadTemplates() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · POST A LOAD · TEMPLATES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pick a template").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Saved load templates pre-fill the wizard. Lane templates are managed in 211 Settings → Lane templates.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var contentCard: some View {
        if loading {
            LifecycleCard {
                LifecycleSection(label: "TEMPLATES", icon: "tray")
                Text("Loading templates…").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) {
                LifecycleSection(label: "ERROR", icon: "exclamationmark.triangle.fill")
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if templates.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "NO TEMPLATES", icon: "tray")
                Text("No saved templates yet. Save one from the Review screen the next time you post a load.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            ForEach(templates) { tpl in
                Button {
                    apply(tpl)
                } label: {
                    LifecycleCard {
                        LifecycleSection(label: tpl.name.uppercased(), icon: "doc.text")
                        LifecycleRow(label: "Origin",      value: dashIfEmpty(tpl.origin))
                        LifecycleRow(label: "Destination", value: dashIfEmpty(tpl.destination))
                        LifecycleRow(label: "Cargo",       value: dashIfEmpty(tpl.cargoType))
                        LifecycleRow(label: "Equipment",   value: dashIfEmpty(tpl.equipmentType))
                        LifecycleRow(label: "Rate",        value: usd(tpl.rate))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func apply(_ tpl: LoadTemplate) {
        draft.origin = tpl.origin ?? ""
        draft.destination = tpl.destination ?? ""
        draft.equipmentType = tpl.equipmentType ?? ""
        draft.weight = tpl.weight
        draft.rate = tpl.rate
        draft.notes = tpl.notes ?? ""
        if let raw = tpl.cargoType, let c = PostLoadDraft.CargoType(rawValue: raw) {
            draft.cargoType = c
        }
        NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "250"])
    }

    private func loadTemplates() async {
        loading = true; loadError = nil
        do {
            let rs: [LoadTemplate] = try await EusoTripAPI.shared.queryNoInput("loadTemplates.list")
            templates = rs
        } catch {
            // Endpoint may not be wired on iOS-side yet — surface a real
            // error so the empty-state message is honest. Server-side
            // exists per the web shipper menu's "Load Templates" entry.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("259 · Templates · Night") {
    PostLoadTemplatesScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("259 · Templates · Afternoon") {
    PostLoadTemplatesScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
