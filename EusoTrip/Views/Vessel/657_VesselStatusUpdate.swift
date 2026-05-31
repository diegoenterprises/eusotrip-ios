//
//  657_VesselStatusUpdate.swift
//  EusoTrip — Vessel Operator · Update Status (carrier action).
//
//  Verbatim port of "657 Vessel Status Update.svg" (Light + Dark). Vessel
//  counterpart of 557_RailStatusUpdate. Reached from 653_VesselBookingDetailCarrier's
//  "Update status" CTA. Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), Shipments tab current.
//
//  Data:
//    vesselShipments.getVesselShipmentDetail (EXISTS vesselShipments.ts:162) -> status
//    vesselShipments.updateVesselShipmentStatus (EXISTS vesselShipments.ts:192 ·
//      CARRIER mutation; advances shared lifecycleStage, records event w/ geostamp)
//
//  Status machine (verbatim §442): booking_requested -> booking_confirmed ->
//  documentation -> container_released -> gate_in -> loaded_on_vessel -> departed ->
//  in_transit -> transshipment -> arrived -> customs_hold -> customs_cleared ->
//  discharged -> gate_out -> delivered -> invoiced -> settled.
//

import SwiftUI

struct VesselStatusUpdateScreen: View {
    let theme: Theme.Palette
    let bookingId: Int
    let currentStatus: String
    var body: some View {
        Shell(theme: theme) {
            VesselStatusUpdateBody(bookingId: bookingId, currentStatus: currentStatus)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
        // Real top back affordance (replaces the old decorative chevron in
        // the body header). Fixed leading slot → never overlaps the title;
        // posts the shared NavBack the VesselOperatorSurface pops on.
        .injectBespokeBackBar(title: nil) {
            NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
        }
    }
}

private struct VesselStatusOption: Identifiable {
    let id = UUID()
    let value: String
    let title: String
    let note: String
    let danger: Bool
}

private struct VesselStatusUpdateBody: View {
    @Environment(\.palette) private var palette
    let bookingId: Int
    let currentStatus: String
    @State private var selected: String = "arrived"
    @State private var submitting = false
    @State private var errorText: String? = nil
    @State private var done = false

    private let options: [VesselStatusOption] = [
        VesselStatusOption(value: "arrived",        title: "Arrived", note: "Port of Savannah call · records ATA timestamp", danger: false),
        VesselStatusOption(value: "transshipment",  title: "Transshipment", note: "relay leg via hub port · keeps in-transit", danger: false),
        VesselStatusOption(value: "customs_hold",   title: "Customs hold — exception", note: "flags control tower · requires note", danger: true)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                statusMachineCard
                advanceToSection
                eventStamp
                esangNote
                actions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · UPDATE STATUS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text("VS-\(bookingId)").font(.system(size: 26, weight: .heavy)).monospaced().foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: currentStatus.replacingOccurrences(of: "_", with: " ").uppercased(), kind: .info)
            }
            Text("Carrier mutation · advances the shared lifecycle stage").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var statusMachineCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("STATUS MACHINE · vesselShipments status").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("loaded_on_vessel · departed").font(EType.caption).foregroundStyle(palette.textTertiary)
                    HStack { Circle().fill(LinearGradient.primary).frame(width: 12, height: 12); Text("in_transit").font(EType.bodyStrong).foregroundStyle(palette.textPrimary); Spacer(); Text("CURRENT").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.info) }
                    HStack { Circle().stroke(LinearGradient.primary, lineWidth: 2).frame(width: 12, height: 12); Text("arrived").font(EType.bodyStrong).foregroundStyle(palette.textPrimary); Spacer(); Text("next ›").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textSecondary) }
                    Text("customs_cleared · discharged · gate_out · delivered").font(EType.caption).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var advanceToSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ADVANCE TO · updateVesselShipmentStatus(status)").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            ForEach(options) { opt in
                Button { selected = opt.value } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(selected == opt.value ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textTertiary), lineWidth: 2).frame(width: 18, height: 18)
                            if selected == opt.value { Circle().fill(LinearGradient.primary).frame(width: 9, height: 9) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(opt.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text(opt.note).font(.system(size: 10.5)).foregroundStyle(opt.danger ? Brand.danger : palette.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected == opt.value ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint), lineWidth: selected == opt.value ? 1.5 : 1)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var eventStamp: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EVENT STAMP").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Text("31.95N, 79.10W · approaching Savannah · 05-23 14:10 EDT").font(EType.body).foregroundStyle(palette.textPrimary)
                Text("Auto-recorded to getVesselShipmentDetail.events on confirm").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var esangNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("ESANG AI").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Berth window confirmed at GPA Garden City — no anchorage wait.").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = errorText { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
            if done { Text("Status advanced.").font(EType.caption).foregroundStyle(Brand.success) }
            HStack(spacing: Space.s2) {
                CTAButton(title: submitting ? "Confirming…" : "Confirm advance",
                          action: { Task { await confirm() } },
                          leadingIcon: "arrow.triangle.2.circlepath")
                CTAButton(title: "Cancel",
                          action: { NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil) })
            }
        }
    }

    private func confirm() async {
        submitting = true; errorText = nil
        struct StatusIn: Encodable { let id: Int; let newStatus: String }
        struct Empty657: Decodable {}
        do {
            let _: Empty657 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.updateVesselShipmentStatus",
                input: StatusIn(id: bookingId, newStatus: selected))
            done = true
            // Submit-and-return: pop back to the booking detail so the
            // updated status reloads there (no stale entry left on stack).
            NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
        } catch {
            errorText = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }
}

#Preview("657 · Vessel Status Update · Night") { VesselStatusUpdateScreen(theme: Theme.dark, bookingId: 77310, currentStatus: "in_transit").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("657 · Vessel Status Update · Light") { VesselStatusUpdateScreen(theme: Theme.light, bookingId: 77310, currentStatus: "in_transit").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
