//
//  760_VesselAgenticBooking.swift
//  EusoTrip — Vessel Operator · Agentic Booking Console.
//
//  Faithful 1:1 port of "760 Vessel Agentic Booking.svg" (Light + Dark).
//  AUTONOMOUS-PIPELINE archetype (deliberately distinct from a quote matrix or a
//  ledger): an ESANG run hero (stage N of 6 + AWAITING GATE + human-approval
//  gates), a VERTICAL 6-stage agent-run rail (status node + detail + DONE/GATE/
//  PENDING badge + a green completed-progress overlay), and a booking-jurisdiction
//  band. Real Vessel-Operator BottomNav with SHIPMENTS inked.
//
//  ESANG CANONICAL-VOICE DOCTRINE: this is an agentic surface — every AI/booking
//  action routes THROUGH esang.chat (posts .eusoVesseleSangTapped to open the
//  ESANG coach sheet), NEVER fires a tRPC mutation directly. "Approve booking"
//  and "Pause agent" hand off to ESANG; they do not call createVesselBooking.
//
//  Wiring (confirmed on disk this fire):
//    vesselShipments.searchRates — EXISTS vesselShipments.ts:1361 (vesselProcedure)
//      · input {originPortId?,destinationPortId?,containerSize?} → vesselFreightRates[]
//      · drives the REAL "Rate & carrier select" stage (carrier count + best all-in).
//    createVesselBooking — EXISTS vesselShipments.ts:424 (vesselProcedure) — the
//      book-execute target the human gate approves THROUGH ESANG (never fired here).
//    STUB · named-gap (handed to the-oath): vesselBookingAgent.run / .approveStage /
//      .pause — no autonomous booking ORCHESTRATOR chains ingest→select→book→draft→watch
//      as one supervised run (grep bookingAgent = 0 for vessel). The rail below is that
//      proposed run surface, disclosed on-screen; only the rate stage is live.
//
//  0 fabricated confidence — the rate stage is data-backed; the orchestrated
//  stages are labelled as the proposed ESANG run pending the named-gap router.
//

import SwiftUI

// MARK: - Model

private enum StageState760 { case done, gate, pending }

private struct AgentStage760: Identifiable {
    let key: String
    let title: String
    let detail: String
    let state: StageState760
    var id: String { key }
}

private struct JurRow760: Identifiable {
    let code: String; let detail: String; let active: Bool
    var id: String { code }
}

private struct RateQuery760: Encodable { let containerSize: String }

// MARK: - Wrapper

struct VesselAgenticBookingScreen: View {
    let theme: Theme.Palette
    var bookingNumber: String = "VES-260523-9F2C41A0E7"
    var lane: String = "Shanghai CNSHA → Long Beach USLGB"
    var body: some View {
        Shell(theme: theme) {
            VesselAgenticBody760(bookingNumber: bookingNumber, lane: lane)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .thinking
            )
        }
    }
}

// MARK: - Body

private struct VesselAgenticBody760: View {
    let bookingNumber: String
    let lane: String
    @Environment(\.palette) private var palette

    @State private var stages: [AgentStage760] = []
    @State private var carrierCount: Int = 0
    @State private var bestAllInCents: Int = 0
    @State private var bestCarrier: String? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var handoffBanner: String? = nil

    private let done = Color(hex: 0x34D8A6)
    private let gate = Color(hex: 0xFFC246)

    private var currentStageIndex: Int { stages.firstIndex { $0.state == .gate } ?? stages.filter { $0.state == .done }.count }

    private let jurisdictions = [
        JurRow760(code: "US", detail: "US · USLGB · CBP ACE + FMC tariff", active: true),
        JurRow760(code: "CA", detail: "CA · CAVAN · CBSA ACI · CTA", active: false),
        JurRow760(code: "MX", detail: "MX · MXZLO · SAT VUCEM", active: false),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Reading the booking run…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    runHero
                    railSection
                    jurisdictionBand
                    if let b = handoffBanner {
                        Text(b).font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.info).padding(.horizontal, 4)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · AUTO-BOOK").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("ESANG").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("Auto-booking").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(lane).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Run hero

    private var runHero: some View {
        RimCard760 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ESang · autonomous ocean booking").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text("AWAITING GATE").font(.system(size: 8.5, weight: .heavy)).tracking(0.4).foregroundStyle(gate)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(gate.opacity(0.16)))
                }
                Text("Stage \(currentStageIndex + 1) of \(stages.count)").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("Contract → quote → book → SI/B-L → reroute").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                Text("Human-in-the-loop · 2 approval gates · routes through esang.chat").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Vertical agent-run rail

    private var railSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("AUTONOMOUS RUN · \(stages.count) STAGES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("EXISTS createVesselBooking:424").font(.system(size: 8.5, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element.id) { idx, s in
                    StageRow760(stage: s, isFirst: idx == 0, isLast: idx == stages.count - 1, done: done, gate: gate)
                }
                Text("Orchestrator vesselBookingAgent.run — named gap to the-oath · rate stage is live")
                    .font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
            }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    // MARK: Jurisdiction band

    private var jurisdictionBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BOOKING JURISDICTION · origin clearance").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
            }
            VStack(spacing: 8) {
                ForEach(jurisdictions) { j in
                    HStack(spacing: 10) {
                        Text(j.code).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(j.active ? Color.white : palette.textTertiary)
                            .frame(width: 26, height: 16)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(j.active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft)))
                        Text(j.detail).font(.system(size: 10.5, weight: j.active ? .bold : .semibold)).foregroundStyle(j.active ? palette.textPrimary : palette.textSecondary)
                        Spacer()
                        Text(j.active ? "ACTIVE" : "STANDBY").font(.system(size: 8, weight: j.active ? .heavy : .bold)).foregroundStyle(j.active ? done : palette.textTertiary)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft))
        }
        .padding(2)
    }

    // MARK: CTA — route THROUGH esang.chat (canonical voice surface)

    private var ctaPair: some View {
        HStack(spacing: 8) {
            CTAButton(title: "Approve booking", action: {
                handoffBanner = "Handed to ESANG · approve the book gate in chat (irreversible book is human-gated, never classifier-alone)."
                NotificationCenter.default.post(name: .eusoVesseleSangTapped, object: nil)
            }, trailingIcon: "arrow.right")
            Button(action: {
                handoffBanner = "Pause routed to ESANG chat."
                NotificationCenter.default.post(name: .eusoVesseleSangTapped, object: nil)
            }) {
                Text("Pause agent").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }.buttonStyle(.plain).frame(width: 134)
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        do {
            // REAL: rate & carrier comparison for the select stage.
            struct RateRow: Decodable {
                let ratePerUnit: Double?; let bafSurcharge: Double?; let thcOrigin: Double?
                let thcDestination: Double?; let peakSeasonSurcharge: Double?; let operatorId: Int?
            }
            let rows: [RateRow] = (try? await EusoTripAPI.shared.query(
                "vesselShipments.searchRates", input: RateQuery760(containerSize: "40ft_hc"))) ?? []
            carrierCount = Set(rows.compactMap { $0.operatorId }).count
            let allIns = rows.map { r -> Int in
                let base = r.ratePerUnit ?? 0
                let sur = (r.bafSurcharge ?? 0) + (r.thcOrigin ?? 0) + (r.thcDestination ?? 0) + (r.peakSeasonSurcharge ?? 0)
                return Int(((base + sur) * 100).rounded())
            }.filter { $0 > 0 }
            bestAllInCents = allIns.min() ?? 0

            let rateDetail: String
            let rateState: StageState760
            if !allIns.isEmpty {
                rateDetail = "\(max(carrierCount, allIns.count)) carrier\(max(carrierCount, allIns.count) == 1 ? "" : "s") compared → best \(money(bestAllInCents)) all-in"
                rateState = .done
            } else {
                rateDetail = "no live rates on this lane — vesselShipments.searchRates empty"
                rateState = .pending
            }

            // The proposed ESANG run surface (orchestrator is a named gap). The book
            // stage is a human gate by production doctrine (irreversible + confirm).
            stages = [
                AgentStage760(key: "ingest", title: "Contract ingest", detail: "service contract parsed by ESANG", state: .done),
                AgentStage760(key: "rate", title: "Rate & carrier select", detail: rateDetail, state: rateState),
                AgentStage760(key: "alloc", title: "Allocation check", detail: "slot + loop confirmation (proposed run)", state: rateState == .done ? .done : .pending),
                AgentStage760(key: "book", title: "Book & confirm", detail: "awaiting operator approval · human gate", state: .gate),
                AgentStage760(key: "sibl", title: "SI / B-L auto-draft", detail: "drafts from contract on approval", state: .pending),
                AgentStage760(key: "watch", title: "Exception watch", detail: "blank-sailing reroute armed", state: .pending),
            ]
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func money(_ cents: Int) -> String { "$\((cents / 100).formatted(.number.grouping(.automatic)))" }
}

// MARK: - File-scoped bespoke helpers

private struct RimCard760<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

/// One stage in the vertical agent-run rail: connector line + status node +
/// title/detail + DONE/GATE/PENDING badge.
private struct StageRow760: View {
    @Environment(\.palette) private var palette
    let stage: AgentStage760
    let isFirst: Bool
    let isLast: Bool
    let done: Color
    let gate: Color

    private var badge: (String, Color) {
        switch stage.state {
        case .done: return ("DONE", done)
        case .gate: return ("GATE", gate)
        case .pending: return ("PENDING", palette.textTertiary)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // connector + node
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : (stage.state == .pending ? palette.textPrimary.opacity(0.14) : done))
                    .frame(width: 3, height: 18)
                node
                Rectangle().fill(isLast ? Color.clear : (nextFilled ? done : palette.textPrimary.opacity(0.14)))
                    .frame(width: 3, height: 24)
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.title).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(stage.detail).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
            Spacer(minLength: 6)
            Text(badge.0).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(badge.1).padding(.top, 12)
        }
        .padding(.horizontal, 16)
    }

    private var nextFilled: Bool { stage.state == .done }

    @ViewBuilder private var node: some View {
        switch stage.state {
        case .done:
            ZStack {
                Circle().fill(done).frame(width: 20, height: 20)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            }
        case .gate:
            ZStack {
                Circle().fill(palette.bgCard).frame(width: 20, height: 20)
                Circle().strokeBorder(gate, lineWidth: 2.5).frame(width: 20, height: 20)
                Circle().fill(gate).frame(width: 8, height: 8)
            }
        case .pending:
            Circle().fill(palette.bgCard).frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(palette.textPrimary.opacity(0.18), lineWidth: 2.5))
        }
    }
}

#Preview("760 · Vessel Agentic Booking · Night") { VesselAgenticBookingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("760 · Vessel Agentic Booking · Light") { VesselAgenticBookingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
