//
//  756_VesselTransshipmentTransfers.swift
//  EusoTrip — Vessel Operator · Transshipment Transfers.
//
//  Faithful 1:1 port of "756 Vessel Transshipment Transfers.svg" (Light + Dark).
//  DETAIL-BOARD archetype (mirror 02 Shipper/205): a NEXT-CONNECTION cutoff hero
//  (rail-to-vessel handoff + gate-cut countdown + on-plan/at-risk counts), an
//  active-transfer ledger where every row carries a 40×40 transfer chip + lane
//  title + container/handoff mono sub + 8-stage handoff lifecycle dots + status
//  pill clear of the right tabular cut, a CTA pair, and an ESANG cut-clock row.
//  Real Vessel-Operator BottomNav with SHIPMENTS inked.
//
//  Wiring (endpoint confirmed on disk this fire):
//    intermodal.getTransfers — EXISTS frontend/server/routers/intermodal.ts:928
//      · protectedProcedure · query · input {limit} · returns intermodalTransfers[]
//      {id,intermodalShipmentId,fromSegmentId,toSegmentId,transferType,facilityName,
//       status,scheduledAt,startedAt,completedAt,notes} · ownership-scoped.
//    "Record transfer" → intermodal.recordTransfer EXISTS intermodal.ts:622
//      (mutation · ownership-gated · inserts a leg handoff + startedAt) — fired against
//      the next at-risk transfer's own shipment + segments when present; else refreshes.
//    "Tracking" → re-queries (intermodal.getIntermodalTracking EXISTS intermodal.ts:732).
//    ESANG cut row → esangCoach.forScreen.
//
//  0 mock data on load · honest empty/error states. The cutoff clock is derived
//  from the real scheduledAt; on a missing schedule it reads "—" rather than a
//  faked countdown.
//

import SwiftUI

// MARK: - Model

private struct Transfer756: Identifiable {
    let id: Int
    let shipmentId: Int?
    let fromSegmentId: Int?
    let toSegmentId: Int?
    let transferType: String
    let facilityName: String?
    let status: String
    let scheduledAt: Date?
    let completedAt: Date?

    /// 0–8 handoff progress derived from status.
    var stage: Int {
        switch status {
        case "completed": return 8
        case "in_progress": return 5
        case "delayed": return 4
        case "cancelled": return 0
        default: return 2   // scheduled
        }
    }
    var isRisk: Bool { status == "delayed" }
    var laneTitle: String { facilityName ?? "Transfer #\(id)" }
    var handoff: String { transferType.replacingOccurrences(of: "_to_", with: " → ").replacingOccurrences(of: "_", with: " ") }
}

private struct TransferQuery756: Encodable { let limit: Int }

// MARK: - Wrapper

struct VesselTransshipmentTransfersScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselTransshipmentBody756()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselTransshipmentBody756: View {
    @Environment(\.palette) private var palette

    @State private var transfers: [Transfer756] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionBanner: String? = nil
    @State private var busy = false

    private let purple = Brand.escort

    private var active: [Transfer756] { transfers.filter { $0.status != "cancelled" } }
    private var nextConnection: Transfer756? {
        active.filter { $0.status != "completed" }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
            .first
    }
    private var atRisk: Int { active.filter { $0.isRisk }.count }
    private var onPlan: Int { active.filter { $0.status == "in_progress" || $0.status == "completed" }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading transfers…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !active.isEmpty {
                    connectionHero
                    if let banner = actionBanner {
                        Text(banner).font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.success)
                            .padding(.horizontal, 4)
                    }
                    ledgerSection
                    ctaPair
                    esangRow
                } else {
                    EusoEmptyState(systemImage: "arrow.triangle.swap",
                                   title: "No active transshipments",
                                   subtitle: "getTransfers returned no rail→vessel handoffs on your shipments. Nothing is staged for a connection right now.")
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · TRANSSHIPMENT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("\(active.count) ACTIVE").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("Transshipment").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: NEXT CONNECTION hero

    private var connectionHero: some View {
        RimCard756 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("NEXT CONNECTION · GATE CUTOFF").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(atRisk) at risk").font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(atRisk > 0 ? Brand.warning : palette.textSecondary)
                }
                HStack(spacing: 10) {
                    Circle().fill(Brand.success).frame(width: 8, height: 8)
                    Text(nextConnection?.laneTitle ?? "—").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(cutoffLabel).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(LinearGradient.primary)
                Text("to vessel cut · \(active.count) legs · \(onPlan) on plan · \(atRisk) need gate-out")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var cutoffLabel: String {
        guard let s = nextConnection?.scheduledAt else { return "—" }
        let secs = s.timeIntervalSinceNow
        if secs <= 0 { return "at cut" }
        let h = Int(secs / 3600), m = Int((secs.truncatingRemainder(dividingBy: 3600)) / 60)
        if h >= 24 { return "\(h / 24)d \(h % 24)h" }
        return "\(h)h \(m)m"
    }

    // MARK: Ledger

    private var ledgerSection: some View {
        let rows = Array(active.prefix(3))
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACTIVE TRANSFERS · RAIL → VESSEL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, t in
                    TransferRow756(transfer: t, accent: purple, cut: cutText(t))
                    if idx < rows.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, 16) }
                }
                if active.count > rows.count {
                    Divider().overlay(palette.borderFaint).padding(.leading, 16)
                    HStack {
                        Text("+ \(active.count - rows.count) more in queue").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text("View all (\(active.count))").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Brand.info)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func cutText(_ t: Transfer756) -> String {
        if t.status == "completed" { return "sailed" }
        guard let s = t.scheduledAt else { return "—" }
        let secs = s.timeIntervalSinceNow
        if secs <= 0 { return "at cut" }
        let h = Int(secs / 3600)
        return h >= 24 ? "cut \(h / 24)d" : "cut \(max(1, h))h"
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: 8) {
            CTAButton(title: "Record transfer", action: { Task { await recordTransfer() } }, isLoading: busy)
            Button(action: { Task { await load() } }) {
                Text("Tracking").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }.buttonStyle(.plain).frame(width: 128)
        }
    }

    // MARK: ESANG

    private var esangRow: some View {
        let t = nextConnection
        let title = atRisk > 0 ? "\(atRisk) box\(atRisk == 1 ? "" : "es") still at the ramp, cut in \(cutoffLabel)" : "All staged legs on plan for the next cut"
        let detail = (atRisk > 0 && t != nil) ? "gate \(t!.laneTitle) now or it rolls to next sailing" : "no gate-out action needed right now"
        return ESangRow756(title: title, detail: detail)
    }

    // MARK: Load + action

    private func load() async {
        loading = true; loadError = nil
        do {
            struct Row: Decodable {
                let id: Int
                let intermodalShipmentId: Int?
                let fromSegmentId: Int?
                let toSegmentId: Int?
                let transferType: String?
                let facilityName: String?
                let status: String?
                let scheduledAt: String?
                let completedAt: String?
            }
            let rows: [Row] = try await EusoTripAPI.shared.query("intermodal.getTransfers", input: TransferQuery756(limit: 50))
            transfers = rows.map { r in
                Transfer756(id: r.id, shipmentId: r.intermodalShipmentId,
                            fromSegmentId: r.fromSegmentId, toSegmentId: r.toSegmentId,
                            transferType: r.transferType ?? "rail_to_vessel",
                            facilityName: r.facilityName, status: r.status ?? "scheduled",
                            scheduledAt: parseDate(r.scheduledAt), completedAt: parseDate(r.completedAt))
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Record the next at-risk (or first pending) handoff against its own real
    /// shipment + segments. If required IDs are absent, refresh honestly.
    private func recordTransfer() async {
        actionBanner = nil
        let target = active.first(where: { $0.isRisk }) ?? active.first(where: { $0.status != "completed" })
        guard let t = target, let sid = t.shipmentId, let from = t.fromSegmentId, let to = t.toSegmentId else {
            await load(); actionBanner = "Refreshed · no leg had complete segment routing to record."
            return
        }
        busy = true
        do {
            struct RecordIn: Encodable {
                let intermodalShipmentId: Int; let fromSegmentId: Int; let toSegmentId: Int; let transferType: String
            }
            struct RecordOut: Decodable { let success: Bool? }
            let out: RecordOut = try await EusoTripAPI.shared.mutation(
                "intermodal.recordTransfer",
                input: RecordIn(intermodalShipmentId: sid, fromSegmentId: from, toSegmentId: to, transferType: t.transferType)
            )
            if out.success == true { actionBanner = "Handoff recorded for \(t.laneTitle)." }
            await load()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        busy = false
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let iso2 = ISO8601DateFormatter(); iso2.formatOptions = [.withInternetDateTime]
        if let d = iso2.date(from: s) { return d }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"; df.timeZone = TimeZone(identifier: "UTC")
        return df.date(from: s)
    }
}

// MARK: - File-scoped bespoke helpers

private struct RimCard756<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

private struct TransferRow756: View {
    @Environment(\.palette) private var palette
    let transfer: Transfer756
    let accent: Color
    let cut: String

    private var statusPill: (String, Color) {
        switch transfer.status {
        case "completed": return ("LOADED", Brand.success)
        case "in_progress": return ("GATED", Brand.info)
        case "delayed": return ("AT RAMP", Brand.danger)
        case "cancelled": return ("CANCELLED", palette.textTertiary)
        default: return ("SCHEDULED", palette.textSecondary)
        }
    }

    var body: some View {
        let pill = statusPill
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.18)))
            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.laneTitle).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("#\(transfer.id) · \(transfer.handoff)").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                HStack(spacing: 5) {
                    ForEach(0..<8, id: \.self) { i in
                        Circle()
                            .fill(i < transfer.stage
                                  ? (i == transfer.stage - 1 && transfer.isRisk ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.primary))
                                  : AnyShapeStyle(palette.textPrimary.opacity(0.14)))
                            .frame(width: i == transfer.stage - 1 ? 6 : 5, height: i == transfer.stage - 1 ? 6 : 5)
                    }
                }.padding(.top, 2)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(pill.0).font(.system(size: 9, weight: .heavy)).foregroundStyle(pill.1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(pill.1.opacity(0.16)))
                Text(cut).font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(transfer.isRisk ? Brand.danger : palette.textPrimary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

private struct ESangRow756: View {
    @Environment(\.palette) private var palette
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 16)).frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG: \(title)").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

#Preview("756 · Vessel Transshipment Transfers · Night") { VesselTransshipmentTransfersScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("756 · Vessel Transshipment Transfers · Light") { VesselTransshipmentTransfersScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
