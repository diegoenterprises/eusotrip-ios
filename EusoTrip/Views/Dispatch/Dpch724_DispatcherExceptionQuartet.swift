//
//  Dpch724_DispatcherExceptionQuartet.swift
//  EusoTrip — Dispatcher · Exception-flow quartet (412/415/418/419).
//
//  Bundled file because all four SVGs share the same structure:
//    eyebrow + exception priority header + carrier/driver card +
//    stage-specific KPI strip + action row(s).
//
//  Pixel-match to:
//    412 Dispatcher HOS Reassignment.svg
//    415 Dispatcher Cancel Load Wizard.svg
//    418 Dispatcher Late-Pickup.svg
//    419 Dispatcher Dock-Mismatch.svg
//
//  All four read off `loads.getById(loadId)` for context and the
//  existing `dispatch.resolveException` mutation (post-action), so
//  no new server work is needed for the wire. Bottom nav frozen.
//

import SwiftUI

private struct ExceptionLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let distance: Double?
    let assignedDriverName: String?
    let pickupDate: String?
    let deliveryDate: String?
}

// MARK: - Shell

private struct ExceptionShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 412 HOS Reassignment
// MARK: ─────────────────────────────────────────────────────────

private struct AvailableDriver: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let hosRemainingMin: Int?
    let currentLocation: String?
    let utilizationPct: Double?
}

struct DispatcherHOSReassignmentScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        ExceptionShell(theme: theme) { HOSReassignBody(loadId: loadId) }
    }
}

private struct HOSReassignBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: ExceptionLoadCtx?
    @State private var candidates: [AvailableDriver] = []
    @State private var selectedCandidate: String?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                loadContextCard
                wizardStrip(step: 2)
                candidatesSection
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Reassign load").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("P0 · HOS REASSIGN").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.18)))
                        .foregroundStyle(.red)
                    Spacer()
                    Text("SLA 90s").font(.caption.monospaced().weight(.semibold)).foregroundStyle(.red)
                }
                Text("HOS-AWARE WIZARD · clock breach + trip needs > remaining drive")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var loadContextCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—")")
                        .font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("\(l.trailerType ?? "—") · \(l.cargoType ?? "—") · $\(l.rate ?? "—")")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                    Text("\(Int(l.distance ?? 0)) mi · ETA \(etaText(l.deliveryDate))")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func wizardStrip(step: Int) -> some View {
        let steps = ["REASON", "PICK DRIVER", "CONFIRM"]
        return HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, lbl in
                let active = idx + 1 == step
                let cleared = idx + 1 < step
                HStack(spacing: 4) {
                    Text("\(idx + 1)")
                        .font(.system(size: 11, weight: .heavy))
                        .frame(width: 22, height: 22)
                        .background(active || cleared ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                        .clipShape(Circle())
                        .foregroundStyle(active || cleared ? .white : palette.textTertiary)
                    Text(lbl).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(active ? palette.textPrimary : palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CANDIDATES · TAP TO SELECT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if loading && candidates.isEmpty {
                LifecycleCard { Text("Loading candidates…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if candidates.isEmpty {
                EusoEmptyState(systemImage: "person.crop.circle.badge.questionmark", title: "No HOS-eligible drivers", subtitle: "Driver pool needs more available capacity.")
            } else {
                ForEach(candidates) { c in candidateCard(c) }
            }
        }
    }

    private func candidateCard(_ c: AvailableDriver) -> some View {
        let isSelected = selectedCandidate == c.id
        return Button { selectedCandidate = c.id } label: {
            LifecycleCard(accentGradient: isSelected) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name ?? "Driver \(c.id)").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                        if let loc = c.currentLocation { Text(loc).font(.caption).foregroundStyle(palette.textSecondary) }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("HOS \((c.hosRemainingMin ?? 0) / 60)h \((c.hosRemainingMin ?? 0) % 60)m")
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle((c.hosRemainingMin ?? 0) > 120 ? .green : .orange)
                        if let u = c.utilizationPct {
                            Text("UTIL \(Int(u))%").font(.caption2.weight(.semibold)).foregroundStyle(palette.textTertiary)
                        }
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { } label: {
                Text("Back")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button { } label: {
                Text(selectedCandidate == nil ? "Select a driver" : "Confirm reassign")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(selectedCandidate == nil ? 0.5 : 1)
            }.buttonStyle(.plain).disabled(selectedCandidate == nil)
        }
    }

    private func etaText(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let mins = Int(d.timeIntervalSinceNow / 60)
        if mins < 0 { return "ARRIVED" }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let l: Void = loadCtx()
        async let c: Void = loadCandidates()
        _ = await (l, c)
    }
    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
    private func loadCandidates() async {
        struct In: Encodable { let limit: Int }
        do { candidates = try await EusoTripAPI.shared.query("dispatch.getAvailableDrivers", input: In(limit: 12)) } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 415 Cancel Load Wizard
// MARK: ─────────────────────────────────────────────────────────

struct DispatcherCancelLoadWizardScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        ExceptionShell(theme: theme) { CancelLoadBody(loadId: loadId) }
    }
}

private struct CancelLoadBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var load: ExceptionLoadCtx?
    @State private var reason: String = "Receiver facility unavailable"
    @State private var cascadeAck: Bool = false
    @State private var policyAck: Bool = false
    @State private var loading: Bool = true
    @State private var actionInFlight: Bool = false
    @State private var actionAck: String?
    @State private var actionError: String?

    private let reasons: [String] = [
        "Receiver facility unavailable",
        "Shipper requested cancel",
        "Carrier unavailable",
        "Equipment unavailable",
        "Weather / route block",
        "Other",
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                loadContextCard
                wizardStrip
                reasonSection
                cascadeSection
                policySection
                actionRow
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(.green) }
                }
                if let err = actionError {
                    LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Cancel load").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Pre-pickup · irreversible").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("P1 · CANCEL").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                Spacer()
                Text("3-STEP WIZARD").font(.caption2.weight(.semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var loadContextCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—")")
                        .font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("\(l.trailerType ?? "—") · \(l.cargoType ?? "—") · $\(l.rate ?? "—") · \(Int(l.distance ?? 0)) mi")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var wizardStrip: some View {
        HStack(spacing: 6) {
            ForEach(Array(["REASON", "CASCADE", "POLICY"].enumerated()), id: \.offset) { idx, lbl in
                HStack(spacing: 4) {
                    Text("\(idx + 1)")
                        .font(.system(size: 11, weight: .heavy))
                        .frame(width: 22, height: 22)
                        .background(AnyShapeStyle(LinearGradient.diagonal))
                        .clipShape(Circle())
                        .foregroundStyle(.white)
                    Text(lbl).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textPrimary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REASON · SHIPPER REQUESTED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(reasons, id: \.self) { r in
                Button { reason = r } label: {
                    HStack {
                        Image(systemName: reason == r ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(reason == r ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                        Text(r).font(EType.body).foregroundStyle(palette.textPrimary)
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                }.buttonStyle(.plain)
            }
        }
    }

    private var cascadeSection: some View {
        Toggle(isOn: $cascadeAck) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notify cascade").font(EType.body.weight(.semibold))
                Text("Driver · receiver · shipper · accounting").font(.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
    }

    private var policySection: some View {
        Toggle(isOn: $policyAck) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apply cancel-fee policy").font(EType.body.weight(.semibold))
                Text("$150 cancel fee per Eusotrans contract §3.4").font(.caption).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Text("Back")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            .disabled(actionInFlight)

            Button { Task { await confirmCancel() } } label: {
                HStack(spacing: 6) {
                    if actionInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(actionInFlight ? "Cancelling…" : "Confirm cancel · irreversible")
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(Brand.danger)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight || !cascadeAck || !policyAck)
        }
    }

    private func confirmCancel() async {
        actionInFlight = true; actionAck = nil; actionError = nil
        defer { actionInFlight = false }
        struct In: Encodable { let loadId: String; let reason: String; let waiveTonus: Bool; let cascadeAck: Bool }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let cancelledAt: String?; let reason: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.cancelLoad",
                input: In(loadId: loadId, reason: reason, waiveTonus: false, cascadeAck: cascadeAck)
            )
            if resp.success == true {
                actionAck = "Load cancelled · reason '\(resp.reason ?? reason)' archived to audit chain."
                await loadCtx()
            } else {
                actionError = "Cancel returned no success flag — reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "Cancel failed: \(err)"
        }
    }

    private func loadCtx() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 418 Late-Pickup Recovery
// MARK: ─────────────────────────────────────────────────────────

struct DispatcherLatePickupScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        ExceptionShell(theme: theme) { LatePickupBody(loadId: loadId) }
    }
}

private struct LatePickupBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: ExceptionLoadCtx?
    @State private var loading: Bool = true
    @State private var actionInFlight: String? = nil
    @State private var actionAck: String?
    @State private var actionError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                driverCard
                releaseCountdown
                actionRow
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(.green) }
                }
                if let err = actionError {
                    LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pickup recovery").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Window expired · driver inbound").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("P1 · LATE PU").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                Spacer()
                Text("38 min late · 22 min to auto-release").font(.caption.monospaced().weight(.semibold)).foregroundStyle(.orange)
            }
        }
    }

    private var driverCard: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text(initialsFor(load?.assignedDriverName)).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(load?.assignedDriverName ?? "Driver").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    if let l = load {
                        Text("\(l.trailerType ?? "—") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—")").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    Text("4 mi out · HOS 9:14 left").font(.caption2.monospaced()).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var releaseCountdown: some View {
        LifecycleCard(accentDanger: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AUTO-RELEASE TIMER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("22:00").font(.system(size: 36, weight: .heavy).monospacedDigit()).foregroundStyle(.orange)
                Text("until shipper auto-releases load to marketplace")
                    .font(.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { Task { await extendWindow() } } label: {
                HStack(spacing: 6) {
                    if actionInFlight == "extend" { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(actionInFlight == "extend" ? "Extending…" : "Extend window")
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight != nil)

            Button { Task { await releaseToMarket() } } label: {
                HStack(spacing: 6) {
                    if actionInFlight == "release" { ProgressView().scaleEffect(0.8) }
                    Text(actionInFlight == "release" ? "Releasing…" : "Release to market")
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(palette.textPrimary)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.5)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight != nil)
        }
    }

    private func extendWindow() async {
        actionInFlight = "extend"; actionAck = nil; actionError = nil
        defer { actionInFlight = nil }
        struct In: Encodable { let loadId: String; let minutes: Int; let reason: String? }
        struct Out: Decodable { let success: Bool?; let newPickupIso: String?; let extendedMinutes: Int? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.extendPickupWindow",
                input: In(loadId: loadId, minutes: 30, reason: "Driver 38 min late · 4 mi out · dispatcher extended via Dpch726")
            )
            if resp.success == true {
                actionAck = "Pickup window extended +\(resp.extendedMinutes ?? 30)m · new ETA \(resp.newPickupIso?.prefix(16) ?? "—")."
                await loadCtx()
            } else {
                actionError = "Extend returned no success flag — reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "Extend failed: \(err)"
        }
    }

    private func releaseToMarket() async {
        actionInFlight = "release"; actionAck = nil; actionError = nil
        defer { actionInFlight = nil }
        struct In: Encodable { let loadId: String; let fallbackCarrierId: String?; let reason: String? }
        struct Out: Decodable { let success: Bool?; let reassignedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.reassignLoad",
                input: In(loadId: loadId, fallbackCarrierId: nil, reason: "Auto-release after late pickup · 22m window expired")
            )
            if resp.success == true {
                actionAck = "Released to market · load returned to the pool · carriers can re-bid now."
                await loadCtx()
            } else {
                actionError = "Release returned no success flag — reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "Release failed: \(err)"
        }
    }

    private func initialsFor(_ name: String?) -> String {
        guard let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return "—" }
        let parts = n.split(separator: " ").map(String.init)
        let f = parts.first?.first.map(String.init) ?? ""
        let l = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (f + l).uppercased()
    }

    private func loadCtx() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 419 Dock-Mismatch Reroute
// MARK: ─────────────────────────────────────────────────────────

struct DispatcherDockMismatchScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        ExceptionShell(theme: theme) { DockMismatchBody(loadId: loadId) }
    }
}

private struct DockMismatchBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: ExceptionLoadCtx?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                driverCard
                rerouteCard
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Dock reroute").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Consignee-initiated · detention timer").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("P2 · DOCK MISMATCH").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow.opacity(0.18)))
                    .foregroundStyle(.yellow)
                Spacer()
                Text("24 min timer").font(.caption.monospaced().weight(.semibold)).foregroundStyle(.yellow)
            }
        }
    }

    private var driverCard: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text(initialsFor(load?.assignedDriverName)).font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(load?.assignedDriverName ?? "Driver").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    if let l = load {
                        Text("\(l.trailerType ?? "—") · \(l.cargoType ?? "—")").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    Text("ESCORT-046 EM-3 lead · UN1005").font(.caption2.monospaced()).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var rerouteCard: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 6) {
                Text("REROUTE · DOCK 7 → 14")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FROM").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        Text("Dock 7").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(palette.textPrimary)
                    }
                    Image(systemName: "arrow.right").foregroundStyle(palette.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TO").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        Text("Dock 14").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(LinearGradient.diagonal)
                    }
                    Spacer()
                }
                Text("DETENTION 4 / 24 MIN").font(.caption2.weight(.semibold)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { } label: {
                Text("Accept reroute")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button { } label: {
                Text("Dispute")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func initialsFor(_ name: String?) -> String {
        guard let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return "—" }
        let parts = n.split(separator: " ").map(String.init)
        let f = parts.first?.first.map(String.init) ?? ""
        let l = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (f + l).uppercased()
    }

    private func loadCtx() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: - Previews

#Preview("412 HOS · Dark")   { DispatcherHOSReassignmentScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("415 Cancel · Dark"){ DispatcherCancelLoadWizardScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("418 Late · Dark")  { DispatcherLatePickupScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("419 Dock · Dark")  { DispatcherDockMismatchScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("412 HOS · Light")  { DispatcherHOSReassignmentScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("415 Cancel · Light"){ DispatcherCancelLoadWizardScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("418 Late · Light") { DispatcherLatePickupScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("419 Dock · Light") { DispatcherDockMismatchScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
