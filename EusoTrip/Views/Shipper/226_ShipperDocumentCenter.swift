//
//  226_ShipperDocumentCenter.swift
//  EusoTrip 2027 UI — brick 226 (shipper · documents)
//
//  Documents Center. Mirrors the shipper-relevant slice of the web
//  `DocumentCenter.tsx` (`/document-center`) — search + category
//  filter + status-grouped grid + tap-to-preview. BOLs, agreements,
//  insurance certs, W9s, run-tickets all live in the same store.
//
//  Wires:
//    • `documents.getAll(search:category:)`
//    • `documents.getStats()`
//    • `documents.getCategories()`
//    • `documents.delete(id:)` — exposed via swipe-action on row.
//
//  Preview & file-fetch are deferred to the chrome (Continuity hand-
//  off via `MeAction.fire("shipper.document.preview", userInfo:)`)
//  to avoid bundling another PDF-viewer dependency in this brick.
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperDocumentCenterStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var search: String = ""
    @Published var category: String? = nil
    @Published private(set) var documents: [DocumentsAPI.Document] = []
    @Published private(set) var stats: DocumentsAPI.Stats? = nil
    @Published private(set) var categories: [DocumentsAPI.Category] = []
    @Published private(set) var deleting: Set<String> = []

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        async let docs = api.documents.getAll(search: search.isEmpty ? nil : search,
                                              category: category)
        async let stats: DocumentsAPI.Stats? = (try? await api.documents.getStats()) ?? nil
        async let cats: [DocumentsAPI.Category] = (try? await api.documents.getCategories()) ?? []
        do {
            self.documents  = try await docs
            self.stats      = await stats
            self.categories = await cats
            self.phase      = .loaded
        } catch {
            self.phase = .error("Couldn't load documents.")
        }
    }

    func delete(id: String) async {
        deleting.insert(id)
        defer { deleting.remove(id) }
        _ = try? await api.documents.delete(id: id)
        await load()
    }
}

// MARK: - Brick

struct ShipperDocumentCenter: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperDocumentCenterStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                statsHero
                searchAndFilter
                listSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.load() }
        .onChange(of: store.category) { _, _ in Task { await store.load() } }
        .refreshable { await store.load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "folder.fill").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · DOCUMENTS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Document center").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("BOL · agreements · insurance · W9 · run-tickets in one place.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                MeAction.fire("shipper.document.upload", userInfo: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.up.fill").font(.system(size: 11, weight: .heavy))
                    Text("Upload").font(.system(size: 11, weight: .heavy))
                }.foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }.padding(.top, 4)
    }

    private var statsHero: some View {
        let s = store.stats
        return HStack(spacing: Space.s2) {
            statTile(label: "TOTAL", value: "\(s?.total ?? 0)", color: nil)
            statTile(label: "ACTIVE", value: "\(s?.active ?? 0)", color: Brand.success)
            statTile(label: "EXPIRING", value: "\(s?.expiring ?? 0)", color: Brand.warning)
            statTile(label: "EXPIRED", value: "\(s?.expired ?? 0)", color: Brand.danger)
        }
    }

    private func statTile(label: String, value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient.diagonal))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var searchAndFilter: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textTertiary)
                TextField("Search documents", text: $store.search)
                    .textFieldStyle(.plain).font(EType.body).foregroundStyle(palette.textPrimary)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onSubmit { Task { await store.load() } }
                if !store.search.isEmpty {
                    Button {
                        store.search = ""
                        Task { await store.load() }
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                            .foregroundStyle(palette.textTertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: "All", count: store.stats?.total, active: store.category == nil) {
                        store.category = nil
                    }
                    ForEach(store.categories) { c in
                        chip(label: c.name, count: c.count, active: store.category == c.id) {
                            store.category = c.id
                        }
                    }
                }
            }
        }
    }

    private func chip(label: String, count: Int?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 11, weight: .heavy))
                if let c = count {
                    Text("\(c)").font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 7)
            .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
            .background(Capsule().fill(active ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)) : AnyShapeStyle(palette.bgCard)))
            .overlay(Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var listSection: some View {
        switch store.phase {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Loading documents…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded:
            if store.documents.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(store.documents) { d in
                        documentRow(d)
                    }
                }
            }
        }
    }

    private func documentRow(_ d: DocumentsAPI.Document) -> some View {
        let style = DocumentStatusStyle.from(d.status)
        let glyph = categoryGlyph(d.category)
        return Button {
            MeAction.fire("shipper.document.preview", userInfo: ["documentId": d.id])
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: glyph).font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(d.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                        statusPill(style.label, color: style.color)
                    }
                    HStack(spacing: 6) {
                        miniPill(d.category.uppercased())
                        if !d.uploadedAt.isEmpty {
                            Text("Uploaded \(d.uploadedAt)").font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                if store.deleting.contains(d.id) {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button {
                        Task { await store.delete(id: d.id) }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Brand.danger.opacity(0.7))
                            .padding(8)
                    }.buttonStyle(.plain)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func categoryGlyph(_ c: String) -> String {
        switch c.lowercased() {
        case "permits":     return "lock.shield.fill"
        case "insurance":   return "checkmark.shield.fill"
        case "compliance":  return "checkmark.seal.fill"
        case "contracts":   return "doc.text.fill"
        case "invoices":    return "creditcard.fill"
        case "bols":        return "shippingbox.fill"
        case "tickets":     return "ticket.fill"
        default:            return "doc.fill"
        }
    }

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private func miniPill(_ s: String) -> some View {
        Text(s).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.5)
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.fill").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No documents yet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Tap Upload to add your first BOL, insurance cert, or W9.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4).frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - status

private struct DocumentStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String) -> DocumentStatusStyle {
        switch raw.lowercased() {
        case "active":     return .init(label: "Active",   color: Brand.success)
        case "valid":      return .init(label: "Valid",    color: Brand.success)
        case "expiring":   return .init(label: "Expiring", color: Brand.warning)
        case "expired":    return .init(label: "Expired",  color: Brand.danger)
        case "pending":    return .init(label: "Pending",  color: Brand.info)
        case "rejected":   return .init(label: "Rejected", color: Brand.danger)
        default:           return .init(label: raw.capitalized, color: .gray)
        }
    }
}

// MARK: - Previews

#Preview("Documents · Dark") {
    ShipperDocumentCenter().preferredColorScheme(.dark)
}

#Preview("Documents · Light") {
    ShipperDocumentCenter().preferredColorScheme(.light)
}
