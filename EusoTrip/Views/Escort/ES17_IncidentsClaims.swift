//
//  ES17_IncidentsClaims.swift
//  EusoTrip — Escort · ES-17 Incidents & Claims (the severity-spined ledger).
//
//  Built from the ES-17 design-authority twins
//  ("07 Escort/{Light,Dark}-SVG/ES-17 Incidents Claims.svg").
//  ARCHETYPE COMPLIANCE ledger — a SEVERITY SPINE: one vertical rail whose nodes are
//  the incidents.severity bands (CRITICAL · MAJOR · MODERATE · MINOR), each carrying
//  its own time-ordered rows, with the open strike row blown open into an in-row
//  claims-packet flow. No grid, no pass/fail, no gate — deliberately unlike ES-06.
//
//  WIRING (traced first-hand against server/routers/escorts.ts this firing):
//    REAL  escorts.getIncidents             :2691  ledger rows (severity/status/location)
//    REAL  escorts.getIncidentStats         :2719  {total, open, resolved, critical}
//    REAL  escorts.getClearanceEventHistory :4559  escort-scoped clearance events
//    REAL  escorts.getReports               :2738  claims-packet documents
//    STUB  incident capture / packet writes         GAP-085 — no escort-callable
//          incident-write procedure exists anywhere in escorts.ts. The capture
//          affordance renders LOCKED with its reason on glass and calls nothing.
//          It is never drawn as a live CTA and never reports a fake success.
//
//  CHAIN
//    C1 ONE-SIDED — the clearance-strike escalation inserts the incident with
//       driverId: null (escorts.ts:4461) while getIncidents filters on
//       eq(incidents.driverId, userId) (escorts.ts:2697). A strike-born incident can
//       therefore never surface through getIncidents. Until the insert stamps
//       driverId (or getIncidents unions clearanceEvents.incidentId), this screen
//       unions the two reads itself and stamps ES-02 provenance on every strike row
//       so the escort is never shown a ledger that quietly omits the worst event.
//    C2 SILENT — nothing here advances an incident: no status transition, no packet
//       write, no counterparty notification.
//
//  OFFLINE (§W) — reads READ_CACHED(30m) via EscortOfflineCache with the staleness
//  line rendered whenever a snapshot is painted instead of a live read. No write path
//  exists to queue; when GAP-085 capture lands it is ONLINE_ONLY (escort outbox not
//  yet ported — PLANNED per Encyclopedia v2). Never a fake queue badge.
//
//  RBAC — escort-gated reads, caller's own rows only. Pricing firewall holds: no
//  shipper identity, no loads.rate, no carrier margin on this surface.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire contracts (mirror server/routers/escorts.ts)

/// `escorts.getIncidents` row (escorts.ts:2691).
private struct ES17Incident: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let severity: String
    let occurredAt: String
    let location: String
    let description: String
    let injuries: Int
    let fatalities: Int
    let status: String
    let createdAt: String
}
private struct ES17IncidentsInput: Encodable {
    var status: String? = nil
    var search: String? = nil
    var severity: String? = nil
}

/// `escorts.getIncidentStats` (escorts.ts:2719).
private struct ES17Stats: Codable, Hashable {
    let total: Int
    let open: Int
    let resolved: Int
    let critical: Int
}

/// `escorts.getClearanceEventHistory` row (escorts.ts:4559). Decoded loosely: the proc
/// returns the raw clearance_events row, so only the fields this screen paints are
/// modelled and every one of them is optional except the id.
private struct ES17ClearanceEvent: Codable, Identifiable, Hashable {
    let id: Int
    let eventType: String?
    let structureName: String?
    let postedClearanceFt: String?
    let poleHeightSetFt: String?
    let damageObserved: Bool?
    let haulStopped: Bool?
    let photos: [String]?
    let notes: String?
    let escalation: String?
    let incidentId: Int?
    let occurredAt: String?
}
private struct ES17ClearanceInput: Encodable { let limit: Int }

/// `escorts.getReports` row (escorts.ts:2738) — the packet's document slots.
private struct ES17Report: Codable, Identifiable, Hashable {
    let id: String
    let type: String?
    let name: String?
    let status: String?
    let createdAt: String?
}
private struct ES17ReportsInput: Encodable {
    var type: String? = nil
    var search: String? = nil
    var status: String? = nil
}

/// The disk snapshot this screen caches (READ_CACHED 30m).
private struct ES17Snapshot: Codable {
    var stats: ES17Stats
    var incidents: [ES17Incident]
    var clearanceEvents: [ES17ClearanceEvent]
    var reportCount: Int
}

/// A ledger row after the two reads are unioned. `fromClearanceEvent` earns the ES-02
/// provenance chip; it is the visible half of CHAIN C1.
private struct ES17LedgerRow: Identifiable, Hashable {
    let id: String
    let title: String
    let locationLine: String
    let severity: String
    let status: String
    var fromClearanceEvent = false
    var poleFt: String? = nil
    var postedFt: String? = nil
    var marginFt: String? = nil
    var damageObserved = false
    var haulStopped = false
    var photoCount = 0
    var packetStepsOnFile = 0
}

private enum ES17Band: String, CaseIterable, Identifiable {
    case critical, major, moderate, minor
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }

    /// Severity colour for this band.
    ///
    /// The screen called a free function `bandTint(_:)` that does not exist in
    /// this file — the only `bandTint` in the tree is a PRIVATE method on the
    /// Catalyst permit-renewals view and takes a CredentialGate, so it was
    /// never reachable from here. Defined on the band itself so the mapping
    /// lives with the thing it describes, using the same Brand severity ramp
    /// the rest of the app uses.
    var tint: Color {
        switch self {
        case .critical: return Brand.danger
        case .major:    return Brand.warning
        case .moderate: return Brand.info
        case .minor:    return Brand.success
        }
    }
}

// MARK: - Screen

struct EscortIncidentsClaims: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    private enum Phase { case loading, loaded, failed }

    @State private var phase: Phase = .loading
    @State private var stats: ES17Stats? = nil
    @State private var incidents: [ES17Incident] = []
    @State private var clearanceEvents: [ES17ClearanceEvent] = []
    @State private var reportCount: Int = 0
    @State private var stalenessLine: String? = nil
    @State private var errorMessage: String? = nil
    @State private var expandedRowId: String? = nil

    private static let cacheKey = "es17-incidents-claims"
    private static let cacheTTL: TimeInterval = 30 * 60   // READ_CACHED(30m)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrowRow
                titleBlock
                statBand
                if phase == .loading && stats == nil {
                    LifecycleCard {
                        Text("Loading the ledger…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else {
                    severitySpine
                    captureStub
                    esangRow
                    actionRow
                    footNote
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            Text("✦ ESCORT · INCIDENTS & CLAIMS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text("EASTBOUND ESCORT LLC")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Incidents & Claims")
                .font(.system(size: 24, weight: .bold)).tracking(-0.4)
                .foregroundStyle(LinearGradient.primary)
            HStack(spacing: 12) {
                if let s = stats {
                    Text("\(s.open) OPEN")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Brand.danger.opacity(0.14)))
                }
                Text("Ledger · role scope")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                // Honesty law: the freshness slot says "cached · N min ago" whenever a
                // snapshot is on glass. It never claims live.
                if let stale = stalenessLine {
                    Label(stale, systemImage: "clock.arrow.circlepath")
                        .font(EType.mono(.micro)).foregroundStyle(Brand.warning)
                } else if phase == .loaded {
                    HStack(spacing: 5) {
                        Circle().fill(Brand.success).frame(width: 7, height: 7)
                        Text("LIVE").font(EType.mono(.micro)).foregroundStyle(palette.textPrimary)
                    }
                }
            }
            if let err = errorMessage {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }

    // MARK: DataStat band (getIncidentStats)

    private var statBand: some View {
        let s = stats ?? ES17Stats(total: 0, open: 0, resolved: 0, critical: 0)
        return HStack(spacing: 0) {
            statCell("\(s.total)", "ON FILE · YTD", gradient: true)
            statDivider
            statCell("\(s.open)", "OPEN", tint: Brand.warning)
            statDivider
            statCell("\(s.resolved)", "RESOLVED", tint: Brand.success)
            statDivider
            statCell("\(s.critical)", "CRITICAL", tint: palette.textPrimary)
        }
    }

    private func statCell(_ value: String, _ label: String,
                          tint: Color? = nil, gradient: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if gradient { Text(value).foregroundStyle(LinearGradient.primary) }
                else { Text(value).foregroundStyle(tint ?? palette.textPrimary) }
            }
            .font(.system(size: 16, weight: .heavy, design: .monospaced))
            Text(label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 26)
    }

    // MARK: Severity spine — the layout

    private var severitySpine: some View {
        LifecycleCard {
            HStack {
                sectionEyebrow("SEVERITY SPINE · BANDS → ROWS")
                Spacer(minLength: 0)
                Text("YTD \(Calendar.current.component(.year, from: Date()).description)")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(ES17Band.allCases) { band in
                    bandSection(band)
                }
            }
        }
    }

    @ViewBuilder
    private func bandSection(_ band: ES17Band) -> some View {
        let rows = rows(in: band)
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if rows.isEmpty {
                        Circle().fill(palette.bgCard)
                            .overlay(Circle().strokeBorder(palette.textTertiary, lineWidth: 1.5))
                    } else {
                        Circle().fill(band.tint)
                    }
                }
                .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 3) {
                    Text(band.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(rows.isEmpty ? palette.textTertiary : band.tint)
                    if rows.isEmpty {
                        // An empty band says so instead of vanishing.
                        Text("0 ON FILE · BAND CLEAR")
                            .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                Text(rows.isEmpty ? "CLEAR" : "\(rows.count) ROW\(rows.count == 1 ? "" : "S")")
                    .font(EType.mono(.micro))
                    .foregroundStyle(rows.isEmpty ? Brand.success : palette.textTertiary)
            }

            ForEach(rows) { row in
                if expandedRowId == row.id {
                    expandedRow(row)
                } else {
                    compactRow(row)
                }
            }
        }
    }

    private func expandedRow(_ row: ES17LedgerRow) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                Text(row.title)
                    .font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 6)
                statusPill(row.status)
            }
            Text(row.locationLine)
                .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)

            HStack {
                if row.fromClearanceEvent {
                    // The real clearanceEvents.incidentId back-link (escorts.ts:4478),
                    // and the visible half of CHAIN C1.
                    Text("ES-02 · CLEARANCE EVENT")
                        .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(LinearGradient.primary)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(Brand.blue.opacity(0.10)))
                }
                Spacer(minLength: 6)
                if row.haulStopped {
                    Text("HAUL STOPPED").font(EType.mono(.micro)).foregroundStyle(Brand.danger)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                figureCell("POLE", row.poleFt ?? "—", tint: palette.textPrimary)
                figureCell("POSTED", row.postedFt ?? "—", tint: palette.textPrimary)
                figureCell("MARGIN", row.marginFt ?? "—", tint: Brand.danger)
                figureCell("DAMAGE", row.damageObserved ? "OBSERVED" : "NONE",
                           tint: row.damageObserved ? Brand.danger : palette.textPrimary)
            }

            Divider().overlay(palette.borderFaint)

            Text("CLAIMS PACKET · \(row.packetStepsOnFile) OF 4 ON FILE")
                .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)

            HStack(spacing: 6) {
                packetStep(row.photoCount > 0 ? "\(row.photoCount) PHOTO" : "PHOTO",
                           onFile: row.packetStepsOnFile > 0)
                packetStep("NARRATIVE", onFile: row.packetStepsOnFile > 1)
                packetStep("CARRIER —", onFile: false)
                packetStep("INSURER —", onFile: false)
            }

            Text("STEPS 3–4 HAVE NO WRITE PROCEDURE ON FILE · GAP-085")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35), lineWidth: 1.5))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal).frame(width: 3)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.16)) { expandedRowId = nil } }
    }

    private func compactRow(_ row: ES17LedgerRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(row.locationLine)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            statusPill(row.status)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.16)) { expandedRowId = row.id } }
    }

    private func statusPill(_ status: String) -> some View {
        let tint: Color = {
            switch status.lowercased() {
            case "resolved":      return Brand.success
            case "investigating": return Brand.info
            default:              return Brand.warning
            }
        }()
        return Text(status.uppercased())
            .font(.system(size: 7.5, weight: .heavy)).tracking(0.4).foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
    }

    private func figureCell(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(EType.mono(.caption)).fontWeight(.bold).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func packetStep(_ label: String, onFile: Bool) -> some View {
        Text(label)
            .font(.system(size: 7.5, weight: .heavy)).tracking(0.3)
            .foregroundStyle(onFile ? Brand.success : palette.textTertiary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(onFile ? Brand.success.opacity(0.16) : palette.bgCardSoft))
    }

    // MARK: Capture — honestly locked (GAP-085). Deliberately NOT a Button.

    private var captureStub: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: "lock")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text("REPORT AN INCIDENT")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                Text("NO ESCORT INCIDENT-WRITE PROCEDURE EXISTS · FILE VIA DISPATCH")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text("STUB")
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().strokeBorder(palette.textTertiary.opacity(0.45)))
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.textTertiary.opacity(0.45),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .accessibilityLabel("Report an incident. Unavailable — no incident write procedure exists yet. File through dispatch.")
    }

    // MARK: ESANG

    private var esangRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack(alignment: .topLeading) {
                Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
                Circle().fill(Color.white.opacity(0.45)).frame(width: 7, height: 7).offset(x: 2, y: 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text("ESANG").font(.system(size: 10, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.primary)
                    Text("· \(openStrikeSummary)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Text("Packet steps with no write path stay unfilled until GAP-085 lands.")
                    .font(.system(size: 8.5, weight: .medium)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal).frame(width: 3)
        }
    }

    private var openStrikeSummary: String {
        let strikes = clearanceEvents.filter { ($0.eventType ?? "") == "strike" || ($0.damageObserved ?? false) }
        if strikes.isEmpty { return "no open strike on the clearance spine" }
        return "\(strikes.count) strike row\(strikes.count == 1 ? "" : "s") carried from ES-02"
    }

    // MARK: Actions — navigation + phone. Both honest; neither invents a write.

    private var actionRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                NotificationCenter.default.post(name: .eusoEscortNavSwap, object: nil,
                                                userInfo: ["screenId": "602"])
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold))
                    Text("OPEN CLEARANCE EVENT")
                        .font(.system(size: 12.5, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                // Honest fallback while capture is a named gap: reach a human.
                if let url = URL(string: "tel://") { openURL(url) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone").font(.system(size: 12, weight: .bold))
                    Text("CALL DISPATCH").font(.system(size: 12, weight: .heavy)).tracking(0.3)
                }
                .foregroundStyle(palette.textPrimary)
                .frame(width: 150).frame(height: 44)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
        }
    }

    private var footNote: some View {
        Text("READ-ONLY LEDGER · NO STATUS TRANSITION EXISTS FROM THIS SURFACE")
            .font(EType.mono(.micro)).tracking(0.3)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: - Ledger fold (the union that CHAIN C1 forces)

    /// Strike rows arrive on the clearance feed, not on getIncidents — see C1.
    private var strikeRows: [ES17LedgerRow] {
        clearanceEvents
            .filter { ($0.eventType ?? "") == "strike" || ($0.damageObserved ?? false) }
            .map { ev in
                let pole = ev.poleHeightSetFt.map { "\($0) ft" }
                let posted = ev.postedClearanceFt.map { "\($0) ft" }
                let margin: String? = {
                    guard let p = Double(ev.poleHeightSetFt ?? ""), let q = Double(ev.postedClearanceFt ?? "")
                    else { return nil }
                    return String(format: "%+.2f ft", q - p)
                }()
                let photos = ev.photos?.count ?? 0
                return ES17LedgerRow(
                    id: "clr-\(ev.id)",
                    title: "Clearance strike · \(ev.structureName ?? "structure not named")",
                    locationLine: [ev.structureName, relativeStamp(ev.occurredAt)]
                        .compactMap { $0 }.joined(separator: " · ").uppercased(),
                    // The escalation writes major on observed damage, else moderate
                    // (escorts.ts:4463) — mirrored, not invented.
                    severity: (ev.damageObserved ?? false) ? "major" : "moderate",
                    status: ev.incidentId != nil ? "reported" : "logged",
                    fromClearanceEvent: true,
                    poleFt: pole, postedFt: posted, marginFt: margin,
                    damageObserved: ev.damageObserved ?? false,
                    haulStopped: ev.haulStopped ?? false,
                    photoCount: photos,
                    // Steps 1–2 only: photos on the event + a narrative when notes exist.
                    packetStepsOnFile: (photos > 0 ? 1 : 0) + ((ev.notes?.isEmpty == false) ? 1 : 0)
                )
            }
    }

    private var incidentRows: [ES17LedgerRow] {
        incidents.map { i in
            ES17LedgerRow(
                id: "inc-\(i.id)",
                title: i.description.isEmpty ? i.type.replacingOccurrences(of: "_", with: " ").capitalized
                                             : i.description,
                locationLine: [i.location.isEmpty ? nil : i.location, relativeStamp(i.occurredAt)]
                    .compactMap { $0 }.joined(separator: " · ").uppercased(),
                severity: i.severity,
                status: i.status
            )
        }
    }

    private func rows(in band: ES17Band) -> [ES17LedgerRow] {
        (incidentRows + strikeRows).filter { $0.severity.lowercased() == band.rawValue }
    }

    private func relativeStamp(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return nil }
        let mins = Int(Date().timeIntervalSince(date) / 60)
        if mins < 60 { return "\(max(mins, 0)) min ago" }
        if mins < 1440 { return "\(mins / 60) h ago" }
        return "\(mins / 1440) d ago"
    }

    // MARK: - Data

    private func load(force: Bool = false) async {
        // READ_CACHED(30m): paint the last-good snapshot first so the ledger is
        // legible with no signal, then overwrite with the live reads. Whenever the
        // snapshot is what is on glass, the staleness line says so.
        if !force,
           let cached = EscortOfflineCache.load(ES17Snapshot.self,
                                                key: Self.cacheKey, ttl: Self.cacheTTL) {
            stats = cached.value.stats
            incidents = cached.value.incidents
            clearanceEvents = cached.value.clearanceEvents
            reportCount = cached.value.reportCount
            stalenessLine = EscortOfflineCache.stalenessLine(age: cached.age)
            phase = .loaded
        }

        async let statsCall: ES17Stats? = try? await EusoTripAPI.shared.query(
            "escorts.getIncidentStats", input: ES17IncidentsInput())
        async let rowsCall: [ES17Incident]? = try? await EusoTripAPI.shared.query(
            "escorts.getIncidents", input: ES17IncidentsInput())
        async let clearanceCall: [ES17ClearanceEvent]? = try? await EusoTripAPI.shared.query(
            "escorts.getClearanceEventHistory", input: ES17ClearanceInput(limit: 50))
        async let reportsCall: [ES17Report]? = try? await EusoTripAPI.shared.query(
            "escorts.getReports", input: ES17ReportsInput())

        let (s, r, c, docs) = await (statsCall, rowsCall, clearanceCall, reportsCall)

        guard let s else {
            if stats == nil {
                phase = .failed
                errorMessage = "Couldn't reach the incident ledger. Pull to retry."
            }
            return
        }

        stats = s
        incidents = r ?? []
        clearanceEvents = c ?? []
        reportCount = docs?.count ?? 0
        stalenessLine = nil            // live read is on glass now
        errorMessage = nil
        phase = .loaded
        if expandedRowId == nil { expandedRowId = strikeRows.first?.id }

        EscortOfflineCache.store(
            ES17Snapshot(stats: s, incidents: incidents,
                         clearanceEvents: clearanceEvents, reportCount: reportCount),
            key: Self.cacheKey)
    }
}

// MARK: - Registered surface wrapper

struct EscortIncidentsClaimsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortIncidentsClaims()
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home",        systemImage: "house",                  isCurrent: false),
                    NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled", isCurrent: false),
                ],
                trailing: [
                    NavSlot(label: "Corridor", systemImage: "map",    isCurrent: false),
                    NavSlot(label: "Me",       systemImage: "person", isCurrent: true),
                ],
                orbState: .idle
            )
        }
    }
}

#Preview("ES-17 · Incidents & Claims · Dark") {
    EscortIncidentsClaimsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("ES-17 · Incidents & Claims · Light") {
    EscortIncidentsClaimsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
