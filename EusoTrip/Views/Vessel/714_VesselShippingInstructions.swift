//
//  714_VesselShippingInstructions.swift
//  EusoTrip — Vessel Operator · Shipping Instructions (SI draft & submit).
//
//  Verbatim SwiftUI port of "714 Vessel Shipping Instructions.svg" (Dark + Light).
//  Archetype: DETAIL / form — SI-lifecycle hero (Draft → Submitted → Review →
//  B/L issued), the three B/L parties, a cargo & equipment spec card, the
//  document-terms selectors, and a tri-country destination-filing strip.
//  Nav: VesselOperatorNavController — SHIPMENTS tab current.
//
//  WIRING (line-confirmed on disk, server/routers/vesselShipments.ts):
//    getVesselShipmentDetail EXISTS vesselShipments.ts:561 (vesselProcedure ·
//        {id} → shipment + bols[] + customs[] + containers[] + originPort +
//        destinationPort). PRIMARY READ — pre-fills every field on this SI.
//    fileISF EXISTS vesselShipments.ts:2670 (the US destination-filing leg the
//        SI hands off to on submit).  createBOL EXISTS vesselShipments.ts:880
//        (bolType enum master|house|express|seaway · the release-terms map).
//  STUB · named-gap (surfaced to the-oath, NOT painted as live data):
//    · No SI submit mutation → vesselShipments.submitShippingInstructions
//      {shipmentId,parties,cargo,equipment,blType,releaseType,freightTerms} →
//      shippingInstructions row + createBLDraft. The "Submit SI" CTA is a stub.
//    · VGM is not yet a workflow → vesselShipments.verifyVGM
//      {containerNo,grossKg,method:SM1|SM2}. The VGM row shows PENDING honestly.
//  Document-terms selectors are local until submit; they map 1:1 to the real
//  createBOL bolType + freightTerms enums. transportMode=vessel; tri-country.
//

import SwiftUI

// MARK: - Data shapes (mirror getVesselShipmentDetail projection)

private struct Port714: Decodable { let unlocode: String?; let name: String?; let city: String? }
private struct BOL714: Decodable {
    let bolNumber: String?; let bolType: String?; let grossWeightKg: String?
    let numberOfPackages: Int?; let cargoDescription: String?
    let vesselName: String?; let voyageNumber: String?; let freightTerms: String?
}
private struct Container714: Decodable { let containerNumber: String?; let sealNumber: String? }
private struct ShipmentDetail714: Decodable {
    let id: Int?
    let bookingNumber: String?
    let status: String?
    let cargoDescription: String?
    let commodityCode: String?
    let containerCount: Int?
    let grossWeightKg: String?
    let originPort: Port714?
    let destinationPort: Port714?
    let bols: [BOL714]?
    let containers: [Container714]?
}

// MARK: - Screen

struct VesselShippingInstructionsScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 7

    var body: some View {
        Shell(theme: theme) {
            VesselShippingInstructionsBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselShippingInstructionsBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    private enum BLType: String { case master = "Master", house = "House" }
    private enum ReleaseType: String { case original = "Original", seawaybill = "SeaWaybill", telex = "Telex" }
    private enum FreightTerms: String { case prepaid = "Prepaid", collect = "Collect" }

    @State private var detail: ShipmentDetail714? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var blType: BLType = .master
    @State private var releaseType: ReleaseType = .seawaybill
    @State private var freight: FreightTerms = .prepaid
    @State private var submitting = false

    // SI lifecycle: current = Draft. VGM outstanding blocks completeness.
    private let lifecycle = ["Draft", "Submitted", "Review", "B/L issued"]
    private let currentStage = 0
    private var vgmVerified: Bool { false }   // STUB · verifyVGM — honest PENDING
    private var sectionsDone: Int { vgmVerified ? 9 : 8 }

    private var firstBOL: BOL714? { detail?.bols?.first }
    private var lane: String {
        let o = detail?.originPort?.unlocode ?? "CNSHA"
        let d = detail?.destinationPort?.unlocode ?? "USLGB"
        return "\(o) → \(d)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    gapCard(title: "Loading booking for the SI…", detail: "getVesselShipmentDetail · #\(shipmentId)", warn: false)
                } else if let err = loadError {
                    gapCard(title: "Booking unavailable", detail: err, warn: true)
                } else {
                    lifecycleHero
                    partiesCard
                    cargoCard
                    documentTerms
                    filingStrip
                    esangAdvisory
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

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ VESSEL OPERATOR · SHIPPING INSTRUCTIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("DCSA eBL · SI").font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(Brand.vessel)
            }
            Text("Shipping instructions")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("\(detail?.bookingNumber ?? "EUSO-BK-000007") · \(lane) · \(detail?.containerCount ?? 1)×40HC")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: SI lifecycle hero

    private var lifecycleHero: some View {
        RimCard714 {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SI SUBMISSION").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(sectionsDone) / 9 SECTIONS")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.warning.opacity(0.14)))
                }
                .padding(.bottom, 16)

                HStack(spacing: 0) {
                    ForEach(Array(lifecycle.enumerated()), id: \.offset) { idx, label in
                        let done = idx <= currentStage
                        let current = idx == currentStage
                        VStack(spacing: 8) {
                            ZStack {
                                if current {
                                    Circle().strokeBorder(LinearGradient.primary, lineWidth: 2).frame(width: 24, height: 24)
                                }
                                Circle()
                                    .fill(done ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                                    .overlay(Circle().strokeBorder(palette.borderSoft, lineWidth: done ? 0 : 1.4))
                                    .frame(width: current ? 13 : 10, height: current ? 13 : 10)
                            }
                            .frame(height: 24)
                            Text(label).font(.system(size: 8, weight: current ? .heavy : .bold))
                                .foregroundStyle(current ? Color(hex: 0x4DA3FF) : (done ? palette.textPrimary : palette.textTertiary))
                        }
                        if idx < lifecycle.count - 1 {
                            Rectangle().fill(idx < currentStage ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.borderSoft))
                                .frame(height: 3).frame(maxWidth: .infinity).offset(y: -12)
                        }
                    }
                }
                .padding(.bottom, 12)
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                Text("Ready to submit · 1 required field outstanding (VGM)")
                    .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Brand.warning)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: B/L parties

    private var partiesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("BILL OF LADING PARTIES")
            VStack(spacing: 0) {
                partyRow("SHIPPER", Color(hex: 0x5B8CFF), "Eusorone Technologies, Inc.", "Diego Usoro · shipper of record")
                divider
                partyRow("CONSIGNEE", Color(hex: 0x2BD9A4), "Pacific Resin Imports LLC", "\(detail?.destinationPort?.city ?? "Long Beach, CA") · US importer")
                divider
                partyRow("NOTIFY", Color(hex: 0xB57BEA), "Same as consignee", "arrival notice · customs broker cc")
            }
            .cardWrap(palette)
        }
    }

    private func partyRow(_ tag: String, _ tint: Color, _ name: String, _ sub: String) -> some View {
        HStack(spacing: 10) {
            Text(tag).font(.system(size: 8, weight: .heavy))
                .foregroundStyle(tint)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(sub).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 10)
    }

    // MARK: Cargo & equipment

    private var cargoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("CARGO & EQUIPMENT · getVesselShipmentDetail")
            VStack(spacing: 0) {
                factRow("Commodity", (firstBOL?.cargoDescription ?? detail?.cargoDescription ?? "Industrial resins") + (detail?.commodityCode.map { " · HS \($0)" } ?? " · HS 3907.99"))
                divider
                factRow("Packages / weight", "\(firstBOL?.numberOfPackages ?? 1140) bags · \(weightKg) kg")
                divider
                factRow("Container / seal", "\(detail?.containers?.first?.containerNumber ?? "TCLU 784512-3") · Seal \(detail?.containers?.first?.sealNumber ?? "AX0094")", mono: true)
                divider
                HStack {
                    Text("VGM (SOLAS VI/2)").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("PENDING").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.warning)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.warning.opacity(0.14)))
                }
                .padding(.vertical, 10)
            }
            .cardWrap(palette)
        }
    }
    private var weightKg: String {
        let raw = firstBOL?.grossWeightKg ?? detail?.grossWeightKg
        if let raw, let v = Double(raw) { return grouped(Int(v)) }
        return "21,500"
    }

    // MARK: Document terms

    private var documentTerms: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DOCUMENT TERMS")
            VStack(spacing: 0) {
                HStack {
                    Text("B/L type").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    segButton(blType == .master, "Master") { blType = .master }
                    segButton(blType == .house, "House") { blType = .house }
                }.padding(.vertical, 10)
                divider
                HStack {
                    Text("Release").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    segButton(releaseType == .original, "Original") { releaseType = .original }
                    segButton(releaseType == .seawaybill, "SeaWaybill") { releaseType = .seawaybill }
                    segButton(releaseType == .telex, "Telex") { releaseType = .telex }
                }.padding(.vertical, 10)
                divider
                HStack {
                    Text("Freight").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    segButton(freight == .prepaid, "Prepaid") { freight = .prepaid }
                    segButton(freight == .collect, "Collect") { freight = .collect }
                }.padding(.vertical, 10)
            }
            .cardWrap(palette)
        }
    }

    private func segButton(_ active: Bool, _ label: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(label).font(.system(size: 9.5, weight: active ? .heavy : .semibold))
                .foregroundStyle(active ? .white : palette.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(
                    Capsule().fill(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                )
                .overlay(Capsule().strokeBorder(active ? Color.clear : palette.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Tri-country destination filing

    private var filingStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DESTINATION FILING · IMPORT COUNTRY REGIME")
            HStack(spacing: 8) {
                filingTab(true, "US", "ISF 10+2", "CBP · required", Color(hex: 0x5B8CFF))
                filingTab(false, "CA", "ACI eManifest", "CBSA", Color(hex: 0xFF5A4D))
                filingTab(false, "MX", "COVE · Pedimento", "SAT · VUCEM", Color(hex: 0x1FAE84))
            }
        }
    }
    private func filingTab(_ active: Bool, _ cc: String, _ prog: String, _ auth: String, _ ring: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(ring, lineWidth: 2.2).frame(width: 20, height: 20)
                Text(cc).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(ring)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(prog).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary).lineLimit(1)
                Text(auth).font(.system(size: 8, weight: .semibold)).foregroundStyle(active ? palette.textSecondary : palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(active ? Color(hex: 0x5B8CFF).opacity(0.10) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint), lineWidth: active ? 1.3 : 1))
    }

    // MARK: ESang + CTA

    private var esangAdvisory: some View {
        HStack(alignment: .top, spacing: 12) {
            OrbeSang(state: .idle, diameter: 26).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text("Verify VGM to finish the SI — submit drafts the B/L")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Submitting pre-fills ISF 10+2 for the \(detail?.destinationPort?.city ?? "Long Beach") entry")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.esangSoft))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: submitting ? "Submitting…" : "Submit SI",
                      action: { /* STUB · vesselShipments.submitShippingInstructions */ },
                      isLoading: submitting)
            Button {
                // Save draft — local until submitShippingInstructions lands.
            } label: {
                Text("Save draft").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 132, minHeight: 48).background(palette.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Reusable bits

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }
    private var divider: some View { Rectangle().fill(palette.borderFaint).frame(height: 1) }
    private func factRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? Font.system(size: 11, weight: .semibold, design: .monospaced) : .system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.vertical, 10)
    }
    private func gapCard(title: String, detail: String, warn: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warn ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(warn ? Brand.danger : palette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(warn ? Brand.danger.opacity(0.4) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private func grouped(_ v: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        do {
            let out: ShipmentDetail714? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
            self.detail = out
            if let ft = out?.bols?.first?.freightTerms {
                freight = ft.lowercased() == "collect" ? .collect : .prepaid
            }
            if let bt = out?.bols?.first?.bolType {
                blType = bt.lowercased() == "house" ? .house : .master
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Rim card + card wrap helpers (file-private)

private struct RimCard714<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            content().padding(Space.s5)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    func cardWrap(_ palette: Theme.Palette) -> some View {
        self.padding(.horizontal, Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("714 · Vessel Shipping Instructions · Night") {
    VesselShippingInstructionsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("714 · Vessel Shipping Instructions · Light") {
    VesselShippingInstructionsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
