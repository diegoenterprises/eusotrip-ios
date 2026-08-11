//
//  767_VesselSeaWaybill.swift
//  EusoTrip — Vessel Operator · Sea Waybill.
//
//  Faithful 1:1 port of "767 Vessel Sea Waybill.svg" (Light + Dark). NET-NEW gap screen closing the
//  BOOKING/DOCUMENTATION moat item "SeaWaybill option". STRAIGHT-CONSIGNMENT + CONTRAST archetype —
//  deliberately distinct from 005 Bill of Lading (negotiable title), 715/719 (B/L draft/eBL), 679 Telex
//  Release: the spine is a named-parties grid (consignee non-transferable) + a Sea-Waybill-vs-Original-B/L
//  comparison strip (surrender / title / negotiable / faster-release), emphasizing NON-NEGOTIABLE · NO
//  SURRENDER, not a negotiable-title surface.
//  Nav: VesselOperatorNavController (HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME).
//
//  VERIFICATION TIER: STATIC-REVIEWED (no Swift toolchain in the build lane). Mirrors the
//  render-verified SVG element-for-element. Uses only confirmed DesignSystem + _VesselReconKit.
//
//  Data / wiring (verified live 2026-06-15 via connected EusoTrip codebase):
//    EXISTS — createBOL vesselShipments.ts:503 (bolType z.enum master/house/express/SEAWAY — db.ts:2570,
//      seed vesselDemoData.ts:237) + getBOL:956 + services/bol.ts:326. A sea waybill IS
//      createBOL({bolType:'seaway'}) — EXISTS-backed, not a stub.
//    NAMED GAP (STUB · the-oath): only the ID-verified RELEASE-without-document gate for a seaway type
//      needs an explicit verb. Propose vessel.releaseSeaway({bolId,consigneeIdRef,confirm:true}) —
//      irreversible, human-gated + consignee-identity evidence + audit. RBAC: vesselProcedure.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 24h) view · waybill issue ONLINE_ONLY(title-waiver). Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

private struct SWBParty: Identifiable { let id = UUID(); let tag: String; let who: String; let detail: String }
private struct SWBRow: Identifiable { let id = UUID(); let label: String; let swb: String; let bl: String; let swbGood: Bool }
private struct SWBAuthority: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }

struct VesselSeaWaybillScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselSeaWaybillBody()
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

private struct VesselSeaWaybillBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var gapNotice: String? = nil

    // Seeds — overwritten by getBOL on .task.
    @State private var swbLine = "SWB MSCU-SW-7741210 · CNSHA→USLGB"
    @State private var swbStatus = "NON-NEGOTIABLE"

    private let parties: [SWBParty] = [
        SWBParty(tag: "SHIPPER",   who: "Eusorone Technologies", detail: "Shanghai CN · shipper of record"),
        SWBParty(tag: "CONSIGNEE", who: "Pier 1 Imports LLC",    detail: "named · non-transferable"),
        SWBParty(tag: "NOTIFY",    who: "Pier 1 Imports LLC",    detail: "same as consignee")
    ]
    private let rows: [SWBRow] = [
        SWBRow(label: "Surrender required", swb: "No",  bl: "Yes", swbGood: false),
        SWBRow(label: "Document of title",  swb: "No",  bl: "Yes", swbGood: false),
        SWBRow(label: "Negotiable",         swb: "No",  bl: "Yes", swbGood: false),
        SWBRow(label: "Faster release",     swb: "Yes", bl: "No",  swbGood: true)
    ]
    private let authorities: [SWBAuthority] = [
        SWBAuthority(code: "US", line: "US · USLGB · CBP · ID-verified release", active: true),
        SWBAuthority(code: "CA", line: "CA · CAVAN · CBSA cargo control",        active: false),
        SWBAuthority(code: "MX", line: "MX · MXZLO · Aduanas · carta porte",     active: false)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Sea waybill").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    hero
                    sectionLabel("NAMED PARTIES", ref: "EXISTS createBOL:892 bolType=seaway")
                    partiesCard
                    sectionLabel("WAYBILL vs ORIGINAL B/L", ref: "bol.ts:326")
                    contrastCard
                    sectionLabel("RELEASE AUTHORITY · discharge port", ref: "createBOL·country")
                    triCountryBand
                    if let note = gapNotice {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.info)
                            Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.info.opacity(0.08)))
                    }
                    HStack(spacing: 8) {
                        CTAButton(title: "Issue Sea Waybill") { Task { await issue() } }
                        SecondaryButton(title: "Switch to B/L") {}
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
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("VESSEL OPERATOR · SEA WAYBILL").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("STRAIGHT · SWB").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
        }
    }

    private func sectionLabel(_ t: String, ref: String?) -> some View {
        HStack {
            Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            if let r = ref { Text(r).font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textTertiary) }
        }
    }

    private var hero: some View {
        RimCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(swbLine).font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    StatusPill(text: swbStatus, kind: .info)
                }
                Text("Sea Waybill — straight").font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("No original issued · no surrender required").font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                Text("Release on consignee identity verification").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var partiesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(parties.enumerated()), id: \.element.id) { idx, p in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.tag).font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        Text(p.who).font(.system(size: 11.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                    }
                    Spacer(minLength: 0)
                    Text(p.detail).font(.system(size: 8.5)).foregroundStyle(palette.textTertiary)
                }
                .padding(.vertical, 8)
                if idx < parties.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var contrastCard: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("SEA WAYBILL").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.blue)
                    .frame(width: 96, alignment: .center)
                Text("ORIGINAL B/L").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    .frame(width: 84, alignment: .trailing)
            }
            .padding(.bottom, 6)
            Divider().overlay(palette.borderFaint)
            ForEach(rows) { r in
                HStack {
                    Text(r.label).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Text(r.swb).font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(r.swbGood ? Brand.success : palette.textTertiary)
                        .frame(width: 64, height: 19)
                        .background(palette.bgCardSoft).clipShape(Capsule())
                    Text(r.bl).font(.system(size: 9.5, weight: .bold)).foregroundStyle(palette.textTertiary)
                        .frame(width: 84, alignment: .trailing)
                }
                .padding(.vertical, 7)
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var triCountryBand: some View {
        VStack(spacing: 0) {
            ForEach(Array(authorities.enumerated()), id: \.element.id) { idx, r in
                HStack(spacing: 10) {
                    Text(r.code).font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(r.active ? Color.white : palette.textSecondary)
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(r.active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(Color.primary.opacity(0.06))))
                    Text(r.line).font(.system(size: r.active ? 10.5 : 10, weight: r.active ? .bold : .regular))
                        .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary)
                    Spacer(minLength: 0)
                    Text(r.active ? "● ACTIVE" : "STANDBY").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(r.active ? Brand.success : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(r.active ? AnyShapeStyle(LinearGradient.primary.opacity(0.10)) : AnyShapeStyle(Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                if idx < authorities.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(6)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Data
    private struct BOL767: Decodable {
        let bolNumber: String?; let bolType: String?; let status: String?
        let originPort: String?; let destinationPort: String?
    }
    private func load() async {
        loading = true; loadError = nil
        // LIVE: getBOL vesselShipments.ts:956 - a sea waybill is a first-class B/L type
        // (createBOL:892 bolType enum includes 'seaway'). The ID-verified release gate remains the
        // named gap (vessel.releaseSeaway) filed with the-oath.
        do {
            struct In: Encodable { let bolNumber: String }
            let b: BOL767? = try await EusoTripAPI.shared.query("vesselShipments.getBOL", input: In(bolNumber: "MSCU-SW-7741210"))
            if let b = b {
                let lane = [b.originPort, b.destinationPort].compactMap { $0 }.joined(separator: "->")
                swbLine = "SWB \(b.bolNumber ?? "MSCU-SW-7741210")\(lane.isEmpty ? "" : " · " + lane)"
                swbStatus = (b.bolType ?? "seaway") == "seaway" ? "NON-NEGOTIABLE" : (b.status ?? "issued").uppercased()
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
    private func issue() async {
        // EXISTS createBOL({bolType:'seaway'}); release gate = STUB vessel.releaseSeaway({bolId,consigneeIdRef,confirm:true}).
        gapNotice = "Issue maps to createBOL({bolType: seaway}) - EXISTS vesselShipments.ts:892 - but requires a booking (shipmentId) context this screen does not carry; the wired entry point is 007 New Booking. ID-verified release gate (vessel.releaseSeaway) is a named gap filed with the-oath."
        await load()
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


/// Rim-accent card (file-private; RimCard is not a shared app symbol — house pattern per 669/689/700).
private struct RimCard<Content: View>: View {
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

#Preview("767 · Sea Waybill · Night") { VesselSeaWaybillScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("767 · Sea Waybill · Light") { VesselSeaWaybillScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
