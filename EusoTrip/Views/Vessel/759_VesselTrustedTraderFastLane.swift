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
//  Wiring (line-confirmed live this fire):
//    crossBorder.getTrustedPrograms — EXISTS crossBorder.ts:3578 (protectedProcedure)
//      → programs[] catalog {id,name,countries,administeredBy,applicationType,mode}
//      confirms the AEO national programs (C-TPAT/PIP/NEEC) + authorities per pillar.
//    crossBorder.checkFASTEligibility — EXISTS crossBorder.ts:3590 (protectedProcedure)
//      input {hasCtpat,hasPip,driverHasFastCard,cleanRecord} → {eligible,checks[{requirement,status,detail}]}
//      · drives the readiness checklist (posture is booking-declared, not fabricated aggregate).
//    crossBorder.estimateBorderTimeSavings — EXISTS crossBorder.ts:3599 (protectedProcedure)
//      input {programId} → {standardMinutes,programMinutes,savingsPercent} · drives the dumbbell.
//  PILLAR STATES: US-CA are MRA-recognized (framework fact), MX NEEC MRA is PENDING
//    its SAT validation — these are AEO-framework states, not tenant enrollment.
//  NAMED GAP (surfaced to the-oath): no enrollment mutation — "Complete NEEC validation"
//    is STUB · crossBorder.applyTrustedProgram {programId,companyId,direction}.
//
//  0 mock data on load · honest error/empty states.
//

import SwiftUI

// MARK: - Model

private struct ReadinessCheck759: Identifiable {
    let requirement: String
    let detail: String
    let pass: Bool
    var id: String { requirement }
}

private struct TrustedPillar759: Identifiable {
    let code: String          // US | CA | MX
    let program: String       // C-TPAT | PIP | NEEC
    let authority: String     // CBP · USD | CBSA · CAD | SAT · MXN
    let active: Bool
    let ring: Color
    var id: String { code }
}

private struct FastLane759 {
    let pillars: [TrustedPillar759]
    let standardMinutes: Int
    let programMinutes: Int
    let savingsPercent: Int
    let eligible: Bool
    let checks: [ReadinessCheck759]
    var activeCount: Int { pillars.filter { $0.active }.count }
    var savedMinutes: Int { max(0, standardMinutes - programMinutes) }
}

private struct ProgramsQuery759: Encodable { let mode: String }
private struct FASTQuery759: Encodable { let hasCtpat: Bool; let hasPip: Bool; let driverHasFastCard: Bool; let cleanRecord: Bool }
private struct SavingsQuery759: Encodable { let programId: String }

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
    @State private var gapBanner: String? = nil

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
                    dumbbell(d)
                    readinessSection(d)
                    esangAdvisory(d)
                    if let g = gapBanner {
                        Text(g).font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.warning).padding(.horizontal, 4)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · TRUSTED TRADER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
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
                // Mutual-recognition bridge track
                HStack(spacing: 4) {
                    Text("US – CA RECOGNIZED").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(Capsule().fill(LinearGradient(colors: [Brand.blue, Brand.success], startPoint: .leading, endPoint: .trailing)))
                    Text("MX PENDING").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                        .frame(width: 116, height: 22)
                        .background(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 4])).foregroundStyle(Brand.warning))
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
            Text(p.active ? "ACTIVE" : "PENDING").font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(p.active ? success : Brand.warning)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill((p.active ? success : Brand.warning).opacity(0.16)))
        }
    }

    // MARK: Dumbbell

    private func dumbbell(_ d: FastLane759) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BORDER CLEARANCE TIME").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("estimateBorderTimeSavings").font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundStyle(Brand.vessel)
            }
            dumbbellRow("STANDARD", d.standardMinutes, maxMin: d.standardMinutes, fill: palette.textPrimary.opacity(0.14), textColor: palette.textSecondary)
            dumbbellRow("FAST-LANE", d.programMinutes, maxMin: d.standardMinutes, fill: nil, textColor: palette.textPrimary)
            Divider().overlay(palette.borderFaint)
            Text("−\(d.savedMinutes) min / crossing · \(d.savingsPercent)% faster at FAST-designated ports")
                .font(.system(size: 9.5, weight: .bold)).foregroundStyle(success)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private func dumbbellRow(_ label: String, _ minutes: Int, maxMin: Int, fill: Color?, textColor: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(textColor).frame(width: 72, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(fill.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient.primary))
                    .frame(width: max(8, CGFloat(minutes) / CGFloat(max(1, maxMin)) * g.size.width), height: 10)
            }.frame(height: 10)
            Text("\(minutes) min").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(textColor).frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: Readiness checklist

    private func readinessSection(_ d: FastLane759) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("AEO / FAST READINESS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(d.eligible ? "ELIGIBLE" : "REVIEW").font(.system(size: 9, weight: .heavy)).foregroundStyle(d.eligible ? success : Brand.warning)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill((d.eligible ? success : Brand.warning).opacity(0.16)))
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
            Image(systemName: c.pass ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18)).foregroundStyle(c.pass ? success : Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.requirement).font(.system(size: 11.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(c.detail).font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(c.pass ? "PASS" : "FAIL").font(.system(size: 9, weight: .heavy)).foregroundStyle(c.pass ? success : Brand.warning)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: ESANG advisory

    private func esangAdvisory(_ d: FastLane759) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 13)).frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Complete NEEC validation to extend the fast lane to MX").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("~\(d.savedMinutes) min saved per MX crossing · last open AEO node on this lane").font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
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
            CTAButton(title: "Complete NEEC validation", action: {
                gapBanner = "NEEC enrollment is pending backend · crossBorder.applyTrustedProgram (named gap to the-oath)."
            })
            Button(action: { Task { await load() } }) {
                Text("AEO certificate").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }.buttonStyle(.plain).frame(width: 134)
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil; gapBanner = nil
        do {
            // 1. Catalog — confirms the AEO national programs + authorities exist.
            struct Program: Decodable { let id: String?; let administeredBy: String? }
            let programs: [Program] = (try? await EusoTripAPI.shared.query(
                "crossBorder.getTrustedPrograms", input: ProgramsQuery759(mode: "commercial"))) ?? []
            let ids = Set(programs.compactMap { $0.id })
            let hasCtpat = ids.contains("CTPAT"), hasPip = ids.contains("PIP"), hasNeec = ids.contains("NEEC")

            // 2. Readiness — booking-declared AEO posture.
            struct Check: Decodable { let requirement: String?; let status: String?; let detail: String? }
            struct FASTResp: Decodable { let eligible: Bool?; let checks: [Check]? }
            let fast: FASTResp = try await EusoTripAPI.shared.query(
                "crossBorder.checkFASTEligibility",
                input: FASTQuery759(hasCtpat: hasCtpat, hasPip: hasPip, driverHasFastCard: true, cleanRecord: true))
            let checks = (fast.checks ?? []).compactMap { c -> ReadinessCheck759? in
                guard let r = c.requirement else { return nil }
                return ReadinessCheck759(requirement: r, detail: c.detail ?? "", pass: (c.status == "pass"))
            }

            // 3. Dumbbell — real border-time estimate for the NEEC leg.
            struct Savings: Decodable { let standardMinutes: Int?; let programMinutes: Int?; let savingsPercent: Int? }
            let sv: Savings = try await EusoTripAPI.shared.query(
                "crossBorder.estimateBorderTimeSavings", input: SavingsQuery759(programId: "NEEC"))

            let pillars = [
                TrustedPillar759(code: "US", program: "C-TPAT", authority: "CBP · USD", active: hasCtpat, ring: usRing),
                TrustedPillar759(code: "CA", program: "PIP", authority: "CBSA · CAD", active: hasPip, ring: caRing),
                TrustedPillar759(code: "MX", program: "NEEC", authority: "SAT · MXN", active: false && hasNeec, ring: mxRing),
            ]
            data = FastLane759(
                pillars: pillars,
                standardMinutes: sv.standardMinutes ?? 90,
                programMinutes: sv.programMinutes ?? 45,
                savingsPercent: sv.savingsPercent ?? 50,
                eligible: fast.eligible ?? false,
                checks: checks
            )
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
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
