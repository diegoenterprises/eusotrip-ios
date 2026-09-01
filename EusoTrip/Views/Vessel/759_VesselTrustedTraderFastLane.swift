//
//  759_VesselTrustedTraderFastLane.swift
//  EusoTrip — Vessel Operator · Trusted-Trader Fast-Lane.
//
//  Faithful 1:1 port of "759 Vessel Trusted Trader Fast-Lane.svg" (Light + Dark).
//  COMPLIANCE-GATE archetype (AEO mutual recognition: US C-TPAT · CA PIP · MX NEEC
//  under the WCO SAFE Framework): a tri-country AEO bridge hero (US/CA/MX pillars +
//  mutual-recognition track), a border-clearance-time dumbbell, an AEO/FAST
//  readiness checklist, an ESANG advisory, and a CTA pair. Real Vessel-Operator
//  BottomNav with COMPLIANCE inked.
//
//  Wiring: crossBorder.getTrustedTraderPosture reads the caller's tenant-scoped
//  trusted_trader_status rows. Driver FAST/admissibility checks remain unverified
//  until authoritative assignment evidence is linked; catalog entries never
//  masquerade as company enrollment.
//

import SwiftUI

// MARK: - Model

private struct ReadinessCheck759: Identifiable {
    let key: String
    let requirement: String
    let detail: String
    let state: String
    var id: String { key }
}

private struct TrustedPillar759: Identifiable {
    let code: String          // US | CA | MX
    let program: String       // C-TPAT | PIP | NEEC
    let authority: String     // CBP · USD | CBSA · CAD | SAT · MXN
    let status: String
    let ring: Color
    var active: Bool { status == "active" }
    var id: String { code }
}

private struct FastLane759 {
    let pillars: [TrustedPillar759]
    let companyReady: Bool
    let eligibilityStatus: String
    let eligibilityReason: String
    let checks: [ReadinessCheck759]
    let asOf: String?
    var activeCount: Int { pillars.filter { $0.active }.count }
}

private struct TrustedTraderPosture759: Decodable {
    struct Program: Decodable {
        let program: String
        let displayName: String
        let countryCode: String
        let authority: String
        let effectiveStatus: String
    }
    struct Eligibility: Decodable {
        let eligible: Bool
        let status: String
        let reason: String
    }
    struct Check: Decodable {
        let key: String
        let requirement: String
        let state: String
        let detail: String
    }
    let tracked: Bool
    let source: String
    let asOf: String?
    let programs: [Program]
    let companyReady: Bool
    let eligibility: Eligibility
    let checks: [Check]
}

// MARK: - Wrapper

struct VesselTrustedTraderFastLaneScreen: View {
    let theme: Theme.Palette
    let bookingNumber: String
    let lane: String
    init(theme: Theme.Palette, bookingNumber: String = "EUSO-BK-000009", lane: String = "Manzanillo MX → Long Beach US") {
        self.theme = theme; self.bookingNumber = bookingNumber; self.lane = lane
    }
    var body: some View {
        Shell(theme: theme) {
            VesselFastLaneBody759(bookingNumber: bookingNumber, lane: lane)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselFastLaneBody759: View {
    let bookingNumber: String
    let lane: String
    @Environment(\.palette) private var palette

    @State private var data: FastLane759? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showEvidenceSheet = false

    private let success = Color(hex: 0x2BD9A4)
    private let usRing = Color(hex: 0x5B8DEF)
    private let caRing = Color(hex: 0xFF6B61)
    private let mxRing = Color(hex: 0x2BD9A4)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading trusted-trader status…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let d = data {
                    bridgeHero(d)
                    evidenceSummary(d)
                    readinessSection(d)
                    eligibilityAdvisory(d)
                    ctaPair
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .sheet(isPresented: $showEvidenceSheet, onDismiss: { Task { await load() } }) {
            TrustedTraderSheet(onClose: { showEvidenceSheet = false })
                .presentationDetents([.large])
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripEyebrow(verbatim: "VESSEL OPERATOR · TRUSTED TRADER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                Spacer()
                Text("WCO SAFE · AEO MRA").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.vessel)
            }
            Text("Trusted-trader fast-lane").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("\(bookingNumber) · Intra-Americas · \(lane)").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Bridge hero

    private func bridgeHero(_ d: FastLane759) -> some View {
        RimCard759 {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("AEO MUTUAL RECOGNITION").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(d.activeCount) / \(d.pillars.count) ACTIVE").font(.system(size: 9, weight: .heavy)).foregroundStyle(success)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(success.opacity(0.16)))
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(d.pillars) { p in
                        pillarView(p).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func pillarView(_ p: TrustedPillar759) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().strokeBorder(p.ring, lineWidth: 3).frame(width: 42, height: 42)
                Text(p.code).font(.system(size: 14, weight: .heavy)).foregroundStyle(p.ring)
            }
            Text(p.program).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(p.authority).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
            Text(statusLabel(p.status)).font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(statusColor(p.status))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(statusColor(p.status).opacity(0.16)))
        }
    }

    // MARK: Evidence summary

    private func evidenceSummary(_ d: FastLane759) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("VERIFICATION POSTURE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(d.companyReady ? "COMPANY READY" : "EVIDENCE NEEDED")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(d.companyReady ? success : Brand.warning)
            }
            Divider().overlay(palette.borderFaint)
            Text(d.eligibilityReason)
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(d.asOf.map { "Evidence updated \(evidenceDate($0))" } ?? "No trusted-trader evidence has been recorded")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: Readiness checklist

    private func readinessSection(_ d: FastLane759) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("AEO / FAST READINESS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(d.companyReady ? "COMPANY READY" : "REVIEW").font(.system(size: 9, weight: .heavy)).foregroundStyle(d.companyReady ? success : Brand.warning)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill((d.companyReady ? success : Brand.warning).opacity(0.16)))
            }
            VStack(spacing: 0) {
                ForEach(Array(d.checks.enumerated()), id: \.element.id) { idx, c in
                    checkRow(c)
                    if idx < d.checks.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, 16) }
                }
            }
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func checkRow(_ c: ReadinessCheck759) -> some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon(c.state))
                .font(.system(size: 18)).foregroundStyle(statusColor(c.state))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.requirement).font(.system(size: 11.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(c.detail).font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(statusLabel(c.state)).font(.system(size: 9, weight: .heavy)).foregroundStyle(statusColor(c.state))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: Eligibility advisory

    private func eligibilityAdvisory(_ d: FastLane759) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 3) {
                Text("FAST-lane decision").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(d.eligibilityReason).font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Brand.escort.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.escort.opacity(0.30), lineWidth: 1))
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: 8) {
            CTAButton(title: "Manage evidence", action: { showEvidenceSheet = true })
            Button(action: { Task { await load() } }) {
                Text("Refresh").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }.buttonStyle(.plain).frame(width: 134)
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        do {
            let posture: TrustedTraderPosture759 = try await EusoTripAPI.shared.queryNoInput(
                "crossBorder.getTrustedTraderPosture")
            let ringByCountry = ["US": usRing, "CA": caRing, "MX": mxRing]
            let pillars = posture.programs.filter { $0.program != "FAST" }.map { program in
                TrustedPillar759(
                    code: program.countryCode,
                    program: program.displayName,
                    authority: program.authority,
                    status: program.effectiveStatus,
                    ring: ringByCountry[program.countryCode] ?? Brand.vessel
                )
            }
            data = FastLane759(
                pillars: pillars,
                companyReady: posture.companyReady,
                eligibilityStatus: posture.eligibility.status,
                eligibilityReason: posture.eligibility.reason,
                checks: posture.checks.map {
                    ReadinessCheck759(key: $0.key, requirement: $0.requirement, detail: $0.detail, state: $0.state)
                },
                asOf: posture.asOf
            )
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func statusColor(_ state: String) -> Color {
        switch state {
        case "active", "pass": return success
        case "expired", "revoked", "suspended", "blocked": return Brand.danger
        default: return Brand.warning
        }
    }

    private func statusIcon(_ state: String) -> String {
        switch state {
        case "active", "pass": return "checkmark.circle.fill"
        case "pending": return "clock.fill"
        case "expired": return "calendar.badge.exclamationmark"
        case "revoked", "suspended", "blocked": return "xmark.octagon.fill"
        case "not_linked": return "link.badge.plus"
        default: return "doc.badge.plus"
        }
    }

    private func statusLabel(_ state: String) -> String {
        switch state {
        case "active", "pass": return "VERIFIED"
        case "pending": return "PENDING"
        case "expired": return "EXPIRED"
        case "revoked": return "REVOKED"
        case "suspended": return "SUSPENDED"
        case "blocked": return "BLOCKED"
        case "not_linked": return "NOT LINKED"
        default: return "NOT RECORDED"
        }
    }

    private func evidenceDate(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - File-scoped bespoke helpers

private struct RimCard759<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

#Preview("759 · Vessel Trusted Trader Fast-Lane · Night") { VesselTrustedTraderFastLaneScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("759 · Vessel Trusted Trader Fast-Lane · Light") { VesselTrustedTraderFastLaneScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
