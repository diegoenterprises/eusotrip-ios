//
//  177_DriverCashAdvance.swift
//  EusoTrip — Screen 177 · Driver Cash & Fuel Advance (LIVE-wired)
//
//  Purpose: fund the load before the driver is short at the pump — one tap
//  issues an advance with the fee and auto-recoup shown up front, so there
//  is no settlement surprise.
//
//  Wiring manifest (server/routers/wallet.ts):
//    wallet.getCashAdvances    EXISTS · wallet.ts:2298
//      output [{ id, amount, fee, feePercent, totalRepayment, repaidAmount,
//               status, dueDate, disbursedAt, repaidAt, createdAt }]
//    wallet.requestFuelAdvance EXISTS · wallet.ts:2121
//      input { loadId, amount, disbursement, idempotencyKey }
//      (inserts cashAdvances + BlockchainService.logEvent FUEL_ADVANCE,
//       broadcasts WS_EVENTS.advanceIssued on WS_CHANNELS.wallet(userId))
//    wallet.requestCashAdvance EXISTS · wallet.ts:2204
//  HONEST GAPS handed to the-oath: there is no getAdvanceLine endpoint, so
//  the hero shows the driver's REAL outstanding advance balance + repayment
//  progress (never a fabricated credit line). The lumper/accessorial
//  pass-through row is informational until a detentionAccessorials advance
//  path exists. The request CTA is inert (with a clear reason) until an
//  active load is bound — never a dead tap.
//  transportMode = truck · currency USD.
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//

import SwiftUI

// MARK: - Wire model

private struct CashAdvance: Decodable, Identifiable {
    let id: Int
    let amount: Double
    let fee: Double
    let feePercent: Double?
    let totalRepayment: Double
    let repaidAmount: Double
    let status: String
    let disbursedAt: String?
    let createdAt: String?
}

// MARK: - ViewModel

@MainActor
private final class CashAdvanceViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, error(String) }
    @Published var phase: Phase = .idle
    @Published var advances: [CashAdvance] = []
    @Published var requestAmount: Double = 300
    @Published var requesting = false
    @Published var toast: String?

    let activeLoadId: Int?
    init(activeLoadId: Int?) { self.activeLoadId = activeLoadId }

    private struct FuelAdvanceIn: Encodable {
        let loadId: Int; let amount: Double
        let disbursement: String; let idempotencyKey: String
    }
    // Tolerant: success is "didn't throw" — decode any object shape.
    private struct AdvanceOut: Decodable {}

    func load() async {
        phase = .loading
        do {
            let rows: [CashAdvance] = try await EusoTripAPI.shared
                .queryNoInput("wallet.getCashAdvances")
            advances = rows
            phase = .ready
        } catch {
            phase = .error("Couldn't reach your advance ledger.")
        }
    }

    var canRequest: Bool { activeLoadId != nil && !requesting }

    func requestFuelAdvance() async {
        guard let loadId = activeLoadId else {
            toast = "Bind an active load to advance against it."
            return
        }
        requesting = true
        defer { requesting = false }
        do {
            let _: AdvanceOut = try await EusoTripAPI.shared.mutation(
                "wallet.requestFuelAdvance",
                input: FuelAdvanceIn(loadId: loadId, amount: requestAmount,
                                     disbursement: "wallet",
                                     idempotencyKey: UUID().uuidString))
            toast = "Fuel advance issued to your wallet."
            await load()
        } catch {
            toast = "Couldn't issue that advance. Try again."
        }
    }

    // Real derived money
    var outstanding: Double {
        advances.filter { !["repaid", "defaulted"].contains($0.status.lowercased()) }
            .reduce(0) { $0 + max($1.totalRepayment - $1.repaidAmount, 0) }
    }
    var totalActive: Double {
        advances.filter { !["repaid", "defaulted"].contains($0.status.lowercased()) }
            .reduce(0) { $0 + $1.totalRepayment }
    }
    var repaidFraction: Double {
        totalActive > 0 ? min(max((totalActive - outstanding) / totalActive, 0), 1) : 0
    }
}

// MARK: - Screen body

struct CashAdvanceView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm: CashAdvanceViewModel

    init(activeLoadId: Int? = nil) {
        _vm = StateObject(wrappedValue: CashAdvanceViewModel(activeLoadId: activeLoadId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverUtilityHeader(eyebrow: "DRIVER · ADVANCES", caption: "EUSOWALLET",
                                title: "Cash advance",
                                subtitle: "fuel · cash · lumper",
                                rightTop: "MICHAEL EUSORONE · DR-00427",
                                rightBottom: "Eusotrans LLC")
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading: DriverUtilityLoading(text: "Loading your advance line…")
            case .error(let m):   DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:          content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
        .overlay(alignment: .bottom) { toastBar }
    }

    private var content: some View {
        VStack(spacing: Space.s4) {
            outstandingHero
            requestCard
            advanceTypesCard
            ledgerCard
        }
        .padding(Space.s5)
    }

    // Hero — real outstanding balance + repayment arc
    private var outstandingHero: some View {
        VStack(spacing: Space.s3) {
            HStack {
                Text("OUTSTANDING ADVANCES").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(vm.advances.filter { !["repaid","defaulted"].contains($0.status.lowercased()) }.count) ACTIVE")
                    .font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            ZStack {
                SemicircleGauge(fraction: vm.repaidFraction)
                    .frame(height: 118)
                VStack(spacing: 2) {
                    Text(money(vm.outstanding))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .monospacedDigit().foregroundStyle(palette.textPrimary)
                    Text(vm.totalActive > 0
                         ? "\(Int(vm.repaidFraction * 100))% repaid"
                         : "no advances outstanding")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                .offset(y: 12)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    // Request card — real mutation with a user-chosen amount
    private var requestCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("REQUEST FUEL ADVANCE").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("2% FEE").font(EType.micro).tracking(0.6).foregroundStyle(Brand.success)
            }
            HStack {
                Button { vm.requestAmount = max(100, vm.requestAmount - 100) } label: {
                    stepGlyph("minus")
                }.buttonStyle(.plain).disabled(!vm.canRequest)
                Spacer()
                VStack(spacing: 0) {
                    Text(money(vm.requestAmount))
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                    Text("+ \(money(vm.requestAmount * 0.02)) fee · settles on POD")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button { vm.requestAmount = min(2000, vm.requestAmount + 100) } label: {
                    stepGlyph("plus")
                }.buttonStyle(.plain).disabled(!vm.canRequest)
            }
            CTAButton(title: vm.requesting ? "Issuing…" : (vm.canRequest ? "Request advance" : "Bind an active load"),
                      action: { Task { await vm.requestFuelAdvance() } },
                      leadingIcon: "dollarsign.circle",
                      isLoading: vm.requesting)
                .opacity(vm.canRequest ? 1 : 0.55)
                .disabled(!vm.canRequest)
            if vm.activeLoadId == nil {
                Text("Requesting funds an advance against your current load — available once a load is active.")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func stepGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            .frame(width: 44, height: 44)
            .background(palette.bgCardSoft, in: Circle())
            .overlay(Circle().strokeBorder(palette.borderSoft))
    }

    // Advance-type fee schedule (informational)
    private var advanceTypesCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("ADVANCE TYPES").font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            typeRow("Fuel advance", detail: "pre-trip funding", fee: "2% fee",
                    cap: "max $1,500", tint: Brand.success)
            Divider().overlay(palette.borderFaint)
            typeRow("Cash advance", detail: "any time, any ATM", fee: "3% fee",
                    cap: "max $1,000", tint: Brand.info)
            Divider().overlay(palette.borderFaint)
            typeRow("Lumper / accessorial", detail: "billed to the load", fee: "0% fee",
                    cap: "as billed", tint: Brand.rail)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func typeRow(_ title: String, detail: String, fee: String, cap: String, tint: Color) -> some View {
        HStack(alignment: .top) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.14)).frame(width: 28, height: 28)
                Text("$").font(.system(size: 13, weight: .heavy)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(detail).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(cap).font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
                Text(fee).font(EType.micro).fontWeight(.bold).foregroundStyle(tint)
            }
        }
        .padding(.vertical, 2)
    }

    // Real ledger
    private var ledgerCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ACTIVE ADVANCES").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("AMOUNT").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            if vm.advances.isEmpty {
                DriverUtilityEmpty(systemImage: "banknote",
                                   title: "No advances on file",
                                   detail: "Take a fuel advance above and it'll show here with its recoup status.")
            } else {
                ForEach(vm.advances.prefix(6)) { a in
                    ledgerRow(a)
                    if a.id != vm.advances.prefix(6).last?.id {
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func ledgerRow(_ a: CashAdvance) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Advance #\(a.id)").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text([a.feePercent.map { "\(Int($0 * 100))% fee" }, shortDate(a.createdAt)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("-\(money(a.amount))").font(EType.mono(.body)).fontWeight(.bold)
                    .foregroundStyle(palette.textPrimary)
                Text(a.status.uppercased()).font(EType.micro).fontWeight(.bold)
                    .foregroundStyle(statusTint(a.status))
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var toastBar: some View {
        if let t = vm.toast {
            Text(t).font(EType.caption).foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                .background(palette.bgSheet, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.borderSoft))
                .padding(.bottom, Space.s6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    withAnimation { vm.toast = nil }
                }
        }
    }

    private func statusTint(_ status: String) -> Color {
        switch status.lowercased() {
        case "repaid":     return Brand.success
        case "disbursed", "approved": return Brand.info
        case "pending":    return Brand.warning
        case "defaulted":  return Brand.danger
        default:           return palette.textSecondary
        }
    }

    private func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
    private func shortDate(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        return String(iso.prefix(10))
    }
}

// MARK: - Semicircle gauge

private struct SemicircleGauge: View {
    let fraction: Double
    @Environment(\.palette) var palette
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                SemiArc().stroke(palette.borderFaint, style: .init(lineWidth: 16, lineCap: .round))
                SemiArc().trim(from: 0, to: max(0, min(fraction, 1)))
                    .stroke(LinearGradient.diagonal, style: .init(lineWidth: 16, lineCap: .round))
            }
            .frame(width: w)
        }
    }
    private struct SemiArc: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            let radius = min(r.width / 2 - 8, r.height - 8)
            p.addArc(center: CGPoint(x: r.midX, y: r.maxY),
                     radius: radius, startAngle: .degrees(180), endAngle: .degrees(0),
                     clockwise: false)
            return p
        }
    }
}

// MARK: - Screen (Shell + Driver nav · ME current)

struct CashAdvanceScreen: View {
    let theme: Theme.Palette
    var activeLoadId: Int? = nil
    var body: some View {
        Shell(theme: theme) {
            CashAdvanceView(activeLoadId: activeLoadId)
        } nav: {
            BottomNav(leading: driverUtilityNavLeading(),
                      trailing: driverUtilityNavTrailing(meCurrent: true), orbState: .idle)
        }
    }
}

#Preview("Cash Advance · Dark") {
    CashAdvanceScreen(theme: Theme.dark, activeLoadId: 1077)
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Cash Advance · Light") {
    CashAdvanceScreen(theme: Theme.light, activeLoadId: 1077)
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
