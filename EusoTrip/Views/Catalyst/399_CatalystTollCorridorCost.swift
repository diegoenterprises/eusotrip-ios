//
//  399_CatalystTollCorridorCost.swift
//  EusoTrip 2027 UI — Catalyst track · carrier network-intelligence band
//
//  Moment: Michael Eusorone (Eusotrans LLC owner-op) opens Toll Spend from the
//          Wallet tab to see every toll dollar the fleet ran up this month, split
//          into the share auto-passed back to the shipper-of-record on settlement
//          vs the share his margin absorbed. This is NOT the home/detail skeleton
//          and NOT the 394 lending ledger: the hero is a SPEND figure with a
//          reimbursable/absorbed split bar, and the body is a CORRIDOR ledger —
//          each tollway agency with its transponder tag, event count and the
//          reimbursable/absorbed verdict. Money rows carry the agency chip but
//          omit lifecycle dots (Foundation Contract §5). The screen exists so toll
//          leakage never silently eats linehaul margin.
//
//  Verbatim SwiftUI twin of:
//    03 Catalyst/Dark-SVG/399 Catalyst Toll Corridor Cost.svg
//  ported into the iOS house Shell + BottomNav chrome.
//
//  Web peer: /catalyst/wallet/toll-spend.
//  LIVE WIRING:
//    • toll expense ledger → tolls.getSpendLedger — run-ticket toll expenses,
//      company-scoped through the signed-in Catalyst's companyId.
//    • completed route context → tolls.getRecentRoutes — route backup for
//      corridors that have not produced run-ticket toll expenses yet.
//    • IFTA basis → iftaCalculator.estimateFromLoads + CatalystFleetIFTA sheet.
//    • row / CTA drilldowns → native CatalystLoadDetailScreen and Fleet IFTA.
//  transportMode = truck; country = US (FHWA tollway agencies, USD). CA 407-ETR /
//  MX casetas resolve through detectLoadCountry when a corridor crosses.
//  Reimbursable share is billed to shipper-of-record Diego Usoro / Eusorone (§11).
//  RBAC: read protectedProcedure; write catalystProcedure (carrier-scope).
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME (WALLET current).
//

import SwiftUI

// MARK: - Shell wrapper

struct CatalystTollCorridorCostScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            TollCorridorBody_399()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_399(),
                trailing: catalystNavTrailing_399(),
                orbState: .idle
            )
        }
    }
}

// MARK: - BottomNav (HOME · DISPATCH · [orb] · WALLET · ME — WALLET current)

private func catalystNavLeading_399() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "tray.full",  isCurrent: false)]
}

private func catalystNavTrailing_399() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

// MARK: - View model (built from the LIVE tolls.getRecentRoutes envelope only)

private struct TollCorridor_399: Identifiable {
    enum Verdict { case reimbursable, absorbed, unknown }
    let id: String
    let loadNumber: String?
    let name: String
    let tagLine: String
    let amount: String
    let verdict: Verdict
    let verdictLabel: String
    let tint: Color
}

private struct TollSpendVM_399 {
    let headerSub: String
    let spendMTD: String
    let monthLabel: String
    let reimbursable: String
    let absorbed: String
    let reimbursableFrac: Double
    let splitCaption: String
    let perLoadedMile: String
    let perMileDelta: String
    let tollEvents: String
    let tollEventsSub: String
    let iftaBasis: String
    let iftaBasisSub: String
    let corridors: [TollCorridor_399]
    let corridorCount: String
    let insightTitle: String
    let insightSub: String

    static let empty = TollSpendVM_399(
        headerSub: "No toll expenses on file",
        spendMTD: "—", monthLabel: "MTD",
        reimbursable: "—", absorbed: "—", reimbursableFrac: 0,
        splitCaption: "Run-ticket toll expenses appear here as soon as receipts post.",
        perLoadedMile: "—", perMileDelta: "",
        tollEvents: "—", tollEventsSub: "No toll rows",
        iftaBasis: "—", iftaBasisSub: "Fleet IFTA",
        corridors: [],
        corridorCount: "—",
        insightTitle: "No toll spend on file",
        insightSub: "Toll receipts and run-ticket expenses will populate this ledger."
    )
}

private struct RecentRouteWire_399: Decodable {
    let id: Int
    let origin: String
    let destination: String
    let completedAt: String?
}

private struct TollLedgerEntryWire_399: Decodable, Identifiable {
    let id: String
    let ticketNumber: String
    let loadNumber: String?
    let origin: String?
    let destination: String?
    let amount: Double
    let description: String?
    let incurredAt: String?
}

private struct TollLedgerSummaryWire_399: Decodable {
    let totalSpend: Double
    let last30DaysSpend: Double
    let entryCount: Int
}

private struct TollLedgerWire_399: Decodable {
    let entries: [TollLedgerEntryWire_399]
    let summary: TollLedgerSummaryWire_399
}

// MARK: - Body

private struct TollCorridorBody_399: View {
    @Environment(\.palette) private var palette

    @State private var vm: TollSpendVM_399 = .empty
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var selectedLoadId: String?
    @State private var showIFTA: Bool = false
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    heroCard
                    kpiStrip
                    corridorSection
                    insightRow
                    ctaPair
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s7)
            }
        }
        .task { await loadAll() }
        .sheet(item: Binding(
            get: { selectedLoadId.map { LoadDrilldown_399(id: $0) } },
            set: { selectedLoadId = $0?.id }
        )) { item in
            CatalystLoadDetailScreen(theme: palette, loadId: item.id)
        }
        .sheet(isPresented: $showIFTA) {
            CatalystFleetIFTA()
                .environment(\.palette, palette)
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ CATALYST · TOLLS").font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(loading ? "LOADING…" : "RECENT ROUTES").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary).frame(width: 28, height: 28)
                    .accessibilityLabel("Back to Wallet")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Toll Spend").font(EType.display).foregroundStyle(palette.textPrimary)
                    Text(vm.headerSub)
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Hero — MTD spend + reimbursable/absorbed split bar

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TOLL SPEND · \(vm.monthLabel)").font(EType.micro).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        Text(vm.spendMTD).font(.system(size: 38, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("REIMBURSABLE").font(EType.micro).tracking(0.6).foregroundStyle(Brand.success)
                        Text(vm.reimbursable).font(.system(size: 16, weight: .bold).monospacedDigit())
                            .foregroundStyle(Brand.success)
                        Text("ABSORBED").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                            .padding(.top, 2)
                        Text(vm.absorbed).font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                splitBar.padding(.top, Space.s3)
                Text(vm.splitCaption).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s2)
            }
            .padding(Space.s4)
        }
        .frame(height: 150)
    }

    private var splitBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.rail.opacity(0.18))
                Capsule().fill(Brand.rail).frame(width: geo.size.width)
                Capsule().fill(LinearGradient(colors: [Brand.success, Color(hex: 0x00A57A)],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * vm.reimbursableFrac)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("\(Int(vm.reimbursableFrac * 100)) percent reimbursable")
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiTile("$ / LOADED MI", vm.perLoadedMile, sub: vm.perMileDelta,
                    valueStyle: AnyShapeStyle(LinearGradient.diagonal), subColor: palette.textSecondary)
            kpiTile("TOLL EVENTS", vm.tollEvents, sub: vm.tollEventsSub,
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: palette.textSecondary)
            kpiTile("IFTA BASIS", vm.iftaBasis, sub: vm.iftaBasisSub,
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: palette.textSecondary)
        }
    }

    private func kpiTile(_ label: String, _ value: String, sub: String,
                         valueStyle: AnyShapeStyle, subColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 26, weight: .semibold).monospacedDigit()).foregroundStyle(valueStyle)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(EType.caption).foregroundStyle(subColor).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Corridor ledger

    private var corridorSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RECENT ROUTES · TOLL BASIS").font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.corridorCount).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                if vm.corridors.isEmpty {
                    EusoEmptyState(
                        systemImage: "road.lanes",
                        title: loading ? "Loading recent routes…" : "No completed routes yet",
                        subtitle: loading ? "" : (loadError ?? "Run-ticket toll expenses appear here after drivers submit receipts or connected toll providers sync transactions.")
                    )
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(vm.corridors.enumerated()), id: \.element.id) { idx, c in
                        Button {
                            selectedLoadId = c.loadNumber
                            if c.loadNumber == nil {
                                actionMessage = nil
                                actionError = "This toll expense is not matched to a load yet."
                            }
                        } label: {
                            corridorRow(c)
                        }
                        .buttonStyle(.plain)
                        if idx < vm.corridors.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 52)
                        }
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func verdictColor_399(_ v: TollCorridor_399.Verdict) -> Color {
        switch v {
        case .reimbursable: return Brand.success
        case .absorbed:     return Brand.warning
        case .unknown:      return palette.textTertiary
        }
    }

    private func corridorRow(_ c: TollCorridor_399) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(c.tint.opacity(0.14))
                Image(systemName: c.verdict == .absorbed ? "exclamationmark.triangle" : "road.lanes")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(c.tint)
            }.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(c.tagLine).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                Text(c.amount).font(EType.bodyStrong).monospacedDigit().foregroundStyle(palette.textPrimary)
                Text(c.verdictLabel).font(.system(size: 10, weight: .bold)).tracking(0.6)
                    .foregroundStyle(verdictColor_399(c.verdict))
            }
        }
        .padding(Space.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.name), \(c.amount), \(c.verdictLabel)")
    }

    // MARK: ESang insight

    private var insightRow: some View {
        Button {
            if let first = vm.corridors.first(where: { $0.loadNumber != nil })?.loadNumber {
                selectedLoadId = first
            } else {
                actionMessage = nil
                actionError = vm.corridors.isEmpty
                    ? "No toll expense rows are available yet."
                    : "No toll expenses are matched to a load yet."
            }
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                 center: .init(x: 0.35, y: 0.30), startRadius: 0, endRadius: 16))
                }.frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.insightTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text(vm.insightSub).font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button {
                    if let first = vm.corridors.first(where: { $0.loadNumber != nil })?.loadNumber {
                        actionError = nil
                        actionMessage = "Opening matched load \(first)."
                        selectedLoadId = first
                    } else {
                        actionMessage = nil
                        actionError = "No toll expense is matched to a load yet."
                    }
                } label: {
                    Text("Review matched loads").font(EType.bodyStrong).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
                }.buttonStyle(.plain)
                Button {
                    showIFTA = true
                } label: {
                    Text("IFTA export").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        .frame(width: 144, height: 48)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                }.buttonStyle(.plain)
            }
            if let actionMessage {
                Text(actionMessage).font(EType.caption).foregroundStyle(Brand.success)
            }
            if let actionError {
                Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }

    // MARK: Network

    private struct RecentRoutesInput_399: Encodable { let limit: Int }
    private struct TollLedgerInput_399: Encodable { let limit: Int }

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }

        do {
            async let ledgerTask: TollLedgerWire_399 = EusoTripAPI.shared.query(
                "tolls.getSpendLedger",
                input: TollLedgerInput_399(limit: 50)
            )
            async let routesTask: [RecentRouteWire_399] = EusoTripAPI.shared.query(
                "tolls.getRecentRoutes",
                input: RecentRoutesInput_399(limit: 8)
            )
            async let iftaTask: IftaAPI.Estimate? = fetchIftaEstimate_399()

            let ledger = try await ledgerTask
            let ifta = await iftaTask
            let routes: [RecentRouteWire_399]
            do {
                routes = try await routesTask
            } catch {
                routes = []
            }

            vm = buildVM_399(ledger: ledger, routes: routes, ifta: ifta)
        } catch {
            vm = .empty
            loadError = "Couldn't reach the tolls service - retry."
        }
    }

    private func fetchIftaEstimate_399() async -> IftaAPI.Estimate? {
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        do {
            return try await EusoTripAPI.shared.ifta.estimateFromLoads(
                year: year,
                quarter: IftaAPI.Quarter.current(in: now)
            )
        } catch {
            return nil
        }
    }

    private func buildVM_399(
        ledger: TollLedgerWire_399,
        routes: [RecentRouteWire_399],
        ifta: IftaAPI.Estimate?
    ) -> TollSpendVM_399 {
        let entries = ledger.entries
        let now = Date()
        let mtdSpend = entries.reduce(0.0) { total, entry in
            guard let date = parseDate_399(entry.incurredAt),
                  Calendar.current.isDate(date, equalTo: now, toGranularity: .month)
            else { return total }
            return total + entry.amount
        }
        let quarterSpend = entries.reduce(0.0) { total, entry in
            guard let date = parseDate_399(entry.incurredAt),
                  quarterOf_399(date) == quarterOf_399(now),
                  Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: now)
            else { return total }
            return total + entry.amount
        }
        let matched = entries.filter { clean_399($0.loadNumber) != nil }
        let unmatched = entries.count - matched.count
        let matchedSpend = matched.reduce(0.0) { $0 + $1.amount }
        let unmatchedSpend = max(0, ledger.summary.totalSpend - matchedSpend)
        let totalSpend = max(ledger.summary.totalSpend, matchedSpend + unmatchedSpend)
        let reimbursableFrac = totalSpend > 0 ? matchedSpend / totalSpend : 0

        let iftaMiles = ifta?.estimatedTotalMiles ?? 0
        let perMile: String
        let perMileSub: String
        if quarterSpend > 0, iftaMiles > 0 {
            perMile = currency_399(quarterSpend / iftaMiles, fractionDigits: 3)
            perMileSub = "\(currency_399(quarterSpend)) / \(miles_399(iftaMiles)) \(IftaAPI.Quarter.current(in: now).label)"
        } else if iftaMiles > 0 {
            perMile = "—"
            perMileSub = "\(miles_399(iftaMiles)) IFTA miles"
        } else {
            perMile = "—"
            perMileSub = "Awaiting IFTA miles"
        }

        let iftaBasis: String
        let iftaSub: String
        if let ifta {
            iftaBasis = miles_399(ifta.estimatedTotalMiles)
            iftaSub = "\(ifta.loadsInPeriod) load\(ifta.loadsInPeriod == 1 ? "" : "s") · \(ifta.period)"
        } else {
            iftaBasis = "—"
            iftaSub = "Fleet IFTA unavailable"
        }

        let entryRows = entries.map { entryRow_399($0) }
        let routeRows = routes.map { routeRow_399($0) }
        let corridors = entryRows.isEmpty ? routeRows : entryRows
        let headerSub: String
        if entries.isEmpty {
            headerSub = routes.isEmpty
                ? "No toll expenses on file"
                : "\(routes.count) completed route\(routes.count == 1 ? "" : "s") · no toll expense rows"
        } else {
            headerSub = "\(entries.count) toll expense\(entries.count == 1 ? "" : "s") · run-ticket ledger"
        }

        return TollSpendVM_399(
            headerSub: headerSub,
            spendMTD: entries.isEmpty ? "—" : currency_399(mtdSpend),
            monthLabel: "MTD",
            reimbursable: entries.isEmpty ? "—" : currency_399(matchedSpend),
            absorbed: entries.isEmpty ? "—" : currency_399(unmatchedSpend),
            reimbursableFrac: reimbursableFrac,
            splitCaption: entries.isEmpty
                ? "No run-ticket toll expenses have posted for this company yet."
                : "\(matched.count) matched to loads · \(unmatched) awaiting load link",
            perLoadedMile: perMile,
            perMileDelta: perMileSub,
            tollEvents: entries.isEmpty ? "—" : "\(ledger.summary.entryCount)",
            tollEventsSub: entries.isEmpty ? "No toll rows" : "\(currency_399(ledger.summary.last30DaysSpend)) last 30d",
            iftaBasis: iftaBasis,
            iftaBasisSub: iftaSub,
            corridors: corridors,
            corridorCount: corridors.isEmpty ? "—" : "\(corridors.count) row\(corridors.count == 1 ? "" : "s")",
            insightTitle: entries.isEmpty ? "No toll spend on file" : "\(matched.count) load-matched toll row\(matched.count == 1 ? "" : "s")",
            insightSub: entries.isEmpty
                ? "Completed routes show below until toll receipts or provider transactions post."
                : "Review unmatched toll rows before settlement so pass-through costs do not leak margin."
        )
    }

    private func entryRow_399(_ entry: TollLedgerEntryWire_399) -> TollCorridor_399 {
        let routeName = [clean_399(entry.origin), clean_399(entry.destination)]
            .compactMap { $0 }
            .joined(separator: " → ")
        let matchedLoad = clean_399(entry.loadNumber)
        let name = routeName.isEmpty ? (matchedLoad ?? entry.ticketNumber) : routeName
        let dateLine = shortDate_399(entry.incurredAt)
        var lineParts = [entry.ticketNumber]
        if let matchedLoad { lineParts.append("load \(matchedLoad)") }
        if let dateLine { lineParts.append(dateLine) }
        if let desc = clean_399(entry.description) { lineParts.append(desc) }
        let matched = matchedLoad != nil
        return TollCorridor_399(
            id: "toll-\(entry.id)",
            loadNumber: matchedLoad,
            name: name,
            tagLine: lineParts.joined(separator: " · "),
            amount: currency_399(entry.amount),
            verdict: matched ? .reimbursable : .absorbed,
            verdictLabel: matched ? "LOAD MATCH" : "UNMATCHED",
            tint: matched ? Brand.success : Brand.warning
        )
    }

    private func routeRow_399(_ route: RecentRouteWire_399) -> TollCorridor_399 {
        TollCorridor_399(
            id: "route-\(route.id)",
            loadNumber: String(route.id),
            name: "\(route.origin) → \(route.destination)",
            tagLine: route.completedAt.map { "completed \(String($0.prefix(10))) · no toll expense row" }
                ?? "completed date unavailable · no toll expense row",
            amount: "—",
            verdict: .unknown,
            verdictLabel: "ROUTE",
            tint: Brand.blue
        )
    }

    private func clean_399(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "—",
              trimmed.lowercased() != "unknown"
        else { return nil }
        return trimmed
    }

    private func parseDate_399(_ value: String?) -> Date? {
        guard let value = clean_399(value) else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(value.prefix(10)))
    }

    private func shortDate_399(_ value: String?) -> String? {
        guard let date = parseDate_399(value) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func quarterOf_399(_ date: Date) -> Int {
        let month = Calendar.current.component(.month, from: date)
        return ((month - 1) / 3) + 1
    }

    private func currency_399(_ value: Double, fractionDigits: Int = 2) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = fractionDigits
        return f.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.\(fractionDigits)f", value))"
    }

    private func miles_399(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "\(f.string(from: NSNumber(value: value)) ?? "\(Int(value.rounded()))") mi"
    }
}

private struct LoadDrilldown_399: Identifiable {
    let id: String
}

// MARK: - Previews

#Preview("399 · Catalyst · Toll Spend · Night") {
    CatalystTollCorridorCostScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("399 · Catalyst · Toll Spend · Afternoon") {
    CatalystTollCorridorCostScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
