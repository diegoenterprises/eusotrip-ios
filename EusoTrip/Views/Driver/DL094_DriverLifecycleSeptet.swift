//
//  DL094_DriverLifecycleSeptet.swift
//  EusoTrip — Driver · Lifecycle septet (DL094-DL100).
//
//  Pixel-match to:
//    094 Driver At Gate.svg
//    095 Driver At Dock.svg
//    096 Driver Departing.svg
//    097 Driver Pre-Delivery.svg
//    098 Driver At Delivery.svg
//    099 Driver POD Sign.svg
//    100 Driver Load Closed.svg
//
//  All share the same scaffold (header + stage banner + KPI grid +
//  next-step copy); only stage metadata differs. Bundled into one
//  Swift file. Bottom nav frozen.
//

import SwiftUI

private struct DLLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let distance: Double?
    let palletCount: Int?
    let temperatureF: Double?
    let dockNumber: String?
    let podCertId: String?
    let actualDeliveryDate: String?
    let deliveryDate: String?
}

private struct DLStage {
    let eyebrow: String
    let citation: String
    let title: String
    let subtitle: String
    let kpis: [DLKpi]
    let nextStep: String
}
private struct DLKpi {
    let label: String
    let value: String
    let subtitle: String
    let color: Color
}

/// Optional action attached to a lifecycle stage. `.none` for read-only
/// stages, `.podSign` for DL099 which exposes a real loads.signPOD mutation.
private enum DLActionKind {
    case none, podSign
}

private struct DLShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Trips", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DLBody: View {
    let loadId: String
    /// Optional inline action — currently used by DL099 POD Sign to surface
    /// a real loads.signPOD mutation button below the next-step copy.
    let actionKind: DLActionKind
    let stageFor: (DLLoadCtx?) -> DLStage

    init(loadId: String, actionKind: DLActionKind = .none, stageFor: @escaping (DLLoadCtx?) -> DLStage) {
        self.loadId = loadId
        self.actionKind = actionKind
        self.stageFor = stageFor
    }

    @Environment(\.palette) private var palette
    @State private var load: DLLoadCtx?
    @State private var loading: Bool = true
    @State private var actionInFlight: Bool = false
    @State private var actionAck: String?
    @State private var actionError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && load == nil {
                    LifecycleCard { Text("Loading load…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    let s = stageFor(load)
                    citationBanner(s)
                    kpiGrid(s.kpis)
                    nextStepCard(s.nextStep)
                    if actionKind == .podSign { signPODActionRow }
                    if let ack = actionAck {
                        LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(.green) }
                    }
                    if let err = actionError {
                        LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private var signPODActionRow: some View {
        Button { Task { await signPOD() } } label: {
            HStack(spacing: 6) {
                if actionInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                Text(actionInFlight ? "Signing…" : "Sign POD")
                    .font(EType.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(actionInFlight)
    }

    private func signPOD() async {
        actionInFlight = true; actionAck = nil; actionError = nil
        defer { actionInFlight = false }
        let sigHash = String(format: "0x%08X", UInt32.random(in: UInt32.min...UInt32.max))
        let podCertId = "BH7C3A-POD-\(Int(Date().timeIntervalSince1970))"
        struct In: Encodable { let loadId: String; let podCertId: String; let signatureHash: String; let signedAtIso: String? }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let podCertId: String?; let signatureHash: String?; let signedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "loads.signPOD",
                input: In(loadId: loadId, podCertId: podCertId, signatureHash: sigHash, signedAtIso: nil)
            )
            if resp.success == true {
                actionAck = "POD signed · cert \(resp.podCertId ?? podCertId) issued · NET-30 wires next."
                await loadCtx()
            } else {
                actionError = "POD sign returned no success flag — reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "POD sign failed: \(err)"
        }
    }

    private var header: some View {
        let s = stageFor(load)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(s.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(s.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(s.subtitle).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationBanner(_ s: DLStage) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—") · \(l.trailerType ?? "—")")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func kpiGrid(_ kpis: [DLKpi]) -> some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.color)
                    Text(k.subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.color.opacity(0.3)))
            }
        }
    }

    private func nextStepCard(_ copy: String) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadCtx() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: - Helpers shared across stages

private func tempLabel(_ f: Double?) -> String { f.map { String(format: "%.0f°F", $0) } ?? "—" }
private func etaLabel(_ iso: String?) -> String {
    guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
    let f = DateFormatter(); f.dateFormat = "H:mm"
    return f.string(from: d)
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DL094 At Gate
// MARK: ─────────────────────────────────────────────────────────

struct DriverAtGateScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DLShell(theme: theme) {
            DLBody(loadId: loadId) { l in
                DLStage(
                    eyebrow: "DRIVER · TRIPS · PICKUP · AT GATE",
                    citation: "§276 · WITHIN-TRACK THIRD-PORT OPENS",
                    title: "At the gate",
                    subtitle: "Gate inbound · 2 trucks ahead",
                    kpis: [
                        .init(label: "DOCK",  value: l?.dockNumber ?? "—", subtitle: "bay open", color: .blue),
                        .init(label: "DWELL", value: "0:00", subtitle: "queue 2", color: .green),
                        .init(label: "PALLETS", value: "\(l?.palletCount ?? 0)", subtitle: "to load", color: .blue),
                        .init(label: "DOCK ETA", value: "0:15", subtitle: "estimated", color: .blue),
                    ],
                    nextStep: "Dock assignment confirms in app. Pull to dock when assigned."
                )
            }
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DL095 At Dock
// MARK: ─────────────────────────────────────────────────────────

struct DriverAtDockScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DLShell(theme: theme) {
            DLBody(loadId: loadId) { l in
                DLStage(
                    eyebrow: "DRIVER · TRIPS · PICKUP · AT DOCK",
                    citation: "§278 · WITHIN-TRACK FOURTH-PORT OPENS",
                    title: "At dock · loading",
                    subtitle: "Live load · sealed on close",
                    kpis: [
                        .init(label: "DOCK", value: l?.dockNumber ?? "—", subtitle: "IN · loading", color: .orange),
                        .init(label: "PALLETS", value: "\(l?.palletCount ?? 0)", subtitle: "to load · sealed on close", color: .blue),
                        .init(label: "TEMP", value: tempLabel(l?.temperatureF), subtitle: "SEAL · pickup", color: .blue),
                        .init(label: "DWELL", value: "0:42", subtitle: "within 2h free", color: .green),
                    ],
                    nextStep: "Load is sealing now. BOL pre-sign queued — sign in app when shipper releases."
                )
            }
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DL096 Departing
// MARK: ─────────────────────────────────────────────────────────

struct DriverDepartingScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DLShell(theme: theme) {
            DLBody(loadId: loadId) { l in
                DLStage(
                    eyebrow: "DRIVER · TRIPS · PICKUP · DEPARTING",
                    citation: "§284 · WITHIN-TRACK FIFTH-PORT OPENS",
                    title: "Departing pickup",
                    subtitle: "Gate-out cleared · BOL pre-sign captured",
                    kpis: [
                        .init(label: "STATUS", value: "DEPARTED", subtitle: "gate-out cleared", color: .green),
                        .init(label: "PALLETS", value: "\(l?.palletCount ?? 0)", subtitle: "loaded · sealed", color: .blue),
                        .init(label: "ETA-DEL", value: etaLabel(l?.deliveryDate), subtitle: "delivery window", color: .blue),
                        .init(label: "BOL", value: "PRE-SIGN", subtitle: "ME · TR pending", color: .orange),
                    ],
                    nextStep: "Long-haul leg begins. Stay within HOS, check fuel cards, and ESang nudges in transit."
                )
            }
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DL097 Pre-Delivery
// MARK: ─────────────────────────────────────────────────────────

struct DriverPreDeliveryScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DLShell(theme: theme) {
            DLBody(loadId: loadId) { l in
                DLStage(
                    eyebrow: "DRIVER · TRIPS · IN TRANSIT · PRE-DELIVERY",
                    citation: "§289 · WITHIN-TRACK SIXTH-PORT OPENS",
                    title: "Pre-delivery approach",
                    subtitle: "Approaching receiver · BOL co-sign queued",
                    kpis: [
                        .init(label: "ETA", value: etaLabel(l?.deliveryDate), subtitle: "to dock", color: .blue),
                        .init(label: "TEMP", value: tempLabel(l?.temperatureF), subtitle: "in-range · sealed", color: .green),
                        .init(label: "PALLETS", value: "\(l?.palletCount ?? 0)", subtitle: "sealed in transit", color: .blue),
                        .init(label: "BOL", value: "READY", subtitle: "TR co-sign queued", color: .blue),
                    ],
                    nextStep: "Call ahead 15 min out. Confirm receiver dock + paperwork access."
                )
            }
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DL098 At Delivery
// MARK: ─────────────────────────────────────────────────────────

struct DriverAtDeliveryScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DLShell(theme: theme) {
            DLBody(loadId: loadId) { l in
                DLStage(
                    eyebrow: "DRIVER · TRIPS · DELIVERY · AT DOCK",
                    citation: "§290 · WITHIN-TRACK SEVENTH-PORT OPENS",
                    title: "At delivery · arrived",
                    subtitle: "Receiving bay · BOL co-sign begun",
                    kpis: [
                        .init(label: "ETA", value: "0m", subtitle: "ARRIVED · OTA", color: .green),
                        .init(label: "DOCK", value: l?.dockNumber ?? "—", subtitle: "IN · receiving", color: .orange),
                        .init(label: "TEMP", value: tempLabel(l?.temperatureF), subtitle: "SEAL · arrival", color: .blue),
                        .init(label: "PALLETS", value: "\(l?.palletCount ?? 0)", subtitle: "staging", color: .blue),
                    ],
                    nextStep: "Receiver inspects + co-signs. POD ink queues once final count locks."
                )
            }
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DL099 POD Sign
// MARK: ─────────────────────────────────────────────────────────

struct DriverPODSignScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DLShell(theme: theme) {
            DLBody(loadId: loadId, actionKind: .podSign) { l in
                let pal = l?.palletCount ?? 0
                return DLStage(
                    eyebrow: "DRIVER · TRIPS · PAPERWORK · POD SIGN",
                    citation: "§292 · WITHIN-TRACK EIGHTH-PORT OPENS",
                    title: "POD sign · \(pal)/\(pal) counted",
                    subtitle: "ePOD CERT QUEUED · ink-ready",
                    kpis: [
                        .init(label: "PALLETS", value: "\(pal)/\(pal)", subtitle: "COUNTED · seal", color: .green),
                        .init(label: "POD CERT", value: "QUEUED", subtitle: "awaiting ink", color: .orange),
                        .init(label: "TEMP", value: tempLabel(l?.temperatureF), subtitle: "SEAL · final", color: .blue),
                        .init(label: "RECEIVER", value: "TR SIGNED", subtitle: "co-signed · 0:14", color: .green),
                    ],
                    nextStep: "Tap to sign POD. ePOD CERT lands in the audit chain on ink confirmation."
                )
            }
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: DL100 Load Closed
// MARK: ─────────────────────────────────────────────────────────

struct DriverLoadClosedScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DLShell(theme: theme) {
            DLBody(loadId: loadId) { l in
                let pal = l?.palletCount ?? 0
                return DLStage(
                    eyebrow: "DRIVER · TRIPS · CLOSED · LOAD CLOSED",
                    citation: "§295 · WITHIN-TRACK NINTH-PORT OPENS · BACKHAUL ARMED",
                    title: "Load closed · payout staged",
                    subtitle: "ePOD ISSUED · NET-30 staged · chain sealed",
                    kpis: [
                        .init(label: "PALLETS", value: "\(pal)/\(pal)", subtitle: "FINAL · sealed", color: .green),
                        .init(label: "POD CERT", value: "ISSUED", subtitle: l?.podCertId ?? "ePOD chain sealed", color: .green),
                        .init(label: "PAYOUT", value: "$\(l?.rate ?? "—")", subtitle: "STAGED · NET-30", color: .green),
                        .init(label: "BACKHAUL", value: "ARMED", subtitle: "advance eligible", color: .blue),
                    ],
                    nextStep: "Backhaul offer arrives shortly. Take it or close the trip and rest."
                )
            }
        }
    }
}

// MARK: - Previews

#Preview("094 Gate · Dark")     { DriverAtGateScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("095 Dock · Light")    { DriverAtDockScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("096 Departing · Dark"){ DriverDepartingScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("097 PreDel · Light")  { DriverPreDeliveryScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("098 AtDel · Dark")    { DriverAtDeliveryScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("099 POD · Light")     { DriverPODSignScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("100 Closed · Dark")   { DriverLoadClosedScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
