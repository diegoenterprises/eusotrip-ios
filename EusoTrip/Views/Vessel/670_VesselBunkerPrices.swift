//
//  670_VesselBunkerPrices.swift
//  EusoTrip — Vessel Operator · Bunker Prices.
//
//  Bespoke port of "670 Vessel Bunker Prices.svg" (Light + Dark) — a price-INTELLIGENCE archetype:
//  an N-point fuel-index trend chart (Path-drawn series + gridlines + end dot + legend) over a
//  grade-headline hero, a by-region price table, a fused ESang projection, and an alert/export CTA
//  pair. NOT a stat dashboard, NOT the ledger archetype of 674. Wrapped in the registered vessel
//  Shell + BottomNav (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) — copied from sibling
//  757_VesselDetentionLetters. Role: VESSEL_OPERATOR (per canonical header).
//
//  Data / wiring (endpoints confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    • vesselBunker.getPrices  (EXISTS · frontend/server/routers/vesselBunker.ts · input
//        {ports[],grades[],weeks} · returns current USD/MT bunker rows plus price history from the
//        live OilPriceMarine provider when configured, falling back only to persisted
//        vessel_bunker_records).
//    • CTA "Set BAF alert" → vesselBunker.setAlert {grade,port,threshold,direction}; persists a
//        user/company-scoped alert row through audit_logs.
//    • CTA "Export"        → vesselBunker.exportPrices; returns a CSV body written to a temporary
//        file and offered through the native share sheet.
//
//  0 mock data on load · honest empty/error states — the chart + table render only from real
//  vesselBunker state; if the provider and persisted bunker records are empty the bespoke empty
//  state shows. Seed values live ONLY in #Preview (injected via VesselBunkerPricesBody(previewSeed:)).
//  Helper types are file-scoped + suffixed 670 to avoid cross-file private collisions.
//
import SwiftUI
import Foundation

struct VesselBunkerPricesScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselBunkerPricesBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Models (file-scoped, 670-suffixed)

private struct RegionPrice670: Identifiable {
    let id: String
    let name: String
    let code: String
    let price: Double
    let delta: Double
}

private struct ExportDoc670: Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
    let rowCount: Int
}

/// Seed bundle — injected ONLY from #Preview so on-device load starts honest/empty.
private struct PreviewSeed670 {
    let series: [Double]
    let regions: [RegionPrice670]
    let esangLine: String
}

private struct VesselBunkerPricesBody: View {
    @Environment(\.palette) private var palette

    let previewSeed: PreviewSeed670?
    init(previewSeed: PreviewSeed670? = nil) { self.previewSeed = previewSeed }

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionBanner: String? = nil
    @State private var actionError: String? = nil
    @State private var busyAction: String? = nil
    @State private var showAlertSheet = false
    @State private var exportDoc: ExportDoc670? = nil

    // Real bunker-index history (drives the chart). Empty until vesselBunker returns history.
    @State private var series: [Double] = []
    @State private var regions: [RegionPrice670] = []
    @State private var esangLine = ""
    @State private var unitLabel = "USD/MT"
    @State private var primaryPort = "SGSIN"
    @State private var primaryGrade = "vlsfo"
    @State private var alertGrade = "vlsfo"
    @State private var alertPort = "SGSIN"
    @State private var alertThreshold = ""
    @State private var alertDirection = "above"

    private var hasData: Bool { series.count >= 2 || !regions.isEmpty }
    private var latest: Double { series.last ?? regions.first?.price ?? 0 }
    private var weekDelta: Double {
        guard series.count >= 2 else { return 0 }
        let prev = series[series.count - 2]
        return prev > 0 ? (latest - prev) / prev * 100 : 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading fuel index…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !hasData {
                    EusoEmptyState(systemImage: "fuelpump",
                                   title: "No bunker index to show",
                                   subtitle: "No marine bunker price history is available for this lane yet. Pull to refresh once the VLSFO or MGO feed posts data.")
                } else {
                    heroCard
                    actionStatus
                    if series.count >= 2 {
                        Text("BUNKER INDEX TREND · \(primaryGrade.uppercased()) · LAST \(series.count) PTS")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                        BunkerTrendChart670(series: series).frame(height: 172)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: Radius.lg)
                                .fill(palette.bgCard)
                                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(palette.borderFaint, lineWidth: 1)))
                    }
                    if !regions.isEmpty {
                        Text("TODAY · BY REGION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                        regionsCard
                    }
                    if !esangLine.isEmpty { esangRow }
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAlertSheet) { alertSheet }
        .sheet(item: $exportDoc) { doc in exportSheet(doc) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · BUNKER PRICES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(unitLabel).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Bunker prices").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: "FUEL · INDEX", kind: .info)
            }
        }
    }

    private var heroCard: some View {
        LifecycleCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(primaryGrade.uppercased()) · \(primaryPort)").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "$%.2f", latest)).font(.system(size: 34, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                        Text("/MT").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textTertiary)
                    }
                    Text(String(format: "%+.1f%% pt/pt", weekDelta))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(weekDelta < 0 ? Brand.success : Brand.warning)
                        .monospacedDigit()
                }
                Spacer()
                if let hi = series.max(), let lo = series.min(), series.count >= 2 {
                    VStack(alignment: .trailing, spacing: 8) {
                        labelValue("HIGH", String(format: "$%.2f", hi), palette.textPrimary)
                        labelValue("LOW",  String(format: "$%.2f", lo), palette.textPrimary)
                        labelValue("RANGE", String(format: "$%.2f", hi - lo), Brand.success)
                    }
                }
            }
        }
    }

    private func labelValue(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(valueColor).monospacedDigit()
        }
    }

    private var regionsCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(regions.enumerated()), id: \.element.id) { idx, p in
                    let tone: Color = p.delta < 0 ? Brand.success : Brand.warning
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "flag")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.info)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.info.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(p.code).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "$%.2f", p.price)).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
                            Text(String(format: "%+.1f%%", p.delta)).font(.system(size: 11)).foregroundStyle(tone).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 12)
                    if idx < regions.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    private var esangRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 14)).frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(esangLine).font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · fuel-index read on your bunker exposure").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg)
            .fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(palette.borderFaint, lineWidth: 1)))
    }

    private var ctaRow: some View {
        HStack(spacing: 12) {
            CTAButton(title: busyAction == "alert" ? "Saving..." : "Set BAF alert",
                      action: {
                          alertPort = primaryPort
                          alertGrade = primaryGrade
                          showAlertSheet = true
                      },
                      trailingIcon: "bell.badge")
            Button { Task { await exportSeries() } } label: {
                Text(busyAction == "export" ? "Exporting..." : "Export")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 144, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(palette.borderFaint, lineWidth: 1)))
            }
            .buttonStyle(.plain)
        }
    }

    private var actionStatus: some View {
        Group {
            if let actionError {
                LifecycleCard(accentDanger: true) {
                    Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
                }
            } else if let actionBanner {
                LifecycleCard {
                    Text(actionBanner).font(EType.caption).foregroundStyle(Brand.success)
                }
            }
        }
    }

    private var alertSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("BAF alert").font(.system(size: 22, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Persist an alert against the live bunker index. ESang can use this threshold when reviewing BAF exposure.")
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)

                Picker("Grade", selection: $alertGrade) {
                    ForEach(["vlsfo", "mgo", "hfo", "lng"], id: \.self) { grade in
                        Text(grade.uppercased()).tag(grade)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Direction", selection: $alertDirection) {
                    Text("Above").tag("above")
                    Text("Below").tag("below")
                }
                .pickerStyle(.segmented)

                sheetField("Port", text: $alertPort, hint: "SGSIN")
                sheetField("Threshold USD/MT", text: $alertThreshold, hint: "725")

                HStack(spacing: 8) {
                    outlineButton670("Cancel") { showAlertSheet = false }
                    CTAButton(title: busyAction == "alert" ? "Saving..." : "Save alert",
                              action: { Task { await setAlert() } },
                              trailingIcon: "checkmark")
                }
            }
            .padding(Space.s5)
        }
        .background(palette.bgPrimary)
        .presentationDetents([.medium, .large])
    }

    private func exportSheet(_ doc: ExportDoc670) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bunker export ready").font(.system(size: 22, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("\(doc.filename) · \(doc.rowCount) row\(doc.rowCount == 1 ? "" : "s")")
                .font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            ShareLink(item: doc.url) {
                Label("Share CSV", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            outlineButton670("Done") { exportDoc = nil }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
        .presentationDetents([.medium])
    }

    private func sheetField(_ label: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField(hint, text: text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 14, weight: .semibold))
                .padding(12)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private func outlineButton670(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func load() async {
        // Preview short-circuit: seed renders in #Preview only, never on device.
        if let seed = previewSeed {
            series = seed.series
            regions = seed.regions
            esangLine = seed.esangLine
            primaryPort = "SGSIN"
            primaryGrade = "vlsfo"
            unitLabel = "USD/MT"
            loading = false
            loadError = nil
            return
        }

        loading = true; loadError = nil
        do {
            struct BunkerQuery: Encodable { let ports: [String]; let grades: [String]; let weeks: Int }
            struct PriceRow: Decodable {
                let port: String?
                let portName: String?
                let grade: String?
                let price: Double?
                let changePercent24h: Double?
            }
            struct HistoryRow: Decodable { let date: String?; let price: Double? }
            struct PricesOut: Decodable {
                let unit: String?
                let primaryPort: String?
                let primaryGrade: String?
                let prices: [PriceRow]?
                let history: [HistoryRow]?
            }

            let res: PricesOut = try await EusoTripAPI.shared.query(
                "vesselBunker.getPrices",
                input: BunkerQuery(ports: [primaryPort], grades: ["vlsfo", "mgo"], weeks: 8)
            )

            unitLabel = res.unit ?? "USD/MT"
            primaryPort = res.primaryPort ?? primaryPort
            primaryGrade = res.primaryGrade ?? primaryGrade
            let vals = (res.history ?? []).compactMap { $0.price }.filter { $0 > 0 }
            series = vals.count >= 2 ? vals : []

            regions = (res.prices ?? []).compactMap { row in
                guard let price = row.price, price > 0 else { return nil }
                let port = row.port ?? primaryPort
                let grade = (row.grade ?? primaryGrade).uppercased()
                let name = [row.portName ?? port, grade].joined(separator: " · ")
                return RegionPrice670(
                    id: "\(port)-\(grade)",
                    name: name,
                    code: port,
                    price: price,
                    delta: row.changePercent24h ?? 0
                )
            }

            // ESang line is derived honestly from the real series (no fabricated booking figures).
            if series.count >= 2 || !regions.isEmpty {
                let dir = weekDelta >= 0 ? "rising" : "easing"
                esangLine = String(format: "%@ index %@ %+.1f%% - review BAF cover", primaryGrade.uppercased(), dir, weekDelta)
            } else {
                esangLine = ""
            }
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func setAlert() async {
        actionError = nil
        actionBanner = nil
        guard let threshold = Double(alertThreshold.trimmingCharacters(in: .whitespacesAndNewlines)), threshold > 0 else {
            actionError = "Enter a positive USD/MT threshold."
            return
        }
        let port = alertPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !port.isEmpty else {
            actionError = "Port is required."
            return
        }
        busyAction = "alert"
        do {
            struct AlertIn: Encodable { let grade: String; let port: String; let threshold: Double; let direction: String }
            struct AlertOut: Decodable { let success: Bool; let id: Int? }
            let out: AlertOut = try await EusoTripAPI.shared.mutation(
                "vesselBunker.setAlert",
                input: AlertIn(grade: alertGrade, port: port.uppercased(), threshold: threshold, direction: alertDirection)
            )
            actionBanner = out.id.map { "BAF alert #\($0) saved." } ?? (out.success ? "BAF alert saved." : "BAF alert submitted.")
            showAlertSheet = false
            alertThreshold = ""
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
        busyAction = nil
    }

    private func exportSeries() async {
        actionError = nil
        actionBanner = nil
        busyAction = "export"
        do {
            struct ExportIn: Encodable { let ports: [String]; let grades: [String]; let weeks: Int }
            struct ExportOut: Decodable { let filename: String; let rowCount: Int; let csv: String }
            let out: ExportOut = try await EusoTripAPI.shared.mutation(
                "vesselBunker.exportPrices",
                input: ExportIn(ports: [primaryPort], grades: ["vlsfo", "mgo"], weeks: 8)
            )
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(out.filename)
            guard let data = out.csv.data(using: .utf8) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: [.atomic])
            exportDoc = ExportDoc670(url: url, filename: out.filename, rowCount: out.rowCount)
            actionBanner = "Export ready: \(out.filename)."
        } catch {
            actionError = error.eusoUserCopy
        }
        busyAction = nil
    }
}

// MARK: - Trend chart (Path-drawn, no chart lib) — preserves the SVG line + area + gridline + dot look.

private struct BunkerTrendChart670: View {
    @Environment(\.palette) private var palette
    let series: [Double]

    private var yMin: Double { (series.min() ?? 0) * 0.96 }
    private var yMax: Double { (series.max() ?? 1) * 1.04 }

    private func pt(_ i: Int, _ v: Double, _ size: CGSize, plotH: CGFloat) -> CGPoint {
        let n = max(1, series.count - 1)
        let span = max(0.0001, yMax - yMin)
        let x = size.width * CGFloat(i) / CGFloat(n)
        let y = plotH * CGFloat(1 - (v - yMin) / span)
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { geo in
            let plotH = geo.size.height - 28   // leave room for the legend
            let span = max(0.0001, yMax - yMin)
            let mid = yMin + span * 0.5
            let upper = yMin + span * 0.8
            ZStack(alignment: .topLeading) {
                // gridlines @ mid + upper of the live range
                ForEach([upper, mid], id: \.self) { g in
                    let y = plotH * CGFloat(1 - (g - yMin) / span)
                    Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                        .stroke(palette.borderFaint, lineWidth: 1)
                }
                // area under the line
                Path { p in
                    p.move(to: CGPoint(x: 0, y: plotH))
                    for (i, v) in series.enumerated() { p.addLine(to: pt(i, v, geo.size, plotH: plotH)) }
                    p.addLine(to: CGPoint(x: geo.size.width, y: plotH)); p.closeSubpath()
                }.fill(LinearGradient(colors: [Brand.info.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                // primary line
                Path { p in
                    for (i, v) in series.enumerated() {
                        let q = pt(i, v, geo.size, plotH: plotH)
                        if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                    }
                }.stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                // end dot
                Circle().fill(LinearGradient.diagonal).frame(width: 8, height: 8)
                    .position(pt(series.count - 1, series.last ?? 0, geo.size, plotH: plotH))
                // legend
                HStack(spacing: 6) {
                    Capsule().fill(LinearGradient.primary).frame(width: 12, height: 3)
                    Text(String(format: "EIA DIESEL $%.2f/gal", series.last ?? 0))
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                .position(x: geo.size.width / 2, y: geo.size.height - 6)
            }
        }
    }
}

// MARK: - Previews (seed lives ONLY here)

private let previewSeed670 = PreviewSeed670(
    series: [3.42, 3.48, 3.51, 3.55, 3.58, 3.62, 3.66, 3.71],
    regions: [
        .init(id: "preview-gulf", name: "Gulf Coast", code: "PADD3", price: 3.49, delta: -0.6),
        .init(id: "preview-midwest", name: "Midwest", code: "PADD2", price: 3.62, delta:  1.4),
        .init(id: "preview-west", name: "West Coast", code: "PADD5", price: 4.18, delta:  2.1),
    ],
    esangLine: "Index rising +1.4% pt/pt - review BAF cover")

/// Preview-only Shell wrapper that injects the seed into the body so the populated bespoke
/// chart/table render in Xcode previews. The seed is referenced ONLY from here — on device the
/// public `VesselBunkerPricesScreen` builds the body with no seed, so it loads live or empty.
private struct VesselBunkerPricesPreview670: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselBunkerPricesBody(previewSeed: previewSeed670)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

#Preview("670 · Vessel Bunker Prices · Night") {
    VesselBunkerPricesPreview670(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("670 · Vessel Bunker Prices · Light") {
    VesselBunkerPricesPreview670(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
