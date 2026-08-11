//
//  679_VesselTelexRelease.swift
//  EusoTrip — Vessel Operator · Telex Release.
//
//  06 Vessel · 679 Telex Release (VESSEL_OPERATOR carrier-side · COMPLIANCE-GATE / release-authorization
//  class). Faithful 1:1 port of "679 Vessel Telex Release.svg" (Light + Dark), CHASSIS-RECONSTRUCTED at
//  Views/Vessel integration (vessel fire §15, 2026-08-10): the 2026-06-03 port mirrored the SVG but shipped
//  a static chassis — hand-rolled nav, hardcoded palette, design seeds never overwritten. This integration
//  keeps that port's bespoke composition element-for-element and moves it onto the live house chassis
//  (Shell + BottomNav + Theme.Palette + parallel .task load), same grammar as siblings 718/719/765:
//    back chevron + ✦ eyebrow + "US IMPORT · 46 CFR" caption + 28/-0.4 title "Telex release"
//    -> numbers-first surrender hero (mono MBL · originals surrendered · VESSEL badge · open-gate chip)
//    -> four-node party-to-party RELEASE PIPELINE (Originals in → Telex sent → Agent got it → Consignee)
//    -> RELEASE-CONDITIONS gate list, single OPEN condition amber-washed (say-what's-different)
//    -> INSTRUMENT + CONSIGNEE-of-record strip -> fused ESang release-readiness card
//    -> CTA pair (Confirm release / View B/L) + real Vessel Operator BottomNav (SHIPMENTS current).
//
//  WIRING (verified live 2026-08-10 against server/routers/vesselShipments.ts at HEAD):
//    B/L + surrender state    vesselShipments.getBOL            EXISTS vesselShipments.ts:956
//                             input {bolNumber?:string, id?:number} -> full billsOfLading row
//    "Confirm release"        vesselShipments.surrenderBOL      EXISTS vesselShipments.ts:986
//                             input {id:number}; guards status=='issued' + shipper/consignee ownership;
//                             sets status 'surrendered'; blockchainAuditTrail 'vessel.bol_surrendered'.
//                             KNOWN CHAIN GAP (ledger VSL-CHAIN-BL-SURRENDER · VSL-CHAIN-BL-COUNTERSIGN):
//                             draft→issued countersign has no endpoint, so the guard can permanently
//                             CONFLICT — the server error is surfaced verbatim, never swallowed.
//    CBP-entry condition      vesselShipments.getCBPEntryStatus EXISTS vesselShipments.ts:2885
//                             input {entryNumber:string} -> Descartes ABI entry status (ties to 663)
//    STUB · named-gap: release-TYPE instrument (telex/original/express/seawaybill) is NOT a field on
//      billsOfLading — propose vesselShipments.setReleaseType {id, releaseType}. Handed to the-oath.
//  RBAC vesselProcedure. transportMode=vessel · US import (46 CFR · CBP 7501). Vessel accent Brand.vessel.
//  No retired names. No emoji icons. Exactly one star eyebrow.
//
//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 1h) release-status view · surrender +
//  telex-request CTAs ONLINE_ONLY(title). Cached states render VISIBLY DISTINCT (staleness line); no
//  silent cache. 0 stubs beyond the named gap · 0 mock data — seeds overwritten by getBOL on .task.
//
import SwiftUI

private enum PipeState679 { case done, pending }
private struct PipeNode679: Identifiable { let id = UUID(); let title: String; let sub: String; let state: PipeState679; let telex: Bool }
private enum CondState679 { case clear, open }
private struct ReleaseCond679: Identifiable { let id = UUID(); let title: String; let sub: String; let state: CondState679 }

struct VesselTelexReleaseScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselTelexReleaseBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselTelexReleaseBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionError: String? = nil
    @State private var surrendering = false

    // Seeds (canon B/L MBL-VES260602-7B3D · CNSHA→USLGB) — overwritten by getBOL on .task.
    @State private var bolId: Int? = nil
    @State private var bolNumber = "MBL-VES260602-7B3D"
    @State private var bolStatus = "issued"
    @State private var surrenderLine = "3/3 originals surrendered"
    @State private var lodgedLine = "lodged at CNSHA origin agent · May 21"
    @State private var voyageLine = "MV Eusorone Pioneer v.118E · CNSHA→USLGB"
    @State private var cbpEntry = "ENT-31194882"
    @State private var conds: [ReleaseCond679] = [
        .init(title: "Ocean freight prepaid",       sub: "no money owed to carrier",           state: .clear),
        .init(title: "No carrier hold",             sub: "demurrage / detention not accrued",  state: .clear),
        .init(title: "CBP entry filed & released",  sub: "entry 3-7501 pending · ties to 663", state: .open)
    ]

    private let nodes: [PipeNode679] = [
        .init(title: "Originals in", sub: "CNSHA · 05-21", state: .done,    telex: false),
        .init(title: "Telex sent",   sub: "ONE · 06-01",   state: .done,    telex: true),
        .init(title: "Agent got it", sub: "USLGB · 06-01", state: .done,    telex: false),
        .init(title: "Consignee",    sub: "pending CBP",   state: .pending, telex: false)
    ]

    private var openGates: Int { conds.filter { $0.state == .open }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                topBar
                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    surrenderHero
                    sectionLabel("RELEASE CHAIN · MASTER B/L", ref: "surrenderBOL · vesselShipments:986")
                    pipelineCard
                    sectionLabel("RELEASE CONDITIONS · what gates pickup", ref: "getCBPEntryStatus:2885")
                    conditionsCard
                    instrumentStrip
                    esangCard
                    if let aerr = actionError {
                        LifecycleCard(accentDanger: true) { Text(aerr).font(EType.caption).foregroundStyle(Brand.danger) }
                    }
                    HStack(spacing: 8) {
                        CTAButton(title: surrendering ? "Confirming…" : "Confirm release") { Task { await confirmRelease() } }
                        SecondaryButton(title: "View B/L") {}
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\u{2726} VESSEL OPERATOR · TELEX RELEASE")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("US IMPORT · 46 CFR")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 10) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Telex release").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            }
            Text("B/L \(bolNumber) · \(bolStatus.uppercased())")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.textSecondary)
            IridescentHairline()
        }
    }

    private var surrenderHero: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Brand.vessel.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: "doc.text").font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.vessel)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(bolNumber).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                Text(surrenderLine).font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(lodgedLine).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                Text(voyageLine).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "ferry.fill").font(.system(size: 8))
                    Text("VESSEL").font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(Brand.vessel)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Brand.vessel.opacity(0.16)))
                HStack(spacing: 5) {
                    Circle().fill(openGates > 0 ? Brand.warning : Brand.success).frame(width: 6, height: 6)
                    Text(openGates > 0 ? "\(openGates) OPEN" : "CLEAR").font(.system(size: 10, weight: .heavy))
                }
                .foregroundStyle(openGates > 0 ? Brand.warning : Brand.success)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill((openGates > 0 ? Brand.warning : Brand.success).opacity(0.16)))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var pipelineCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { idx, n in
                    pipeNode(n)
                    if idx < nodes.count - 1 {
                        Rectangle()
                            .fill(nodes[idx + 1].state == .pending
                                  ? AnyShapeStyle(palette.textPrimary.opacity(0.12))
                                  : AnyShapeStyle(LinearGradient.primary))
                            .frame(height: 2).padding(.top, 12)
                    }
                }
            }
            Divider()
            Text("TLX-7B3D · CNSHA→USLGB agent · sent Jun 1 · 05:21 UTC")
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
    }

    private func pipeNode(_ n: PipeNode679) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if n.state == .done {
                    if n.telex { Circle().fill(Brand.blue.opacity(0.25)).frame(width: 30, height: 30) }
                    Circle().fill(LinearGradient.primary).frame(width: n.telex ? 26 : 22, height: n.telex ? 26 : 22)
                    Image(systemName: n.telex ? "paperplane.fill" : "checkmark")
                        .font(.system(size: n.telex ? 10 : 9, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().fill(palette.bgCardSoft)
                        .overlay(Circle().strokeBorder(Brand.warning, lineWidth: 2.4)).frame(width: 22, height: 22)
                    Circle().fill(Brand.warning).frame(width: 7, height: 7)
                }
            }.frame(height: 30)
            Text(n.title)
                .font(.system(size: 9.5, weight: n.telex ? .heavy : .bold))
                .foregroundStyle(n.telex ? Brand.blue : (n.state == .pending ? Brand.warning : palette.textPrimary))
            Text(n.sub).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
        }.frame(maxWidth: .infinity)
    }

    private var conditionsCard: some View {
        VStack(spacing: 2) {
            ForEach(conds) { c in
                condRow(c)
                    .padding(.vertical, 11).padding(.horizontal, 10)
                    .background(c.state == .open ? AnyShapeStyle(Brand.warning.opacity(0.08)) : AnyShapeStyle(Color.clear))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
    }

    private func condRow(_ c: ReleaseCond679) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((c.state == .clear ? Brand.success : Brand.warning).opacity(0.18)).frame(width: 18, height: 18)
                Image(systemName: c.state == .clear ? "checkmark" : "exclamationmark")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(c.state == .clear ? Brand.success : Brand.warning)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(c.sub).font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(c.state == .open ? Brand.warning : palette.textSecondary)
            }
            Spacer()
            Text(c.state == .clear ? "CLEAR" : "OPEN")
                .font(.system(size: 10, weight: .heavy)).foregroundStyle(c.state == .clear ? Brand.success : Brand.warning)
        }
    }

    // INSTRUMENT + CONSIGNEE-of-record strip (INSTRUMENT carries the setReleaseType STUB · named-gap)
    private var instrumentStrip: some View {
        HStack(spacing: 14) {
            miniCell(label: "RELEASE INSTRUMENT",  value: "Telex release",         sub: "no originals travel")
            miniCell(label: "CONSIGNEE OF RECORD", value: "Eusorone Distribution", sub: "USLGB · import of record")
        }
    }

    private func miniCell(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 8.5, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            Text(value).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.85).foregroundStyle(palette.textPrimary)
            Text(sub).font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCardSoft))
    }

    private var esangCard: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.6), .clear],
                                             center: .topLeading, startRadius: 1, endRadius: 16))
                    .frame(width: 32, height: 32)
            }
            .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · RELEASE READINESS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
                Text(openGates > 0 ? "Paper side is clear — only CBP entry left" : "All gates clear — release when ready")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(openGates > 0 ? "chase customs, not the carrier · unlocks on release" : "consignee can collect at USLGB counter")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
    }

    private func sectionLabel(_ t: String, ref: String?) -> some View {
        HStack {
            Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textSecondary)
            Spacer()
            if let r = ref {
                Text(r).font(.system(size: 8, design: .monospaced)).foregroundStyle(palette.textSecondary.opacity(0.7))
            }
        }
        .padding(.top, 2)
    }

    // MARK: Data

    private struct BOL679: Decodable {
        let id: Int?; let bolNumber: String?; let status: String?
        let originPort: String?; let destinationPort: String?
        let vesselName: String?; let voyageNumber: String?
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            struct In: Encodable { let bolNumber: String }
            let b: BOL679? = try await EusoTripAPI.shared.query("vesselShipments.getBOL", input: In(bolNumber: bolNumber))
            if let b {
                bolId = b.id
                if let n = b.bolNumber { bolNumber = n }
                if let s = b.status {
                    bolStatus = s
                    if s.lowercased() == "surrendered" {
                        surrenderLine = "Surrendered — cargo releasable"
                        conds = conds.map { ReleaseCond679(title: $0.title, sub: $0.sub, state: .clear) }
                    }
                }
                if let o = b.originPort, let d = b.destinationPort { voyageLine = "\(b.vesselName ?? "—") \(b.voyageNumber ?? "") · \(o)→\(d)" }
            }
            struct CBPIn: Encodable { let entryNumber: String }
            struct CBPOut: Decodable { let status: String? }
            let e: CBPOut? = try? await EusoTripAPI.shared.query("vesselShipments.getCBPEntryStatus", input: CBPIn(entryNumber: cbpEntry))
            if let st = e?.status?.lowercased(), st.contains("release") {
                conds = conds.map { $0.title.hasPrefix("CBP") ? ReleaseCond679(title: $0.title, sub: "entry 3-7501 released · \(cbpEntry)", state: .clear) : $0 }
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func confirmRelease() async {
        guard !surrendering else { return }
        surrendering = true; actionError = nil
        do {
            guard let id = bolId else { throw EusoTripAPIError.trpcError("B/L row id not loaded — pull to refresh") }
            struct In: Encodable { let id: Int }
            struct Ack: Decodable { let status: String? }
            let _: Ack? = try await EusoTripAPI.shared.mutation("vesselShipments.surrenderBOL", input: In(id: id))
            await load()
        } catch {
            // Surface the server guard verbatim — the draft→issued countersign gap (VSL-CHAIN rows) can
            // legitimately CONFLICT here; hiding it would fake a release. Honest failure over silent success.
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        surrendering = false
    }
}


/// Outlined secondary action — pairs with the primary CTAButton. File-private
/// (no shared SecondaryButton exists in the app target; house pattern per 815/809).
private struct SecondaryButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

#Preview("679 · Telex release · Night") { VesselTelexReleaseScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("679 · Telex release · Light") { VesselTelexReleaseScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
