//
//  220_ShipperRateBoard.swift
//  EusoTrip 2027 UI — brick 220 (shipper · rate intel)
//
//  Lane-rate intel + market trend dashboard. Mirrors the shipper-
//  relevant slice of the web `ratesRouter` (no dedicated web page
//  yet — the procs are surfaced inside MarketPricing/HotZones on
//  web; iOS gets its own focused screen).
//
//  Cohort B day-1. Real wire: `rates.getMarketRates(originState,
//  destState, equipment, period)` + `rates.getFuelSurcharge`.
//

import SwiftUI

@MainActor
final class ShipperRateBoardStore: ObservableObject {
    enum LoadState {
        case idle
        case loading
        case error(String)
        case loaded(rate: ShipperRatesAPI.MarketRateResponse, fsc: ShipperRatesAPI.FuelSurcharge?)
    }

    @Published private(set) var state: LoadState = .idle
    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) { self.api = api }

    func calculate(origin: String, destination: String, equipment: String?, period: String) async {
        state = .loading
        do {
            async let r = api.ratesNS.getMarketRates(
                originState: origin, destState: destination,
                equipment: equipment, period: period
            )
            async let f: ShipperRatesAPI.FuelSurcharge? = (try? await api.ratesNS.getFuelSurcharge()) ?? nil
            let (rate, fsc) = try await (r, f)
            state = .loaded(rate: rate, fsc: fsc)
        } catch {
            state = .error("Couldn't reach rate service.")
        }
    }
}

struct ShipperRateBoard: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperRateBoardStore()

    @State private var origin: String = "TX"
    @State private var dest: String = "GA"
    @State private var equipment: String = "dry_van"
    @State private var period: String = "month"

    private static let equipments: [(String, String)] = [
        ("dry_van", "Dry van"), ("reefer", "Reefer"),
        ("flatbed", "Flatbed"), ("tanker", "Tanker"),
    ]
    private static let periods: [(String, String)] = [
        ("week", "7 d"), ("month", "30 d"), ("quarter", "90 d"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                inputCard
                resultSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.calculate(origin: origin, destination: dest, equipment: equipment, period: period) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · RATE BOARD").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Lane intel").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("Spot vs market average · trend · 30-day rate history. Pre-bid before you post.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(.top, 4)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("LANE").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                stateField(label: "ORIGIN", text: $origin)
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textTertiary)
                stateField(label: "DEST", text: $dest)
            }
            Text("EQUIPMENT").font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.equipments, id: \.0) { e in chip(label: e.1, active: equipment == e.0) { equipment = e.0 } }
                }
            }
            Text("WINDOW").font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            HStack(spacing: 6) {
                ForEach(Self.periods, id: \.0) { p in chip(label: p.1, active: period == p.0) { period = p.0 } }
            }
            Button {
                Task { await store.calculate(origin: origin, destination: dest, equipment: equipment, period: period) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .heavy))
                    Text("Pull rates").font(.system(size: 14, weight: .heavy))
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func stateField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            TextField("XX", text: text).textFieldStyle(.plain)
                .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center).autocorrectionDisabled()
                .textInputAutocapitalization(.characters).onChange(of: text.wrappedValue) { _, v in
                    if v.count > 2 { text.wrappedValue = String(v.prefix(2)) }
                }
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity).background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                .background(Capsule().fill(active ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)) : AnyShapeStyle(palette.bgCard)))
                .overlay(Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultSection: some View {
        switch store.state {
        case .idle:        EmptyView()
        case .loading:
            HStack { ProgressView(); Text("Pulling lane data…").font(EType.caption).foregroundStyle(palette.textSecondary); Spacer() }
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m): errorBanner(m)
        case .loaded(let r, let f):
            heroRate(r); historyChart(r.history); if let f { fscCard(f) }
        }
    }

    private func heroRate(_ r: ShipperRatesAPI.MarketRateResponse) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("LANE").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(r.lane).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$\(String(format: "%.2f", r.avgRate))")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                Text("/ mi avg").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 10) {
                trendChip(r.trend, percent: r.trendPercent)
                Text("\(r.volumeIndex) loads sampled").font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func trendChip(_ trend: String, percent: Double) -> some View {
        let (icon, color): (String, Color) = {
            switch trend.lowercased() {
            case "up":   return ("arrow.up.right", Brand.success)
            case "down": return ("arrow.down.right", Brand.danger)
            default:      return ("arrow.right", palette.textTertiary)
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .heavy))
            Text(percent != 0 ? String(format: "%+.1f%%", percent) : trend.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
        }
        .foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.75))
    }

    private func historyChart(_ pts: [ShipperRatesAPI.HistoryPoint]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("HISTORY (\(pts.count) DAYS)").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
            if pts.isEmpty {
                Text("No deliveries in window.").font(EType.caption).foregroundStyle(palette.textTertiary).padding(.vertical, Space.s2)
            } else {
                let maxRate = max(pts.map(\.rate).max() ?? 1, 0.01)
                GeometryReader { geo in
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(pts) { p in
                            Capsule().fill(LinearGradient.diagonal)
                                .frame(width: max(2, (geo.size.width / CGFloat(pts.count)) - 2),
                                       height: max(2, geo.size.height * CGFloat(p.rate / maxRate)))
                        }
                    }
                }.frame(height: 80)
                HStack {
                    Text("min $\(String(format: "%.2f", pts.map(\.rate).min() ?? 0))")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("max $\(String(format: "%.2f", pts.map(\.rate).max() ?? 0))")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func fscCard(_ f: ShipperRatesAPI.FuelSurcharge) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "fuelpump.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("FUEL SURCHARGE").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("$\(String(format: "%.2f", f.basePrice))/gal").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$\(String(format: "%.2f", f.currentRate))").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                Text("/ mi").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
            }
            Text("Effective \(f.effectiveDate) · next update \(f.nextUpdate)").font(EType.micro).tracking(0.3).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorBanner(_ m: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 22)).foregroundStyle(palette.textSecondary)
            Text("Rate service offline").font(EType.title).foregroundStyle(palette.textPrimary)
            Text(m).font(EType.caption).foregroundStyle(palette.textTertiary)
        }.frame(maxWidth: .infinity).padding(Space.s4).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("220 · Rate Board · Night") {
    ShipperRateBoard().environment(\.palette, Theme.dark).preferredColorScheme(.dark).background(Theme.dark.bgPage)
}
#Preview("220 · Rate Board · Day") {
    ShipperRateBoard().environment(\.palette, Theme.light).preferredColorScheme(.light).background(Theme.light.bgPage)
}
