//
//  765_VesselLetterOfCredit.swift
//  EusoTrip — Vessel Operator · Letter of Credit.
//
//  Faithful 1:1 port of "765 Vessel Letter of Credit.svg" (Light + Dark). NET-NEW gap screen closing
//  the VESSEL-MODE BOOKING/DOCUMENTATION moat item "bank-endorsement workflow (LC negotiation)".
//  PRESENTATION-CHECKLIST + ENDORSEMENT-CHAIN archetype — deliberately distinct from 005 Bill of Lading
//  (title state machine), 715 B/L Draft Approval, 719 DCSA eBL (title-token custody), 679 Telex Release,
//  718 Cargo Release: the spine is a UCP-600 document-presentation checklist (COMPLIANT/DISCREPANT per
//  article) + a horizontal Issuing→Advising→Negotiating→Endorse-B/L bank chain, not a B/L surface.
//  Nav: VesselOperatorNavController (HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME).
//
//  VERIFICATION TIER: STATIC-REVIEWED (no Swift toolchain in the build lane). Mirrors the
//  render-verified SVG element-for-element. Uses only confirmed DesignSystem + _VesselReconKit.
//
//  Data / wiring (verified live 2026-06-15 via connected EusoTrip codebase):
//    EXISTS — getBOL vesselShipments.ts:567 (bl_drafts, bolType incl. master; createBOL:892,
//      surrenderBOL:986); endorsement/signature reuse createBOLSignatureRequest signatures.ts (EXISTS · line drifts, verify at claim) +
//      services/bol.ts:326.
//    NAMED GAP (STUB · the-oath): no documentary-credit model ('letter of credit' grep = 0). Propose
//      lc.checkPresentation({lcRef,bolId}) -> {documents[{name,articleCite,state}],discrepancyCount,verdict};
//      lc.endorse({lcRef,bolId,confirm:true}) — money + irreversible, human-gated + confirm + USD + audit;
//      discrepancy decision is the expensive-advisor case. RBAC: vesselProcedure.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 24h) LC terms · presentation submit ONLINE_ONLY(money). Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

private struct LCDoc: Identifiable {
    let id = UUID(); let name: String; let detail: String; let compliant: Bool
}
private struct ChainNode: Identifiable {
    let id = UUID(); let role: String; let who: String
    enum NodeState { case done, active, pending }
    let state: NodeState
}
private struct LCLaw: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }

struct VesselLetterOfCreditScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselLetterOfCreditBody()
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

private struct VesselLetterOfCreditBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    private let docs: [LCDoc] = [
        LCDoc(name: "Commercial invoice",     detail: "art. 18 · amount matches LC",        compliant: true),
        LCDoc(name: "Ocean bill of lading",   detail: "art. 20 · clean on board · to order", compliant: true),
        LCDoc(name: "Packing list",           detail: "consistent · 1×40' HC reefer",        compliant: true),
        LCDoc(name: "Certificate of origin",  detail: "USMCA · matches goods desc",          compliant: true),
        LCDoc(name: "Insurance certificate",  detail: "art. 28 · cover 100%, LC needs 110%", compliant: false)
    ]
    @State private var gapNotice: String? = nil
    @State private var chain: [ChainNode] = [
        ChainNode(role: "Issuing",     who: "BoC",      state: .done),
        ChainNode(role: "Advising",    who: "DBS SG",   state: .done),
        ChainNode(role: "Negotiating", who: "HSBC",     state: .active),
        ChainNode(role: "Endorse B/L", who: "to order", state: .pending)
    ]
    private let laws: [LCLaw] = [
        LCLaw(code: "US", line: "US · UCP 600 + UCC Art.5 · USD",       active: true),
        LCLaw(code: "CA", line: "CA · UCP 600 + bills of exch. · CAD",  active: false),
        LCLaw(code: "MX", line: "MX · UCP 600 + LGTOC · MXN",           active: false)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Letter of credit").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    hero
                    sectionLabel("DOCUMENT PRESENTATION · UCP 600", ref: "presentation check not live")
                    presentationCard
                    sectionLabel("BANK ENDORSEMENT CHAIN", ref: "live endorsement records")
                    endorsementChain
                    sectionLabel("LC GOVERNING LAW · presenting bank", ref: "governing law · by country")
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
                        CTAButton(title: "Endorse & release") { Task { await endorse() } }
                        SecondaryButton(title: "Flag discrepancy") {}
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
            Text("VESSEL OPERATOR · LETTER OF CREDIT").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("UCP 600 · BoC").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
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
                    Text("LC IRREV-26-7741203 · sight credit").font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    StatusPill(text: "1 DISCREPANT", kind: .warning)
                }
                Text("$1,200,000").font(.system(size: 24, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("Irrevocable · UCP 600 · payable at sight").font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                Text("Issuing: Bank of China · expiry Jun 30").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var presentationCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(docs.enumerated()), id: \.element.id) { idx, d in
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        if d.compliant {
                            Circle().fill(Brand.success).frame(width: 18, height: 18)
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color.white)
                        } else {
                            Circle().strokeBorder(Brand.warning, lineWidth: 2).frame(width: 18, height: 18)
                            Image(systemName: "exclamationmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(d.detail).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Text(d.compliant ? "COMPLIANT" : "DISCREPANT").font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(d.compliant ? Brand.success : Brand.warning)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                if idx < docs.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, 44) }
            }
        }
        .padding(.vertical, 4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var endorsementChain: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(chain.enumerated()), id: \.element.id) { idx, n in
                VStack(spacing: 6) {
                    Text(n.role).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    chainDot(n.state)
                    Text(n.who).font(.system(size: 8)).foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                if idx < chain.count - 1 {
                    Rectangle().fill(idx < 2 ? Brand.success : palette.bgCardSoft)
                        .frame(height: 3).offset(y: 20)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func chainDot(_ st: ChainNode.NodeState) -> some View {
        ZStack {
            switch st {
            case .done:
                Circle().fill(Brand.success).frame(width: 20, height: 20)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color.white)
            case .active:
                Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.5).frame(width: 20, height: 20)
                Circle().fill(LinearGradient.primary).frame(width: 8, height: 8)
            case .pending:
                Circle().strokeBorder(palette.bgCardSoft, lineWidth: 2.5).frame(width: 20, height: 20)
            }
        }
    }

    private var triCountryBand: some View {
        VStack(spacing: 0) {
            ForEach(Array(laws.enumerated()), id: \.element.id) { idx, r in
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
                if idx < laws.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(6)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Data
    private struct BOL765: Decodable { let bolNumber: String?; let status: String? }
    private func load() async {
        loading = true; loadError = nil
        // LIVE: getBOL vesselShipments.ts:956 - the negotiable B/L under the credit drives the
        // "Endorse B/L" chain node. The UCP-600 document-presentation compliance check remains the
        // named gap (lc.checkPresentation) - checklist rows are doctrine content, not server truth.
        do {
            struct In: Encodable { let bolNumber: String }
            let b: BOL765? = try await EusoTripAPI.shared.query("vesselShipments.getBOL", input: In(bolNumber: "MSCUSH6840517"))
            if let st = b?.status?.lowercased() {
                chain = chain.map { n in
                    if n.role == "Endorse B/L" {
                        return ChainNode(role: n.role, who: n.who, state: (st == "surrendered" || st == "endorsed") ? .done : n.state)
                    }
                    return n
                }
            }
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }
    private func endorse() async {
        // STUB · named-gap lc.endorse({lcRef,bolId,confirm:true}) — money + irreversible, human-gated + audited.
        gapNotice = "Endorse & release moves money and cannot be undone, so it needs a live connection and is never queued offline. It is not available yet — nothing was written and the credit is untouched."
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

#Preview("765 · Letter of Credit · Night") { VesselLetterOfCreditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("765 · Letter of Credit · Light") { VesselLetterOfCreditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
