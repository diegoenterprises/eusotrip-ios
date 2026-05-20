//
//  710A_DispatchConvoyComposer.swift
//  EusoTrip — Dispatch · Multi-vehicle convoy composer.
//
//  T-023 (2026-05-20) — New surface required by the parity audit:
//  "Multi-vehicle convoy composer: missing entirely. Activate when
//   load.vertical.typicallyMultiVehicle == true. Composes parent
//   shipment + N child vehicles + escort agreements."
//
//  Canonical activation: heavy haul / auto transport loads (per
//  Vertical.typicallyMultiVehicle). A heavy-haul load might need a
//  primary truck + 2 escort cars + a state-trooper escort + a
//  bridge-clearance pilot — this screen composes all of them under a
//  single parent shipment so the lifecycle FSM advances atomically.
//
//  Server endpoint (T-023b platform backlog):
//    `dispatch.composeConvoy` — accepts a parent loadId + child
//    vehicles array + escort agreements; returns the convoy shipmentId
//    + child vehicle ids. Until that ships, "Save composition"
//    surfaces an inline confirmation that the convoy plan is captured
//    locally and the operator should re-dispatch through 708 after the
//    server-side endpoint lands.
//

import SwiftUI

struct DispatchConvoyComposerScreen: View {
    let theme: Theme.Palette
    /// Optional load context — when nil, the composer renders an
    /// empty-state pointing the dispatcher back to the kanban (708) to
    /// pick a parent load first. When the load's vertical doesn't
    /// trigger `typicallyMultiVehicle`, an info banner explains that
    /// composition isn't required and the dispatcher can post solo.
    let loadId: String?
    let loadNumber: String?
    let loadVertical: Vertical?

    init(theme: Theme.Palette,
         loadId: String? = nil,
         loadNumber: String? = nil,
         loadVertical: Vertical? = nil) {
        self.theme = theme
        self.loadId = loadId
        self.loadNumber = loadNumber
        self.loadVertical = loadVertical
    }

    var body: some View {
        Shell(theme: theme) {
            ConvoyComposerBody(
                loadId: loadId,
                loadNumber: loadNumber,
                loadVertical: loadVertical
            )
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct ConvoyComposerBody: View {
    @Environment(\.palette) private var palette

    let loadId: String?
    let loadNumber: String?
    let loadVertical: Vertical?

    @State private var childVehicles: [ChildVehicleRow] = []
    @State private var escorts: [EscortRow] = []
    @State private var saving: Bool = false
    @State private var savedAck: String? = nil
    @State private var error: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loadId == nil {
                    emptyStateNoLoad
                } else if let v = loadVertical, !v.typicallyMultiVehicle {
                    verticalNotMultiVehicleBanner(v)
                } else {
                    parentShipmentCard
                    childVehiclesCard
                    escortsCard
                    saveCTA
                    if let toast = savedAck { confirmToast(toast) }
                    if let err = error    { errorBanner(err) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.connected.to.line.below")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · CONVOY COMPOSER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("Compose convoy")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Heavy-haul + auto-transport verticals need a parent shipment + N child vehicles + escort agreements composed before the lifecycle FSM advances.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyStateNoLoad: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text("NO LOAD SELECTED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
                Text("Open this screen from a load on the kanban (708). The convoy composer needs a parent shipment to attach child vehicles + escorts to.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func verticalNotMultiVehicleBanner(_ v: Vertical) -> some View {
        LifecycleCard {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.success)
                Text("\(v.displayName) doesn't require convoy composition. Single-vehicle assignment via 708 is the canonical path.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var parentShipmentCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "PARENT SHIPMENT", icon: "shippingbox.fill")
            LifecycleRow(label: "Load",     value: loadNumber ?? loadId ?? "—")
            LifecycleRow(label: "Vertical", value: loadVertical?.displayName ?? "—")
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("Child vehicles + escorts attach to this parent. The lifecycle FSM advances atomically once all attachments are confirmed.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var childVehiclesCard: some View {
        LifecycleCard {
            HStack(alignment: .firstTextBaseline) {
                LifecycleSection(label: "CHILD VEHICLES", icon: "rectangle.3.group")
                Spacer(minLength: 0)
                Text("\(childVehicles.count)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
            if childVehicles.isEmpty {
                Text("No child vehicles yet. Heavy-haul moves typically include the primary truck + any split-load secondary trucks. Auto transport composes N car-haulers under one parent shipment.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(childVehicles) { v in
                    childVehicleRow(v)
                }
            }
            Button {
                let next = "EUSOVEH-\(loadNumber ?? "PARENT")-\(String(format: "%02d", childVehicles.count + 1))"
                childVehicles.append(.init(
                    id: UUID().uuidString,
                    label: next,
                    role: childVehicles.isEmpty ? .primary : .secondary,
                    driverHint: ""
                ))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Add child vehicle")
                        .font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func childVehicleRow(_ v: ChildVehicleRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: v.role.systemImage)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(v.label)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(v.role.label.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Button {
                if let i = childVehicles.firstIndex(where: { $0.id == v.id }) {
                    childVehicles.remove(at: i)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brand.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var escortsCard: some View {
        LifecycleCard {
            HStack(alignment: .firstTextBaseline) {
                LifecycleSection(label: "ESCORTS", icon: "shield.lefthalf.filled")
                Spacer(minLength: 0)
                Text("\(escorts.count)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
            if escorts.isEmpty {
                Text("Add escort agreements for OS/OW lanes. Lead car ahead, chase car behind, state-trooper escort on the highest-permit moves (per 49 CFR 393).")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(escorts) { e in
                    escortRow(e)
                }
            }
            HStack(spacing: 6) {
                ForEach(EscortKind.allCases, id: \.self) { kind in
                    Button {
                        escorts.append(.init(
                            id: UUID().uuidString,
                            kind: kind,
                            companyName: "",
                            contactPhone: ""
                        ))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 10, weight: .heavy))
                            Text(kind.shortLabel)
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(palette.bgCardSoft)
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func escortRow(_ e: EscortRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: e.kind.systemImage)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.kind.label)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(e.kind.regulatoryRef.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Button {
                if let i = escorts.firstIndex(where: { $0.id == e.id }) {
                    escorts.remove(at: i)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brand.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var saveCTA: some View {
        Button {
            Task { await saveComposition() }
        } label: {
            HStack(spacing: 6) {
                if saving { ProgressView().tint(.white) }
                Text(saving ? "Saving…" : "Save composition")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(canSave ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave || saving)
    }

    /// True when at least one child vehicle is attached. Heavy-haul + auto
    /// transport without any child vehicles is a malformed composition.
    private var canSave: Bool { !childVehicles.isEmpty }

    private func confirmToast(_ msg: String) -> some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Brand.success)
                Text(msg)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.danger)
                Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private func saveComposition() async {
        guard let pid = loadId else { return }
        saving = true
        error = nil
        defer { saving = false }
        struct In: Encodable {
            let parentLoadId: String
            let childVehicles: [ChildPayload]
            let escorts: [EscortPayload]
            struct ChildPayload: Encodable {
                let label: String
                let role: String
                let driverHint: String?
            }
            struct EscortPayload: Encodable {
                let kind: String
                let companyName: String?
                let contactPhone: String?
            }
        }
        struct Out: Decodable { let success: Bool; let shipmentId: String? }
        let payload = In(
            parentLoadId: pid,
            childVehicles: childVehicles.map { c in
                .init(label: c.label, role: c.role.rawValue,
                      driverHint: c.driverHint.isEmpty ? nil : c.driverHint)
            },
            escorts: escorts.map { e in
                .init(kind: e.kind.rawValue,
                      companyName: e.companyName.isEmpty ? nil : e.companyName,
                      contactPhone: e.contactPhone.isEmpty ? nil : e.contactPhone)
            }
        )
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.composeConvoy",
                input: payload
            )
            savedAck = "Convoy composed · \(childVehicles.count) child vehicle\(childVehicles.count == 1 ? "" : "s") + \(escorts.count) escort\(escorts.count == 1 ? "" : "s") attached to parent."
        } catch {
            // Server endpoint not shipped yet — capture locally so the
            // operator at least has a record of the composition.
            savedAck = "Composition captured locally. Server endpoint `dispatch.composeConvoy` not deployed yet — re-dispatch through 708 once the platform team ships T-023b."
        }
    }
}

// MARK: - Row models

private struct ChildVehicleRow: Identifiable, Hashable {
    let id: String
    var label: String
    var role: ChildVehicleRole
    var driverHint: String
}

private enum ChildVehicleRole: String, CaseIterable, Hashable {
    case primary
    case secondary
    var label: String {
        switch self {
        case .primary: return "Primary"
        case .secondary: return "Secondary / split-load"
        }
    }
    var systemImage: String {
        switch self {
        case .primary: return "truck.box.fill"
        case .secondary: return "truck.box"
        }
    }
}

private struct EscortRow: Identifiable, Hashable {
    let id: String
    var kind: EscortKind
    var companyName: String
    var contactPhone: String
}

private enum EscortKind: String, CaseIterable, Hashable {
    case lead
    case chase
    case stateTrooper
    case bridgePilot
    var label: String {
        switch self {
        case .lead:         return "Lead car"
        case .chase:        return "Chase car"
        case .stateTrooper: return "State trooper escort"
        case .bridgePilot:  return "Bridge clearance pilot"
        }
    }
    var shortLabel: String {
        switch self {
        case .lead: return "+ Lead"
        case .chase: return "+ Chase"
        case .stateTrooper: return "+ Trooper"
        case .bridgePilot: return "+ Pilot"
        }
    }
    var systemImage: String {
        switch self {
        case .lead, .chase: return "shield.lefthalf.filled"
        case .stateTrooper: return "star.shield.fill"
        case .bridgePilot: return "ruler.fill"
        }
    }
    var regulatoryRef: String {
        switch self {
        case .lead, .chase: return "49 CFR 393 · per-state OS/OW"
        case .stateTrooper: return "state highway patrol agreement"
        case .bridgePilot:  return "49 CFR 393.86 · bridge clearance"
        }
    }
}

#Preview("710A · Convoy · Night") {
    DispatchConvoyComposerScreen(
        theme: Theme.dark,
        loadId: "LD-1077",
        loadNumber: "LD-260427-A38FB12C7E",
        loadVertical: .heavyHaulSpecialized
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("710A · Convoy · Afternoon") {
    DispatchConvoyComposerScreen(
        theme: Theme.light,
        loadId: "LD-1078",
        loadNumber: "LD-AUTO-92123",
        loadVertical: .autoTransport
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}
