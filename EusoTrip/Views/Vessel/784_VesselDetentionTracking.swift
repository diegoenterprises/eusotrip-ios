//
//  784_VesselDetentionTracking.swift
//  EusoTrip — Vessel Operator · Detention Tracking (PER-DIEM ACCRUAL LADDER).
//
//  Bespoke port of canonical wireframe 784 "Vessel Detention Tracking" (06
//  Vessel · Light/Dark). DETAIL/MONEY-TIMELINE grammar (mirror of 770 / 02
//  Shipper 227 Settlement Detail) per FOUNDER CADENCE DIRECTIVE 2026-05-24:
//  a detail header (back-chevron + ✦ eyebrow + 28/700 title + iridescent
//  hairline), a cardRim+inset hero ActiveCard (total $ owed + ACCRUING/carrier
//  chips + accrual progress bar), a 3-cell KPI strip (OVER FREE · AT RISK ·
//  WITHIN FREE), an itemized equipment accrual ladder (container # / days-over
//  + LFD/per-diem sub + status pill + right $/hours value), a context strip,
//  and a Schedule-return / Dispute CTA pair.
//
//  Docked under SHIPMENTS. role=.vesselOperator · transportMode=vessel · US.
//
//  REAL WIRING (tRPC, server/routers):
//    · yardManagement.getDetentionTracking   {onlyActive} ->
//        { records:[{ id, trailerNumber, carrierName, loadId, arrivalTime,
//                     freeTimeHours, totalTimeHours, detentionHours, rate,
//                     accruedCharge, status:"critical"|"warning"|"normal",
//                     type:"loading"|"unloading" }],
//          summary:{ activeDetentions, totalAccruedCharges,
//                    avgDetentionHours, criticalCount } }
//        (yardManagement.ts:1762). Every figure on this screen derives from
//        this one live endpoint — hero $, KPI counts, ladder rows.
//
//  WIRE-GAP (surfaced, honest):
//    · Schedule return → yardManagement.checkOutTrailer EXISTS (:804) but is
//      keyed to a trailer/appointment id this read endpoint does not return;
//      we surface the action with an honest "needs an appointment context"
//      note rather than firing a malformed mutation.
//    · Dispute → STUB · vessel-detention-dispute-mutation. There is NO
//      detentionDispute.create proc yet (today disputes are filed manually
//      with the carrier). We render the CTA and an honest "filed manually
//      with carrier" acknowledgement — NO fabricated disputeId.
//
//  RBAC: getDetentionTracking is protectedProcedure. NO mock data — empty /
//  loading / error states are real; an empty board renders "no detention
//  accruing" rather than fabricated rows.
//

import SwiftUI

struct VesselDetentionTrackingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselDetentionTrackingBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (yardManagement.getDetentionTracking)

/// Top-level response: ladder rows + summary rollup.
private struct DetentionTrackingResponse784: Decodable {
    let records: [DetentionRecord784]
    let summary: DetentionSummary784?
}

/// One equipment row in the accrual ladder. Numeric columns may serialize as
/// quoted strings (DECIMAL) — decode defensively.
private struct DetentionRecord784: Decodable, Identifiable {
    let id: String
    let trailerNumber: String?
    let carrierName: String?
    let loadId: String?
    let arrivalTime: String?
    let freeTimeHours: Double?
    let totalTimeHours: Double?
    let detentionHours: Double?
    let rate: Double?
    let accruedCharge: Double?
    let status: String?   // "critical" | "warning" | "normal"
    let type: String?     // "loading" | "unloading"

    private enum CodingKeys: String, CodingKey {
        case id, trailerNumber, carrierName, loadId, arrivalTime
        case freeTimeHours, totalTimeHours, detentionHours, rate
        case accruedCharge, status, type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            id = UUID().uuidString
        }
        trailerNumber = try? c.decode(String.self, forKey: .trailerNumber)
        carrierName   = try? c.decode(String.self, forKey: .carrierName)
        loadId        = try? c.decode(String.self, forKey: .loadId)
        arrivalTime   = try? c.decode(String.self, forKey: .arrivalTime)
        freeTimeHours  = DetentionRecord784.decodeDouble(c, .freeTimeHours)
        totalTimeHours = DetentionRecord784.decodeDouble(c, .totalTimeHours)
        detentionHours = DetentionRecord784.decodeDouble(c, .detentionHours)
        rate           = DetentionRecord784.decodeDouble(c, .rate)
        accruedCharge  = DetentionRecord784.decodeDouble(c, .accruedCharge)
        status = try? c.decode(String.self, forKey: .status)
        type   = try? c.decode(String.self, forKey: .type)
    }

    private static func decodeDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let i = try? c.decode(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

private struct DetentionSummary784: Decodable {
    let activeDetentions: Int?
    let totalAccruedCharges: Double?
    let avgDetentionHours: Double?
    let criticalCount: Int?

    private enum CodingKeys: String, CodingKey {
        case activeDetentions, totalAccruedCharges, avgDetentionHours, criticalCount
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeDetentions = try? c.decode(Int.self, forKey: .activeDetentions)
        if let d = try? c.decode(Double.self, forKey: .totalAccruedCharges) {
            totalAccruedCharges = d
        } else if let s = try? c.decode(String.self, forKey: .totalAccruedCharges) {
            totalAccruedCharges = Double(s)
        } else { totalAccruedCharges = nil }
        if let d = try? c.decode(Double.self, forKey: .avgDetentionHours) {
            avgDetentionHours = d
        } else if let s = try? c.decode(String.self, forKey: .avgDetentionHours) {
            avgDetentionHours = Double(s)
        } else { avgDetentionHours = nil }
        criticalCount = try? c.decode(Int.self, forKey: .criticalCount)
    }
}

// MARK: - Body

private struct VesselDetentionTrackingBody: View {
    @Environment(\.palette) private var palette

    @State private var records: [DetentionRecord784] = []
    @State private var summary: DetentionSummary784? = nil

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var syncedAt: Date? = nil

    // Schedule-return CTA — honest wire-gap surface (no appointment context
    // returned by the read endpoint, so we don't fire a malformed mutation).
    @State private var scheduleNote: String? = nil

    // Dispute CTA — STUB (vessel-detention-dispute-mutation). No proc yet;
    // surface an honest manual-filing acknowledgement, never a fake disputeId.
    @State private var disputeAck: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Brand.danger)
                                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            }
                        }
                    } else {
                        heroCard
                        kpiStrip
                        accrualLadderSection
                        contextStrip
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + back + title + terminal/sync)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · DETENTION")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("PER DIEM")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Detention")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LBCT USLGB")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(syncedLabel)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, Space.s4)
        }
        .padding(.top, Space.s5)
    }

    private var syncedLabel: String {
        guard let syncedAt else { return "syncing…" }
        let mins = Int(max(0, Date().timeIntervalSince(syncedAt)) / 60)
        if mins <= 0 { return "synced just now" }
        if mins == 1 { return "synced 1m ago" }
        return "synced \(mins)m ago"
    }

    // MARK: - Hero card (gradient rim + total owed + accrual bar)

    private var heroCard: some View {
        let owed = summary?.totalAccruedCharges ?? records.reduce(0) { $0 + ($1.accruedCharge ?? 0) }
        let overCount = overRecords.count
        let carrier = primaryCarrier
        let perDiem = primaryRate
        let highest = highestRecord

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: Space.s3) {
                // Status + carrier chips.
                HStack(spacing: Space.s2) {
                    chip(text: owed > 0 ? "ACCRUING" : "CLEAR",
                         tint: owed > 0 ? Brand.danger : Brand.success)
                    if let carrier { chip(text: carrier.uppercased(), tint: Brand.rail) }
                    Spacer(minLength: 0)
                }

                // Money figure + sub-lines.
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text(currency(owed))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(overCount > 0
                             ? "owed · \(overCount) box\(overCount == 1 ? "" : "es") over FT"
                             : "owed · within free time")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(accrualSubLine(perDiem: perDiem))
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }

                // Accrual progress bar — fraction = over-records / total active.
                GeometryReader { geo in
                    let frac = accrualFraction
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textTertiary.opacity(0.18))
                            .frame(height: 6)
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(6, geo.size.width * frac), height: 6)
                    }
                }
                .frame(height: 6)
            }
            // HIGHEST column (top-right overlay).
            VStack(alignment: .trailing, spacing: 4) {
                Text("HIGHEST")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(highest.map { highestLabel($0) } ?? "—")
                    .font(EType.mono(.body))
                    .foregroundStyle(highest != nil ? Brand.danger : palette.textSecondary)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s5)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.5)
        )
    }

    private func chip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.16)))
    }

    private func accrualSubLine(perDiem: Double?) -> String {
        var parts: [String] = []
        if let perDiem, perDiem > 0 {
            parts.append("rate \(currency(perDiem))/hr")
        }
        let todayAccrual = overRecords.reduce(0.0) { $0 + (($1.detentionHours ?? 0) * ($1.rate ?? 0)) }
        if todayAccrual > 0 {
            parts.append("accrued \(currency(todayAccrual))")
        }
        if parts.isEmpty { return "no per-diem accruing" }
        return parts.joined(separator: " · ")
    }

    private func highestLabel(_ r: DetentionRecord784) -> String {
        let h = r.detentionHours ?? 0
        let hStr = h >= 1 ? "\(Int(h.rounded()))h" : String(format: "%.1fh", h)
        return "\(hStr) / \(currency(r.accruedCharge ?? 0))"
    }

    // MARK: - KPI strip (OVER FREE · AT RISK · WITHIN FREE)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // OVER FREE — gradient-fill tile.
            VStack(alignment: .leading, spacing: 6) {
                Text("OVER FREE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(overRecords.count)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiTile(label: "AT RISK",     value: "\(atRiskRecords.count)", accent: Brand.info)
            kpiTile(label: "WITHIN FREE", value: "\(withinFreeRecords.count)", accent: Brand.success)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func kpiTile(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Equipment accrual ladder

    private var accrualLadderSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("EQUIPMENT · ACCRUAL LADDER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getDetentionTracking")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, Space.s1)

            VStack(spacing: 0) {
                if records.isEmpty {
                    emptyLadderRow
                } else {
                    let ladder = sortedLadder
                    ForEach(Array(ladder.enumerated()), id: \.element.id) { idx, r in
                        ladderRow(r)
                        if idx < ladder.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
            }
            .padding(.vertical, Space.s1)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var emptyLadderRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.success.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.success)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("No detention accruing")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("all equipment within free time")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text("CLEAR")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Brand.success.opacity(0.12)))
        }
        .padding(Space.s4)
    }

    private func ladderRow(_ r: DetentionRecord784) -> some View {
        let bucket = rowBucket(r)
        let color = bucket.color
        let det = r.detentionHours ?? 0

        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: bucket.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(rowTitle(r))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: Space.s2)
                    Text(bucket.label)
                        .font(.system(size: 11, weight: .bold)).tracking(0.4)
                        .foregroundStyle(color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(0.14)))
                }
                Text(rowSubLine(r))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            // Right value: $ accrued for over/at-risk, "no charge" within free.
            Text(det > 0 || (r.accruedCharge ?? 0) > 0
                 ? currency(r.accruedCharge ?? 0)
                 : "no charge")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(det > 0 || (r.accruedCharge ?? 0) > 0 ? color : palette.textTertiary)
                .monospacedDigit()
        }
        .padding(Space.s4)
    }

    private func rowTitle(_ r: DetentionRecord784) -> String {
        let box = r.trailerNumber ?? r.loadId ?? "Equipment"
        let det = r.detentionHours ?? 0
        if det <= 0 { return "\(box) · within free" }
        if det < 24 {
            let h = Int(det.rounded())
            return "\(box) · \(h)h over"
        }
        let days = Int((det / 24).rounded())
        return "\(box) · \(days)d over"
    }

    private func rowSubLine(_ r: DetentionRecord784) -> String {
        var parts: [String] = []
        if let arr = r.arrivalTime { parts.append("in \(shortDate(arr))") }
        if let free = r.freeTimeHours { parts.append("free \(Int(free.rounded()))h") }
        if let rate = r.rate, rate > 0 { parts.append("\(currency(rate))/hr") }
        if parts.isEmpty { return "detention record" }
        return parts.joined(separator: " · ")
    }

    private struct LadderBucket { let label: String; let color: Color; let icon: String }

    private func rowBucket(_ r: DetentionRecord784) -> LadderBucket {
        let s = (r.status ?? "").lowercased()
        let det = r.detentionHours ?? 0
        if s == "critical" || det >= 24 {
            return LadderBucket(label: "OVER", color: Brand.danger, icon: "exclamationmark.circle.fill")
        }
        if s == "warning" || det > 0 {
            // "AT RISK" = small over or approaching the line; use info accent
            // to match the canvas TCLU "AT RISK" treatment.
            return LadderBucket(label: det > 0 ? "OVER" : "AT RISK", color: det > 0 ? Brand.danger : Brand.info,
                                icon: det > 0 ? "exclamationmark.circle.fill" : "clock.fill")
        }
        return LadderBucket(label: "WITHIN", color: Brand.success, icon: "checkmark.circle.fill")
    }

    // MARK: - Context strip

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DETENTION TRACKING · yardManagement")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getDetentionTracking")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("Schedule return → checkOutTrailer · dispute filed with carrier")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(activeContextLine)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var activeContextLine: String {
        let active = summary?.activeDetentions ?? records.count
        let avg = summary?.avgDetentionHours
        var s = "\(active) active"
        if let avg, avg > 0 { s += " · avg \(String(format: "%.1f", avg))h dwell" }
        return s
    }

    // MARK: - CTA row (Schedule return · Dispute)

    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let note = scheduleNote {
                LifecycleCard(accentGradient: true) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(note).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
            }
            if let ack = disputeAck {
                LifecycleCard(accentWarning: true) {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.warning)
                        Text(ack).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
            }
            HStack(spacing: Space.s2) {
                Button {
                    // WIRE-GAP: checkOutTrailer needs a trailer/appointment id
                    // this read endpoint does not surface. Surface honestly
                    // rather than fire a malformed mutation.
                    scheduleNote = records.isEmpty
                        ? "Nothing accruing to schedule a return for."
                        : "Open the box in Shipments to pick a return appointment — checkOutTrailer needs the gate slot."
                    disputeAck = nil
                } label: {
                    Text("Schedule return")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(LinearGradient.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button {
                    // STUB: vessel-detention-dispute-mutation does not exist.
                    // Today disputes are filed manually with the carrier — say so.
                    let carrier = primaryCarrier ?? "the carrier"
                    disputeAck = "Dispute prepared. No in-app filing yet — raise with \(carrier) directly; export the ladder as backup."
                    scheduleNote = nil
                } label: {
                    Text("Dispute")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: 148, minHeight: 48)
                        .frame(maxWidth: .infinity)
                        .background(palette.bgCard)
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Derived buckets

    /// "Over free" — detention hours accrued (or critical/warning status).
    private var overRecords: [DetentionRecord784] {
        records.filter { ($0.detentionHours ?? 0) > 0 || ($0.status ?? "").lowercased() == "critical" }
    }
    /// "At risk" — flagged warning but not yet over.
    private var atRiskRecords: [DetentionRecord784] {
        records.filter { ($0.detentionHours ?? 0) <= 0 && ($0.status ?? "").lowercased() == "warning" }
    }
    /// "Within free" — normal status, no detention accrued.
    private var withinFreeRecords: [DetentionRecord784] {
        records.filter { ($0.detentionHours ?? 0) <= 0 && ($0.status ?? "").lowercased() != "warning" }
    }

    private var sortedLadder: [DetentionRecord784] {
        // Worst first: highest detention hours / accrued charge at the top.
        records.sorted {
            ($0.detentionHours ?? 0, $0.accruedCharge ?? 0) >
            ($1.detentionHours ?? 0, $1.accruedCharge ?? 0)
        }
    }

    private var highestRecord: DetentionRecord784? {
        records.max { ($0.accruedCharge ?? 0) < ($1.accruedCharge ?? 0) }
            .flatMap { ($0.accruedCharge ?? 0) > 0 ? $0 : nil }
    }

    private var primaryCarrier: String? {
        let names = records.compactMap { $0.carrierName }
            .filter { !$0.isEmpty && $0.lowercased() != "unknown" && $0.lowercased() != "unknown carrier" }
        return names.first
    }

    private var primaryRate: Double? {
        records.compactMap { $0.rate }.filter { $0 > 0 }.first
    }

    private var accrualFraction: Double {
        let total = records.count
        guard total > 0 else { return 0 }
        return min(1.0, Double(overRecords.count) / Double(total))
    }

    // MARK: - Formatting

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = (value.rounded() == value) ? 0 : 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func shortDate(_ iso: String) -> String {
        let inFmt = ISO8601DateFormatter()
        inFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = inFmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d else { return String(iso.prefix(10)) }
        let out = DateFormatter()
        out.dateFormat = "MM/dd"
        return out.string(from: d)
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 240)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Load (yardManagement.getDetentionTracking)

    private func load() async {
        loading = true; loadError = nil
        struct DetentionIn: Encodable { let onlyActive: Bool }
        do {
            let resp: DetentionTrackingResponse784 = try await EusoTripAPI.shared.query(
                "yardManagement.getDetentionTracking", input: DetentionIn(onlyActive: true))
            self.records = resp.records
            self.summary = resp.summary
            self.syncedAt = Date()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("784 · Vessel Detention Tracking · Night") {
    VesselDetentionTrackingScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("784 · Vessel Detention Tracking · Light") {
    VesselDetentionTrackingScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
