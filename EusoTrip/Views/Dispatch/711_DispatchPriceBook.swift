//
//  711_DispatchPriceBook.swift
//  EusoTrip — Dispatch · Price book (rate sheet + FSC + min charge).
//
//  Mirrors Dispatch Commodity's "Price Book" — rate type variants
//  (per_mile / flat / per_barrel / per_gallon / per_ton), fuel-surcharge
//  config, billable wait time. Wired to pricebook.getEntries +
//  pricebook.lookupRate. Hazmat / cargoType / lane filters built in for
//  full vertical + product parity per founder doctrine.
//

import SwiftUI

struct DispatchPriceBookScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { PriceBookBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct PricebookEntry: Decodable, Identifiable, Hashable {
    let id: Int
    let entryName: String
    let originCity: String?
    let originState: String?
    let destinationCity: String?
    let destinationState: String?
    let cargoType: String?
    let hazmatClass: String?
    let rateType: String
    let rate: String?           // returned as decimal string from drizzle
    let fscIncluded: Int?
    let fscMethod: String?
    let fscValue: String?
    let minimumCharge: String?
    let effectiveDate: String?
    let expirationDate: String?
    let isActive: Int?
}

private struct EntriesResponse: Decodable, Hashable { let entries: [PricebookEntry] }

private struct PriceBookBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [PricebookEntry] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var cargoFilter: String = ""
    @State private var hazmatFilter: String = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterCard
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · PRICE BOOK").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Rate sheet").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Per-mile · flat · per-barrel · per-gallon · per-ton. FSC + min charge baked in.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var filterCard: some View {
        LifecycleCard {
            LifecycleSection(label: "FILTERS", icon: "line.3.horizontal.decrease.circle")
            HStack(spacing: 8) {
                TextField("Cargo type", text: $cargoFilter)
                    .textFieldStyle(.plain).font(EType.body)
                    .padding(8).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .onSubmit { Task { await load() } }
                TextField("Hazmat class", text: $hazmatFilter)
                    .textFieldStyle(.plain).font(EType.body)
                    .padding(8).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .onSubmit { Task { await load() } }
                Button { Task { await load() } } label: {
                    Text("Apply").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading rate sheet…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty {
            EusoEmptyState(systemImage: "book.closed", title: "No rate entries", subtitle: "Add a price book entry on the web to seed this view.")
        } else {
            ForEach(rows) { e in
                LifecycleCard(accentDanger: e.hazmatClass != nil) {
                    LifecycleSection(label: e.entryName.uppercased(), icon: "doc.text.fill")
                    LifecycleRow(label: "Lane",         value: lane(e))
                    LifecycleRow(label: "Cargo",        value: dashIfEmpty(e.cargoType))
                    if let h = e.hazmatClass, !h.isEmpty { LifecycleRow(label: "Hazmat", value: h) }
                    LifecycleRow(label: "Rate type",    value: e.rateType.uppercased())
                    LifecycleRow(label: "Rate",         value: usdString(e.rate) + suffix(for: e.rateType))
                    LifecycleRow(label: "Min charge",   value: usdString(e.minimumCharge))
                    LifecycleRow(label: "FSC",          value: fscDescription(e))
                    LifecycleRow(label: "Effective",    value: dashIfEmpty(e.effectiveDate))
                    LifecycleRow(label: "Expires",      value: dashIfEmpty(e.expirationDate))
                }
            }
        }
    }

    private func lane(_ e: PricebookEntry) -> String {
        let o = [e.originCity, e.originState].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let d = [e.destinationCity, e.destinationState].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if o.isEmpty && d.isEmpty { return "—" }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }

    private func suffix(for rateType: String) -> String {
        switch rateType {
        case "per_mile": return " /mi"
        case "per_barrel": return " /bbl"
        case "per_gallon": return " /gal"
        case "per_ton": return " /ton"
        default: return ""
        }
    }

    private func usdString(_ s: String?) -> String {
        guard let s = s, let v = Double(s) else { return "—" }
        return usd(v)
    }

    private func fscDescription(_ e: PricebookEntry) -> String {
        guard (e.fscIncluded ?? 0) == 1, let m = e.fscMethod, let v = e.fscValue else { return "—" }
        return "\(m.uppercased()) · \(v)"
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable {
            let cargoType: String?
            let hazmatClass: String?
            let isActive: Bool?
        }
        let cargo = cargoFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let haz = hazmatFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let r: EntriesResponse = try await EusoTripAPI.shared.api.query("pricebook.getEntries", input: In(
                cargoType: cargo.isEmpty ? nil : cargo,
                hazmatClass: haz.isEmpty ? nil : haz,
                isActive: true
            ))
            rows = r.entries
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("711 · Price book · Night") { DispatchPriceBookScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("711 · Price book · Afternoon") { DispatchPriceBookScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
