//
//  658_RailDisputeMediation.swift
//  EusoTrip — Rail · Rail Engineer · Dispute Mediation (brick 658).
//
//  Verbatim SwiftUI port of "05 Rail/658 Rail Dispute Mediation · Dark" at the
//  golden design-authority bar. CARRIER (Rail Engineer) vantage on the mediation
//  SCHEDULER for a live billing dispute: an assigned-panel card, a 3-cell KPI
//  strip, a dated session list, a proposals-on-the-table band, and a Propose-
//  session / Reschedule CTA pair — so the claimant never misses the 24h
//  counter-position deadline.
//
//  Nav: REAL Rail Engineer enum HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//  transportMode = rail · AAR arbitration panel · non-binding until accept.
//
//  WIRING (web parity /rail/disputes/mediation):
//    dispute  → freightClaims.getDisputeResolution EXISTS · freightClaims.ts:1763
//               ({limit:1}) → first live dispute id.
//    mediation→ freightClaims.getDisputeMediation  EXISTS · freightClaims.ts:2246
//               ({disputeId}) → { mediationStatus, mediator(null STUB), sessions[],
//               proposedResolutions[], timeline[] } (sessions/proposals reconstructed
//               from dispute_events; mediator identity is a hard STUB → null).
//    Propose / Reschedule → freightClaims.scheduleMediationSession EXISTS · :2372
//               ({disputeId,scheduledAt,notes}) → writes a MEDIATION_SESSION event.
//  NEXT/window are HONEST derivations from real session dates. RBAC protectedProcedure
//  (party-gated). Panel identity defaults to the institutional neutral (AAR
//  arbitration) and flags "pending" when the mediator STUB is null.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shapes (mirror freightClaims.getDisputeMediation)

private struct MedMediator658: Decodable { let id: String?; let name: String?; let firm: String? }
private struct MedSession658: Decodable, Identifiable {
    let id: String
    let date: String?
    let notes: String?
    let outcome: String?         // resolved | scheduled
}
private struct MedProposal658: Decodable, Identifiable {
    let id: String
    let proposedBy: String?
    let amount: Double?
    let terms: String?
    let status: String?
}
private struct MedTimeline658: Decodable { let date: String?; let event: String?; let details: String? }
private struct Mediation658: Decodable {
    let mediationStatus: String?
    let mediator: MedMediator658?
    let sessions: [MedSession658]?
    let proposedResolutions: [MedProposal658]?
    let timeline: [MedTimeline658]?
}
private struct MedDisputeRow658: Decodable { let id: String; let disputeNumber: String?; let type: String?; let amount: Double? }
private struct MedDisputeList658: Decodable { let disputes: [MedDisputeRow658]? }

// MARK: - Screen wrapper

struct RailDisputeMediationScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailDisputeMediationBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",  isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailDisputeMediationBody: View {
    @Environment(\.palette) private var palette

    @State private var disputeId: String = ""
    @State private var dispute: MedDisputeRow658? = nil
    @State private var mediation: Mediation658? = nil
    @State private var hasDispute = true
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var scheduling = false
    @State private var actionBanner: String? = nil
    @State private var actionIsError = false

    private func money(_ v: Double) -> String {
        if v >= 1000 { return "$" + String(format: "%.1fK", v / 1000) }
        return "$" + String(Int(v))
    }

    private var sessions: [MedSession658] { mediation?.sessions ?? [] }
    private var proposals: [MedProposal658] { mediation?.proposedResolutions ?? [] }

    private var panelName: String { mediation?.mediator?.name ?? "AAR Arbitration Panel" }
    private var panelFirm: String { mediation?.mediator?.firm ?? (mediation?.mediator == nil ? "rail panel · neutral · assignment pending" : "rail panel · neutral") }
    private var panelInitials: String {
        let words = panelName.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(words).uppercased()
    }
    private var statusPill: String { (mediation?.mediationStatus ?? "not started").replacingOccurrences(of: "_", with: " ").uppercased() }

    /// Days until the next scheduled session (honest, from real dates).
    private var nextSessionDays: Int? {
        let upcoming = sessions.compactMap { s -> Date? in
            guard (s.outcome ?? "").lowercased() != "resolved", let d = parseDate(s.date) else { return nil }
            return d >= Calendar.current.startOfDay(for: Date()) ? d : nil
        }.min()
        return upcoming.map { max(0, Int(($0.timeIntervalSince(Date())) / 86400)) }
    }
    private var acceptWindowDays: Int? {
        // Window = days to the last (decision) session.
        sessions.compactMap { parseDate($0.date) }.max().map { max(0, Int($0.timeIntervalSince(Date()) / 86400)) }
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return ISO8601DateFormatter().date(from: s) ?? {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: String(s.prefix(10)))
        }()
    }
    private func shortDate(_ s: String?) -> String {
        guard let d = parseDate(s) else { return s ?? "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                titleRow
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    skeleton.padding(.top, Space.s4)
                } else if let err = loadError {
                    errorCard(err).padding(.top, Space.s4)
                } else if !hasDispute {
                    EusoEmptyState(systemImage: "person.2.badge.gearshape",
                                   title: "No dispute in mediation",
                                   subtitle: "A billing dispute must be escalated before a panel is assigned.")
                        .padding(.top, Space.s5)
                } else {
                    panelCard.padding(.top, Space.s4)
                    kpiStrip.padding(.top, Space.s4)
                    sessionsList.padding(.top, Space.s5)
                    proposalsCard.padding(.top, Space.s4)
                    if let banner = actionBanner { actionBannerView(banner).padding(.top, Space.s3) }
                    ctaPair.padding(.top, Space.s4)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Top bar / title

    private var topBar: some View {
        HStack {
            Text("✦ RAIL ENGINEER · DISPUTE MEDIATION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("MED · SESSIONS").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
            Text("Mediation").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(palette.textPrimary)
        }
        .padding(.top, Space.s3)
    }

    // MARK: Panel card (gradient rim)

    private var panelCard: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                Text(panelInitials).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(panelName).font(.system(size: 16, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(panelFirm).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                Text(statusPill).font(.system(size: 10, weight: .heavy)).tracking(0.5).foregroundStyle(Brand.success)
                    .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(Brand.success.opacity(0.16)))
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text("NEXT").font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text(nextSessionDays.map { "\($0)d" } ?? "—").font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(nextSessionLabel).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }
    private var nextSessionLabel: String {
        let scheduled = sessions.filter { (($0.outcome ?? "").lowercased()) != "resolved" }.count
        return "session \(sessions.count - scheduled + 1)"
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiCell("SESSIONS", "\(sessions.count)", "scheduled", highlight: true)
            kpiCell("PROPOSALS", "\(proposals.count)", "on table", highlight: false)
            kpiCell("WINDOW", acceptWindowDays.map { "\($0)d" } ?? "—", "to accept", highlight: false)
        }
    }
    private func kpiCell(_ label: String, _ value: String, _ sub: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(highlight ? .white.opacity(0.85) : palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(highlight ? .white : palette.textPrimary)
            Text(sub).font(.system(size: 10)).foregroundStyle(highlight ? .white.opacity(0.8) : palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(highlight ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Sessions list

    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SESSIONS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if sessions.isEmpty {
                EusoEmptyState(systemImage: "calendar.badge.plus", title: "No sessions scheduled",
                               subtitle: "Propose the first mediation session below.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.prefix(5).enumerated()), id: \.element.id) { idx, s in
                        sessionRow(s, index: idx)
                        if idx < min(sessions.count, 5) - 1 { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                    }
                    HStack {
                        Text("Counter-positions due 24h prior · binding on accept")
                            .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        Spacer()
                    }.padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func sessionRow(_ s: MedSession658, index: Int) -> some View {
        let st = outcomeKind(s.outcome, isLast: index == sessions.count - 1)
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(st.color.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: st.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(st.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Session \(index + 1) · \(sessionTitle(s))").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("\(shortDate(s.date)) · \(s.notes ?? "session")").font(EType.mono(.caption)).tracking(0.2).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Text(st.label).font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(st.color)
                .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(st.color.opacity(0.16)))
        }
        .padding(Space.s4)
    }

    private func sessionTitle(_ s: MedSession658) -> String {
        if let o = s.outcome, o.lowercased() == "resolved" { return "decision" }
        return "session"
    }
    private func outcomeKind(_ outcome: String?, isLast: Bool) -> (label: String, color: Color, icon: String) {
        switch (outcome ?? "").lowercased() {
        case "resolved": return ("RESOLVED", Brand.success, "checkmark.circle")
        case "scheduled": return isLast ? ("UPCOMING", Brand.hazmat, "calendar") : ("SCHEDULED", Brand.info, "calendar")
        default: return ("HELD", Brand.info, "checkmark.circle")
        }
    }

    // MARK: Proposals card

    private var proposalsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROPOSALS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if proposals.isEmpty {
                Text("No proposals on the table yet · non-binding until accepted")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(proposals.prefix(3)) { p in
                    HStack {
                        Text(proposalParty(p.proposedBy)).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text(money(p.amount ?? 0)).font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    }
                }
                Text("Panel band non-binding until a party accepts")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private func proposalParty(_ by: String?) -> String {
        switch (by ?? "").lowercased() {
        case "filer": return "Claimant proposal"
        case "counterparty": return "Carrier proposal"
        default: return (by ?? "party").capitalized + " proposal"
        }
    }

    // MARK: Action banner + CTA

    private func actionBannerView(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: actionIsError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(actionIsError ? Brand.danger : Brand.success)
            Text(text).font(EType.caption).foregroundStyle(actionIsError ? Brand.danger : palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background((actionIsError ? Brand.danger : Brand.success).opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder((actionIsError ? Brand.danger : Brand.success).opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: scheduling ? "Proposing…" : "Propose session",
                      action: { Task { await schedule(daysOut: 7) } }, isLoading: scheduling)
            Button(action: { Task { await schedule(daysOut: 14) } }) {
                Text("Reschedule").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(width: 138, height: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int; let offset: Int }
        struct MedIn: Encodable { let disputeId: String }
        do {
            let list: MedDisputeList658 = try await EusoTripAPI.shared.query(
                "freightClaims.getDisputeResolution", input: ListIn(limit: 1, offset: 0))
            guard let d = list.disputes?.first else {
                hasDispute = false; loading = false; return
            }
            hasDispute = true
            self.dispute = d
            self.disputeId = d.id
            let m: Mediation658 = try await EusoTripAPI.shared.query(
                "freightClaims.getDisputeMediation", input: MedIn(disputeId: d.id))
            self.mediation = m
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func schedule(daysOut: Int) async {
        guard !scheduling, hasDispute, !disputeId.isEmpty else {
            actionIsError = true; actionBanner = "No dispute in mediation to schedule."; return
        }
        scheduling = true; actionBanner = nil
        struct ScheduleIn: Encodable { let disputeId: String; let scheduledAt: String; let notes: String }
        struct ScheduleOut: Decodable { let success: Bool?; let scheduledAt: String? }
        let at = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: daysOut, to: Date()) ?? Date())
        do {
            let out: ScheduleOut = try await EusoTripAPI.shared.mutation("freightClaims.scheduleMediationSession",
                input: ScheduleIn(disputeId: disputeId, scheduledAt: at,
                                  notes: "Mediation session requested from the rail dispute-mediation board."))
            actionIsError = false
            actionBanner = "Session scheduled · \(shortDate(out.scheduledAt ?? at))"
            await load()
        } catch {
            actionIsError = true
            actionBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        scheduling = false
    }

    // MARK: Scaffolds

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 116)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 72)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
        }
    }
    private func errorCard(_ err: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Previews

#Preview("658 · Rail Dispute Mediation · Night") {
    RailDisputeMediationScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("658 · Rail Dispute Mediation · Light") {
    RailDisputeMediationScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
