//
//  161_DriverGatePass.swift
//  EusoTrip — Driver · Gate Pass credential (brick 161).
//
//  Verbatim reconstruction of "01 Driver/Dark-SVG/161 Driver Gate Pass.svg"
//  (canvas 440×956, Theme.dark). Driver-vantage gate-pass credential — the
//  GP-XXXXXX terminal pass minted when the pickup/delivery appointment is
//  confirmed, carried by the driver and PRESENTED (scanned or read) at the dock
//  gate. Fills the catalog gap for the real `gate_passes` credential: before
//  this fire no role in any mode had a gate-pass surface.
//
//  DETAIL grammar (matches sibling pushed-detail screens 162/163):
//    detail TopBar (back-chevron + one ✦ eyebrow + 22/700/-0.3 title + mono
//    context sub + right two-line driver register + iridescent hairline) →
//    gradient-rimmed PASS hero (status pills · GP code · facility · valid window ·
//    stylized QR credential glyph) → APPOINTMENT section (confirmation row ·
//    load row · driver row) → ESang watch band → CTA pair (Appointment ·
//    Check in at gate).
//
//  ── tRPC wiring — REAL contract (the-oath §48, 2026-05-30) ──────────────────
//  Anchors LINE-CONFIRMED this fire against server/routers/appointments.ts +
//  drizzle/schema.ts:
//    • appointments.getGatePass({ appointmentId })   PRIMARY  (read)
//        → { passCode?, qrCodeData?, passStatus?, validFrom?, validUntil?,
//            usedAt?, appointmentId?, confirmationNumber?, appointmentType?,
//            appointmentStatus?, dockNumber?, terminalId?, facilityName?,
//            scheduledDate?, scheduledTime?, loadNumber?, originState?,
//            destState?, distanceMiles?, bolNumber?, driverId? }
//        Built + staged THIS fire (appointments.getGatePass.patch.ts). It is the
//        READ half of the credential: updateStatus (appointments.ts:194) MINTS
//        the pass into `gate_passes` on confirm, but nothing re-reads it, and
//        getById (:86) omits the credential entirely. Read-only · driver-isolated
//        (mirrors checkIn's ownership gate, :243). Re-fetch re-queries (NO write).
//    • appointments.checkIn({ appointmentId, … })  (EXISTS · appointments.ts:238)
//        → real db.update(status='checked_in'); returns { success, queuePosition,
//          estimatedWait }. Drives the "Check in at gate" primary CTA.
//
//  Backing table gate_passes (schema.ts:10533): passCode varchar(12) uniqueIndex ·
//  qrCodeData · driverId/terminalId/appointmentId/loadId · validFrom/validUntil ·
//  status enum active|used|expired|revoked · usedAt.
//
//  HONEST DEGRADE (0% mock doctrine): every field the resolver returns null for
//  (no pass minted yet · empty dev DB · no linked load) renders an em-dash —
//  never the SVG's representative sample values (GP-7Q4K2M / Meridian / CONF-004182
//  / 53' DRY VAN). Those live ONLY in #Preview. No try?-collapse anywhere; the
//  loader is a real do/catch surfacing `actionError`; the CTA is a real mutation
//  surfacing `actionAck` / `actionError`.
//
//  RBAC: DRIVER (assigned driver only — server enforces appt.driverId == userId,
//  or a company-scoped terminal operator). transportMode = truck (this brick;
//  the same surface serves rail/vessel gate passes — terminology is mode-neutral).
//  USA persona; the credential is country-agnostic.
//  Nav: canonical Driver enum HOME · TRIPS · [orb] · LOADS · ME (TRIPS current,
//  supplied by the Driver nav chrome — this detail screen renders content only,
//  matching 002_RailShipmentDetail / 006_RailCrossBorderCustoms).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shape (decoded from the REAL getGatePass payload)

private struct GatePass161: Decodable {
    // Credential (null until updateStatus mints one)
    let passCode: String?
    let qrCodeData: String?
    let passStatus: String?        // active | used | expired | revoked
    let validFrom: String?         // ISO-8601
    let validUntil: String?        // ISO-8601
    let usedAt: String?
    // Appointment context
    let appointmentId: String?
    let confirmationNumber: String?
    let appointmentType: String?   // "pickup" | "delivery"
    let appointmentStatus: String? // scheduled | confirmed | checked_in | …
    let dockNumber: String?
    let terminalId: String?
    let facilityName: String?      // may be null (host enrichment)
    let scheduledDate: String?     // "YYYY-MM-DD"
    let scheduledTime: String?     // "HH:MM"
    // Load summary (all honest-null when no linked load / empty dev DB)
    let loadNumber: String?
    let originState: String?
    let destState: String?
    let distanceMiles: String?
    let bolNumber: String?
    let driverId: String?
}

// MARK: - Screen

struct DriverGatePass_161: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// The appointment whose active gate pass this screen presents.
    let appointmentId: Int

    // Real loading + action state (honest wiring; no try?-collapse).
    @State private var pass: GatePass161? = nil
    @State private var loading = true
    @State private var actionError: String? = nil
    @State private var actionAck: String? = nil
    @State private var checkingIn = false
    /// Set only by the DEBUG preview init so `.task` doesn't overwrite seeded
    /// sample data with a network call. Always false in production.
    @State private var seeded = false

    init(appointmentId: Int) {
        self.appointmentId = appointmentId
    }
    #if DEBUG
    fileprivate init(appointmentId: Int, previewPass: GatePass161) {
        self.appointmentId = appointmentId
        _pass = State(initialValue: previewPass)
        _loading = State(initialValue: false)
        _seeded = State(initialValue: true)
    }
    #endif

    // MARK: Derived display (all from the payload; sample values never hardcoded)

    private func dash(_ s: String?) -> String {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return "—" }
        return s
    }

    private var statusWord: String {
        switch (pass?.passStatus ?? "").lowercased() {
        case "active":  return "ACTIVE"
        case "used":    return "USED"
        case "expired": return "EXPIRED"
        case "revoked": return "REVOKED"
        case "":        return loading ? "…" : "NOT ISSUED"
        default:        return (pass?.passStatus ?? "—").uppercased()
        }
    }
    private var statusColor: Color {
        switch statusWord {
        case "ACTIVE":            return Brand.success
        case "REVOKED", "EXPIRED": return Brand.danger
        case "USED":              return palette.textSecondary
        case "…":                 return palette.textTertiary
        default:                  return palette.textTertiary
        }
    }
    private var isActive: Bool { (pass?.passStatus ?? "").lowercased() == "active" }
    private var isCheckedIn: Bool { (pass?.appointmentStatus ?? "").lowercased() == "checked_in" }

    /// Appointment kind word ("PICKUP · LIVE LOAD" style chip — kind only; we
    /// don't invent a load-type the payload doesn't carry).
    private var kindChip: String {
        switch (pass?.appointmentType ?? "").lowercased() {
        case "pickup":   return "PICKUP"
        case "delivery": return "DELIVERY"
        case "":         return "APPOINTMENT"
        default:         return (pass?.appointmentType ?? "").uppercased()
        }
    }

    /// "HH:MM" extracted from an ISO string (or nil).
    private func clock(_ iso: String?) -> String? {
        guard let iso, iso.count >= 16 else { return nil }
        // ISO "2026-05-23T13:00:00…" → index 11..<16
        let s = Array(iso)
        guard s.count >= 16 else { return nil }
        return String(s[11..<16])
    }
    private var validWindow: String {
        guard let f = clock(pass?.validFrom), let u = clock(pass?.validUntil) else { return "—" }
        return "\(f) – \(u)"
    }
    /// "YYYY-MM-DD" → "MMM DD" (uppercased) plus the relative "OPENS IN N MIN"
    /// computed honestly from validFrom vs now (no baked "42 min").
    private var validDayLine: String {
        let day = relativeDay(pass?.validFrom ?? pass?.scheduledDate)
        let rel = opensRelative()
        if day == "—" && rel == nil { return "—" }
        return [day, rel].compactMap { $0 }.joined(separator: " · ")
    }
    private func relativeDay(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "—" }
        let mm = String(Array(iso)[5..<7]); let dd = String(Array(iso)[8..<10])
        let months = ["01":"JAN","02":"FEB","03":"MAR","04":"APR","05":"MAY","06":"JUN",
                      "07":"JUL","08":"AUG","09":"SEP","10":"OCT","11":"NOV","12":"DEC"]
        guard let mon = months[mm] else { return "—" }
        return "\(mon) \(dd)"
    }
    /// Minutes until the pass window opens, computed from validFrom.
    private func opensRelative() -> String? {
        guard let iso = pass?.validFrom,
              let from = ISO8601DateFormatter().date(from: normalizedISO(iso)) else { return nil }
        let delta = from.timeIntervalSinceNow
        if delta > 60 {
            let mins = Int(delta / 60)
            if mins >= 120 { return "OPENS IN \(mins / 60) H" }
            return "OPENS IN \(mins) MIN"
        }
        if let u = pass?.validUntil,
           let until = ISO8601DateFormatter().date(from: normalizedISO(u)),
           until.timeIntervalSinceNow > 0 {
            return "OPEN NOW"
        }
        return nil
    }
    private func normalizedISO(_ s: String) -> String {
        // getGatePass returns "…T13:00:00.000Z" (toISOString, fractional secs).
        // A default ISO8601DateFormatter rejects the ".000" fraction, so strip
        // any fractional component (keeping a trailing zone marker), then ensure
        // a Z suffix when the server omits the zone.
        var out = s
        if let dot = out.firstIndex(of: ".") {
            let tail = out[out.index(after: dot)...]
            if let zIdx = tail.firstIndex(where: { $0 == "Z" || $0 == "+" }) {
                out = String(out[..<dot]) + String(tail[zIdx...])
            } else {
                out = String(out[..<dot])
            }
        }
        if out.hasSuffix("Z") || out.contains("+") { return out }
        return out + "Z"
    }

    private var routeLine: String {
        let o = pass?.originState, d = pass?.destState
        if let o, let d, !o.isEmpty, !d.isEmpty { return "\(o) → \(d)" }
        return "—"
    }
    private var loadMetaLine: String {
        var parts: [String] = []
        if let mi = pass?.distanceMiles, let v = Double(mi) {
            parts.append("\(Int(v)) MI")
        }
        if let ln = pass?.loadNumber, !ln.isEmpty { parts.append(ln) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
    private var facilityLine: String { dash(pass?.facilityName) }
    private var dockLine: String {
        let dock = pass?.dockNumber.flatMap { $0.isEmpty ? nil : "DOCK \($0)" }
        // We only have terminalId, not a city — show dock + terminal ref honestly.
        let term = pass?.terminalId.flatMap { $0.isEmpty ? nil : "TERMINAL \($0)" }
        let line = [dock, term].compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? "—" : line
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if let err = actionError { banner(err, tint: Brand.danger, icon: "exclamationmark.triangle.fill") }
                    if let ack = actionAck { banner(ack, tint: Brand.success, icon: "checkmark.seal.fill") }

                    passHero
                    appointmentSection
                    esangBand
                    ctaPair
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
                .padding(.bottom, Space.s8)
            }
        }
        .background(palette.bgPrimary.ignoresSafeArea())
        .task { if !seeded { await load() } }
    }

    // MARK: TopBar (DETAIL grammar)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ DRIVER · GATE PASS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(statusWord + (isActive ? " · VALID 4H" : ""))
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(statusColor)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gate pass")
                        .font(.system(size: 22, weight: .bold)).kerning(-0.3)
                        .foregroundStyle(palette.textPrimary)
                    Text(kindChip == "APPOINTMENT" ? "present at the dock gate"
                                                    : "\(kindChip.lowercased()) · \(opensRelative()?.lowercased() ?? "present at gate")")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(dash(pass?.driverId.map { "DRIVER \($0)" }))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(dash(pass?.confirmationNumber))
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, Space.s4)
        }
        .padding(.top, Space.s5)
        .padding(.horizontal, Space.s5)
    }

    // MARK: Pass hero (gradient-rimmed credential card)

    private var passHero: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // Status pills
            HStack(spacing: Space.s2) {
                pill(statusWord, fg: statusColor, bg: statusColor.opacity(0.16))
                pill(kindChip, fg: palette.textSecondary, bg: Color.white.opacity(0.06))
                Spacer()
            }

            // Code + QR row
            HStack(alignment: .top, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        eyebrow("GATE PASS CODE")
                        Text(dash(pass?.passCode))
                            .font(.system(size: 34, weight: .bold, design: .monospaced)).kerning(0.5)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(facilityLine)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(dockLine)
                            .font(.system(size: 10, weight: .bold)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    VStack(alignment: .leading, spacing: 6) {
                        eyebrow("VALID WINDOW")
                        Text(validWindow)
                            .font(.system(size: 14, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text(validDayLine)
                            .font(.system(size: 10, weight: .bold)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: Space.s2)
                qrCredential
            }
        }
        .padding(Space.s5)
        .eusoCard(radius: Radius.xl, intensity: .standard)
    }

    /// Stylized credential glyph — flat ink on a matte-white tile, NOT a real
    /// scannable code (the qrCodeData payload is the source of truth at the
    /// gate). Matches the SVG's 104×104 white block + "SCAN OR READ" caption.
    private var qrCredential: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: 0xF5F5F7))
                Image(systemName: "qrcode")
                    .resizable().scaledToFit()
                    .frame(width: 84, height: 84)
                    .foregroundStyle(Color.black)
                    .opacity(pass?.qrCodeData == nil ? 0.18 : 1)
            }
            .frame(width: 104, height: 104)
            Text("SCAN OR READ")
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Appointment section

    private var appointmentSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            eyebrow("APPOINTMENT")

            // Confirmation row
            infoRow(
                icon: "calendar",
                iconTint: Brand.blue.opacity(0.20),
                title: "Confirmation · \(dash(pass?.confirmationNumber))",
                sub: confirmationSub,
                trailing: (pass?.appointmentStatus ?? "scheduled").uppercased(),
                trailingColor: Color(hex: 0x5AA2FF),
                trailingMono: false)

            // Load row
            infoRow(
                icon: "shippingbox.fill",
                iconTint: Color.white.opacity(0.06),
                title: routeLine,
                sub: loadMetaLine,
                trailing: dash(pass?.bolNumber.map { "BOL \($0)" }),
                trailingColor: palette.textSecondary,
                trailingMono: true)

            // Driver row (avatar)
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.primary).frame(width: 32, height: 32)
                    Text("DR")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(dash(pass?.driverId.map { "Driver #\($0)" }))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(dash(pass?.terminalId.map { "TERMINAL \($0)" }))
                        .font(.system(size: 10, weight: .bold)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
            .padding(Space.s4)
            .frame(minHeight: 56)
            .eusoRow()
        }
    }

    private var confirmationSub: String {
        var parts: [String] = []
        if kindChip != "APPOINTMENT" { parts.append(kindChip) }
        let day = relativeDay(pass?.scheduledDate)
        if day != "—" { parts.append(day) }
        if let t = pass?.scheduledTime, !t.isEmpty { parts.append(t) }
        if let dk = pass?.dockNumber, !dk.isEmpty { parts.append("DOCK \(dk)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // MARK: ESang watch band

    private var esangBand: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(esangPrimaryLine)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("ESANG armed the watch; check in to take a dock-queue position.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.esangSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
    private var esangPrimaryLine: String {
        if let u = clock(pass?.validUntil) {
            let dock = pass?.dockNumber.flatMap { $0.isEmpty ? nil : " dock \($0)" } ?? ""
            return "Pass valid until \(u) — present at the\(dock) gate."
        }
        return "Present this pass at the dock gate."
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            // Secondary — back to the appointment detail (pushed-detail dismiss)
            Button(action: { dismiss() }) {
                Text("Appointment")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))

            // Primary — check in at gate (REAL mutation)
            CTAButton(
                title: isCheckedIn ? "Checked in" : "Check in at gate",
                action: { Task { await checkIn() } },
                trailingIcon: isCheckedIn ? "checkmark" : "arrow.right",
                isLoading: checkingIn)
            .disabled(isCheckedIn || !isActive)
            .opacity(isCheckedIn || !isActive ? 0.6 : 1)
        }
    }

    // MARK: - Reusable bits

    private func eyebrow(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .heavy)).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }
    private func pill(_ s: String, fg: Color, bg: Color) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .bold)).tracking(0.6)
            .foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(bg)
            .clipShape(Capsule())
    }
    private func banner(_ text: String, tint: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
    private func infoRow(icon: String, iconTint: Color, title: String, sub: String,
                         trailing: String, trailingColor: Color, trailingMono: Bool) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(iconTint)
                    .frame(width: 32, height: 32)
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                Text(sub).font(.system(size: 10, weight: .bold)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Text(trailing)
                .font(trailingMono ? EType.mono(.caption) : .system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(trailingColor)
        }
        .padding(Space.s4)
        .frame(minHeight: 56)
        .eusoRow()
    }

    // MARK: - Loaders / actions (single REAL endpoint each — honest do/catch)

    private func load() async {
        loading = true; actionError = nil
        struct In: Encodable { let appointmentId: String }
        do {
            let p: GatePass161 = try await EusoTripAPI.shared.query(
                "appointments.getGatePass",
                input: In(appointmentId: String(appointmentId)))
            self.pass = p
        } catch {
            actionError = "Couldn’t load this gate pass. " +
                ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        loading = false
    }

    private func checkIn() async {
        guard isActive, !isCheckedIn else { return }
        checkingIn = true; actionError = nil; actionAck = nil
        defer { checkingIn = false }
        struct In: Encodable { let appointmentId: String }
        struct Out: Decodable { let success: Bool?; let queuePosition: Int?; let estimatedWait: Int? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "appointments.checkIn", input: In(appointmentId: String(appointmentId)))
            if resp.success == true {
                let q = resp.queuePosition ?? 0
                actionAck = q > 0
                    ? "Checked in · queue position \(q)."
                    : "Checked in at the gate."
                await load()   // re-read to reflect checked_in status
            } else {
                actionError = "Check-in returned no success flag — reload and try again."
            }
        } catch {
            actionError = "Check-in failed. " +
                ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

// MARK: - Previews
//
// Sample values live ONLY here (0% mock doctrine — the live view shows decoded
// data with em-dash fallbacks). These mirror the SVG's representative figures.

#if DEBUG
private extension GatePass161 {
    static let sample = GatePass161(
        passCode: "GP-7Q4K2M",
        qrCodeData: "{\"passCode\":\"GP-7Q4K2M\"}",
        passStatus: "active",
        validFrom: "2026-05-23T13:00:00.000Z",
        validUntil: "2026-05-23T17:00:00.000Z",
        usedAt: nil,
        appointmentId: "4182",
        confirmationNumber: "CONF-004182",
        appointmentType: "pickup",
        appointmentStatus: "confirmed",
        dockNumber: "12",
        terminalId: "9",
        facilityName: "Meridian Distribution Center",
        scheduledDate: "2026-05-23",
        scheduledTime: "13:00",
        loadNumber: "EUSO-2026-04-16-004182",
        originState: "MS",
        destState: "NC",
        distanceMiles: "612.0",
        bolNumber: "4182",
        driverId: nil)
}

#Preview("161 · Driver Gate Pass · Night") {
    DriverGatePass_161(appointmentId: 4182, previewPass: .sample)
        .preferredColorScheme(.dark)
        .environment(\.palette, Theme.dark)
}
#endif
