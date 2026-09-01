//
//  797_VesselFuelSurchargeTracking.swift
//  EusoTrip — Vessel Operator · Fuel Surcharge Tracking (INDEX-TREND archetype).
//
//  Faithful port of "797 Vessel Fuel Surcharge Tracking.svg" (Dark + Light). Tracks
//  the ocean bunker surcharge (BAF) applied to live sailings — a gradient MTD hero
//  with the DOE reference + average applied rate, an applied-FSC-rate trend built
//  from the live sailings, and a per-sailing surcharge ledger — so the operator sees
//  the rate basis behind every fuel line at a glance instead of reconciling a
//  spreadsheet of bunker rates.
//
//  Nav: Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), SHIPMENTS inked.
//
//  REAL WIRING (tRPC · server/routers/detentionAccessorials.ts):
//    · detentionAccessorials.getFuelSurchargeTracking  {dateFrom?, dateTo?, limit}
//        -> { surcharges:[{id, loadId, loadRate, surchargeAmount, surchargePercent,
//              origin, destination, status, appliedDate}],
//              summary:{ total, totalAmount, avgRate, currentDOEPrice } }  (:1881)
//        companyId-scoped (dc.type='fuel_surcharge'). Hero = summary.totalAmount +
//        summary.avgRate; the trend + ledger are the live surcharge rows.
//    · "Export BAF report" composes a BAF CSV from the LIVE rows and opens the native
//        share sheet (server exportFuelSurchargeReport is a NAMED GAP · honest interim).
//    · "Rates" toggles the FSC-basis detail (DOE reference + the index gap below).
//
//  DEGRADED (honest, surfaced not hidden): summary.currentDOEPrice is hard-coded 3.85
//  in-router ("would pull from DOE API in production") — a live VLSFO/bunker index feed
//  is a NAMED GAP. The "INDEX FEED · DOE GAP" chip flags this rather than presenting a
//  stale price as a live index; the trend is drawn from the REAL applied FSC rate per
//  sailing, never a fabricated 10-week index series.
//
//  RBAC: getFuelSurchargeTracking protectedProcedure (isolated · companyId-scoped).
//  transportMode=vessel · USD. NO mock data — every sailing, dollar and rate is a live row.
//

import SwiftUI
import UIKit

struct VesselFuelSurchargeTrackingScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselFuelSurchargeTrackingBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct FuelSurchargeResult797: Decodable {
    let surcharges: [FuelSurcharge797]
    let summary: FuelSurchargeSummary797?
}

private struct FuelSurchargeSummary797: Decodable {
    let total: Int?
    let totalAmount: Double?
    let avgRate: Double?
    let currentDOEPrice: Double?
}

private struct FuelSurcharge797: Decodable, Identifiable {
    let id: Int
    let loadId: Int?
    let loadRate: Double?
    let surchargeAmount: Double?
    let surchargePercent: Double?
    let origin: String?
    let destination: String?
    let status: String?
    let appliedDate: String?
}

// MARK: - Body

private struct VesselFuelSurchargeTrackingBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.vesselOperatorNavHandler) private var navHandler

    @State private var surcharges: [FuelSurcharge797] = []
    @State private var summary: FuelSurchargeSummary797? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showRates = false
    @State private var exportDoc: ShareDoc797? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                IridescentHairline().padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        errorCard(err)
                    } else {
                        heroCard
                        trendSection
                        if showRates { basisCard }
                        sailingsSection
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .sheet(item: $exportDoc) { doc in ActivityShareSheet797(items: [doc.url]) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("VESSEL OPERATOR · FUEL SURCHARGE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("BAF · VES").font(EType.mono(.micro)).tracking(0.8).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Button { navHandler?("Shipments") } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }.buttonStyle(.plain)
                Text("Bunker surcharge")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Text("BAF").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.info)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.info.opacity(0.18)))
            }
            .padding(.top, Space.s3)
        }
    }

    // MARK: Hero (gradient-rim · MTD total + DOE ref + avg rate)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("VLSFO · bunker reference")
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(palette.textPrimary.opacity(0.08)))
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BUNKER SURCHARGE · MTD")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text(money(summary?.totalAmount ?? 0))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Space.s3) {
                    heroStat(label: "DOE REF", value: doeRefText, tone: palette.textPrimary)
                    heroStat(label: "AVG RATE", value: pct(summary?.avgRate ?? 0), tone: Brand.warning)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }

    private func heroStat(label: String, value: String, tone: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(tone)
        }
    }

    // MARK: Applied-FSC-rate trend (real, from live sailings)

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("APPLIED FSC RATE · BY SAILING (%)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("INDEX FEED · DOE GAP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Brand.warning.opacity(0.18)))
            }
            if trendPoints.count >= 2 {
                FSCTrendChart797(points: trendPoints, minY: trendMin, maxY: trendMax)
                    .frame(height: 132)
                    .padding(Space.s4)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            } else {
                EusoEmptyState(systemImage: "chart.line.uptrend.xyaxis",
                               title: "Not enough sailings to trend",
                               subtitle: "The applied-FSC trend draws once two or more sailings carry a bunker surcharge — never a fabricated index.")
            }
        }
    }

    // MARK: FSC basis detail (Rates toggle)

    private var basisCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FSC BASIS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            basisRow("DOE reference", doeRefText)
            basisRow("Average applied rate", pct(summary?.avgRate ?? 0))
            basisRow("Sailings with FSC", "\(summary?.total ?? surcharges.count)")
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("No verified VLSFO or bunker index is linked. The DOE reference is shown separately.")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 2)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func basisRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Per-sailing ledger

    private var sailingsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SURCHARGE BY SAILING · \(surcharges.count) ACTIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if surcharges.isEmpty {
                EusoEmptyState(systemImage: "fuelpump",
                               title: "No bunker surcharge applied",
                               subtitle: "BAF lines appear here once a sailing accrues a fuel surcharge against its linehaul.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(surcharges.enumerated()), id: \.element.id) { idx, sc in
                        sailingRow(sc)
                        if idx < surcharges.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func sailingRow(_ sc: FuelSurcharge797) -> some View {
        let applied = (sc.status ?? "").lowercased().contains("appl")
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.info.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "ferry.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.info)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(lane(sc)).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("\(pct(sc.surchargePercent ?? 0)) of linehaul · \(appliedLabel(sc))")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(applied ? "APPLIED" : "PENDING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(applied ? Brand.success : Brand.warning)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill((applied ? Brand.success : Brand.warning).opacity(0.18)))
                Text(money(sc.surchargeAmount ?? 0))
                    .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { exportBAF() } label: {
                Text("Export BAF report").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(LinearGradient.primary).clipShape(Capsule())
            }
            .buttonStyle(.plain).disabled(surcharges.isEmpty).opacity(surcharges.isEmpty ? 0.6 : 1.0)

            Button { withAnimation(.easeOut(duration: 0.18)) { showRates.toggle() } } label: {
                Text(showRates ? "Hide" : "Rates").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 108, minHeight: 50).padding(.horizontal, Space.s3)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 172)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Derived

    private var doeRefText: String {
        guard let p = summary?.currentDOEPrice, p > 0 else { return "—" }
        return "$\(String(format: "%.2f", p))/gal"
    }

    /// Real trend points — applied FSC rate ordered by appliedDate.
    private var trendPoints: [Double] {
        let sorted = surcharges.sorted { ($0.appliedDate ?? "") < ($1.appliedDate ?? "") }
        return sorted.map { $0.surchargePercent ?? 0 }
    }
    private var trendMin: Double { max(0, (trendPoints.min() ?? 0) - 1) }
    private var trendMax: Double { (trendPoints.max() ?? 1) + 1 }

    private func lane(_ sc: FuelSurcharge797) -> String {
        let o = cleanLoc(sc.origin), d = cleanLoc(sc.destination)
        if o.isEmpty && d.isEmpty { return sc.loadId.map { "VES-\($0)" } ?? "Sailing #\(sc.id)" }
        return "\(o.isEmpty ? "—" : o) → \(d.isEmpty ? "—" : d)"
    }
    private func cleanLoc(_ s: String?) -> String {
        guard let s, !s.isEmpty, s != "N/A" else { return "" }
        return s
    }
    private func appliedLabel(_ sc: FuelSurcharge797) -> String {
        guard let d = shortDate(sc.appliedDate) else { return "applied" }
        return "applied \(d)"
    }
    private func shortDate(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d else { return nil }
        let out = DateFormatter(); out.dateFormat = "MM-dd"
        return out.string(from: d)
    }
    private func pct(_ v: Double) -> String { "\(String(format: "%.1f", v))%" }
    private func money(_ v: Double) -> String {
        if v == v.rounded() { return "$\(Int(v).formatted(.number.grouping(.automatic)))" }
        return "$\(String(format: "%.2f", v))"
    }

    // MARK: - Actions

    private func load() async {
        loading = true; loadError = nil
        struct FSCIn: Encodable { let limit: Int }
        do {
            let res: FuelSurchargeResult797 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getFuelSurchargeTracking", input: FSCIn(limit: 25))
            self.surcharges = res.surcharges
            self.summary = res.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func exportBAF() {
        guard !surcharges.isEmpty else { return }
        var csv = "lane,fsc_percent,surcharge_usd,linehaul_usd,status,applied_date\n"
        for sc in surcharges {
            let lane = self.lane(sc).replacingOccurrences(of: ",", with: " ")
            csv += "\(lane),\(String(format: "%.2f", sc.surchargePercent ?? 0)),"
            csv += "\(String(format: "%.2f", sc.surchargeAmount ?? 0)),\(String(format: "%.2f", sc.loadRate ?? 0)),"
            csv += "\(sc.status ?? ""),\(sc.appliedDate ?? "")\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("baf-report-\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.data(using: .utf8)?.write(to: url)
            exportDoc = ShareDoc797(url: url)
        } catch {
            loadError = "Couldn't compose the BAF report."
        }
    }
}

// MARK: - Trend chart (area + line, from real FSC rates)

private struct FSCTrendChart797: View {
    let points: [Double]
    let minY: Double
    let maxY: Double
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let span = max(maxY - minY, 0.001)
            let xs: [CGFloat] = points.count > 1
                ? points.indices.map { CGFloat($0) / CGFloat(points.count - 1) * w }
                : [w / 2]
            let ys: [CGFloat] = points.map { h - CGFloat(($0 - minY) / span) * h }

            ZStack {
                // Gridlines.
                ForEach(0..<3, id: \.self) { i in
                    let y = h * CGFloat(i) / 2
                    Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                        .stroke(palette.borderFaint, lineWidth: 1)
                }
                // Area fill.
                Path { p in
                    guard let first = xs.first, let firstY = ys.first else { return }
                    p.move(to: CGPoint(x: first, y: h))
                    p.addLine(to: CGPoint(x: first, y: firstY))
                    for i in 1..<xs.count { p.addLine(to: CGPoint(x: xs[i], y: ys[i])) }
                    p.addLine(to: CGPoint(x: xs[xs.count - 1], y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.20), Brand.magenta.opacity(0.04)],
                                     startPoint: .top, endPoint: .bottom))
                // Line.
                Path { p in
                    guard let firstY = ys.first, let firstX = xs.first else { return }
                    p.move(to: CGPoint(x: firstX, y: firstY))
                    for i in 1..<xs.count { p.addLine(to: CGPoint(x: xs[i], y: ys[i])) }
                }
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                // Latest marker.
                if let lastX = xs.last, let lastY = ys.last {
                    Circle().fill(LinearGradient.diagonal).frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(palette.bgCardSoft, lineWidth: 2))
                        .position(x: lastX, y: lastY)
                }
            }
        }
    }
}

// MARK: - Share plumbing

private struct ShareDoc797: Identifiable { let id = UUID(); let url: URL }

private struct ActivityShareSheet797: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview("797 · Vessel Fuel Surcharge Tracking · Night") {
    VesselFuelSurchargeTrackingScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("797 · Vessel Fuel Surcharge Tracking · Light") {
    VesselFuelSurchargeTrackingScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
