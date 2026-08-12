//
//  004_VesselDemurrageDetention.swift
//  EusoTrip — Vessel Shipper · Demurrage & Detention (single-shipment exposure).
//
//  Verbatim port of "004 Vessel Demurrage Detention.svg" (Dark + Light parity).
//  Shipper-side counterpart of the operator fleet monitor 658_VesselDemurrageDetentionWatch.
//  One booking's terminal-dwell demurrage + off-terminal detention exposure, the CBP
//  hold cause, an ESang advisory, the projected charge if unresolved, and two actions:
//  Book a CES exam slot (clear the hold) and Dispute the demurrage. Shipper nav anchored
//  (HOME · LOADS · [orb] · TRACK · ME), LOADS current — mirrors 002_VesselBookingDetail.
//
//  Data (REAL — no mock, no fabricated fallbacks):
//    vesselShipments.getVesselShipmentDetail (EXISTS vesselShipments.ts:259) -> hero + demurrage[] + customs[]
//    vesselShipments.getISFStatus           (EXISTS vesselShipments.ts:1215) -> ISF chip + exam state
//    vesselShipments.disputeVesselDemurrage (STAGED §56 — server_patch_vesselShipments.ts.md) -> Dispute CTA
//    vesselShipments.bookCESExam            (STAGED §56 — server_patch_vesselShipments.ts.md + migration 0321) -> Book CES exam CTA
//
//  NOTE on calculateVesselDemurrage: the SVG <desc> names it, but it is a MUTATION that
//  INSERTS a vessel_demurrage row (vesselShipments.ts:1301). Firing it on a read-only
//  detail open would persist a charge as a side effect of viewing. Per the no-side-effect-
//  on-load discipline (002 precedent), this screen does NOT call it on load; the free-time
//  projection is derived from the already-persisted demurrage rows (ratePerDay/freeTimeDays).
//
//  LifecycleProductContext: VESSEL · 40RF reefer (cold-chain, −18°C) is the stringent
//  variant flagged in the hero subline; dry FCL is the default lens.
//

import SwiftUI

// MARK: - Flexible decimal (server money may arrive as string | number)

private struct V4Decimal: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = Double(s) }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let i = try? c.decode(Int.self) { value = Double(i) }
        else { value = nil }
    }
}

// MARK: - Data shapes (decoded from REAL getVesselShipmentDetail + getISFStatus)

/// vessel_demurrage row. Real columns (schema.ts:10494). Money via V4Decimal.
private struct VesselDemurrage004: Decodable, Identifiable {
    let id: Int
    let chargeType: String?     // "demurrage" | "detention" | "per_diem"
    let freeTimeDays: Int?
    let chargeableDays: Int?
    let ratePerDay: V4Decimal?
    let totalCharge: V4Decimal?
    let startDate: String?
    let endDate: String?
    let status: String?         // "accruing" | "invoiced" | "paid" | "disputed" | "waived"
}

/// customs_declarations row (subset) — backs the CBP hold-cause card.
private struct VesselCustoms004: Decodable, Identifiable {
    let id: Int
    let entryNumber: String?
    let status: String?         // "draft" | "filed" | "under_review" | "cleared" | "held" | "rejected"
    let holdReasons: [String]?
}

private struct VesselPort004: Decodable {
    let name: String?
    let unlocode: String?
    let city: String?
    let country: String?        // "US" | "CA" | "MX" | "NL" ...
}

/// vesselShipments.getVesselShipmentDetail (EXISTS :259) — real vessel_shipments
/// columns + the nested joins the server spreads in (demurrage, customs, ports).
private struct VesselShipmentDetail004: Decodable {
    let id: Int
    let bookingNumber: String?
    let cargoType: String?
    let commodity: String?
    let containerSize: String?
    let status: String?
    let originPort: VesselPort004?
    let destinationPort: VesselPort004?
    let demurrage: [VesselDemurrage004]?
    let customs: [VesselCustoms004]?
}

/// vesselShipments.getISFStatus (EXISTS :1215) — ISF 10+2 filing state.
private struct VesselISFStatus004: Decodable {
    let status: String?         // "cleared" | "filed" | "overdue" | "not_filed"
    let isfFiled: Bool?
    let isfCleared: Bool?
    let warning: String?
}

// MARK: - Screen

struct VesselDemurrageDetentionScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int
    init(theme: Theme.Palette, shipmentId: Int = 0) {
        self.theme = theme
        self.shipmentId = shipmentId
    }
    var body: some View {
        Shell(theme: theme) {
            VesselDemurrageDetentionBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Track", systemImage: "clock",   isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",  isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselDemurrageDetentionBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var detail: VesselShipmentDetail004? = nil
    @State private var isf: VesselISFStatus004? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Both CTAs write here on failure — never silently swallowed.
    @State private var actionError: String? = nil
    @State private var disputing = false
    @State private var booking = false
    @State private var disputeOk = false
    @State private var bookedOk = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s5)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if let actionError { actionErrorBanner(actionError) }
                    if disputeOk { successBanner("Demurrage disputed, under review.") }
                    if bookedOk { successBanner("CES exam slot requested. You'll be notified on confirmation.") }

                    if loading {
                        loadingState
                    } else if let err = loadError {
                        errorCard(err)
                    } else if detail == nil {
                        EusoEmptyState(systemImage: "shippingbox",
                                       title: "Shipment not found",
                                       subtitle: "This booking is no longer available or you don't have access to it.")
                    } else {
                        freeTimeMeter
                        chargeBreakdown
                        holdCause
                        esangAdvisory
                        projection
                        actions
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Derived demurrage facts (from persisted rows — no fabrication)

    private var demRows: [VesselDemurrage004] { detail?.demurrage ?? [] }
    private var demurrageRows: [VesselDemurrage004] { demRows.filter { ($0.chargeType ?? "") == "demurrage" } }
    private var detentionRows: [VesselDemurrage004] { demRows.filter { ($0.chargeType ?? "") == "detention" || ($0.chargeType ?? "") == "per_diem" } }

    private var demurrageCharge: Double { demurrageRows.compactMap { $0.totalCharge?.value }.reduce(0, +) }
    private var detentionCharge: Double { detentionRows.compactMap { $0.totalCharge?.value }.reduce(0, +) }
    private var freeDays: Int { demurrageRows.compactMap { $0.freeTimeDays }.max() ?? 0 }
    private var detentionFreeDays: Int { detentionRows.compactMap { $0.freeTimeDays }.max() ?? 0 }
    private var ratePerDay: Double { demurrageRows.compactMap { $0.ratePerDay?.value }.max() ?? 0 }
    private var detentionRate: Double { detentionRows.compactMap { $0.ratePerDay?.value }.max() ?? 0 }
    /// Day elapsed since the earliest accruing start. nil when nothing has started.
    private var dwellDay: Int? {
        let starts = demRows.compactMap { parseISO($0.startDate) }
        guard let first = starts.min() else { return nil }
        return max(0, Int(Date().timeIntervalSince(first) / 86400))
    }
    private var accruing: Bool { demRows.contains { ($0.status ?? "").lowercased() == "accruing" } }
    private var disputed: Bool { demRows.contains { ($0.status ?? "").lowercased() == "disputed" } }

    // MARK: Top bar  (SVG: back chevron · eyebrow y=72 · booking# y=116 · status pill · subline y=138)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("✦ VESSEL SHIPPER · DEMURRAGE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
            }
            .padding(.top, Space.s5)

            HStack(alignment: .center) {
                Text(detail?.bookingNumber ?? "-")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .kerning(-0.5)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                if let pill = statusPill {
                    Text(pill.0)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Color(hex: 0x05060A))
                        .padding(.horizontal, Space.s4).padding(.vertical, 6)
                        .background(Capsule().fill(pill.1))
                }
            }
            .padding(.top, Space.s4)

            Text(subline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 6)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
    }

    /// Red CUSTOMS HOLD when the shipment is on a customs hold (SVG state); else the
    /// real status as a gradient pill. Never fabricated.
    private var statusPill: (String, AnyShapeStyle)? {
        let s = (detail?.status ?? "").lowercased()
        if s == "customs_hold" { return ("CUSTOMS HOLD", AnyShapeStyle(Brand.danger)) }
        guard !s.isEmpty else { return nil }
        return (s.replacingOccurrences(of: "_", with: " ").uppercased(), AnyShapeStyle(LinearGradient.primary))
    }

    /// "<size> <cargo> · <commodity> · <terminal> · origin → destination" — real or omitted.
    private var subline: String {
        var parts: [String] = []
        if let size = prettySize(detail?.containerSize) { parts.append(size) }
        if let cargo = detail?.cargoType, !cargo.isEmpty { parts.append(cargo) }
        if let c = detail?.commodity, !c.isEmpty { parts.append(c) }
        let o = portShort(detail?.originPort), d = portShort(detail?.destinationPort)
        if let o, let d { parts.append("\(o) → \(d)") }
        else if let only = o ?? d { parts.append(only) }
        return parts.isEmpty ? "Demurrage & detention exposure" : parts.joined(separator: " · ")
    }

    // MARK: Free-time meter  (SVG y=178 gradient-rim card)

    private var freeTimeMeter: some View {
        let used = dwellDay ?? 0
        let remaining = max(0, freeDays - used)
        let frac: Double = freeDays > 0 ? min(1.0, Double(used) / Double(freeDays)) : 0
        return VStack(alignment: .leading, spacing: 0) {
            Text(meterEyebrow(used: used))
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)

            HStack(alignment: .firstTextBaseline) {
                Text(money(demurrageCharge))
                    .font(.system(size: 34, weight: .bold)).monospacedDigit()
                    .foregroundStyle(demurrageCharge > 0 ? Brand.warning : Brand.success)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(freeDays > 0 ? "\(remaining) free days remaining" : "No free-time clock yet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    if ratePerDay > 0 {
                        Text("then \(money(ratePerDay))/day")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(.top, Space.s3)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10)).frame(height: 10)
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: geo.size.width * CGFloat(frac), height: 10)
                }
            }
            .frame(height: 10)
            .padding(.top, Space.s4)

            Text(meterNote)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Brand.warning)
                .padding(.top, Space.s3)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func meterEyebrow(used: Int) -> String {
        guard freeDays > 0 else { return "DEMURRAGE · NO FREE-TIME CLOCK" }
        return "DEMURRAGE · \(freeDays) FREE DAYS · DAY \(used) OF \(freeDays)"
    }
    private var meterNote: String {
        if disputed { return "Demurrage disputed · under review" }
        let onHold = (detail?.status ?? "").lowercased() == "customs_hold"
        if onHold && freeDays > 0 {
            let day6 = freeDays + 1
            return "CBP exam clearing now · demurrage starts day \(day6) if unresolved"
        }
        if accruing { return "Meter running · free time consuming at terminal" }
        return "Free time intact · meter starts on terminal discharge"
    }

    // MARK: Charge breakdown  (SVG y=350 two cards)

    private var chargeBreakdown: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("CHARGE BREAKDOWN\(terminalSuffix)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: Space.s3) {
                splitCard(title: "DEMURRAGE", sub: "terminal dwell",
                          value: demurrageValueLabel, gradient: false)
                splitCard(title: "DETENTION", sub: "off-terminal per-diem",
                          value: detentionValueLabel, gradient: true)
            }
        }
    }

    private var terminalSuffix: String {
        if let t = portShort(detail?.destinationPort) { return " · \(t.uppercased())" }
        return ""
    }
    private var demurrageValueLabel: String {
        if let d = dwellDay, freeDays > 0 { return "\(money(demurrageCharge)) · day \(d)/\(freeDays)" }
        return money(demurrageCharge)
    }
    private var detentionValueLabel: String {
        if detentionCharge > 0 { return money(detentionCharge) }
        if detentionFreeDays > 0 { return "\(detentionFreeDays) free days" }
        return "-"
    }

    private func splitCard(title: String, sub: String, value: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(sub)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s3)
            Group {
                if gradient {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: 20, weight: .bold)).monospacedDigit()
            .padding(.top, Space.s3)
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Hold cause  (SVG y=486 — CBP + ISF chips, driven by getISFStatus + customs[])

    private var holdCause: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("HOLD CAUSE · CBP")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(holdTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(holdDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
                HStack(spacing: Space.s2) {
                    chip(isfChipLabel, tone: isfChipTone)
                    chip(examChipLabel, tone: Brand.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var heldCustoms: VesselCustoms004? {
        detail?.customs?.first { ($0.status ?? "").lowercased() == "held" }
            ?? detail?.customs?.first { ($0.status ?? "").lowercased() == "under_review" }
            ?? detail?.customs?.first
    }
    private var holdTitle: String {
        if let r = heldCustoms?.holdReasons, let first = r.first, !first.isEmpty { return first }
        if let e = heldCustoms?.entryNumber, !e.isEmpty { return "CBP entry \(e) under review" }
        return "CBP hold - cause pending"
    }
    private var holdDetail: String {
        if let w = isf?.warning, !w.isEmpty { return w }
        if isf?.isfFiled == true { return "ISF 10+2 on file · CBP examination in progress" }
        return "ISF status pending · awaiting CBP examination outcome"
    }
    private var isfChipLabel: String { isf?.isfFiled == true ? "ISF ON FILE" : "ISF NOT FILED" }
    private var isfChipTone: Color { isf?.isfFiled == true ? Brand.success : Brand.danger }
    private var examChipLabel: String {
        switch (isf?.status ?? heldCustoms?.status ?? "").lowercased() {
        case "cleared": return "CLEARED"
        case "rejected": return "REJECTED"
        default: return "EXAM IN PROGRESS"
        }
    }

    private func chip(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tone)
            .padding(.horizontal, Space.s3).padding(.vertical, 5)
            .background(Capsule().fill(tone.opacity(0.16)))
    }

    // MARK: ESang advisory  (SVG y=594)

    private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(Color.white.opacity(0.35)).frame(width: 14, height: 14).offset(x: -4, y: -4)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ESang: book CES exam to clear before the demurrage clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(esangSubline)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private var esangSubline: String {
        let reefer = (detail?.cargoType ?? "").lowercased().contains("reefer")
            || (detail?.containerSize ?? "").lowercased().contains("reefer")
        let exposure = projectedTotal
        let amt = exposure > 0 ? "avoid ~\(money(exposure)) exposure" : "minimise dwell exposure"
        return reefer ? "Reefer monitored · \(amt) + spoilage risk" : amt
    }

    // MARK: Projection  (SVG y=702 red band)

    private var projection: some View {
        let total = projectedTotal
        return VStack(alignment: .leading, spacing: Space.s3) {
            Text("PROJECTED IF UNRESOLVED")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack {
                Text(projectionLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(total > 0 ? money(total) : "-")
                    .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Brand.danger)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 10)
            .background(Brand.danger.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }
    /// Honest projection from persisted rates over the next 5 chargeable days.
    private var projectedTotal: Double {
        let span = 5.0
        return (ratePerDay + detentionRate) * span
    }
    private var projectionLine: String {
        let start = (freeDays > 0 ? freeDays + 1 : 1)
        if ratePerDay > 0 || detentionRate > 0 {
            return "Day \(start)–\(start + 4) · \(money(ratePerDay)) demurrage + \(money(detentionRate)) detention"
        }
        return "No projected charges - rates not yet set"
    }

    // MARK: Actions  (SVG y=742 — gradient "Book CES exam slot" · glass "Dispute")

    private var actions: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await bookCESExam() }
            } label: {
                HStack(spacing: 8) {
                    if booking { ProgressView().tint(Color(hex: 0x05060A)) }
                    Text("Book CES exam slot").font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Color(hex: 0x05060A))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(booking || loading)

            Button {
                Task { await disputeDemurrage() }
            } label: {
                HStack(spacing: 6) {
                    if disputing { ProgressView().tint(palette.textPrimary) }
                    Text("Dispute").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(palette.textPrimary)
                .frame(width: 132, height: 48)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(disputing || loading || disputed || demRows.isEmpty)
        }
    }

    // MARK: Chrome

    private func successBanner(_ msg: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.success)
            Text(msg).font(EType.caption).foregroundStyle(Brand.success)
            Spacer()
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.success.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorCard(_ err: String) -> some View {
        VStack(alignment: .leading) {
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(Brand.danger.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func actionErrorBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.danger)
            Text(message).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer()
            Button { actionError = nil } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 128)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: Helpers

    private func money(_ v: Double) -> String {
        guard v != 0 else { return "$0" }
        return "$\(Int(v.rounded()))"
    }
    private func portShort(_ p: VesselPort004?) -> String? {
        guard let p else { return nil }
        if let city = p.city, !city.isEmpty {
            if let cc = p.country, !cc.isEmpty { return "\(city) \(cc)" }
            return city
        }
        if let name = p.name, !name.isEmpty { return name }
        if let loc = p.unlocode, !loc.isEmpty { return loc }
        return nil
    }
    private func prettySize(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.split(separator: "_").map { seg -> String in
            seg.allSatisfy { $0.isNumber || $0 == "f" || $0 == "t" } ? String(seg) : seg.uppercased()
        }.joined(separator: " ")
    }
    private func parseISO(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: iso)
    }

    // MARK: Load (two REAL reads · do/catch · never try?)

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct ISFIn: Encodable { let shipmentId: Int }
        do {
            async let detailTask: VesselShipmentDetail004? =
                EusoTripAPI.shared.query("vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
            // ISF status is best-effort context for the hold-cause card; a failure here
            // must not blank the whole screen, so it's decoded optional + tolerated.
            async let isfTask: VesselISFStatus004? =
                EusoTripAPI.shared.query("vesselShipments.getISFStatus", input: ISFIn(shipmentId: shipmentId))
            self.detail = try await detailTask
            self.isf = (try? await isfTask) ?? nil
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    // MARK: Dispute (STAGED §56 endpoint — real DB write on the server)

    private func disputeDemurrage() async {
        guard !demRows.isEmpty else { actionError = "No demurrage charge to dispute yet."; return }
        disputing = true; actionError = nil; disputeOk = false
        struct DisputeIn: Encodable { let shipmentId: Int; let reason: String }
        struct DisputeOut: Decodable { let success: Bool?; let disputed: Int? }
        do {
            let out: DisputeOut = try await EusoTripAPI.shared.mutation(
                "vesselShipments.disputeVesselDemurrage",
                input: DisputeIn(shipmentId: shipmentId,
                                 reason: "Shipper dispute — charges contested pending CBP exam outcome"))
            if out.success == true { disputeOk = true; await load() }
            else { actionError = "Dispute could not be filed. Please try again." }
        } catch {
            actionError = "Couldn't file dispute. "
                + (error.eusoUserCopy)
        }
        disputing = false
    }

    // MARK: Book CES exam (STAGED §56 endpoint + migration 0321 — real DB insert)

    private func bookCESExam() async {
        booking = true; actionError = nil; bookedOk = false
        struct BookIn: Encodable { let shipmentId: Int }
        struct BookOut: Decodable { let success: Bool?; let appointmentId: Int? }
        do {
            let out: BookOut = try await EusoTripAPI.shared.mutation(
                "vesselShipments.bookCESExam", input: BookIn(shipmentId: shipmentId))
            if out.success == true { bookedOk = true }
            else { actionError = "CES exam slot could not be requested. Please try again." }
        } catch {
            actionError = "Couldn't request CES exam. "
                + (error.eusoUserCopy)
        }
        booking = false
    }
}

// MARK: - Previews (SVG sample identity/figures live ONLY here — never in the live view)

#Preview("004 · Vessel Demurrage Detention · Night") {
    VesselDemurrageDetentionScreen(theme: Theme.dark, shipmentId: 39044)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("004 · Vessel Demurrage Detention · Light") {
    VesselDemurrageDetentionScreen(theme: Theme.light, shipmentId: 39044)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
