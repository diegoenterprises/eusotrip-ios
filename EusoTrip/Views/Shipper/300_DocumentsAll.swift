//
//  300_DocumentsAll.swift
//  EusoTrip — Shipper · Documents (Arc H).
//  Backed by `documents.getAll` + `documents.getStats`.
//

import SwiftUI

struct DocumentsAllScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DocumentsAllBody() } nav: { shipperLifecycleNav() }
    }
}

private struct DocumentsAllBody: View {
    @Environment(\.palette) private var palette
    @State private var docs: [DocRow] = []
    @State private var stats: DocStats? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var search: String = ""
    @State private var category: String? = nil

    private let categories = [nil, "BOL", "POD", "Rate-Con", "Insurance", "Permit", "Other"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                searchBar
                if let s = stats { statsRow(s) }
                filterStrip
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · DOCUMENTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Documents").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var searchBar: some View {
        TextField("Search docs", text: $search)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onSubmit { Task { await load() } }
    }

    private func statsRow(_ s: DocStats) -> some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "TOTAL",   value: "\(s.total)", icon: "doc")
            LifecycleStatTile(label: "VALID",   value: "\(s.valid)", icon: "checkmark.circle")
            LifecycleStatTile(label: "EXPIRING", value: "\(s.expiring)", icon: "exclamationmark.circle", danger: s.expiring > 0)
            LifecycleStatTile(label: "EXPIRED",  value: "\(s.expired)", icon: "xmark.circle", danger: s.expired > 0)
        }
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories, id: \.self) { cat in
                    Button { Task { category = cat; await load() } } label: {
                        Text(cat ?? "All").font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(category == cat ? .white : palette.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(category == cat ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading documents…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if docs.isEmpty { EusoEmptyState(systemImage: "doc", title: "No documents", subtitle: "Run tickets, BOLs, PODs, and rate-cons land here as your loads progress.") }
        else {
            ForEach(docs) { d in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "301", "docId": d.id])
                } label: {
                    LifecycleCard {
                        HStack {
                            Image(systemName: iconFor(d.category)).foregroundStyle(LinearGradient.diagonal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                                Text("\(dashIfEmpty(d.category)) · \(humanISO(d.uploadedAt, format: "MMM d"))").font(EType.caption).foregroundStyle(palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Text(dashIfEmpty(d.status?.uppercased())).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                            Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func iconFor(_ category: String?) -> String {
        switch (category ?? "").lowercased() {
        case "bol":      return "doc.text"
        case "pod":      return "photo"
        case "rate-con", "rate_con": return "doc.richtext"
        case "insurance": return "checkmark.shield"
        case "permit":   return "ticket"
        default:         return "doc"
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let search: String?; let category: String? }
        do {
            async let d: [DocRow]      = EusoTripAPI.shared.query("documents.getAll", input: In(search: search.isEmpty ? nil : search, category: category))
            async let s: DocStats      = EusoTripAPI.shared.queryNoInput("documents.getStats")
            docs  = try await d
            stats = (try? await s)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

private struct DocRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String?
    let status: String?
    let uploadedAt: String?
}

private struct DocStats: Decodable, Hashable {
    let total: Int
    let active: Int
    let valid: Int
    let expiring: Int
    let expired: Int
}

#Preview("300 · Documents · Night") {
    DocumentsAllScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("300 · Documents · Afternoon") {
    DocumentsAllScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
