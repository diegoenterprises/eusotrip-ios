//
//  331_CatalystCommissionEngine.swift
//  EusoTrip — Catalyst · Commission Engine (brick 331).
//
//  iOS port of the web `frontend/client/src/pages/CommissionEnginePage.tsx`.
//  Renders the platform's dynamic-fee calculator so the catalyst (and the
//  founder testing the math) can model net-to-catalyst per load before
//  rate-confirmation. Server-side stack is unchanged — calls
//  `commissionEngine.calculateSplit` + `commissionEngine.getCommodityIndexes`
//  + `commissionEngine.getFeeStructure`. The web page was shipping a
//  broken contract (called `.calculate` which doesn't exist + passed
//  `driverGamificationScore` instead of `driverScore`); the paired web
//  commit fixes that contract so iOS + web read off the same shape.
//
//  Doctrine refs:
//    • feedback_zero_stubs_doctrine — every CTA fires a real endpoint.
//    • feedback_doctrine_parity — Catalyst gets equal-depth surfaces.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

struct CommissionSplitResult: Decodable, Hashable {
    let grossRate: Double
    let platformFeeRate: Double
    let platformFeePercent: Double
    let platformFeeAmount: Double
    let driverCommissionRate: Double
    let driverCommissionPercent: Double
    let driverCommission: Double
    let netToCatalyst: Double
    let riskFactor: Double
    let gamificationBonus: Double
    let commodityFactor: Double
}

struct CommissionFeeStructure: Decodable, Hashable {
    let baseFeePercent: Double
    let minFeePercent: Double
    let maxFeePercent: Double
    let driverCommissionPercent: Double
    let gamificationMaxBonusPercent: Double
}

// MARK: - Screen

struct CatalystCommissionEngineScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { CommissionEngineBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Match", systemImage: "arrow.triangle.merge", isCurrent: false)],
                trailing: [NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false),
                           NavSlot(label: "Me",      systemImage: "person",        isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct CommissionEngineBody: View {
    @Environment(\.palette) private var palette

    @State private var grossRate: String = "3500"
    @State private var distance: String = "750"
    @State private var cargoType: String = "liquid"
    @State private var hazmatClass: String = "3"
    @State private var driverScorePct: Double = 85
    @State private var result: CommissionSplitResult?
    @State private var feeStructure: CommissionFeeStructure?
    @State private var commodityIndexes: [String: Double] = [:]
    @State private var calculating: Bool = false
    @State private var error: String?

    private let cargoOptions: [(String, String)] = [
        ("general",   "General"),
        ("liquid",    "Liquid Bulk"),
        ("petroleum", "Petroleum"),
        ("gas",       "Gas / LNG"),
        ("chemicals", "Chemicals"),
        ("hazmat",    "Hazmat"),
        ("oversized", "Oversized"),
        ("dry_van",   "Dry Van"),
        ("reefer",    "Reefer"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                formulaCard
                calculatorCard
                if let r = result {
                    splitCard(r)
                }
                if !commodityIndexes.isEmpty {
                    commodityCard
                }
                if let e = error {
                    LifecycleCard(accentDanger: true) {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await initialLoad() }
        .refreshable { await initialLoad() }
        // Recalculate whenever any input changes (debounced via the
        // server-side computation being cheap).
        .onChange(of: grossRate)        { _, _ in Task { await calculate() } }
        .onChange(of: distance)         { _, _ in Task { await calculate() } }
        .onChange(of: cargoType)        { _, _ in Task { await calculate() } }
        .onChange(of: hazmatClass)      { _, _ in Task { await calculate() } }
        .onChange(of: driverScorePct)   { _, _ in Task { await calculate() } }
    }

    // MARK: subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "percent")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · COMMISSION ENGINE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Dynamic platform fee")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Model net-to-catalyst per load. Real commodity index + driver-score gamification.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formulaCard: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FEE FORMULA")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
                Text("PLATFORM_FEE = BASE(8%) × (1 + RISK − GAMIFICATION) × COMMODITY")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let f = feeStructure {
                    Text("Range \(Int(f.minFeePercent))%–\(Int(f.maxFeePercent))% · Driver commission \(Int(f.driverCommissionPercent))% · Hazmat +2% · Long-haul +1%")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var calculatorCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                LifecycleSection(label: "FEE CALCULATOR", icon: "function")
                inputField(label: "GROSS RATE ($)", binding: $grossRate, keyboard: .numberPad)
                inputField(label: "DISTANCE (MI)",  binding: $distance,  keyboard: .numberPad)
                inputField(label: "HAZMAT CLASS (OPTIONAL)", binding: $hazmatClass, keyboard: .default)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CARGO TYPE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(cargoOptions, id: \.0) { tup in
                                Button { cargoType = tup.0 } label: {
                                    Text(tup.1)
                                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .foregroundStyle(cargoType == tup.0 ? .white : palette.textSecondary)
                                        .background(cargoType == tup.0
                                            ? AnyShapeStyle(LinearGradient.diagonal)
                                            : AnyShapeStyle(palette.bgCard))
                                        .clipShape(Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("DRIVER SCORE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("\(Int(driverScorePct))/100").font(EType.caption.weight(.heavy).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                    }
                    Slider(value: $driverScorePct, in: 0...100, step: 1)
                }
                if calculating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Calculating split…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    private func inputField(label: String, binding: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField("", text: binding)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func splitCard(_ r: CommissionSplitResult) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 8) {
                LifecycleSection(label: "SPLIT", icon: "chart.pie.fill")
                splitRow(label: "Gross Rate",            value: r.grossRate,         color: palette.textPrimary)
                splitRow(label: "Platform Fee (\(String(format: "%.1f", r.platformFeePercent))%)",
                                                          value: -r.platformFeeAmount, color: .blue)
                splitRow(label: "Driver Commission (\(Int(r.driverCommissionPercent))%)",
                                                          value: -r.driverCommission, color: .purple)
                Divider()
                splitRow(label: "Net to Catalyst",       value: r.netToCatalyst,     color: .green, big: true)
                HStack(spacing: 6) {
                    if r.riskFactor > 0 {
                        capsule(text: "RISK +\(String(format: "%.1f", r.riskFactor * 100))%", color: .red)
                    }
                    if r.gamificationBonus > 0 {
                        capsule(text: "BONUS −\(String(format: "%.1f", r.gamificationBonus * 100))%", color: .green)
                    }
                    if abs(r.commodityFactor - 1.0) > 0.0001 {
                        capsule(text: "COMMODITY ×\(String(format: "%.2f", r.commodityFactor))", color: .blue)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func splitRow(label: String, value: Double, color: Color, big: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(big ? EType.body.weight(.semibold) : EType.caption)
                .foregroundStyle(big ? palette.textPrimary : palette.textSecondary)
            Spacer()
            Text(currencyString(value))
                .font(big ? .system(size: 22, weight: .heavy).monospacedDigit()
                          : EType.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func capsule(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var commodityCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                LifecycleSection(label: "LIVE COMMODITY INDEX", icon: "chart.line.uptrend.xyaxis")
                let keys = commodityIndexes.keys.sorted()
                let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(keys, id: \.self) { k in
                        VStack(spacing: 2) {
                            Text(k.uppercased())
                                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                                .foregroundStyle(palette.textTertiary)
                            Text(String(format: "%.2f", commodityIndexes[k] ?? 0))
                                .font(.system(size: 13, weight: .heavy).monospacedDigit())
                                .foregroundStyle(palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(palette.bgCard)
                        )
                    }
                }
            }
        }
    }

    // MARK: pipeline

    private func initialLoad() async {
        async let split: Void = calculate()
        async let indexes: Void = loadIndexes()
        async let structure: Void = loadFeeStructure()
        _ = await (split, indexes, structure)
    }

    private func calculate() async {
        let gr = Double(grossRate.replacingOccurrences(of: ",", with: "")) ?? 0
        let dm = Double(distance.replacingOccurrences(of: ",", with: "")) ?? 0
        guard gr > 0 else { return }
        calculating = true
        defer { calculating = false }
        struct In: Encodable {
            let grossRate: Double
            let cargoType: String
            let distanceMiles: Double
            let driverScore: Double
            let hazmatClass: String?
        }
        do {
            let r: CommissionSplitResult = try await EusoTripAPI.shared.query(
                "commissionEngine.calculateSplit",
                input: In(
                    grossRate: gr,
                    cargoType: cargoType,
                    distanceMiles: dm,
                    driverScore: driverScorePct / 100.0,
                    hazmatClass: hazmatClass.isEmpty ? nil : hazmatClass
                )
            )
            self.result = r
            self.error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadIndexes() async {
        do {
            let m: [String: Double] = try await EusoTripAPI.shared
                .queryNoInput("commissionEngine.getCommodityIndexes")
            self.commodityIndexes = m
        } catch {
            // Best-effort: commodity strip is optional context.
        }
    }

    private func loadFeeStructure() async {
        do {
            let f: CommissionFeeStructure = try await EusoTripAPI.shared
                .queryNoInput("commissionEngine.getFeeStructure")
            self.feeStructure = f
        } catch {
            // Best-effort.
        }
    }

    private func currencyString(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

#Preview("331 · Commission · Dark") {
    CatalystCommissionEngineScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("331 · Commission · Light") {
    CatalystCommissionEngineScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
