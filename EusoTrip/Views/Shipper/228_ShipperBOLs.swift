//
//  228_ShipperBOLs.swift
//  EusoTrip 2027 UI — brick 228 (shipper · BOLs)
//
//  Bills of Lading list + generate-from-load + PDF view. Mirrors
//  the shipper-relevant slice of the web `BOLGeneration.tsx` and
//  `BOLManagement.tsx` (`/bol`). Same backing as the driver-side
//  EusoTicket BOL stack — just lensed to the shipper's perspective
//  (BOLs the shipper authored / co-signed, not just ones a driver
//  picked up).
//
//  Wires:
//    • `eusoTicket.listBOLs(status:limit:)`
//    • `bol.generateBOLFromLoad(loadId:)` (re-exported as
//      `EusoTicketAPI.generateBOLFromLoad`)
//    • `eusoTicket.generateBOLPDF(bolNumber:)` for the inline PDF
//      hand-off (uses the same SFSafariView path the driver brick
//      already established at 106 MeEusoTickets).
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperBOLsStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded(EusoTicketAPI.BOLList)
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var statusFilter: String? = nil
    @Published private(set) var generatingFor: Int? = nil
    @Published var lastBOL: EusoTicketAPI.GeneratedBOL? = nil
    @Published var lastError: String? = nil

    static let statusFilters: [(String?, String)] = [
        (nil, "All"),
        ("active", "Active"),
        ("delivered", "Delivered"),
        ("voided", "Voided"),
    ]

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let r = try await api.eusoTicket.listBOLs(status: statusFilter, limit: 50)
            phase = .loaded(r)
        } catch {
            phase = .error("Couldn't load BOLs.")
        }
    }

    func generate(loadId: Int) async {
        generatingFor = loadId
        defer { generatingFor = nil }
        do {
            let b = try await api.eusoTicket.generateBOLFromLoad(loadId: loadId)
            lastBOL = b
            await load()
        } catch {
            lastError = "Couldn't generate BOL."
        }
    }
}

// MARK: - Brick

struct ShipperBOLs: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperBOLsStore()
    @State private var generateLoadId: String = ""
    @State private var showGenerateSheet: Bool = false
    @State private var showAck: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                statsHero
                filterRow
                listSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
        .task { await store.load() }
        .onChange(of: store.statusFilter) { _, _ in Task { await store.load() } }
        .refreshable { await store.load() }
        // RealtimeService → live updates refresh the BOL list when
        // upstream load events flip a BOL into available/expired,
        // when a new BOL is generated, or when POD lands.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await store.load() }
        }
        .sheet(isPresented: $showGenerateSheet) { generateSheet }
        .onChange(of: store.lastBOL?.bolNumber ?? "") { _, v in if !v.isEmpty { showAck = true } }
        .alert("BOL generated", isPresented: $showAck, actions: {
            Button("OK") { store.lastBOL = nil }
        }, message: {
            if let b = store.lastBOL?.bolNumber { Text("New BOL: \(b)") }
        })
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.richtext.fill").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · BOLS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Bills of Lading").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("Generate from any load · view PDF · status timeline.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                showGenerateSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.rectangle.fill").font(.system(size: 11, weight: .heavy))
                    Text("Generate").font(.system(size: 11, weight: .heavy))
                }.foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }.padding(.top, 4)
    }

    private var statsHero: some View {
        let rows: [EusoTicketAPI.BOLRow] = {
            if case .loaded(let r) = store.phase { return r.bols } else { return [] }
        }()
        let total = (try? { () throws -> Int in
            if case .loaded(let r) = store.phase { return r.total } else { return rows.count }
        }()) ?? rows.count
        let active = rows.filter { $0.status.lowercased() == "active" }.count
        let delivered = rows.filter { $0.status.lowercased() == "delivered" }.count
        return HStack(spacing: Space.s2) {
            statTile(label: "TOTAL", value: "\(total)", color: nil)
            statTile(label: "ACTIVE", value: "\(active)", color: Brand.info)
            statTile(label: "DELIVERED", value: "\(delivered)", color: Brand.success)
        }
    }

    private func statTile(label: String, value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient.diagonal))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ShipperBOLsStore.statusFilters, id: \.1) { item in
                    chip(label: item.1, active: store.statusFilter == item.0) {
                        store.statusFilter = item.0
                    }
                }
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
        switch store.phase {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Loading BOLs…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded(let r):
            if r.bols.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(r.bols) { row in bolRow(row) }
                }
            }
        }
    }

    private func bolRow(_ b: EusoTicketAPI.BOLRow) -> some View {
        let style = BOLStatusStyle.from(b.status)
        return Button {
            if let n = b.bolNumber {
                MeAction.fire("shipper.bol.preview", userInfo: ["bolNumber": n])
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text.fill").font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(b.bolNumber ?? "—")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textPrimary).lineLimit(1)
                        statusPill(style.label, color: style.color)
                    }
                    if let l = b.loadNumber {
                        Text("Load \(l)").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    HStack(spacing: 6) {
                        if let d = b.driverName {
                            Label(d, systemImage: "person.fill").font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(palette.textTertiary)
                        }
                        if let c = b.createdAt {
                            Text(String(c.prefix(10)))
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.fill.badge.plus").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No BOLs yet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Generate a BOL from any active load to start the chain of custody.")
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

    private var generateSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("GENERATE BOL").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("From a load").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("Type the load ID — server resolves shipper / consignee / commodity / hazmat fields automatically. Shape varies by cargo type (tanker / hazmat / reefer).")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("LOAD ID").font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
                    TextField("e.g. 12345", text: $generateLoadId)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain).padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                Button {
                    if let id = Int(generateLoadId) {
                        Task {
                            await store.generate(loadId: id)
                            showGenerateSheet = false
                            generateLoadId = ""
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if store.generatingFor != nil {
                            ProgressView().scaleEffect(0.6).tint(.white)
                        } else {
                            Image(systemName: "doc.badge.plus").font(.system(size: 13, weight: .heavy))
                        }
                        Text(store.generatingFor != nil ? "Generating…" : "Generate BOL")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(Int(generateLoadId) == nil || store.generatingFor != nil)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
    }
}

// MARK: - status

private struct BOLStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String) -> BOLStatusStyle {
        switch raw.lowercased() {
        case "active":     return .init(label: "Active",    color: Brand.info)
        case "delivered":  return .init(label: "Delivered", color: Brand.success)
        case "in_transit": return .init(label: "In transit",color: Brand.warning)
        case "voided":     return .init(label: "Voided",    color: Brand.danger)
        default:           return .init(label: raw.capitalized, color: .gray)
        }
    }
}

// MARK: - Previews

#Preview("BOLs · Dark") { ShipperBOLs().preferredColorScheme(.dark) }
#Preview("BOLs · Light") { ShipperBOLs().preferredColorScheme(.light) }
