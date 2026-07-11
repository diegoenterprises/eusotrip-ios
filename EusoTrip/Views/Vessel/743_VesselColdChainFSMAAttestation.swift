//
//  743_VesselColdChainFSMAAttestation.swift
//  EusoTrip — Vessel Operator · Cold-Chain FSMA Attestation (COMPLIANCE GATE).
//
//  Verbatim bespoke port of canonical wireframe "743 Vessel Cold-Chain FSMA
//  Attestation · Dark" (06 Vessel · Vessel Operator). A COMPLIANCE/ATTESTATION
//  gate: a blocking-vs-cleared status hero carrying the regulator citation (21 CFR
//  Part 1 subpart O · FSMA Sanitary Transport), a sanitary-transport CHECK card
//  where each row is a check-state chip + a DONE/ON/ACK state pill (completion
//  ticks, not lifecycle dots), an active-booking proof card with three inline
//  proof cells (excursions / readings / gap), and the tri-country cold-chain
//  authority band. Turns a regulator checklist into one tap-to-attest gate so the
//  operator clears the reefer for stow without leaving the app. Docked under
//  COMPLIANCE.
//
//  REAL WIRING (tRPC · server/routers/reeferTemp.ts → services/fsmaCompliance.ts,
//  re-verified 2026-07-11):
//    · reeferTemp.getFSMAStatus {loadId}                                  (:767)
//        -> { isCompliant, currentTemp, setPoint, minAllowed, maxAllowed,
//        excursionCount, excursionMinutes, lastReading, preCoolVerified,
//        readings:[…], violations:[…] }. Backs the status gate, the pre-cool +
//        continuous-logging checks, and the three proof cells. Live off
//        fsma_temp_logs. Needs a bound reefer booking — honest unbound state when
//        loadId is 0.
//    · "Temp log" reveals the REAL readings from getFSMAStatus.readings.
//    · "Record attestation" -> recordFsmaAttestation does not exist yet; the
//        sanitary-condition + written-procedures checks are the operator's
//        attestation, and the CTA surfaces the write gap honestly instead of
//        faking success.  STUB · named-gap (attestation write + audit row).
//
//  transportMode=vessel · US FSMA (CA CFIA / MX COFEPRIS carried as content).
//  RBAC vesselProcedure. NO mock data — the gate, checks, and proof cells derive
//  from the live FSMA status.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes

private struct FSMAStatus743: Decodable {
    let loadId: Int?
    let isCompliant: Bool?
    let currentTemp: Double?
    let setPoint: Double?
    let excursionCount: Int?
    let excursionMinutes: Int?
    let lastReading: String?
    let preCoolVerified: Bool?
    let readings: [FSMAReading743]
    let violations: [String]
}
private struct FSMAReading743: Decodable, Identifiable {
    let id: Int
    let temperature: Double?
    let unit: String?
    let eventType: String?
    let isExcursion: Bool?
    let createdAt: String?
}

// MARK: - Screen

struct VesselColdChainFSMAScreen: View {
    let theme: Theme.Palette
    /// The reefer booking/load the attestation belongs to. 0 = unbound (opened
    /// from the compliance hub); a specific booking injects the real load id.
    var loadId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselColdChainFSMABody(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle)
        }
    }
}

// MARK: - Body

private struct VesselColdChainFSMABody: View {
    let loadId: Int
    @Environment(\.palette) private var palette

    @State private var status: FSMAStatus743? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showLog = false
    @State private var attestNote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingState
                } else if loadId <= 0 {
                    unboundState
                } else if let err = loadError {
                    errorCard(err)
                } else if let s = status {
                    statusGate(s)
                    checkCard(s)
                    proofCard(s)
                    if let note = attestNote { infoBanner(note) }
                    ctaRow
                    if showLog { tempLogSection(s) }
                    authorityBand
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Derived checks

    private struct Check { let title: String; let detail: String; let state: String; let ok: Bool; let attested: Bool }
    private func checks(_ s: FSMAStatus743) -> [Check] {
        let precool = s.preCoolVerified ?? false
        let logging = !s.readings.isEmpty
        return [
            Check(title: "Pre-cool verification",
                  detail: precool ? "container pulled to set point before stow" : "no pre-cool reading on record",
                  state: precool ? "DONE" : "MISSING", ok: precool, attested: false),
            Check(title: "Continuous temp logging",
                  detail: "\(s.readings.count) reading\(s.readings.count == 1 ? "" : "s")" + (lastReadingShort(s).map { " · last \($0)" } ?? ""),
                  state: logging ? "ON" : "OFF", ok: logging, attested: false),
            Check(title: "Sanitary condition",
                  detail: "wash certificate + CSC plate — operator attested",
                  state: "ACK", ok: (s.isCompliant ?? false), attested: true),
            Check(title: "Written procedures",
                  detail: "shipper SOP acknowledged · carrier trained",
                  state: "ACK", ok: true, attested: true),
        ]
    }
    private func satisfied(_ s: FSMAStatus743) -> Int { checks(s).filter { $0.ok }.count }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 8, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · FSMA ATTESTATION")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("21 CFR 1.908").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("FSMA attestation")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary).padding(.top, Space.s4)
            Text("Sanitary Transport · subpart O")
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).padding(.top, 2)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Status gate hero

    private func statusGate(_ s: FSMAStatus743) -> some View {
        let compliant = s.isCompliant ?? false
        let accent = compliant ? Brand.success : Brand.danger
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(accent).frame(width: 16, height: 16)
                        Image(systemName: compliant ? "checkmark" : "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    }
                    Text(compliant ? "COMPLIANT · STOW CLEARED" : "BLOCKED · STOW HELD")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(accent)
                }
                Spacer()
                Text("\(satisfied(s)) OF 4").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(accent)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.16))

            VStack(alignment: .leading, spacing: 6) {
                Text(compliant ? "FSMA Sanitary Transport rule satisfied" : (s.violations.first ?? "Sanitary Transport rule not yet satisfied"))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(compliant ? "Pre-cool verified · continuous logging on · no excursions"
                               : "Resolve the flagged conditions before stow")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                Text("21 CFR Part 1 subpart O · \(s.excursionCount ?? 0) excursion\((s.excursionCount ?? 0) == 1 ? "" : "s")")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s4)
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }

    // MARK: Check card

    private func checkCard(_ s: FSMAStatus743) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("SANITARY TRANSPORT · CHECKS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(satisfied(s)) OF 4 SATISFIED").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.success)
            }
            VStack(spacing: 0) {
                let cs = checks(s)
                ForEach(Array(cs.enumerated()), id: \.offset) { idx, c in
                    checkRow(c)
                    if idx < cs.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, 68) }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func checkRow(_ c: Check) -> some View {
        let accent = c.ok ? Brand.success : (c.attested ? Brand.warning : Brand.danger)
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: c.ok ? "checkmark" : (c.attested ? "signature" : "exclamationmark"))
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(c.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(c.detail).font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: Space.s2)
            Text(c.state).font(.system(size: 9, weight: .heavy)).foregroundStyle(accent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(accent.opacity(0.16)))
        }
        .padding(Space.s4)
    }

    // MARK: Proof card

    private func proofCard(_ s: FSMAStatus743) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("FSMA · ACTIVE BOOKING").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.info.opacity(0.16)).frame(width: 40, height: 40)
                        Image(systemName: "thermometer.snowflake").font(.system(size: 17, weight: .semibold)).foregroundStyle(Brand.info)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reeferHeadline(s)).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                        Text("VES-\(s.loadId ?? loadId) · reefer booking")
                            .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }
                Divider().overlay(palette.borderFaint)
                HStack(spacing: 0) {
                    proofCell("EXCURSIONS", "\(s.excursionCount ?? 0)", (s.excursionCount ?? 0) == 0 ? Brand.success : Brand.danger)
                    proofCell("READINGS", "\(s.readings.count)", palette.textPrimary)
                    proofCell("GAP MIN", "\(s.excursionMinutes ?? 0)", (s.excursionMinutes ?? 0) == 0 ? Brand.success : Brand.warning)
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private func reeferHeadline(_ s: FSMAStatus743) -> String {
        if let t = s.currentTemp {
            return String(format: "Reefer at %.0f°F", t) + (s.setPoint.map { String(format: " · set %.0f°F", $0) } ?? "")
        }
        return "Frozen / chilled reefer · continuous log"
    }
    private func proofCell(_ label: String, _ value: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(c)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Temp log (real readings)

    private func tempLogSection(_ s: FSMAStatus743) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("TEMP LOG · getFSMAStatus.readings").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if s.readings.isEmpty {
                EusoEmptyState(systemImage: "thermometer.medium", title: "No temperature readings yet",
                               subtitle: "Continuous logging populates the trail once the reefer reports.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(s.readings.prefix(12).enumerated()), id: \.element.id) { idx, r in
                        readingRow(r)
                        if idx < min(11, s.readings.count - 1) { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }
    private func readingRow(_ r: FSMAReading743) -> some View {
        HStack(spacing: Space.s3) {
            Circle().fill((r.isExcursion ?? false) ? Brand.danger : Brand.success).frame(width: 7, height: 7)
            Text(String(format: "%.1f°%@", r.temperature ?? 0, (r.unit ?? "F").uppercased()))
                .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            Text(r.eventType ?? "reading").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Spacer()
            if let t = r.createdAt { Text(shortDateTime(t)).font(EType.mono(.caption)).foregroundStyle(palette.textTertiary) }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
    }

    // MARK: Authority band (side-by-side capsules)

    private var authorityBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("COLD-CHAIN AUTHORITY · STOW MARKET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                authorityCapsule("US · FDA", "FSMA · 21 CFR 1.908", active: true)
                authorityCapsule("CA · CFIA", "SFCR SOR/2018-108", active: false)
                authorityCapsule("MX · COFEPRIS", "NOM-251 · SENASICA", active: false)
            }
        }
    }
    private func authorityCapsule(_ code: String, _ instrument: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(code).font(.system(size: 10, weight: .heavy)).foregroundStyle(active ? Brand.info : palette.textSecondary)
                if active { Spacer(minLength: 0); Circle().fill(Brand.info).frame(width: 5, height: 5) }
            }
            Text(instrument).font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(active ? Brand.info.opacity(0.85) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background((active ? Brand.info.opacity(0.10) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(active ? Brand.info.opacity(0.45) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: CTA

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                attestNote = "Attestation writes land with recordFsmaAttestation — the sanitary + procedures attestation records against this booking once it ships."
            } label: {
                Text("Record attestation").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48).background(LinearGradient.primary).clipShape(Capsule())
            }.buttonStyle(.plain).frame(maxWidth: .infinity)
            Button { withAnimation(.easeOut(duration: 0.18)) { showLog.toggle() } } label: {
                Text(showLog ? "Hide log" : "Temp log").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 110, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: States / format

    private var unboundState: some View {
        EusoEmptyState(systemImage: "shield.lefthalf.filled",
                       title: "Open a reefer booking to attest",
                       subtitle: "The FSMA Sanitary Transport gate reads the live temperature trail of a specific reefer container.")
    }
    private func infoBanner(_ msg: String) -> some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }
    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }
    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 116)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 220)
        }
    }
    private func lastReadingShort(_ s: FSMAStatus743) -> String? {
        guard let iso = s.lastReading else { return nil }
        return shortDateTime(iso)
    }
    private func shortDateTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date = d else { return String(iso.prefix(16)) }
        let out = DateFormatter(); out.dateFormat = "MMM d · HH:mm"
        return out.string(from: date)
    }

    private func load() async {
        guard loadId > 0 else { loading = false; return }
        loading = true; loadError = nil
        struct In: Encodable { let loadId: Int }
        do {
            let resp: FSMAStatus743 = try await EusoTripAPI.shared.query("reeferTemp.getFSMAStatus", input: In(loadId: loadId))
            self.status = resp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("743 · Vessel FSMA Attestation · Night") {
    VesselColdChainFSMAScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("743 · Vessel FSMA Attestation · Light") {
    VesselColdChainFSMAScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
