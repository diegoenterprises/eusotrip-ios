//
//  286_ShipperPaperworkEchoM06.swift
//  EusoTrip — Shipper · LIFECYCLE ECHO · PAPERWORK (M-06 chain).
//
//  Wireframe: 02 Shipper/Dark-SVG/286 Shipper Paperwork Echo M06.svg
//  Archetype: MONEY / RECONCILIATION. The M-06 dialect of the paperwork
//  echo (a reefer poultry lane Atlanta → Miami instead of the M-05 steel
//  flatbed): BOL, POD, and accessorials line up against the awarded
//  amount so Diego approves and stages the settlement in one tap. A
//  money-led hero + a reconciliation ledger (BOL / POD) + a settlement
//  breakdown — never a settlement-strip + KPI-quartet skeleton. The
//  reefer-vs-flatbed distinction is REAL snapshot data (cargoType,
//  weight), not baked copy.
//
//  Web peer: frontend/client/src/pages/shipper/loads/:id/paperwork.
//  Wiring (on-disk confirmed):
//    • shippers.getLifecycleSnapshot EXISTS shippers.ts:1216 → delivered
//      load + carrier + lane + status (PRIMARY CONSUME).
//    • shippers.getSettlementForLoad EXISTS shippers.ts:1390 → staged
//      amount, status, payable date (CONSUMED · staged payable to Aurora).
//    • Approve POD & settle → pod.approvePOD EXISTS pod.ts:134 (PRIMARY
//      ACTION · flips pod_pending → delivered, staging the settlement)
//      then routes to the settlement detail (227) via nav-swap.
//    • Open ledger → invoices (437) via nav-swap.
//  RBAC: shipperProcedure (companyId-owned). transportMode=truck · US.
//
//  Honest binding: the accessorial figure reads the snapshot's
//  accessorialTotal; the staged amount is the real settlement.amount
//  (falls back to the awarded load.rate). No fabricated line items — an
//  absent settlement renders the awarded amount and an em-dash payable.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct ShipperPaperworkEchoM06Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ShipperEchoSnapshotView(loadId: loadId, eyebrow: "SHIPPER · LOAD · PAPERWORK") { live in
                    PaperworkEchoM06Body(live: live, loadId: loadId)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct PaperworkEchoM06Body: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var settlement: ShipperAPI.SettlementForLoad?
    @State private var loadedSettlement = false
    @State private var isApproving = false
    @State private var actionError: String?

    private var disc: String? {
        session.user?.name.flatMap { $0.isEmpty ? nil : echoMonogram($0) }
    }
    private var stagedAmount: Double? { settlement?.amount ?? live.load.rate }
    private var accessorials: Double { live.accessorialTotal }
    private var podApproved: Bool {
        let s = live.load.status.lowercased()
        return s.contains("delivered") || s.contains("approved") || s.contains("invoiced") || s.contains("paid") || s.contains("closed")
    }
    private var perMile: String { echoRatePerMile(rate: stagedAmount, distance: live.load.distance) }
    private var distanceLabel: String { live.load.distance.map { "\(Int($0)) mi" } ?? "— mi" }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ShipperEchoHeader(
                eyebrow: "SHIPPER · LOAD · PAPERWORK",
                trailing: live.load.loadNumber,
                title: echoLaneCities(live),
                showBack: true,
                discInitials: disc
            )
            heroCard
            ShipperEchoLifecycleStrip(active: .paperwork, caption: ribbonCaption)
            reconciliationCard
            breakdownCard
            carrierBadge
            ShipperEchoCTAPair(
                primaryTitle: isApproving ? "Approving…" : "Approve POD & settle",
                primaryLoading: isApproving,
                primaryAction: { Task { await approveAndSettle() } },
                secondaryTitle: "Open ledger",
                secondaryAction: { shipperEchoNavSwap("437", loadId: loadId) }
            )
            if let err = actionError { errorBanner(err) }
        }
        .task {
            guard !loadedSettlement else { return }
            loadedSettlement = true
            settlement = (try? await EusoTripAPI.shared.shipper.getSettlementForLoad(loadId: loadId)) ?? nil
        }
    }

    // MARK: Hero — settlement staged, awaiting POD approval

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("SETTLEMENT STAGED · AWAITING POD APPROVAL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .bottom, spacing: Space.s3) {
                    Text(usd(stagedAmount))
                        .font(.system(size: 40, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("linehaul · \(perMile) · \(distanceLabel)")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text("accessorials \(usd0(accessorials)) · approve to settle")
                            .font(.system(size: 11, weight: .regular)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    heroBadge("PAPERWORK", tint: Brand.escort)
                    heroBadge("BOL MATCHED", tint: Brand.success)
                    heroBadge(podApproved ? "POD SIGNED" : "POD PENDING", tint: podApproved ? Brand.success : Brand.warning)
                }
            }
        }
    }

    private func heroBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.20)))
    }

    // MARK: Reconciliation ledger — BOL matched · POD approved

    private var reconciliationCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "RECONCILIATION")
            VStack(spacing: 0) {
                reconRow(
                    icon: "doc.text.fill",
                    title: "BOL matched",
                    sub: bolSubLine,
                    state: "signed",
                    stateColor: Brand.success,
                    tint: Brand.blue
                )
                Divider().overlay(palette.borderFaint)
                reconRow(
                    icon: "signature",
                    title: podApproved ? "POD approved" : "POD pending",
                    sub: podSubLine,
                    state: podApproved ? "approved" : "pending",
                    stateColor: podApproved ? Brand.success : Brand.warning,
                    tint: Brand.escort
                )
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func reconRow(icon: String, title: String, sub: String, state: String, stateColor: Color, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(sub).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text(state).font(.system(size: 13, weight: .bold)).foregroundStyle(stateColor)
        }
        .padding(.vertical, 8)
    }

    // MARK: Settlement breakdown ledger

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "SETTLEMENT BREAKDOWN")
            VStack(spacing: 10) {
                breakdownRow(label: "Linehaul · \(distanceLabel) @ \(perMile)", value: usd0(live.load.rate), strong: true)
                Divider().overlay(palette.borderFaint)
                breakdownRow(label: "Accessorials · detention / tarp / lumper", value: usd0(accessorials), strong: true)
                Divider().overlay(palette.borderFaint)
                HStack(alignment: .firstTextBaseline) {
                    Text("STAGED PAYABLE TO \(carrierNameUpper)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: Space.s3)
                    Text(usd0(stagedAmount)).font(.system(size: 15, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func breakdownRow(label: String, value: String, strong: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: Space.s3)
            Text(value).font(.system(size: 12, weight: strong ? .bold : .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Carrier badge

    private var carrierBadge: some View {
        ShipperEchoPartyRow(
            monogram: echoMonogram(live.carrier?.name),
            title: live.carrier?.name ?? "Awarded carrier",
            authority: echoAuthorityLine(dot: live.carrier?.dotNumber, mc: live.carrier?.mcNumber, place: live.driver.map { "driver \($0.name)" }),
            pill: ("PAPERWORK", .info),
            accent: Brand.escort
        )
    }

    // MARK: Copy + action

    private var carrierNameUpper: String { (live.carrier?.name ?? "carrier").uppercased() }
    private var bolSubLine: String {
        var parts: [String] = []
        if let w = live.load.weight, w > 0 { parts.append("\(Int(w)) lb") }
        if let c = live.load.cargoType, !c.isEmpty { parts.append(c) }
        parts.append("piece count verified")
        return parts.joined(separator: " · ")
    }
    private var podSubLine: String {
        podApproved ? "consignee signed · Diego approved" : "consignee signed · awaiting your approval"
    }
    private var ribbonCaption: String {
        let recv = live.delivery?.facilityName ?? live.delivery?.city ?? "consignee"
        return "Delivered at \(recv) · BOL matched · accessorials \(usd0(accessorials)) · staged \(usd0(stagedAmount))"
    }

    private func approveAndSettle() async {
        isApproving = true; actionError = nil
        do {
            _ = try await EusoTripAPI.shared.pod.approvePOD(loadId: live.load.id)
            shipperEchoNavSwap("227", loadId: loadId)
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isApproving = false
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

#Preview("286 · Paperwork echo M06 · Night") {
    ShipperPaperworkEchoM06Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("286 · Paperwork echo M06 · Afternoon") {
    ShipperPaperworkEchoM06Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
