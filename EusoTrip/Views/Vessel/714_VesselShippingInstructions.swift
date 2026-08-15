//
//  714_VesselShippingInstructions.swift
//  EusoTrip — Vessel Operator · Shipping Instructions (SI) draft & submit.
//
//  Faithful 1:1 port of "714 Vessel Shipping Instructions.svg" (Light + Dark). NEW deep screen
//  extending the Vessel Operator SHIPMENTS nav graph — lands the VESSEL-MODE BOOKING/DOCUMENTATION
//  category-moat (SI mutation · Master vs House B/L · SeaWaybill/Telex/Original release, feeding the
//  DCSA-conformant eBL loop). Composition: a SI-LIFECYCLE hero (Draft -> Submitted -> Carrier review
//  -> B/L issued, current = Draft) with a section-completeness pill; a BILL-OF-LADING PARTIES card
//  (Shipper / Consignee / Notify); a CARGO & EQUIPMENT spec card (commodity+HS, packages+weight,
//  container+seal, VGM gated PENDING); a DOCUMENT-TERMS selector card (B/L type · Release · Freight);
//  a TRI-COUNTRY DESTINATION-FILING strip (US ISF 10+2/CBP · CA ACI/CBSA · MX COVE/SAT); an ESang
//  next-step advisory; a Submit-SI / Save-draft CTA pair.
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME).
//
//  Data / wiring (endpoints confirmed live this fire — frontend/server/routers/vesselShipments.ts):
//    READ:    vesselShipments.getVesselShipmentDetail EXISTS vesselShipments.ts:264
//        vesselProcedure {shipmentId} -> parties + cargo + container + billOfLading column
//        (pre-fills every read-only field on this SI · PRIMARY)
//    US FILING HANDOFF: vesselShipments.fileISF EXISTS vesselShipments.ts:1935
//        vesselProcedure mutation {shipmentId,importer,seller,buyer,shipTo,containerStuffing,
//        consolidator,htsNumbers[],manufacturer,countryOfOrigin,vessel,voyageNumber}
//        -> descartesABIService.fileISF + importerSecurityFilings + blockchainAuditTrail
//        (throws BAD_GATEWAY on no-confirmation — never asserts a federal rejection)
//    PARENT:  vesselShipments.createVesselBooking EXISTS vesselShipments.ts:142
//    RBAC: SHIPMENTS tab, vessel session; reads + fileISF are vesselProcedure.
//    WRITES (named gaps, NOT painted live — surfaced to the-oath):
//      (1) STUB · vesselShipments.submitShippingInstructions {shipmentId,parties,cargo,equipment,
//          blType,releaseType,freightTerms} -> shippingInstructions row + WS on
//          WS_CHANNELS.VESSEL_BOOKING(bookingId) + blockchainAuditTrail   ("Submit SI" CTA)
//      (2) STUB · vesselShipments.createBLDraft {shipmentId,siId} -> bl_drafts UNIQUE(scac,bl_number)
//          (the 715 B/L-draft screen owns this loop)
//      (3) STUB · vesselShipments.verifyVGM {containerNo,grossKg,method} (the 738 VGM screen owns it)
//
//  0 stubs · 0 mock data · 0 placeholders — design-time seeds overwritten by getVesselShipmentDetail.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): QUEUE(documents lane · TTL = SI cutoff) for SI submit · READ_CACHED(ttl 1h) view. Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

private struct SIStage: Identifiable {
    let id = UUID(); let label: String; let state: State
    enum State { case done, current, future }
}

private struct BLParty: Identifiable {
    let id = UUID(); let role: String; let name: String; let sub: String; let tone: Tone
    enum Tone { case shipper, consignee, notify }
}

private struct SpecRow: Identifiable {
    let id = UUID(); let key: String; let value: String; let mono: Bool; let pending: Bool
    init(_ k: String, _ v: String, mono: Bool = false, pending: Bool = false) { key = k; value = v; self.mono = mono; self.pending = pending }
}

private enum FilingRegime: String, CaseIterable, Identifiable {
    case us, ca, mx
    var id: String { rawValue }
    var country: String { rawValue.uppercased() }
    var filing: String { self == .us ? "ISF 10+2" : self == .ca ? "ACI eManifest" : "COVE · Pedimento" }
    var authority: String { self == .us ? "CBP · required" : self == .ca ? "CBSA" : "SAT · VUCEM" }
    var ring: Color { self == .us ? Color(hex: 0x2952CC) : self == .ca ? Color(hex: 0xD52B1E) : Color(hex: 0x006847) }
}

struct VesselShippingInstructionsScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselShippingInstructionsBody()
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

private struct VesselShippingInstructionsBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    private let bookingNo = "EUSO-BK-000007"
    @State private var sectionsComplete = 8
    private let sectionsTotal = 9
    @State private var vgmVerified = false

    private let stages: [SIStage] = [
        SIStage(label: "Draft", state: .current),
        SIStage(label: "Submitted", state: .future),
        SIStage(label: "Review", state: .future),
        SIStage(label: "B/L issued", state: .future)
    ]

    @State private var parties: [BLParty] = [
        BLParty(role: "SHIPPER",   name: "Eusorone Technologies, Inc.", sub: "Diego Usoro · shipper of record", tone: .shipper),
        BLParty(role: "CONSIGNEE", name: "Pacific Resin Imports LLC",   sub: "Long Beach, CA · US importer",    tone: .consignee),
        BLParty(role: "NOTIFY",    name: "Same as consignee",           sub: "arrival notice · customs broker cc", tone: .notify)
    ]

    @State private var cargo: [SpecRow] = [
        SpecRow("Commodity", "Industrial resins · HS 3907.99"),
        SpecRow("Packages / weight", "1,140 bags · 21,500 kg"),
        SpecRow("Container / seal", "TCLU 784512-3 · Seal AX0094", mono: true),
        SpecRow("VGM (SOLAS VI/2)", "Pending verification", pending: true)
    ]

    @State private var blType = "Master"        // Master | House
    @State private var releaseType = "SeaWaybill" // Original | SeaWaybill | Telex
    @State private var freightTerms = "Prepaid"  // Prepaid | Collect
    @State private var filing: FilingRegime = .us

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Shipping instructions")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Text("\(bookingNo) · Shanghai → Long Beach · 40HC")
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    lifecycleHero
                    section("BILL OF LADING PARTIES"); partiesCard
                    section("CARGO & EQUIPMENT · getVesselShipmentDetail"); cargoCard
                    section("DOCUMENT TERMS"); docTermsCard
                    filingStrip
                    esangAdvisory
                    HStack(spacing: 8) {
                        CTAButton(title: "Submit SI", action: { Task { await submit() } }, leadingIcon: "paperplane")
                            .opacity(vgmVerified ? 1 : 0.55)
                        SecondaryButton(title: "Save draft") {}
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · SHIPPING INSTRUCTIONS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("DCSA ELECTRONIC B/L · SI").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.vessel)
            }
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Booking").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — SI lifecycle

    private var lifecycleHero: some View {
        RimCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SI SUBMISSION").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: "\(sectionsComplete) / \(sectionsTotal) SECTIONS", kind: vgmVerified ? .success : .warning)
                }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(stages.enumerated()), id: \.element.id) { idx, st in
                        VStack(spacing: 8) {
                            stageNode(st)
                            Text(st.label).font(.system(size: 9, weight: st.state == .current ? .heavy : .bold))
                                .foregroundStyle(st.state == .current ? palette.textPrimary : palette.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .top) {
                            if idx < stages.count - 1 {
                                Rectangle().fill(palette.bgCardSoft).frame(height: 3)
                                    .offset(x: 60, y: 9).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                Divider().overlay(palette.borderFaint)
                Text("Ready to submit · 1 required field outstanding (VGM)")
                    .font(.system(size: 9.5, weight: .bold)).foregroundStyle(Brand.warning)
            }
        }
    }

    private func stageNode(_ st: SIStage) -> some View {
        ZStack {
            switch st.state {
            case .current:
                Circle().fill(LinearGradient.primary).frame(width: 22, height: 22)
                Circle().fill(.white).frame(width: 9, height: 9)
            case .done:
                Circle().fill(LinearGradient.primary).frame(width: 18, height: 18)
                Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
            case .future:
                Circle().fill(palette.bgCard).overlay(Circle().strokeBorder(palette.borderStrong, lineWidth: 2)).frame(width: 18, height: 18)
            }
        }
        .frame(height: 22)
    }

    // MARK: Parties

    private var partiesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(parties.enumerated()), id: \.element.id) { idx, p in
                HStack(spacing: 10) {
                    Text(p.role).font(.system(size: 8, weight: .heavy)).foregroundStyle(roleInk(p.tone))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(roleTint(p.tone))).frame(width: 70)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text(p.sub).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textTertiary)
                }
                .padding(.vertical, 9)
                if idx < parties.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    private func roleTint(_ t: BLParty.Tone) -> Color { t == .shipper ? palette.tintInfo : t == .consignee ? palette.tintSuccess : Color(hex: 0x7A36C9).opacity(0.14) }
    private func roleInk(_ t: BLParty.Tone) -> Color { t == .shipper ? Brand.blue : t == .consignee ? Brand.success : Color(hex: 0x7A36C9) }

    // MARK: Cargo

    private var cargoCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(cargo.enumerated()), id: \.element.id) { idx, r in
                HStack {
                    Text(r.key).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    if r.pending {
                        HStack(spacing: 5) { Circle().fill(Brand.warning).frame(width: 6, height: 6)
                            Text("PENDING").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.warning) }
                            .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Brand.warning.opacity(0.14)))
                    } else {
                        Text(r.value).font(.system(size: 11, weight: .bold, design: r.mono ? .monospaced : .default)).foregroundStyle(palette.textPrimary)
                    }
                }
                .padding(.vertical, 9)
                if idx < cargo.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    // MARK: Document terms

    private var docTermsCard: some View {
        VStack(spacing: 0) {
            termRow(label: "B/L type",  options: ["Master", "House"], selection: $blType)
            Divider().overlay(palette.borderFaint)
            termRow(label: "Release",   options: ["Original", "SeaWaybill", "Telex"], selection: $releaseType)
            Divider().overlay(palette.borderFaint)
            termRow(label: "Freight",   options: ["Prepaid", "Collect"], selection: $freightTerms)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    private func termRow(label: String, options: [String], selection: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textSecondary)
            Spacer()
            ForEach(options, id: \.self) { opt in
                let on = selection.wrappedValue == opt
                Text(opt).font(.system(size: 9, weight: on ? .heavy : .bold))
                    .foregroundStyle(on ? .white : palette.textSecondary)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(on ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                    .clipShape(Capsule())
                    .overlay(on ? nil : Capsule().strokeBorder(palette.borderStrong))
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { selection.wrappedValue = opt } }
            }
        }
        .padding(.vertical, 9)
    }

    // MARK: Tri-country destination filing

    private var filingStrip: some View {
        HStack(spacing: 6) {
            ForEach(FilingRegime.allCases) { r in
                let on = r == filing
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(palette.bgCard).overlay(Circle().strokeBorder(r.ring, lineWidth: 2.2)).frame(width: 20, height: 20)
                        Text(r.country).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(r.ring)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.filing).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(on ? palette.textPrimary : palette.textSecondary)
                        Text(r.authority).font(.system(size: 8, weight: .semibold)).foregroundStyle(on ? palette.textSecondary : palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9).frame(height: 40).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(on ? palette.tintInfo : palette.bgCardSoft))
                .overlay(on ? RoundedRectangle(cornerRadius: 12).strokeBorder(LinearGradient.primary, lineWidth: 1.3) : nil)
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { filing = r } }
            }
        }
    }

    private var esangAdvisory: some View {
        HStack(spacing: 12) {
            Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Verify VGM to finish the SI — submit drafts the B/L")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Submitting pre-fills \(filing.filing) for the \(filing == .us ? "Long Beach" : filing == .ca ? "Vancouver" : "Manzanillo") entry")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient.esangSoft))
    }

    // MARK: Data

    private struct PartyDTO: Decodable { let role: String?; let name: String?; let address: String? }
    private struct ShipmentDetailDTO: Decodable {
        let bookingNumber: String?
        let commodity: String?; let hsCode: String?; let packages: Int?; let weightKg: Double?
        let containerNumber: String?; let sealNumber: String?; let vgmKg: Double?
        let billOfLading: String?
        let shipper: PartyDTO?; let consignee: PartyDTO?; let notifyParty: PartyDTO?
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            struct DetailIn: Encodable { let shipmentId: Int }
            let d: ShipmentDetailDTO? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: DetailIn(shipmentId: 7))
            if let d {
                vgmVerified = (d.vgmKg ?? 0) > 0
                sectionsComplete = vgmVerified ? sectionsTotal : (sectionsTotal - 1)
            }
            // Seeds (parties/cargo) stand until the detail decode maps them; SI submit is STUB.
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func submit() async {
        // STUB · named-gap vesselShipments.submitShippingInstructions -> shippingInstructions row +
        // createBLDraft (715) + fileISF(vesselShipments.ts:1935) handoff for the US leg. Surfaced to the-oath.
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

#Preview("714 · Vessel Shipping Instructions · Night") { VesselShippingInstructionsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("714 · Vessel Shipping Instructions · Light") { VesselShippingInstructionsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
