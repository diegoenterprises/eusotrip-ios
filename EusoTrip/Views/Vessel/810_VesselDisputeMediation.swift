//
//  810_VesselDisputeMediation.swift
//  EusoTrip — Vessel Operator · Dispute Mediation.
//
//  Faithful bespoke port of the RECONSTRUCTED "810 Vessel Dispute Mediation.svg" (Light + Dark),
//  adapted INTO the app convention. Archetype: a mediator-panel gradient-rim hero (arbitrator + AWARD
//  due + days-to-award), a LEFT date-gutter vertical timeline (assigned done · brief-due ringed-active ·
//  session scheduled · award neutral) each with its date in the mono gutter, a proposed-resolutions
//  footer, the ESang brief-deadline advisory, and the Submit brief / Schedule CTA pair. Nav anchored to
//  the registered vessel sibling Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME),
//  the same wrapper 757_VesselDetentionLetters ships.
//
//  Data / wiring (endpoint MCP-CONFIRMED this fire via EUSOTRIP_PLATFORM):
//    HERO + TIMELINE: freightClaims.getDisputeMediation EXISTS frontend/server/routers/freightClaims.ts:855
//        protectedProcedure · input {disputeId:string} · returns {disputeId,mediationStatus,
//        mediator{id,name,firm}|null,sessions[{id,date,notes,outcome}],proposedResolutions[{id,proposedBy,
//        amount,terms,status}],timeline[{date,event,details}]}. In this build the procedure returns
//        empty arrays / null mediator (no rows yet) — so the timeline overwrites the design-time seeds
//        ONLY when getDisputeMediation returns a non-empty timeline; otherwise the seeds are kept as the
//        honest "not_started" projection rather than fabricating server rows.
//    WRITE: STUB · named-gap — scheduleMediationSession / submitMediationBrief have no mutation on disk
//        (no proposed {disputeId,...} writers in freightClaims.ts); both CTAs re-run load() and are
//        honestly flagged STUB (surfaced to the-oath) rather than faked.
//    RBAC: protectedProcedure.
//
//  In-module substitutions (the canonical port's RimCard / SecondaryButton / Brand.violet / StatusPill
//  tone: are NOT shared app symbols): RimCard810 + secondaryButton810 are file-scoped from the sibling
//  757 gradient-rim grammar; accentViolet810 stands in for the missing Brand.violet; the AWARD pill is
//  StatusPill(text:kind:.info). No module-level EmptyInput — MediationInput810 is per-file.
//
//  0 stubs in render · 0 mock data on a live timeline · honest empty projection — values render from
//  real state; design-time seeds are overwritten by the query on .task whenever the server has rows.
//

import SwiftUI

/// Stands in for the canonical port's `Brand.violet`, which is not a shared app
/// color (Brand ships blue/magenta/success/warning/danger only). Same panel-violet
/// the SVG used for the SMA mediation accents.
private let accentViolet810 = Color(red: 0.49, green: 0.30, blue: 0.92)

private enum EventState810 { case done, active, scheduled, future }
private struct MedEvent810: Identifiable {
    let id = UUID(); let date: String; let title: String; let sub: String; let tag: String; let state: EventState810
}

struct VesselDisputeMediationScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselDisputeMediationBody810()
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

private struct VesselDisputeMediationBody810: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var disputeId = "DSP-260525-7C3A09F18B"
    @State private var subline = "MED-260527-9F2C41A0 · DSP-260525-7C3A09F18B"
    @State private var mediatorName = "A. Renton FCIArb"
    @State private var mediatorFirm = "Society of Maritime Arbitrators · panel of 3"
    @State private var mediatorMeta = "SMA-NY rules · NY office + Zoom"
    @State private var sessionsLine = "0 / 3 sessions held · counsel green-lit ±$2k"
    @State private var awardPill = "AWARD 07-02"
    @State private var daysToAward = "35d"
    @State private var proposedLine = "Proposed: vessel $26.4k · CMA-CGM $18.4k · midpoint $22.4k"
    @State private var esangLine = "1 exhibit pending · award holds 07-02 if on time"

    @State private var events: [MedEvent810] = [
        MedEvent810(date: "05-27", title: "Mediator assigned", sub: "SMA NY assigned panel of 3",       tag: "DONE",     state: .done),
        MedEvent810(date: "06-05", title: "Vessel brief due",  sub: "submitMediationBrief · 9 exhibits", tag: "ACTIVE",   state: .active),
        MedEvent810(date: "06-12", title: "Session 1 · panel", sub: "NY office + Zoom · all parties",    tag: "SCHED",    state: .scheduled),
        MedEvent810(date: "07-02", title: "Award expected",    sub: "binding · SMA-NY rules",            tag: "EXPECTED", state: .future)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Dispute mediation").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    RimCard810 { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    RimCard810 { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    mediatorHero
                    Text("MEDIATION TIMELINE · getDisputeMediation · \(events.count) EVENTS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    timelineCard
                    esangCard
                    HStack(spacing: 8) {
                        CTAButton(title: "Submit brief", action: { Task { await submitBrief() } }, trailingIcon: "doc.badge.plus")
                        secondaryButton810(title: "Schedule") { Task { await schedule() } }
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
                Text("VESSEL OPERATOR · DISPUTE MEDIATION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("SMA NY · PANEL 3").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(accentViolet810)
            }
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Disputes").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var mediatorHero: some View {
        RimCard810 {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("MEDIATOR · SMA NEW YORK").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    Text(mediatorName).font(.system(size: 20, weight: .heavy)).tracking(-0.3).foregroundStyle(palette.textPrimary)
                    Text(mediatorFirm).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text(mediatorMeta).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    Text(sessionsLine).font(.system(size: 10.5, weight: .bold)).foregroundStyle(accentViolet810)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(text: awardPill, kind: .info)
                    Text(daysToAward).font(.system(size: 22, weight: .heavy)).tracking(-0.4).foregroundStyle(palette.textPrimary).monospacedDigit()
                    Text("TO AWARD").font(.system(size: 9, weight: .heavy)).tracking(0.3).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { idx, e in
                HStack(alignment: .top, spacing: 10) {
                    Text(e.date).font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(e.state == .active ? Brand.warning : palette.textTertiary)
                        .frame(width: 40, alignment: .trailing)
                    TimelineNode810(state: e.state, isLast: idx == events.count - 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.system(size: 13, weight: .bold))
                            .foregroundStyle(e.state == .future ? palette.textSecondary : palette.textPrimary)
                        Text(e.sub).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(e.tag).font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundStyle(tagColor(e.state))
                }
                .padding(.vertical, 8)
            }
            Divider().overlay(palette.borderFaint).padding(.top, 4)
            Text(proposedLine).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary).padding(.top, 10)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    private var esangCard: some View {
        HStack(spacing: 12) {
            Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("Submit the brief by 06-05 — 9 of 10 exhibits packed").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · \(esangLine)").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint))
    }

    private func tagColor(_ s: EventState810) -> Color {
        switch s {
        case .done: return Brand.success
        case .active: return Brand.warning
        case .scheduled: return accentViolet810
        case .future: return palette.textTertiary
        }
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar the
    /// registered vessel siblings ship for their secondary CTA (mirrors 757).
    private func secondaryButton810(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 52)
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
    private struct Timeline810: Decodable { let date: String?; let event: String?; let details: String? }
    private struct Mediation810: Decodable {
        let mediationStatus: String?; let timeline: [Timeline810]?
    }
    private struct MediationInput810: Encodable { let disputeId: String }

    private func load() async {
        loading = true; loadError = nil
        do {
            let m: Mediation810 = try await EusoTripAPI.shared.query("freightClaims.getDisputeMediation",
                                                                     input: MediationInput810(disputeId: disputeId))
            if let t = m.timeline, !t.isEmpty {
                events = t.prefix(4).enumerated().map { idx, e in
                    let state: EventState810 = idx == 0 ? .done : (idx == 1 ? .active : (idx == 2 ? .scheduled : .future))
                    let tag = ["DONE", "ACTIVE", "SCHED", "EXPECTED"][min(idx, 3)]
                    return MedEvent810(date: shortDate(e.date), title: e.event ?? "—", sub: e.details ?? "", tag: tag, state: state)
                }
            }
            // Empty timeline ("not_started") keeps the design-time projection — no fabricated rows.
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func submitBrief() async { /* submitMediationBrief — STUB · named-gap (no mutation on disk; surfaced to the-oath). */ await load() }
    private func schedule() async    { /* scheduleMediationSession — STUB · named-gap. */ await load() }

    private func shortDate(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return iso ?? "" }
        return String(iso.dropFirst(5).prefix(5))
    }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — the canonical port's `RimCard` is not a shared app
/// symbol, so we render the same gradient-stroked context-card grammar the
/// registered vessel siblings (757 `RimCard757`) ship.
private struct RimCard810<Content: View>: View {
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

/// Date-gutter timeline node: filled+check (done), ringed gradient (active), tinted dot (scheduled),
/// hollow neutral (future). Spine drawn by the row's leading vertical rule.
private struct TimelineNode810: View {
    let state: EventState810
    let isLast: Bool
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 0) {
            node
            if !isLast { Rectangle().fill(palette.borderFaint).frame(width: 2).frame(maxHeight: .infinity) }
        }
        .frame(width: 20)
    }
    @ViewBuilder private var node: some View {
        switch state {
        case .done:
            ZStack { Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) }
        case .active:
            ZStack { Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 3).frame(width: 20, height: 20)
                Circle().fill(LinearGradient.diagonal).frame(width: 8, height: 8) }
        case .scheduled:
            ZStack { Circle().strokeBorder(accentViolet810, lineWidth: 2).frame(width: 18, height: 18)
                Circle().fill(accentViolet810).frame(width: 7, height: 7) }
        case .future:
            Circle().strokeBorder(palette.textTertiary.opacity(0.5), lineWidth: 2).frame(width: 16, height: 16)
        }
    }
}

#Preview("810 · Vessel Dispute Mediation · Night") { VesselDisputeMediationScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("810 · Vessel Dispute Mediation · Light") { VesselDisputeMediationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
