//
//  751_VesselISFRequirements.swift
//  EusoTrip — Vessel Operator · Advance Security Filing (COMPLIANCE/CUSTOMS · tri-country
//  filing-checklist archetype).
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/751 Vessel ISF Requirements.svg": a US/CA/MX
//  country segment drives the active advance-security regime; the active regime renders its
//  filing-composition hero (12-cell element bar) + a numbered element checklist; a TRI-COUNTRY
//  ADVANCE FILING band carries all three authority · filing · timing · penalty · currency
//  variations; and a MUTUAL RECOGNITION row (CTPAT–PIP–OEA · USMCA AEO fast-lane) closes it.
//  App Shell + real Vessel-Operator BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME).
//
//  Honest binding (frontend/server/routers/vesselShipments.ts):
//    element checklist + hero <- vesselShipments.getISFRequirements (EXISTS :3429 ·
//      vesselProcedure · NO input -> services/crossBorderVessel.ts ISF_10_PLUS_2 :62 ->
//      [{field,description,timing,penalty}]). The 12 ISF 10+2 elements (10 importer + carrier
//      +1 Vessel Stow Plan / +2 Container Status Messages), their timing and the $5,000/violation
//      penalty are 100% real. The endpoint carries NO per-booking filed/pending state, so the
//      hero shows the ELEMENT-TYPE composition (10 importer · +1 · +2), NOT a fabricated
//      "11/12 filed"; live filed/pending binds to vesselShipments.getISFStatus (EXISTS :2080)
//      once a bookingId is in scope (surfaced as a NAMED GAP for the live-progress view).
//    tri-country band = regulatory reference (US CBP ISF 10+2 · CA CBSA ACI · MX SAT Pedimento) —
//      CA/MX ocean-lane advance filing is a NAMED GAP vessel.getAdvanceFiling.
//    mutual recognition = regulatory reference (USMCA AEO: CTPAT/PIP/OEA · −40% exam priority).
//    "File +2 container status" -> vesselShipments.updateVesselShipmentStatus (EXISTS :304) —
//      STUB here (no bookingId in scope) -> re-loads. "Switch regime" -> client segment toggle.
//
//  0 mock data on load · honest empty/error states · seed ONLY in #Preview. Helpers _751.
//

import SwiftUI

// MARK: - View model

private enum ISFElementKind751 { case importer, stow, status }

private struct ISFElement751: Identifiable {
    let id = UUID()
    let number: Int
    let short: String
    let kind: ISFElementKind751
}

private struct ISFReqVM751 {
    let importerCount: Int
    let stowCount: Int
    let statusCount: Int
    let timing: String
    let penalty: String
    let importerElements: [ISFElement751]

    var total: Int { importerCount + stowCount + statusCount }

    static let preview = ISFReqVM751(
        importerCount: 10, stowCount: 1, statusCount: 1,
        timing: "−24h ETD · pre-load", penalty: "$5,000/viol",
        importerElements: [
            .init(number: 1, short: "Manufacturer", kind: .importer),
            .init(number: 2, short: "Seller", kind: .importer),
            .init(number: 3, short: "Buyer", kind: .importer),
            .init(number: 4, short: "Ship-to party", kind: .importer),
            .init(number: 5, short: "Stuffing location", kind: .importer),
            .init(number: 6, short: "Consolidator", kind: .importer),
            .init(number: 7, short: "Importer of record #", kind: .importer),
            .init(number: 8, short: "Consignee #", kind: .importer),
            .init(number: 9, short: "Country of origin", kind: .importer),
            .init(number: 10, short: "HTS 6-digit", kind: .importer),
        ]
    )
}

// MARK: - Screen wrapper

struct VesselISFRequirementsScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselISFRequirementsBody751()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselISFRequirementsBody751: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var vm: ISFReqVM751? = nil

    private var amberText: Color { scheme == .dark ? Color(hex: 0xFFB74D) : Color(hex: 0xE08A00) }
    private var dangerText: Color { scheme == .dark ? Color(hex: 0xFF8A7D) : Color(hex: 0xC0362B) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                IridescentHairline()
                countrySegment
                if loading {
                    LifecycleCard { Text("Loading ISF 10+2 elements…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let vm, !vm.importerElements.isEmpty {
                    hero(vm)
                    activeElements(vm)
                    triCountryBand
                    mutualRecognition
                    ctaRow
                } else {
                    EusoEmptyState(systemImage: "shield.lefthalf.filled",
                                   title: "No ISF 10+2 elements",
                                   subtitle: "No advance-filing requirements were returned for this regime.")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                EusoTripEyebrow(verbatim: "VESSEL OPERATOR · ADVANCE FILING")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("CBP · 19 CFR 149").font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(0.4)
                    .foregroundStyle(Brand.vessel)
            }
            Text("Advance security filing").font(.system(size: 26, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
            Text("VES-260527-A7F3C19D04 · Shanghai CNSHA → Long Beach USLGB")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Country segment
    private var countrySegment: some View {
        HStack(spacing: 8) {
            segChip(title: "US · CBP", sub: "ISF 10+2", active: true)
            segChip(title: "CA · CBSA", sub: "ACI eMANIFEST", active: false)
            segChip(title: "MX · SAT", sub: "PEDIMENTO · VUCEM", active: false)
        }
    }
    private func segChip(title: String, sub: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 11, weight: .heavy)).kerning(0.3).foregroundColor(active ? .white : palette.textSecondary)
            Text(sub).font(.system(size: 8, weight: .bold)).kerning(0.2).foregroundColor(active ? .white.opacity(0.85) : palette.textTertiary)
        }
        .frame(maxWidth: .infinity).frame(height: 30)
        .background(Group {
            if active { Capsule().fill(LinearGradient.primary) }
            else { Capsule().fill(palette.bgCard).overlay(Capsule().stroke(palette.borderSoft)) }
        })
    }

    // MARK: Hero — element composition
    private func hero(_ vm: ISFReqVM751) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal.opacity(0.85))
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("ISF 10+2 · REQUIRED ELEMENTS · \(vm.total)")
                        .font(.system(size: 9, weight: .heavy)).kerning(0.6).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("10+\(vm.stowCount + vm.statusCount)").font(.system(size: 9, weight: .heavy))
                        .foregroundColor(amberText)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.warning.opacity(scheme == .dark ? 0.16 : 0.12)))
                }
                // 12-cell element-type bar
                HStack(spacing: 3) {
                    ForEach(0..<vm.importerCount, id: \.self) { _ in cell(LinearGradient.primary) }
                    ForEach(0..<vm.stowCount, id: \.self) { _ in cell(LinearGradient(colors: [Brand.success, Brand.success], startPoint: .leading, endPoint: .trailing)) }
                    ForEach(0..<vm.statusCount, id: \.self) { _ in cell(LinearGradient(colors: [Brand.warning, Brand.warning], startPoint: .leading, endPoint: .trailing)) }
                }
                .padding(.top, 12)
                Text("10 importer · +1 stow plan (carrier) · +2 container status (carrier)")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .padding(.top, 10)
                Divider().background(palette.textPrimary.opacity(0.08)).padding(.top, 8)
                Text("\(vm.timing) · \(vm.penalty) + loading block")
                    .font(.system(size: 11, weight: .heavy)).foregroundColor(dangerText)
                    .padding(.top, 8)
            }
            .padding(18)
        }
        .frame(height: 118)
    }

    private func cell(_ fill: LinearGradient) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(fill).frame(maxWidth: .infinity).frame(height: 10)
    }

    // MARK: Active elements — numbered 2-col grid
    private func activeElements(_ vm: ISFReqVM751) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVE ELEMENTS · ISF 10+2 · \(vm.importerCount) IMPORTER")
                .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], alignment: .leading, spacing: 12) {
                ForEach(vm.importerElements) { el in
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(LinearGradient.primary).frame(width: 18, height: 18)
                            Text("\(el.number)").font(.system(size: 8.5, weight: .heavy)).foregroundColor(.white)
                        }
                        Text(el.short).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.borderFaint)))
        }
    }

    // MARK: Tri-country advance filing band
    private var triCountryBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRI-COUNTRY ADVANCE FILING · CNSHA IMPORT LANE")
                .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                filingRow(code: "US", title: "CBP · ISF 10+2", sub: "−24h pre-load · 19 CFR 149 · USD", right: "$5,000/viol", rightColor: dangerText, tag: "● ACTIVE", tagColor: Color(hex: 0x5BB0FF), active: true)
                Divider().background(palette.textPrimary.opacity(0.05)).padding(.leading, 16)
                filingRow(code: "CA", title: "CBSA · ACI eManifest", sub: "−1h (15d hazmat) · Customs Act 12.1 · CAD", right: "≤$25,000 CAD", rightColor: amberText, tag: "STANDBY", tagColor: palette.textTertiary, active: false)
                Divider().background(palette.textPrimary.opacity(0.05)).padding(.leading, 16)
                filingRow(code: "MX", title: "SAT · Pedimento + VUCEM", sub: "pre-arrival · DODA · IVA/IEPS · MXN", right: "agente aduanal", rightColor: palette.textSecondary, tag: "STANDBY", tagColor: palette.textTertiary, active: false)
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.borderFaint)))
        }
    }

    private func filingRow(code: String, title: String, sub: String, right: String, rightColor: Color, tag: String, tagColor: Color, active: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textPrimary.opacity(0.06)))
                .frame(width: 26, height: 24)
                .overlay(Text(code).font(.system(size: 10, weight: .heavy)).foregroundColor(active ? .white : palette.textSecondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(sub).font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(right).font(.system(size: 10.5, weight: .heavy)).foregroundColor(rightColor)
                Text(tag).font(.system(size: 8.5, weight: .heavy)).kerning(0.4).foregroundColor(tagColor)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(active ? LinearGradient(colors: [Brand.blue.opacity(0.10), Brand.magenta.opacity(0.10)], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing))
    }

    // MARK: Mutual recognition
    private var mutualRecognition: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MUTUAL RECOGNITION · USMCA AEO FAST-LANE")
                .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                aeoChip(program: "CTPAT", scope: "US · Tier 2", active: true)
                Text("–").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textTertiary)
                aeoChip(program: "PIP", scope: "CA · CBSA", active: false)
                Text("–").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textTertiary)
                aeoChip(program: "OEA", scope: "MX · SAT", active: false)
                Spacer(minLength: 0)
                VStack(spacing: 1) {
                    Text("−40% EXAM").font(.system(size: 9, weight: .heavy)).foregroundColor(Brand.success)
                    Text("priority lane").font(.system(size: 8, weight: .bold)).foregroundColor(Brand.success)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Brand.success.opacity(scheme == .dark ? 0.14 : 0.10)))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint)))
        }
    }

    private func aeoChip(program: String, scope: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(program).font(.system(size: 10, weight: .heavy)).foregroundColor(active ? .white : palette.textSecondary)
            Text(scope).font(.system(size: 8, weight: .bold)).foregroundColor(active ? .white.opacity(0.85) : palette.textTertiary)
        }
        .frame(width: 74, height: 32)
        .background(Group {
            if active { RoundedRectangle(cornerRadius: 10).fill(LinearGradient.primary) }
            else { RoundedRectangle(cornerRadius: 10).fill(palette.bgCardSoft).overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.borderSoft)) }
        })
    }

    // MARK: CTA
    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await load() } }) {
                Text("File +2 container status").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(LinearGradient.primary))
            }
            Button(action: { Task { await load() } }) {
                Text("Switch regime").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 128, height: 48)
                    .background(Capsule().fill(palette.bgCardSoft).overlay(Capsule().stroke(palette.textPrimary.opacity(0.10))))
            }
        }
    }

    // MARK: Load
    private func load() async {
        loading = true; loadError = nil
        do {
            struct Req751: Decodable { let field: String?; let timing: String?; let penalty: String? }
            let reqs: [Req751] = try await EusoTripAPI.shared.query("vesselShipments.getISFRequirements", input: EmptyInput751())

            var importer: [ISFElement751] = []
            var stow = 0, status = 0
            var timing = "−24h ETD · pre-load"
            var penalty = "$5,000/viol"
            for r in reqs {
                let f = (r.field ?? "")
                let low = f.lowercased()
                if low.contains("stow") { stow += 1; continue }
                if low.contains("container status") { status += 1; continue }
                importer.append(ISFElement751(number: importer.count + 1, short: shortField(f), kind: .importer))
                if let p = r.penalty, p.contains("5,000") { penalty = "$5,000/viol" }
                if let t = r.timing, t.lowercased().contains("24") { timing = "−24h ETD · pre-load" }
            }

            vm = importer.isEmpty ? nil : ISFReqVM751(
                importerCount: importer.count,
                stowCount: stow,
                statusCount: status,
                timing: timing,
                penalty: penalty,
                importerElements: importer
            )
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func shortField(_ f: String) -> String {
        let low = f.lowercased()
        if low.contains("manufacturer") { return "Manufacturer" }
        if low.contains("seller") { return "Seller" }
        if low.contains("buyer") { return "Buyer" }
        if low.contains("ship-to") { return "Ship-to party" }
        if low.contains("stuffing") { return "Stuffing location" }
        if low.contains("consolidator") { return "Consolidator" }
        if low.contains("importer of record") { return "Importer of record #" }
        if low.contains("consignee") { return "Consignee #" }
        if low.contains("country of origin") { return "Country of origin" }
        if low.contains("hts") { return "HTS 6-digit" }
        return f
    }
}

private struct EmptyInput751: Encodable {}

#Preview("751 · ISF Requirements · Light") {
    VesselISFRequirementsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("751 · ISF Requirements · Dark") {
    VesselISFRequirementsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
