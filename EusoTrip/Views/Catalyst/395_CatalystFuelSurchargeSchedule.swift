//
//  395_CatalystFuelSurchargeSchedule.swift
//  EusoTrip — Catalyst · Fuel Surcharge Schedule (carrier back-office pricing band).
//
//  Verbatim iOS-house port of the canonical bespoke wireframe:
//    03 Catalyst/Code/395_CatalystFuelSurchargeSchedule.swift
//    03 Catalyst/Dark-SVG/395 Catalyst Fuel Surcharge Schedule.svg
//
//  Moment: Michael Eusorone (Eusotrans LLC owner-op · USDOT 3 194 882 ·
//  MC-820 144 · Belle Plaine IA) opens his fuel-surcharge program from
//  the Wallet tab. The signature body is an FSC STEP LADDER — a diesel-
//  index gauge hero (PADD-3 Gulf Coast EIA) feeding a stepped bracket
//  table where each diesel $/gal band escalates to its own ¢/mi
//  surcharge; the bracket holding the live PADD-3 price is lit gradient
//  with a NOW marker and the bars step outward row by row as a literal
//  staircase. Table rows omit lifecycle dots (Foundation Contract §5).
//  Web peer: /catalyst/wallet/fsc.
//
//  Server wiring (line-confirmed on disk this fire):
//    • index gauge (PADD-3 $/gal · natl avg · week-of · week Δ)
//        → rateSheet.getCurrentDiesel(padd:)   — EXISTS (EusoTripAPI
//          RateSheetAPI). Returns price / padd / reportDate / source /
//          change1w. Hydrates the hero over the seed; honest em-dash on
//          failure. (Web peer fuelSurchargeIndex.currentDieselIndex
//          fuelSurchargeIndex.ts:56 maps to this iOS-shaped wrapper.)
//    • active schedule + method  → fscEngine.getSchedules (fscEngine.ts:27)   — not on iOS yet
//    • bracket-ladder rows       → fscEngine.getSchedulePreview (fscEngine.ts:233) — not on iOS yet
//      (fsc_lookup_table: fuelPriceMin / fuelPriceMax / surchargeAmount)
//    • applied-now ¢/mi          → fscEngine.calculateFSC (fscEngine.ts:97)  — not on iOS yet
//    • week Δ + trend            → fscEngine.getFSCHistory (fscEngine.ts:333) — not on iOS yet
//    • attached-lanes count      → fscEngine.attachToContract (fscEngine.ts:300) — not on iOS yet
//    • "Refresh PADD prices" CTA → fscEngine.updatePaddPrices (fscEngine.ts:172, mutation) — not on iOS yet
//    • "Edit table" CTA          → fscEngine.createSchedule (fscEngine.ts:49, mutation) — not on iOS yet
//  RBAC: isolatedApprovedProcedure carrier-scope (fscEngine.ts:16)
//        + requireAccess DISPATCH/CATALYST resource INVOICE on writes (fscEngine.ts:71).
//  transportMode = truck · PADD region 3 Gulf Coast · currency USD.
//
//  ZERO-FALLBACK (2026-06-09 · audit M4): the hero hydrates from the live
//  PADD-3 index, schedule identity/method/base-peg/surcharge-now hydrate
//  from fscEngine.getSchedules (+ getSchedulePreview band lookup for table
//  schedules), and everything without a live source (the per-band ladder
//  rows of fsc_lookup_table, attached-lane count, FSC-billed rollup) is an
//  honest em-dash / EusoEmptyState. WIRE-GAP: fscEngine exposes no read for
//  the lookup-table rows — needed before the staircase can ever render.
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME (WALLET current).
//

import SwiftUI

// MARK: - Wrapper

struct CatalystFuelSurchargeScheduleScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            FuelSurchargeBody_395()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_395(),
                trailing: catalystNavTrailing_395(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_395() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_395() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person.crop.circle", isCurrent: false)]
}

// MARK: - Bracket model

private struct FscBracket_395: Identifiable {
    let id: String            // "3.75-4.00"
    let range: String         // "$3.75 – 4.00"
    let surcharge: String     // "$0.46"
    let barFraction: Double   // 0…1 — escalating step width
    let active: Bool          // band holding the live PADD price
}

// MARK: - Body

private struct FuelSurchargeBody_395: View {
    @Environment(\.palette) private var palette

    // Index gauge — em-dash until rateSheet.getCurrentDiesel answers. No seeds.
    @State private var paddRegion: String   = "PADD 3 GULF COAST"
    @State private var weekLabel: String    = "—"
    @State private var scheduleId: String   = "—"
    @State private var dieselPrice: String  = "—"
    @State private var basePegLabel: String = "—"
    @State private var ceilingLabel: String = ""
    @State private var gaugeFraction: Double = 0
    @State private var appliedSurcharge: String = "—"
    @State private var surchargeUnit: String = "/mi"
    @State private var nationalLine: String = "—"

    // Step ladder — LIVE fscEngine.getSchedules header + getLookupTable rows.
    @State private var methodLabel: String  = "—"
    @State private var brackets: [FscBracket_395] = []
    @State private var activeScheduleId: Int? = nil
    @State private var liveDieselValue: Double? = nil

    // Footer · attached lanes — no live source (pricebook fscIncluded rollup
    // unexposed) → em-dash, never invented.
    @State private var attachedLanes: Int? = nil
    @State private var fscBilled: String   = "—"
    @State private var billedWindow: String = "—"

    @State private var refreshing: Bool = false
    @State private var scheduleLoadNote: String? = nil
    @State private var scheduleActionMessage: String? = nil
    @State private var scheduleActionError: String? = nil
    @State private var showScheduleEditor: Bool = false
    @State private var savingSchedule: Bool = false
    @State private var draftScheduleName: String = ""
    @State private var draftBasePrice: String = ""
    @State private var draftBandWidth: String = "0.25"
    @State private var draftBandCount: Int = 8
    @State private var draftStepSurcharge: String = "0.05"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar_395
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    heroCard_395
                    ladderSection_395
                    attachedFooter_395
                    ctaRow_395
                    legend_395
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s7)
            }
        }
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
        .sheet(isPresented: $showScheduleEditor) {
            scheduleEditorSheet_395
        }
    }

    // MARK: - TopBar

    private var topBar_395: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("CATALYST · FUEL SURCHARGE · PADD 3")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer(minLength: 0)
                Text(scheduleId)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                Text("Fuel surcharge")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: - Hero · PADD-3 diesel index gauge

    private var heroCard_395: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(paddRegion) · \(weekLabel)")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(dieselPrice)
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("/gal")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    indexGauge_395
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("SURCHARGE NOW")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(appliedSurcharge)
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                        Text(appliedSurcharge == "—" ? "" : surchargeUnit)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text(nationalLine)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Brand.success)
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 108)
    }

    private var indexGauge_395: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.textTertiary.opacity(0.18)).frame(height: 6)
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: max(8, w * gaugeFraction), height: 6)
                    Rectangle().fill(palette.textTertiary).frame(width: 1.5, height: 12)
                    Circle().fill(palette.bgCard)
                        .overlay(Circle().strokeBorder(Brand.magenta, lineWidth: 2.5))
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, w * gaugeFraction - 5))
                }
                .frame(height: 12)
            }
            .frame(width: 200, height: 12)
            HStack {
                Text(basePegLabel)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(ceilingLabel)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 200)
        }
    }

    // MARK: - Step ladder

    private var ladderSection_395: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("SURCHARGE TABLE · ¢/MI BY DIESEL $/GAL")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(methodLabel)
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("DIESEL BAND $/GAL")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("SURCHARGE")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s2)
                Rectangle().fill(palette.borderFaint).frame(height: 1)

                if brackets.isEmpty {
                    EusoEmptyState(
                        systemImage: "tablecells",
                        title: "No bracket table on file",
                        subtitle: scheduleLoadNote ?? "Create a table schedule here to persist your FSC ladder."
                    )
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(brackets.enumerated()), id: \.element.id) { idx, b in
                        bracketRow_395(b)
                        if idx < brackets.count - 1 && !b.active && !brackets[idx + 1].active {
                            Rectangle().fill(palette.borderFaint.opacity(0.7))
                                .frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func bracketRow_395(_ b: FscBracket_395) -> some View {
        HStack(spacing: Space.s3) {
            Text(b.range)
                .font(EType.mono(.caption))
                .fontWeight(b.active ? .bold : .semibold)
                .foregroundStyle(b.active ? palette.textPrimary : palette.textSecondary)
                .frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                Capsule()
                    .fill(b.active
                          ? AnyShapeStyle(LinearGradient.diagonal)
                          : AnyShapeStyle(Brand.rail.opacity(0.28)))
                    .frame(width: max(14, w * b.barFraction), height: 14)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)
            if b.active {
                Text("NOW")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            Text(b.surcharge)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, Space.s4)
        .frame(height: 50)
        .background(activeBracketBackground_395(b.active))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(b.range) dollars per gallon, surcharge \(b.surcharge) per mile\(b.active ? ", active band" : "")")
    }

    @ViewBuilder
    private func activeBracketBackground_395(_ active: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Brand.blue.opacity(0.10))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(LinearGradient.diagonal)
                        .frame(width: 3)
                }
                .padding(.horizontal, 6)
        } else {
            Color.clear
        }
    }

    // MARK: - Footer · attached lanes

    private var attachedFooter_395: some View {
        HStack {
            // Attached-lane count + billed rollup have no live source on any
            // wired proc — honest em-dash, never an invented "$4,210 · 90d".
            (Text("Attached lanes ")
                + Text(attachedLanes.map { "\($0)" } ?? "—").fontWeight(.bold).foregroundColor(palette.textPrimary)
                + Text(" · FSC billed ")
                + Text(fscBilled).fontWeight(.bold).foregroundColor(palette.textPrimary)
                + Text(" · \(billedWindow)"))
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Button {
                openScheduleEditor_395()
            } label: {
                Text("+ NEW BRACKET")
                    .font(EType.micro).tracking(0.4).fontWeight(.heavy)
                    .foregroundStyle(LinearGradient.primary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - CTA pair

    private var ctaRow_395: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                CTAButton(
                    title: "Refresh PADD prices",
                    action: {
                        Task { await refreshPaddPrices_395() }
                    },
                    isLoading: refreshing
                )

                Button {
                    openScheduleEditor_395()
                } label: {
                    Text(activeScheduleId == nil ? "Create table" : "New table")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 132)
                        .frame(minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit surcharge table")
            }
            if let msg = scheduleActionError ?? scheduleActionMessage {
                HStack(spacing: 8) {
                    Image(systemName: scheduleActionError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(scheduleActionError == nil ? Brand.success : Brand.danger)
                    Text(msg)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(scheduleActionError == nil ? palette.textSecondary : Brand.danger)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Legend

    private var legend_395: some View {
        HStack(spacing: Space.s4) {
            legendItem_395(
                swatch: AnyView(Capsule().fill(LinearGradient.diagonal).frame(width: 14, height: 8)),
                label: "live band today")
            legendItem_395(
                swatch: AnyView(Capsule().fill(Brand.rail.opacity(0.34)).frame(width: 14, height: 8)),
                label: "inactive band")
            legendItem_395(
                swatch: AnyView(Rectangle().fill(palette.textTertiary).frame(width: 1.5, height: 8)),
                label: "base peg")
            Spacer(minLength: 0)
        }
    }

    private func legendItem_395(swatch: AnyView, label: String) -> some View {
        HStack(spacing: 6) {
            swatch
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Network (live: getCurrentDiesel + fscEngine.getSchedules/getSchedulePreview)

    private struct FscScheduleWire_395: Decodable {
        let id: Int
        let scheduleName: String
        let basePrice: String?        // DECIMAL → JSON string
        let method: String
        let cpmRate: String?          // DECIMAL → JSON string
        let percentageRate: String?   // DECIMAL → JSON string
        let paddRegion: String
        let fuelType: String?
        let updateFrequency: String?
        let lastPaddPrice: String?
        let isActive: Int?
    }
    private struct FscSchedulesWire_395: Decodable { let schedules: [FscScheduleWire_395] }
    private struct SchedulesInput_395: Encodable { let isActive: Bool }
    private struct PreviewInput_395: Encodable { let scheduleId: Int; let paddPrice: Double? }
    private struct PreviewWire_395: Decodable {
        let fsc: Double
        let method: String
        let paddPrice: Double
        let basePrice: Double
    }
    private struct LookupWire_395: Decodable {
        let schedule: LookupSchedule_395?
        let brackets: [LookupBracket_395]
    }
    private struct LookupSchedule_395: Decodable {
        let id: Int
        let scheduleName: String
        let method: String
        let paddRegion: String
        let basePrice: Double?
        let lastPaddPrice: Double?
        let isActive: Bool
    }
    private struct LookupBracket_395: Decodable {
        let id: Int
        let fuelPriceMin: Double
        let fuelPriceMax: Double
        let surchargeAmount: Double
    }
    private struct LookupInput_395: Encodable { let scheduleId: Int? }
    private struct TableEntryInput_395: Encodable {
        let fuelPriceMin: Double
        let fuelPriceMax: Double
        let surchargeAmount: Double
    }
    private struct CreateScheduleInput_395: Encodable {
        let scheduleName: String
        let method: String
        let paddRegion: String
        let fuelType: String?
        let updateFrequency: String?
        let basePrice: Double?
        let tableEntries: [TableEntryInput_395]?
    }
    private struct CreateScheduleOut_395: Decodable {
        let id: Int
        let scheduleName: String
        let status: String
    }
    private struct PaddUpdateOut_395: Decodable {
        let updatedCount: Int?
    }

    private func loadAll() async {
        refreshing = true
        defer { refreshing = false }

        // 1. Live PADD-3 Gulf Coast diesel index → hero gauge + national line.
        var livePadd: Double? = nil
        do {
            let diesel = try await EusoTripAPI.shared.rateSheet.getCurrentDiesel(padd: "3")
            applyDiesel_395(diesel)
            livePadd = diesel.price
            liveDieselValue = diesel.price
        } catch {
            scheduleActionError = "Diesel index sync failed. \(error.eusoUserCopy)"
        }

        // 2. Live schedule header → identity + method + base peg + surcharge-now.
        do {
            scheduleLoadNote = nil
            let wire: FscSchedulesWire_395 = try await EusoTripAPI.shared.query(
                "fscEngine.getSchedules", input: SchedulesInput_395(isActive: true))
            guard let schedule = wire.schedules.first else {
                activeScheduleId = nil
                scheduleId = "—"
                methodLabel = "—"
                appliedSurcharge = "—"
                brackets = []
                scheduleLoadNote = "No FSC schedule on file. Create a table schedule here to persist your ladder."
                return
            }
            activeScheduleId = schedule.id
            scheduleId = schedule.scheduleName.uppercased()
            let freq = (schedule.updateFrequency ?? "weekly").uppercased()
            methodLabel = "\(schedule.method.uppercased()) · \(freq)"
            if let base = schedule.basePrice.flatMap(Double.init), base > 0 {
                basePegLabel = String(format: "$%.2f base peg", base)
            }

            switch schedule.method {
            case "cpm":
                // fsc = miles × rate / 100 → per-mile surcharge = rate / 100.
                if let rate = schedule.cpmRate.flatMap(Double.init) {
                    appliedSurcharge = String(format: "$%.2f", rate / 100.0)
                    surchargeUnit = "/mi"
                }
            case "percentage":
                if let pct = schedule.percentageRate.flatMap(Double.init) {
                    appliedSurcharge = String(format: "%.1f", pct)
                    surchargeUnit = "% of linehaul"
                }
            case "table":
                // Real band lookup against the live PADD price.
                do {
                    let preview: PreviewWire_395 = try await EusoTripAPI.shared.query(
                        "fscEngine.getSchedulePreview",
                        input: PreviewInput_395(scheduleId: schedule.id, paddPrice: livePadd)
                    )
                    if preview.fsc > 0 {
                        appliedSurcharge = String(format: "$%.2f", preview.fsc)
                        surchargeUnit = "/mi"
                    }
                } catch {
                    scheduleActionError = "FSC preview sync failed. \(error.eusoUserCopy)"
                }
                await loadLookupTable_395(scheduleId: schedule.id, livePadd: livePadd)
            default:
                brackets = []
                scheduleLoadNote = "This active FSC schedule uses \(schedule.method.uppercased()); bracket rows apply to table schedules."
                break
            }
        } catch {
            scheduleLoadNote = "Couldn't reach the FSC engine. Retry from this screen."
            scheduleActionError = error.eusoUserCopy
        }
    }

    private func loadLookupTable_395(scheduleId: Int, livePadd: Double?) async {
        do {
            let lookup: LookupWire_395 = try await EusoTripAPI.shared.query(
                "fscEngine.getLookupTable",
                input: LookupInput_395(scheduleId: scheduleId)
            )
            brackets = mapLookupBrackets_395(lookup.brackets, livePadd: livePadd)
            if brackets.isEmpty {
                scheduleLoadNote = "Schedule \(lookup.schedule?.scheduleName ?? self.scheduleId) has no bracket rows yet. Add a table schedule here."
            } else {
                scheduleLoadNote = nil
            }
        } catch {
            brackets = []
            scheduleLoadNote = "Couldn't load FSC bracket rows. \(error.eusoUserCopy)"
        }
    }

    private func mapLookupBrackets_395(_ rows: [LookupBracket_395], livePadd: Double?) -> [FscBracket_395] {
        let maxSurcharge = max(rows.map(\.surchargeAmount).max() ?? 0, 0.01)
        return rows.map { row in
            let active = livePadd.map { $0 >= row.fuelPriceMin && $0 <= row.fuelPriceMax } ?? false
            return FscBracket_395(
                id: "\(row.id)",
                range: "\(formatPrice_395(row.fuelPriceMin)) – \(formatPrice_395(row.fuelPriceMax))",
                surcharge: formatPrice_395(row.surchargeAmount),
                barFraction: min(1.0, max(0.08, row.surchargeAmount / maxSurcharge)),
                active: active
            )
        }
    }

    private func refreshPaddPrices_395() async {
        guard !refreshing else { return }
        refreshing = true
        scheduleActionError = nil
        scheduleActionMessage = nil
        defer { refreshing = false }
        do {
            let out: PaddUpdateOut_395 = try await EusoTripAPI.shared.mutationNoInput("fscEngine.updatePaddPrices")
            scheduleActionMessage = "PADD prices refreshed · \(out.updatedCount ?? 0) active schedule\(out.updatedCount == 1 ? "" : "s") updated."
        } catch {
            scheduleActionError = "PADD refresh failed. \(error.eusoUserCopy)"
        }
        await loadAll()
    }

    private func openScheduleEditor_395() {
        scheduleActionError = nil
        scheduleActionMessage = nil
        let base = liveDieselValue ?? 3.50
        draftScheduleName = "PADD 3 table \(shortDate_395(Date().ISO8601Format()))"
        draftBasePrice = String(format: "%.2f", base)
        draftBandWidth = "0.25"
        draftBandCount = 8
        draftStepSurcharge = "0.05"
        showScheduleEditor = true
    }

    private var scheduleEditorSheet_395: some View {
        NavigationStack {
            Form {
                Section("Schedule") {
                    TextField("Schedule name", text: $draftScheduleName)
                    TextField("Base diesel price", text: $draftBasePrice)
                        .keyboardType(.decimalPad)
                    TextField("Band width", text: $draftBandWidth)
                        .keyboardType(.decimalPad)
                    Stepper("Bands: \(draftBandCount)", value: $draftBandCount, in: 3...16)
                    TextField("Surcharge per band", text: $draftStepSurcharge)
                        .keyboardType(.decimalPad)
                }
                Section("Preview") {
                    ForEach(buildDraftTableEntries_395().indices, id: \.self) { idx in
                        let row = buildDraftTableEntries_395()[idx]
                        HStack {
                            Text("\(formatPrice_395(row.fuelPriceMin)) – \(formatPrice_395(row.fuelPriceMax))")
                            Spacer()
                            Text(formatPrice_395(row.surchargeAmount))
                                .fontWeight(.semibold)
                        }
                    }
                }
                if let scheduleActionError {
                    Section {
                        Text(scheduleActionError)
                            .foregroundStyle(Brand.danger)
                    }
                }
            }
            .navigationTitle("FSC table")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showScheduleEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(savingSchedule ? "Saving..." : "Create") {
                        Task { await createSchedule_395() }
                    }
                    .disabled(savingSchedule || trim_395(draftScheduleName).isEmpty || buildDraftTableEntries_395().isEmpty)
                }
            }
        }
    }

    private func buildDraftTableEntries_395() -> [TableEntryInput_395] {
        guard draftBandCount > 0,
              let base = Double(trim_395(draftBasePrice)),
              let width = Double(trim_395(draftBandWidth)), width > 0,
              let surchargeStep = Double(trim_395(draftStepSurcharge)), surchargeStep >= 0 else { return [] }
        let start = max(0, base - (width * 2))
        return (0..<draftBandCount).map { index in
            let priceMin = start + (Double(index) * width)
            let priceMax = priceMin + width
            let surcharge = max(0, Double(index - 1) * surchargeStep)
            return TableEntryInput_395(
                fuelPriceMin: priceMin,
                fuelPriceMax: priceMax,
                surchargeAmount: surcharge
            )
        }
    }

    private func createSchedule_395() async {
        let entries = buildDraftTableEntries_395()
        guard !entries.isEmpty else {
            scheduleActionError = "Enter a base price, band width, and surcharge step."
            return
        }
        guard !savingSchedule else { return }
        savingSchedule = true
        scheduleActionError = nil
        scheduleActionMessage = nil
        defer { savingSchedule = false }
        do {
            let out: CreateScheduleOut_395 = try await EusoTripAPI.shared.mutation(
                "fscEngine.createSchedule",
                input: CreateScheduleInput_395(
                    scheduleName: trim_395(draftScheduleName),
                    method: "table",
                    paddRegion: "3",
                    fuelType: "diesel",
                    updateFrequency: "weekly",
                    basePrice: Double(trim_395(draftBasePrice)),
                    tableEntries: entries
                )
            )
            showScheduleEditor = false
            scheduleActionMessage = "Created \(out.scheduleName) · \(out.status.uppercased())."
            await loadAll()
        } catch {
            scheduleActionError = "FSC schedule wasn't saved. \(error.eusoUserCopy)"
        }
    }

    private func trim_395(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyDiesel_395(_ d: RateSheetAPI.CurrentDiesel) {
        // Price → "$3.75"
        dieselPrice = formatPrice_395(d.price)
        // Gauge over a fixed $2.00–$6.00 display axis (axis bounds are
        // presentation, labeled honestly — the marker is the live price).
        let axisLow = 2.00, axisHigh = 6.00
        ceilingLabel = formatPrice_395(axisHigh)
        let frac = (d.price - axisLow) / (axisHigh - axisLow)
        gaugeFraction = min(1.0, max(0.0, frac))
        // PADD label (server echoes "3" / "PADD 3" / region name).
        if let p = d.padd, !p.isEmpty {
            paddRegion = p.uppercased().contains("PADD") ? p.uppercased() : "PADD \(p) GULF COAST"
        }
        // Week-of label from the EIA report date + source provenance.
        if let rd = d.reportDate, !rd.isEmpty {
            weekLabel = "EIA \(shortDate_395(rd))"
        } else if d.source == "EIA" {
            weekLabel = "EIA LIVE"
        }
        // National line: live price + honest week-over-week Δ when present.
        nationalLine = nationalLine_395(price: d.price, change1w: d.change1w)
    }

    private func nationalLine_395(price: Double, change1w: Double?) -> String {
        let base = "natl \(formatPrice_395(price))"
        guard let w = change1w, w != 0 else { return "\(base) · flat wk" }
        let sign = w > 0 ? "+" : "-"
        return "\(base) · \(sign)\(formatPrice_395(abs(w))) wk"
    }

    private func formatPrice_395(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func shortDate_395(_ raw: String) -> String {
        // "2026-05-25" → "WK21"-style short tag; fall back to the raw prefix.
        if raw.count >= 10 { return String(raw.prefix(10)) }
        return raw
    }
}

// MARK: - Previews

#Preview("395 · Catalyst · Fuel Surcharge · Night") {
    CatalystFuelSurchargeScheduleScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("395 · Catalyst · Fuel Surcharge · Afternoon") {
    CatalystFuelSurchargeScheduleScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
