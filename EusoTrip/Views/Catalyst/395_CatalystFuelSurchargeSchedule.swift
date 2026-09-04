//
//  395_CatalystFuelSurchargeSchedule.swift
//  EusoTrip — Catalyst · Fuel Surcharge Schedule (carrier back-office pricing band).
//
//  Original composition references:
//    03 Catalyst/Code/395_CatalystFuelSurchargeSchedule.swift
//    03 Catalyst/Dark-SVG/395 Catalyst Fuel Surcharge Schedule.svg
//
//  The regional EIA gauge and persisted per-mile ladder distinguish the
//  current observation from the contract's configured rates. Missing or
//  expired evidence leaves the ladder visible without a current marker.
//  Web peer: /catalyst/wallet/fsc.
//
//  Source contract: fscEngine.getSchedules selects an active diesel schedule;
//  getSchedulePreview returns its exact per-mile/percentage rate, current
//  regional EIA evidence and selected bracket ID. getLookupTable supplies
//  the ladder. A cached schedule price is never treated as an observation.
//  updatePaddPrices and createSchedule are persisted online actions. Counts
//  and billed rollups without a server projection remain unavailable.
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
    @Environment(\.scenePhase) private var scenePhase

    // Regional evidence comes from the selected schedule, not a separate index.
    @State private var paddRegion: String   = "PADD unavailable"
    @State private var selectedPaddKey: String? = nil
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
    @State private var loadGeneration = UUID()
    @State private var fuelValidUntil: Date? = nil
    @State private var fuelExpiredThrough = Date.distantPast
    @State private var fuelSourceURL: URL? = nil
    @State private var usesEIAForRate = false

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
    @State private var draftPaddKey: String? = nil
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
        .task(id: fuelValidUntil) {
            guard let deadline = fuelValidUntil else { return }
            do {
                while deadline > Date() {
                    try await Task.sleep(for: .seconds(min(deadline.timeIntervalSinceNow, 60)))
                }
                guard !Task.isCancelled else { return }
                fuelExpiredThrough = max(fuelExpiredThrough, deadline)
                loadGeneration = UUID()
                refreshing = false
                dieselPrice = "—"
                liveDieselValue = nil
                nationalLine = "Observation expired"
                gaugeFraction = 0
                fuelSourceURL = nil
                if usesEIAForRate {
                    appliedSurcharge = "—"
                    highlightBracket_395(id: nil)
                }
                scheduleActionError = "The EIA observation expired. Refresh the schedule."
            } catch { /* The view or observation changed. */ }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await loadAll() } }
        }
        .onDisappear { loadGeneration = UUID() }
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
                    Text("CATALYST · FUEL SURCHARGE")
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

    // MARK: - Hero · Regional diesel index gauge

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
                    if liveDieselValue != nil {
                        indexGauge_395
                    } else {
                        Text("Current EIA unavailable")
                            .font(EType.micro)
                            .foregroundStyle(palette.textSecondary)
                    }
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
                    if let fuelSourceURL {
                        Link(nationalLine, destination: fuelSourceURL)
                            .font(EType.mono(.micro))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(nationalLine)
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .frame(minHeight: 108)
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
                Text("RATE/MI · DIESEL USD/GAL")
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

    // MARK: - Network

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
    private struct SchedulesInput_395: Encodable { let isActive: Bool; let fuelType: String }
    private struct PreviewInput_395: Encodable { let scheduleId: Int }
    private struct FuelSource_395: Decodable {
        let provider: String
        let url: String
        let scopeKey: String
    }
    private struct ContractDiesel_395: Decodable {
        let price: Double
        let period: String
        let region: String
        let change1w: Double?
        let freshnessSec: Double
        let nextReleaseAt: String
        let sources: [FuelSource_395]
        var deadline: Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: nextReleaseAt) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: nextReleaseAt)
        }
        var sourceURL: URL? {
            guard let source = sources.first(where: { $0.provider == "EIA" && $0.scopeKey == region }),
                  let url = URL(string: source.url), url.scheme == "https",
                  ["eia.gov", "www.eia.gov"].contains(url.host ?? "") else { return nil }
            return url
        }
        func isUsable(for padd: String?, now: Date = Date()) -> Bool {
            price.isFinite && price > 0 && price <= 999.999 && freshnessSec.isFinite &&
                freshnessSec >= 0 && freshnessSec < 1e12 && sourceURL != nil &&
                region == "PADD\(padd ?? "")" && (deadline.map { $0 > now } ?? false)
        }
    }
    private struct MatchedBracket_395: Decodable { let id: Int? }
    private struct PreviewWire_395: Decodable {
        let fsc: Double
        let fscUnit: String
        let method: String
        let paddPrice: Double?
        let basePrice: Double?
        let fuel: ContractDiesel_395?
        let matchedBracket: MatchedBracket_395?
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
        let generation = UUID()
        loadGeneration = generation
        refreshing = true
        defer { if loadGeneration == generation { refreshing = false } }
        activeScheduleId = nil
        selectedPaddKey = nil
        liveDieselValue = nil
        fuelValidUntil = nil
        fuelSourceURL = nil
        usesEIAForRate = false
        dieselPrice = "—"
        appliedSurcharge = "—"
        basePegLabel = "—"
        paddRegion = "PADD unavailable"
        weekLabel = "—"
        nationalLine = "—"
        gaugeFraction = 0
        brackets = []
        scheduleId = "—"
        methodLabel = "—"
        scheduleActionError = nil
        do {
            scheduleLoadNote = nil
            let wire: FscSchedulesWire_395 = try await EusoTripAPI.shared.query(
                "fscEngine.getSchedules", input: SchedulesInput_395(isActive: true, fuelType: "diesel"))
            guard loadGeneration == generation else { return }
            guard let schedule = wire.schedules.first(where: { $0.fuelType?.lowercased() == "diesel" }) else {
                scheduleLoadNote = "No active diesel schedule on file."
                return
            }
            activeScheduleId = schedule.id
            selectedPaddKey = schedule.paddRegion
            paddRegion = "PADD \(schedule.paddRegion)"
            scheduleId = schedule.scheduleName.uppercased()
            let freq = (schedule.updateFrequency ?? "weekly").uppercased()
            methodLabel = "\(schedule.method.uppercased()) · \(freq)"
            if let base = schedule.basePrice.flatMap(Double.init), base > 0 {
                basePegLabel = String(format: "$%.2f base peg", base)
            }

            if schedule.method == "table" {
                await loadLookupTable_395(scheduleId: schedule.id, matchedId: nil, generation: generation)
                guard loadGeneration == generation else { return }
            }

            let preview: PreviewWire_395 = try await EusoTripAPI.shared.query(
                "fscEngine.getSchedulePreview", input: PreviewInput_395(scheduleId: schedule.id))
            guard loadGeneration == generation else { return }
            guard preview.fsc.isFinite, preview.fsc >= 0,
                  preview.method == schedule.method,
                  preview.fscUnit == (schedule.method == "percentage" ? "percent" : "per_mile") else {
                scheduleActionError = "The surcharge rate could not be verified."
                return
            }
            let fuel = preview.fuel.flatMap { evidence in
                evidence.isUsable(for: selectedPaddKey) && (evidence.deadline.map { $0 > fuelExpiredThrough } ?? false) ? evidence : nil
            }
            usesEIAForRate = schedule.method == "table"
            guard !usesEIAForRate || fuel != nil else {
                scheduleActionError = "A current regional EIA observation is required for this schedule."
                return
            }
            appliedSurcharge = String(format: "%.4f", preview.fsc)
            surchargeUnit = preview.fscUnit == "percent" ? "% of linehaul" : "/mi"
            if let fuel {
                applyDiesel_395(fuel)
            } else {
                scheduleActionError = "Current regional diesel observation unavailable. Fixed contract rate shown."
            }
            if schedule.method == "table" {
                highlightBracket_395(id: preview.matchedBracket?.id)
            }
        } catch {
            guard loadGeneration == generation else { return }
            scheduleLoadNote = "Couldn't reach the FSC engine. Retry from this screen."
            scheduleActionError = error.eusoUserCopy
        }
    }

    private func loadLookupTable_395(scheduleId: Int, matchedId: Int?, generation: UUID) async {
        do {
            let lookup: LookupWire_395 = try await EusoTripAPI.shared.query(
                "fscEngine.getLookupTable",
                input: LookupInput_395(scheduleId: scheduleId)
            )
            guard loadGeneration == generation else { return }
            brackets = mapLookupBrackets_395(lookup.brackets, matchedId: matchedId)
            if brackets.isEmpty {
                scheduleLoadNote = "Schedule \(lookup.schedule?.scheduleName ?? self.scheduleId) has no bracket rows yet. Add a table schedule here."
            } else {
                scheduleLoadNote = nil
            }
        } catch {
            guard loadGeneration == generation else { return }
            brackets = []
            scheduleLoadNote = "Couldn't load FSC bracket rows. \(error.eusoUserCopy)"
        }
    }

    private func mapLookupBrackets_395(_ rows: [LookupBracket_395], matchedId: Int?) -> [FscBracket_395] {
        let maxSurcharge = max(rows.map(\.surchargeAmount).max() ?? 0, 0.01)
        return rows.map { row in
            let active = row.id == matchedId
            return FscBracket_395(
                id: "\(row.id)",
                range: "\(formatPrice_395(row.fuelPriceMin)) – \(formatPrice_395(row.fuelPriceMax))",
                surcharge: String(format: "%.4f", row.surchargeAmount),
                barFraction: min(1.0, max(0, row.surchargeAmount / maxSurcharge)),
                active: active
            )
        }
    }

    private func highlightBracket_395(id: Int?) {
        brackets = brackets.map { row in
            FscBracket_395(id: row.id, range: row.range, surcharge: row.surcharge,
                barFraction: row.barFraction, active: id.map { String($0) == row.id } ?? false)
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
        draftScheduleName = "Diesel table \(shortDate_395(Date().ISO8601Format()))"
        draftPaddKey = selectedPaddKey
        draftBasePrice = liveDieselValue.map { String(format: "%.3f", $0) } ?? ""
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
                    Picker("Region", selection: $draftPaddKey) {
                        Text("Select region").tag(String?.none)
                        ForEach(["1A", "1B", "1C", "2", "3", "4", "5"], id: \.self) { region in
                            Text("PADD \(region)").tag(Optional(region))
                        }
                    }
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
                    .disabled(savingSchedule || draftPaddKey == nil || trim_395(draftScheduleName).isEmpty || buildDraftTableEntries_395().isEmpty)
                }
            }
        }
    }

    private func buildDraftTableEntries_395() -> [TableEntryInput_395] {
        guard draftBandCount > 0,
              let base = Double(trim_395(draftBasePrice)), base.isFinite, base > 0,
              let width = Double(trim_395(draftBandWidth)), width.isFinite, width > 0,
              let surchargeStep = Double(trim_395(draftStepSurcharge)), surchargeStep.isFinite, surchargeStep >= 0 else { return [] }
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
        guard !entries.isEmpty, let draftPaddKey else {
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
                    paddRegion: draftPaddKey,
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

    private func applyDiesel_395(_ d: ContractDiesel_395) {
        guard d.isUsable(for: selectedPaddKey) else { return }
        liveDieselValue = d.price
        fuelValidUntil = d.deadline
        fuelSourceURL = d.sourceURL
        dieselPrice = String(format: "$%.3f", d.price)
        // Gauge over a fixed $2.00–$7.00 display axis (axis bounds are
        // presentation, labeled honestly — the marker is the live price).
        let axisLow = 2.00, axisHigh = 7.00
        ceilingLabel = formatPrice_395(axisHigh)
        let frac = (d.price - axisLow) / (axisHigh - axisLow)
        gaugeFraction = min(1.0, max(0.0, frac))
        weekLabel = "EIA \(shortDate_395(d.period))"
        nationalLine = "\(Int(d.freshnessSec / 3600))h observation age"
        if let change = d.change1w {
            nationalLine += String(format: " · %+.3f/gal wk", change)
        }
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
