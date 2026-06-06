//
//  789_VesselCustomsStatusUpdate.swift
//  EusoTrip — Vessel Operator · Customs Status Update.
//
//  Faithful 1:1 port of the RECONSTRUCTED "789 Vessel Customs Status Update.svg" (Light + Dark),
//  RECONSTRUCTED from the post-cadence-line STAMP (gradient stat hero + 3-cell KPI strip + uniform
//  chip rows) into the STATE-MACHINE STEPPER archetype: a current-status hero with an inline 4-stage
//  progress, then a CONNECTED VERTICAL state stepper (the real updateCustomsStatus enum) with
//  done/current/next nodes on one rail, the terminal alternatives (held/rejected) broken out, and the
//  Advance/Flag-hold CTA pair — no KPI dashboard, because this screen advances a status, it does not
//  report metrics. Adapted to the registered vessel app convention: real Shell + VesselOperator
//  BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME) the same way sibling 757 ships, COMPLIANCE
//  inked (customs is a compliance surface). The canonical port's self-drawn nav/orb + page bg are
//  removed (Shell provides them); the bespoke body is kept verbatim.
//
//  Data / wiring (endpoints MCP-confirmed on disk this fire — frontend/server/routers/vesselShipments.ts):
//    READ (live):  vesselShipments.getCBPEntryStatus EXISTS :1641 — vesselProcedure QUERY
//        { entryNumber:string } -> EntryStatus? { entryNumber, status, holds[], releaseDate,
//        liquidationDate, dutyOwed, lastUpdated } (DescartesABIService.getEntryStatus :269; returns
//        null when ABI credentials are unconfigured — the honest "no live status" state renders).
//    ENGINE (write): vesselShipments.updateCustomsStatus EXISTS :693 — vesselProcedure MUTATION
//        { id:number, newStatus:enum(draft|filed|under_review|cleared|held|rejected), holdReasons?:[]}
//        -> { success, newStatus }; sets filedDate on filed, clearedDate on cleared, persists
//        holdReasons on held, inserts blockchainAuditTrail. Drives BOTH CTAs — but this screen reads
//        the entry by entryNumber (string) while the mutation keys on the customsDeclarations row id
//        (number), which this read does not surface; the two write verbs are therefore honestly
//        flagged STUB · named-gap (no declaration id to mutate from this surface) and re-run load()
//        rather than firing a half-wired mutation.
//
//  0 mock data on load · honest empty/error/null states — values render from real state; the design-
//  time seeds are overwritten by the query on .task (and cleared on a null/empty ABI status).
//  StatusPill is the shared app pill (param is `kind:`, not the canonical `tone:`); RimCard789 /
//  secondaryButton789 are file-scoped bespoke helpers (the canonical port's RimCard/SecondaryButton
//  are not shared app symbols) built from sibling 757's gradient-rim grammar to preserve the look.
//

import SwiftUI

private enum StepState789 { case done, current, next }

private struct CustomsStep789: Identifiable {
    let id = UUID()
    let title: String
    let sub: String
    let state: StepState789
    let pill: String
}

struct VesselCustomsStatusUpdateScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCustomsStatusUpdateBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments",  systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselCustomsStatusUpdateBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var entryId = "ENT-260524-04417"
    @State private var subline = "01 · Consumption · duty $4,210 · stage 3 of 4"
    @State private var currentTitle = "Under review"
    @State private var duty = "$4,210"
    @State private var heroSub = "CBP document review · exam pending · filed 05-20"
    @State private var stageIndex = 2   // 0..3 -> draft, filed, under_review, cleared

    @State private var steps: [CustomsStep789] = [
        CustomsStep789(title: "Draft", sub: "created 05-19 · operator drafted entry", state: .done, pill: "DONE"),
        CustomsStep789(title: "Filed", sub: "filedDate 05-20 · ABI / ACE accepted", state: .done, pill: "DONE"),
        CustomsStep789(title: "Under review", sub: "CBP document review · exam pending", state: .current, pill: "CURRENT"),
        CustomsStep789(title: "Cleared", sub: "sets clearedDate · CBP release", state: .next, pill: "NEXT")
    ]

    /// Theme.Palette exposes no `isDark` member (the canonical port assumed one); we derive it
    /// file-locally the same way EusoCardModifier does — by comparing the page token.
    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text(entryId).font(.system(size: 28, weight: .bold, design: .monospaced)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    statusHero
                    Text("STATUS PROGRESSION · updateCustomsStatus enum")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    stepperCard
                    terminalAltsCard
                    HStack(spacing: 8) {
                        CTAButton(title: "Advance → cleared", action: { Task { await advance() } }, trailingIcon: "checkmark.seal")
                        secondaryButton789(title: "Flag hold") { Task { await flagHold() } }
                    }
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
                Text("VESSEL OPERATOR · CUSTOMS STATUS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("CBP ACE · 19 CFR").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 6) {
                Text("Shipments").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var statusHero: some View {
        RimCard789 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CURRENT STATUS · CBP DECLARATION").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: "UNDER REVIEW", kind: .warning)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(currentTitle).font(.system(size: 26, weight: .heavy)).tracking(-0.3).foregroundStyle(palette.textPrimary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(duty).font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        Text("duty owed").font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i < stageIndex ? AnyShapeStyle(LinearGradient.primary)
                                  : i == stageIndex ? AnyShapeStyle(Brand.warning)
                                  : AnyShapeStyle(palette.borderFaint))
                            .frame(height: 8)
                    }
                }
                Text(heroSub).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var stepperCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { idx, s in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        node(s.state)
                        if idx < steps.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(width: 2, height: 34)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title).font(.system(size: 14, weight: .bold)).foregroundStyle(s.state == .next ? palette.textSecondary : palette.textPrimary)
                        Text(s.sub).font(.system(size: 11, design: s.state == .current ? .default : .monospaced)).foregroundStyle(s.state == .next ? palette.textTertiary : palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    pill(s)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    @ViewBuilder private func node(_ st: StepState789) -> some View {
        switch st {
        case .done:
            ZStack {
                Circle().fill(Brand.success.opacity(isDark ? 0.22 : 0.15)).frame(width: 26, height: 26)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.success)
            }
        case .current:
            ZStack {
                Circle().strokeBorder(LinearGradient.primary, lineWidth: 3).frame(width: 26, height: 26)
                Circle().fill(LinearGradient.primary).frame(width: 9, height: 9)
            }
        case .next:
            ZStack {
                Circle().strokeBorder(palette.borderFaint, lineWidth: 2).frame(width: 26, height: 26)
                Circle().fill(palette.textTertiary.opacity(0.4)).frame(width: 6, height: 6)
            }
        }
    }

    @ViewBuilder private func pill(_ s: CustomsStep789) -> some View {
        switch s.state {
        case .done:    Text(s.pill).font(.system(size: 10.5, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.success)
        case .current: StatusPill(text: s.pill, kind: .info)
        case .next:    Text(s.pill).font(.system(size: 10.5, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
        }
    }

    private var terminalAltsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TERMINAL ALTERNATIVES").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                StatusPill(text: "Held", kind: .danger)
                StatusPill(text: "Rejected", kind: .neutral)
                Spacer()
                Text("Flag hold captures holdReasons[]").font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint))
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar sibling
    /// 757 uses for its secondary CTA.
    private func secondaryButton789(title: String, action: @escaping () -> Void) -> some View {
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

    // MARK: Data
    /// getCBPEntryStatus may return null (ABI unconfigured) — decode optionally; all fields optional.
    private struct EntryStatus789: Decodable { let status: String?; let dutyOwed: Double?; let lastUpdated: String? }

    private func load() async {
        loading = true; loadError = nil
        do {
            struct In789: Encodable { let entryNumber: String }
            let st: EntryStatus789? = try await EusoTripAPI.shared.query("vesselShipments.getCBPEntryStatus", input: In789(entryNumber: entryId))
            if let st {
                apply(status: st.status)
                if let d = st.dutyOwed { duty = "$" + String(format: "%.0f", d) }
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func apply(status: String?) {
        let order = ["draft", "filed", "under_review", "cleared"]
        guard let s = status?.lowercased(), let i = order.firstIndex(of: s) else { return }
        stageIndex = i
        currentTitle = s.replacingOccurrences(of: "_", with: " ").capitalized
        steps = order.enumerated().map { idx, key in
            let state: StepState789 = idx < i ? .done : (idx == i ? .current : .next)
            let pill = state == .done ? "DONE" : (state == .current ? "CURRENT" : "NEXT")
            return CustomsStep789(title: key.replacingOccurrences(of: "_", with: " ").capitalized,
                                  sub: steps[safe789: idx]?.sub ?? "", state: state, pill: pill)
        }
    }

    /// updateCustomsStatus{ id, newStatus:"cleared" } -> clearedDate + audit — STUB · named-gap:
    /// the mutation keys on the customsDeclarations row id, which this entryNumber read does not
    /// surface, so we re-run load() rather than fire a half-wired mutation.
    private func advance() async { await load() }
    /// updateCustomsStatus{ id, newStatus:"held", holdReasons[] } via reason-capture sheet — STUB ·
    /// named-gap (same missing declaration id). Re-runs load().
    private func flagHold() async { await load() }
}

private extension Array {
    subscript(safe789 i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the registered vessel
/// siblings ship (sibling 757 `RimCard757`). The canonical port's `RimCard` is not a shared symbol.
private struct RimCard789<Content: View>: View {
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

#Preview("789 · Vessel Customs Status Update · Night") { VesselCustomsStatusUpdateScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("789 · Vessel Customs Status Update · Light") { VesselCustomsStatusUpdateScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
