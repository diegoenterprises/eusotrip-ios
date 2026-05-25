//
//  557_RailStatusUpdate.swift
//  EusoTrip — Rail Engineer · Update Status (carrier action).
//
//  Status machine: car_ordered -> car_placed -> loaded -> departed ->
//  in_transit -> at_interchange -> in_yard -> spotted -> settled.
//

import SwiftUI

struct RailStatusUpdateScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int
    let currentStatus: String
    var body: some View {
        Shell(theme: theme) {
            RailStatusUpdateBody(shipmentId: shipmentId, currentStatus: currentStatus)
        } nav: {
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

private struct RailStatusOption: Identifiable {
    let id = UUID()
    let value: String
    let title: String
    let note: String
    let danger: Bool
}

private struct RailStatusUpdateBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let currentStatus: String
    @State private var selected: String = "at_interchange"
    @State private var submitting = false
    @State private var errorText: String? = nil
    @State private var done = false

    private let options: [RailStatusOption] = [
        RailStatusOption(value: "at_interchange", title: "At interchange", note: "NS Inman handoff · records yard + timestamp", danger: false),
        RailStatusOption(value: "in_yard",        title: "In yard (spotted)", note: "starts demurrage free-time meter", danger: false),
        RailStatusOption(value: "exception_hold", title: "Hold — exception", note: "flags control tower · requires note", danger: true)
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
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · UPDATE STATUS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text("RS-\(shipmentId)").font(.system(size: 26, weight: .heavy)).monospaced().foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: currentStatus.replacingOccurrences(of: "_", with: " ").uppercased(), kind: .info)
            }
            Text("Carrier mutation · advances the shared lifecycle stage").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var statusMachineCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("STATUS MACHINE · railShipments status").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("car_ordered · car_placed · loaded · departed").font(EType.caption).foregroundStyle(palette.textTertiary)
                    HStack { Circle().fill(LinearGradient.primary).frame(width: 12, height: 12); Text("in_transit").font(EType.bodyStrong).foregroundStyle(palette.textPrimary); Spacer(); Text("CURRENT").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.info) }
                    HStack { Circle().stroke(LinearGradient.primary, lineWidth: 2).frame(width: 12, height: 12); Text("at_interchange").font(EType.bodyStrong).foregroundStyle(palette.textPrimary); Spacer(); Text("next ›").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textSecondary) }
                    Text("in_yard · spotted · settled").font(EType.caption).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var advanceToSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ADVANCE TO · updateRailShipmentStatus(status)").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
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
                Text("Birmingham AL · 33.5207, -86.8025 · 05-23 04:48 CDT").font(EType.body).foregroundStyle(palette.textPrimary)
                Text("Auto-recorded to getRailShipmentDetail.events on confirm").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var esangNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("ESANG AI").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Interchange at NS Inman keeps the 05-24 06:30 ETA intact.").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = errorText { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
            if done { Text("Status advanced.").font(EType.caption).foregroundStyle(Brand.success) }
            HStack(spacing: Space.s2) {
                CTAButton(title: submitting ? "Confirming…" : "Confirm advance",
                          leadingIcon: "arrow.triangle.2.circlepath",
                          action: { Task { await confirm() } })
                CTAButton(title: "Cancel")
            }
        }
    }

    private func confirm() async {
        submitting = true; errorText = nil
        struct StatusIn: Encodable { let id: Int; let status: String }
        struct Empty557: Decodable {}
        do {
            _ = try await EusoTripAPI.shared.mutation(
                "railShipments.updateRailShipmentStatus",
                input: StatusIn(id: shipmentId, status: selected)) as Empty557
            done = true
        } catch {
            errorText = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }
}

#Preview("557 · Rail Status Update · Night") { RailStatusUpdateScreen(theme: Theme.dark, shipmentId: 48231, currentStatus: "in_transit").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("557 · Rail Status Update · Light") { RailStatusUpdateScreen(theme: Theme.light, shipmentId: 48231, currentStatus: "in_transit").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
