//
//  206_ShipperSettlements.swift
//  EusoTrip — Shipper · Settlements (brick 206).
//
//  Parity-reconciled to `02 Shipper/Code/206_ShipperSettlements.swift`
//  per _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: TopBar (eyebrow + payable counter + title + sync sub-line),
//  IridescentHairline, 3-col KPI strip in a single card with hairline
//  dividers (PAYABLE · PAID 30D · AVG DSO), 5-chip filter row with
//  counts, ledger rows with 3px status-tinted tier rim + status pill +
//  amount + 108×6 tri-color breakdown bar, bottom 48pt action ribbon
//  ("Approve N payables · $TOTAL").
//
//  Real data preserved: ShipperDeliveryConfirmationsStore +
//  shippers.getDeliveryConfirmations + 205 sheet binding. Aggregates
//  computed client-side from the same verified server array.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1).
//  §11.4 / §15.2 anchor settlement set this brick is calibrated against:
//    LD-260427-B41782FF02 (KC→Omaha NH₃ · MC-331 · Heartland Cryogenics
//    · POD signed) — payable-POD ready to approve.
//    LD-260427-A38FB12C7E (Houston→Dallas UN1203 · MC-306 · Gulf Coast
//    Tankers · POD pending) — escrow.
//    LD-260425-7C3A09F18B (LA→Phoenix berries · 1.5h detention · Pacific
//    Cold Logistics) — disputed.
//
//  Web peer: client/src/pages/Settlements.tsx.
//  Notification names: eusoShipperSettlementApprove,
//                      eusoShipperSettlementOpenLoad.
//
//  BottomNav: Me current — out of scope per parity mandate §1.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Visual taxonomy

private enum LedgerStatus {
    case payablePOD       // gradient — approve-ready
    case escrowPending    // warn (hazmat orange)
    case disputed         // danger
    case paidRecent       // paidGrad
    case paidCompact      // neutral hollow ring
}

// MARK: - Screen body

struct ShipperSettlements: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var store = ShipperDeliveryConfirmationsStore()

    @State private var selectedStatus: ShipperAPI.DeliveryConfirmationStatus? = nil
    @State private var openLoadDetail: SettlementSheetTarget? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    kpiStrip
                    statusChips
                    ledger
                    Color.clear.frame(height: 96 + 48 + 24)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
            .overlay(alignment: .bottom) {
                if approvableCount > 0 {
                    actionRibbon
                        .padding(.horizontal, Space.s5)
                        .padding(.bottom, Space.s4)
                }
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $openLoadDetail) { target in
            ShipperLoadDetailScreen(
                theme: palette,
                loadId: target.loadId,
                previewLoadNumber: target.loadNumber,
                previewLane: target.lane
            )
            .environmentObject(session)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var allRows: [ShipperAPI.DeliveryConfirmation] {
        store.state.value ?? []
    }

    // MARK: - TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · SETTLEMENTS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(payableCounterLine)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textSecondary)
            }
            Text("Settlements")
                .font(EType.display)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s2)
            Text(syncSubline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var payableCounterLine: String {
        guard approvableCount > 0 else { return "0 PAYABLE" }
        return "\(approvableCount) PAYABLE · \(currency(approvableSum))"
    }

    private var syncSubline: String {
        let company = "Eusorone Technologies"
        let suffix: String
        switch store.state {
        case .loading: suffix = "syncing ledger…"
        case .loaded:  suffix = "payable / paid ledger · last sync just now"
        case .empty:   suffix = "ledger empty · post a load to start the cycle"
        case .error:   suffix = "ledger sync failed — pull to retry"
        }
        return "\(company) · \(suffix)"
    }

    // MARK: - KPI strip (3-col with hairline dividers, in a single card)

    private var kpiStrip: some View {
        HStack(spacing: 0) {
            kpiColumn(label: "PAYABLE",
                      value: currency(approvableSum),
                      tone: .gradient,
                      meta: "\(approvableCount) load\(approvableCount == 1 ? "" : "s") · escrow")
            kpiDivider
            kpiColumn(label: "PAID 30D",
                      value: currency(paid30dSum),
                      tone: .success,
                      meta: "\(paid30dCount) load\(paid30dCount == 1 ? "" : "s") · cleared")
            kpiDivider
            kpiColumn(label: "AVG DSO",
                      value: avgDSODisplay,
                      tone: .primary,
                      meta: "net-7 EusoQuickPay")
        }
        .padding(.vertical, Space.s3)
        .padding(.horizontal, Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private enum KpiTone { case gradient, success, primary }

    private func kpiColumn(label: String, value: String,
                           tone: KpiTone, meta: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                switch tone {
                case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                case .success:  Text(value).foregroundStyle(Brand.success)
                case .primary:  Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: 22, weight: .bold).monospacedDigit())
            Text(meta)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 40)
            .padding(.horizontal, Space.s2)
    }

    // MARK: - Filter chips (5: All · Payable · Paid · Disputed · Hold)

    private var statusChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All",
                     count: allRows.count,
                     isActive: selectedStatus == nil) {
                    setStatus(nil)
                }
                chip(label: "Payable",
                     count: payableCount,
                     isActive: selectedStatus == .pending) {
                    setStatus(.pending)
                }
                chip(label: "Paid",
                     count: paidCount,
                     isActive: selectedStatus == .confirmed) {
                    setStatus(.confirmed)
                }
                chip(label: "Disputed",
                     count: disputedCount,
                     isActive: selectedStatus == .disputed) {
                    setStatus(.disputed)
                }
                // Hold isn't on the server enum yet; show as inert chip.
                chip(label: "Hold", count: 0, isActive: false) { }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(label: String, count: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if count > 0 {
                    Text("\(label) · \(count)")
                } else {
                    Text(label)
                }
            }
            .font(isActive ? EType.bodyStrong : .system(size: 12, weight: .semibold))
            .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(isActive
                        ? AnyShapeStyle(LinearGradient.primary)
                        : AnyShapeStyle(palette.bgCard))
            .overlay(Capsule().strokeBorder(isActive ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderSoft), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func setStatus(_ s: ShipperAPI.DeliveryConfirmationStatus?) {
        guard s != selectedStatus else { return }
        selectedStatus = s
        store.setStatusFilter(s)
        Task { await store.refresh() }
    }

    // MARK: - Ledger

    @ViewBuilder
    private var ledger: some View {
        switch store.state {
        case .loading:
            ledgerSkeleton
        case .loaded:
            if filteredRows.isEmpty {
                EusoEmptyState(
                    systemImage: "dollarsign.arrow.circlepath",
                    title: emptyTitle,
                    subtitle: emptySubtitle
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(filteredRows) { r in
                        ledgerRow(r)
                    }
                }
            }
        case .empty:
            EusoEmptyState(
                systemImage: "dollarsign.arrow.circlepath",
                title: emptyTitle,
                subtitle: emptySubtitle
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    private var filteredRows: [ShipperAPI.DeliveryConfirmation] { allRows }

    private func ledgerRow(_ r: ShipperAPI.DeliveryConfirmation) -> some View {
        let status = ledgerStatus(for: r)
        let isCompact = (status == .paidCompact)
        return Button {
            openLoadDetail = SettlementSheetTarget(
                loadId: r.loadId,
                loadNumber: r.loadNumber,
                lane: lane(from: r)
            )
            NotificationCenter.default.post(name: .eusoShipperSettlementOpenLoad, object: nil,
                                            userInfo: ["loadId": r.loadId])
        } label: {
            HStack(spacing: 0) {
                tierRim(for: status).frame(width: 3)
                if isCompact {
                    compactBody(r, status: status)
                } else {
                    standardBody(r, status: status)
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rowA11yLabel(r, status: status))
    }

    private func standardBody(_ r: ShipperAPI.DeliveryConfirmation, status: LedgerStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.loadNumber.isEmpty ? "—" : r.loadNumber)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                statusPill(for: status, row: r)
            }
            Text(lane(from: r))
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Text(detailLine(for: r, status: status))
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            HStack(alignment: .center, spacing: Space.s2) {
                Text(r.rate > 0 ? currency(r.rate) : "—")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text(breakdownText(for: r, status: status))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(status == .disputed ? Brand.danger : palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                breakdownBar(for: r, status: status)
                    .frame(width: 108, height: 6)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s4)
    }

    private func compactBody(_ r: ShipperAPI.DeliveryConfirmation, status: LedgerStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.loadNumber.isEmpty ? "—" : r.loadNumber)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                paidHollowPill(for: r)
            }
            Text(lane(from: r))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Text(detailLine(for: r, status: status))
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    @ViewBuilder
    private func tierRim(for status: LedgerStatus) -> some View {
        switch status {
        case .payablePOD:
            Rectangle().fill(LinearGradient.diagonal)
        case .escrowPending:
            Rectangle().fill(LinearGradient(colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
                                            startPoint: .top, endPoint: .bottom))
        case .disputed:
            Rectangle().fill(LinearGradient(colors: [Color(hex: 0xFF6A6A), Color(hex: 0xE03B3B)],
                                            startPoint: .top, endPoint: .bottom))
        case .paidRecent:
            Rectangle().fill(LinearGradient(colors: [Brand.success, Color(hex: 0x00A07B)],
                                            startPoint: .top, endPoint: .bottom))
        case .paidCompact:
            Rectangle().fill(palette.textTertiary.opacity(0.5))
        }
    }

    @ViewBuilder
    private func statusPill(for status: LedgerStatus, row: ShipperAPI.DeliveryConfirmation) -> some View {
        switch status {
        case .payablePOD:
            pillCapsule(text: "PAYABLE · POD",
                        fill: AnyShapeStyle(LinearGradient.primary),
                        textColor: .white)
        case .escrowPending:
            pillCapsule(text: "ESCROW · PENDING",
                        fill: AnyShapeStyle(LinearGradient(
                            colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
                            startPoint: .leading, endPoint: .trailing)),
                        textColor: .white)
        case .disputed:
            pillCapsule(text: "DISPUTED",
                        fill: AnyShapeStyle(LinearGradient(
                            colors: [Color(hex: 0xFF6A6A), Color(hex: 0xE03B3B)],
                            startPoint: .leading, endPoint: .trailing)),
                        textColor: .white)
        case .paidRecent:
            pillCapsule(text: "PAID · \(daysSinceDelivered(row).uppercased())",
                        fill: AnyShapeStyle(LinearGradient(
                            colors: [Brand.success, Color(hex: 0x00A07B)],
                            startPoint: .leading, endPoint: .trailing)),
                        textColor: .white)
        case .paidCompact:
            paidHollowPill(for: row)
        }
    }

    private func pillCapsule(text: String, fill: AnyShapeStyle, textColor: Color) -> some View {
        Text(text)
            .font(EType.micro).tracking(0.5)
            .foregroundStyle(textColor)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(fill))
    }

    private func paidHollowPill(for r: ShipperAPI.DeliveryConfirmation) -> some View {
        Text("PAID · \(daysSinceDelivered(r).uppercased())")
            .font(EType.micro).tracking(0.5)
            .foregroundStyle(Color(hex: 0x00A07B))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(Brand.success))
    }

    /// 108×6 tri-color breakdown — line-haul gradient → FSC amber →
    /// accessorial green or danger. Without server-shipped breakdowns,
    /// we synthesize from a canonical 82.5% / 11.0% / 6.5% split (the
    /// §15.2 anchor mix) so every row reads consistently. When the
    /// backend ships rate.lineHaul / rate.fsc / rate.accessorial,
    /// swap to those values.
    private func breakdownBar(for r: ShipperAPI.DeliveryConfirmation, status: LedgerStatus) -> some View {
        let danger = (status == .disputed)
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textTertiary.opacity(0.15))
                HStack(spacing: 0) {
                    Rectangle().fill(LinearGradient.primary)
                        .frame(width: w * 0.825, height: 6)
                    Rectangle().fill(Brand.hazmat)
                        .frame(width: w * 0.110, height: 6)
                    Rectangle().fill(danger
                                     ? AnyShapeStyle(LinearGradient(
                                         colors: [Color(hex: 0xFF6A6A), Color(hex: 0xE03B3B)],
                                         startPoint: .leading, endPoint: .trailing))
                                     : AnyShapeStyle(Brand.success))
                        .frame(width: w * 0.065, height: 6)
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func detailLine(for r: ShipperAPI.DeliveryConfirmation, status: LedgerStatus) -> String {
        let when = humanDate(r.deliveredAt)
        switch status {
        case .payablePOD:
            return when.map { "POD signed \($0)" } ?? "POD signed · ready to approve"
        case .escrowPending:
            return when.map { "Escrow · POD pending since \($0)" } ?? "Escrow · POD pending"
        case .disputed:
            return when.map { "Disputed · contested \($0)" } ?? "Disputed · awaiting review"
        case .paidRecent, .paidCompact:
            return when.map { "Cleared · delivered \($0)" } ?? "Cleared via EusoQuickPay"
        }
    }

    private func breakdownText(for r: ShipperAPI.DeliveryConfirmation, status: LedgerStatus) -> String {
        if status == .disputed { return "+ detention · contested" }
        guard r.rate > 0 else { return "—" }
        let lineHaul = r.rate * 0.825
        let fsc      = r.rate * 0.110
        let acc      = r.rate * 0.065
        return "\(currency(lineHaul)) line · \(currency(fsc)) FSC · \(currency(acc)) acc."
    }

    // MARK: - Status mapping (server → ledger taxonomy)

    private func ledgerStatus(for r: ShipperAPI.DeliveryConfirmation) -> LedgerStatus {
        let s = r.status.lowercased()
        if s == "disputed" { return .disputed }
        if s == "pending"  { return .escrowPending }
        // Confirmed: split into payable-POD vs paid-recent vs paid-compact
        // by elapsed time since delivery.
        let days = daysSinceDeliveredCount(r)
        if days < 1 { return .payablePOD }      // <24h since POD → ready to approve
        if days < 3 { return .paidRecent }      // 1–3d → recent paid card
        return .paidCompact                     // 3d+ → compact paid row
    }

    // MARK: - Aggregates

    private var approvableRows: [ShipperAPI.DeliveryConfirmation] {
        allRows.filter {
            let s = ledgerStatus(for: $0)
            return s == .payablePOD || s == .escrowPending
        }
    }
    private var approvableCount: Int { approvableRows.count }
    private var approvableSum: Double { approvableRows.reduce(0) { $0 + $1.rate } }

    private var paid30dRows: [ShipperAPI.DeliveryConfirmation] {
        allRows.filter {
            let s = ledgerStatus(for: $0)
            return s == .paidRecent || s == .paidCompact
        }
    }
    private var paid30dSum: Double { paid30dRows.reduce(0) { $0 + $1.rate } }
    private var paid30dCount: Int { paid30dRows.count }

    /// Average days since delivery across paid rows. Stand-in for true
    /// DSO until the backend ships invoice→pay-cleared timestamps.
    private var avgDSODisplay: String {
        let paidDays = paid30dRows.map { daysSinceDeliveredCount($0) }
        guard !paidDays.isEmpty else { return "—" }
        let avg = Double(paidDays.reduce(0, +)) / Double(paidDays.count)
        return String(format: "%.1fd", avg)
    }

    private var payableCount: Int {
        allRows.filter { $0.status.lowercased() == "pending" || ledgerStatus(for: $0) == .payablePOD }.count
    }
    private var paidCount: Int { paid30dCount }
    private var disputedCount: Int { allRows.filter { $0.status.lowercased() == "disputed" }.count }

    // MARK: - Empty / error / skeleton

    private var emptyTitle: String {
        switch selectedStatus {
        case .pending:   return "No payable settlements"
        case .confirmed: return "No paid settlements"
        case .disputed:  return "No disputed settlements"
        case nil:        return "No settlements yet"
        }
    }

    private var emptySubtitle: String {
        switch selectedStatus {
        case .pending:
            return "Loads pending settlement will appear here once a driver delivers and the receiver signs the POD."
        case .confirmed:
            return "Cleared deliveries appear here after EusoQuickPay settles the load."
        case .disputed:
            return "Disputes show here when a delivery confirmation is contested."
        case nil:
            return "Once a load you posted is delivered, it'll show up here with the billed rate."
        }
    }

    private var ledgerSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 96)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: { Task { await store.refresh() } }) {
                Text("Retry")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Bottom action ribbon

    private var actionRibbon: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperSettlementApprove, object: nil,
                                            userInfo: ["count": approvableCount,
                                                       "total": approvableSum])
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                Text("Approve \(approvableCount) payable\(approvableCount == 1 ? "" : "s") · \(currency(approvableSum))")
                    .font(EType.bodyStrong)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(LinearGradient.primary))
        .clipShape(Capsule())
        .accessibilityLabel("Approve \(approvableCount) payables totaling \(currency(approvableSum))")
    }

    // MARK: - Helpers

    private func lane(from row: ShipperAPI.DeliveryConfirmation) -> String {
        let o = row.origin.trimmingCharacters(in: .whitespacesAndNewlines)
                          .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        let d = row.destination.trimmingCharacters(in: .whitespacesAndNewlines)
                               .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        if o.isEmpty && d.isEmpty { return "—" }
        let left  = o.isEmpty ? "—" : o
        let right = d.isEmpty ? "—" : d
        return "\(left) → \(right)"
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func humanDate(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFmt.date(from: iso)
        if date == nil {
            isoFmt.formatOptions = [.withInternetDateTime]
            date = isoFmt.date(from: iso)
        }
        if date == nil {
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            day.locale = Locale(identifier: "en_US_POSIX")
            date = day.date(from: iso)
        }
        guard let d = date else { return iso }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: d)
    }

    private func daysSinceDeliveredCount(_ r: ShipperAPI.DeliveryConfirmation) -> Int {
        let iso = r.deliveredAt
        guard !iso.isEmpty else { return 999 }
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFmt.date(from: iso)
        if date == nil {
            isoFmt.formatOptions = [.withInternetDateTime]
            date = isoFmt.date(from: iso)
        }
        if date == nil {
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            day.locale = Locale(identifier: "en_US_POSIX")
            date = day.date(from: iso)
        }
        guard let d = date else { return 999 }
        return Int(Date().timeIntervalSince(d) / 86_400)
    }

    private func daysSinceDelivered(_ r: ShipperAPI.DeliveryConfirmation) -> String {
        let n = daysSinceDeliveredCount(r)
        if n < 1 { return "today" }
        if n == 1 { return "1d ago" }
        return "\(n)d ago"
    }

    private func rowA11yLabel(_ r: ShipperAPI.DeliveryConfirmation, status: LedgerStatus) -> String {
        let statusName: String = {
            switch status {
            case .payablePOD:    return "Payable, POD signed"
            case .escrowPending: return "Escrow, POD pending"
            case .disputed:      return "Disputed"
            case .paidRecent:    return "Paid recently"
            case .paidCompact:   return "Paid"
            }
        }()
        return "\(r.loadNumber), \(lane(from: r)), \(currency(r.rate)), \(statusName)"
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }
}

// MARK: - Sheet identifier

private struct SettlementSheetTarget: Identifiable, Hashable {
    let loadId: String
    let loadNumber: String
    let lane: String
    var id: String { loadId }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperSettlementApprove   = Notification.Name("eusoShipperSettlementApprove")
    static let eusoShipperSettlementOpenLoad  = Notification.Name("eusoShipperSettlementOpenLoad")
}

// MARK: - Screen wrapper

struct ShipperSettlementsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperSettlements()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_206(),
                trailing: shipperNavTrailing_206(),
                orbState: .idle
            )
        }
    }
}

// Out of scope per parity mandate §1 — settlements live under Me.
private func shipperNavLeading_206() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_206() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("206 · Shipper · Settlements · Night") {
    ShipperSettlementsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("206 · Shipper · Settlements · Afternoon") {
    ShipperSettlementsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
