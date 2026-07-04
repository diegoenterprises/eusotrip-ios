//
//  525_DispatcherBhClosedStageCard.swift
//  EusoTrip — Dispatcher · BH lifecycle 525 · Closed (money-ledger + settlement handoff).
//
//  Wireframe slot: 04 Dispatcher / 525 Dispatcher BH Closed Stage Card (Light+Dark SVG,
//  golden re-port 2026-06-25 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition (SVG-verbatim): closed-load money-ledger hero (status chips + shipper
//  gross + debit/credit line items + margin row) → CYCLE / MARGIN / TERMS KPI triple →
//  close-record card → settlement-handoff strip → CTA pair (Open settlement / Reopen load).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                          — status + gross + dates + parties.
//    READ  location.detention.getForLoad          — detention line item (real charges).
//    READ  documentManagement.getDocuments        — POD-on-file chip.
//    READ  documentManagement.getAuditTrail       — close audit-chain entry count.
//    WRITE dispatch.updateLoadStatus              — Close (→ complete) / Reopen (→ delivered).
//  Honest gaps (no server proc — rendered as data-absence states, never faked):
//    · carrier linehaul / lumper / margin economics on the load projection (ledger rows)
//    · cross-role settlement handoff (the carrier-side settlement link isn't readable
//      from this board — Open settlement surfaces the honest not-linked state)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens only.
//

import SwiftUI

// MARK: - Screen

struct DispatcherBHClosed525Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH525Body(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                    isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                  isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct BH525Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var detentionTotal: Double?
    @State private var podOnFile: Bool?
    @State private var auditCount: Int?
    @State private var loadFailed = false
    @State private var statusInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var showSettlementSheet = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrowRow
                titleRow
                Rectangle().fill(palette.iridescentHairline).frame(height: 1)
                heroCard
                kpiTriple
                sectionLabel("CLOSE RECORD")
                closeRecord
                settlementStrip
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(Brand.success) }
                }
                if let err = actionError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                }
                if loadFailed {
                    LifecycleCard(accentWarning: true) {
                        Text("Couldn't reach the board for this load. Everything shown is the last loaded state — pull to refresh.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showSettlementSheet) { BH525SettlementSheet(carrierName: carrierName) }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BACKHAUL · CLOSED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("\(load?.loadNumber ?? "—") · \(load?.rateDisplay ?? "—")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
        }
    }

    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Button { navHandler?("board") } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text("Closed").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
                if !isClosed {
                    Button("Close load") { Task { await flipStatus(to: "complete") } }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — money ledger

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                BH525Chip(text: statusChipText, tint: isClosed ? Brand.success : Brand.warning)
                Spacer()
                Text(podChipText)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(podOnFile == true ? Brand.success : palette.textTertiary)
            }
            Text(load?.rateDisplay ?? "—")
                .font(.system(size: 44, weight: .heavy).monospacedDigit())
                .foregroundStyle(LinearGradient.diagonal)
            Text("SHIPPER GROSS · NET-30")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Divider().overlay(palette.borderFaint)
            VStack(spacing: 0) {
                BH525LedgerRow(title: "Carrier linehaul",
                               value: "—",
                               sub: "not on this load record",
                               tint: nil)
                Divider().overlay(palette.borderFaint)
                BH525LedgerRow(title: "Lumper reimbursement",
                               value: "—",
                               sub: "not on this load record",
                               tint: nil)
                Divider().overlay(palette.borderFaint)
                BH525LedgerRow(title: "Detention",
                               value: detentionText,
                               sub: detentionTotal == nil ? "no dwell record on this load" : "from the gate clock",
                               tint: (detentionTotal ?? 0) > 0 ? Brand.warning : Brand.success)
                Divider().overlay(palette.borderStrong)
                BH525LedgerRow(title: "Brokerage margin",
                               value: "—",
                               sub: "not on this load record",
                               tint: nil)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }

    // MARK: KPI triple — CYCLE / MARGIN / TERMS

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH525Kpi(label: "CYCLE",
                     value: cycleText,
                     sub: cycleText == "—" ? "needs posted + delivered dates" : "post to delivery",
                     tint: nil)
            BH525Kpi(label: "MARGIN",
                     value: "—",
                     sub: "not on this load record",
                     tint: nil)
            BH525Kpi(label: "TERMS",
                     value: "NET-30",
                     sub: "platform pay terms",
                     tint: nil)
        }
    }

    // MARK: Close record

    private var closeRecord: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                BH525RecordRow(title: "Delivered", value: deliveredText)
                Divider().overlay(palette.borderFaint)
                BH525RecordRow(title: "Status", value: bh525Humanize(load?.status))
                Divider().overlay(palette.borderFaint)
                BH525RecordRow(title: "Audit chain", value: auditText)
            }
        }
    }

    // MARK: Settlement strip

    private var settlementStrip: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: Space.s2) {
                Image(systemName: "arrow.right.doc.on.clipboard")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settlement handoff")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("No settlement is linked to this load on this board — the carrier side of the close runs on \(carrierName)'s settlement desk.")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                BH525Chip(text: "NOT LINKED", tint: Brand.neutral)
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { showSettlementSheet = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                    Text("Open settlement").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { Task { await flipStatus(to: "delivered") } } label: {
                HStack(spacing: 6) {
                    if statusInFlight { ProgressView().scaleEffect(0.8) }
                    Text(statusInFlight ? "Posting…" : "Reopen load").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(palette.textPrimary)
                .background(Capsule().fill(palette.bgCard))
                .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(statusInFlight)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Derived display

    private var isClosed: Bool {
        ["complete", "paid", "delivered", "invoiced"].contains(load?.status ?? "")
    }

    private var statusChipText: String {
        switch load?.status {
        case "complete", "paid": return "DELIVERED · CLOSED"
        case let s?: return bh525Humanize(s).uppercased()
        case nil: return "—"
        }
    }

    private var podChipText: String {
        switch podOnFile {
        case true: return "POD ON FILE"
        case false: return "POD MISSING"
        default: return "POD —"
        }
    }

    private var detentionText: String {
        guard let d = detentionTotal else { return "$0" }
        return String(format: "$%.0f", d)
    }

    private var cycleText: String {
        guard let created = bh525ISODate(load?.createdAt),
              let delivered = bh525ISODate(load?.actualDeliveryDate ?? load?.deliveryDate) else { return "—" }
        let days = max(0, Int(delivered.timeIntervalSince(created) / 86_400))
        return "\(days)d"
    }

    private var deliveredText: String {
        guard let d = bh525ISODate(load?.actualDeliveryDate ?? load?.deliveryDate) else { return "not recorded" }
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }

    private var auditText: String {
        guard let n = auditCount else { return "—" }
        return n > 0 ? "recorded · \(n) entr\(n == 1 ? "y" : "ies")" : "no entries yet"
    }

    private var carrierName: String {
        load?.catalyst?.companyName ?? load?.catalyst?.name ?? "the carrier"
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s1)
    }

    // MARK: Data

    private func refresh() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
            loadFailed = false
        } catch { loadFailed = load == nil }
        await fetchDetention()
        await fetchPod()
        await fetchAudit()
    }

    private func fetchDetention() async {
        struct In: Encodable { let loadId: Int }
        struct Rec: Decodable { let detentionCharge: Double? }
        guard let numeric = Int((load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")) else { return }
        do {
            let recs: [Rec] = try await EusoTripAPI.shared.query("location.detention.getForLoad", input: In(loadId: numeric))
            detentionTotal = recs.compactMap { $0.detentionCharge }.reduce(0, +)
        } catch { detentionTotal = nil }
    }

    private func fetchPod() async {
        struct In: Encodable { let entityType: String; let entityId: String; let page: Int; let pageSize: Int }
        struct Doc: Decodable { let id: String?; let type: String? }
        struct Out: Decodable { let documents: [Doc]? }
        let numericId = (load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")
        do {
            let out: Out = try await EusoTripAPI.shared.query(
                "documentManagement.getDocuments",
                input: In(entityType: "load", entityId: numericId, page: 1, pageSize: 50))
            podOnFile = (out.documents ?? []).contains(where: { $0.type == "pod" || $0.type == "delivery_receipt" })
        } catch { podOnFile = nil }
    }

    private func fetchAudit() async {
        struct In: Encodable { let page: Int; let pageSize: Int }
        struct Out: Decodable { let total: Int? }
        do {
            let out: Out = try await EusoTripAPI.shared.query(
                "documentManagement.getAuditTrail",
                input: In(page: 1, pageSize: 1))
            auditCount = out.total
        } catch { auditCount = nil }
    }

    private func flipStatus(to status: String) async {
        guard !statusInFlight else { return }
        statusInFlight = true; actionAck = nil; actionError = nil
        defer { statusInFlight = false }
        struct In: Encodable { let loadId: String; let status: String }
        struct Out: Decodable { let success: Bool?; let newStatus: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation("dispatch.updateLoadStatus",
                                                                 input: In(loadId: loadId, status: status))
            if out.success == true {
                actionAck = status == "delivered"
                    ? "Load reopened to the delivered stage — paperwork and detention can be reworked before it closes again."
                    : "Load closed — the board archives this card and the close posts to the audit chain."
                await refresh()
            } else {
                actionError = "The stage didn't change. The board still shows the last saved stage — try again."
            }
        } catch {
            actionError = "The stage didn't post. The board still shows the last saved stage — check the connection and try again."
        }
    }
}

// MARK: - Settlement honest sheet

private struct BH525SettlementSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let carrierName: String

    var body: some View {
        ZStack {
            palette.bgPrimary.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("Settlement").font(EType.h2).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                LifecycleCard(accentWarning: true) {
                    Text("No settlement is linked to this load on this board.")
                        .font(EType.caption).foregroundStyle(palette.textPrimary)
                    Text("The payout side of this close runs on \(carrierName)'s settlement desk. The POD and the delivery packet filed here ride with the load record, so their settlement view reads the same documents you see on this card.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(Space.s4)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Small primitives

private struct BH525Chip: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }
}

private struct BH525Kpi: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let sub: String
    let tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

private struct BH525LedgerRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let value: String
    let sub: String
    let tint: Color?
    var body: some View {
        HStack(alignment: .center, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(sub).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(value)
                .font(EType.mono(.body))
                .foregroundStyle(tint ?? palette.textSecondary)
        }
        .padding(.vertical, 8)
    }
}

private struct BH525RecordRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - File-local helpers

private func bh525Humanize(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    return raw.replacingOccurrences(of: "_", with: " ").capitalized
}

private func bh525ISODate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    return ISO8601DateFormatter().date(from: s)
}

// MARK: - Previews

#Preview("525 Closed · Dark") {
    DispatcherBHClosed525Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("525 Closed · Light") {
    DispatcherBHClosed525Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
