//
//  707_RailVerifiedReceiverGate.swift
//  EusoTrip — Rail Engineer · PIH Verified-Receiver Gate (49 CFR 174.5).
//
//  Bespoke port of "05 Rail/Dark-SVG/707 Rail Verified Receiver Gate.svg".
//  ARCHETYPE = CREDENTIAL-VERIFICATION GATE — a blocking release verdict hero
//  (PIH placard + held state) over the four-row 49 CFR 174.5 verified-receiver
//  checklist, ending in a release control that stays LOCKED until every check
//  clears. Deliberately a credential gate, NOT 703's incident filing and NOT
//  704's score gauge.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.notifyConsigneeAtInterchange  EXISTS railShipments.ts:2304 —
//        the REAL pre-arrival notification send. Firing "Notify receiver"
//        delivers the pre-arrival notice and advances the pre-arrival check to
//        cleared once the send lands (audited + WS to the consignee).
//    railShipments.getInterchangeHandoff  EXISTS railShipments.ts:2434 — the
//        real custody board; a car held at interchange confirms the "held"
//        state the gate blocks release against.
//  VERIFIED ABSENT (honest state, never fabricated):
//    A railHazmat.getVerifiedReceiverChecks registry feed (DOT verified-receiver
//    registry / 24-7 emergency-contact confirm / signature-authority) is not on
//    disk. Those three checks read PENDING and the gate stays LOCKED (fail-safe
//    per 49 CFR 174.5 — registry unreachable never auto-releases). releaseCar is
//    a server-re-checked, confirm-gated write that is absent; Release surfaces
//    that honestly and never releases a PIH car from this screen alone.
//  COUNTRY: US 49 CFR 174.5 · CHEMTREC / CA TDG · CANUTEC / MX NOM-002 · SETIQ.
//

import SwiftUI

struct RailVerifiedReceiverGateScreen: View {
    let theme: Theme.Palette
    var railcarNumber: String = "GATX 215704"
    var unNumber: String = "UN1017"
    var material: String = "Chlorine"
    var hazClass: String = "2.3"
    var consigneeName: String = ""
    var shipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            RailVerifiedReceiverGateBody(railcarNumber: railcarNumber, unNumber: unNumber,
                                         material: material, hazClass: hazClass,
                                         consigneeName: consigneeName, shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Check model

private enum CheckState707 { case cleared, pending }

private struct Check707: Identifiable {
    let title: String
    let detail: String
    let registryId: String?
    var state: CheckState707
    var id: String { title }
}

private struct Handoff707: Decodable {
    struct Car: Decodable { let railcarNumber: String?; let status: String? }
    let cars: [Car]?
}
private struct HandoffInput707: Encodable { let shipmentId: Int }

private struct NotifyInput707: Encodable { let shipmentId: Int; let interchangePointName: String?; let country: String? }
private struct NotifyResult707: Decodable { let sent: Bool?; let reason: String? }

// MARK: - Body

private struct RailVerifiedReceiverGateBody: View {
    let railcarNumber: String
    let unNumber: String
    let material: String
    let hazClass: String
    let consigneeName: String
    let shipmentId: Int

    @Environment(\.palette) private var palette
    @State private var preArrivalSent = false
    @State private var heldAtInterchange = false
    @State private var loading = true
    @State private var notifying = false
    @State private var notifyMessage: String? = nil
    @State private var notifyIsError = false
    @State private var regime = 0
    @State private var showReleaseNotice = false

    private let regimes: [(String, String, String)] = [
        ("US · 174.5", "CHEMTREC", "US"),
        ("CA · TDG", "CANUTEC", "CA"),
        ("MX · NOM-002", "SETIQ", "MX"),
    ]
    private var emergencyBody: String { regimes[regime].1 }

    private var checks: [Check707] {
        [
            Check707(title: "Consignee on DOT verified-receiver registry",
                     detail: "no verified-receiver registry feed on file — confirm manually",
                     registryId: nil, state: .pending),
            Check707(title: "Pre-arrival notification delivered",
                     detail: preArrivalSent ? "sent to the consignee · receiver ack pending" : "not yet sent — fire Notify receiver below",
                     registryId: nil, state: preArrivalSent ? .cleared : .pending),
            Check707(title: "24/7 emergency-contact ID confirmed",
                     detail: "\(emergencyBody) reference on file · owner confirm pending",
                     registryId: nil, state: .pending),
            Check707(title: "Signature authority on file",
                     detail: "plant safety officer signature not yet captured",
                     registryId: nil, state: .pending),
        ]
    }
    private var clearedCount: Int { checks.filter { $0.state == .cleared }.count }
    private var gateBlocked: Bool { clearedCount < checks.count }
    private var consigneeDisplay: String { consigneeName.isEmpty ? "consignee on the waybill" : consigneeName }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Verified receiver")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("\(unNumber) \(material) · car \(railcarNumber)")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4).lineLimit(1)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    gateHero
                    checklistHeader
                    checklist
                    lockNote
                    triBand
                    footerActions
                    if let m = notifyMessage {
                        LifecycleCard(accentDanger: notifyIsError) {
                            Text(m).font(EType.caption).foregroundStyle(notifyIsError ? Brand.danger : Brand.success)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Release is a server-gated safety decision", isPresented: $showReleaseNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A PIH car releases only when the server re-runs all four verified-receiver checks and confirms each one. With \(checks.count - clearedCount) check\(checks.count - clearedCount == 1 ? "" : "s") pending, the gate stays locked — no release from this screen.")
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ CARRIER · RAIL · PIH RELEASE GATE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("49 CFR 174.5")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("PIH \(hazClass)", Brand.hazmat)
            chip("\(clearedCount)/\(checks.count) checks", clearedCount == checks.count ? Brand.success : Brand.warning)
            chip(gateBlocked ? "blocked" : "clear", gateBlocked ? Brand.danger : Brand.success)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Gate hero — PIH placard + held verdict.

    private var gateHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RELEASE GATE · CAR HELD AT INTERCHANGE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(Brand.danger)
                Spacer()
                if heldAtInterchange {
                    Text("CUSTODY CONFIRMED").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.danger.opacity(0.14), Brand.hazmat.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
            HStack(alignment: .top, spacing: 14) {
                pihPlacard
                VStack(alignment: .leading, spacing: 4) {
                    Text("Receiver not yet verified").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("\(checks.count - clearedCount) of \(checks.count) verified-receiver checks pending. Car cannot be released until all clear.")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    Text("Consignee · \(consigneeDisplay)").font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(Brand.danger.opacity(0.55), lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // A simple PIH 2.3 poison-gas placard (rotated diamond).
    private var pihPlacard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(45))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.85), lineWidth: 2)
                            .frame(width: 62, height: 62)
                            .rotationEffect(.degrees(45)))
            VStack(spacing: 1) {
                Image(systemName: "aqi.medium").font(.system(size: 15, weight: .black)).foregroundStyle(.black)
                Text("POISON").font(.system(size: 7, weight: .black)).foregroundStyle(.black)
                Text("GAS").font(.system(size: 7, weight: .black)).foregroundStyle(.black)
                Text(hazClass).font(.system(size: 9, weight: .black)).foregroundStyle(.black)
            }
        }
        .frame(width: 90, height: 90)
    }

    private var checklistHeader: some View {
        HStack {
            Text("VERIFIED-RECEIVER CHECKS · 49 CFR 174.5")
                .font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            Spacer()
        }
    }

    private var checklist: some View {
        VStack(spacing: 0) {
            ForEach(Array(checks.enumerated()), id: \.element.id) { i, c in
                checkRow(c)
                if i < checks.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func checkRow(_ c: Check707) -> some View {
        let cleared = c.state == .cleared
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill((cleared ? Brand.success : Brand.warning).opacity(0.14)).frame(width: 26, height: 26)
                Image(systemName: cleared ? "checkmark" : "exclamationmark")
                    .font(.system(size: 11, weight: .black)).foregroundStyle(cleared ? Brand.success : Brand.warning)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text((c.registryId.map { "\($0) · " } ?? "") + c.detail)
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(cleared ? Brand.success : palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(cleared ? "CLEARED" : "PENDING")
                .font(.system(size: 8, weight: .heavy)).foregroundStyle(cleared ? Brand.success : Brand.warning)
        }
        .padding(.vertical, 12)
    }

    private var lockNote: some View {
        HStack(spacing: 8) {
            Image(systemName: gateBlocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(gateBlocked ? Brand.danger : Brand.success)
            Text("Server re-runs all four on release · confirm required.")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
            CTAButton(title: notifying ? "Notifying…" : "Notify receiver", action: { Task { await notifyReceiver() } })
                .frame(maxWidth: .infinity)
                .disabled(notifying || shipmentId == 0)
            Button(action: { showReleaseNotice = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold))
                    Text("Release")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(gateBlocked ? palette.textTertiary : palette.textPrimary)
                .frame(width: 130)
                .frame(minHeight: 48, maxHeight: 48)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func reload() async {
        loading = true
        if shipmentId != 0 {
            let h: Handoff707? = try? await EusoTripAPI.shared.query(
                "railShipments.getInterchangeHandoff", input: HandoffInput707(shipmentId: shipmentId))
            let carRows = h?.cars ?? []
            heldAtInterchange = carRows.contains { ($0.railcarNumber ?? "") == railcarNumber } || !carRows.isEmpty
        }
        loading = false
    }

    private func notifyReceiver() async {
        guard shipmentId != 0 else { return }
        notifying = true; notifyMessage = nil
        do {
            let r: NotifyResult707 = try await EusoTripAPI.shared.mutation(
                "railShipments.notifyConsigneeAtInterchange",
                input: NotifyInput707(shipmentId: shipmentId, interchangePointName: nil, country: regimes[regime].2))
            if r.sent == true {
                preArrivalSent = true
                notifyIsError = false
                notifyMessage = "Pre-arrival notice delivered — one of four checks cleared. The registry, emergency-contact and signature checks still hold the gate."
            } else {
                notifyIsError = true
                notifyMessage = r.reason == "no_consignee_on_file"
                    ? "No consignee on the waybill — the pre-arrival notice can't be sent. Add a consignee contact first."
                    : "The receiver couldn't be reached on any channel. The pre-arrival check stays pending."
            }
        } catch {
            notifyIsError = true
            notifyMessage = "The notification didn't send. The gate is unchanged — check your connection and try again."
        }
        notifying = false
    }
}

#Preview("707 · Rail Verified Receiver Gate · Night") {
    RailVerifiedReceiverGateScreen(theme: Theme.dark, consigneeName: "Lakeside Water Treatment, KC")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("707 · Rail Verified Receiver Gate · Light") {
    RailVerifiedReceiverGateScreen(theme: Theme.light, consigneeName: "Lakeside Water Treatment, KC")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
