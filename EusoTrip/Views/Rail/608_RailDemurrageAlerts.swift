//
//  608_RailDemurrageAlerts.swift
//  EusoTrip — Rail Engineer · Demurrage Alerts (carrier-side MONEY archetype).
//
//  Reconstructed from the stamped gauge+3KPI+3row skeleton into a purpose-built
//  money surface: an aggregate 72h $-exposure FORECAST hero (cumulative accrual
//  curve + now-line) over a ranked per-car DETENTION RUNWAY ledger (free-time
//  consumed vs the free-time window, $ today + $ projected). Ranks which dropped
//  cars are about to start charging and the dollars at stake so the engineer
//  disputes/dispatches before per-diem ignites.
//
//  Live wiring: railDemurrageAuto.dashboard (forecastSeries + perCarRunway +
//  summary) → the curve + KPI + runway; per-car "Dispute" → createDispute
//  (confirm-gated). Honest: empty runway → an honest "no cars accruing" state,
//  never a fabricated curve.
//

import SwiftUI

struct RailDemurrageAlertsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDemurrageAlertsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodable model (matches railDemurrageAuto.dashboard)

private struct ForecastPoint608: Decodable, Identifiable {
    var id: Int { hours }
    let hours: Int
    let cumUsd: Double
}

private struct RunwayCar608: Decodable, Identifiable {
    var id: Int { demurrageId }
    let demurrageId: Int
    let railcarNumber: String?
    let freeTimeHours: Int?
    let chargeableHours: Int?
    let ratePerHour: Double?
    let usdToday: Double?
    let usdProjected: Double?
}

private struct DemurrageSummary608: Decodable {
    let activeAccruals: Int?
    let totalChargesAccruing: Double?
    let disputesOpen: Int?
}

private struct Dashboard608: Decodable {
    let forecastSeries: [ForecastPoint608]?
    let perCarRunway: [RunwayCar608]?
    let summary: DemurrageSummary608?
}

private struct DisputeResult608: Decodable {
    let disputeId: String?
    let status: String?
}

private enum DisputeReason608: String, CaseIterable, Identifiable {
    case serviceFailure = "service_failure"
    case weather = "weather"
    case customerError = "customer_error"
    case dataError = "data_error"
    case other = "other"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .serviceFailure: return "Service failure"
        case .weather: return "Weather"
        case .customerError: return "Customer error"
        case .dataError: return "Data error"
        case .other: return "Other"
        }
    }
}

// MARK: - Body

private struct RailDemurrageAlertsBody: View {
    @Environment(\.palette) private var palette
    @State private var data: Dashboard608? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Dispute flow
    @State private var disputeCar: RunwayCar608? = nil
    @State private var disputeReason: DisputeReason608 = .serviceFailure
    @State private var disputeSubmitting = false
    @State private var toast: String? = nil

    private var cars: [RunwayCar608] { data?.perCarRunway ?? [] }
    private var series: [ForecastPoint608] { data?.forecastSeries ?? [] }
    private var totalNow: Double { data?.summary?.totalChargesAccruing ?? 0 }

    private func riskColor(_ c: RunwayCar608) -> Color {
        let free = Double(c.freeTimeHours ?? 48)
        let used = Double(c.chargeableHours ?? 0)
        if used > 0 { return Brand.danger }               // already charging
        if free - used < 12 { return Brand.warning }       // near the window
        return Brand.success
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading demurrage exposure…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    forecastHero
                    kpiStrip
                    if cars.isEmpty {
                        LifecycleCard { Text("No cars accruing demurrage right now.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                    } else {
                        runwayLedger
                    }
                    CTAButton(title: "Burndown by dwell reason", leadingIcon: "chart.bar.xaxis")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(item: $disputeCar) { car in disputeSheet(car) }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.badge.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · DEMURRAGE ALERTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Demurrage alerts")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Forecast hero — 72h cumulative $-exposure curve

    private var forecastHero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("72H EXPOSURE")
                        .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textTertiary.opacity(0.10)))
                    Spacer()
                    Text("now $\(Int(totalNow))")
                        .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                }
                ForecastCurve608(points: series, lineColor: Brand.danger, palette: palette)
                    .frame(height: 92)
                HStack {
                    Text("now")
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("+72h projected $\(Int(series.last?.cumUsd ?? totalNow))")
                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 172)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "ACCRUING", value: "$\(Int(totalNow))", gradientNumeral: true)
            MetricTile(label: "CARS", value: "\(data?.summary?.activeAccruals ?? cars.count)", accent: Brand.warning)
            MetricTile(label: "DISPUTES", value: "\(data?.summary?.disputesOpen ?? 0)", accent: Brand.info)
        }
    }

    // MARK: Runway ledger

    private var runwayLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DETENTION RUNWAY · ranked by $ at stake")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(cars.sorted { ($0.usdProjected ?? 0) > ($1.usdProjected ?? 0) }) { c in runwayRow(c) }
            }
        }
    }

    private func runwayRow(_ c: RunwayCar608) -> some View {
        let color = riskColor(c)
        let free = Double(c.freeTimeHours ?? 48)
        let used = Double(c.chargeableHours ?? 0)
        // Fraction of the free-time window consumed (>1 → already charging).
        let frac = min(used / max(free, 1), 1.0)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.railcarNumber ?? "—")
                        .font(.system(size: 13, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                    Text("\(Int(free))h free · \(Int(used))h over · $\(Int(c.ratePerHour ?? 0))/h")
                        .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("$\(Int(c.usdToday ?? 0))")
                        .font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(color)
                    Text("→ $\(Int(c.usdProjected ?? 0)) / 24h")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            // Free-time runway bar with a tip marker at the consumed fraction.
            RunwayBar608(fraction: frac, color: color, palette: palette)
            HStack {
                Spacer()
                Button {
                    disputeCar = c
                    disputeReason = .serviceFailure
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "flag.fill").font(.system(size: 10, weight: .heavy))
                        Text("Dispute").font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(color)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(color.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.s3)
        .background(used > 0 ? Brand.danger.opacity(0.06) : palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(used > 0 ? Brand.danger.opacity(0.30) : palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Dispute sheet

    private func disputeSheet(_ car: RunwayCar608) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPUTE DEMURRAGE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Dispute \(car.railcarNumber ?? "car") · $\(Int(car.usdToday ?? 0))")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3).foregroundStyle(palette.textPrimary)
            Text("Contest this detention charge. It drops out of billing until an operator resolves the dispute.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)

            VStack(alignment: .leading, spacing: Space.s2) {
                Text("REASON").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                ForEach(DisputeReason608.allCases) { reason in
                    Button {
                        disputeReason = reason
                    } label: {
                        HStack {
                            Image(systemName: disputeReason == reason ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(disputeReason == reason ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                            Text(reason.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                            Spacer()
                        }
                        .padding(Space.s3)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(disputeReason == reason ? palette.borderFaint : Color.clear))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                Task { await submitDispute(car) }
            } label: {
                HStack {
                    Spacer()
                    if disputeSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Submit dispute").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(disputeSubmitting)

            Spacer()
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Data

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        do {
            self.data = try await EusoTripAPI.shared.query("railDemurrageAuto.dashboard", input: Empty())
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func submitDispute(_ car: RunwayCar608) async {
        struct DisputeInput: Encodable { let confirm: Bool; let demurrageId: Int; let reason: String }
        disputeSubmitting = true
        do {
            let _: DisputeResult608 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.createDispute",
                input: DisputeInput(confirm: true, demurrageId: car.demurrageId, reason: disputeReason.rawValue)
            )
            disputeCar = nil
            withAnimation(.easeOut(duration: 0.18)) { toast = "Dispute filed for \(car.railcarNumber ?? "car")" }
            await load()
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        } catch {
            withAnimation(.easeOut(duration: 0.18)) { toast = (error as? EusoTripAPIError)?.errorDescription ?? "Dispute failed" }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
        disputeSubmitting = false
    }
}

// MARK: - Forecast curve (cumulative $-exposure over 72h)
//
// A cumulative accrual curve drawn from the real forecastSeries. The area fills
// with a gradient and the line strokes on top; a now-line marks hour 0. The
// curve draws in on appear (trim 0→1) with a decelerating ease; Reduce Motion
// snaps it straight to full. Honest: an empty series renders a flat baseline,
// never a fabricated ramp.
private struct ForecastCurve608: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let points: [ForecastPoint608]
    let lineColor: Color
    let palette: Theme.Palette
    @State private var drawn: CGFloat = 0

    private func point(_ p: ForecastPoint608, w: CGFloat, h: CGFloat, maxHours: Double, maxUsd: Double) -> CGPoint {
        let x = maxHours > 0 ? CGFloat(Double(p.hours) / maxHours) * w : 0
        let y = h - CGFloat(p.cumUsd / maxUsd) * (h - 6) - 3
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let sorted = points.sorted { $0.hours < $1.hours }
            let maxHours = Double(sorted.last?.hours ?? 72)
            let maxUsd = max(sorted.map { $0.cumUsd }.max() ?? 1, 1)

            ZStack {
                // Baseline grid
                Path { p in p.move(to: CGPoint(x: 0, y: h - 3)); p.addLine(to: CGPoint(x: w, y: h - 3)) }
                    .stroke(palette.borderFaint, lineWidth: 1)

                if sorted.count >= 2 {
                    // Area fill
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h - 3))
                        for pnt in sorted { p.addLine(to: point(pnt, w: w, h: h, maxHours: maxHours, maxUsd: maxUsd)) }
                        p.addLine(to: CGPoint(x: point(sorted.last!, w: w, h: h, maxHours: maxHours, maxUsd: maxUsd).x, y: h - 3))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [lineColor.opacity(0.28), lineColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .mask(Rectangle().frame(width: w * drawn).offset(x: -(w * (1 - drawn)) / 2))

                    // Line
                    Path { p in
                        p.move(to: point(sorted.first!, w: w, h: h, maxHours: maxHours, maxUsd: maxUsd))
                        for pnt in sorted.dropFirst() { p.addLine(to: point(pnt, w: w, h: h, maxHours: maxHours, maxUsd: maxUsd)) }
                    }
                    .trim(from: 0, to: drawn)
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    // Now-line at hour 0
                    Path { p in p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: h)) }
                        .stroke(palette.textTertiary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .onAppear {
                if reduceMotion { drawn = 1 }
                else { withAnimation(.easeOut(duration: 0.6)) { drawn = 1 } }
            }
        }
    }
}

// MARK: - Runway bar (free-time consumed, with tip marker)

private struct RunwayBar608: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fraction: Double
    let color: Color
    let palette: Theme.Palette
    @State private var shown: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.14)).frame(height: 6)
                Capsule().fill(color).frame(width: max(4, w * shown), height: 6)
                // Tip marker at the consumed fraction
                Circle().fill(color).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(palette.bgCard, lineWidth: 2))
                    .offset(x: max(0, w * shown - 5))
            }
        }
        .frame(height: 10)
        .onAppear {
            if reduceMotion { shown = CGFloat(fraction) }
            else { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { shown = CGFloat(fraction) } }
        }
        .onChange(of: fraction) { _, newValue in
            if reduceMotion { shown = CGFloat(newValue) }
            else { withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { shown = CGFloat(newValue) } }
        }
    }
}

#Preview("608 · Rail Demurrage Alerts · Night") { RailDemurrageAlertsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("608 · Rail Demurrage Alerts · Light") { RailDemurrageAlertsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
