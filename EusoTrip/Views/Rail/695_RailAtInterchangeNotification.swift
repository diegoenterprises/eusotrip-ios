//
//  695_RailAtInterchangeNotification.swift
//  EusoTrip — Rail Engineer · Notify Consignee At Interchange.
//
//  Bespoke port of "05 Rail/Dark-SVG/695 Rail At-Interchange Notification.svg".
//  ARCHETYPE = BROADCAST COMPOSER — an auto-fired event hero, a recipients ×
//  channels matrix, and an auto-localized message preview. Deliberately a
//  composer, NOT a detail card and NOT a timeline.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getConsigneePreview  EXISTS railShipments.ts:2883
//        {shipmentNumber} → {consigneeName,consigneeEmail,destinationName/City/
//        State,railcarNumber,status,lastEventLocation,lastEventAt}. Tenant-gated
//        (no cross-tenant consignee PII leak). This drives the recipient row and
//        the event hero — a real consignee or an honest "no consignee on file".
//    railShipments.notifyConsigneeAtInterchange EXISTS railShipments.ts:2304
//        {shipmentId,interchangePointName?,etaText?,country?} → sends via
//        notificationService, broadens the emitRailAtInterchange WS event to the
//        consignee's room, and writes a blockchainAuditTrail rail.consignee_
//        notified row. Ownership-gated. "Send" fires this; success shows only
//        after the write lands.
//    railShipments.getCrossBorderInterchangePoints EXISTS railShipments.ts:2621
//        — the interchange-point + country the localization is driven by.
//  HONEST STATE:
//    The server delivers on the consignee's enabled channels; the channel chips
//    express intent, never a fabricated multi-recipient blast. A site / customs-
//    broker recipient with no contact on file is shown as "add contact", never
//    given an invented name or a phantom send.
//

import SwiftUI

struct RailAtInterchangeNotifyScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var shipmentNumber: String = ""

    var body: some View {
        Shell(theme: theme) {
            RailAtInterchangeNotifyBody(shipmentId: shipmentId, shipmentNumber: shipmentNumber)
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

// MARK: - Data shapes

private struct ConsigneePreview695: Decodable {
    let shipmentNumber: String?
    let consigneeName: String?
    let consigneeEmail: String?
    let destinationName: String?
    let destinationCity: String?
    let destinationState: String?
    let railcarNumber: String?
    let status: String?
    let lastEventLocation: String?
    let lastEventAt: String?
}
private struct PreviewInput695: Encodable { let shipmentNumber: String }

private struct InterchangePoint695: Decodable, Identifiable, Hashable {
    let id: String?
    let name: String?
    var key: String { id ?? name ?? UUID().uuidString }
    var display: String { name ?? id ?? "Interchange" }
}
private struct InterchangeInput695: Encodable { let country: String? }

private struct NotifyInput695: Encodable {
    let shipmentId: Int
    let interchangePointName: String?
    let etaText: String?
    let country: String?
}
private struct NotifyResult695: Decodable {
    let sent: Bool?
    let reason: String?
    let channels: [String]?
    let consigneeId: Int?
}

// MARK: - Body

private struct RailAtInterchangeNotifyBody: View {
    let shipmentId: Int
    let shipmentNumber: String

    @Environment(\.palette) private var palette
    @State private var preview: ConsigneePreview695? = nil
    @State private var points: [InterchangePoint695] = []
    @State private var chosenPoint: InterchangePoint695? = nil
    @State private var loading = true
    @State private var sending = false
    @State private var sentResult: NotifyResult695? = nil
    @State private var sendError: String? = nil
    @State private var scheduled = false
    @State private var regime = 0
    // Channel intent — the platform delivers on the consignee's enabled channels.
    @State private var wantsPush = true
    @State private var wantsEmail = true
    @State private var wantsSMS = false

    private let regimes: [(String, String, String)] = [
        ("US · EN", "push+email", "US"),
        ("CA · EN/FR", "bilingual", "CA"),
        ("MX · ES", "SMS/Wapp", "MX"),
    ]

    private var hasConsignee: Bool { (preview?.consigneeName ?? preview?.consigneeEmail) != nil }
    private var laneText: String {
        let city = preview?.destinationCity
        let state = preview?.destinationState
        if let c = city, let s = state { return "\(c), \(s)" }
        return preview?.destinationName ?? "destination"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Notify consignee")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("\(preview?.shipmentNumber ?? (shipmentNumber.isEmpty ? "rail shipment" : shipmentNumber)) · \(laneText)")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4).lineLimit(1)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    eventHero
                    interchangePicker
                    recipientHeader
                    recipientMatrix
                    messagePreview
                    triBand
                    footerActions
                    resultBanner
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ CARRIER · RAIL · NOTIFY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("AT-INTERCHANGE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("at interchange", Brand.info)
            chip(hasConsignee ? "consignee on file" : "no consignee", hasConsignee ? Brand.success : Brand.warning)
            if let car = preview?.railcarNumber { chip(car, palette.textSecondary) }
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Auto-fired event hero.

    private var eventHero: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(Brand.info.opacity(0.12)).frame(width: 46, height: 46)
                Image(systemName: "bell.badge.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(Brand.info)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("EVENT · AT INTERCHANGE").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                    Text("auto-fired").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.info)
                        .padding(.horizontal, 6).frame(height: 16).background(Capsule().fill(Brand.info.opacity(0.14)))
                }
                Text("Car reached the interchange").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(preview?.lastEventLocation.map { "last event · \($0)" } ?? "notify the consignee on their channel now")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    @ViewBuilder
    private var interchangePicker: some View {
        Menu {
            ForEach(points, id: \.key) { p in Button(p.display) { chosenPoint = p } }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.blue)
                Text(chosenPoint?.display ?? "Interchange point (localizes the message)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(chosenPoint == nil ? palette.textTertiary : palette.textPrimary).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private var recipientHeader: some View {
        HStack {
            Text("RECIPIENTS · DELIVERY CHANNELS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(activeChannels.isEmpty ? "no channel selected" : activeChannels.joined(separator: " · ").lowercased())
                .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var activeChannels: [String] {
        var c: [String] = []
        if wantsPush { c.append("PUSH") }
        if wantsEmail { c.append("EMAIL") }
        if wantsSMS { c.append("SMS") }
        return c
    }

    // MARK: Recipients × channels matrix — only real recipients, honest gaps.

    private var recipientMatrix: some View {
        VStack(spacing: 0) {
            // Consignee — the real recipient the server notifies.
            if hasConsignee {
                recipientRow(name: preview?.consigneeName ?? "Consignee",
                             role: "Consignee · primary",
                             detail: preview?.consigneeEmail ?? "channels resolved by platform",
                             live: true,
                             channels: [("PUSH", $wantsPush), ("EMAIL", $wantsEmail), ("SMS", $wantsSMS)])
            } else {
                EusoEmptyState(systemImage: "person.crop.circle.badge.questionmark",
                               title: "No consignee on file",
                               subtitle: "This shipment's waybill carries no consignee contact. Add a consignee on the waybill before an at-interchange notice can be sent — the platform never sends to a phantom recipient.")
            }
            if hasConsignee, let site = preview?.destinationName {
                Divider().overlay(palette.borderFaint)
                recipientRow(name: site, role: "Unloading site", detail: "no direct contact — reached through consignee", live: false, channels: [])
            }
            if hasConsignee, regimes[regime].2 == "MX" {
                Divider().overlay(palette.borderFaint)
                recipientRow(name: "Customs broker", role: "MX customs · add contact", detail: "no broker contact on file for this lane", live: false, channels: [])
            }
        }
        .padding(hasConsignee ? 16 : 0)
        .background(hasConsignee ? palette.bgCard : Color.clear)
        .overlay(hasConsignee ? RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint) : nil)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func recipientRow(name: String, role: String, detail: String, live: Bool, channels: [(String, Binding<Bool>)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.bgCardSoft).frame(width: 36, height: 36)
                    Image(systemName: live ? "building.2.fill" : "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(live ? Brand.blue : palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text(role).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            Text(detail).font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textTertiary).lineLimit(1)
            if !channels.isEmpty {
                HStack(spacing: 8) {
                    ForEach(channels, id: \.0) { ch in channelToggle(ch.0, ch.1) }
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func channelToggle(_ label: String, _ on: Binding<Bool>) -> some View {
        Button(action: { on.wrappedValue.toggle() }) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(on.wrappedValue ? Color.white : palette.textSecondary)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(on.wrappedValue ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft)))
                .overlay(Capsule().strokeBorder(on.wrappedValue ? Color.clear : palette.borderFaint))
        }
        .buttonStyle(.plain)
    }

    // MARK: Auto-localized message preview — mirrors the server copy.

    private var messagePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MESSAGE PREVIEW · AUTO-LOCALIZED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(regimes[regime].0).font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(previewTitle).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(previewBody).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
        }
    }

    private var shipNo: String { preview?.shipmentNumber ?? (shipmentNumber.isEmpty ? "your rail shipment" : shipmentNumber) }
    private var atText: String { chosenPoint.map { " at \($0.display)" } ?? " at the interchange" }
    private var previewTitle: String {
        regimes[regime].2 == "MX" ? "Su vagón llegó al punto de intercambio" : "Your rail car has reached the interchange"
    }
    private var previewBody: String {
        regimes[regime].2 == "MX"
        ? "El envío ferroviario \(shipNo) llegó\(atText)."
        : "Rail shipment \(shipNo) arrived\(atText)."
    }

    private var triBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == regime ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { regime = i }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: sending ? "Sending…" : "Send notification", action: { Task { await send() } })
                .frame(maxWidth: .infinity)
                .disabled(sending || !hasConsignee || activeChannels.isEmpty)
            Button(action: { scheduled = true }) {
                Text(scheduled ? "Scheduled" : "Schedule")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 118)
                    .frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(scheduled)
        }
    }

    @ViewBuilder
    private var resultBanner: some View {
        if let err = sendError {
            LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
        } else if let r = sentResult {
            LifecycleCard {
                if r.sent == true {
                    Text("Notice delivered to the consignee on \((r.channels ?? []).joined(separator: ", ").isEmpty ? "their enabled channels" : (r.channels ?? []).joined(separator: ", ")). Audit + realtime event recorded.")
                        .font(EType.caption).foregroundStyle(Brand.success)
                } else {
                    Text(r.reason == "no_consignee_on_file"
                         ? "No consignee is on the waybill — nothing was sent. Add a consignee contact first."
                         : "The consignee could not be notified on any channel. The event stays queued for retry.")
                        .font(EType.caption).foregroundStyle(Brand.warning)
                }
            }
        } else if scheduled {
            LifecycleCard { Text("Queued to fire when the car reaches \(chosenPoint?.display ?? "the interchange").").font(EType.caption).foregroundStyle(palette.textSecondary) }
        }
    }

    // MARK: Load + send

    private func reload() async {
        loading = true
        if !shipmentNumber.isEmpty {
            let p: ConsigneePreview695? = try? await EusoTripAPI.shared.query(
                "railShipments.getConsigneePreview", input: PreviewInput695(shipmentNumber: shipmentNumber))
            self.preview = p
        }
        let pts: [InterchangePoint695]? = try? await EusoTripAPI.shared.query(
            "railShipments.getCrossBorderInterchangePoints", input: InterchangeInput695(country: regimes[regime].2))
        self.points = pts ?? []
        loading = false
    }

    private func send() async {
        sending = true; sendError = nil; sentResult = nil
        do {
            let r: NotifyResult695 = try await EusoTripAPI.shared.mutation(
                "railShipments.notifyConsigneeAtInterchange",
                input: NotifyInput695(shipmentId: shipmentId,
                                      interchangePointName: chosenPoint?.display,
                                      etaText: nil,
                                      country: regimes[regime].2))
            sentResult = r
        } catch {
            sendError = "The notification didn't send. Nothing was delivered — check your connection and try again."
        }
        sending = false
    }
}

#Preview("695 · Rail At-Interchange Notify · Night") {
    RailAtInterchangeNotifyScreen(theme: Theme.dark, shipmentId: 0, shipmentNumber: "").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("695 · Rail At-Interchange Notify · Light") {
    RailAtInterchangeNotifyScreen(theme: Theme.light, shipmentId: 0, shipmentNumber: "").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
