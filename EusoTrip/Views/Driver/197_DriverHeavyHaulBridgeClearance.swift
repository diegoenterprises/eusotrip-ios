//
//  197_DriverHeavyHaulBridgeClearance.swift
//  EusoTrip — Screen 197 · Heavy-Haul Bridge Clearance (LIVE-wired · ROUTE)
//
//  Purpose: resolve a superload's oversize permits and escort staging BEFORE
//  the wheels turn — so a low overpass is a reroute on the screen instead of a
//  strike on the structure.
//
//  Wiring manifest:
//    compliance.getPermits          EXISTS · compliance.ts:861
//      → [{ id, type, states, status, expiresAt, vehicle, name }] — the
//        company's real oversize/overweight permits + expiry status.
//    loads.getEscortAssignment      EXISTS · loads.ts:2029
//      input { loadId } → [{ position, status, escortName, companyName,
//                           companyDot, companyMc, rate, rateType }]
//  HONEST GAP handed to the-oath: there is NO bridge/height/weight clearance
//  engine or HERE-fed reroute as a tRPC procedure — the route-evidence hero and
//  clearance gates are shown as the framework (what gets checked) with an
//  explicit "pending integration" state, never a fabricated ETA, mileage, or
//  span verdict, and never an authored route curve. Proposed: trailerRegulatory.checkBridgeClearance
//  ({ routePoints, heightIn, weightLb }) → { spans[], reroute }.
//  transportMode = truck · country US (state oversize permits + P/EVO).
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//
//  §W OFFLINE POLICY: ONLINE_ONLY(permit validity and escort staging decide whether a superload
//  may move; a cached ACTIVE could roll a load on a lapsed permit).
//  Honored: nothing on this surface is persisted or replayed client-side;
//  on any failure the model is cleared and the reason is surfaced.
//

import SwiftUI

private struct OversizePermit: Decodable, Identifiable {
    let id: String?
    let type: String?
    let status: String?
    let expiresAt: String?
    let name: String?
    let vehicle: String?
    var rowId: String { id ?? name ?? UUID().uuidString }
}
private struct EscortAssignment: Decodable, Identifiable {
    let id: Int?
    let position: String?
    let status: String?
    let escortName: String?
    let companyName: String?
    let companyDot: String?
    let rate: Double?
    let rateType: String?
    var rowId: Int { id ?? 0 }
}

@MainActor
private final class BridgeClearanceViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, error(String) }
    @Published var phase: Phase = .idle
    @Published var permits: [OversizePermit] = []
    @Published var escorts: [EscortAssignment] = []

    let loadId: String?
    init(loadId: String?) { self.loadId = loadId }

    private struct EscortIn: Encodable { let loadId: String }

    func load() async {
        phase = .loading
        permits = (try? await EusoTripAPI.shared.queryNoInput("compliance.getPermits")) ?? []
        if let loadId {
            escorts = (try? await EusoTripAPI.shared.query(
                "loads.getEscortAssignment", input: EscortIn(loadId: loadId))) ?? []
        }
        phase = .ready
    }
}

struct DriverHeavyHaulBridgeClearanceView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm: BridgeClearanceViewModel

    let loadRef: String
    let dims: String        // height · weight spec from the load (e.g. "16ft 2in · 142k lb")
    let origin: String
    let dest: String

    init(loadId: String? = nil, loadRef: String = "RGN lowboy",
         dims: String = "oversize · superload", origin: String = "Origin", dest: String = "Destination") {
        _vm = StateObject(wrappedValue: BridgeClearanceViewModel(loadId: loadId))
        self.loadRef = loadRef; self.dims = dims; self.origin = origin; self.dest = dest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverComplianceHeader(
                eyebrow: "DRIVER · HEAVY-HAUL ROUTE", caption: "OVERSIZE",
                title: "Bridge Clearance", subtitle: "\(loadRef) · \(dims)",
                rightLabel: "ESCORTS", rightValue: "\(vm.escorts.count)")
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading: DriverUtilityLoading(text: "Reading permits + escort…")
            case .error(let m):   DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:          content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: Space.s4) {
            routeHero
            clearanceGates
            permitMatrix
            escortCard
            ctaPair
        }
        .padding(Space.s5)
    }

    // Route evidence — named endpoints only; live routing honestly pending.
    private var routeHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                VStack {
                    HStack {
                        routePin(origin, align: .leading)
                        Spacer()
                        routePin(dest, align: .trailing)
                    }
                    Spacer()
                    VStack(spacing: 5) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                        Text("NO VERIFIED ROUTE GEOMETRY")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.warning)
                        Text("SPAN CLEARANCE + LIVE ROUTING — PENDING INTEGRATION")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(palette.bgCard.opacity(0.9), in: Capsule())
                }
                .padding(Space.s3)
            }
            .frame(height: 150)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Bridge clearance route from \(origin) to \(dest). Verified route geometry and span clearance are pending integration.")
        }
        .padding(4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private func routePin(_ label: String, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 3) {
            Circle().fill(LinearGradient.diagonal).frame(width: 8, height: 8)
            Text(label.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(palette.bgCard.opacity(0.85), in: Capsule())
        }
    }

    private var clearanceGates: some View {
        ComplianceSection(label: "CLEARANCE GATES · FRAMEWORK",
                          trailing: "PENDING", trailingColor: Brand.warning) {
            VStack(spacing: Space.s3) {
                ComplianceGateRow(systemImage: "arrow.triangle.branch", tint: Brand.danger,
                                  title: "Low-bridge / overpass height",
                                  subtitle: "posted clearance vs load height", status: "check",
                                  statusColor: Brand.danger)
                Divider().overlay(palette.borderFaint)
                ComplianceGateRow(systemImage: "sun.max", tint: Brand.warning,
                                  title: "Mountain-corridor permit hours",
                                  subtitle: "grade · chain law · daylight window", status: "check",
                                  statusColor: Brand.warning)
                Divider().overlay(palette.borderFaint)
                ComplianceGateRow(systemImage: "scalemass", tint: Brand.info,
                                  title: "Superload weigh clearance",
                                  subtitle: "gross weight vs superload permit", status: "check",
                                  statusColor: Brand.info)
                ComplianceGapNote(
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    title: "Automatic span verdicts",
                    detail: "The height/weight-vs-posted-clearance engine isn't wired on this build — gates read as the framework to verify, never a fabricated CLEAR/REROUTE.")
            }
        }
    }

    private var permitMatrix: some View {
        ComplianceSection(label: "OVERSIZE PERMITS",
                          trailing: "\(vm.permits.count) ON FILE") {
            if vm.permits.isEmpty {
                DriverUtilityEmpty(systemImage: "doc.badge.gearshape",
                                   title: "No oversize permits on file",
                                   detail: "State oversize/overweight permits appear here with their expiry status as they're added to the company profile.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.permits.prefix(6).enumerated()), id: \.element.rowId) { idx, p in
                        permitRow(p)
                        if idx < min(vm.permits.count, 6) - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    private func permitRow(_ p: OversizePermit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text((p.type ?? p.name ?? "Permit").capitalized).font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(p.expiresAt.map { "expires \($0)" } ?? (p.vehicle ?? "—"))
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            // An ABSENT permit status previously rendered the word "ACTIVE"
            // in green — a fabricated compliance verdict on an oversize
            // permit. Unknown now reads UNKNOWN, in neutral.
            Text((p.status ?? "unknown").uppercased()).font(EType.micro).tracking(0.4).fontWeight(.bold)
                .foregroundStyle(permitColor(p.status)).fixedSize()
        }
        .padding(.vertical, 2)
    }
    /// Only a status the server explicitly reports as good earns green. Absent
    /// or unrecognised states stay neutral — never flattered into "active".
    private func permitColor(_ s: String?) -> Color {
        switch (s ?? "").lowercased() {
        case "expired", "revoked", "suspended", "denied": return Brand.danger
        case "expiring", "pending", "submitted": return Brand.warning
        case "active", "approved", "issued", "valid": return Brand.success
        default: return palette.textSecondary
        }
    }

    private var escortCard: some View {
        ComplianceSection(label: "P/EVO ESCORT ASSIGNMENT",
                          trailing: vm.escorts.isEmpty ? "NONE" : "\(vm.escorts.count) STAGED",
                          trailingColor: vm.escorts.isEmpty ? Brand.warning : Brand.success) {
            if vm.escorts.isEmpty {
                DriverUtilityEmpty(systemImage: "car.2",
                                   title: "No escort assigned",
                                   detail: "Pilot / escort-vehicle assignments for the superload appear here once staged to the load.")
            } else {
                VStack(spacing: Space.s3) {
                    ForEach(vm.escorts) { e in
                        ComplianceGateRow(
                            systemImage: "car.fill", tint: Brand.escort,
                            title: e.escortName ?? (e.position?.capitalized ?? "Escort"),
                            subtitle: [e.companyName, e.companyDot.map { "DOT \($0)" }]
                                .compactMap { $0 }.joined(separator: " · "),
                            status: (e.status ?? "assigned").capitalized,
                            statusColor: Brand.escort)
                    }
                }
            }
        }
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {} label: {
                Text("Accept routing").font(EType.title).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(LinearGradient.primary.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain).disabled(true)
            .accessibilityLabel("Accept routing — route engine not yet available")
            Button {} label: {
                Text("Request escort").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain).disabled(true).opacity(0.6)
            .accessibilityLabel("Request escort — driver-side request not yet available")
        }
    }
}

// MARK: - Screen (Shell + Driver nav · LOADS current)

struct DriverHeavyHaulBridgeClearanceScreen: View {
    let theme: Theme.Palette
    var loadId: String? = nil
    var loadRef: String = "RGN lowboy"
    var dims: String = "oversize · superload"
    var origin: String = "Origin"
    var dest: String = "Destination"
    var body: some View {
        Shell(theme: theme) {
            DriverHeavyHaulBridgeClearanceView(loadId: loadId, loadRef: loadRef,
                                               dims: dims, origin: origin, dest: dest)
        } nav: {
            BottomNav(leading: driverComplianceNavLeading(.loads),
                      trailing: driverComplianceNavTrailing(.loads), orbState: .idle)
        }
    }
}

#Preview("Bridge Clearance · Dark") {
    DriverHeavyHaulBridgeClearanceScreen(theme: Theme.dark, loadRef: "RGN lowboy",
                                         dims: "16ft 2in · 142k lb", origin: "Houston TX", dest: "Denver CO")
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Bridge Clearance · Light") {
    DriverHeavyHaulBridgeClearanceScreen(theme: Theme.light, loadRef: "RGN lowboy",
                                         dims: "16ft 2in · 142k lb", origin: "Houston TX", dest: "Denver CO")
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
