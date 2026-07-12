//
//  794_VesselAccessorialRateConfig.swift
//  EusoTrip — Vessel Operator · Accessorial Rate Config (TARIFF-TABLE archetype).
//
//  Faithful port of "794 Vessel Accessorial Rate Config.svg" (Dark + Light). A
//  column-aligned, editable rate table — one tariff surface to set the demurrage /
//  detention / chassis / congestion / reefer day-rates and free-time every downstream
//  invoice prices from, so there is a single source of truth for accessorial pricing.
//  Distinct from the card/list vessel screens: a spreadsheet-grade tariff editor.
//
//  Nav: Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), COMPLIANCE inked.
//
//  REAL WIRING (tRPC · server/routers/detentionAccessorials.ts):
//    · detentionAccessorials.getAccessorialCatalog  {category?, search?}
//        -> { items:[{code, name, category, defaultRate, unit, freeTime, description}],
//              categories, total }  (:1434) — backs the rate rows.
//    · detentionAccessorials.configureAccessorialRate  {code, rate, freeTime?, customerId?}
//        -> { success, code, newRate, freeTime, effectiveDate }  (:1464 · mutation)
//        — the per-row edit + "Save tariff" verb. "Add rate" opens the full catalog
//        picker (same getAccessorialCatalog) to bring an unlisted code onto the sheet.
//
//  RBAC: protectedProcedure (desc: tighten to a vessel operator-admin gate). transportMode=
//  vessel · scope tariff-wide (ALL) — CUST-scope per-customer overrides are configured
//  from a booking (customerId), not this global sheet. COUNTRY-DONE: a tariff-jurisdiction
//  segmented control sets the authority + currency the table prices under — US FMC·MTO
//  tariff / USD (active) · CA CBSA·CTA / CAD · MX SAT·API maniobras+IVA / MXN (standby).
//  NAMED GAP for the-oath: vessel.getAccessorialRegime({country}) -> {tariffAuthority,
//  freeTimeBasis, currency}; it drives the active basis + adds country/currency to
//  configureAccessorialRate. NO mock data — every code, rate, free-time is a live row.
//

import SwiftUI

struct VesselAccessorialRateConfigScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselAccessorialRateConfigBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct AccessorialCatalog794: Decodable {
    let items: [AccessorialCatalogItem794]
    let total: Int?
}

private struct AccessorialCatalogItem794: Decodable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let category: String?
    let defaultRate: Double?
    let unit: String?
    let freeTime: Int?
    let description: String?
}

private struct ConfigureRateResult794: Decodable {
    let success: Bool?
    let code: String?
    let newRate: Double?
    let freeTime: Int?
    let effectiveDate: String?
}

/// A jurisdiction the tariff table can price under.
private enum TariffJurisdiction794: String, CaseIterable {
    case us = "US", ca = "CA", mx = "MX"
    var authority: String { self == .us ? "FMC · MTO tariff" : self == .ca ? "CBSA · CTA" : "SAT · API" }
    var currency: String { self == .us ? "USD" : self == .ca ? "CAD" : "MXN" }
    var active: Bool { self == .us }
}

// MARK: - Body

private struct VesselAccessorialRateConfigBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.vesselOperatorNavHandler) private var navHandler

    @State private var items: [AccessorialCatalogItem794] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    /// Per-code local edits (rate, freeTime) applied over the catalog defaults.
    @State private var edits: [String: RateEdit794] = [:]
    @State private var editingCode: String? = nil
    @State private var jurisdiction: TariffJurisdiction794 = .us

    @State private var saving = false
    @State private var saveAck: String? = nil
    @State private var saveError: String? = nil
    @State private var showCatalog = false

    /// The five headline tariff codes surfaced in the primary table (the SVG's
    /// DEM/DET/CHC/CON/RPM rows). The full catalog opens via "Add rate".
    private let primaryCodes = ["DEM", "DET", "CHC", "CON", "RPM"]

    private struct RateEdit794 { var rate: Double; var freeTime: Int }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        errorCard(err)
                    } else {
                        summaryCard
                        rateTable
                        jurisdictionCard
                        if let ack = saveAck { banner(ack, danger: false) }
                        if let err = saveError { banner(err, danger: true) }
                        ctaRow
                        if showCatalog { catalogSection }
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header (eyebrow + breadcrumb + title)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Text("✦").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("VESSEL OPERATOR · RATE CONFIG")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("PER CONTAINER").font(EType.mono(.micro)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Button { navHandler?("Compliance") } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                Text("Rate tariff")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s3)
        }
    }

    // MARK: Summary card (gradient-rim · code count + draft/live state)

    private var summaryCard: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Accessorial tariff")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("\(items.count) codes · priced in \(jurisdiction.currency)")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(edits.isEmpty ? "LIVE" : "DRAFT")
                .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                .foregroundStyle(edits.isEmpty ? Brand.success : Brand.warning)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill((edits.isEmpty ? Brand.success : Brand.warning).opacity(0.18)))
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing),
                          lineWidth: 1.5))
    }

    // MARK: Rate table (CODE · RATE · FREE · SCOPE + inline editor)

    private var rateTable: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RATE TABLE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("per container").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                // Column header.
                HStack {
                    Text("CODE").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("RATE").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary).frame(width: 66, alignment: .trailing)
                    Text("FREE").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary).frame(width: 40, alignment: .trailing)
                    Text("").frame(width: 26)
                }
                .padding(.horizontal, Space.s4).padding(.top, Space.s3).padding(.bottom, Space.s2)
                Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)

                let rows = tableRows
                if rows.isEmpty {
                    EusoEmptyState(systemImage: "tablecells",
                                   title: "Catalog unavailable",
                                   subtitle: "The accessorial code catalog populates the tariff table from the schedule.")
                        .padding(Space.s4)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, item in
                        rateRow(item)
                        if editingCode == item.code { inlineEditor(item) }
                        if idx < rows.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                        }
                    }
                }
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            Text("Rates apply at invoice generation · tariff-wide (ALL) scope · CUST overrides configured from a booking.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }

    private func rateRow(_ item: AccessorialCatalogItem794) -> some View {
        let rate = effectiveRate(item)
        let free = effectiveFree(item)
        let edited = edits[item.code] != nil
        return HStack(spacing: Space.s3) {
            Text(item.code)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 44, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.textPrimary.opacity(0.08)))
            Text(item.name)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: Space.s1)
            HStack(spacing: 2) {
                Text(rateText(rate))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(edited ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
                Text(unitSuffix(item.unit))
                    .font(.system(size: 9)).foregroundStyle(palette.textTertiary)
            }
            .frame(width: 72, alignment: .trailing)
            Text(free > 0 ? "\(free)\(freeUnit(item.unit))" : "—")
                .font(.system(size: 12)).monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .frame(width: 40, alignment: .trailing)
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    editingCode = (editingCode == item.code) ? nil : item.code
                }
            } label: {
                Image(systemName: editingCode == item.code ? "checkmark.circle.fill" : "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(editingCode == item.code ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            }
            .buttonStyle(.plain)
            .disabled(!jurisdiction.active)
            .frame(width: 26)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    private func inlineEditor(_ item: AccessorialCatalogItem794) -> some View {
        let binding = Binding<RateEdit794>(
            get: { edits[item.code] ?? RateEdit794(rate: item.defaultRate ?? 0, freeTime: item.freeTime ?? 0) },
            set: { edits[item.code] = $0 }
        )
        return VStack(spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                editorField(label: "RATE", value: Binding(
                    get: { binding.wrappedValue.rate },
                    set: { binding.wrappedValue = RateEdit794(rate: $0, freeTime: binding.wrappedValue.freeTime) }))
                editorStepper(label: "FREE", value: Binding(
                    get: { binding.wrappedValue.freeTime },
                    set: { binding.wrappedValue = RateEdit794(rate: binding.wrappedValue.rate, freeTime: $0) }))
            }
            HStack {
                if edits[item.code] != nil {
                    Button { edits[item.code] = nil } label: {
                        Text("Reset").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text(jurisdiction.active ? "Save tariff to apply" : "\(jurisdiction.rawValue) is standby — US only")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(Rectangle().fill(LinearGradient.diagonal).frame(width: 3), alignment: .leading)
    }

    private func editorField(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 2) {
                Text("$").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textSecondary)
                TextField("0", value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .frame(maxWidth: .infinity)
    }

    private func editorStepper(label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack {
                Button { value.wrappedValue = max(0, value.wrappedValue - 1) } label: {
                    Image(systemName: "minus").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }.buttonStyle(.plain)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button { value.wrappedValue += 1 } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Jurisdiction card (segmented US/CA/MX · US active)

    private var jurisdictionCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TARIFF JURISDICTION · BASIS + CURRENCY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("US ACTIVE").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.info)
            }
            HStack(spacing: Space.s2) {
                ForEach(TariffJurisdiction794.allCases, id: \.self) { j in
                    Button { withAnimation(.easeOut(duration: 0.15)) { jurisdiction = j } } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(j.rawValue).font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(jurisdiction == j ? .white : palette.textSecondary)
                                if j == jurisdiction {
                                    Circle().fill(.white).frame(width: 5, height: 5)
                                }
                            }
                            Text(j.authority).font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(jurisdiction == j ? .white.opacity(0.92) : palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(j.active ? j.currency : "\(j.currency) · standby")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(jurisdiction == j ? .white.opacity(0.9) : palette.textTertiary)
                        }
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(jurisdiction == j ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: CTA row (Save tariff · Add rate)

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await saveTariff() } } label: {
                HStack(spacing: 6) {
                    if saving { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(saving ? "Saving…" : "Save tariff")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(saving || edits.isEmpty || !jurisdiction.active)
            .opacity((edits.isEmpty || !jurisdiction.active) ? 0.6 : 1.0)

            Button { withAnimation(.easeOut(duration: 0.18)) { showCatalog.toggle() } } label: {
                Text("Add rate").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 132, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Full catalog picker (Add rate)

    @ViewBuilder
    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACCESSORIAL CATALOG · BY CODE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                let extra = items.filter { !primaryCodes.contains($0.code) }
                ForEach(Array(extra.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        // Bring the code onto the editable sheet with its default rate.
                        edits[item.code] = RateEdit794(rate: item.defaultRate ?? 0, freeTime: item.freeTime ?? 0)
                        editingCode = item.code
                        withAnimation(.easeOut(duration: 0.18)) { showCatalog = false }
                    } label: {
                        HStack(spacing: Space.s3) {
                            Text(item.code)
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundStyle(Brand.info)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Brand.info.opacity(0.14)))
                            Text(item.name).font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.textPrimary).lineLimit(1)
                            Spacer()
                            Text(rateText(item.defaultRate ?? 0))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.textSecondary)
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16)).foregroundStyle(LinearGradient.diagonal)
                        }
                        .padding(Space.s3)
                    }
                    .buttonStyle(.plain)
                    if idx < extra.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s3)
                    }
                }
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: Banners / loading / error

    private func banner(_ msg: String, danger: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: danger ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(danger ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.diagonal))
            Text(msg).font(EType.caption)
                .foregroundStyle(danger ? Brand.danger : palette.textPrimary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background((danger ? Brand.danger : Brand.success).opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder((danger ? Brand.danger : Brand.success).opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 300)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Derived

    /// The primary five headline codes (in canonical order) that exist in the catalog.
    private var tableRows: [AccessorialCatalogItem794] {
        var rows: [AccessorialCatalogItem794] = []
        for code in primaryCodes {
            if let item = items.first(where: { $0.code == code }) { rows.append(item) }
        }
        // Any codes the operator brought on via "Add rate" that aren't primary.
        for code in edits.keys where !primaryCodes.contains(code) {
            if let item = items.first(where: { $0.code == code }) { rows.append(item) }
        }
        return rows
    }

    private func effectiveRate(_ item: AccessorialCatalogItem794) -> Double {
        edits[item.code]?.rate ?? item.defaultRate ?? 0
    }
    private func effectiveFree(_ item: AccessorialCatalogItem794) -> Int {
        edits[item.code]?.freeTime ?? item.freeTime ?? 0
    }
    private func rateText(_ v: Double) -> String {
        if v == v.rounded() { return "$\(Int(v))" }
        return "$\(String(format: "%.2f", v))"
    }
    private func unitSuffix(_ unit: String?) -> String {
        switch (unit ?? "").lowercased() {
        case "per hour": return "/hr"
        case "per day":  return "/day"
        case "flat":     return "flat"
        case "percent":  return "%"
        default:         return ""
        }
    }
    private func freeUnit(_ unit: String?) -> String {
        (unit ?? "").lowercased().contains("hour") ? "h" : "d"
    }

    // MARK: - Actions

    private func load() async {
        loading = true; loadError = nil
        do {
            let res: AccessorialCatalog794 = try await EusoTripAPI.shared.queryNoInput(
                "detentionAccessorials.getAccessorialCatalog")
            self.items = res.items
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func saveTariff() async {
        guard !edits.isEmpty, jurisdiction.active else { return }
        saving = true; saveAck = nil; saveError = nil
        struct ConfigIn: Encodable { let code: String; let rate: Double; let freeTime: Int }
        var saved = 0
        var firstError: String? = nil
        for (code, edit) in edits {
            do {
                let res: ConfigureRateResult794 = try await EusoTripAPI.shared.mutation(
                    "detentionAccessorials.configureAccessorialRate",
                    input: ConfigIn(code: code, rate: edit.rate, freeTime: edit.freeTime))
                if res.success == true { saved += 1 }
            } catch {
                if firstError == nil {
                    firstError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
        if saved > 0 {
            saveAck = "Applied \(saved) rate\(saved == 1 ? "" : "s") to the \(jurisdiction.currency) tariff."
            edits.removeAll()
            editingCode = nil
        }
        if let firstError, saved == 0 { saveError = firstError }
        saving = false
    }
}

#Preview("794 · Vessel Accessorial Rate Config · Night") {
    VesselAccessorialRateConfigScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("794 · Vessel Accessorial Rate Config · Light") {
    VesselAccessorialRateConfigScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
