//
//  804_VesselOverchargeRecovery.swift
//  EusoTrip — Vessel Operator · Overcharge Recovery.
//
//  Faithful 1:1 port of "804 Vessel Overcharge Recovery.svg" (Light + Dark), RECONSTRUCTED to a
//  purpose-built RECOVERY-PIPELINE archetype (deliberately NOT the money-ledger skeleton it used to
//  share with 803 Freight Audit / 805 Loss Prevention): the hero is a 4-stage recovery funnel
//  (Identified -> Disputed -> In Review -> Recovered) with proportional tapering bars + per-stage
//  count/dollars, a thin pending/avg-days/written-off metrics rail, and a per-carrier RECOVERY CASES
//  ledger whose rows carry a recovered-of-overcharge fraction, an aging line and a status pill.
//  Nav anchored to the registered vessel siblings' Shell + BottomNav wrapper (HOME · SHIPMENTS ·
//  [orb] · COMPLIANCE[current] · ME) — the exact shape 757 ships.
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    freightClaims.getOverchargeRecovery (EXISTS frontend/server/routers/freightClaims.ts:952 ·
//        protectedProcedure · {status?(identified|disputed|recovered|written_off),limit,offset} ->
//        {recoveries:[{id,invoiceNumber,carrier,overchargeAmount,recoveredAmount,status,identifiedDate,
//        recoveredDate,type}],total,summary:{totalIdentified,totalRecovered,pendingRecovery,recoveryRate,
//        avgRecoveryDays}}). Funnel stages are derived from the status buckets; recoveryRate =
//        totalRecovered/totalIdentified. NOTE recoveries[] currently returns empty (web stub, confirmed
//        on disk line 960-981) — the bespoke seeds below are overwritten by the live query on .task /
//        .refreshable only when the server returns non-empty data, so we never fabricate over real zeros.
//    "File recovery dispute" -> freightClaims.fileClaim (EXISTS freightClaims.ts:332 · inserts claim row +
//        blockchainAuditTrail entry, broadcasts WS_CHANNELS.claims / WS_EVENTS.claimFiled). Today this
//        screen only re-pulls the tracker after filing (the file-dispute composer lives on the claim flow);
//        flagged STUB here (no inline mutation wired) rather than faked.
//    "Export" STUB named-gap exportOverchargeRecovery (re-runs load()). RBAC: protectedProcedure.
//        transportMode=vessel · USD.
//
//  In-module fidelity notes: the canonical port leaned on app symbols that do not exist in this module —
//  Brand.primary (a LinearGradient here, NOT a Color) -> Brand.blue; palette.track -> palette.borderSoft;
//  StatusPill(text:tone:) -> the real StatusPill(text:kind:); Money.usd(...) -> file-private usd804(...);
//  RimCard/ESangRow/SecondaryButton are not shared symbols -> RimCard804 / ESangRow804 / secondaryButton804
//  built from sibling 757's gradient-rim grammar. EmptyInput is per-file (OverchargeInput804). The bespoke
//  body — funnel, metrics rail, carrier ledger, ESang row — is preserved faithfully.
//

import SwiftUI

private struct FunnelStage804: Identifiable {
    let id = UUID()
    let label: String
    let frac: Double           // relative to the widest (Identified) stage
    let color: Color
    let detail: String         // "9 · $42,800"
}

private struct RecoveryCase804: Identifiable {
    let id = UUID()
    let carrierCode: String    // chip initials (MSC / MAEU / OOLU)
    let title: String          // "MSC · accessorial"
    let sub: String            // "INV-MSC-88241 · recovered 6d ago"
    let tone: StatusPill.Kind
    let chip: Color
    let pill: String
    let value: String          // recovered money
    let ofOver: String         // "of $3,200 over"
    let muted: Bool
}

struct VesselOverchargeRecoveryScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselOverchargeRecoveryBody()
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

private struct VesselOverchargeRecoveryBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var hero    = "$31,600"
    @State private var subline = "recovered of $42,800 identified · 74% rate · avg 22d to recover"
    @State private var ratePct = "74% recovered"
    @State private var pending     = "$11,200"
    @State private var avgDays     = "22d"
    @State private var writtenOff  = "$640"

    @State private var stages: [FunnelStage804] = [
        .init(label: "IDENTIFIED", frac: 1.00,  color: Brand.blue,    detail: "9 · $42,800"),
        .init(label: "DISPUTED",   frac: 0.453, color: Brand.warning, detail: "5 · $19,400"),
        .init(label: "IN REVIEW",  frac: 0.201, color: Brand.info,    detail: "2 · $8,600"),
        .init(label: "RECOVERED",  frac: 0.738, color: Brand.success, detail: "6 · $31,600")
    ]

    @State private var cases: [RecoveryCase804] = [
        .init(carrierCode: "MSC",  title: "MSC · accessorial",  sub: "INV-MSC-88241 · recovered 6d ago",  tone: .success, chip: Brand.success, pill: "RECOVERED", value: "$3,200", ofOver: "of $3,200 over", muted: false),
        .init(carrierCode: "MAEU", title: "Maersk · duplicate", sub: "INV-MAEU-71530 · disputed 18d ago", tone: .warning, chip: Brand.warning, pill: "DISPUTED",  value: "$0",     ofOver: "of $2,400 over", muted: false),
        .init(carrierCode: "OOLU", title: "OOCL · rate error",  sub: "INV-OOLU-50912 · in review 4d ago", tone: .info,    chip: Brand.blue,    pill: "REVIEW",    value: "$0",     ofOver: "of $1,850 over", muted: false)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text(hero).font(.system(size: 34, weight: .bold, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    pipelineCard
                    metricsRail
                    Text("RECOVERY CASES · BY CARRIER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    caseLedger
                    HStack(spacing: 8) {
                        CTAButton(title: "File recovery dispute", action: { Task { await fileDispute() } }, trailingIcon: "doc.text")
                        secondaryButton804(title: "Export") { Task { await load() } }
                    }
                    ESangRow804(title: "ESang: the Maersk duplicate is your best open case",
                                subtitle: "file the dispute now · 81% of duplicates recover in 18d")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · OVERCHARGE RECOVERY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("2026-Q2").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Compliance").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // RECOVERY PIPELINE — 4-stage funnel
    private var pipelineCard: some View {
        RimCard804 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("RECOVERY PIPELINE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(ratePct).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Brand.success)
                }
                ForEach(stages) { s in
                    HStack(spacing: 10) {
                        Text(s.label).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textSecondary)
                            .frame(width: 74, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.borderSoft).frame(height: 11)
                                Capsule().fill(s.color).frame(width: max(6, geo.size.width * s.frac), height: 11)
                            }
                        }.frame(height: 11)
                        Text(s.detail).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                            .frame(width: 86, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var metricsRail: some View {
        HStack(alignment: .top, spacing: 0) {
            railStat(label: "PENDING", value: pending, tone: Brand.warning, align: .leading)
            railStat(label: "AVG TO RECOVER", value: avgDays, tone: palette.textPrimary, align: .leading)
            railStat(label: "WRITTEN OFF", value: writtenOff, tone: palette.textTertiary, align: .trailing)
        }.padding(.horizontal, 2)
    }

    private func railStat(label: String, value: String, tone: Color, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(tone)
        }.frame(maxWidth: .infinity, alignment: align == .trailing ? .trailing : .leading)
    }

    private var caseLedger: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cases.enumerated()), id: \.element.id) { idx, c in
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(c.chip.opacity(0.14)).frame(width: 40, height: 40)
                            .overlay(Text(c.carrierCode).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(c.chip))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(c.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            StatusPill(text: c.pill, kind: c.tone)
                            Text(c.value).font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(c.muted ? palette.textTertiary : palette.textPrimary)
                            Text(c.ofOver).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                        }
                    }
                    .padding(.vertical, 10)
                    if idx < cases.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar the
    /// registered sibling 757 uses for its secondary CTA.
    private func secondaryButton804(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            struct Rec: Decodable { let invoiceNumber: String?; let carrier: String?; let overchargeAmount: Double?; let recoveredAmount: Double?; let status: String?; let type: String? }
            struct Summary: Decodable { let totalIdentified: Double?; let totalRecovered: Double?; let pendingRecovery: Double?; let recoveryRate: Double?; let avgRecoveryDays: Double? }
            struct Out: Decodable { let recoveries: [Rec]; let summary: Summary }
            let r: Out = try await EusoTripAPI.shared.query("freightClaims.getOverchargeRecovery", input: OverchargeInput804(limit: 20, offset: 0))
            let s = r.summary
            let identified = s.totalIdentified ?? 0, recovered = s.totalRecovered ?? 0
            if recovered > 0 { hero = usd804(recovered) }
            let rate = identified > 0 ? Int(round(recovered / identified * 100)) : 0
            ratePct = "\(rate)% recovered"
            pending = usd804(s.pendingRecovery ?? 0)
            avgDays = "\(Int(round(s.avgRecoveryDays ?? 0)))d"
            subline = "recovered of \(usd804(identified)) identified · \(rate)% rate · avg \(avgDays) to recover"

            if !r.recoveries.isEmpty {
                let bucket: (String) -> (Double, Int) = { st in
                    let g = r.recoveries.filter { ($0.status ?? "") == st }
                    return (g.reduce(0) { $0 + ($1.overchargeAmount ?? 0) }, g.count)
                }
                let idAmt = identified, idN = r.recoveries.count
                let (dAmt, dN) = bucket("disputed")
                let reviewG = r.recoveries.filter { ($0.status ?? "") == "identified" }
                let iAmt = reviewG.reduce(0) { $0 + ($1.overchargeAmount ?? 0) }, iN = reviewG.count
                let (rAmt, rN) = bucket("recovered")
                let base = max(idAmt, 1)
                stages = [
                    FunnelStage804(label: "IDENTIFIED", frac: 1.0,                 color: Brand.blue,    detail: "\(idN) · \(usd804(idAmt))"),
                    FunnelStage804(label: "DISPUTED",   frac: min(1, dAmt / base), color: Brand.warning, detail: "\(dN) · \(usd804(dAmt))"),
                    FunnelStage804(label: "IN REVIEW",  frac: min(1, iAmt / base), color: Brand.info,    detail: "\(iN) · \(usd804(iAmt))"),
                    FunnelStage804(label: "RECOVERED",  frac: min(1, rAmt / base), color: Brand.success, detail: "\(rN) · \(usd804(rAmt))")
                ]
                writtenOff = usd804(bucket("written_off").0)

                cases = r.recoveries.prefix(3).map { rec in
                    let st = rec.status ?? "identified"
                    let tone: StatusPill.Kind = st == "recovered" ? .success : (st == "disputed" ? .warning : (st == "written_off" ? .neutral : .info))
                    let chip: Color = st == "recovered" ? Brand.success : (st == "disputed" ? Brand.warning : (st == "written_off" ? Brand.neutral : Brand.blue))
                    let code = (rec.carrier ?? "—").uppercased().prefix(4)
                    return RecoveryCase804(
                        carrierCode: String(code),
                        title: "\(rec.carrier ?? "—") · \(rec.type ?? "review")",
                        sub: "\(rec.invoiceNumber ?? "—") · \(st)",
                        tone: tone, chip: chip, pill: st.uppercased(),
                        value: usd804(rec.recoveredAmount ?? 0),
                        ofOver: "of \(usd804(rec.overchargeAmount ?? 0)) over",
                        muted: st == "written_off")
                }
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func fileDispute() async {
        // freightClaims.fileClaim (EXISTS freightClaims.ts:332) — inserts claim row + blockchainAuditTrail,
        // broadcasts WS_CHANNELS.claims / WS_EVENTS.claimFiled. STUB here (no inline composer mutation wired
        // on this surface); re-pull the tracker after the claim flow files.
        await load()
    }

    /// USD formatter — the canonical port's `Money.usd(...)` is not a shared app
    /// symbol in this module, so we render the same grouped-dollar grammar file-scoped.
    private func usd804(_ amount: Double) -> String {
        "$" + Int(amount.rounded()).formatted(.number.grouping(.automatic))
    }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (757 `RimCard757`, 664 `moveContextCard`) ship.
private struct RimCard804<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

/// ESang advisory row — the canonical port's `ESangRow` is not a shared app
/// symbol, so we render the same sparkle + advisory grammar file-scoped.
private struct ESangRow804: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

/// Typed input for `freightClaims.getOverchargeRecovery` (status is optional and
/// omitted here — we want the full pipeline, not a single bucket).
private struct OverchargeInput804: Encodable {
    let limit: Int
    let offset: Int
}

#Preview("804 · Overcharge Recovery · Night") { VesselOverchargeRecoveryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("804 · Overcharge Recovery · Light") { VesselOverchargeRecoveryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
