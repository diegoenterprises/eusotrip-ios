//
//  190_DriverItinerary.swift
//  EusoTrip — Screen 190 · Driver Itinerary (LIVE-wired · TIMELINE archetype)
//
//  Purpose: one sequenced day-plan Michael can drive without thinking between
//  stops — the active stop, today's numbers, and a stop-by-stop timeline of
//  every leg with its window and status.
//
//  Wiring manifest:
//    driverMobile.getDriverSchedule  EXISTS · driverMobile.ts:1512
//      → { loads[{ id, referenceNumber, status, origin, destination,
//                  pickupDate, deliveryDate, rate, distance }], totalScheduled }
//      real source: the driver's accepted/assigned/in-transit loads.
//    hos.getCurrentStatus            EXISTS · hos.ts:179
//      → { limits{ driving.remaining, onDuty.remaining (min) }, canDrive }
//  HONEST GAP handed to the-oath: there is NO per-load intra-stop sequence
//  read (loadStops is written on loads.create:638 but never exposed as a
//  query) and NO day-plan-PDF generator. The timeline is therefore built
//  from the real scheduled loads as origin→dest legs — we never fabricate
//  interior stops — and the PDF export is surfaced as an explicit honest gap.
//  Proposed: loads.getStops({ loadId }) and driver.dayPlan.generate.
//  transportMode = truck · country US.
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//

import SwiftUI

// MARK: - Wire models

private struct ItineraryLoad: Decodable, Identifiable {
    let id: Int
    let referenceNumber: String?
    let status: String?
    let origin: String?
    let destination: String?
    let pickupDate: String?
    let deliveryDate: String?
    let rate: Double?
    let distance: Double?
}
private struct ItinerarySchedule: Decodable {
    let loads: [ItineraryLoad]
    let totalScheduled: Int?
}
private struct HosLimit: Decodable { let remaining: Int? }
private struct HosLimits: Decodable { let driving: HosLimit?; let onDuty: HosLimit? }
private struct HosSnapshot: Decodable { let limits: HosLimits?; let canDrive: Bool? }

// MARK: - ViewModel

@MainActor
private final class ItineraryViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, error(String) }
    @Published var phase: Phase = .idle
    @Published var loads: [ItineraryLoad] = []
    @Published var driveRemainingMin: Int?

    func load() async {
        phase = .loading
        do {
            async let sched: ItinerarySchedule =
                EusoTripAPI.shared.queryNoInput("driverMobile.getDriverSchedule")
            async let hos: HosSnapshot =
                EusoTripAPI.shared.queryNoInput("hos.getCurrentStatus")
            loads = try await sched.loads
            driveRemainingMin = (try? await hos)?.limits?.driving?.remaining
            phase = .ready
        } catch {
            phase = .error("Couldn't reach your schedule.")
        }
    }

    var totalMiles: Int { Int(loads.compactMap { $0.distance }.reduce(0, +).rounded()) }
    var grossPay: Double { loads.compactMap { $0.rate }.reduce(0, +) }
    var activeLoad: ItineraryLoad? {
        loads.first { ($0.status ?? "") == "in_transit" } ?? loads.first
    }
}

// MARK: - Screen body

struct DriverItineraryView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm = ItineraryViewModel()

    private static let todayCaption: String = {
        let f = DateFormatter(); f.dateFormat = "EEE · MMM d"
        return f.string(from: Date()).uppercased()
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverComplianceHeader(
                eyebrow: "DRIVER · ITINERARY", caption: Self.todayCaption,
                title: "Itinerary",
                subtitle: vm.activeLoad?.referenceNumber ?? "day plan",
                rightLabel: "STOPS", rightValue: "\(vm.loads.count)")
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading: DriverUtilityLoading(text: "Sequencing your day…")
            case .error(let m):   DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:          content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: Space.s4) {
            if let a = vm.activeLoad { activeStopHero(a) }
            byTheNumbers
            stopByStop
            esangCard
            ComplianceGapNote(
                systemImage: "doc.text",
                title: "Day-plan PDF export",
                detail: "One-tap day-plan export isn't connected on this build — no document is generated rather than one we can't stand behind.")
            CTAButton(title: "Refresh itinerary", action: { Task { await vm.load() } },
                      leadingIcon: "arrow.clockwise")
        }
        .padding(Space.s5)
    }

    // Active-stop hero — the next live leg the driver is running.
    private func activeStopHero(_ a: ItineraryLoad) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ACTIVE STOP · \(a.referenceNumber ?? "—")")
                    .font(EType.micro).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                StatusPill(text: statusLabel(a.status), kind: statusKind(a.status))
            }
            Text(a.destination ?? "Destination")
                .font(EType.h2).foregroundStyle(palette.textPrimary)
            Text("\(a.origin ?? "Origin") → \(a.destination ?? "Destination")")
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            Divider().overlay(palette.borderFaint)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAY · OPEN CLOCK").font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(driveClockLabel).font(EType.mono(.body)).fontWeight(.bold)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("DELIVERY").font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(shortWhen(a.deliveryDate)).font(EType.mono(.body)).fontWeight(.bold)
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private var byTheNumbers: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("TODAY · BY THE NUMBERS").font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                MetricTile(label: "Stops", value: "\(vm.loads.count)", gradientNumeral: true)
                MetricTile(label: "Miles", value: vm.totalMiles > 0 ? "\(vm.totalMiles)" : "—")
                MetricTile(label: "Gross",
                           value: vm.grossPay > 0 ? money(vm.grossPay) : "—")
                MetricTile(label: "Drive left", value: driveClockLabel,
                           accent: (vm.driveRemainingMin ?? 999) < 120 ? Brand.warning : nil)
            }
        }
    }

    private var stopByStop: some View {
        ComplianceSection(label: "STOP-BY-STOP",
                          trailing: "\(vm.loads.count) LEG\(vm.loads.count == 1 ? "" : "S")") {
            if vm.loads.isEmpty {
                DriverUtilityEmpty(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                   title: "No legs scheduled",
                                   detail: "Accepted and in-transit loads sequence here as you take them.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.loads.enumerated()), id: \.element.id) { idx, l in
                        legRow(l, isLast: idx == vm.loads.count - 1)
                    }
                }
            }
        }
    }

    private func legRow(_ l: ItineraryLoad, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(statusKind(l.status) == .success
                                  ? AnyShapeStyle(Color.clear) : AnyShapeStyle(LinearGradient.diagonal),
                                  lineWidth: 2.4)
                    .background(Circle().fill(statusKind(l.status) == .success
                                              ? AnyShapeStyle(LinearGradient.diagonal)
                                              : AnyShapeStyle(palette.bgCard)))
                    .frame(width: 18, height: 18)
                    .overlay {
                        if statusKind(l.status) == .success {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle().fill(LinearGradient.diagonal).frame(width: 7, height: 7)
                        }
                    }
                if !isLast {
                    Rectangle().fill(palette.borderSoft).frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(minHeight: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(shortWhen(l.pickupDate)) · \(statusLabel(l.status).uppercased())")
                    .font(EType.micro).tracking(0.6).fontWeight(.bold)
                    .foregroundStyle(statusColor(l.status))
                Text(l.origin ?? "Origin").font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("\(l.referenceNumber ?? "—") · \(l.destination ?? "—")\(l.rate.map { " · " + money($0) } ?? "")")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast ? 0 : Space.s3)
    }

    private var esangCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG AI").font(EType.micro).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(esangLine).font(EType.caption).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
    }

    // MARK: helpers

    private var esangLine: String {
        if vm.loads.count >= 2 {
            return "\(vm.loads.count) legs sequenced across \(vm.totalMiles) mi — I'll flag any window that goes tight before you're boxed in."
        } else if vm.loads.count == 1 {
            return "One leg on today — I'm watching the delivery window and your drive clock."
        }
        return "Nothing scheduled yet — accept a load and I'll build the sequence."
    }

    private var driveClockLabel: String {
        guard let m = vm.driveRemainingMin, m > 0 else { return "—" }
        return "\(m / 60)h \(m % 60)m"
    }

    private func statusLabel(_ s: String?) -> String {
        switch (s ?? "").lowercased() {
        case "in_transit": return "Live"
        case "assigned":   return "Assigned"
        case "accepted":   return "Accepted"
        case "delivered", "completed": return "Done"
        default: return (s ?? "Planned").capitalized
        }
    }
    private func statusKind(_ s: String?) -> StatusPill.Kind {
        switch (s ?? "").lowercased() {
        case "in_transit": return .info
        case "delivered", "completed": return .success
        case "assigned", "accepted": return .warning
        default: return .neutral
        }
    }
    private func statusColor(_ s: String?) -> Color {
        switch statusKind(s) {
        case .info: return Brand.info
        case .success: return Brand.success
        case .warning: return Brand.warning
        default: return palette.textSecondary
        }
    }

    private func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// A lenient "when" formatter — real schedule dates arrive as ISO or plain
// date strings; format what parses, never invent a time.
private func shortWhen(_ s: String?) -> String {
    guard let s, !s.isEmpty else { return "—" }
    let iso = ISO8601DateFormatter()
    if let d = iso.date(from: s) { return fmt(d) }
    for pat in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
        let df = DateFormatter(); df.dateFormat = pat
        if let d = df.date(from: s) { return fmt(d) }
    }
    return String(s.prefix(16))
}
private func fmt(_ d: Date) -> String {
    let cal = Calendar.current
    let df = DateFormatter()
    let comps = cal.dateComponents([.hour, .minute], from: d)
    df.dateFormat = (comps.hour == 0 && comps.minute == 0) ? "MMM d" : "MMM d · HH:mm"
    return df.string(from: d)
}

// MARK: - Screen (Shell + Driver nav · ME current)

struct DriverItineraryScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DriverItineraryView()
        } nav: {
            BottomNav(leading: driverComplianceNavLeading(.me),
                      trailing: driverComplianceNavTrailing(.me), orbState: .idle)
        }
    }
}

#Preview("Itinerary · Dark") {
    DriverItineraryScreen(theme: Theme.dark)
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Itinerary · Light") {
    DriverItineraryScreen(theme: Theme.light)
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
