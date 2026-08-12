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
//    READ (live):  vesselShipments.getCustomsEntries EXISTS :2062 — vesselProcedure QUERY (no input)
//        -> raw customs_declarations rows desc by id (entryNumber, status enum draft|filed|
//        under_review|cleared|held|rejected, declarationType, dutyAmount/declaredValue as
//        DECIMAL-strings, filedDate/clearedDate). The screen anchors on the MOST RECENT real
//        declaration — no fabricated ENT number/duty/dates; honest empty state when none exist.
//    READ (overlay): vesselShipments.getCBPEntryStatus EXISTS :1768 — vesselProcedure QUERY
//        { entryNumber:string } -> EntryStatus? { entryNumber, status, holds[], releaseDate,
//        liquidationDate, dutyOwed, lastUpdated } (DescartesABIService.getEntryStatus :269; returns
//        null when ABI credentials are unconfigured — the declaration row remains the floor).
//    ENGINE (write): vesselShipments.updateCustomsStatus EXISTS :697 — vesselProcedure MUTATION
//        { id:number, newStatus:enum(draft|filed|under_review|cleared|held|rejected), holdReasons?:[]}
//        -> { success, newStatus }; sets filedDate on filed, clearedDate on cleared, persists
//        holdReasons on held, inserts blockchainAuditTrail. Drives BOTH CTAs — getCustomsEntries now
//        surfaces the customsDeclarations row id, so the former named-gap stub is CLOSED: Advance
//        and Flag-hold fire the real mutation keyed on that id (the held reason-capture composer is
//        the remaining named follow-up; holdReasons is optional server-side).
//
//  ZERO-FALLBACK: nil-initialized — no design-time seeds. Every cell renders from the live
//  declaration row (or the ABI overlay) or em-dashes; the status pill reads the REAL status field,
//  never a hardcoded "UNDER REVIEW". StatusPill is the shared app pill (param is `kind:`, not the
//  canonical `tone:`); RimCard789 / secondaryButton789 are file-scoped bespoke helpers (the
//  canonical port's RimCard/SecondaryButton are not shared app symbols) built from sibling 757's
//  gradient-rim grammar to preserve the look.
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

    // ZERO-FALLBACK: nil/empty init — every cell renders live or em-dash.
    @State private var entryId: String? = nil            // real entryNumber (or "Entry #<id>")
    @State private var declarationId: Int? = nil         // customs_declarations row id (mutation key)
    @State private var subline: String? = nil
    @State private var currentTitle: String? = nil
    @State private var duty: String? = nil
    @State private var heroSub: String? = nil
    @State private var stageIndex: Int? = nil            // 0..3 -> draft, filed, under_review, cleared
    @State private var status: String? = nil             // the REAL status enum value — drives the pill
    @State private var noEntry = false

    @State private var steps: [CustomsStep789] = []
    @State private var actionError: String? = nil
    @State private var acting = false

    /// Theme.Palette exposes no `isDark` member (the canonical port assumed one); we derive it
    /// file-locally the same way EusoCardModifier does — by comparing the page token.
    private var isDark: Bool { palette.bgPage == Theme.dark.bgPage }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text(entryId ?? "—").font(.system(size: 28, weight: .bold, design: .monospaced)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Text(subline ?? "—").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if noEntry {
                    EusoEmptyState(systemImage: "doc.badge.clock",
                                   title: "No customs entries on file",
                                   subtitle: "The declaration status ladder appears here once an entry is drafted for a booking.")
                } else {
                    statusHero
                    Text("STATUS PROGRESSION · customs ladder")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    stepperCard
                    terminalAltsCard
                    if let ae = actionError {
                        Text(ae).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    HStack(spacing: 8) {
                        CTAButton(title: acting ? "Updating…" : "Advance → cleared", action: { Task { await advance() } }, trailingIcon: "checkmark.seal")
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
                    // The pill reads the REAL status field — never a hardcoded stage.
                    StatusPill(text: statusPillText, kind: statusPillKind)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(currentTitle ?? "—").font(.system(size: 26, weight: .heavy)).tracking(-0.3).foregroundStyle(palette.textPrimary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(duty ?? "—").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        Text("duty owed").font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i < (stageIndex ?? -1) ? AnyShapeStyle(LinearGradient.primary)
                                  : i == (stageIndex ?? -1) ? AnyShapeStyle(Brand.warning)
                                  : AnyShapeStyle(palette.borderFaint))
                            .frame(height: 8)
                    }
                }
                Text(heroSub ?? "—").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var statusPillText: String {
        guard let s = status, !s.isEmpty else { return "—" }
        return s.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private var statusPillKind: StatusPill.Kind {
        switch (status ?? "").lowercased() {
        case "cleared":             return .success
        case "held", "rejected":    return .danger
        case "under_review":        return .warning
        case "filed":               return .info
        default:                    return .neutral
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

    /// Raw customs_declarations row (vesselShipments.getCustomsEntries). Drizzle
    /// DECIMALs arrive as JSON strings and timestamps as ISO strings — every
    /// field decodes tolerantly so one odd cell never kills the ladder.
    private struct EntryRow789: Decodable {
        let id: Int?
        let entryNumber: String?
        let declarationType: String?
        let status: String?
        let dutyAmount: Double?
        let declaredValue: Double?
        let filedDate: String?
        let clearedDate: String?

        enum CodingKeys: String, CodingKey {
            case id, entryNumber, declarationType, status, dutyAmount, declaredValue, filedDate, clearedDate
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id              = try? c.decode(Int.self,    forKey: .id)
            entryNumber     = try? c.decode(String.self, forKey: .entryNumber)
            declarationType = try? c.decode(String.self, forKey: .declarationType)
            status          = try? c.decode(String.self, forKey: .status)
            dutyAmount      = Self.flex(c, .dutyAmount)
            declaredValue   = Self.flex(c, .declaredValue)
            filedDate       = try? c.decode(String.self, forKey: .filedDate)
            clearedDate     = try? c.decode(String.self, forKey: .clearedDate)
        }

        private static func flex(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
            if let d = try? c.decode(Double.self, forKey: key) { return d }
            if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
            return nil
        }
    }

    /// getCBPEntryStatus may return null (ABI unconfigured) — decode optionally; all fields optional.
    private struct EntryStatus789: Decodable { let status: String?; let dutyOwed: Double?; let lastUpdated: String? }
    private struct EmptyIn789: Encodable {}

    private func load() async {
        loading = true; loadError = nil
        do {
            // 1) Anchor on the MOST RECENT real declaration row (desc by id).
            let rows: [EntryRow789] = try await EusoTripAPI.shared.query(
                "vesselShipments.getCustomsEntries", input: EmptyIn789())
            guard let e = rows.first else {
                noEntry = true
                entryId = nil; declarationId = nil; subline = nil; currentTitle = nil
                duty = nil; heroSub = nil; stageIndex = nil; status = nil; steps = []
                loading = false
                return
            }
            noEntry = false
            declarationId = e.id
            entryId = e.entryNumber.flatMap { $0.isEmpty ? nil : $0 } ?? e.id.map { "Entry #\($0)" }
            duty = e.dutyAmount.map { "$" + String(format: "%.0f", $0) }
            apply(status: e.status, entry: e)

            // 2) ABI overlay — live CBP status when the gateway is configured;
            //    the declaration row remains the honest floor when it is not.
            if let num = e.entryNumber, !num.isEmpty {
                struct In789: Encodable { let entryNumber: String }
                let st: EntryStatus789? = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getCBPEntryStatus", input: In789(entryNumber: num))
                if let st {
                    if let s = st.status, !s.isEmpty { apply(status: s, entry: e) }
                    if let d = st.dutyOwed { duty = "$" + String(format: "%.0f", d) }
                }
            }
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func apply(status raw: String?, entry e: EntryRow789) {
        let order = ["draft", "filed", "under_review", "cleared"]
        let s = (raw ?? "").lowercased()
        status = s.isEmpty ? nil : s
        // held/rejected are terminal alternatives off the post-filing rail.
        let i = order.firstIndex(of: s) ?? ((s == "held" || s == "rejected") ? 2 : nil) ?? 0
        stageIndex = i
        currentTitle = s.isEmpty ? nil : s.replacingOccurrences(of: "_", with: " ").capitalized

        let day10: (String?) -> String? = { iso in iso.flatMap { $0.isEmpty ? nil : String($0.prefix(10)) } }
        let filedSub = day10(e.filedDate).map { "filedDate \($0) · ABI / ACE" } ?? "sets filedDate · ABI / ACE"
        let clearedSub = day10(e.clearedDate).map { "clearedDate \($0) · CBP release" } ?? "sets clearedDate · CBP release"
        let subs = ["operator drafted entry", filedSub, "CBP document review", clearedSub]

        steps = order.enumerated().map { idx, key in
            let state: StepState789 = idx < i ? .done : (idx == i ? .current : .next)
            let pill = state == .done ? "DONE" : (state == .current ? "CURRENT" : "NEXT")
            return CustomsStep789(title: key.replacingOccurrences(of: "_", with: " ").capitalized,
                                  sub: subs[safe789: idx] ?? "", state: state, pill: pill)
        }

        let typeLabel = e.declarationType.flatMap { $0.isEmpty ? nil : $0.capitalized } ?? "—"
        let stageLabel = (s == "held" || s == "rejected") ? s : "stage \(i + 1) of 4"
        subline = "\(typeLabel) · duty \(duty ?? "—") · \(stageLabel)"
        if let f = day10(e.filedDate) {
            heroSub = day10(e.clearedDate).map { "filed \(f) · cleared \($0)" } ?? "filed \(f)"
        } else {
            heroSub = "not yet filed"
        }
    }

    /// updateCustomsStatus{ id, newStatus:"cleared" } — REAL mutation (vesselShipments.ts:697,
    /// sets clearedDate + blockchainAuditTrail). The declaration id is now surfaced by
    /// getCustomsEntries, so the former named-gap stub is closed.
    private func advance() async { await setStatus("cleared") }
    /// updateCustomsStatus{ id, newStatus:"held" } — REAL mutation; the reason-capture
    /// composer remains the named follow-up (holdReasons optional server-side).
    private func flagHold() async { await setStatus("held") }

    private func setStatus(_ newStatus: String) async {
        guard let id = declarationId else { return }
        acting = true; actionError = nil
        struct In: Encodable { let id: Int; let newStatus: String }
        struct Out: Decodable { let success: Bool?; let newStatus: String? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "vesselShipments.updateCustomsStatus", input: In(id: id, newStatus: newStatus))
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
        acting = false
    }
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
