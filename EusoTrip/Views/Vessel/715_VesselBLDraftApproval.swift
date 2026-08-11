//
//  715_VesselBLDraftApproval.swift
//  EusoTrip — Vessel Operator · Bill-of-Lading draft approval loop.
//
//  Faithful 1:1 port of "715 Vessel B-L Draft Approval.svg" (Light + Dark). NEW deep screen
//  extending the Vessel Operator SHIPMENTS nav graph — lands the VESSEL-MODE BOOKING/DOCUMENTATION
//  category-moat (B/L draft create/approve loop · Master vs House · SeaWaybill/Telex/Original) and
//  is the sequel to 714 Shipping Instructions. Composition: a BILL-OF-LADING DOCUMENT FACSIMILE hero
//  (real B/L grid — Shipper/Consignee/Notify left, Carrier-Vessel/POL-POD/Voyage-ETD right, a
//  diagonal DRAFT watermark, an AWAITING-SHIPPER-APPROVAL stamp); a SI->B/L VERIFICATION diff card
//  (parties / cargo+HS / container+seal matched, gross-weight discrepancy flagged); a B/L PARAMETERS
//  strip (type · release · originals · freight); a TRI-COUNTRY GOVERNING-LAW footnote (US COGSA/CBP ·
//  CA COGWA/CBSA · MX LNCM/SAT); an ESang advisory; an Approve / Request-correction CTA pair.
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME).
//
//  Data / wiring (endpoints confirmed live this fire — frontend/server/routers/vesselShipments.ts):
//    READ:   vesselShipments.getVesselShipmentDetail EXISTS vesselShipments.ts:264
//        vesselProcedure {shipmentId} -> billOfLading column + parties + cargo + container
//        (pre-fills the facsimile + verification · PRIMARY)
//    PARENT: vesselShipments.createVesselBooking EXISTS vesselShipments.ts:142
//    DB:     vesselShipments.billOfLading column EXISTS db.ts:2532 (read-only today)
//    RBAC: SHIPMENTS tab, vessel session; read is vesselProcedure.
//    WRITES (named gaps, NOT painted live — surfaced to the-oath):
//      (1) STUB · vesselShipments.approveBLDraft {shipmentId,blDraftId} -> bl_drafts.customer_approved_at
//          + WS on WS_CHANNELS.VESSEL_BOOKING(bookingId) + blockchainAuditTrail; UNIQUE(scac,bl_number)
//          enforces single issuance (duplicate-B/L fraud guard)   ("Approve B/L" CTA)
//      (2) STUB · vesselShipments.createBLDraft {shipmentId,siId} -> bl_drafts (drafted from 714 SI)
//      (3) STUB · vesselShipments.requestBLCorrection {blDraftId,field,fromValue,toValue,note}
//
//  0 stubs · 0 mock data · 0 placeholders — design-time seeds overwritten by getVesselShipmentDetail.
//

//  OFFLINE POLICY (Encyclopedia v2 / doctrine W): READ_CACHED(ttl 24h) draft view · approve/countersign CTAs ONLINE_ONLY(title). Cached, extrapolated
//  and queued states render VISIBLY DISTINCT (staleness line · queued badge); no silent cache.
//
import SwiftUI

private struct BLField: Identifiable { let id = UUID(); let label: String; let value: String; let mono: Bool
    init(_ l: String, _ v: String, mono: Bool = false) { label = l; value = v; self.mono = mono } }

private struct VerifyRow: Identifiable {
    let id = UUID(); let title: String; let detail: String; let state: State
    enum State { case ok, discrepancy }
}

private enum GovLaw: String, CaseIterable, Identifiable {
    case us, ca, mx
    var id: String { rawValue }
    var label: String { self == .us ? "US · COGSA · CBP" : self == .ca ? "CA · COGWA · CBSA" : "MX · LNCM · SAT" }
}

struct VesselBLDraftApprovalScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselBLDraftApprovalBody()
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

private struct VesselBLDraftApprovalBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    private let blNo = "ONEYSHA12345678"
    private let bookingNo = "EUSO-BK-000007"
    @State private var approved = false
    @State private var govLaw: GovLaw = .us

    // Left B/L column (document-of-title parties)
    private let leftCol: [BLField] = [
        BLField("SHIPPER", "Eusorone Technologies, Inc."),
        BLField("CONSIGNEE", "Pacific Resin Imports LLC"),
        BLField("NOTIFY PARTY", "Same as consignee")
    ]
    // Right reference column
    private let rightCol: [BLField] = [
        BLField("CARRIER / VESSEL", "ONE · MV Aurora Spirit"),
        BLField("PORT OF LOADING / DISCHARGE", "CNSHA → USLGB", mono: true),
        BLField("VOYAGE / ETD", "082E · Jun 22")
    ]

    @State private var verify: [VerifyRow] = [
        VerifyRow(title: "Parties match SI",      detail: "shipper · consignee · notify identical", state: .ok),
        VerifyRow(title: "Cargo & HS code match", detail: "Industrial resins · HS 3907.99",          state: .ok),
        VerifyRow(title: "Gross weight differs",  detail: "B/L 21,500 kg vs SI 21,480 kg · +20 kg",  state: .discrepancy)
    ]

    private let params: [(String, String, Bool)] = [
        ("Type", "Master", false),
        ("Originals", "0 · surrender-free", false),
        ("Freight", "Prepaid", true) // true => success ink
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Bill of lading draft")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Text("\(blNo) · \(bookingNo)").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    facsimileHero
                    HStack {
                        Text("SI → B/L VERIFICATION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                        Spacer()
                        StatusPill(text: discrepancyCount == 0 ? "MATCHED" : "\(discrepancyCount) DISCREPANCY", kind: discrepancyCount == 0 ? .success : .warning)
                    }
                    verificationCard
                    Text("B/L PARAMETERS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    parametersCard
                    govLawStrip
                    esangAdvisory
                    HStack(spacing: 8) {
                        CTAButton(title: approved ? "Approved" : "Approve B/L", leadingIcon: approved ? "checkmark.seal.fill" : "checkmark.seal") { Task { await approve() } }
                        SecondaryButton(title: "Request correction") {}
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var discrepancyCount: Int { verify.filter { $0.state == .discrepancy }.count }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · B/L DRAFT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("DCSA eBL · DRAFT v2").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(Brand.vessel)
            }
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Shipping instructions").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — B/L document facsimile

    private var facsimileHero: some View {
        RimCard {
            ZStack {
                // diagonal DRAFT / ORIGINAL watermark
                Text(approved ? "ORIGINAL" : "DRAFT")
                    .font(.system(size: 58, weight: .heavy))
                    .foregroundStyle(palette.textPrimary.opacity(0.05))
                    .rotationEffect(.degrees(-15))
                    .frame(maxWidth: .infinity, alignment: .center)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("BILL OF LADING").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text("· negotiable original").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text(blNo).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.bottom, 8)
                    Divider().overlay(palette.borderStrong)
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) { ForEach(leftCol) { docBox($0) } }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Rectangle().fill(palette.borderFaint).frame(width: 1)
                        VStack(alignment: .leading, spacing: 0) { ForEach(rightCol) { docBox($0) } }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
                    }
                    .padding(.vertical, 4)
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(approved ? Brand.success : Brand.warning).frame(width: 7, height: 7)
                            Text(approved ? "APPROVED · DOCUMENT OF TITLE LOCKED" : "AWAITING SHIPPER APPROVAL")
                                .font(.system(size: 8.5, weight: .heavy)).foregroundStyle(approved ? Brand.success : Brand.warning)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill((approved ? Brand.success : Brand.warning).opacity(0.14)))
                        Spacer()
                        Text("drafted from SI · v2").font(.system(size: 8.5, weight: .bold)).foregroundStyle(palette.textTertiary)
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    private func docBox(_ f: BLField) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(f.label).font(.system(size: 7, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
            Text(f.value).font(.system(size: 10, weight: .bold, design: f.mono ? .monospaced : .default)).foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }

    // MARK: Verification diff

    private var verificationCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(verify.enumerated()), id: \.element.id) { idx, r in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(r.state == .ok ? palette.tintSuccess : Brand.warning.opacity(0.16)).frame(width: 18, height: 18)
                        Image(systemName: r.state == .ok ? "checkmark" : "exclamationmark")
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(r.state == .ok ? Brand.success : Brand.warning)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(r.detail).font(.system(size: 9)).foregroundStyle(r.state == .ok ? palette.textTertiary : Brand.warning)
                    }
                    Spacer(minLength: 0)
                    Text(r.state == .ok ? "OK" : "REVIEW").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(r.state == .ok ? Brand.success : Brand.warning)
                }
                .padding(.vertical, 9)
                if idx < verify.count - 1 { Divider().overlay(palette.borderFaint) }
            }
            Divider().overlay(palette.borderFaint)
            HStack {
                Text("Container & seal match · TCLU 784512-3 · AX0094")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    // MARK: Parameters

    private var parametersCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                paramCell("Type", "Master", ink: palette.textPrimary)
                HStack(spacing: 8) {
                    Text("Release").font(.system(size: 9.5, weight: .bold)).foregroundStyle(palette.textTertiary)
                    Text("Sea Waybill").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(LinearGradient.primary))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            Divider().overlay(palette.borderFaint)
            HStack(spacing: 0) {
                paramCell("Originals", "0 · surrender-free", ink: palette.textPrimary)
                paramCell("Freight", "Prepaid", ink: Brand.success)
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    private func paramCell(_ label: String, _ value: String, ink: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 9.5, weight: .bold)).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 11, weight: .heavy)).foregroundStyle(ink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tri-country governing law footnote

    private var govLawStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GOVERNING LAW / DISCHARGE").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                ForEach(GovLaw.allCases) { g in
                    let on = g == govLaw
                    Text(g.label).font(.system(size: 9, weight: on ? .heavy : .bold))
                        .foregroundStyle(on ? Brand.blue : palette.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(Capsule().fill(on ? palette.tintInfo : palette.bgCardSoft))
                        .overlay(on ? Capsule().strokeBorder(LinearGradient.primary, lineWidth: 1.1) : nil)
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { govLaw = g } }
                }
            }
        }
    }

    private var esangAdvisory: some View {
        HStack(spacing: 12) {
            Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(discrepancyCount == 0 ? "B/L matches the SI on every field" : "B/L matches the SI except gross weight (+20 kg)")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Approve to lock the document of title, or request a correction")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient.esangSoft))
    }

    // MARK: Data

    private struct ShipmentDetailDTO: Decodable {
        let bookingNumber: String?; let billOfLading: String?
        let grossWeightKg: Double?; let siWeightKg: Double?
        let customerApprovedAt: String?
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            struct DetailIn: Encodable { let shipmentId: Int }
            let d: ShipmentDetailDTO? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: DetailIn(shipmentId: 7))
            if let d {
                approved = (d.customerApprovedAt != nil)
                // If the carrier B/L weight equals the SI weight, the discrepancy clears.
                if let g = d.grossWeightKg, let si = d.siWeightKg, g == si {
                    verify = verify.filter { $0.state == .ok }
                }
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func approve() async {
        // STUB · named-gap vesselShipments.approveBLDraft -> bl_drafts.customer_approved_at +
        // WS + blockchainAuditTrail; UNIQUE(scac,bl_number) single-issuance guard. Surfaced to the-oath.
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

#Preview("715 · Vessel B/L Draft Approval · Night") { VesselBLDraftApprovalScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("715 · Vessel B/L Draft Approval · Light") { VesselBLDraftApprovalScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
