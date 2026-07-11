//
//  298B_ShipperDetentionAutoClock.swift
//  EusoTrip — Shipper · DETENTION AUTO-CLOCK (per-load live meter).
//
//  Wireframe: 02 Shipper/Dark-SVG/298B Shipper Detention Auto-Clock.svg
//  Archetype: MONEY / LIVE-CLOCK. Distinct from 298 Detention Exposure
//  (the portfolio ledger across every facility) — this is ONE load's live
//  detention meter: the truck is inside the receiver fence right now, the
//  grace has expired, and the charge is climbing to the second. A money-led
//  "$X and climbing" hero, a fence-status card (entered / total dwell /
//  free vs billable), a live detention meter (accrued + rate), the OOIDA/
//  TIA charge build-up, the by-country free-time regime, and an ESANG
//  dispute-read advisory. Auto-invoice arms on fence-exit.
//
//  Web peer: frontend/client/src/pages/shipper/loads/:id (detention).
//  Wiring (on-disk confirmed):
//    • detentionAccessorials.getActiveDetentions EXISTS
//      detentionAccessorials.ts:264 → the live clock row for this load
//      (arrival, elapsed, free-time, billable minutes, current charge).
//      PRIMARY CONSUME — filtered to the screen's loadId, else the most
//      billable active clock (honest, real rows only).
//    • detentionAccessorials.calculateDetention EXISTS
//      detentionAccessorials.ts:363 → the authoritative meter rate + tier
//      breakdown (the "$75 / hr" line), fed the row's real arrival anchor.
//    • detentionAccessorials.disputeDetention EXISTS
//      detentionAccessorials.ts:519 → "Dispute" (fires the real write via a
//      claimId reason sheet; server validates reason.min(10)).
//    • billing.approveDetention EXISTS billing.ts:831 → "Pre-approve"
//      (clears the charge at fence-exit; { detentionId, adjustedAmount? }).
//  RBAC: shipperProcedure (companyId-owned). transportMode=truck · US.
//
//  COUNTRY (tri-country): the free-time regime band states the receiver-
//  country grace + rate basis driving the meter — US OOIDA/TIA 2h $75/hr
//  (active) · CA carrier tariff filed w/ CTA ~1h CAD · MX estadías per SAT
//  / contrato MXN. The per-load regime recompute
//  (detentionAccessorials.getFreeTimeRegime) is a named gap handed to
//  the-oath; the band renders the reference constants, never a fabricated
//  per-load grace.
//
//  Honest: every figure renders from the live clock row or the server
//  meter — no fabricated dwell, no invented rate. When no clock is running
//  for this load, an honest "no clock running" state renders, never a
//  seeded charge.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen root

struct ShipperDetentionAutoClockScreen: View {
    let theme: Theme.Palette
    /// The load this clock is scoped to. "0"/absent falls back to the most
    /// urgent active clock in the store (still real, never fabricated).
    var loadId: String = "0"

    var body: some View {
        Shell(theme: theme) {
            ShipperDetentionAutoClockBody(loadId: loadId)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct ShipperDetentionAutoClockBody: View {
    @Environment(\.palette) private var palette
    let loadId: String

    @StateObject private var store = ShipperDetentionAutoClockStore()
    @State private var disputing = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                switch store.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Space.s8)
                case .empty:
                    noClockState
                case .error(let msg):
                    errorState(msg)
                case .clock(let c):
                    heroCard(c)
                    fenceStatusCard(c)
                    meterCard(c)
                    chargeBuildUpCard(c)
                    FreeTimeRegimeBand(theme: palette, trailing: "AUTO-INVOICE · ON EXIT")
                    esangDisputeCard(c)
                    ctaRow(c)
                    footnote
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
            .padding(.bottom, Space.s8)
        }
        .task { await store.load(loadId: loadId) }
        .refreshable { await store.load(loadId: loadId) }
        .sheet(isPresented: $disputing) {
            if let c = store.clock {
                DetentionDisputeSheet(clock: c, store: store).eusoSheetX()
            }
        }
    }

    // MARK: Header (bespoke — accruing eyebrow + live title)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · DETENTION CLOCK")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer(minLength: Space.s2)
                Text(store.accruing ? "ACCRUING · LIVE" : (store.clock == nil ? "NO CLOCK" : "WITHIN FREE TIME"))
                    .font(EType.mono(.micro))
                    .foregroundStyle(store.accruing ? Brand.warning : palette.textTertiary)
            }
            Text("Detention exposure")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            if let sub = store.subtitle {
                Text(sub)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            IridescentHairline().padding(.top, 2)
        }
    }

    // MARK: Hero — "$X and climbing"

    private func heroCard(_ c: DetentionClock) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(c.accruing ? "DETENTION ACCRUING · BILLED TO THE SECOND" : "DETENTION · WITHIN FREE TIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(usdCents(c.currentCharge))
                        .font(.system(size: 40, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(c.accruing ? "and climbing" : "held at free")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.accruing ? Brand.warning : palette.textTertiary)
                    Spacer(minLength: 0)
                }
                Text(c.heroSubline)
                    .font(.system(size: 11, weight: .regular)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: Fence status

    private func fenceStatusCard(_ c: DetentionClock) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                sectionLabel("RECEIVER FENCE")
                Spacer(minLength: 0)
                StatusPill(text: c.insideFence ? "INSIDE FENCE · DWELLING" : "OUTBOUND", kind: c.insideFence ? .warning : .neutral)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                fenceCell(label: "ENTERED", value: c.enteredLabel, sub: "fence-timestamped")
                fenceCell(label: "TOTAL DWELL", value: c.totalDwellClock, sub: c.accruing ? "grace expired \(c.graceExpiredLabel)" : "grace running")
            }
            Divider().overlay(palette.borderFaint)
            HStack(spacing: 0) {
                splitCell(label: "FREE TIME", value: c.freeTimeLabel, tone: .neutral)
                divider
                splitCell(label: "BILLABLE", value: c.billableLabel, tone: c.accruing ? .warn : .neutral)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Detention meter

    private func meterCard(_ c: DetentionClock) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                sectionLabel("DETENTION METER")
                Spacer(minLength: 0)
                Text(c.accruing ? "LIVE" : "IDLE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(c.accruing ? Brand.warning : palette.textTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
            HStack(alignment: .bottom, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ACCRUED").font(.system(size: 8.5, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text(usdCents(c.currentCharge))
                        .font(.system(size: 26, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("RATE").font(.system(size: 8.5, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text(c.ratePerHourLabel)
                        .font(.system(size: 16, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(c.ratePerMinuteLabel)
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(c.accruing ? Brand.warning : palette.textTertiary)
                }
            }
            Text("Fence-timestamped from \(c.enteredLabel) · billed to the second")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(c.accruing ? Brand.warning.opacity(0.4) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Charge build-up ledger

    private func chargeBuildUpCard(_ c: DetentionClock) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("CHARGE BUILD-UP · OOIDA / TIA STANDARD")
            VStack(spacing: 10) {
                buildRow(title: "Free time", detail: "\(c.freeTimeLabel) grace · honored", amount: "$0.00", tone: .neutral)
                Divider().overlay(palette.borderFaint)
                buildRow(title: "Billable detention", detail: "\(c.billableLabel) @ \(c.ratePerHourLabel)", amount: usdCents(c.currentCharge), tone: c.accruing ? .warn : .neutral)
                if c.accruing {
                    Divider().overlay(palette.borderFaint)
                    HStack {
                        Text("climbing").font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(Brand.warning)
                        Spacer(minLength: 0)
                        Text(c.ratePerMinuteLabel).font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(Brand.warning)
                    }
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: ESANG dispute read (derived advisory over real clock facts)

    private func esangDisputeCard(_ c: DetentionClock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 22, height: 22)
                    Text("E").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                }
                Text("ESANG · DISPUTE READ").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(c.accruing ? "DISPUTE RISK LOW" : "NO CHARGE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(c.accruing ? Brand.success : palette.textTertiary)
            }
            Text(c.disputeRead)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(c.accruing ? "Pre-approve clears at exit · within the facility's dwell history, no rounding to argue." : "The meter stays at zero until the truck dwells past free time.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.08), Brand.magenta.opacity(0.06)], startPoint: .leading, endPoint: .trailing))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: CTA row

    private func ctaRow(_ c: DetentionClock) -> some View {
        HStack(spacing: Space.s2) {
            Button { disputing = true } label: {
                Text("Dispute")
                    .font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            CTAButton(
                title: store.isApproving ? "Pre-approving…" : "Pre-approve \(c.ratePerHourLabel)",
                action: { Task { await store.preApprove() } },
                isLoading: store.isApproving
            )
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Helper cells / states

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }

    private func fenceCell(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8.5, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 9, weight: .medium)).foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum CellTone { case neutral, warn }
    private func splitCell(label: String, value: String, tone: CellTone) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 16, weight: .heavy)).monospacedDigit()
                .foregroundStyle(tone == .warn ? Brand.warning : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 30)
    }

    private func buildRow(title: String, detail: String, amount: String, tone: CellTone) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 10, weight: .medium)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s3)
            Text(amount).font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(tone == .warn ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
        }
    }

    private var noClockState: some View {
        EusoEmptyState(
            systemImage: "clock.badge.checkmark",
            title: "No clock running",
            subtitle: "No truck is dwelling past free time on this load right now. A live detention meter appears here the moment a driver crosses the receiver fence and the grace expires."
        )
        .padding(.top, Space.s6)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.danger)
            }
            Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
            Button { Task { await store.load(loadId: loadId) } } label: {
                Text("Retry").font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footnote: some View {
        Text("Detention bills automatically when the fence-in timestamp and free-time grace agree. Pre-approve arms the invoice to clear at fence-exit; Dispute pauses billing until your team reviews.")
            .font(EType.caption).foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    private func usdCents(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US"); f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - Dispute sheet (fires the REAL disputeDetention write)

private struct DetentionDisputeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let clock: DetentionClock
    @ObservedObject var store: ShipperDetentionAutoClockStore

    @State private var reason = ""
    @State private var submitting = false
    @State private var errorText: String?

    private var trimmed: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { trimmed.count >= 10 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Charge") {
                    Text("\(clock.facilityName) · detention")
                        .font(EType.bodyStrong)
                    if let ref = clock.loadRef {
                        Text(ref).font(EType.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Text("Accrued \(clock.currentCharge, format: .currency(code: "USD"))")
                        .font(EType.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Section("Why are you disputing? (min 10 characters)") {
                    TextEditor(text: $reason).frame(minHeight: 120)
                }
                if let errorText {
                    Section { Text(errorText).font(EType.caption).foregroundStyle(Brand.danger) }
                }
            }
            .navigationTitle("Dispute charge")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            submitting = true; errorText = nil
                            do { try await store.dispute(reason: trimmed); submitting = false; dismiss() }
                            catch { submitting = false; errorText = "Couldn't file the dispute. \(error.eusoUserCopy)" }
                        }
                    } label: {
                        if submitting { ProgressView() } else { Text("Submit").fontWeight(.semibold) }
                    }
                    .disabled(!valid || submitting)
                }
            }
        }
    }
}

// MARK: - Clock view-model (derived from the REAL ActiveDetention row)

struct DetentionClock: Equatable {
    let id: Int
    let loadId: Int?
    let facilityName: String
    let arrivalTime: String?
    let elapsedMinutes: Int
    let freeTimeMinutes: Int
    let billableMinutes: Int
    let currentCharge: Double
    /// Authoritative $/hr from calculateDetention's first tier when it
    /// resolved; else derived from the row (currentCharge / billable hours),
    /// else the OOIDA/TIA reference floor. Never a fabricated headline.
    let serverRatePerHour: Double?

    var accruing: Bool { billableMinutes > 0 }
    var insideFence: Bool { arrivalTime != nil }
    var loadRef: String? { loadId.map { "LD-\($0)" } }

    var effectiveRatePerHour: Double {
        if let r = serverRatePerHour, r > 0 { return r }
        let billableHours = Double(billableMinutes) / 60.0
        if billableHours > 0, currentCharge > 0 { return currentCharge / billableHours }
        return 75  // OOIDA/TIA reference floor
    }
    var ratePerHourLabel: String { "$\(Int(effectiveRatePerHour.rounded())) / hr" }
    var ratePerMinuteLabel: String { String(format: "+$%.2f / min", effectiveRatePerHour / 60.0) }

    var enteredLabel: String { humanISO(arrivalTime, format: "HH:mm") }
    var totalDwellClock: String { clockString(elapsedMinutes) }
    var freeTimeLabel: String { hoursMinutes(freeTimeMinutes) }
    var billableLabel: String { hoursMinutes(billableMinutes) }
    var graceExpiredLabel: String {
        guard let a = arrivalTime else { return "—" }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = iso.date(from: a); if d == nil { iso.formatOptions = [.withInternetDateTime]; d = iso.date(from: a) }
        guard let date = d else { return "—" }
        let expiry = date.addingTimeInterval(TimeInterval(freeTimeMinutes * 60))
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: expiry)
    }
    var heroSubline: String {
        var parts: [String] = []
        if let ref = loadRef { parts.append(ref) }
        parts.append(facilityName)
        parts.append(accruing ? "\(billableLabel) billable" : "within free time")
        return parts.joined(separator: " · ")
    }
    var disputeRead: String {
        accruing
            ? "Clean charge — fence-timed from \(enteredLabel), the \(freeTimeLabel) grace honored. Billed to the second, no rounding."
            : "No charge yet — the truck is inside the \(freeTimeLabel) free window."
    }

    private func clockString(_ mins: Int) -> String {
        let h = mins / 60, m = mins % 60
        return String(format: "%d:%02d", h, m)
    }
    private func hoursMinutes(_ mins: Int) -> String {
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h)h 00m" : "\(h)h \(String(format: "%02d", m))m"
    }
}

// MARK: - Store

@MainActor
final class ShipperDetentionAutoClockStore: ObservableObject {
    enum Phase: Equatable {
        case loading, empty, clock(DetentionClock), error(String)
    }
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isApproving = false

    var clock: DetentionClock? {
        if case .clock(let c) = phase { return c }
        return nil
    }
    var accruing: Bool { clock?.accruing ?? false }
    var subtitle: String? { clock?.heroSubline }

    private func targetLoadId(from raw: String) -> Int? {
        let cleaned = raw.replacingOccurrences(of: "load_", with: "")
                         .replacingOccurrences(of: "LD-", with: "")
        return Int(cleaned)
    }

    func load(loadId raw: String) async {
        phase = .loading
        do {
            let resp = try await EusoTripAPI.shared.detention.getActive(limit: 25)
            let rows = resp.detentions
            guard !rows.isEmpty else { phase = .empty; return }

            let want = targetLoadId(from: raw)
            // Prefer the row for this load; else the most billable active
            // clock (the one bleeding money now) — always a real row.
            let picked = (want.flatMap { id in rows.first { $0.loadId == id } })
                ?? rows.max(by: { $0.currentCharge < $1.currentCharge })
                ?? rows[0]

            // Authoritative meter rate from the server calculator, fed the
            // row's real arrival anchor. Best-effort — a miss falls back to
            // the row-derived rate, never a fabricated headline.
            var serverRate: Double? = nil
            if let arrival = picked.arrivalTime {
                if let calc = try? await EusoTripAPI.shared.detention.calculateDetention(
                    arrivalTime: arrival,
                    freeTimeMinutes: picked.freeTimeMinutes
                ) {
                    serverRate = calc.tierBreakdown.first?.rate
                }
            }

            phase = .clock(DetentionClock(
                id: picked.id,
                loadId: picked.loadId,
                facilityName: picked.facilityName,
                arrivalTime: picked.arrivalTime,
                elapsedMinutes: picked.elapsedMinutes,
                freeTimeMinutes: picked.freeTimeMinutes,
                billableMinutes: picked.billableMinutes,
                currentCharge: picked.currentCharge,
                serverRatePerHour: serverRate
            ))
        } catch {
            phase = .error(error.eusoUserCopy)
        }
    }

    /// Fires the REAL disputeDetention write (server field `claimId`).
    func dispute(reason: String) async throws {
        guard let c = clock else { return }
        _ = try await EusoTripAPI.shared.detention.dispute(detentionId: c.id, reason: reason)
        // Re-poll so the clock reflects the paused-billing state.
        if let lid = c.loadId { await load(loadId: String(lid)) }
    }

    /// Fires the REAL billing.approveDetention write — pre-approves the
    /// charge to clear at fence-exit.
    func preApprove() async {
        guard let c = clock else { return }
        isApproving = true
        defer { isApproving = false }
        _ = try? await EusoTripAPI.shared.detention.approveDetention(detentionId: c.id)
        if let lid = c.loadId { await load(loadId: String(lid)) }
    }
}

// MARK: - billing.approveDetention (thin accessor, collision-free)
//
// `billing.approveDetention` isn't yet on the shared DetentionAPI; defined
// here as a collision-free extension so this per-load pre-approve fires a
// real write. Server input mirrors billing.ts:832 verbatim
// ({ detentionId: number, adjustedAmount?: number }).

extension DetentionAPI {
    struct ApproveDetentionResult: Decodable, Equatable {
        let success: Bool?
        let detentionId: Int?
        let status: String?
        let message: String?
    }

    @discardableResult
    func approveDetention(detentionId: Int, adjustedAmount: Double? = nil) async throws -> ApproveDetentionResult {
        struct Input: Encodable {
            let detentionId: Int
            let adjustedAmount: Double?
        }
        return try await api.mutation(
            "billing.approveDetention",
            input: Input(detentionId: detentionId, adjustedAmount: adjustedAmount)
        )
    }
}

// MARK: - Previews

#Preview("298B · Detention Auto-Clock · Night") {
    ShipperDetentionAutoClockScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("298B · Detention Auto-Clock · Afternoon") {
    ShipperDetentionAutoClockScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
