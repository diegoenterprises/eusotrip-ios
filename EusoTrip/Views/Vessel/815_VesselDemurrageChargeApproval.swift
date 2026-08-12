//
//  815_VesselDemurrageChargeApproval.swift
//  EusoTrip — Vessel Operator · Demurrage Charge Approval.
//
//  Faithful 1:1 port of "815 Vessel Demurrage Charge Approval.svg" (Light + Dark), RECONSTRUCTED to
//  flagship APPROVAL-QUEUE grammar (mirror 02 Shipper/205 + 06 Vessel/758): 28pt detail title + back
//  chevron + caption + overflow, EXPOSURE gradient-rim hero (pending-approval figure + ready-to-invoice
//  count + selection line), a multi-select queue where every row carries a checkbox AND a 40x40
//  charge-type chip (demurrage clock / detention box / chassis wheel) + charge title + container mono
//  sub + per-card Approve/Dispute chips + right tabular amount + aged, batch summary card, batch CTA
//  pair (Approve selected / Hold), ESang dispute-nudge row.
//
//  IN-APP CONVENTION: top-level `VesselDemurrageChargeApprovalScreen(theme:)` wraps the bespoke body in
//  the app `Shell(theme:) { Body } nav: { BottomNav(...) }` so the REAL Vessel Operator BottomNav
//  navigates (SVG owns the LOOK, iOS owns the FUNCTION). Nav anchored to the vessel-operator slots
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), COMPLIANCE inked — same Shell+nav shape as the cited
//  siblings 664 Vessel Terminal Appointment + 680 Vessel Intermodal Segment Board.
//
//  Data / wiring (endpoint confirmed on the platform this fire):
//    demurrageCharges.generateCharges (EXISTS frontend/server/routers/demurrageCharges.ts:27 · query ·
//      optional input · returns { charges:[DemurrageCharge], batch }) backs the queue + exposure figure.
//      DemurrageCharge carries chargeType/status/terminalName/loadReference/finalCharge
//      (DemurrageChargeEngine.ts:18). Wired through the generic tRPC client with EmptyInput().
//    row Approve -> demurrageCharges.approveCharge (EXISTS demurrageCharges.ts).
//    row Dispute -> demurrageCharges.disputeCharge (EXISTS demurrageCharges.ts).
//    batch -> demurrageCharges.batchApprove (EXISTS demurrageCharges.ts) persists audit-backed approvals.
//    ZERO-FALLBACK: state is em-dash/zero/empty-initialized and UNCONDITIONALLY overwritten from the
//    live generateCharges response — an empty queue renders the honest empty state, never a seeded
//    composition. Write verbs hit the canonical demurrageCharges persistence path.
//

import SwiftUI

private enum ChargeKind815 { case demurrage, detention, chassis
    var glyph: String { switch self { case .demurrage: "clock"; case .detention: "shippingbox"; case .chassis: "truck.box" } }
    var tint: Color { switch self { case .demurrage: Color(red: 0.70, green: 0.45, blue: 0.0); case .detention: Brand.info; case .chassis: Color(red: 0.38, green: 0.49, blue: 0.55) } }
}

private struct PendingCharge815: Identifiable {
    let id: String
    let kind: ChargeKind815
    let title: String
    let sub: String
    let amount: String
    let amountValue: Double    // real finalCharge — totals are summed from this, never re-parsed strings
    let aged: String
    let status: String
    var selected: Bool
}

struct VesselDemurrageChargeApprovalScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselDemurrageChargeApprovalBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselDemurrageChargeApprovalBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    // ZERO-FALLBACK: em-dash/zero/empty init — every figure is unconditionally
    // overwritten from the live generateCharges response; an empty queue renders
    // the honest empty state, never the seeded MSCU/TCLU/CMAU composition.
    @State private var pending  = "—"
    @State private var readyN   = 0
    @State private var totalN   = 0
    @State private var terminalChip: String? = nil   // real terminalName when the queue carries one

    @State private var charges: [PendingCharge815] = []
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var inFlightChargeId: String? = nil
    @State private var batchInFlight = false

    private var selectedCount: Int { charges.filter { $0.selected }.count }
    private var selectedTotal: Int {
        Int(charges.filter { $0.selected }.reduce(0.0) { $0 + $1.amountValue }.rounded())
    }
    /// Live-derived ESang nudge (smallest pending charge) — nil hides the row.
    private var esangNudge: (title: String, subtitle: String)? {
        guard let smallest = charges.min(by: { $0.amountValue < $1.amountValue }), charges.count > 1 else { return nil }
        return (title: "ESang: the \(smallest.amount) \(smallest.title.lowercased()) is the smallest in the batch",
                subtitle: "\(smallest.sub) · review before approving")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if charges.isEmpty {
                    EusoEmptyState(systemImage: "checkmark.circle",
                                   title: "No charges pending approval",
                                   subtitle: "Stopped financial timers with billable minutes generate the approval queue — nothing is waiting on you.")
                } else {
                    actionBanners
                    exposureHero
                    HStack {
                        Text("PENDING QUEUE · \(totalN)").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("\(selectedCount) selected").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                    ForEach(Array(charges.enumerated()), id: \.element.id) { idx, c in chargeRow(idx, c) }
                    batchSummary
                    HStack(spacing: 8) {
                        CTAButton(title: "Approve selected · $\(selectedTotal)", action: { Task { await batchApprove() } }, leadingIcon: "checkmark.circle")
                        SecondaryButton815(title: "Hold") { Task { await load() } }
                    }
                    if let nudge = esangNudge {
                        ESangRow815(title: nudge.title, subtitle: nudge.subtitle)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private var actionBanners: some View {
        if let actionMessage {
            LifecycleCard {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.success)
                    Text(actionMessage).font(EType.caption).foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
        if let actionError {
            LifecycleCard(accentDanger: true) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
                    Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · CHARGE APPROVAL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(terminalChip.map { "QUEUE · \($0)" } ?? "QUEUE").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Approve charges").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var exposureHero: some View {
        RimCard815 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("PENDING APPROVAL").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("READY TO INVOICE").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(pending).font(.system(size: 32, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(readyN)").font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        Text("of \(totalN) charges").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    }
                }
                Divider().overlay(palette.borderFaint)
                Text("\(selectedCount) selected · $\(selectedTotal) ready · batch posts to settlement")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func chargeRow(_ idx: Int, _ c: PendingCharge815) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Button { charges[idx].selected.toggle() } label: {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(c.selected ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(c.selected ? Color.clear : palette.textTertiary, lineWidth: 2))
                            .frame(width: 24, height: 24)
                            .overlay(c.selected ? Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white) : nil)
                    }.buttonStyle(.plain)
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(c.kind.tint.opacity(0.12)).frame(width: 40, height: 40)
                        .overlay(Image(systemName: c.kind.glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(c.kind.tint))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(c.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(c.amount).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        Text(c.aged).font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    }
                }
                HStack(spacing: 8) {
                    Button { Task { await approve(idx) } } label: {
                        Text(inFlightChargeId == c.id ? "Approving…" : "Approve")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Brand.success)
                            .frame(width: 96, height: 26)
                            .background(Capsule().fill(Brand.success.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .disabled(inFlightChargeId != nil || batchInFlight)
                    Button { Task { await dispute(idx) } } label: {
                        Text(inFlightChargeId == c.id ? "Filing…" : "Dispute")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 96, height: 26)
                            .overlay(Capsule().stroke(palette.borderFaint, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(inFlightChargeId != nil || batchInFlight)
                    Spacer()
                }
            }
        }
    }

    private var batchSummary: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.info.opacity(0.12)).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.info))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audit-logged on approve · posts to settlement").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("\(selectedCount) of \(charges.count) selected · $\(selectedTotal) ready to invoice").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            struct Charge: Decodable {
                let id: String?
                let chargeType: String?; let terminalName: String?; let loadReference: String?
                let finalCharge: Double?; let status: String?; let generatedAt: String?
            }
            struct Resp: Decodable { let charges: [Charge]? }
            let r: Resp = try await EusoTripAPI.shared.query("demurrageCharges.generateCharges", input: EmptyInput())

            // UNCONDITIONAL overwrite — an empty response empties the queue and
            // the honest empty state renders; nothing seeded survives a load.
            let cs = r.charges ?? []
            totalN = cs.count
            readyN = cs.filter { ["pending", "adjusted", ""].contains(($0.status ?? "").lowercased()) }.count
            let total = cs.reduce(0.0) { $0 + ($1.finalCharge ?? 0) }
            pending = "$\(Int(total))"
            terminalChip = cs.compactMap { $0.terminalName }.first(where: { !$0.isEmpty })
            charges = cs.compactMap { c in
                guard let chargeId = c.id, !chargeId.isEmpty else { return nil }
                let kind: ChargeKind815 = (c.chargeType ?? "").uppercased().contains("DETENTION") ? .detention
                    : ((c.chargeType ?? "").lowercased().contains("chassis") ? .chassis : .demurrage)
                let title: String = {
                    let type = c.chargeType?.capitalized ?? "Charge"
                    if let t = c.terminalName, !t.isEmpty { return "\(type) · \(t)" }
                    return type
                }()
                let status = (c.status ?? "pending").lowercased()
                return PendingCharge815(
                    id: chargeId,
                    kind: kind,
                    title: title,
                    sub: c.loadReference ?? "—",
                    amount: "$\(Int(c.finalCharge ?? 0))",
                    amountValue: c.finalCharge ?? 0,
                    aged: agedLabel(c.generatedAt),
                    status: status,
                    selected: status == "pending" || status == "adjusted" || status.isEmpty)
            }
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    /// "Nd aged" from the REAL generatedAt timestamp — em-dash when absent.
    private func agedLabel(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let d = fractional.date(from: iso) ?? plain.date(from: iso) else { return "—" }
        let days = max(0, Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0)
        return "\(days)d aged"
    }

    private func approve(_ idx: Int) async {
        guard charges.indices.contains(idx) else { return }
        let charge = charges[idx]
        actionMessage = nil; actionError = nil; inFlightChargeId = charge.id
        defer { inFlightChargeId = nil }
        do {
            let out: ChargeDecisionResponse815 = try await EusoTripAPI.shared.mutation(
                "demurrageCharges.approveCharge",
                input: ChargeIdInput815(chargeId: charge.id)
            )
            actionMessage = "Approved \(charge.sub) · event \(out.eventId.map(String.init) ?? "recorded")"
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
    }

    private func dispute(_ idx: Int) async {
        guard charges.indices.contains(idx) else { return }
        let charge = charges[idx]
        actionMessage = nil; actionError = nil; inFlightChargeId = charge.id
        defer { inFlightChargeId = nil }
        do {
            let out: ChargeDecisionResponse815 = try await EusoTripAPI.shared.mutation(
                "demurrageCharges.disputeCharge",
                input: DisputeChargeInput815(chargeId: charge.id, reason: "Disputed from vessel operator charge approval queue.")
            )
            actionMessage = "Dispute filed for \(charge.sub) · event \(out.eventId.map(String.init) ?? "recorded")"
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
    }

    private func batchApprove() async {
        let selected = charges.filter { $0.selected }.map(\.id)
        guard !selected.isEmpty else {
            actionMessage = nil
            actionError = "Select at least one charge before approving a batch."
            return
        }
        actionMessage = nil; actionError = nil; batchInFlight = true
        defer { batchInFlight = false }
        do {
            let out: BatchApproveResponse815 = try await EusoTripAPI.shared.mutation(
                "demurrageCharges.batchApprove",
                input: BatchApproveInput815(chargeIds: selected)
            )
            if let failed = out.failed, !failed.isEmpty {
                actionMessage = "Approved \(out.approved ?? 0); \(failed.count) need review."
            } else {
                actionMessage = "Approved \(out.approved ?? selected.count) demurrage charge\(selected.count == 1 ? "" : "s")."
            }
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
    }
}

// MARK: - File-scoped bespoke chrome (self-contained — preserves the 815 EXPOSURE-hero look)

/// Gradient-rimmed EXPOSURE hero card — app `bgCard` fill + diagonal brand stroke.
private struct RimCard815<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) { content }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

/// ESang dispute-nudge row — soft brand-tinted card with a sparkle glyph.
private struct ESangRow815: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Brand.magenta.opacity(0.12)).frame(width: 36, height: 36)
                .overlay(Image(systemName: "sparkle").font(.system(size: 14, weight: .heavy)).foregroundStyle(LinearGradient.diagonal))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(LinearGradient.esangSoft, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

/// Outlined secondary action — pairs with the primary CTAButton.
private struct SecondaryButton815: View {
    @Environment(\.palette) private var palette
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyInput: Encodable {}
private struct ChargeIdInput815: Encodable { let chargeId: String }
private struct DisputeChargeInput815: Encodable { let chargeId: String; let reason: String }
private struct BatchApproveInput815: Encodable { let chargeIds: [String] }
private struct ChargeDecisionResponse815: Decodable { let success: Bool?; let status: String?; let eventId: Int? }
private struct BatchApproveResponse815: Decodable {
    struct Failure: Decodable { let chargeId: String?; let message: String? }
    let success: Bool?
    let approved: Int?
    let failed: [Failure]?
}

#Preview("815 · Demurrage Charge Approval · Night") { VesselDemurrageChargeApprovalScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("815 · Demurrage Charge Approval · Light") { VesselDemurrageChargeApprovalScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
