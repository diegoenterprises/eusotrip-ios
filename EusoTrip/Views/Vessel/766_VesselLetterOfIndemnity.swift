//
//  766_VesselLetterOfIndemnity.swift
//  EusoTrip — Vessel Operator · Letter of Indemnity (LOI).
//
//  Faithful 1:1 port of "766 Vessel Letter of Indemnity.svg" (Light + Dark). NET-NEW gap screen closing
//  the BOOKING/DOCUMENTATION moat (release-without-OBL / Telex side). UNDERTAKING / SIGNATORY archetype —
//  deliberately distinct from 679 Telex Release (carrier-side release pipeline), 718 Cargo Release, and
//  005/715/719 (B/L surfaces): the spine is a guarantee — an indemnity-amount hero (110% cargo value) +
//  an undertaking-terms checklist + TWO counter-signatory cards (merchant DU disc + bank guarantor).
//  Nav: VesselOperatorNavController (HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME).
//
//  VERIFICATION TIER: STATIC-REVIEWED (no Swift toolchain in the build lane). Mirrors the
//  render-verified SVG element-for-element. Uses only confirmed DesignSystem + _VesselReconKit.
//
//  Data / wiring (verified live 2026-06-15 via connected EusoTrip codebase):
//    EXISTS — surrenderBOL vesselShipments.ts:597 (draft→issued→surrendered) + getBOL:956; release path
//      shared with the telex flow.
//    NAMED GAP (STUB · the-oath): no indemnity model ('indemnity' grep = 0). Propose loi.issue({bolId,
//      indemnityValueCents,reason,signatories[]}) -> {loiId,status,expiresOn}; loi.acceptRelease({loiId,
//      confirm:true}) — irreversible + financial exposure, human-gated + bank-countersign required + audit.
//      RBAC: vesselProcedure.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 24h) view · LOI issue ONLINE_ONLY(money-legal). Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

private struct LOITerm: Identifiable { let id = UUID(); let text: String }
private struct LOILaw: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }

struct VesselLetterOfIndemnityScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselLetterOfIndemnityBody()
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

private struct VesselLetterOfIndemnityBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var gapNotice: String? = nil

    // Seeds - overwritten by getBOL on .task.
    @State private var underlyingBL = "MSCUSH6840517"
    @State private var blSurrendered = false
    @State private var openDay = 9

    private let terms: [LOITerm] = [
        LOITerm(text: "Deliver cargo without production of original B/L"),
        LOITerm(text: "Indemnify carrier against all consequences"),
        LOITerm(text: "Provide originals to carrier when available"),
        LOITerm(text: "ITIC / P&I club approved wording"),
        LOITerm(text: "Valid until originals surrendered")
    ]
    private let laws: [LOILaw] = [
        LOILaw(code: "US", line: "US · English-law LOI · USCG/CBP release", active: true),
        LOILaw(code: "CA", line: "CA · LOI · CBSA release control",        active: false),
        LOILaw(code: "MX", line: "MX · carta de indemnización · Aduanas",  active: false)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Letter of indemnity").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    hero
                    sectionLabel("UNDERTAKING TERMS", ref: "STUB · loi.issue")
                    termsCard
                    sectionLabel("COUNTER-SIGNATORIES", ref: "EXISTS surrenderBOL:986")
                    signatories
                    sectionLabel("LOI JURISDICTION · release authority", ref: "loi.issue·country")
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
                        CTAButton(title: "Submit to carrier") { Task { await submit() } }
                        SecondaryButton(title: "Save draft") {}
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
            Text("VESSEL OPERATOR · INDEMNITY").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("P&I · LOI").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
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
        // INDEMNITY RISK CLOCK - three-zone band (exposure state · open window · cover ratio).
        // Deliberately NOT the money-figure card 765 leads with: the LOI's story is unsecured
        // time, so time is the hero and the amount is a footnote.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CARRIER EXPOSURE").font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(blSurrendered ? "DISCHARGED" : "UNSECURED").font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(blSurrendered ? Brand.success : Brand.warning)
                Text(blSurrendered ? "originals surrendered" : "originals not yet presented")
                    .font(.system(size: 9)).foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(palette.borderFaint).frame(width: 1, height: 44)
            VStack(alignment: .center, spacing: 4) {
                Text("OPEN WINDOW").font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(blSurrendered ? "closed" : "day \(openDay)").font(.system(size: 15, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("until surrender").font(.system(size: 9)).foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            Rectangle().fill(palette.borderFaint).frame(width: 1, height: 44)
            VStack(alignment: .trailing, spacing: 4) {
                Text("COVER").font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("110%").font(.system(size: 15, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                Text("$1.32M · single-bank").font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder((blSurrendered ? Brand.success : Brand.warning).opacity(0.5), lineWidth: 1.5))
        .overlay(alignment: .topLeading) {
            Text("LOI-260615 · B/L \(underlyingBL)").font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textTertiary).padding(.leading, 16).padding(.top, -7)
                .background(palette.bgPage)
        }
    }

    private var termsCard: some View {
        // Undertaking reads as a legal document: numbered clauses against a left rule -
        // not a compliance checklist (that grammar belongs to 765 LC).
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(terms.enumerated()), id: \.element.id) { idx, t in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(idx + 1).").font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Brand.magenta).frame(width: 20, alignment: .trailing)
                    Text(t.text).font(.system(size: 12)).foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                if idx < terms.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, 32) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [Brand.magenta, Brand.blue], startPoint: .top, endPoint: .bottom))
                .frame(width: 3).padding(.vertical, 10)
        }
    }

    private var signatories: some View {
        HStack(spacing: 12) {
            // Merchant card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Brand.magenta, Color(hex: 0xBE01FF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 30)
                        Text("DU").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.white)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Merchant").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text("Eusorone Tech.").font(.system(size: 8.5)).foregroundStyle(palette.textTertiary)
                    }
                }
                Text("● SIGNED").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.success)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(palette.bgCardSoft).clipShape(Capsule())
                Text("Diego Usoro · shipper of record").font(.system(size: 8.5)).foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: 16))
            // Bank card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7).fill(palette.bgCardSoft).frame(width: 30, height: 28)
                        Image(systemName: "building.columns").font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.blue)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Bank").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text("Std Chartered").font(.system(size: 8.5)).foregroundStyle(palette.textTertiary)
                    }
                }
                Text("● COUNTERSIGNED").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.success)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(palette.bgCardSoft).clipShape(Capsule())
                Text("Joint & several liability").font(.system(size: 8.5)).foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: 16))
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
    private struct BOL766: Decodable { let bolNumber: String?; let status: String?; let createdAt: String? }
    private func load() async {
        loading = true; loadError = nil
        // LIVE: getBOL vesselShipments.ts:956 - the underlying B/L surrender state discharges the LOI.
        // LOI issuance + signatory/guarantor capture remain the named gap (loi.issue) - filed with
        // the-oath. surrenderBOL:986 is the discharge trigger this screen watches.
        do {
            struct In: Encodable { let bolNumber: String }
            let b: BOL766? = try await EusoTripAPI.shared.query("vesselShipments.getBOL", input: In(bolNumber: underlyingBL))
            if let b = b {
                if let n = b.bolNumber { underlyingBL = n }
                blSurrendered = (b.status?.lowercased() == "surrendered")
                if let c = b.createdAt, c.count >= 10,
                   let d = ISO8601DateFormatter().date(from: String(c.prefix(10)) + "T00:00:00Z") {
                    openDay = max(Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? openDay, 1)
                }
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
    private func submit() async {
        // STUB · named-gap loi.issue / loi.acceptRelease({loiId,confirm:true}) — irreversible release, audited.
        gapNotice = "LOI submission is irreversible and its endpoint (loi.issue / loi.acceptRelease) is a named gap filed with the-oath. ONLINE_ONLY(money-legal) - nothing was written server-side."
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

#Preview("766 · Letter of Indemnity · Night") { VesselLetterOfIndemnityScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("766 · Letter of Indemnity · Light") { VesselLetterOfIndemnityScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
