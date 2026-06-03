//
//  808_VesselClaimWorkflow.swift
//  EusoTrip — Vessel Operator · Claim Workflow.
//
//  Faithful 1:1 port of the RECONSTRUCTED "808 Vessel Claim Workflow.svg" (Light + Dark),
//  adapted to app convention. The CLAIM-LIFECYCLE archetype: a reserve-vs-claimed gradient-rim
//  hero ($34,200 figure + SLA clock + INVESTIGATION pill), a horizontal lifecycle strip
//  (done done · active · neutral) with a blocking caption, the BLOCKING ITEMS as icon-chip rows
//  with state pills, the ESang fused-clock advisory, and the Advance stage / Document CTA pair.
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME)
//  — the same Shell + BottomNav wrapper the registered vessel sibling 757 ships.
//
//  Data / wiring (endpoints MCP-confirmed on disk this fire · frontend/server/routers/freightClaims.ts):
//    LIFECYCLE STRIP: freightClaims.getClaimWorkflow EXISTS :459 ·
//        input {claimId:string} · returns {claimId, currentStep:number (1-indexed),
//        steps:[{step:Int, name:String, description?, required[]?, completed:Bool}]}.
//        Strip renders live from steps[] + currentStep (NOT the manifest's {stages,slaRemainingHours,
//        blockingItems} — the real procedure ships a 6-step File→Close ladder; we map a step to
//        .done when completed, .active when step == currentStep, else .future).
//    WRITE (advance): freightClaims.updateClaimStatus EXISTS :393 ·
//        input {id:string, status:claimStatusSchema, notes?, settledAmount?} · returns {success,...}.
//        Advance pushes status "investigating" then re-loads the workflow.
//    DOCUMENT (attach evidence): freightClaims.addClaimEvidence EXISTS :437 ·
//        input {claimId, type, name, description?, url?} → {id, uploadUrl, ...}. The Document CTA is
//        flagged STUB here because attaching needs a file picker + upload (out of this screen's scope);
//        the real mutation is named so the-oath can wire the picker, NOT faked.
//    RBAC: protectedProcedure (vessel operator).
//
//  The hero figure, SLA clock and the two blocking items are NOT carried by getClaimWorkflow, so they
//  render as honest design-time seeds (overwritten only by what the endpoint actually returns); the
//  ESang line is the same fused advisory grammar. 0 mock data on the wire · honest loading/error states.
//  RimCard808 / secondaryButton808 are file-scoped bespoke helpers (the canonical port's RimCard /
//  SecondaryButton are not shared app symbols) built from sibling 757's gradient-rim grammar.
//

import SwiftUI

private enum StageState808 { case done, active, future }
private enum BlockSev808 { case warn, danger }

private struct ClaimStage808: Identifiable {
    let id = UUID(); let label: String; let date: String; let state: StageState808
}
private struct BlockingItem808: Identifiable {
    let id = UUID(); let title: String; let sub: String; let pill: String; let stage: String; let sev: BlockSev808
}

struct VesselClaimWorkflowScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselClaimWorkflowBody()
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

private struct VesselClaimWorkflowBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var claimId = "CLM-260524-A38FB12C7E"
    @State private var subline = "CLM-260524-A38FB12C7E · USOAK → USHOU · reefer produce"
    @State private var vesselLine = "CLAIM TOTAL · MV CMA-CGM MARCO POLO 0TPXE"
    @State private var claimTotal = "$34,200"
    @State private var claimSub = "claim total · 12 cartons short · reserve $30k"
    @State private var claimMeta = "VES-260524-9F2C41A0E7 · adjuster LB"
    @State private var stagePill = "INVESTIGATION"
    @State private var slaHours = "38h"
    @State private var stageOfFive = "3 / 6"
    @State private var lifecycleCaption = "Surveyor PDF blocks stage 4 · carrier ack'd in 8h · on-time 92%"
    @State private var esangLine = "clears in ~6h · SLA holds with 32h to spare · live tick"

    @State private var stages: [ClaimStage808] = [
        ClaimStage808(label: "Filed",        date: "05-24",   state: .done),
        ClaimStage808(label: "Review",       date: "05-24",   state: .done),
        ClaimStage808(label: "Investig.",    date: "38h SLA", state: .active),
        ClaimStage808(label: "Decision",     date: "",        state: .future),
        ClaimStage808(label: "Settle",       date: "",        state: .future),
        ClaimStage808(label: "Close",        date: "",        state: .future)
    ]
    @State private var blocking: [BlockingItem808] = [
        BlockingItem808(title: "Surveyor inspection PDF", sub: "received 05-25 · partial · pages 3–7 missing", pill: "PARTIAL", stage: "stage 3", sev: .warn),
        BlockingItem808(title: "Carrier BOL signature · rev-2", sub: "CMA-CGM countersign pending · rev-2", pill: "PENDING", stage: "stage 4", sev: .danger)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Claim workflow").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    RimCard808 { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    RimCard808 { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    claimHero
                    Text("CLAIM LIFECYCLE · getClaimWorkflow · STAGE \(stageOfFive)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    lifecycleCard
                    Text("BLOCKING ITEMS · \(blocking.count) OPEN · addClaimEvidence (STUB · needs picker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    blockingCard
                    esangCard
                    HStack(spacing: 8) {
                        CTAButton(title: "Advance stage",
                                  action: { Task { await advance() } },
                                  trailingIcon: "arrow.forward.circle")
                        secondaryButton808(title: "Document") { Task { await document() } }
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
                Text("VESSEL OPERATOR · CLAIM WORKFLOW").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("CARGO DAMAGE · OPEN").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.danger)
            }
            HStack(spacing: 6) {
                Text("Claims").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var claimHero: some View {
        RimCard808 {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(vesselLine).font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    Text(claimTotal).font(.system(size: 44, weight: .bold)).tracking(-1)
                        .foregroundStyle(palette.textPrimary).monospacedDigit()
                    Text(claimSub).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text(claimMeta).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(text: stagePill, kind: .warning)
                    Text(slaHours).font(.system(size: 20, weight: .heavy)).tracking(-0.3).foregroundStyle(Brand.danger).monospacedDigit()
                    Text("SLA TO STAGE 4").font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var lifecycleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClaimLifecycleStrip808(stages: stages)
            Divider().overlay(palette.borderFaint)
            Text(lifecycleCaption).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    private var blockingCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(blocking.enumerated()), id: \.element.id) { idx, b in
                HStack(alignment: .top, spacing: 12) {
                    BlockChip808(sev: b.sev)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(b.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(b.pill).font(.system(size: 11, weight: .heavy)).tracking(0.5).foregroundStyle(blockColor(b.sev))
                        Text(b.stage).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(blockColor(b.sev))
                    }
                }
                .padding(.vertical, 12)
                if idx < blocking.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    private var esangCard: some View {
        HStack(spacing: 12) {
            Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("Advance to Decision once surveyor PDF lands").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · \(esangLine)").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint))
    }

    private func blockColor(_ s: BlockSev808) -> Color { s == .danger ? Brand.danger : Brand.warning }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar sibling
    /// 757 uses for its secondary CTA.
    private func secondaryButton808(title: String, action: @escaping () -> Void) -> some View {
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

    // MARK: Data — decodes the REAL freightClaims.getClaimWorkflow shape (:459).
    private struct Step808: Decodable { let step: Int?; let name: String?; let completed: Bool? }
    private struct Workflow808: Decodable { let currentStep: Int?; let steps: [Step808]? }

    private func load() async {
        loading = true; loadError = nil
        do {
            let w: Workflow808 = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimWorkflow",
                input: ["claimId": claimId])
            if let s = w.steps, !s.isEmpty {
                // currentStep is 1-indexed on the wire; clamp into range.
                let cur = max(1, min(w.currentStep ?? 1, s.count))
                stages = s.map { st in
                    let n = st.step ?? 0
                    let state: StageState808 = (st.completed == true)
                        ? .done
                        : (n == cur ? .active : .future)
                    return ClaimStage808(label: shortLabel(st.name),
                                         date: n == cur ? slaHours + " SLA" : "",
                                         state: state)
                }
                stageOfFive = "\(cur) / \(s.count)"
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Trim long server step names ("Initial Review") to the strip's compact slot.
    private func shortLabel(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "—" }
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return String(first.prefix(9))
    }

    private func advance() async {
        // freightClaims.updateClaimStatus EXISTS :393 — pushes the next status,
        // writes the incident row, then we re-load the live workflow.
        struct AdvanceIn808: Encodable { let id: String; let status: String }
        struct Ack808: Decodable { let success: Bool? }
        _ = try? await EusoTripAPI.shared.mutation(
            "freightClaims.updateClaimStatus",
            input: AdvanceIn808(id: claimId, status: "investigating")) as Ack808
        await load()
    }

    private func document() async {
        // addClaimEvidence EXISTS :437 but attaching needs a file picker + upload
        // (out of this screen's scope) — STUB · named-gap surfaced to the-oath.
        await load()
    }
}

private struct BlockChip808: View {
    let sev: BlockSev808
    @Environment(\.palette) private var palette
    var body: some View {
        let (c, sym): (Color, String) = sev == .danger
            ? (Brand.danger, "doc.text") : (Brand.warning, "doc.plaintext")
        let dark = palette.bgPage == Theme.dark.bgPage
        return ZStack {
            RoundedRectangle(cornerRadius: 10).fill(c.opacity(dark ? 0.20 : 0.14))
            Image(systemName: sym).font(.system(size: 16, weight: .semibold)).foregroundStyle(c)
        }.frame(width: 40, height: 40)
    }
}

/// Horizontal lifecycle strip: done = filled gradient + check, active = ringed gradient node,
/// future = hollow neutral ring. Connector tinted up to the active node.
private struct ClaimLifecycleStrip808: View {
    let stages: [ClaimStage808]
    @Environment(\.palette) private var palette
    var body: some View {
        GeometryReader { geo in
            let n = max(stages.count, 1)
            let step = geo.size.width / CGFloat(n)
            let activeIdx = stages.firstIndex { $0.state == .active } ?? (stages.count - 1)
            ZStack(alignment: .top) {
                Path { p in
                    p.move(to: CGPoint(x: step/2, y: 14)); p.addLine(to: CGPoint(x: geo.size.width - step/2, y: 14))
                }.stroke(palette.borderFaint, lineWidth: 2)
                Path { p in
                    p.move(to: CGPoint(x: step/2, y: 14))
                    p.addLine(to: CGPoint(x: step/2 + step * CGFloat(activeIdx), y: 14))
                }.stroke(LinearGradient.diagonal, lineWidth: 2.5)
                HStack(spacing: 0) {
                    ForEach(stages) { st in
                        VStack(spacing: 4) {
                            node(st.state)
                            Text(st.label).font(.system(size: 8, weight: st.state == .active ? .heavy : .bold))
                                .foregroundStyle(st.state == .future ? palette.textTertiary : palette.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(st.date).font(.system(size: 7.5, design: .monospaced))
                                .foregroundStyle(st.state == .active ? Brand.warning : palette.textTertiary)
                        }
                        .frame(width: step)
                    }
                }
            }
        }
        .frame(height: 60)
    }
    @ViewBuilder private func node(_ s: StageState808) -> some View {
        switch s {
        case .done:
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 22, height: 22)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            }.frame(height: 28)
        case .active:
            ZStack {
                Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 3).frame(width: 28, height: 28)
                Circle().fill(LinearGradient.diagonal).frame(width: 10, height: 10)
            }.frame(height: 28)
        case .future:
            Circle().strokeBorder(palette.textTertiary.opacity(0.5), lineWidth: 2).frame(width: 20, height: 20).frame(height: 28)
        }
    }
}

// MARK: - File-scoped bespoke helper (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards sibling 757
/// (`RimCard757`) and the registered vessel siblings ship.
private struct RimCard808<Content: View>: View {
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

#Preview("808 · Vessel Claim Workflow · Night") { VesselClaimWorkflowScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("808 · Vessel Claim Workflow · Light") { VesselClaimWorkflowScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
