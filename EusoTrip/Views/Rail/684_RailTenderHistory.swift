//
//  684_RailTenderHistory.swift
//  EusoTrip — Rail · Shipper · Tender History (brick 684).
//
//  Verbatim SwiftUI port of "05 Rail/684 Rail Tender History" (Dark).
//  SHIPPER-SIDE OUTCOME win-rate LEDGER: an accept-rate hero with a split bar
//  (accepted / declined / expired) over a chronological tender-outcome list.
//  tenderHistory used to return a hardcoded empty array; §67 made it persist —
//  this screen reads that real ledger. Composition follows function — a win-
//  rate ledger, NOT a live board.
//
//  Web parity: app/(rail)/tender/history/page.tsx.
//
//  tRPC wiring (this is a fully-real read screen):
//    • list ← railTenderWorkflow.tenderHistory      (EXISTS railTenderWorkflow.ts:435 —
//              BARE ARRAY of tender rows, tenant-scoped; rateUsd is null on a
//              tender event, so the rate column renders honest em-dash)
//    • win-rate ← computed from the loaded ledger (accepted / total)
//    • filter chips re-query tenderHistory with the status filter (EXISTS input)
//
//  RBAC: protectedProcedure (dual-leg tenant scope). transportMode = rail ·
//  tri-country currency band US USD / CA CAD / MX MXN.
//  BottomNav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen root

struct RailTenderHistoryScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) { RailTenderHistoryBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person.fill",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data (mirror the tenderHistory row)

private struct TenderRow684: Decodable, Identifiable {
    let id: Int
    let carrier: String?
    let origin: String?
    let destination: String?
    let originScac: String?
    let destinationScac: String?
    let outcome: String?
    let status: String?
    let rateUsd: Double?
    let timestamp: String?
    let commodityStcc: String?

    var lane: String {
        let o = origin ?? originScac ?? "—"
        let d = destination ?? destinationScac ?? "—"
        return "\(o) → \(d)"
    }
    var outcomeKey: String { (outcome ?? status ?? "submitted").lowercased() }
}

private enum HistoryFilter684: String, CaseIterable {
    case all, accepted, declined
    var label: String {
        switch self {
        case .all: return "All"; case .accepted: return "Accepted"; case .declined: return "Declined"
        }
    }
    var statusParam: String? {
        switch self {
        case .all: return nil; case .accepted: return "accepted"; case .declined: return "declined"
        }
    }
}

// MARK: - Body

private struct RailTenderHistoryBody: View {
    @Environment(\.palette) private var palette

    @State private var rows: [TenderRow684] = []
    @State private var filter: HistoryFilter684 = .all
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showExport = false

    // MARK: Derived win-rate (computed from the REAL ledger)

    private var accepted: Int { rows.filter { $0.outcomeKey == "accepted" }.count }
    private var declined: Int { rows.filter { $0.outcomeKey == "declined" }.count }
    private var expired:  Int { rows.filter { ["expired", "cancelled"].contains($0.outcomeKey) }.count }
    private var total:    Int { rows.count }
    private var winRate:  Int { total > 0 ? Int((Double(accepted) / Double(total) * 100).rounded()) : 0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterChips
                if loading {
                    LifecycleCard { Text("Loading tender ledger…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    winRateHero
                    if rows.isEmpty {
                        EusoEmptyState(systemImage: "tray",
                                       title: "No tenders yet",
                                       subtitle: "Tender outcomes for your rail lanes appear here as carriers accept, decline, or let an offer expire.")
                    } else {
                        outcomeSection
                    }
                    regimeRow
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showExport) { exportSheet }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("✦ SHIPPER · RAIL · TENDER HISTORY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("180-DAY")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Tender history")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 10)
            Text("Eusorone Technologies · \(total) tenders · 180 days")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary).padding(.top, 4)
            IridescentHairline().padding(.top, 14)
        }
    }

    private var filterChips: some View {
        HStack(spacing: Space.s2) {
            ForEach(HistoryFilter684.allCases, id: \.self) { f in
                Button {
                    filter = f
                    Task { await load() }
                } label: {
                    Text(f.label)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(filter == f ? Color(hex: 0x6FA8FF) : palette.textSecondary)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(filter == f ? Color(hex: 0x6FA8FF).opacity(0.14) : palette.bgCard))
                        .overlay(Capsule().strokeBorder(filter == f ? Color.clear : palette.borderFaint))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Win-rate hero

    private var winRateHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.success)
                Text("WIN RATE · LAST 180 DAYS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.success)
                Spacer(minLength: 4)
                Text(total > 0 ? "\(accepted)/\(total)" : "—")
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.success.opacity(0.14)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(winRate)%")
                    .font(.system(size: 30, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("accepted").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textSecondary)
                    Text("\(accepted) acc · \(declined) dec · \(expired) exp of \(total)")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                }
            }
            // 3-segment split bar (accepted / declined / expired)
            GeometryReader { geo in
                let w = geo.size.width
                let denom = max(total, 1)
                let accW = w * CGFloat(accepted) / CGFloat(denom)
                let decW = w * CGFloat(declined) / CGFloat(denom)
                let expW = w * CGFloat(expired) / CGFloat(denom)
                HStack(spacing: 0) {
                    Rectangle().fill(Brand.success).frame(width: accW)
                    Rectangle().fill(Brand.warning).frame(width: decW)
                    Rectangle().fill(palette.textTertiary).frame(width: expW)
                    Rectangle().fill(Color.white.opacity(0.14))
                }
                .clipShape(Capsule())
            }
            .frame(height: 9)
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Outcome list

    private var outcomeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TENDER OUTCOMES · \(rows.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Color(hex: 0x9FB0BE))
                Spacer()
                Text("newest first").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    outcomeRow(row)
                    if idx < rows.count - 1 { Divider().padding(.horizontal, 16).overlay(palette.borderFaint) }
                }
            }
            .padding(.vertical, 6)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    @ViewBuilder
    private func outcomeRow(_ row: TenderRow684) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dayLabel(row.timestamp))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 10) {
                    Text(row.lane).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(row.carrier ?? "—").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                outcomeChip(row.outcomeKey)
                Text(row.rateUsd.map { "$\(Int($0).formatted(.number.grouping(.automatic)))" } ?? "—")
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func outcomeChip(_ key: String) -> some View {
        switch key {
        case "accepted":
            chip("ACCEPTED", Brand.success, Brand.success.opacity(0.14))
        case "declined":
            chip("DECLINED", Color(hex: 0xFF6B5E), Color(hex: 0xFF6B5E).opacity(0.14))
        case "expired", "cancelled":
            chip("EXPIRED", Brand.warning, Brand.warning.opacity(0.16))
        case "pending":
            chip("PENDING", Color(hex: 0x6FA8FF), Color(hex: 0x6FA8FF).opacity(0.14))
        default:
            chip("SUBMITTED", palette.textSecondary, Color.white.opacity(0.06))
        }
    }

    @ViewBuilder
    private func chip(_ text: String, _ fg: Color, _ bg: Color) -> some View {
        Text(text).font(.system(size: 9.5, weight: .heavy)).tracking(0.3)
            .foregroundStyle(fg)
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Capsule().fill(bg))
    }

    private func dayLabel(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "dd MMM"
        return f.string(from: d)
    }

    // MARK: Regime chips

    private var regimeRow: some View {
        HStack(spacing: Space.s2) {
            regimeChip("US · USD", "STB rate", active: true)
            regimeChip("CA · CAD", "CTA rate", active: false)
            regimeChip("MX · MXN", "ARTF tarifa", active: false)
        }
    }

    @ViewBuilder
    private func regimeChip(_ title: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
            Text(sub).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(active ? Color(hex: 0x6FA8FF).opacity(0.20) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderFaint))
    }

    // MARK: CTA + export

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Export ledger",
                      action: { showExport = true },
                      trailingIcon: "square.and.arrow.up")
            RailSecondaryActionButton(
                title: "Filter",
                sheetTitle: "Ledger filter · \(filter.label)",
                lines: [
                    "Showing \(rows.count) tenders · filter \(filter.label)",
                    "\(accepted) accepted · \(declined) declined · \(expired) expired",
                    "Win rate \(winRate)% over the last 180 days",
                    "Rate column is honest-blank — a tender event stores no rate until a settlement links."
                ],
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
    }

    private var exportLines: [String] {
        rows.map { r in
            "\(dayLabel(r.timestamp)) · \(r.lane) · \(r.carrier ?? "—") · \(r.outcomeKey.uppercased())"
        }
    }

    private var exportSheet: some View {
        let body = ([
            "EusoTrip · Rail Tender Ledger",
            "Win rate \(winRate)% · \(accepted) acc / \(declined) dec / \(expired) exp of \(total)",
            ""
        ] + exportLines).joined(separator: "\n")
        return NavigationStack {
            ScrollView {
                Text(body)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s4)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: body) { Text("Share") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showExport = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct HistIn: Encodable { let status: String?; let limit: Int }
        do {
            let out = try await EusoTripAPI.shared.query(
                "railTenderWorkflow.tenderHistory",
                input: HistIn(status: filter.statusParam, limit: 100)) as [TenderRow684]
            self.rows = out
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("684 · Rail Tender History · Night") {
    RailTenderHistoryScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("684 · Rail Tender History · Light") {
    RailTenderHistoryScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
