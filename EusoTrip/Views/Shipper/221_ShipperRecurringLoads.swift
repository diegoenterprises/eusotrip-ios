//
//  221_ShipperRecurringLoads.swift
//  EusoTrip 2027 UI — brick 221 (shipper · recurring lanes)
//
//  Recurring / dedicated-lane manager. Mirrors the surface the web
//  `RecurringLoadScheduler.tsx` exposes: shipper's saved lane
//  configurations + one-tap post from a template + favorites filter.
//
//  Wires `loadTemplates.list` (read) + `shippers.create` (post-now
//  mutation, reuses 204's CargoType enum). The web 5-step wizard
//  (overview → schedule → hos → agreement → review) is deferred to
//  desktop: the ⚡ "Schedule on web" CTA fires `MeAction.fire(
//  "shipper.recurring.schedule")` which the chrome can route to a
//  Continuity hand-off.
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperRecurringLoadsStore: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case loaded([LoadTemplatesAPI.Template])
        case error(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published var search: String = ""
    @Published var filter: Filter = .all
    @Published var posting: Set<Int> = []
    @Published var lastAck: ShipperAPI.PostLoadAck? = nil
    @Published var lastError: String? = nil

    enum Filter: String, CaseIterable, Identifiable {
        case all, favorites, archived
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all:        return "All"
            case .favorites:  return "Favorites"
            case .archived:   return "Archived"
            }
        }
    }

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        state = .loading
        do {
            let rows = try await api.loadTemplates.list(
                search: search.isEmpty ? nil : search,
                favoritesOnly: filter == .favorites ? true : nil,
                includeArchived: filter == .archived ? true : nil
            )
            let visible = (filter == .archived)
                ? rows.filter { $0.isArchived == true }
                : rows.filter { $0.isArchived != true }
            state = .loaded(visible)
        } catch {
            state = .error("Couldn't load saved lanes.")
        }
    }

    func post(template t: LoadTemplatesAPI.Template) async {
        posting.insert(t.id)
        defer { posting.remove(t.id) }
        let originPair = Self.cityState(t.origin)
        let destPair   = Self.cityState(t.destination)
        guard !originPair.isEmpty, !destPair.isEmpty else {
            lastError = "Template missing origin or destination."
            return
        }
        let raw    = (t.cargoType ?? "general").lowercased()
        let cargo  = ShipperAPI.CargoType(rawValue: raw) ?? .general
        let rate: Double?   = t.rate.flatMap { Double($0) }
        let weight: Double? = t.weight.flatMap { Double($0) }
        do {
            let ack = try await api.shipper.create(
                origin: originPair,
                destination: destPair,
                cargoType: cargo,
                rate: rate,
                weight: weight,
                notes: t.description,
                pickupDate: nil
            )
            lastAck = ack
            lastError = nil
            await load()
        } catch {
            lastError = "Couldn't post load. Try again."
        }
    }

    private static func cityState(_ loc: LoadTemplatesAPI.Template.Location?) -> String {
        guard let loc else { return "" }
        let c = (loc.city ?? "").trimmingCharacters(in: .whitespaces)
        let s = (loc.state ?? "").trimmingCharacters(in: .whitespaces)
        if !c.isEmpty && !s.isEmpty { return "\(c), \(s)" }
        if !c.isEmpty { return c }
        if !s.isEmpty { return s }
        return ""
    }
}

// MARK: - Brick

struct ShipperRecurringLoads: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperRecurringLoadsStore()
    @State private var detail: LoadTemplatesAPI.Template? = nil
    @State private var showAck: Bool = false

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
        .onChange(of: store.filter) { _, _ in Task { await store.load() } }
        .onChange(of: store.lastAck?.id ?? -1) { _, v in if v != -1 { showAck = true } }
        .sheet(item: $detail) { ShipperRecurringLoadDetail(template: $0).environmentObject(store) }
        .alert("Posted", isPresented: $showAck, actions: {
            Button("OK") { store.lastAck = nil }
        }, message: {
            if let ack = store.lastAck {
                Text("Load \(ack.loadNumber) is live on the board.")
            }
        })
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · RECURRING").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Saved lanes").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("Repost a dedicated lane in one tap. Mirrors web · `loadTemplates.list`.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                MeAction.fire("shipper.recurring.schedule", userInfo: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 11, weight: .heavy))
                    Text("Schedule").font(.system(size: 11, weight: .heavy))
                }.foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }.padding(.top, 4)
    }

    private var statsHero: some View {
        let rows: [LoadTemplatesAPI.Template] = {
            if case .loaded(let r) = store.state { return r } else { return [] }
        }()
        let favoriteCount = rows.filter { $0.isFavorite == true }.count
        let totalUses = rows.reduce(0) { $0 + ($1.useCount ?? 0) }
        return HStack(spacing: Space.s2) {
            statTile(label: "LANES", value: "\(rows.count)", color: nil)
            statTile(label: "FAVORITES", value: "\(favoriteCount)", color: Brand.warning)
            statTile(label: "TOTAL POSTS", value: "\(totalUses)", color: Brand.success)
        }
    }

    private func statTile(label: String, value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient.diagonal))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var searchAndFilter: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textTertiary)
                TextField("Search lanes / commodities", text: $store.search)
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

            HStack(spacing: 6) {
                ForEach(ShipperRecurringLoadsStore.Filter.allCases) { f in
                    chip(label: f.label, active: store.filter == f) { store.filter = f }
                }
                Spacer()
            }
        }
    }

    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, Space.s3).padding(.vertical, 7)
                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                .background(Capsule().fill(active ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)) : AnyShapeStyle(palette.bgCard)))
                .overlay(Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var listSection: some View {
        switch store.state {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Loading lanes…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded(let rows):
            if rows.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        Button { detail = row } label: { templateRow(row) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func templateRow(_ t: LoadTemplatesAPI.Template) -> some View {
        let lane = "\(t.origin?.city ?? t.origin?.state ?? "—") → \(t.destination?.city ?? t.destination?.state ?? "—")"
        let isFav = t.isFavorite == true
        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Image(systemName: isFav ? "star.fill" : "tray.full")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(isFav ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(LinearGradient.diagonal))
                    .frame(width: 32, height: 32)
                    .background(palette.bgCardSoft).clipShape(Circle())
                    .overlay(Circle().strokeBorder(palette.borderFaint))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(t.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(lane).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                HStack(spacing: 6) {
                    if let eq = t.equipmentType { miniPill(eq.replacingOccurrences(of: "_", with: " ")) }
                    if let c = t.cargoType { miniPill(c) }
                    if let count = t.useCount, count > 0 {
                        Text("\(count)x").font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.post(template: t) }
            } label: {
                HStack(spacing: 4) {
                    if store.posting.contains(t.id) {
                        ProgressView().scaleEffect(0.55).tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill").font(.system(size: 10, weight: .heavy))
                    }
                    Text(store.posting.contains(t.id) ? "Posting" : "Post").font(.system(size: 11, weight: .heavy))
                }.foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.posting.contains(t.id))
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func miniPill(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.6)
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.full").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No saved lanes yet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Save a lane from PostLoad → ⋯ to repost it in one tap from here.")
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

// MARK: - Detail sheet

struct ShipperRecurringLoadDetail: View {
    let template: LoadTemplatesAPI.Template
    @EnvironmentObject private var store: ShipperRecurringLoadsStore
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                hero
                fields
                actions
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LANE TEMPLATE").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(template.name).font(.system(size: 24, weight: .heavy)).foregroundStyle(palette.textPrimary)
            HStack(spacing: 6) {
                if template.isFavorite == true {
                    miniPill("FAVORITE", color: Brand.warning)
                }
                if template.isArchived == true {
                    miniPill("ARCHIVED", color: Brand.danger)
                }
                if let count = template.useCount, count > 0 {
                    miniPill("\(count) POSTS", color: nil)
                }
            }
            if let d = template.description, !d.isEmpty {
                Text(d).font(EType.body).foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Origin", "\(template.origin?.city ?? "—") · \(template.origin?.state ?? "—")")
            row("Destination", "\(template.destination?.city ?? "—") · \(template.destination?.state ?? "—")")
            if let d = template.distance { row("Distance", "\(d) mi") }
            if let c = template.commodity { row("Commodity", c) }
            if let c = template.cargoType { row("Cargo type", c) }
            if let e = template.equipmentType { row("Equipment", e.replacingOccurrences(of: "_", with: " ")) }
            if let t = template.trailerType { row("Trailer", t) }
            if let w = template.weight { row("Weight", "\(w) \(template.weightUnit ?? "lb")") }
            if let q = template.quantity { row("Quantity", "\(q) \(template.quantityUnit ?? "")") }
            if let h = template.hazmatClass { row("Hazmat class", h) }
            if let u = template.unNumber { row("UN #", u) }
            if let r = template.rate { row("Saved rate", "$\(r)") }
            if let lu = template.lastUsedAt { row("Last used", relative(lu)) }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary).frame(width: 110, alignment: .leading)
            Text(v).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await store.post(template: template)
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if store.posting.contains(template.id) {
                        ProgressView().scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill").font(.system(size: 13, weight: .heavy))
                    }
                    Text(store.posting.contains(template.id) ? "Posting…" : "Post this lane now")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.posting.contains(template.id))

            Button {
                MeAction.fire("shipper.recurring.schedule", userInfo: ["templateId": template.id])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 12, weight: .heavy))
                    Text("Schedule recurring on web").font(.system(size: 12, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .foregroundStyle(palette.textPrimary).background(palette.bgCard)
                .overlay(Capsule().strokeBorder(palette.borderFaint))
                .clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    private func miniPill(_ s: String, color: Color?) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color ?? palette.textTertiary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(palette.bgCardSoft.opacity(0.6)))
            .overlay(Capsule().strokeBorder((color ?? palette.borderFaint).opacity(0.5)))
    }

    private func relative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let secs = Date().timeIntervalSince(d)
        if secs < 3600 { return "\(Int(secs/60)) min ago" }
        if secs < 86400 { return "\(Int(secs/3600)) h ago" }
        return "\(Int(secs/86400)) d ago"
    }
}

// MARK: - Previews

#Preview("Recurring · Dark") {
    ShipperRecurringLoads().preferredColorScheme(.dark)
}

#Preview("Recurring · Light") {
    ShipperRecurringLoads().preferredColorScheme(.light)
}
