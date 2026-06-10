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
//  ZERO-FALLBACK (2026-06-09 · B18 fix): the previous build rendered a permanent fabricated story
//  ("$34,200" hero · "38h" SLA · invented blocking items · CLM-260524-A38FB12C7E) that no load path
//  ever overwrote. Now the screen anchors to a REAL claim: freightClaims.getClaims(limit:1) resolves
//  the newest live claim id, freightClaims.getClaimById(:246) hydrates the claim amount (decoded
//  tolerantly — the server currently hardcodes amount:0, fixed in a parallel server lane; 0/absent
//  renders an em-dash, never an invented figure), and getClaimWorkflow drives the lifecycle strip.
//  SLA hours and blocking items have NO server source today → em-dash + honest "none on file" row.
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

    // B18: nil/empty initial state — everything below hydrates from the live claim.
    @State private var claim: Claim808? = nil
    @State private var stages: [ClaimStage808] = []
    @State private var currentStepName: String? = nil
    @State private var nextStepName: String? = nil
    @State private var stageOf: String = "—"

    /// Blocking items have NO server source today (getClaimWorkflow carries none) —
    /// the ledger renders its honest "none on file" row until a real feed exists.
    private let blocking: [BlockingItem808] = []

    // MARK: Derived display (live claim or em-dash — never an invented figure)

    private var claimTotal: String {
        guard let amt = claim?.amount, amt > 0 else { return "—" }
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amt)) ?? "$\(Int(amt))"
    }
    private var subline: String {
        guard let c = claim else { return "No claim resolved yet" }
        var parts = [c.claimNumber ?? c.id ?? "—"]
        if let o = c.load?.origin, let d = c.load?.destination, !o.isEmpty, !d.isEmpty { parts.append("\(o) → \(d)") }
        if let t = c.type, !t.isEmpty { parts.append(t.replacingOccurrences(of: "_", with: " ")) }
        return parts.joined(separator: " · ")
    }
    private var claimSub: String {
        guard let c = claim else { return "—" }
        let d = c.description ?? ""
        return d.isEmpty ? "claim total" : d
    }
    private var claimMeta: String {
        guard let c = claim else { return "—" }
        var parts: [String] = []
        if let ln = c.load?.loadNumber, !ln.isEmpty, ln != "-" { parts.append(ln) }
        if let fd = c.filedDate, !fd.isEmpty { parts.append("filed \(fd)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
    private var stagePill: String {
        if let s = currentStepName, !s.isEmpty { return s.uppercased() }
        return (claim?.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased()
    }
    private var headerBadge: String {
        guard let c = claim else { return "—" }
        let t = (c.type ?? "claim").replacingOccurrences(of: "_", with: " ").uppercased()
        let s = (c.status ?? "open").replacingOccurrences(of: "_", with: " ").uppercased()
        return "\(t) · \(s)"
    }
    private var lifecycleCaption: String {
        if let next = nextStepName { return "Current: \(currentStepName ?? "—") · next: \(next)" }
        return currentStepName.map { "Current: \($0)" } ?? "—"
    }

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
                } else if claim == nil {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No claims on file",
                                   subtitle: "File a freight claim from a booking to track its lifecycle here.")
                } else {
                    claimHero
                    Text("CLAIM LIFECYCLE · getClaimWorkflow · STAGE \(stageOf)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    lifecycleCard
                    Text("BLOCKING ITEMS · addClaimEvidence (STUB · needs picker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    blockingCard
                    esangCard
                    HStack(spacing: 8) {
                        CTAButton(title: "Advance stage",
                                  action: { Task { await advance() } },
                                  trailingIcon: "arrow.forward.circle")
                            .disabled(claim?.id == nil)
                            .opacity(claim?.id == nil ? 0.45 : 1)
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
                // Live claim type · status — em-dash until a real claim resolves.
                Text(headerBadge).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(claim == nil ? palette.textTertiary : Brand.danger)
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
                    Text("CLAIM TOTAL · getClaimById").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    // B18: the hero renders the REAL decoded amount — em-dash for 0/absent
                    // (server amount:0 stub is being fixed in a parallel lane).
                    Text(claimTotal).font(.system(size: 44, weight: .bold)).tracking(-1)
                        .foregroundStyle(palette.textPrimary).monospacedDigit()
                    Text(claimSub).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.textSecondary).lineLimit(2)
                    Text(claimMeta).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(text: stagePill, kind: .warning)
                    // No SLA feed exists server-side — honest em-dash, never an invented clock.
                    Text("—").font(.system(size: 20, weight: .heavy)).tracking(-0.3).foregroundStyle(palette.textTertiary).monospacedDigit()
                    Text("SLA · NOT TRACKED").font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(palette.textTertiary)
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
            if blocking.isEmpty {
                Text("No blocking items on file — evidence and signature blockers appear here when the claims feed carries them.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            }
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
                // Derived from the LIVE workflow ladder only — no fabricated advice.
                Text(nextStepName.map { "Next stage: \($0)" } ?? "Workflow up to date")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · \(lifecycleCaption)").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
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

    // MARK: Data — anchors to a REAL claim, then decodes the REAL server shapes.

    private func load() async {
        loading = true; loadError = nil
        do {
            // 1. Resolve the newest live claim (real `claim_<n>` id) — the workflow
            //    may never anchor to an invented claim reference.
            struct ClaimsIn808: Encodable { let limit: Int; let offset: Int }
            struct ClaimsResp808: Decodable { let claims: [Claim808] }
            let list: ClaimsResp808 = try await EusoTripAPI.shared.query(
                "freightClaims.getClaims", input: ClaimsIn808(limit: 1, offset: 0))
            guard let anchor = list.claims.first, let cid = anchor.id else {
                claim = nil; stages = []; loading = false
                return
            }

            // 2. Hydrate the claim detail (amount · lane · parties) + the workflow ladder.
            struct ByIdIn808: Encodable { let id: String }
            struct WfIn808: Encodable { let claimId: String }
            async let detail: Claim808? = EusoTripAPI.shared.query(
                "freightClaims.getClaimById", input: ByIdIn808(id: cid))
            async let wf: Workflow808 = EusoTripAPI.shared.query(
                "freightClaims.getClaimWorkflow", input: WfIn808(claimId: cid))
            let (d, w) = try await (detail, wf)
            claim = d ?? anchor

            if let s = w.steps, !s.isEmpty {
                // currentStep is 1-indexed on the wire; clamp into range.
                let cur = max(1, min(w.currentStep ?? 1, s.count))
                stages = s.map { st in
                    let n = st.step ?? 0
                    let state: StageState808 = (st.completed == true)
                        ? .done
                        : (n == cur ? .active : .future)
                    return ClaimStage808(label: shortLabel(st.name),
                                         date: "",
                                         state: state)
                }
                stageOf = "\(cur) / \(s.count)"
                currentStepName = s.first { ($0.step ?? 0) == cur }?.name
                nextStepName = s.first { ($0.step ?? 0) == cur + 1 }?.name
            } else {
                stages = []; stageOf = "—"; currentStepName = nil; nextStepName = nil
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Trim long server step names ("Initial Review") to the strip's compact slot.
    private func shortLabel(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "-" }
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return String(first.prefix(9))
    }

    private func advance() async {
        // freightClaims.updateClaimStatus EXISTS :393 — pushes the next status on the
        // REAL anchored claim, then re-loads the live workflow. Gated on a live id.
        guard let cid = claim?.id else { return }
        struct AdvanceIn808: Encodable { let id: String; let status: String }
        struct Ack808: Decodable { let success: Bool? }
        do {
            let _: Ack808 = try await EusoTripAPI.shared.mutation(
                "freightClaims.updateClaimStatus",
                input: AdvanceIn808(id: cid, status: "investigating"))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        await load()
    }

    private func document() async {
        // addClaimEvidence EXISTS :437 but attaching needs a file picker + upload
        // (out of this screen's scope) — STUB · named-gap surfaced to the-oath.
        await load()
    }
}

// MARK: - Wire shapes (mirror freightClaims.getClaims / getClaimById / getClaimWorkflow)

private struct ClaimLoad808: Decodable {
    let loadNumber: String?
    let origin: String?
    let destination: String?
    let commodity: String?
}

private struct Claim808: Decodable {
    let id: String?
    let claimNumber: String?
    let type: String?
    let status: String?
    let description: String?
    let amount: Double?
    let filedDate: String?
    let load: ClaimLoad808?

    private enum CodingKeys: String, CodingKey { case id, claimNumber, type, status, description, amount, filedDate, load }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try? c.decodeIfPresent(String.self, forKey: .id)
        claimNumber = try? c.decodeIfPresent(String.self, forKey: .claimNumber)
        type        = try? c.decodeIfPresent(String.self, forKey: .type)
        status      = try? c.decodeIfPresent(String.self, forKey: .status)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        // Tolerant amount: Double on the wire today (hardcoded 0 server-side, fix in
        // flight) — also accept a DECIMAL-string so the parallel server fix can land
        // either shape without re-breaking this hero (zero-fallback doctrine).
        if let d = try? c.decodeIfPresent(Double.self, forKey: .amount) {
            amount = d
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .amount) {
            amount = Double(s)
        } else {
            amount = nil
        }
        filedDate   = try? c.decodeIfPresent(String.self, forKey: .filedDate)
        load        = try? c.decodeIfPresent(ClaimLoad808.self, forKey: .load)
    }
}

private struct Step808: Decodable { let step: Int?; let name: String?; let completed: Bool? }
private struct Workflow808: Decodable { let currentStep: Int?; let steps: [Step808]? }

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
