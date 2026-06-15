//
//  820_VesselReeferPreCool.swift
//  EusoTrip — Vessel Operator · Reefer Pre-Cool (FSMA pre-load gate).
//
//  Faithful 1:1 port of "06 Vessel/820 Vessel Reefer Pre-Cool.svg" (Light + Dark), adapted INTO the
//  app on the canonical DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton ·
//  IridescentHairline · EusoEmptyState) and registered under the VESSEL_OPERATOR role per the
//  canonical header. Nav is the registered vessel-operator wrapper the siblings ship
//  (757 Detention Letters): HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME — COMPLIANCE inked
//  because the pre-cool gate is an FSMA 21 CFR 1.908 compliance surface.
//
//  LIVE SUPER-INTELLIGENCE FUSION (OPERATOR DIRECTIVE 2026-06-02): the per-hold zone telemetry stream
//  (reeferTemp.getLatestByZone) is the heartbeat; the hero verified-count, the KPI strip and the
//  pre-cool gate rows are three faces of the SAME `zones`/`fsma` state — when a hold reaches setpoint
//  or FSMA flips they all re-reason together off `load()`. Degraded provider state shows an explicit
//  error card, never a frozen number.
//
//  WIRING MANIFEST (web peer · frontend/server/routers/reeferTemp.ts · MCP-CONFIRMED this fire):
//    reeferTemp.getLatestByZone EXISTS reeferTemp.ts:61  · input {loadId?:number} · returns
//        Record<"front"|"center"|"rear",{tempF,tempC,status,recordedAt}> -> per-hold rows (hero · gate).
//    reeferTemp.getFSMAStatus   EXISTS reeferTemp.ts:392 · input {loadId:number} · returns
//        getFSMAStatus(): {loadId,cargoClass,isCompliant,currentTemp,setPoint,minAllowed,maxAllowed,
//        excursionCount,excursionMinutes,lastReading,preCoolVerified,readings[],violations[]}
//        (fsmaCompliance.ts:194) -> FSMA REQ/OK guard tile + strip. NOTE: real fields are `isCompliant`
//        + `preCoolVerified` (NOT compliant/required/status) — decoder + derived getters aligned to the
//        real shape this fire; "required" is derived honestly (FSMA always required for reefer/food).
//    reeferTemp.verifyPreCool   EXISTS reeferTemp.ts:380 (mutation) · input {loadId,trailerTemp,unit}
//        -> "Verify pre-cool" CTA (attests pre-cool at setpoint, writes FSMA pickup reading).
//    reeferTemp.recordFSMATemp  EXISTS reeferTemp.ts:359 (mutation) -> "FSMA log" path (footer note).
//    RBAC: protectedProcedure, scoped by reeferReadings.driverId (operatorId/containerId scope is a
//          STUB · named-gap surfaced by 799/702 — vessel-container reuse still rides driverId).
//    STUB · named-gap: per-hold setpoint + pre-cool BAND (verified/pending) is derived CLIENT-SIDE from
//          status (the zone row ships act temp + status only). "FSMA log" has no inline write path here
//          (recordFSMATemp needs a temp-entry sheet) — flagged STUB, re-runs load().
//
//  ZERO-FALLBACK (2026-06-09 · C1 fix): NO seed rows anywhere. When getLatestByZone returns no
//  zones the honest "Awaiting pre-cool telemetry" empty state renders and the "Verify pre-cool"
//  CTA is DISABLED — the FSMA attestation mutation can ONLY fire with (a) a real load scope
//  (loadId > 0) and (b) a live zone reading whose tempC feeds verifyPreCool. The screen can
//  never attest from fabricated telemetry. Counters derive from live rows only (0 when empty).
//  RoundedRectangle/Capsule chips are file-private, suffixed _820 to avoid cross-file private
//  collisions, built from sibling 757's gradient-rim grammar.
//

import SwiftUI

// MARK: - Screen (wrapper · Shell + registered vessel-operator nav)

struct VesselReeferPreCoolScreen: View {
    let theme: Theme.Palette
    /// Active reefer FCL booking the pre-cool gate scopes to. 0 (registry/zero-arg use) means
    /// "no load threaded": telemetry reads fall back to the operator's own latest readings
    /// across loads, and the FSMA verify CTA stays DISABLED — attesting needs a real loadId.
    var loadId: Int = 0
    init(theme: Theme.Palette, loadId: Int = 0) { self.theme = theme; self.loadId = loadId }

    var body: some View {
        Shell(theme: theme) {
            VesselReeferPreCoolBody820(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror reeferTemp.ts return rows)

/// One zone row from `reeferTemp.getLatestByZone` (keyed map front/center/rear / per-hold).
private struct ReeferZoneReading820: Decodable {
    let tempF: Double?
    let tempC: Double?
    let status: String?
    let recordedAt: String?
}

/// `reeferTemp.getFSMAStatus` -> FSMA guard envelope (fsmaCompliance.ts:194), decoded leniently
/// to the REAL field names (`isCompliant`, `preCoolVerified`); MCP-confirmed this fire.
private struct FSMAStatus820: Decodable {
    let isCompliant: Bool?
    let preCoolVerified: Bool?
    let cargoClass: String?
}

/// `reeferTemp.ambient` -> the AMBIENT (deck/port) weather at the reefer
/// position, used here to surface a FORECAST-KEYED pre-cool recommendation:
/// when the deck/port forecast is hot, pull the box deeper below setpoint
/// BEFORE stuffing so the cold reserve survives the heat soak. All fields
/// nullable so an enterprise-gated payload (available:false) decodes without
/// throwing => the recommendation banner stays HIDDEN, never fabricated.
private struct ReeferAmbient820: Decodable {
    let available: Bool?
    let ambientTempF: Double?
    let weatherCode: Int?
    let preCool: PreCool820?

    struct PreCool820: Decodable {
        let recommended: Bool?
        init(from decoder: Decoder) throws {
            if let b = try? decoder.singleValueContainer().decode(Bool.self) {
                recommended = b; return
            }
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            recommended = try? c?.decodeIfPresent(Bool.self, forKey: .recommended)
        }
        private enum CodingKeys: String, CodingKey { case recommended }
    }
}

// MARK: - Body

private struct VesselReeferPreCoolBody820: View {
    @Environment(\.palette) private var palette
    let loadId: Int

    @State private var zones: [String: ReeferZoneReading820] = [:]
    @State private var fsma: FSMAStatus820? = nil
    @State private var ambient: ReeferAmbient820? = nil   // forecast-keyed pre-cool · null/available:false today
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var verifying = false
    @State private var verifyDone = false
    @State private var verifyError: String? = nil

    // Derived gate counters — the three faces of one tick read THIS state.
    // ALL derive from live zone rows only: 0/0 when no telemetry, never a seeded floor.

    private var holdRows: [PreCoolHold820] { Self.holds(from: zones) }
    private var verifiedCount: Int { holdRows.filter { $0.band == .verified }.count }
    private var monitored: Int { holdRows.count }
    private var pendingCount: Int { max(0, monitored - verifiedCount) }
    /// FSMA is always required for reefer/food-grade cargo (21 CFR 1.908) — the gate exists for it.
    private var fsmaRequired: Bool { true }
    private var fsmaOK: Bool { (fsma?.isCompliant ?? false) || (fsma?.preCoolVerified ?? false) }
    private var verifyProgress: Double { monitored == 0 ? 0 : Double(verifiedCount) / Double(monitored) }

    /// THE critical gate (C1): verifyPreCool may only fire with a REAL load scope AND a live
    /// zone reading carrying a real temperature. No seeds, no default temps, no loadId 0 writes.
    private var liveLead: PreCoolHold820? { holdRows.first { $0.band != .verified && $0.tempC != nil } }
    private var canVerify: Bool { loadId > 0 && !zones.isEmpty && liveLead != nil }

    // Forecast-keyed pre-cool recommendation -------------------------------
    // HONEST: the banner only reads when the ambient feed is available with a
    // real deck/port temperature — enterprise-gated (available:false / nil)
    // hides it entirely. The "pull deeper" advice is keyed to the live
    // forecast (ambient temp + the server's preCool flag), never invented.

    private var ambientReady: Bool {
        (ambient?.available ?? false) && ambient?.ambientTempF != nil
    }

    /// True when the live forecast warrants a deeper pre-cool — either the
    /// server flagged it (`preCool.recommended`) or the deck/port forecast is
    /// hot enough (≥ 90°F) that the box needs extra cold reserve before the
    /// heat soak. Strictly derived from live ambient fields.
    private var preCoolRecommended: Bool {
        guard ambientReady else { return false }
        if ambient?.preCool?.recommended == true { return true }
        if let a = ambient?.ambientTempF, a >= 90 { return true }
        return false
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    heroCard
                    forecastPreCoolBanner
                    kpiStrip
                    gateSection
                    gateStrip
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Eyebrow / title

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("VESSEL OPERATOR · PRE-COOL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            // Honest scope chip: the real load when threaded, em-dash otherwise (no invented carrier/port).
            Text(loadId > 0 ? "LOAD \(loadId)" : "—").font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Text("Pre-cool verify").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(zones.isEmpty ? "no telemetry" : "synced live").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }.padding(.top, Space.s2)
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Telemetry degraded").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Hero card

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                    chip("GATE", color: palette.textSecondary)
                    chip(pendingCount == 1 ? "1 PENDING" : "\(pendingCount) PENDING", color: Brand.warning)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("VERIFIED").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        Text("\(verifiedCount)").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(Brand.success)
                    }
                }
                HStack(alignment: .center, spacing: Space.s4) {
                    Text("\(verifiedCount)/\(monitored)")
                        .font(.system(size: 44, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("reefers pre-cooled to setpoint").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                        Text(pendingCount == 0 ? "all holds at setpoint"
                                               : "\(pendingCount) awaiting setpoint pulldown")
                            .font(.system(size: 11)).foregroundStyle(pendingCount > 0 ? Brand.warning : Brand.success)
                    }
                    Spacer()
                }
                .padding(.top, Space.s3)
                ProgressView(value: verifyProgress).tint(Brand.magenta).padding(.top, Space.s2)
            }
            .padding(Space.s4)
        }
        .frame(height: 132)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    // MARK: Forecast-keyed pre-cool recommendation (reeferTemp.ambient)

    /// The forecast-keyed pre-cool advice: when the deck/port forecast is hot,
    /// pull the box deeper below setpoint before stuffing so the cold reserve
    /// survives the heat soak. Bespoke: the live sky condition is the
    /// WeatherIcons glyph for the forecast weatherCode. HONEST: rendered ONLY
    /// when the ambient feed is available with a real temperature — gated
    /// (available:false / nil) collapses it. No fabricated forecast/advice.
    @ViewBuilder
    private var forecastPreCoolBanner: some View {
        if ambientReady, let a = ambient, let aF = a.ambientTempF {
            let code = a.weatherCode ?? 0
            let warn = preCoolRecommended
            HStack(alignment: .top, spacing: Space.s3) {
                // Bespoke sky glyph for the live forecast weatherCode.
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06)).frame(width: 48, height: 48)
                    WeatherIcons.symbolView(for: code, size: 32)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(warn ? "PRE-COOL DEEPER" : "PRE-COOL NOMINAL")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(warn ? Brand.warning : Brand.success)
                        Text("· forecast \(String(format: "%.0f°F", aF)) at berth")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Text(warn
                         ? "Hot deck/port forecast — pull each box below setpoint before stuffing so the cold reserve survives the heat soak."
                         : "Deck/port forecast within band — standard setpoint pull-down is sufficient before stuffing.")
                        .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(warn ? Brand.warning.opacity(0.07) : palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(warn ? Brand.warning.opacity(0.4) : palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        // available:false / nil => hidden; lights up when the key lands.
    }

    // MARK: KPI strip (VERIFIED · PENDING · FSMA)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("VERIFIED").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                Text("\(verifiedCount)/\(monitored)").font(.system(size: 28, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                Text("at setpoint").font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            darkKpiTile(label: "PENDING", value: "\(pendingCount)", caption: "pulldown", tone: pendingCount > 0 ? Brand.warning : palette.textPrimary)
            darkKpiTile(label: "FSMA", value: fsmaOK ? "OK" : (fsmaRequired ? "REQ" : "-"),
                        caption: fsmaOK ? "attested" : "21 CFR 1.908", tone: fsmaOK ? Brand.success : Brand.info)
        }
    }

    private func darkKpiTile(label: String, value: String, caption: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit().foregroundStyle(tone)
            Text(caption).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Pre-cool gate · by hold

    private var gateSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PRE-COOL GATE · BY HOLD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("verifyPreCool:380").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                let rows = holdRows
                if rows.isEmpty {
                    EusoEmptyState(systemImage: "snowflake",
                                   title: "Awaiting pre-cool telemetry",
                                   subtitle: "Hold setpoint pulldown appears here as each reefer reports in.")
                        .padding(Space.s4)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        holdRow(row)
                        if idx < rows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 68)
                        }
                    }
                }
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            Text("FSMA log · recordFSMATemp reeferTemp.ts:359").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }

    private func holdRow(_ u: PreCoolHold820) -> some View {
        let accent: Color
        let icon: String
        let pillKind: StatusPill.Kind
        switch u.band {
        case .verified: accent = Brand.success; icon = "thermometer.snowflake"; pillKind = .success
        case .pulling:  accent = Brand.warning; icon = "clock";                  pillKind = .warning
        case .fsma:     accent = Brand.info;    icon = "thermometer.snowflake";  pillKind = .info
        }
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(u.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(u.meta).font(EType.mono(.caption)).tracking(0.2).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(text: u.pill, kind: pillKind)
                Text(u.valText).font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(u.band == .pulling ? Brand.warning : palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }

    // MARK: Gate strip

    private var gateStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("GATE · PRE-LOAD HOLD").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(monitored) reefers").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            Text("verifyPreCool gate · setpoint pulldown before stuffing").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            // Honest scope line — real load ref or em-dash; never an invented carrier/booking string.
            Text(loadId > 0 ? "LOAD \(loadId) · live zone telemetry" : "— · no load threaded").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = verifyError { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
            if verifyDone { Text("Pre-cool verified · FSMA attestation written.").font(EType.caption).foregroundStyle(Brand.success) }
            if !canVerify {
                // C1 honest state: the attestation CTA is hard-disabled without live telemetry
                // on a real load — the screen may never attest from seeds or defaults.
                Text(loadId > 0 ? "No live telemetry — pre-cool cannot be attested until a zone reports in."
                                : "No load threaded — open a reefer booking to attest its pre-cool.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                CTAButton(title: verifying ? "Verifying…" : "Verify pre-cool",
                          action: { Task { await verify() } },
                          isLoading: verifying)
                    .frame(maxWidth: .infinity)
                    .disabled(!canVerify)
                    .opacity(canVerify ? 1 : 0.45)
                Button(action: { Task { await load() } }) {  // recordFSMATemp — STUB · named-gap (no temp-entry sheet here), re-runs load()
                    Text("FSMA log")
                        .font(EType.title).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).frame(maxWidth: 148)
            }
        }
    }

    // MARK: Load (one tick)

    private func load() async {
        loading = true; loadError = nil
        do {
            // getLatestByZone takes an OPTIONAL loadId — when no load is threaded (0) the
            // input omits it and the proc returns the operator's own latest readings.
            async let z: [String: ReeferZoneReading820] = EusoTripAPI.shared.query(
                "reeferTemp.getLatestByZone", input: LoadIn820(loadId: loadId > 0 ? loadId : nil))
            let zoneMap = try await z
            self.zones = zoneMap
            // getFSMAStatus REQUIRES a real loadId — only ask with a threaded load,
            // otherwise the FSMA tile reads its honest un-attested "REQ" state.
            if loadId > 0 {
                self.fsma = try await EusoTripAPI.shared.query(
                    "reeferTemp.getFSMAStatus", input: FSMAIn820(loadId: loadId))
            } else {
                self.fsma = nil
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        // Ambient (deck/port forecast) is a best-effort overlay — its feed is
        // enterprise-gated and may return available:false or be unreachable.
        // A failure NEVER degrades the gate: the recommendation just stays
        // hidden until the key lands. loadId is optional on the wire.
        self.ambient = try? await EusoTripAPI.shared.query(
            "reeferTemp.ambient", input: LoadIn820(loadId: loadId > 0 ? loadId : nil))
        loading = false
    }

    private func verify() async {
        // C1 gate: attest ONLY from a live zone reading on a real load. Never from
        // seeds, never with a default temperature, never against loadId 0.
        guard loadId > 0, let lead = liveLead, let temp = lead.tempC else {
            verifyError = "No live telemetry — pre-cool cannot be attested."
            return
        }
        verifying = true; verifyError = nil
        do {
            let _: VerifyOut820 = try await EusoTripAPI.shared.mutation(
                "reeferTemp.verifyPreCool",
                input: VerifyIn820(loadId: loadId, trailerTemp: temp, unit: "C"))
            verifyDone = true
            await load()
        } catch {
            verifyError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        verifying = false
    }

    // MARK: Hold derivation (client-side band typing — see STUB note)
    // ZERO-FALLBACK: empty zones ⇒ empty rows ⇒ the honest empty state renders. No seeds.

    private static func holds(from zones: [String: ReeferZoneReading820]) -> [PreCoolHold820] {
        let order = ["front", "center", "rear"]
        return order.compactMap { key -> PreCoolHold820? in
            guard let z = zones[key] else { return nil }
            let c = z.tempC ?? z.tempF.map { ($0 - 32) * 5 / 9 }
            let status = (z.status ?? "").lowercased()
            let band: PreCoolHold820.Band =
                (status == "precool" || status == "pre_cool" || status == "verified") ? .verified
                : (status == "pulling" || status == "pulldown") ? .pulling
                : .fsma
            let temp = c.map { String(format: "%.1f°", $0) } ?? "-"
            return PreCoolHold820(
                band: band,
                title: "\(key.capitalized) · setpoint",
                meta: "ZONE-\(key.uppercased()) · \(band == .pulling ? "pulling down" : "at setpoint")",
                pill: band == .verified ? "VERIFIED" : (band == .pulling ? "PENDING" : "FSMA"),
                valText: temp,
                tempC: c)
        }
    }
}

// MARK: - Per-file typed inputs / outputs (NO module-level EmptyInput; suffixed _820)

private struct LoadIn820: Encodable { let loadId: Int? }
private struct FSMAIn820: Encodable { let loadId: Int }
private struct VerifyIn820: Encodable { let loadId: Int; let trailerTemp: Double; let unit: String }
private struct VerifyOut820: Decodable { let success: Bool? }

// MARK: - Hold model (rows derive ONLY from live getLatestByZone readings — no seeds)

private struct PreCoolHold820: Identifiable {
    let id = UUID()
    enum Band { case verified, pulling, fsma }
    let band: Band
    let title: String
    let meta: String
    let pill: String
    let valText: String
    let tempC: Double?
}

#Preview("820 · Vessel Reefer Pre-Cool · Night") {
    VesselReeferPreCoolScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("820 · Vessel Reefer Pre-Cool · Light") {
    VesselReeferPreCoolScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
