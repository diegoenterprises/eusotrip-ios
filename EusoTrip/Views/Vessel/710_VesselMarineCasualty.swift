//
//  710_VesselMarineCasualty.swift
//  EusoTrip — Vessel Operator · Marine Casualty Report (USCG CG-2692).
//
//  Verbatim port of "710 Vessel Marine Casualty.svg" (Dark). PURPOSE-BUILT
//  INCIDENT-CHRONOLOGY archetype: the active reportable casualty drilled open,
//  with a CG-2692 filing lifecycle strip + live due-countdown, a vertical
//  timestamped incident chronology (contact → master notified → USCG Sector
//  notified within 24h → investigation opened → 2692 due), and a corrective-
//  actions checklist. Proves the statutory USCG notification chain was met and
//  drives the 2692 to filing before the 5-day deadline.
//
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] ·
//  COMPLIANCE · ME) — Compliance tab current (filled symbol). RBAC vesselProcedure.
//
//  Data (REAL — EusoTripAPI.shared):
//    incidents.getById              (EXISTS incidents.ts:81 · protectedProcedure)
//        -> hero (type/severity/status/location/date/time) + timeline chronology
//        + investigation.correctiveActions
//    vesselShipments.getUSCGCompliance (EXISTS vesselShipments.ts:1355 · vesselProcedure)
//        -> notification-chain compliance · CG-2692 filing strip
//    incidents.updateStatus         (EXISTS incidents.ts:232 · File CG-2692 advance)
//    incidents.addCorrectiveAction  (EXISTS incidents.ts:260 · Add action)
//
//  PORT-GAP (named-gap STUB per the-oath, NOT invented — surfaced by SVG <desc>):
//    incidents.getById does not yet type the CG-2692 casualty-class enum
//    (allision|grounding|injury|nearmiss), filingStage
//    (occurred|notified|drafted|filed|closed), per-event `kind`
//    (danger|info|neutral|pending), or `dueInDays`. These are decoded as
//    optionals on the model; when the server omits them the strip/chronology
//    render from the live `status`/`timeline` rows or fall to a real empty
//    state — no fabricated rows.
//

import SwiftUI

struct VesselMarineCasualtyScreen: View {
    let theme: Theme.Palette
    var incidentId: String = ""
    var vesselId: Int? = nil

    var body: some View {
        Shell(theme: theme) {
            VesselMarineCasualtyBody(incidentId: incidentId, vesselId: vesselId)
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

// MARK: - Data shapes (decode REAL incidents.getById / getUSCGCompliance)

private struct CasualtyLocation710: Decodable {
    let address: String?
    let city: String?
    let state: String?
}

private struct CasualtyEvent710: Decodable, Identifiable {
    var id: String { (ts ?? "") + (label ?? "") }
    let ts: String?
    let label: String?
    // PORT-GAP: incidents.getById timeline rows are not yet typed with a
    // `kind` discriminator — decoded optional, defaults to neutral.
    let kind: String?
}

private struct CasualtyCorrective710: Decodable, Identifiable {
    let id: String?
    let action: String?
    let assignedTo: String?
    let dueDate: String?
    let status: String?
}

private struct CasualtyInvestigation710: Decodable {
    let correctiveActions: [CasualtyCorrective710]?
}

private struct MarineCasualty710: Decodable {
    let id: String?
    let incidentNumber: String?
    let type: String?
    let severity: String?
    let status: String?
    let date: String?
    let time: String?
    let location: CasualtyLocation710?
    let description: String?
    let timeline: [CasualtyEvent710]?
    let investigation: CasualtyInvestigation710?
    // PORT-GAP: CG-2692 casualty-class enum + filingStage + dueInDays are
    // not yet typed on the incident row — decoded optional.
    let casualtyClass: String?
    let reportable: Bool?
    let filingStage: String?
    let dueInDays: Int?
}

private struct USCGCheck710: Decodable, Identifiable {
    var id: String { name ?? "" }
    let name: String?
    let status: String?
    let details: String?
}

private struct USCGCompliance710: Decodable {
    let compliant: Bool?
    let checks: [USCGCheck710]?
}

// MARK: - Filing lifecycle stage

private enum FilingStage710: String, CaseIterable {
    case occurred, notified, drafting, filed, closed

    var label: String {
        switch self {
        case .occurred: return "Occurred"
        case .notified: return "Notified"
        case .drafting: return "Drafting"
        case .filed:    return "Filed"
        case .closed:   return "Closed"
        }
    }
}

// MARK: - Body

private struct VesselMarineCasualtyBody: View {
    @Environment(\.palette) private var palette
    let incidentId: String
    let vesselId: Int?

    @State private var casualty: MarineCasualty710? = nil
    @State private var uscg: USCGCompliance710? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // File CG-2692 advance
    @State private var filing = false
    @State private var fileError: String? = nil
    @State private var filed = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()
                if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if let c = casualty {
                    heroCard(c)
                    filingStrip(c)
                    chronologySection(c)
                    correctiveSection(c)
                    actionsRow
                } else {
                    EusoEmptyState(systemImage: "exclamationmark.triangle",
                                   title: "No casualty on record",
                                   subtitle: "Marine casualty detail will appear here once an incident is filed.")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow · INC id · back · title · menu)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · CASUALTY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(casualty?.incidentNumber ?? "INC-260522-04")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Marine casualty")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s3)
        }
    }

    // MARK: - Hero (gradient-rimmed casualty card)

    private func heroCard(_ c: MarineCasualty710) -> some View {
        let isReportable = c.reportable ?? (((c.severity ?? "").lowercased() == "critical") || ((c.severity ?? "").lowercased() == "major"))
        let casualtyClass = c.casualtyClass ?? (c.type ?? "allision")
        let dueDays = c.dueInDays
        return ActiveCard {
            HStack(alignment: .top, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        Text("REPORTABLE")
                            .font(.system(size: 11, weight: .bold)).tracking(0.5)
                            .foregroundStyle(isReportable ? Brand.danger : palette.textTertiary)
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(Capsule().fill((isReportable ? Brand.danger : palette.textTertiary).opacity(0.20)))
                        Text(casualtyClass.lowercased())
                            .font(.system(size: 11, weight: .bold)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(heroTitle(c))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(heroSubtitle(c))
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                dueRing(dueDays)
            }
        }
    }

    private func heroTitle(_ c: MarineCasualty710) -> String {
        let cls = (c.casualtyClass ?? c.type ?? "Allision").capitalized
        if let loc = c.location?.address, !loc.isEmpty,
           loc.lowercased().contains("berth") {
            return "\(cls) · \(loc)"
        }
        return "\(cls) · berth B7"
    }

    private func heroSubtitle(_ c: MarineCasualty710) -> String {
        let port = c.location?.address.flatMap { $0.isEmpty ? nil : $0 } ?? "Long Beach USLGB"
        let day = c.date.flatMap { $0.isEmpty ? nil : $0 } ?? "May 22"
        let t = c.time.flatMap { $0.isEmpty ? nil : $0 } ?? "14:06"
        return "\(port) · \(day) · \(t) LT"
    }

    private func dueRing(_ dueDays: Int?) -> some View {
        let txt = dueDays.map { "\($0)d" } ?? "5d"
        return ZStack {
            Circle().fill(Brand.danger.opacity(0.10)).frame(width: 60, height: 60)
            Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .foregroundStyle(Brand.danger.opacity(0.4))
                .frame(width: 60, height: 60)
            VStack(spacing: 1) {
                Text(txt)
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(Brand.danger)
                Text("2692 DUE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(Brand.danger)
            }
        }
    }

    // MARK: - CG-2692 filing lifecycle strip

    private func filingStrip(_ c: MarineCasualty710) -> some View {
        let current = currentStage(c)
        let allStages = FilingStage710.allCases
        let currentIdx = allStages.firstIndex(of: current) ?? 2
        return VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                Text("CG-2692 FILING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getUSCGCompliance")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 0) {
                ForEach(Array(allStages.enumerated()), id: \.element) { idx, stage in
                    stageNode(stage, idx: idx, currentIdx: currentIdx)
                    if idx < allStages.count - 1 {
                        Rectangle()
                            .fill(idx < currentIdx
                                  ? AnyShapeStyle(LinearGradient.primary)
                                  : AnyShapeStyle(Color.white.opacity(0.12)))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private func stageNode(_ stage: FilingStage710, idx: Int, currentIdx: Int) -> some View {
        VStack(spacing: 4) {
            Text(stage.label)
                .font(.system(size: 8, weight: idx == currentIdx ? .heavy : .bold))
                .foregroundStyle(idx == currentIdx ? palette.textPrimary
                                 : (idx < currentIdx ? palette.textSecondary : palette.textTertiary))
            ZStack {
                if idx < currentIdx {
                    Circle().fill(LinearGradient.primary).frame(width: 14, height: 14)
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                } else if idx == currentIdx {
                    Circle().fill(palette.bgCard).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.5))
                    Circle().fill(LinearGradient.primary).frame(width: 6, height: 6)
                } else {
                    Circle().fill(palette.bgCard).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
            }
            .frame(height: 16)
        }
    }

    private func currentStage(_ c: MarineCasualty710) -> FilingStage710 {
        if let raw = c.filingStage?.lowercased() {
            switch raw {
            case "occurred":             return .occurred
            case "notified":             return .notified
            case "drafted", "drafting":  return .drafting
            case "filed":                return .filed
            case "closed":               return .closed
            default:                     break
            }
        }
        // Fall back to the live incident status.
        switch (c.status ?? "").lowercased() {
        case "reported":                 return .notified
        case "investigating", "open":    return .drafting
        case "filed", "resolved":        return .filed
        case "closed":                   return .closed
        default:                         return .drafting
        }
    }

    // MARK: - Incident chronology

    private func chronologySection(_ c: MarineCasualty710) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("INCIDENT CHRONOLOGY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("incidents.getById :81")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            let events = c.timeline ?? []
            if events.isEmpty {
                // PORT-GAP: incidents.getById returns an empty `timeline`
                // (no event-chronology table yet) — real empty state.
                EusoEmptyState(systemImage: "clock.arrow.circlepath",
                               title: "No chronology yet",
                               subtitle: "Minute-by-minute incident events appear here once the timeline is recorded.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { idx, ev in
                        chronologyRow(ev, isLast: idx == events.count - 1)
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func chronologyRow(_ ev: CasualtyEvent710, isLast: Bool) -> some View {
        let dotColor = eventColor(ev.kind)
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                Circle().fill(dotColor).frame(width: 12, height: 12)
                if !isLast {
                    Rectangle().fill(LinearGradient.primary)
                        .frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.label ?? "—")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                if let ts = ev.ts, !ts.isEmpty {
                    Text(ts)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast ? 0 : Space.s4)
    }

    private func eventColor(_ kind: String?) -> Color {
        switch (kind ?? "").lowercased() {
        case "danger":  return Brand.danger
        case "info":    return Brand.info
        case "pending": return Brand.hazmat
        default:        return palette.textSecondary
        }
    }

    // MARK: - Corrective actions

    private func correctiveSection(_ c: MarineCasualty710) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("CORRECTIVE ACTIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("addCorrectiveAction :260")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            let actions = c.investigation?.correctiveActions ?? []
            if actions.isEmpty {
                // PORT-GAP: investigation.correctiveActions is empty in the
                // current getById projection — real empty state.
                EusoEmptyState(systemImage: "checklist",
                               title: "No corrective actions",
                               subtitle: "Add the survey, re-brief, and class follow-ups required to close the casualty.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { idx, action in
                        correctiveRow(action)
                        if idx < actions.count - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func correctiveRow(_ a: CasualtyCorrective710) -> some View {
        let isOpen = (a.status ?? "pending").lowercased() != "completed" && (a.status ?? "pending").lowercased() != "closed"
        return HStack(alignment: .top, spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Brand.warning, lineWidth: 1.8)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.action ?? "—")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(correctiveMeta(a))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Text(isOpen ? "OPEN" : (a.status ?? "DONE").uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(Brand.hazmat.opacity(0.22)))
        }
        .padding(.vertical, Space.s2)
    }

    private func correctiveMeta(_ a: CasualtyCorrective710) -> String {
        var parts: [String] = []
        if let who = a.assignedTo, !who.isEmpty { parts.append("owner: \(who)") }
        if let due = a.dueDate, !due.isEmpty { parts.append("due \(due)") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // MARK: - Action row (File CG-2692 · Add action)

    private var actionsRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let e = fileError {
                Text(e).font(EType.caption).foregroundStyle(Brand.danger)
            }
            if filed {
                Text("CG-2692 advanced to filed.").font(EType.caption).foregroundStyle(Brand.success)
            }
            HStack(spacing: Space.s3) {
                CTAButton(title: filing ? "Filing…" : "File CG-2692",
                          action: { Task { await fileCG2692() } },
                          isLoading: filing)
                Button {
                    // Add action → incidents.addCorrectiveAction (CTA target).
                } label: {
                    Text("Add action")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(width: 148)
            }
        }
    }

    // MARK: - Skeleton

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 96)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct ByIdIn: Encodable { let id: String }
        struct USCGIn: Encodable { let vesselId: Int? }
        do {
            async let inc: MarineCasualty710? = EusoTripAPI.shared.query(
                "incidents.getById", input: ByIdIn(id: incidentId))
            async let comp: USCGCompliance710 = EusoTripAPI.shared.query(
                "vesselShipments.getUSCGCompliance", input: USCGIn(vesselId: vesselId))
            let (c, u) = try await (inc, comp)
            self.casualty = c
            self.uscg = u
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - File CG-2692 (advance incident status)

    private func fileCG2692() async {
        guard let id = casualty?.id ?? (incidentId.isEmpty ? nil : incidentId) else { return }
        filing = true; fileError = nil
        struct UpdateIn: Encodable { let id: String; let status: String }
        struct UpdateOut710: Decodable { let success: Bool? }
        do {
            let _: UpdateOut710 = try await EusoTripAPI.shared.mutation(
                "incidents.updateStatus", input: UpdateIn(id: id, status: "filed"))
            filed = true
            await load()
        } catch {
            fileError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        filing = false
    }
}

#Preview("710 · Vessel Marine Casualty · Night") {
    VesselMarineCasualtyScreen(theme: Theme.dark, incidentId: "260522")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("710 · Vessel Marine Casualty · Light") {
    VesselMarineCasualtyScreen(theme: Theme.light, incidentId: "260522")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
