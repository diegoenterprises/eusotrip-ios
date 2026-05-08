//
//  327_HazmatAudit.swift
//  EusoTrip — Shipper · Hazmat audit (Arc J).
//

import SwiftUI

struct HazmatAuditScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { HazmatAuditBody() } nav: { shipperLifecycleNav() }
    }
}

private struct HazmatRow: Decodable, Identifiable, Hashable {
    let id: String
    let loadId: String?
    let loadNumber: String?
    let unNumber: String?
    let hazmatClass: String?
    let date: String?
    let originCountry: String?
    let destinationCountry: String?
    let manifestUrl: String?
}

private struct HazmatAuditBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [HazmatRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var presentedPDF: EusoPDFPresentation? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .fullScreenCover(item: $presentedPDF) { p in
            EusoPDFViewer(title: p.title, subtitle: p.subtitle, source: .url(p.url))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "triangle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("SHIPPER · HAZMAT AUDIT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.warning)
            }
            Text("Hazmat audit log").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("5-year retention per 49 CFR 172.201. Tap a row to open the manifest.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard {
                HStack(spacing: 8) {
                    ProgressView().tint(LinearGradient.diagonal).scaleEffect(0.8)
                    Text("Loading hazmat history…").font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
                        Text("Couldn't load hazmat audit").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    }
                    Text(err).font(EType.caption).foregroundStyle(palette.textTertiary).lineLimit(2)
                    Button { Task { await load() } } label: {
                        Text("Retry").font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(LinearGradient.diagonal))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        else if rows.isEmpty { EusoEmptyState(systemImage: "triangle", title: "No hazmat history", subtitle: "Hazmat loads aren't on file in the audit window.") }
        else {
            ForEach(rows) { r in
                Button {
                    if let url = r.manifestUrl, let u = URL(string: url) {
                        presentedPDF = EusoPDFPresentation(
                            url: u,
                            title: "Hazmat manifest",
                            subtitle: r.loadNumber
                        )
                    }
                    else if let lid = r.loadId {
                        NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "205", "loadId": lid])
                    }
                } label: {
                    LifecycleCard(accentWarning: true) {
                        LifecycleSection(label: dashIfEmpty(r.loadNumber?.uppercased()), icon: "doc.text")
                        LifecycleRow(label: "UN",         value: dashIfEmpty(r.unNumber))
                        LifecycleRow(label: "Class",      value: dashIfEmpty(r.hazmatClass))
                        LifecycleRow(label: "Date",       value: humanISO(r.date, format: "MMM d, yyyy"))
                        LifecycleRow(label: "Origin",     value: dashIfEmpty(r.originCountry))
                        LifecycleRow(label: "Destination", value: dashIfEmpty(r.destinationCountry))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [HazmatRow] = try await EusoTripAPI.shared.queryNoInput("hazmat.getShipperAuditTrail")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("327 · Hazmat audit · Night") { HazmatAuditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("327 · Hazmat audit · Afternoon") { HazmatAuditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
