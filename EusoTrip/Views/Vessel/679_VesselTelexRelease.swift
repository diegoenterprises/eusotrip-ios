//
//  679_VesselTelexRelease.swift
//  EusoTrip — Vessel Operator · Telex Release (B/L surrender · release gate).
//
//  Verbatim port of "679 Vessel Telex Release.svg" (Dark + Light). Archetype =
//  COMPLIANCE-GATE (release authorization). Numbers-first surrender hero, a four-
//  node party-to-party release pipeline (telex node highlighted), the release-
//  conditions gate list with the single OPEN row amber-washed, and the instrument
//  + consignee-of-record strip.
//
//  tRPC (anchored on disk 2026-07):
//    vesselShipments.getBOL (EXISTS :944, {bolNumber?|id?}) — the master B/L row
//      (status drives surrender state / open gate).
//    vesselShipments.surrenderBOL (EXISTS :974, mutation {id}) — "Confirm release":
//      guards status=='issued' + shipper/consignee ownership; sets status
//      'surrendered' + blockchainAuditTrail 'vessel.bol_surrendered'.
//    vesselShipments.getCBPEntryStatus (EXISTS :2807, {entryNumber}) — the CBP
//      condition (releaseDate present ⇒ CLEAR, else OPEN) — ties to screen 663.
//  HONEST GAP (surfaced): there is no release-TYPE field / telex-transmission proc —
//    the release instrument ("Telex release") + transmission record are the design's
//    canonical presentation; proposed vesselShipments.setReleaseType → the-oath.
//
//  RBAC vesselProcedure. transportMode = vessel · US import · 46 CFR. NAV
//  (VesselOperator): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

private struct VNotify679: Decodable { let name: String?; let contact: String? }

private struct VBOL679: Decodable {
    let id: Int
    let bolNumber: String?
    let bolType: String?
    let status: String?          // draft | issued | surrendered | released
    let vesselName: String?
    let voyageNumber: String?
    let freightTerms: String?
    let originPort: String?
    let destinationPort: String?
    let notifyParty: VNotify679?
}

private struct VCBPStatus679: Decodable {
    let entryNumber: String?
    let status: String?
    let releaseDate: String?
}

struct VesselTelexReleaseScreen: View {
    var theme: Theme.Palette = Theme.dark
    var bolNumber: String = "MBL-VES260602-7B3D"
    var entryNumber: String = "3-7501"
    var lane: String = "CNSHA→USLGB"
    var vesselDisplay: String = "MV Eusorone Pioneer v.118E"

    var body: some View {
        Shell(theme: theme) {
            VesselTelexReleaseBody(bolNumber: bolNumber, entryNumber: entryNumber,
                                   lane: lane, vesselDisplay: vesselDisplay)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                  isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselTelexReleaseBody: View {
    @Environment(\.palette) private var palette
    let bolNumber: String
    let entryNumber: String
    let lane: String
    let vesselDisplay: String

    @State private var bol: VBOL679? = nil
    @State private var cbp: VCBPStatus679? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil
    @State private var releasing = false

    private var cbpCleared: Bool { cbp?.releaseDate != nil }
    private var freightPrepaid: Bool { (bol?.freightTerms ?? "prepaid").lowercased() == "prepaid" }
    private var noCarrierHold: Bool {
        !((bol?.status ?? "").lowercased().contains("hold"))
    }
    private var openConditions: Int {
        var n = 0
        if !freightPrepaid { n += 1 }
        if !noCarrierHold { n += 1 }
        if !cbpCleared { n += 1 }
        return n
    }
    private var surrendered: Bool {
        ["surrendered", "released", "delivered"].contains((bol?.status ?? "").lowercased())
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if let actionNote { noteBanner(actionNote) }

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    hero
                    releaseChain
                    conditions
                    instrumentStrip
                    esang
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ VESSEL OPERATOR · TELEX RELEASE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("US IMPORT · 46 CFR")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Telex release")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Brand.vessel.opacity(0.18))
                    Image(systemName: "doc.text")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x33C7DA))
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(bol?.bolNumber ?? bolNumber)
                        .font(EType.mono(.caption)).tracking(0.2)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(surrenderLine)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("lodged at CNSHA origin agent · May 21")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    Text("\(vesselDisplay) · \(lane)")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("VESSEL")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0x33C7DA))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.vessel.opacity(0.22)))
                    if openConditions > 0 {
                        Text("\(openConditions) OPEN")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(Brand.warning)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Brand.warning.opacity(0.20)))
                    }
                }
            }
        }
        .padding(Space.s5)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private var surrenderLine: String {
        surrendered ? "Originals surrendered" : "3/3 originals surrendered"
    }

    // MARK: - Release chain pipeline

    private struct ChainNode { let title: String; let sub: String; let done: Bool }

    private var chainNodes: [ChainNode] {
        [
            ChainNode(title: "Originals in", sub: "CNSHA · 05-21", done: true),
            ChainNode(title: "Telex sent", sub: "ONE · 06-01", done: true),
            ChainNode(title: "Agent got it", sub: "USLGB · 06-01", done: true),
            ChainNode(title: "Consignee", sub: cbpCleared ? "released" : "pending CBP", done: cbpCleared),
        ]
    }

    private var releaseChain: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("RELEASE CHAIN · MASTER B/L · surrenderBOL")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(chainNodes.enumerated()), id: \.offset) { idx, node in
                        VStack(spacing: 8) {
                            ZStack {
                                if idx == 1 {
                                    Circle().strokeBorder(Brand.blue.opacity(0.4), lineWidth: 3)
                                        .frame(width: 30, height: 30)
                                }
                                Circle()
                                    .fill(node.done ? AnyShapeStyle(LinearGradient.primary)
                                                    : AnyShapeStyle(palette.bgCardSoft))
                                    .overlay(Circle().strokeBorder(node.done ? Color.clear : Brand.warning, lineWidth: 2.2))
                                    .frame(width: 22, height: 22)
                                if node.done {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(.white)
                                } else {
                                    Circle().fill(Brand.warning).frame(width: 7, height: 7)
                                }
                            }
                            .frame(height: 30)
                            Text(node.title)
                                .font(.system(size: 9.5, weight: node.done ? .bold : .heavy))
                                .foregroundStyle(node.done ? palette.textPrimary : Brand.warning)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text(node.sub)
                                .font(EType.mono(.micro))
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                        if idx < chainNodes.count - 1 {
                            Rectangle()
                                .fill(chainNodes[idx + 1].done ? AnyShapeStyle(LinearGradient.primary)
                                      : AnyShapeStyle(Color.white.opacity(0.14)))
                                .frame(height: 2.4)
                                .offset(y: 15)
                        }
                    }
                }
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                Text("TLX-7B3D · \(lane) agent · sent Jun 1 · 05:21 UTC")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - Release conditions

    private struct Condition { let title: String; let sub: String; let clear: Bool }

    private var conditionList: [Condition] {
        [
            Condition(title: "Ocean freight prepaid", sub: "no money owed to carrier", clear: freightPrepaid),
            Condition(title: "No carrier hold", sub: "demurrage / detention not accrued", clear: noCarrierHold),
            Condition(title: "CBP entry filed & released",
                      sub: cbpCleared ? "entry \(cbp?.entryNumber ?? entryNumber) released" : "entry \(entryNumber) pending · ties to 663",
                      clear: cbpCleared),
        ]
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("RELEASE CONDITIONS · what gates pickup")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(Array(conditionList.enumerated()), id: \.offset) { _, c in
                    conditionRow(c)
                }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func conditionRow(_ c: Condition) -> some View {
        let tint = c.clear ? Brand.success : Brand.warning
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(tint.opacity(0.20)).frame(width: 20, height: 20)
                Image(systemName: c.clear ? "checkmark" : "exclamationmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(c.sub)
                    .font(EType.mono(.micro))
                    .foregroundStyle(c.clear ? palette.textTertiary : Brand.warning)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            Text(c.clear ? "CLEAR" : "OPEN")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(tint)
        }
        .padding(Space.s3)
        .background(c.clear ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Brand.warning.opacity(0.10)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Instrument + consignee strip

    private var instrumentStrip: some View {
        HStack(spacing: Space.s3) {
            factTile(label: "RELEASE INSTRUMENT", title: "Telex release", sub: "no originals travel")
            factTile(label: "CONSIGNEE OF RECORD", title: consigneeName, sub: "USLGB · import of record")
        }
    }

    private var consigneeName: String {
        bol?.notifyParty?.name ?? "Consignee of record"
    }

    private func factTile(label: String, title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - ESANG

    private var esang: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .white.opacity(0)],
                                             center: .init(x: 0.35, y: 0.30),
                                             startRadius: 0, endRadius: 16))
                    .frame(width: 22, height: 22)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · RELEASE READINESS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(cbpCleared ? "Cleared — cargo can release" : "Paper side is clear — only CBP entry left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("chase customs, not the carrier · unlocks on release")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await confirmRelease() }
            } label: {
                Text(surrendered ? "Released" : (releasing ? "Releasing…" : "Confirm release"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(releasing || surrendered ? 0.6 : 1)
            .disabled(releasing || surrendered)

            Button {
                Task { await viewBOL() }
            } label: {
                Text("View B/L")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading + note

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 112)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 120)
        }
    }

    private func noteBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.info)
            Text(message).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Button { actionNote = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.info.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.info.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct BOLIn: Encodable { let bolNumber: String }
        struct CBPIn: Encodable { let entryNumber: String }
        do {
            async let b: VBOL679? = EusoTripAPI.shared.query(
                "vesselShipments.getBOL", input: BOLIn(bolNumber: bolNumber))
            async let c: VCBPStatus679? = EusoTripAPI.shared.query(
                "vesselShipments.getCBPEntryStatus", input: CBPIn(entryNumber: entryNumber))
            let (bolRow, cbpRow) = try await (b, c)
            self.bol = bolRow
            self.cbp = cbpRow
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func confirmRelease() async {
        guard let b = bol else {
            actionNote = "No bill of lading loaded to release."
            return
        }
        releasing = true
        struct In: Encodable { let id: Int }
        struct Out: Decodable { let success: Bool?; let status: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "vesselShipments.surrenderBOL", input: In(id: b.id))
            if out.success == true {
                actionNote = "Release confirmed — B/L surrendered by telex."
                await load()
            } else {
                actionNote = "Release could not be confirmed."
            }
        } catch {
            actionNote = "Release unavailable. "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        releasing = false
    }

    private func viewBOL() async {
        actionNote = "Opening master B/L \(bol?.bolNumber ?? bolNumber)."
    }
}

#Preview("679 · Vessel Telex Release · Night") {
    VesselTelexReleaseScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("679 · Vessel Telex Release · Light") {
    VesselTelexReleaseScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
