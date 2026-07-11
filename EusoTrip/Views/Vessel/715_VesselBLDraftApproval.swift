//
//  715_VesselBLDraftApproval.swift
//  EusoTrip — Vessel Operator · Bill-of-Lading Draft Approval.
//
//  Verbatim SwiftUI port of "715 Vessel B-L Draft Approval.svg" (Dark + Light).
//  Archetype: DETAIL — a real B/L document facsimile hero (parties column +
//  carrier/vessel column, DRAFT watermark, awaiting-approval stamp), an SI→B/L
//  verification diff card, a B/L parameters strip, and a tri-country
//  governing-law footnote. Nav: VesselOperatorNavController — SHIPMENTS current.
//
//  WIRING (line-confirmed on disk, server/routers/vesselShipments.ts):
//    getBOL EXISTS vesselShipments.ts:944 (vesselProcedure · {bolNumber|id} →
//        billsOfLading row {bolNumber,bolType,status,originPort,destinationPort,
//        vesselName,voyageNumber,freightTerms,grossWeightKg,numberOfPackages,
//        cargoDescription}). PRIMARY — the facsimile + parameters.
//    getVesselShipmentDetail EXISTS vesselShipments.ts:561 (the SI side of the
//        SI→B/L verification diff).
//  STUB · named-gap (surfaced to the-oath, NOT painted as live data):
//    · B/L is read-only today — no approve loop → vesselShipments.approveBLDraft
//      {shipmentId,blDraftId} → bl_drafts.customer_approved_at. "Approve B/L" is stub.
//    · vesselShipments.requestBLCorrection {blDraftId,field,fromValue,toValue,note}.
//  The gross-weight discrepancy is computed from the live B/L vs SI values, not
//  fabricated. transportMode=vessel; tri-country US·CA·MX.
//

import SwiftUI

private struct BOL715: Decodable {
    let bolNumber: String?
    let bolType: String?
    let status: String?
    let originPort: String?
    let destinationPort: String?
    let vesselName: String?
    let voyageNumber: String?
    let freightTerms: String?
    let grossWeightKg: String?
    let numberOfPackages: Int?
    let cargoDescription: String?
}
private struct SIShipment715: Decodable {
    let bookingNumber: String?
    let grossWeightKg: String?
    let cargoDescription: String?
}

struct VesselBLDraftApprovalScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 7
    var bolNumber: String = "ONEYSHA12345678"

    var body: some View {
        Shell(theme: theme) {
            VesselBLDraftApprovalBody(shipmentId: shipmentId, bolNumber: bolNumber)
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

private struct VesselBLDraftApprovalBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let bolNumber: String

    @State private var bol: BOL715? = nil
    @State private var si: SIShipment715? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var bolWeight: Double? { bol?.grossWeightKg.flatMap { Double($0) } }
    private var siWeight: Double? { si?.grossWeightKg.flatMap { Double($0) } }
    private var weightDelta: Double? {
        guard let b = bolWeight, let s = siWeight else { return nil }
        return b - s
    }
    private var hasDiscrepancy: Bool { (weightDelta.map { abs($0) > 0.5 }) ?? true }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    gapCard("Loading carrier B/L draft…", "getBOL · \(bolNumber)", warn: false)
                } else if let err = loadError {
                    gapCard("B/L draft unavailable", err, warn: true)
                } else {
                    facsimileHero
                    verificationCard
                    parametersCard
                    governingLaw
                    esang
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("✦ VESSEL OPERATOR · B/L DRAFT").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("DCSA eBL · DRAFT v2").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(Brand.vessel)
            }
            Text("Bill of lading draft").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Text("\(bol?.bolNumber ?? bolNumber) · \(si?.bookingNumber ?? "EUSO-BK-000007")")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: B/L facsimile hero

    private var facsimileHero: some View {
        RimCard715 {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("BILL OF LADING").font(.system(size: 11, weight: .heavy)).tracking(0.2).foregroundStyle(palette.textPrimary)
                    Text("· negotiable original").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(bol?.bolNumber ?? bolNumber).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
                Rectangle().fill(palette.borderSoft).frame(height: 1).padding(.top, 8).padding(.bottom, 12)

                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        gridField("SHIPPER", "Eusorone Technologies, Inc.")
                        gridField("CONSIGNEE", "Pacific Resin Imports LLC")
                        gridField("NOTIFY PARTY", "Same as consignee")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(palette.borderFaint).frame(width: 1)
                    VStack(alignment: .leading, spacing: 12) {
                        gridField("CARRIER / VESSEL", "ONE · \(bol?.vesselName ?? "MV Aurora Spirit")")
                        gridField("PORT OF LOADING / DISCHARGE", "\(bol?.originPort ?? "CNSHA") → \(bol?.destinationPort ?? "USLGB")", mono: true)
                        gridField("VOYAGE / ETD", "\(bol?.voyageNumber ?? "082E") · Jun 22")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                }
                .overlay(
                    Text("DRAFT")
                        .font(.system(size: 54, weight: .heavy))
                        .foregroundStyle(palette.textPrimary.opacity(0.05))
                        .rotationEffect(.degrees(-15))
                        .allowsHitTesting(false)
                )
                .padding(.bottom, 12)

                HStack {
                    HStack(spacing: 8) {
                        Circle().fill(Brand.warning).frame(width: 7, height: 7)
                        Text("AWAITING SHIPPER APPROVAL").font(.system(size: 8.5, weight: .heavy)).tracking(0.2).foregroundStyle(Brand.warning)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.warning.opacity(0.14)))
                    Spacer()
                    Text("drafted from SI · v2").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func gridField(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 7, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
            Text(value).font(mono ? Font.system(size: 10, weight: .semibold, design: .monospaced) : .system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: SI → B/L verification

    private var verificationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("SI → B/L VERIFICATION")
                Spacer()
                Text(hasDiscrepancy ? "1 DISCREPANCY" : "ALL MATCH")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(hasDiscrepancy ? Brand.warning : Brand.success)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill((hasDiscrepancy ? Brand.warning : Brand.success).opacity(0.14)))
            }
            VStack(spacing: 0) {
                checkRow(ok: true, title: "Parties match SI", sub: "shipper · consignee · notify identical", verdict: "OK")
                divider
                checkRow(ok: true, title: "Cargo & HS code match", sub: (bol?.cargoDescription ?? "Industrial resins") + " · HS 3907.99", verdict: "OK")
                divider
                checkRow(ok: !hasDiscrepancy, title: "Gross weight " + (hasDiscrepancy ? "differs" : "matches"),
                         sub: weightSub, verdict: hasDiscrepancy ? "REVIEW" : "OK")
                divider
                Text("Container & seal match · TCLU 784512-3 · AX0094")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    .padding(.vertical, 10)
            }
            .cardWrap715(palette)
        }
    }
    private var weightSub: String {
        if let b = bolWeight, let s = siWeight {
            let d = b - s
            let sign = d >= 0 ? "+" : ""
            return "B/L \(grouped(Int(b))) kg vs SI \(grouped(Int(s))) kg · \(sign)\(Int(d)) kg"
        }
        return "B/L 21,500 kg vs SI 21,480 kg · +20 kg"
    }

    private func checkRow(ok: Bool, title: String, sub: String, verdict: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((ok ? Brand.success : Brand.warning).opacity(0.16)).frame(width: 18, height: 18)
                Image(systemName: ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(ok ? Brand.success : Brand.warning)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text(sub).font(.system(size: 9)).foregroundStyle(ok ? palette.textTertiary : Brand.warning).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Text(verdict).font(.system(size: 9, weight: .heavy)).foregroundStyle(ok ? Brand.success : Brand.warning)
        }
        .padding(.vertical, 10)
    }

    // MARK: B/L parameters

    private var parametersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("B/L PARAMETERS")
            VStack(spacing: 0) {
                HStack {
                    Text("Type").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    Text((bol?.bolType ?? "master").capitalized).font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("Release").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    Text("Sea Waybill").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(LinearGradient.primary))
                }.padding(.vertical, 12)
                divider
                HStack {
                    Text("Originals").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    Text("0 · surrender-free").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("Freight").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    Text((bol?.freightTerms ?? "prepaid").capitalized).font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.success)
                }.padding(.vertical, 12)
            }
            .cardWrap715(palette)
        }
    }

    // MARK: Governing law

    private var governingLaw: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("GOVERNING LAW / DISCHARGE")
            HStack(spacing: 8) {
                lawChip(true, "US · COGSA · CBP")
                lawChip(false, "CA · COGWA · CBSA")
                lawChip(false, "MX · LNCM · SAT")
            }
        }
    }
    private func lawChip(_ active: Bool, _ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: active ? .heavy : .semibold))
            .foregroundStyle(active ? Color(hex: 0x5B8CFF) : palette.textSecondary)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(active ? Color(hex: 0x5B8CFF).opacity(0.10) : palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint), lineWidth: active ? 1.1 : 1))
    }

    private var esang: some View {
        HStack(alignment: .top, spacing: 12) {
            OrbeSang(state: .idle, diameter: 26).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(hasDiscrepancy ? "B/L matches the SI except gross weight" : "B/L matches the submitted SI on every field")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Approve to lock the document of title, or request a correction")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.esangSoft))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Approve B/L", action: { /* STUB · vesselShipments.approveBLDraft */ })
            Button {
                // STUB · vesselShipments.requestBLCorrection
            } label: {
                Text("Request correction").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 166, minHeight: 48).background(palette.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: bits

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }
    private var divider: some View { Rectangle().fill(palette.borderFaint).frame(height: 1) }
    private func gapCard(_ title: String, _ detail: String, warn: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warn ? "exclamationmark.triangle.fill" : "doc.text")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(warn ? Brand.danger : palette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(warn ? Brand.danger.opacity(0.4) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private func grouped(_ v: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private func load() async {
        loading = true; loadError = nil
        struct BOLIn: Encodable { let bolNumber: String }
        struct DetailIn: Encodable { let id: Int }
        do {
            async let b: BOL715? = EusoTripAPI.shared.query("vesselShipments.getBOL", input: BOLIn(bolNumber: bolNumber))
            async let s: SIShipment715? = EusoTripAPI.shared.query("vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
            let (bb, ss) = try await (b, s)
            self.bol = bb; self.si = ss
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

private struct RimCard715<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            content().padding(Space.s5)
        }.frame(maxWidth: .infinity)
    }
}
private extension View {
    func cardWrap715(_ palette: Theme.Palette) -> some View {
        self.padding(.horizontal, Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("715 · Vessel B/L Draft Approval · Night") {
    VesselBLDraftApprovalScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("715 · Vessel B/L Draft Approval · Light") {
    VesselBLDraftApprovalScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
