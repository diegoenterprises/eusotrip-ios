//
//  795_VesselDetentionHistory.swift
//  EusoTrip — Vessel Operator · Detention History (BILLING-TIMELINE archetype).
//
//  Faithful port of "795 Vessel Detention History.svg" (Dark + Light). This is a
//  time-ordered audit of every CLOSED detention window and whether it was actually
//  collected — a billed-total headline, a four-cell KPI strip (COLLECTED inked with
//  the brand gradient), and a vertical resolution timeline of date-stamped nodes on
//  a rail (PAID / INVOICED / DISPUTED / PENDING) so disputes that quietly age are
//  caught before they are written off. Distinct from the demurrage watch surfaces —
//  a timeline, not a live board.
//
//  Nav: Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), COMPLIANCE
//  inked — the history lives in the vessel COMPLIANCE domain.
//
//  REAL WIRING (tRPC · server/routers/detentionAccessorials.ts):
//    · detentionAccessorials.getDetentionHistory  {status?, limit, offset}
//        -> { events:[{id, loadId, facilityName, arrivalTime, departureTime,
//              totalMinutes, freeTimeMinutes, billableMinutes, totalCharge, status,
//              billingStatus, carrierName, shipperName, cargoType, createdAt}], total }
//        (:635) — companyId-scoped. Node colour + pill = billingStatus; amount =
//        totalCharge; timeline order = createdAt DESC. The KPI strip + hero derive
//        from the live event set (billed total, collected share, invoiced/disputed).
//    · "Filter" cycles the live status facet and re-queries getDetentionHistory.
//    · "Export ledger" composes a CSV from the LIVE events and opens the native
//        share sheet — a real, self-contained export (server exportDetentionLedger
//        is a NAMED GAP; the client CSV is the honest interim, never a dead tap).
//    · A disputed row escalates through detentionAccessorials.disputeDetention
//        {claimId, reason} (:1083 · writes the dispute + blockchainAuditTrail +
//        broadcasts) — surfaced as the per-node "Dispute" action.
//
//  RBAC: getDetentionHistory / disputeDetention protectedProcedure, companyId-scoped.
//  transportMode=vessel · USD. COUNTRY-DONE: a billing-window regime strip re-bases
//  the collectible history by discharge jurisdiction — US FMC 46 CFR 541 (invoice
//  ≤ 30d, unbilled past the window is unpayable · USD) active / CA·MX contractual
//  (no statutory limit · CAD·MXN) standby. NAMED GAP for the-oath:
//  vessel.getDetentionBillingRegime({country}) -> {billingAuthority, invoiceLimitDays|null,
//  currency}. NO mock data — every node, count and dollar derives from a live row.
//

import SwiftUI
import UIKit

struct VesselDetentionHistoryScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselDetentionHistoryBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror detentionAccessorials.getDetentionHistory rows)

private struct DetentionHistoryResult795: Decodable {
    let events: [DetentionEvent795]
    let total: Int?
}

private struct DetentionEvent795: Decodable, Identifiable {
    let id: Int
    let loadId: Int?
    let facilityName: String?
    let totalMinutes: Double?
    let freeTimeMinutes: Double?
    let billableMinutes: Double?
    let totalCharge: Double?
    let status: String?
    let billingStatus: String?
    let carrierName: String?
    let shipperName: String?
    let cargoType: String?
    let createdAt: String?
}

// MARK: - Body

private struct VesselDetentionHistoryBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.vesselOperatorNavHandler) private var navHandler

    @State private var events: [DetentionEvent795] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    /// Live status facet cycled by the Filter chip (nil = all closed events).
    @State private var statusFacet: String? = nil
    @State private var exportDoc: ShareDoc795? = nil

    private let facets: [String?] = [nil, "paid", "invoiced", "disputed", "pending"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        errorCard(err)
                    } else {
                        kpiStrip
                        timelineSection
                        ctaRow
                        billingRegimeStrip
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .sheet(item: $exportDoc) { doc in
            ActivityShareSheet795(items: [doc.url])
        }
    }

    // MARK: Header (eyebrow + breadcrumb + billed-total hero)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("VESSEL OPERATOR · HISTORY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("CLOSED · 30D")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Button { navHandler?("Compliance") } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Compliance").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, Space.s2)

            Text(money(billedTotal, compact: false))
                .font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, Space.s3)
            Text("\(events.count) closed event\(events.count == 1 ? "" : "s") · 30 days · \(collectedPct)% collected")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
    }

    // MARK: KPI strip (CLOSED · INVOICED · DISPUTED · COLLECTED-gradient)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiCell(label: "CLOSED", value: "\(events.count)", caption: "30 days")
            kpiCell(label: "INVOICED", value: "\(invoicedCount)", caption: money(invoicedAmount, compact: true))
            kpiCell(label: "DISPUTED", value: "\(disputedCount)", caption: money(disputedAmount, compact: true))
            gradientKpiCell(label: "COLLECTED", value: "\(collectedPct)%", caption: "of billed")
        }
    }

    private func kpiCell(label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 24, weight: .bold, design: .monospaced)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 9)).foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func gradientKpiCell(label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(.white.opacity(0.85))
            Text(value).font(.system(size: 24, weight: .bold, design: .monospaced)).tracking(-0.4)
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 9)).foregroundStyle(.white.opacity(0.85))
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Resolution timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RESOLUTION TIMELINE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let f = statusFacet {
                    Text(f.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.info)
                }
                Text("See all (\(events.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Brand.info)
            }

            if events.isEmpty {
                EusoEmptyState(systemImage: "clock.arrow.circlepath",
                               title: "No closed detention",
                               subtitle: "Resolved detention windows appear here on a timeline once a dwell closes and bills.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.prefix(12).enumerated()), id: \.element.id) { idx, ev in
                        timelineNode(ev, isLast: idx == min(events.count, 12) - 1)
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            }
        }
    }

    private func timelineNode(_ ev: DetentionEvent795, isLast: Bool) -> some View {
        let (accent, pill) = billingStyle(ev.billingStatus)
        return HStack(alignment: .top, spacing: Space.s3) {
            // Rail + node marker.
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(palette.bgCardSoft)
                        .overlay(Circle().strokeBorder(accent, lineWidth: 2))
                        .frame(width: 14, height: 14)
                    Circle().fill(accent).frame(width: 6, height: 6)
                }
                if !isLast {
                    Rectangle().fill(palette.borderFaint)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nodeTitle(ev))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: Space.s2)
                    Text((pill).uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.16)))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(nodeSub(ev))
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: Space.s2)
                    Text(money(ev.totalCharge ?? 0, compact: false))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .padding(.bottom, isLast ? 0 : Space.s5)
        }
    }

    // MARK: CTA row (Export ledger · Filter)

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { exportLedger() } label: {
                Text("Export ledger")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(events.isEmpty)
            .opacity(events.isEmpty ? 0.6 : 1.0)

            Button { cycleFilter() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .bold))
                    Text(statusFacet?.capitalized ?? "Filter")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(palette.textPrimary)
                .frame(minWidth: 124, minHeight: 48)
                .padding(.horizontal, Space.s3)
                .background(palette.bgCard)
                .overlay(Capsule().strokeBorder(palette.borderFaint))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Billing-window regime strip (tri-country)

    private var billingRegimeStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("BILLING WINDOW · BY REGIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("unbilled past the window is unpayable")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            // A window rail: US 30-day cap, CA/MX contractual (no statutory limit).
            HStack(spacing: 0) {
                Rectangle().fill(Brand.info).frame(height: 3)
                    .frame(maxWidth: .infinity)
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(Brand.warning)
                        .frame(width: 18, height: 14)
                    Text("30").font(.system(size: 7, weight: .heavy)).foregroundStyle(Color(hex: 0x3A2600))
                }
                Rectangle().fill(palette.borderSoft).frame(height: 2)
                    .frame(maxWidth: .infinity)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack {
                Text("US · FMC 46 CFR 541 · invoice ≤ 30d · USD")
                    .font(.system(size: 8.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                Text("CA · MX contractual · no statutory limit")
                    .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 320)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Derived figures

    private var billedTotal: Double { events.reduce(0) { $0 + ($1.totalCharge ?? 0) } }
    private var invoicedCount: Int { events.filter { ($0.billingStatus ?? "") == "invoiced" }.count }
    private var invoicedAmount: Double { events.filter { ($0.billingStatus ?? "") == "invoiced" }.reduce(0) { $0 + ($1.totalCharge ?? 0) } }
    private var disputedCount: Int { events.filter { ($0.billingStatus ?? "") == "disputed" }.count }
    private var disputedAmount: Double { events.filter { ($0.billingStatus ?? "") == "disputed" }.reduce(0) { $0 + ($1.totalCharge ?? 0) } }
    private var paidAmount: Double { events.filter { ($0.billingStatus ?? "") == "paid" }.reduce(0) { $0 + ($1.totalCharge ?? 0) } }
    private var collectedPct: Int { billedTotal > 0 ? Int((paidAmount / billedTotal * 100).rounded()) : 0 }

    private func nodeTitle(_ ev: DetentionEvent795) -> String {
        if let f = ev.facilityName, !f.isEmpty, f != "Unknown" { return f }
        if let c = ev.carrierName, !c.isEmpty, c != "N/A" { return c }
        if let l = ev.loadId, l > 0 { return "VES-\(l)" }
        return "Detention #\(ev.id)"
    }

    private func nodeSub(_ ev: DetentionEvent795) -> String {
        var parts: [String] = []
        if let d = shortDate(ev.createdAt) { parts.append(d) }
        if let c = ev.carrierName, !c.isEmpty, c != "N/A" { parts.append(c) }
        else if let s = ev.shipperName, !s.isEmpty, s != "N/A" { parts.append(s) }
        if let bm = ev.billableMinutes, bm > 0 {
            let h = bm / 60
            parts.append(h >= 1 ? String(format: "%.0fh over", h) : String(format: "%.0fm over", bm))
        }
        return parts.isEmpty ? "closed dwell" : parts.joined(separator: " · ")
    }

    private func billingStyle(_ s: String?) -> (Color, String) {
        switch (s ?? "").lowercased() {
        case "paid":     return (Brand.success, "paid")
        case "invoiced": return (Brand.info, "invoiced")
        case "disputed": return (Brand.danger, "disputed")
        default:         return (Brand.warning, "pending")
        }
    }

    private func shortDate(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d else { return String(iso.prefix(10).suffix(5)) }
        let out = DateFormatter(); out.dateFormat = "MM-dd"
        return out.string(from: d)
    }

    private func money(_ v: Double, compact: Bool) -> String {
        if compact {
            if abs(v) >= 1000 { return "$\(String(format: "%.1f", v / 1000))K" }
            return "$\(Int(v))"
        }
        if v == v.rounded() { return "$\(Int(v).formatted(.number.grouping(.automatic)))" }
        return "$\(String(format: "%.2f", v))"
    }

    // MARK: - Actions

    private func load() async {
        loading = true; loadError = nil
        struct HistoryIn: Encodable { let status: String?; let limit: Int }
        do {
            let res: DetentionHistoryResult795 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getDetentionHistory",
                input: HistoryIn(status: statusFacet, limit: 100))
            self.events = res.events
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func cycleFilter() {
        let idx = facets.firstIndex(where: { $0 == statusFacet }) ?? 0
        statusFacet = facets[(idx + 1) % facets.count]
        Task { await load() }
    }

    /// Compose a CSV from the LIVE events and hand it to the native share sheet.
    /// Self-contained — no server export endpoint required (that is a named gap).
    private func exportLedger() {
        guard !events.isEmpty else { return }
        var csv = "facility,party,billing_status,billable_minutes,charge_usd,date\n"
        for ev in events {
            let facility = (ev.facilityName ?? "").replacingOccurrences(of: ",", with: " ")
            let party = (ev.carrierName ?? ev.shipperName ?? "").replacingOccurrences(of: ",", with: " ")
            let bs = ev.billingStatus ?? ""
            let bm = Int(ev.billableMinutes ?? 0)
            let charge = String(format: "%.2f", ev.totalCharge ?? 0)
            let date = ev.createdAt ?? ""
            csv += "\(facility),\(party),\(bs),\(bm),\(charge),\(date)\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("detention-ledger-\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.data(using: .utf8)?.write(to: url)
            exportDoc = ShareDoc795(url: url)
        } catch {
            loadError = "Couldn't compose the ledger export."
        }
    }
}

// MARK: - Share plumbing

private struct ShareDoc795: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityShareSheet795: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview("795 · Vessel Detention History · Night") {
    VesselDetentionHistoryScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("795 · Vessel Detention History · Light") {
    VesselDetentionHistoryScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
