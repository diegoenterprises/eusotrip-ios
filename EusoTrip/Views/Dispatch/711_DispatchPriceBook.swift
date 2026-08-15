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
                leading: DispatchNavRoute.leading(current: .me),
                trailing: DispatchNavRoute.trailing(current: .me),
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
    @State private var showingCreateEntry = false

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
        .eusoRefreshable { await load() }
        .sheet(isPresented: $showingCreateEntry) {
            PriceBookCreateEntrySheet {
                showingCreateEntry = false
                Task { await load() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · PRICE BOOK").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Text("Rate sheet").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Button { showingCreateEntry = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add rate entry")
            }
            Text("Per-mile · flat · per-barrel · per-gallon · per-ton. FSC + min charge baked in.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var filterCard: some View {
        LifecycleCard {
            LifecycleSection(label: "FILTERS", icon: "line.3.horizontal.decrease.circle")
            HStack(spacing: 8) {
                TextField("Cargo type", text: $cargoFilter)
                    .textFieldStyle(.plain).font(EType.body)
                    .padding(8).background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .onSubmit { Task { await load() } }
                TextField("Hazmat class", text: $hazmatFilter)
                    .textFieldStyle(.plain).font(EType.body)
                    .padding(8).background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
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
            LifecycleCard {
                VStack(spacing: Space.s3) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text("No rate entries")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Button { showingCreateEntry = true } label: {
                        Label("Add rate entry", systemImage: "plus.circle.fill")
                            .font(EType.bodyStrong)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s3)
                            .background(LinearGradient.diagonal)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
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
        if o.isEmpty && d.isEmpty { return "-" }
        return "\(o.isEmpty ? "-" : o) → \(d.isEmpty ? "-" : d)"
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
        guard let s = s, let v = Double(s) else { return "-" }
        return usd(v)
    }

    private func fscDescription(_ e: PricebookEntry) -> String {
        guard (e.fscIncluded ?? 0) == 1, let m = e.fscMethod, let v = e.fscValue else { return "-" }
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
            let r: EntriesResponse = try await EusoTripAPI.shared.query("pricebook.getEntries", input: In(
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

private struct PriceBookCreateEntrySheet: View {
    private enum RateType: String, CaseIterable, Identifiable {
        case perMile = "per_mile"
        case flat
        case perBarrel = "per_barrel"
        case perGallon = "per_gallon"
        case perTon = "per_ton"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .perMile: return "Per mile"
            case .flat: return "Flat"
            case .perBarrel: return "Per barrel"
            case .perGallon: return "Per gallon"
            case .perTon: return "Per ton"
            }
        }
    }

    private enum FSCMethod: String, CaseIterable, Identifiable {
        case percentage
        case perMile = "per_mile"
        case flat
        var id: String { rawValue }
        var label: String {
            switch self {
            case .percentage: return "Percent"
            case .perMile: return "Per mile"
            case .flat: return "Flat"
            }
        }
    }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    @State private var entryName = ""
    @State private var originCity = ""
    @State private var originState = ""
    @State private var destinationCity = ""
    @State private var destinationState = ""
    @State private var cargoType = ""
    @State private var hazmatClass = ""
    @State private var rateType: RateType = .perMile
    @State private var rate = ""
    @State private var minimumCharge = ""
    @State private var fscIncluded = false
    @State private var fscMethod: FSCMethod = .percentage
    @State private var fscValue = ""
    @State private var effectiveDate = Date()
    @State private var hasExpiration = false
    @State private var expirationDate = Date()
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    fieldGroup("ENTRY") {
                        textField("Entry name", text: $entryName)
                    }
                    fieldGroup("LANE") {
                        textField("Origin city", text: $originCity)
                        stateField("Origin state", text: $originState)
                        textField("Destination city", text: $destinationCity)
                        stateField("Destination state", text: $destinationState)
                    }
                    fieldGroup("FREIGHT") {
                        textField("Cargo or product type", text: $cargoType)
                        textField("Hazmat class, when applicable", text: $hazmatClass)
                    }
                    fieldGroup("RATE") {
                        Picker("Rate type", selection: $rateType) {
                            ForEach(RateType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        textField("Rate", text: $rate, keyboard: .decimalPad)
                        textField("Minimum charge", text: $minimumCharge, keyboard: .decimalPad)
                    }
                    fieldGroup("FUEL SURCHARGE") {
                        Toggle("Include fuel surcharge", isOn: $fscIncluded)
                            .tint(Brand.magenta)
                        if fscIncluded {
                            Picker("Method", selection: $fscMethod) {
                                ForEach(FSCMethod.allCases) { method in
                                    Text(method.label).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                            textField("FSC value", text: $fscValue, keyboard: .decimalPad)
                        }
                    }
                    fieldGroup("DATES") {
                        DatePicker("Effective", selection: $effectiveDate, displayedComponents: .date)
                        Toggle("Set expiration", isOn: $hasExpiration)
                            .tint(Brand.magenta)
                        if hasExpiration {
                            DatePicker("Expires", selection: $expirationDate, in: effectiveDate..., displayedComponents: .date)
                        }
                    }

                    if let saveError {
                        Text(saveError)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button { Task { await save() } } label: {
                        HStack(spacing: Space.s2) {
                            if saving { ProgressView().tint(.white) }
                            Text(saving ? "Saving…" : "Save rate entry")
                                .font(EType.bodyStrong)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s3)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                }
                .padding(Space.s4)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Add rate entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func fieldGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) { content() }
                .padding(Space.s3)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
        }
    }

    private func textField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .font(EType.body)
            .padding(Space.s2)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func stateField(_ title: String, text: Binding<String>) -> some View {
        textField(title, text: Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = String($0.uppercased().prefix(2)) }
        ))
    }

    private func trimmed(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func dateString(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    @MainActor
    private func save() async {
        saveError = nil
        guard let name = trimmed(entryName) else {
            saveError = "Enter a name for this rate entry."
            return
        }
        guard let rateValue = Double(rate), rateValue > 0 else {
            saveError = "Enter a rate greater than zero."
            return
        }
        let minimumValue: Double?
        if let minimum = trimmed(minimumCharge) {
            guard let parsed = Double(minimum), parsed >= 0 else {
                saveError = "Minimum charge must be zero or greater."
                return
            }
            minimumValue = parsed
        } else {
            minimumValue = nil
        }
        let surchargeValue: Double?
        if fscIncluded {
            guard let parsed = Double(fscValue), parsed >= 0 else {
                saveError = "Enter a valid fuel-surcharge value."
                return
            }
            surchargeValue = parsed
        } else {
            surchargeValue = nil
        }

        struct Input: Encodable {
            let entryName: String
            let originCity: String?
            let originState: String?
            let destinationCity: String?
            let destinationState: String?
            let cargoType: String?
            let hazmatClass: String?
            let rateType: String
            let rate: Double
            let fscIncluded: Bool
            let fscMethod: String?
            let fscValue: Double?
            let minimumCharge: Double?
            let effectiveDate: String
            let expirationDate: String?
        }
        struct Response: Decodable { let id: Int? }

        saving = true
        defer { saving = false }
        do {
            let _: Response = try await EusoTripAPI.shared.mutation("pricebook.createEntry", input: Input(
                entryName: name,
                originCity: trimmed(originCity),
                originState: trimmed(originState),
                destinationCity: trimmed(destinationCity),
                destinationState: trimmed(destinationState),
                cargoType: trimmed(cargoType),
                hazmatClass: trimmed(hazmatClass),
                rateType: rateType.rawValue,
                rate: rateValue,
                fscIncluded: fscIncluded,
                fscMethod: fscIncluded ? fscMethod.rawValue : nil,
                fscValue: surchargeValue,
                minimumCharge: minimumValue,
                effectiveDate: dateString(effectiveDate),
                expirationDate: hasExpiration ? dateString(expirationDate) : nil
            ))
            onCreated()
        } catch {
            saveError = error.eusoUserCopy
        }
    }
}

#Preview("711 · Price book · Night") { DispatchPriceBookScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("711 · Price book · Afternoon") { DispatchPriceBookScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
