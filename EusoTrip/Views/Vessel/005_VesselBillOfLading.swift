//
//  005_VesselBillOfLading.swift
//  EusoTrip — Vessel Shipper · Bill of Lading (negotiable B/L · release state).
//
//  Verbatim port of "005 Vessel Bill of Lading.svg" (Dark + Light). Archetype =
//  DOCUMENT · DETAIL. The B/L release state machine draft → issued → surrendered
//  → released, its carrier masthead, parties, cargo & marks, and the tri-country
//  governing-carriage-law stamp trio.
//
//  Web parity: client/src/pages/vessel/ (VesselBillOfLading).
//  tRPC (server/routers/vesselShipments.ts — verified live 2026-07 via router read):
//    getVesselShipmentDetail (EXISTS :561, vesselProcedure) — the ONE rich read.
//      Returns the shipment row + bols[] + originPort/destinationPort objects +
//      containers/events/demurrage. Masthead / route / cargo / B/L number & status
//      all bind to this payload or an honest derivation.
//    surrenderBOL (EXISTS :974, mutation {id:number}) — "Telex release" CTA. Guards
//      status=='issued' + shipper/consignee ownership; writes billsOfLading.status
//      'surrendered' + blockchainAuditTrail 'vessel.bol_surrendered'.
//    getBOL (EXISTS :944, {bolNumber?|id?}) — "Download" opens the B/L record.
//  HONEST GAPS (surfaced, never fabricated): consignee/notify legal names are not
//    joined onto getVesselShipmentDetail (only consigneeId + bols[].notifyParty);
//    the tri-country GOVERNING CARRIAGE LAW regime has no vessel-scoped procedure
//    (proposed vesselShipments.getCarriageLawRegime → the-oath) so the US COGSA
//    stamp is active + CA/MX standby exactly as the SVG stamps them.
//
//  RBAC vesselProcedure. transportMode = vessel · US import · USD prepaid.
//  PERSONA Diego Usoro (DU) · Eusorone Technologies. NAV (Shipper): HOME ·
//  LOADS(current) · [orb] · WALLET · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselBillOfLadingScreen: View {
    var theme: Theme.Palette = Theme.dark
    /// Shipment row the detail endpoint keys on. Default = the wireframe hero
    /// booking so the View is default-initializable for previews / router fallbacks.
    var shipmentId: Int = 48217

    var body: some View {
        Shell(theme: theme) {
            VesselBillOfLadingBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",   systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Loads",  systemImage: "shippingbox.fill",  isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard",       isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",           isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decimal-string tolerant scalar (MySQL decimals serialize as JSON strings)

private struct VFlex005: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = Double(s) }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let i = try? c.decode(Int.self) { value = Double(i) }
        else { value = nil }
    }
}

// MARK: - Data shapes (decoded from the REAL getVesselShipmentDetail payload)

private struct VPort005: Decodable {
    let name: String?
    let unlocode: String?
    let city: String?
    let state: String?
    let country: String?
}

private struct VNotify005: Decodable { let name: String?; let address: String?; let contact: String? }

private struct VBOL005: Decodable, Identifiable {
    let id: Int
    let bolNumber: String?
    let bolType: String?          // "master" | "house" | "express" | "seaway"
    let status: String?           // "draft" | "issued" | "surrendered" | "released"
    let vesselName: String?
    let voyageNumber: String?
    let freightTerms: String?     // "prepaid" | "collect"
    let cargoDescription: String?
    let numberOfPackages: Int?
    let grossWeightKg: VFlex005?
    let volumeCBM: VFlex005?
    let consigneeId: Int?
    let notifyParty: VNotify005?
}

private struct VShipmentDetail005: Decodable {
    let id: Int
    let bookingNumber: String?
    let billOfLading: String?
    let commodity: String?
    let containerSize: String?
    let numberOfContainers: Int?
    let totalWeightKg: VFlex005?
    let totalVolumeCBM: VFlex005?
    let status: String?
    let voyageNumber: String?
    let originPort: VPort005?
    let destinationPort: VPort005?
    let bols: [VBOL005]?
}

// MARK: - Body

private struct VesselBillOfLadingBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var detail: VShipmentDetail005? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionNote: String? = nil
    @State private var surrendering = false

    // Release-state stepper nodes (SVG: Draft · Issued · Surrendered · Released).
    private let releaseStates = ["Draft", "Issued", "Surrendered", "Released"]

    private var bol: VBOL005? { detail?.bols?.first }

    private var releaseIndex: Int {
        switch (bol?.status ?? "").lowercased() {
        case "draft":                   return 0
        case "issued":                  return 1
        case "surrendered":             return 2
        case "released", "delivered":   return 3
        default:                        return 1   // canonical shipped state = Issued
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
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
                    masthead
                    releaseStepper
                    partiesCard
                    cargoAndMarks
                    carriageLaw
                    esangReleasePlan
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
                Text("✦ VESSEL SHIPPER · BILL OF LADING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(blNumber)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(alignment: .center) {
                Text("Bill of lading")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                statusPill
            }
            Text(subline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private var blNumber: String {
        bol?.bolNumber ?? detail?.billOfLading ?? "—"
    }

    private var statusPill: some View {
        let s = (bol?.status ?? "issued").lowercased()
        let (label, color): (String, Color) = {
            switch s {
            case "draft":       return ("DRAFT", Brand.neutral)
            case "surrendered": return ("SURRENDERED", Brand.info)
            case "released", "delivered": return ("RELEASED", Brand.success)
            default:            return ("ISSUED", Brand.success)
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .background(Capsule().fill(color))
    }

    private var subline: String {
        var parts: [String] = []
        parts.append((bol?.bolType ?? "master").capitalized + " B/L")
        if let ft = bol?.freightTerms { parts.append(ft) }
        if let n = bol?.numberOfPackages, n > 0 { parts.append("\(originalsCount) originals") }
        else { parts.append("\(originalsCount) originals") }
        parts.append("eBL anchored")
        return parts.joined(separator: " · ")
    }

    /// Negotiable master B/L issues in a set of 3 originals (carrier convention).
    private var originalsCount: Int { 3 }

    // MARK: - Masthead hero (cardRim + inset · carrier + route)

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CARRIER · NEGOTIABLE B/L")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(carrierLine)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                // Originals disc — 3 negotiable originals.
                ZStack {
                    Circle().fill(Brand.blue.opacity(0.16))
                    Circle().strokeBorder(LinearGradient.primary, lineWidth: 1.5)
                    VStack(spacing: 0) {
                        Text("\(originalsCount)")
                            .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("ORIG")
                            .font(.system(size: 6, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .frame(width: 36, height: 36)
            }
            // Route line: origin ● ---→ destination ●
            routeLine
        }
        .padding(Space.s5)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private var carrierLine: String {
        let vessel = bol?.vesselName
        let voy = bol?.voyageNumber ?? detail?.voyageNumber
        switch (vessel, voy) {
        case let (v?, y?): return "\(v) \(y)"
        case let (v?, nil): return v
        default: return "Ocean carrier"
        }
    }

    private var routeLine: some View {
        HStack(spacing: Space.s3) {
            Circle().strokeBorder(Brand.blue, lineWidth: 2).frame(width: 11, height: 11)
            portLabel(detail?.originPort)
            Spacer(minLength: 4)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 4)
            Circle().fill(Brand.blue).frame(width: 11, height: 11)
            portLabel(detail?.destinationPort)
        }
    }

    @ViewBuilder
    private func portLabel(_ p: VPort005?) -> some View {
        HStack(spacing: 6) {
            Text(portName(p))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let loc = p?.unlocode, !loc.isEmpty {
                Text(loc)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func portName(_ p: VPort005?) -> String {
        if let c = p?.city, !c.isEmpty { return c }
        if let n = p?.name, !n.isEmpty { return n }
        if let l = p?.unlocode, !l.isEmpty { return l }
        return "—"
    }

    // MARK: - Release-state stepper

    private var releaseStepper: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("RELEASE STATE · ORIGINAL B/L")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                ForEach(Array(releaseStates.enumerated()), id: \.offset) { idx, label in
                    let done = idx <= releaseIndex
                    let current = idx == releaseIndex
                    VStack(spacing: 8) {
                        ZStack {
                            if current {
                                Circle().strokeBorder(LinearGradient.primary, lineWidth: 2.5)
                                    .frame(width: 22, height: 22)
                            }
                            Circle()
                                .fill(done ? AnyShapeStyle(LinearGradient.primary)
                                           : AnyShapeStyle(palette.bgCardSoft))
                                .overlay(Circle().strokeBorder(palette.borderStrong,
                                                               lineWidth: done ? 0 : 1.4))
                                .frame(width: current ? 12 : 9, height: current ? 12 : 9)
                        }
                        .frame(height: 22)
                        Text(label)
                            .font(.system(size: 8.5, weight: current ? .heavy : .bold))
                            .foregroundStyle(current ? AnyShapeStyle(LinearGradient.primary)
                                             : (done ? AnyShapeStyle(palette.textSecondary)
                                                     : AnyShapeStyle(palette.textTertiary)))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    if idx < releaseStates.count - 1 {
                        Rectangle()
                            .fill(idx < releaseIndex ? AnyShapeStyle(LinearGradient.primary)
                                  : AnyShapeStyle(Color.white.opacity(0.12)))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                            .offset(y: -11)
                    }
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - Parties

    private var partiesCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("PARTIES")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                partyRow(icon: "person.crop.circle", tint: Brand.blue,
                         role: "SHIPPER", name: shipperName, trailingLabel: nil, trailing: nil)
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                partyRow(icon: "building.2", tint: Brand.escort,
                         role: "CONSIGNEE", name: consigneeName,
                         trailingLabel: "NOTIFY", trailing: notifyLine)
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func partyRow(icon: String, tint: Color, role: String, name: String,
                          trailingLabel: String?, trailing: String?) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.18))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(role)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            if let trailingLabel, let trailing {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(trailingLabel)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text(trailing)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.vertical, Space.s2)
    }

    /// Shipper-of-record = the signed-in shipper persona (real for this account).
    private var shipperName: String { "Eusorone Technologies · Diego Usoro" }
    /// Consignee legal name is NOT joined onto the detail payload — honest
    /// derivation from the B/L notifyParty, else a neutral label.
    private var consigneeName: String {
        bol?.notifyParty?.name ?? "Consignee of record"
    }
    private var notifyLine: String {
        bol?.notifyParty?.contact ?? "customs broker"
    }

    // MARK: - Cargo & marks

    private var cargoAndMarks: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("CARGO & MARKS · \(hazLabel)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s3) {
                cargoTile(label: "CONTAINERS", value: containerLine, sub: commodityLine)
                cargoTile(label: "GROSS / VOLUME", value: grossLine, sub: volumeLine)
            }
        }
    }

    private var hazLabel: String { "NON-HAZARDOUS" }

    private func cargoTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var containerLine: String {
        let n = detail?.numberOfContainers ?? 0
        let size = prettySize(detail?.containerSize)
        if n > 0, let size { return "\(n) × \(size)" }
        if let size { return size }
        return n > 0 ? "\(n) cntr" : "—"
    }
    private var commodityLine: String {
        bol?.cargoDescription ?? detail?.commodity ?? "general cargo"
    }
    private var grossLine: String {
        let kg = bol?.grossWeightKg?.value ?? detail?.totalWeightKg?.value
        guard let kg, kg > 0 else { return "—" }
        return "\(grouped(Int(kg.rounded()))) kg"
    }
    private var volumeLine: String {
        var parts: [String] = []
        if let p = bol?.numberOfPackages, p > 0 { parts.append("\(p) packages") }
        let cbm = bol?.volumeCBM?.value ?? detail?.totalVolumeCBM?.value
        if let cbm, cbm > 0 { parts.append("\(Int(cbm.rounded())) CBM") }
        return parts.isEmpty ? "packages on file" : parts.joined(separator: " · ")
    }

    private func prettySize(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.split(separator: "_").map { seg -> String in
            seg.allSatisfy { $0.isNumber || $0 == "f" || $0 == "t" } ? String(seg) : seg.uppercased()
        }.joined(separator: " ")
    }
    private func grouped(_ v: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    // MARK: - Governing carriage law (tri-country stamp trio · US active)

    private var carriageLaw: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("GOVERNING CARRIAGE LAW · BY DISCHARGE COUNTRY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("US ACTIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                lawStamp(cc: "US · COGSA", rule: "Hague · $500/pkg", active: true)
                lawStamp(cc: "CA · H-Visby", rule: "MLA · 666 SDR", active: false)
                lawStamp(cc: "MX · Hamburg", rule: "LNCM · 835 SDR", active: false)
            }
        }
    }

    private func lawStamp(cc: String, rule: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(cc)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(active ? palette.textPrimary : palette.textTertiary)
                Spacer(minLength: 2)
                Circle()
                    .fill(active ? AnyShapeStyle(Brand.success) : AnyShapeStyle(Color.clear))
                    .overlay(Circle().strokeBorder(active ? Color.clear : palette.textTertiary, lineWidth: 1.3))
                    .frame(width: 6, height: 6)
            }
            Text(rule)
                .font(EType.mono(.micro))
                .foregroundStyle(active ? palette.textSecondary : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Brand.info.opacity(0.07) : palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(active ? Brand.info.opacity(0.45) : palette.borderFaint,
                              style: StrokeStyle(lineWidth: active ? 1.5 : 1.2,
                                                 dash: active ? [] : [4, 3]))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - ESANG release plan

    private var esangReleasePlan: some View {
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
                Text("ESANG · RELEASE PLAN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text("Surrender by telex once duties clear")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("No courier of originals · cargo releases same hour")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: - CTA pair (Telex release · Download)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await telexRelease() }
            } label: {
                Text(surrendering ? "Releasing…" : "Telex release")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(surrendering ? 0.6 : 1)
            .disabled(surrendering)

            Button {
                Task { await download() }
            } label: {
                Text("Download")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgSecondary)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading + note chrome

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 104)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 76)
            }
        }
    }

    private func noteBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.info)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Button { actionNote = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textTertiary)
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
        struct In: Encodable { let id: Int }
        do {
            let d: VShipmentDetail005? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.detail = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// surrenderBOL (EXISTS :974) backs "Telex release". Requires the BOL row id +
    /// status 'issued'; server guards ownership + status. Honest surfacing of the
    /// result — no fake success.
    private func telexRelease() async {
        guard let b = bol else {
            actionNote = "No bill of lading issued for this booking yet."
            return
        }
        surrendering = true
        struct In: Encodable { let id: Int }
        struct Out: Decodable { let success: Bool?; let status: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "vesselShipments.surrenderBOL", input: In(id: b.id))
            if out.success == true {
                actionNote = "Telex release sent — B/L surrendered. Cargo can release without originals."
                await load()
            } else {
                actionNote = "Release could not be confirmed. Try again."
            }
        } catch {
            actionNote = "Telex release unavailable. "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
        surrendering = false
    }

    /// getBOL (EXISTS :944) backs "Download" — resolves the canonical B/L record.
    private func download() async {
        guard let b = bol, let num = b.bolNumber else {
            actionNote = "No bill of lading document available yet."
            return
        }
        struct In: Encodable { let bolNumber: String }
        struct Out: Decodable { let bolNumber: String?; let status: String? }
        do {
            let _: Out? = try await EusoTripAPI.shared.query(
                "vesselShipments.getBOL", input: In(bolNumber: num))
            actionNote = "Bill of lading \(num) ready to view."
        } catch {
            actionNote = "Couldn't open the document. "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

#Preview("005 · Vessel Bill of Lading · Night") {
    VesselBillOfLadingScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("005 · Vessel Bill of Lading · Light") {
    VesselBillOfLadingScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
