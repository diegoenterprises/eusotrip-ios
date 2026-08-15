//
//  784_VesselDetentionTracking.swift
//  EusoTrip — Vessel Operator · Detention Tracking.
//
//  Faithful 1:1 port of "784 Vessel Detention Tracking.svg" (Light + Dark),
//  RECONSTRUCTED to the flagship DETAIL/MONEY-TIMELINE grammar (770 /
//  02 Shipper 227 Settlement Detail) per FOUNDER CADENCE DIRECTIVE 2026-05-24
//  — detail header (✦ eyebrow + 28/700 title + synced caption), gradient-rimmed
//  hero ActiveCard ($ accrued figure + ACCRUING chip + highest-accrual right-
//  cluster + accrual progress bar), 3-cell KPI strip (cell-1 eusoDiagonal
//  OVER FREE · AT RISK · WITHIN FREE), itemized equipment-accrual ladder with
//  status-tinted icon chip + trailer/days-over title + LFD/per-hour sub +
//  status pill + right $/time value, ESang next-best-action card + Schedule
//  return / Dispute CTA pair, real Vessel-Operator BottomNav (COMPLIANCE inked
//  — detention is a compliance/accessorial surface). Nav anchored to the same
//  Shell + BottomNav wrapper the registered vessel sibling 757 ships.
//
//  Data / wiring (endpoint MCP-CONFIRMED this fire via EUSOTRIP_PLATFORM):
//    yardManagement.getDetentionTracking
//      (EXISTS frontend/server/routers/yardManagement.ts:1869 · query ·
//       input {locationId?:String, onlyActive?:Bool=true}? ·
//       returns {records:[{id, trailerNumber, carrierName, loadId,
//         arrivalTime:ISO, freeTimeHours, totalTimeHours, detentionHours,
//         rate, accruedCharge, status:"critical"|"warning"|"normal",
//         type:"loading"|"unloading"}],
//       summary:{activeDetentions, totalAccruedCharges, avgDetentionHours,
//         criticalCount}}).
//      The REAL server shape (verified) differs from the canonical port's
//      assumed daysOver/perDiem/over|atRisk|withinFree shape; this port wires
//      the REAL fields and maps them to the wireframe grammar honestly:
//        critical → OVER (≥4h over free) · warning → AT RISK (2–4h) ·
//        normal → WITHIN FREE. Hero $ = totalAccruedCharges; KPI strip counts
//        derived from record status; the highest-accrual record drives the
//        hero right-cluster + ESang next-best-action. When db is null or no
//        active detentions, the server returns an empty ledger — the bespoke
//        empty state renders honestly, no fabricated rows.
//    "Schedule return" -> yardManagement.checkOutTrailer (EXISTS) closes a
//      checked-in yard appointment and, when loadId is present, closes the active detention record.
//    "Dispute" -> detentionAccessorials.disputeDetention (EXISTS) for claim-backed rows;
//      geofence-only detention rows show an honest unavailable message until a claim exists.
//
//  RimCard784 grammar is inlined via ActiveCard (shared gradient-rim hero);
//  the file-scoped helpers (secondaryButton784, EmptyInput784) suffix the
//  screen number to avoid cross-file private collisions, built from sibling
//  757's grammar.
//

import SwiftUI

struct VesselDetentionTrackingScreen: View {
    let theme: Theme.Palette
    let onlyActive: Bool
    init(theme: Theme.Palette, onlyActive: Bool = true) {
        self.theme = theme; self.onlyActive = onlyActive
    }
    var body: some View {
        Shell(theme: theme) {
            VesselDetentionTrackingBody(onlyActive: onlyActive)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",      isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Real server shape (yardManagement.getDetentionTracking)

private struct DetentionRecord784: Decodable, Identifiable {
    let id: String
    let detentionRecordId: Int?
    let claimId: Int?
    let trailerNumber: String?
    let carrierName: String?
    let loadId: String?
    let arrivalTime: String?
    let freeTimeHours: Double?
    let totalTimeHours: Double?
    let detentionHours: Double?
    let rate: Double?
    let accruedCharge: Double?
    let status: String?              // critical | warning | normal
    let type: String?                // loading | unloading
}
private struct DetentionSummary784: Decodable {
    let activeDetentions: Int?
    let totalAccruedCharges: Double?
    let avgDetentionHours: Double?
    let criticalCount: Int?
}
private struct DetentionResponse784: Decodable {
    let records: [DetentionRecord784]?
    let summary: DetentionSummary784?
}
private struct OnlyActiveQuery784: Encodable { let onlyActive: Bool }
private struct CheckoutInput784: Encodable {
    let locationId: String
    let trailerNumber: String
    let loadId: String?
    let notes: String?
}
private struct CheckoutResult784: Decodable {
    let success: Bool?
    let checkOutId: String?
    let dwellTimeMinutes: Int?
}
private struct DisputeInput784: Encodable {
    let claimId: Int
    let reason: String
}
private struct DisputeResult784: Decodable {
    let success: Bool?
    let claimId: Int?
    let status: String?
    let message: String?
}

private struct VesselDetentionTrackingBody: View {
    let onlyActive: Bool
    @Environment(\.palette) private var palette
    @State private var data: DetentionResponse784? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var actionInFlight = false

    private let slate = Color(hex: 0x607D8B)
    private let warnText = Color(hex: 0xC2410C)

    // Derived status buckets (real status → wireframe grammar)
    private var records: [DetentionRecord784] { data?.records ?? [] }
    private var overCount: Int  { records.filter { $0.status == "critical" }.count }
    private var atRiskCount: Int { records.filter { $0.status == "warning" }.count }
    private var withinCount: Int { records.filter { ($0.status ?? "normal") == "normal" }.count }
    private var totalAccrued: Double { data?.summary?.totalAccruedCharges ?? 0 }
    private var avgHours: Double { data?.summary?.avgDetentionHours ?? 0 }
    /// Highest-accrual record drives the hero right-cluster + ESang target.
    private var topRecord: DetentionRecord784? {
        records.max { ($0.accruedCharge ?? 0) < ($1.accruedCharge ?? 0) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading detention…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if records.isEmpty {
                    EusoEmptyState(systemImage: "clock.badge.checkmark",
                                   title: "No active detention",
                                   subtitle: "No accruing boxes came back. Nothing is past free time, so there is no per-diem to track right now.")
                } else {
                    heroCard
                    HStack(spacing: 8) {
                        kpiTile("OVER FREE", "\(overCount)", gradient: true)
                        kpiTile("AT RISK", "\(atRiskCount)", tint: Brand.info)
                        kpiTile("WITHIN FREE", "\(withinCount)", tint: Brand.success)
                    }
                    accrualList
                    esangCard
                    HStack(spacing: 8) {
                        CTAButton(title: actionInFlight ? "Working…" : "Schedule return", action: { Task { await scheduleReturn() } }, trailingIcon: "arrow.uturn.left")
                        secondaryButton784(title: "Dispute") { Task { await dispute() } }
                            .frame(width: 130)
                    }
                    if let error = actionError {
                        LifecycleCard(accentDanger: true) {
                            Text(error).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if let message = actionMessage {
                        LifecycleCard {
                            Text(message).font(EType.caption).foregroundStyle(Brand.success)
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DETENTION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("PER DIEM").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Detention").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(records.count) ACTIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Text("synced now").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    chip("ACCRUING", Brand.danger)
                    if let carrier = topRecord?.carrierName, !carrier.isEmpty {
                        chip(carrier.uppercased(), slate)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("HIGHEST").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        Text(highestLabel).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(warnText)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(money(totalAccrued)).font(.system(size: 32, weight: .heavy)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("accrued · \(overCount) boxes over FT").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text("avg detention \(hours(avgHours)) · \(atRiskCount) at risk").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    }
                }
                progressBar(accrualFraction)
            }
        }
    }

    private var highestLabel: String {
        guard let r = topRecord else { return "-" }
        return "\(hours(r.detentionHours ?? 0)) / \(money(r.accruedCharge ?? 0))"
    }
    private var accrualFraction: Double {
        let total = max(1, records.count)
        return min(1.0, Double(overCount) / Double(total))
    }

    // MARK: Accrual ladder

    private var accrualList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("EQUIPMENT · ACCRUAL LADDER", "ACTIVE · \(overCount) OVER")
            let sorted = records.sorted { ($0.accruedCharge ?? 0) > ($1.accruedCharge ?? 0) }
            VStack(spacing: 0) {
                ForEach(Array(sorted.prefix(3).enumerated()), id: \.element.id) { idx, r in
                    accrualRow(r)
                    if idx < min(2, sorted.count - 1) { Divider().overlay(palette.borderFaint) }
                }
                Text(footer(sorted))
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10).padding(.horizontal, 16).padding(.bottom, 4)
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func accrualRow(_ r: DetentionRecord784) -> some View {
        let status = r.status ?? "normal"
        let iconSys: String
        let tint: Color
        let pillText: String
        let valueText: String
        switch status {
        case "critical":
            iconSys = "minus.circle"; tint = Brand.danger; pillText = "OVER"; valueText = money(r.accruedCharge ?? 0)
        case "warning":
            iconSys = "clock"; tint = Brand.info; pillText = "AT RISK"; valueText = hours(r.detentionHours ?? 0)
        default:
            iconSys = "checkmark.circle"; tint = Brand.success; pillText = "OK"
            let remaining = max(0, (r.freeTimeHours ?? 0) - (r.totalTimeHours ?? 0))
            valueText = "\(hours(remaining)) left"
        }
        return HStack(spacing: 12) {
            iconChip(iconSys, tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(r)).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(rowSub(r)).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                pill(pillText, tint)
                Text(valueText).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(tint == Brand.danger ? warnText : tint)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func rowTitle(_ r: DetentionRecord784) -> String {
        let trailer = r.trailerNumber ?? r.loadId ?? "-"
        switch r.status ?? "normal" {
        case "critical": return "\(trailer) · \(hours(r.detentionHours ?? 0)) over"
        case "warning":  return "\(trailer) · approaching LFD"
        default:         return "\(trailer) · within free"
        }
    }
    private func rowSub(_ r: DetentionRecord784) -> String {
        let perHour = "$\(Int(r.rate ?? 0))/h"
        switch r.status ?? "normal" {
        case "critical": return "\(r.type == "loading" ? "loading" : "unloading") · per-hour \(perHour)"
        case "warning":  return "free \(hours(r.freeTimeHours ?? 0)) · dwell \(hours(r.totalTimeHours ?? 0))"
        default:         return "dwell \(hours(r.totalTimeHours ?? 0)) of \(hours(r.freeTimeHours ?? 0)) free · no charge"
        }
    }
    private func footer(_ recs: [DetentionRecord784]) -> String {
        let rest = recs.dropFirst(3).count
        return rest == 0 ? "All records shown" : "+ \(rest) more rows · sorted highest-accrual first"
    }

    // MARK: ESang next-best-action

    private var esangCard: some View {
        let target = records.first { $0.status == "warning" } ?? topRecord
        let title: String = target.map { r in
            let t = r.trailerNumber ?? r.loadId ?? "the top box"
            return (r.status == "warning") ? "Return \(t) before it passes LFD" : "Return \(t) - your highest-accruing box"
        } ?? "Return the highest-accruing box first"
        let detail: String = target.map { r in
            (r.status == "warning")
                ? "\(hours(r.detentionHours ?? 0)) over free - stops a new $\(Int(r.rate ?? 0))/h charge"
                : "\(money(r.accruedCharge ?? 0)) accrued at $\(Int(r.rate ?? 0))/h"
        } ?? "\(money(totalAccrued)) accruing across \(overCount) boxes"

        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 18)).frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG AI").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: Formatting

    private func money(_ v: Double) -> String { "$\(Int(v).formatted(.number.grouping(.automatic)))" }
    private func hours(_ v: Double) -> String {
        if v >= 1 { return String(format: "%.1fh", v) }
        return "\(Int((v * 60).rounded()))m"
    }

    // MARK: Inline primitives

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 11, weight: .bold)).foregroundStyle(c)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(c.opacity(0.14)))
    }
    private func pill(_ t: String, _ c: Color) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(c)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(c.opacity(0.14)))
    }
    private func iconChip(_ s: String, _ c: Color) -> some View {
        Image(systemName: s).font(.system(size: 16, weight: .semibold)).foregroundStyle(c)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(c.opacity(0.14)))
    }
    private func kpiTile(_ l: String, _ v: String, tint: Color? = nil, gradient: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(v).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(gradient ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint ?? palette.textPrimary))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(gradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(gradient ? Color.clear : palette.borderFaint, lineWidth: 1))
    }
    private func progressBar(_ f: Double) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textPrimary.opacity(0.08)).frame(height: 6)
                Capsule().fill(LinearGradient.diagonal).frame(width: max(0, min(1, f)) * g.size.width, height: 6)
            }
        }
        .frame(height: 6)
    }
    private func sectionLabel(_ t: String, _ tr: String) -> some View {
        HStack {
            Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(tr).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar the
    /// registered sibling (757) uses for its secondary CTA.
    private func secondaryButton784(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Load + write verbs

    private func load() async {
        loading = true; loadError = nil
        do {
            self.data = try await EusoTripAPI.shared.query("yardManagement.getDetentionTracking", input: OnlyActiveQuery784(onlyActive: onlyActive))
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func scheduleReturn() async {
        guard !actionInFlight else { return }
        actionMessage = nil; actionError = nil
        guard let target = topRecord, let trailer = target.trailerNumber, trailer.isEmpty == false else {
            actionError = "No active trailer row is available to return."
            return
        }
        actionInFlight = true
        do {
            let result: CheckoutResult784 = try await EusoTripAPI.shared.mutation(
                "yardManagement.checkOutTrailer",
                input: CheckoutInput784(locationId: "vessel-detention",
                                        trailerNumber: trailer,
                                        loadId: target.loadId,
                                        notes: "Scheduled return from Vessel Detention Tracking"))
            if result.success == true {
                actionMessage = "Return recorded \(result.checkOutId ?? "") · dwell \(hours(Double(result.dwellTimeMinutes ?? 0) / 60))."
                await load()
            } else {
                actionError = "Return did not confirm. Reopen the trailer row and try again."
            }
        } catch {
            actionError = error.eusoUserCopy
        }
        actionInFlight = false
    }

    private func dispute() async {
        guard !actionInFlight else { return }
        actionMessage = nil; actionError = nil
        guard let target = topRecord else {
            actionError = "No detention row is available to dispute."
            return
        }
        guard let claimId = target.claimId else {
            actionError = "This is a geofence-only detention row. A billable claim must exist before a dispute can be filed."
            return
        }
        actionInFlight = true
        do {
            let result: DisputeResult784 = try await EusoTripAPI.shared.mutation(
                "detentionAccessorials.disputeDetention",
                input: DisputeInput784(claimId: claimId,
                                       reason: "Operator disputes vessel detention charge from tracking screen pending appointment, gate, and free-time evidence review."))
            if result.success == true {
                actionMessage = result.message ?? "Dispute filed for claim \(result.claimId ?? claimId)."
                await load()
            } else {
                actionError = "Dispute did not confirm. Reopen the charge and try again."
            }
        } catch {
            actionError = error.eusoUserCopy
        }
        actionInFlight = false
    }
}

#Preview("784 · Vessel Detention Tracking · Night") { VesselDetentionTrackingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("784 · Vessel Detention Tracking · Light") { VesselDetentionTrackingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
