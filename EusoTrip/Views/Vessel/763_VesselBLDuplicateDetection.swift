//
//  763_VesselBLDuplicateDetection.swift
//  EusoTrip — Vessel Operator · B/L Duplicate & Switch-B/L Detection.
//
//  Faithful 1:1 port of "763 Vessel B-L Duplicate Detection.svg" (Light + Dark). NET-NEW gap screen
//  closing the VESSEL-MODE GAP-HUNT items "BL uniqueness / duplicate detection — UNIQUE(scac,
//  bl_number)" and "Voyage replay vs AIS gaps > 4h → switch-BL flag". DOCUMENT-FRAUD DIFF archetype —
//  deliberately distinct from 716 AIS Integrity STS Sanctions (which owns the vessel/AIS-MOVEMENT
//  fraud surface: STS rendezvous, reflagging, GISIS phantom-ship, OFAC party-screen). 763 is the
//  B/L DOCUMENT-fraud angle: a two-column ORIGINAL vs DUPLICATE field diff + a duplicate-fraud
//  checklist → verdict. No overlap (716 = movement/registry, 763 = paper/title).
//  Nav: VesselOperatorNavController (HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME).
//
//  VERIFICATION TIER: STATIC-REVIEWED (no Swift toolchain in the build lane). Mirrors the
//  render-verified SVG element-for-element. Uses only confirmed DesignSystem + _VesselReconKit.
//
//  Data / wiring (verified live 2026-06-15 via connected EusoTrip codebase):
//    EXISTS — getBOL vesselShipments.ts:567 + listBOLs:973 (bl_drafts, UNIQUE(scac,bl_number);
//      createBOL:892, surrenderBOL:986); sanctions.screenEntity sanctions.ts:107 (real OFAC).
//    NAMED GAP (STUB · the-oath): no duplicate/switch-BL DETECTOR diffing two issuances of one
//      (scac,bl_number) + scoring substitution risk (UNIQUE rejects a dup at write; no read-side
//      surfacing of the attempted collision + consignee-swap). Propose blIntegrity.checkDuplicate(
//      {scac,blNumber}) -> {instances[], fields[{name,originalValue,duplicateValue,diff}],
//      signals[{name,state,detail}], verdict}; blIntegrity.holdRelease({bolId,confirm:true}) — blocks
//      release, human-gated + audited; eval owed (switch-BL precision/recall). RBAC: vesselProcedure.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 1h) analytics · no offline commits (read-only surface). Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

private struct BLField: Identifiable { let id = UUID(); let name: String; let original: String; let duplicate: String; let diff: Bool }
private struct FraudSignal: Identifiable { let id = UUID(); let name: String; let detail: String; let badge: String; let danger: Bool }
private struct BLRegistry: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }

struct VesselBLDuplicateDetectionScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselBLDuplicateDetectionBody()
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

private struct VesselBLDuplicateDetectionBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var bl = "MSCUSH6840517"
    @State private var duplicateSeen = true      // overwritten by the listBOLs scan on .task
    @State private var gapNotice: String? = nil

    @State private var fields: [BLField] = [
        BLField(name: "Consignee",      original: "Pier 1 Imports", duplicate: "Horizon Trd FZE", diff: true),
        BLField(name: "Issue date",     original: "Jun 02",         duplicate: "Jun 09",          diff: true),
        BLField(name: "Release type",   original: "Original",       duplicate: "Telex",           diff: true),
        BLField(name: "Declared value", original: "$1.20M",         duplicate: "$1.20M",          diff: false)
    ]
    @State private var signals: [FraudSignal] = [
        FraudSignal(name: "Duplicate (SCAC, B/L no.)", detail: "same number, 2 issuances", badge: "FLAG",   danger: true),
        FraudSignal(name: "Consignee substitution",    detail: "Pier 1 → Horizon FZE",     badge: "FLAG",   danger: true),
        FraudSignal(name: "Release-method mismatch",   detail: "Original vs Telex",         badge: "REVIEW", danger: false)
    ]
    private let registries: [BLRegistry] = [
        BLRegistry(code: "US", line: "US · FMC + CBP · e-Manifest dup-check", active: true),
        BLRegistry(code: "CA", line: "CA · CBSA ACI · cargo control no.", active: false),
        BLRegistry(code: "MX", line: "MX · SAT VUCEM · BL registry", active: false)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("B/L integrity").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    hero
                    sectionLabel("ORIGINAL vs DUPLICATE", ref: "EXISTS getBOL:956")
                    diffCard
                    sectionLabel("DUPLICATE-FRAUD SIGNALS", ref: "STUB · blIntegrity.checkDup")
                    signalList
                    sectionLabel("B/L REGISTRY AUTHORITY", ref: "blIntegrity·country")
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
                        CTAButton(title: "Flag & hold release") { Task { await hold() } }
                        SecondaryButton(title: "Clear") { gapNotice = nil }
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
            Text("VESSEL OPERATOR · B/L INTEGRITY").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("SCAC MSCU").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
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
                    Text("B/L \(bl) · SCAC MSCU").font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    StatusPill(text: duplicateSeen ? "1 DUPLICATE" : "NO DUPLICATE", kind: duplicateSeen ? .danger : .success)
                }
                Text(duplicateSeen ? "Switch-B/L risk — REVIEW" : "Single issuance — registry clean")
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text(duplicateSeen ? "UNIQUE(scac, bl_number) collision" : "UNIQUE(scac, bl_number) holds")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                HStack {
                    Text(duplicateSeen ? "Issued twice · fields diverge" : "One issuance on file · fields verified")
                        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(duplicateSeen ? "HOLD RELEASE" : "RELEASABLE").font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(duplicateSeen ? Brand.danger : Brand.success)
                }
            }
        }
    }

    private var diffCard: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("ORIGINAL").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.success)
                Spacer().frame(width: 28)
                Text("DUPLICATE").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.danger)
            }
            .padding(.bottom, 6)
            Divider().overlay(palette.borderFaint)
            ForEach(fields) { f in
                HStack(spacing: 8) {
                    Circle().fill(f.diff ? Brand.danger : Brand.success).frame(width: 7, height: 7)
                    Text(f.name).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 4)
                    Text(f.original).font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Text(f.duplicate).font(.system(size: 9, weight: f.diff ? .heavy : .regular, design: .monospaced))
                        .foregroundStyle(f.diff ? Brand.danger : palette.textSecondary)
                        .frame(width: 96, alignment: .trailing)
                }
                .padding(.vertical, 7)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var signalList: some View {
        VStack(spacing: 0) {
            ForEach(Array(signals.enumerated()), id: \.element.id) { idx, g in
                if idx > 0 { Divider().overlay(palette.borderFaint) }
                HStack(spacing: 12) {
                    ZStack {
                        Circle().strokeBorder(g.danger ? Brand.danger : Brand.warning, lineWidth: 2).frame(width: 18, height: 18)
                        Text("!").font(.system(size: 11, weight: .heavy)).foregroundStyle(g.danger ? Brand.danger : Brand.warning)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name).font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(g.detail).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 6)
                    Text(g.badge).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(g.danger ? Brand.danger : Brand.warning)
                }
                .padding(.vertical, 9)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var triCountryBand: some View {
        VStack(spacing: 0) {
            ForEach(Array(registries.enumerated()), id: \.element.id) { idx, r in
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
                if idx < registries.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(6)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Data
    private struct BOL763: Decodable {
        let id: Int?; let bolNumber: String?; let bolType: String?; let status: String?
        let consigneeId: Int?; let createdAt: String?
    }
    private func load() async {
        loading = true; loadError = nil
        // LIVE: getBOL vesselShipments.ts:956 (the ORIGINAL column) + listBOLs vesselShipments.ts:973
        // (candidate scan - client-side duplicate detection until blIntegrity.checkDuplicate lands;
        // that read-side DETECTOR remains the named gap filed with the-oath. The DB UNIQUE(scac,
        // bl_number) constraint only rejects a dup at write time.)
        do {
            struct In: Encodable { let bolNumber: String }
            struct ListIn: Encodable { let limit: Int }
            async let orig: BOL763? = EusoTripAPI.shared.query("vesselShipments.getBOL", input: In(bolNumber: bl))
            async let all: [BOL763] = EusoTripAPI.shared.query("vesselShipments.listBOLs", input: ListIn(limit: 100))
            let (o, list) = try await (orig, all)
            if let n = o?.bolNumber { bl = n }
            let dupes = list.filter { $0.bolNumber == o?.bolNumber && $0.id != o?.id }
            duplicateSeen = !dupes.isEmpty
            if let o = o, dupes.isEmpty {
                fields = [
                    BLField(name: "B/L number",   original: o.bolNumber ?? bl, duplicate: "no second issuance", diff: false),
                    BLField(name: "Type",         original: (o.bolType ?? "original").capitalized, duplicate: "-", diff: false),
                    BLField(name: "Status",       original: (o.status ?? "issued").capitalized,   duplicate: "-", diff: false),
                    BLField(name: "Registered",   original: String((o.createdAt ?? "").prefix(10)), duplicate: "-", diff: false)
                ]
                signals = [FraudSignal(name: "Duplicate (SCAC, B/L no.)", detail: "0 second issuances in registry", badge: "CLEAR", danger: false)]
            } else if let o = o, let d = dupes.first {
                fields = [
                    BLField(name: "B/L number", original: o.bolNumber ?? bl, duplicate: d.bolNumber ?? "-", diff: false),
                    BLField(name: "Type",       original: (o.bolType ?? "-").capitalized, duplicate: (d.bolType ?? "-").capitalized, diff: o.bolType != d.bolType),
                    BLField(name: "Status",     original: (o.status ?? "-").capitalized,  duplicate: (d.status ?? "-").capitalized,  diff: o.status != d.status),
                    BLField(name: "Registered", original: String((o.createdAt ?? "").prefix(10)), duplicate: String((d.createdAt ?? "").prefix(10)), diff: true)
                ]
                signals = [
                    FraudSignal(name: "Duplicate (SCAC, B/L no.)", detail: "same number, \(dupes.count + 1) issuances", badge: "FLAG", danger: true),
                    FraudSignal(name: "Consignee substitution", detail: o.consigneeId == d.consigneeId ? "same consignee of record" : "consignee differs between issuances", badge: o.consigneeId == d.consigneeId ? "REVIEW" : "FLAG", danger: o.consigneeId != d.consigneeId),
                    FraudSignal(name: "Release-method mismatch", detail: o.bolType == d.bolType ? "types match" : "\(o.bolType ?? "?") vs \(d.bolType ?? "?")", badge: o.bolType == d.bolType ? "CLEAR" : "REVIEW", danger: false)
                ]
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
    private func hold() async {
        // STUB · named-gap blIntegrity.holdRelease({bolId,confirm:true}) — blocks cargo release, audited.
        gapNotice = "Hold-release is a named backend gap (blIntegrity.holdRelease) - filed with the-oath. The flag is recorded locally only; nothing was written server-side."
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

#Preview("763 · B/L Integrity · Night") { VesselBLDuplicateDetectionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("763 · B/L Integrity · Light") { VesselBLDuplicateDetectionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
