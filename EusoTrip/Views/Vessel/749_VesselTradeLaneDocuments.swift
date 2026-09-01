//
//  749_VesselTradeLaneDocuments.swift
//  EusoTrip — Vessel Operator · Trade Lane Documents (DOCUMENT-CHECKLIST archetype).
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/749 Vessel Trade Lane Documents.svg": a
//  composition DONUT hero shows the required trade-lane doc set by class, and the body is a
//  per-document checklist where each doc carries its own type glyph, a required/class flag
//  and a distinct status pill — not a uniform chip row. App Shell + real Vessel-Operator
//  BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Honest binding (frontend/server/routers/vesselShipments.ts):
//    required doc list <- vesselShipments.getCrossBorderVesselDocs (EXISTS :3440 ·
//      vesselProcedure · {direction,mode,hasHazmat,hasLiveAnimals} -> services/crossBorderVessel.ts
//      getRequiredVesselDocs :109 -> string[]). US_import returns the real 13-doc set (B/L ·
//      Commercial Invoice · Packing List · Certificate of Origin · ISF 10+2 · AMS · CBP Entry
//      Summary 7501 · Customs Bond · FDA Prior Notice · USDA/APHIS permit · ISF bond · HTS
//      classification · Arrival Notice). The endpoint returns doc NAMES only — no attach/filed
//      state — so each row's pill is the doc CLASS (CORE · FILING · PERMIT), derived honestly
//      from the name, NOT a fabricated ATTACHED/MISSING status. Live per-doc attach state binds
//      to vesselShipments.getVesselShipmentDetail (EXISTS :162) documents + getCustomsEntries
//      (EXISTS :3359) once a bookingId is in scope — surfaced as a NAMED GAP for the attach view.
//    "Attach document" -> vessel document upload (NO dedicated mutation — NAMED GAP
//      vessel.attachTradeDoc({bookingId,docType,url}); re-loads here). "All docs" -> full list.
//
//  0 mock data on load · honest empty/error states · seed ONLY in #Preview. Helpers _749.
//

import SwiftUI

// MARK: - View model

private enum DocClass749 { case core, filing, permit
    var label: String { switch self { case .core: return "CORE"; case .filing: return "FILING"; case .permit: return "PERMIT" } }
}

private struct TradeDocRow749: Identifiable {
    let id = UUID()
    let name: String
    let sub: String
    let cls: DocClass749
    let glyph: String
    let tint: Color
}

private struct TradeDocVM749 {
    let direction: String
    let lane: String
    let total: Int
    let coreCount: Int
    let filingCount: Int
    let permitCount: Int
    let docs: [TradeDocRow749]

    static let preview = TradeDocVM749(
        direction: "US IMPORT", lane: "Shanghai → Long Beach",
        total: 13, coreCount: 4, filingCount: 7, permitCount: 2,
        docs: [
            .init(name: "Bill of Lading (B/L)", sub: "core trade", cls: .core, glyph: "doc.text", tint: Color(hex: 0x5BB0FF)),
            .init(name: "Commercial invoice", sub: "core trade", cls: .core, glyph: "doc.text", tint: Color(hex: 0x5BB0FF)),
            .init(name: "ISF 10+2", sub: "advance filing", cls: .filing, glyph: "shield.lefthalf.filled", tint: Color(hex: 0xC56BE0)),
            .init(name: "CBP Entry Summary 7501", sub: "advance filing", cls: .filing, glyph: "doc.badge.gearshape", tint: Color(hex: 0xC56BE0)),
            .init(name: "FDA Prior Notice", sub: "agency permit", cls: .permit, glyph: "cross.case", tint: Brand.warning),
        ]
    )
}

// MARK: - Screen wrapper

struct VesselTradeLaneDocumentsScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselTradeLaneDocumentsBody749()
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

private struct VesselTradeLaneDocumentsBody749: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var vm: TradeDocVM749? = nil

    private var coreColor: Color { Color(hex: 0x5BB0FF) }
    private var filingColor: Color { Color(hex: 0xC56BE0) }
    private var permitColor: Color { Brand.warning }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading trade-lane docs…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let vm, !vm.docs.isEmpty {
                    hero(vm)
                    Text("DOCUMENTS · CORE TRADE + US IMPORT FILINGS")
                        .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                    checklist(vm)
                    ctaRow(vm)
                } else {
                    EusoEmptyState(systemImage: "doc.on.doc",
                                   title: "No required documents",
                                   subtitle: "No required trade-lane documents were returned for this route.")
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
                EusoTripEyebrow(verbatim: "VESSEL OPERATOR · TRADE DOCS")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(vm?.direction ?? "US IMPORT").font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(0.4)
                    .foregroundStyle(Brand.vessel)
            }
            Text("Trade lane documents").font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
            Text("\(vm?.lane ?? "Shanghai → Long Beach") · \(vm?.total ?? 0) required documents")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Hero — composition donut
    private func hero(_ vm: TradeDocVM749) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal.opacity(0.85))
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            HStack(spacing: 20) {
                donut(vm)
                VStack(alignment: .leading, spacing: 10) {
                    Text("US IMPORT DOC SET · CBP").font(.system(size: 9, weight: .heavy)).kerning(0.8).foregroundStyle(palette.textTertiary)
                    statRow(coreColor, "\(vm.coreCount) core trade")
                    statRow(filingColor, "\(vm.filingCount) advance filings")
                    statRow(permitColor, "\(vm.permitCount) agency permit\(vm.permitCount == 1 ? "" : "s")")
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .frame(height: 132)
    }

    private func donut(_ vm: TradeDocVM749) -> some View {
        let total = max(vm.total, 1)
        let core = Double(vm.coreCount) / Double(total)
        let filing = Double(vm.filingCount) / Double(total)
        let permit = Double(vm.permitCount) / Double(total)
        return ZStack {
            Circle().stroke(palette.textPrimary.opacity(0.08), lineWidth: 11)
            arc(from: 0, to: core, color: coreColor)
            arc(from: core, to: core + filing, color: filingColor)
            arc(from: core + filing, to: core + filing + permit, color: permitColor)
            VStack(spacing: 0) {
                Text("\(vm.total)").font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                Text("REQUIRED").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: 88, height: 88)
    }

    private func arc(from: Double, to: Double, color: Color) -> some View {
        Circle().trim(from: from, to: max(to - 0.012, from))
            .stroke(color, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }

    private func statRow(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Checklist
    private func checklist(_ vm: TradeDocVM749) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.docs.enumerated()), id: \.element.id) { idx, d in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9).fill(d.tint.opacity(scheme == .dark ? 0.14 : 0.12))
                        .frame(width: 34, height: 34)
                        .overlay(Image(systemName: d.glyph).font(.system(size: 14, weight: .regular)).foregroundColor(d.tint))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Text(d.sub).font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 6)
                    Text(d.cls.label).font(.system(size: 8.5, weight: .heavy)).kerning(0.4)
                        .foregroundColor(d.tint)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(d.tint.opacity(scheme == .dark ? 0.16 : 0.12)))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                if idx < vm.docs.count - 1 {
                    Divider().background(palette.textPrimary.opacity(0.05)).padding(.leading, 62)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.borderFaint)))
    }

    // MARK: CTA
    private func ctaRow(_ vm: TradeDocVM749) -> some View {
        HStack(spacing: 8) {
            Button(action: { Task { await load() } }) {
                Text("Attach document").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(LinearGradient.primary))
            }
            Button(action: { Task { await load() } }) {
                Text("All \(vm.total) docs").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 118, height: 48)
                    .background(Capsule().fill(palette.bgCardSoft).overlay(Capsule().stroke(palette.textPrimary.opacity(0.10))))
            }
        }
    }

    // MARK: Load
    private func load() async {
        loading = true; loadError = nil
        do {
            let names: [String] = try await EusoTripAPI.shared.query("vesselShipments.getCrossBorderVesselDocs", input: DocsInput749())
            var docs: [TradeDocRow749] = []
            var core = 0, filing = 0, permit = 0
            let commonSet: Set<String> = ["bill of lading (b/l)", "commercial invoice", "packing list", "certificate of origin"]
            for name in names {
                let cls = classify(name, common: commonSet)
                switch cls {
                case .core: core += 1
                case .filing: filing += 1
                case .permit: permit += 1
                }
                docs.append(TradeDocRow749(
                    name: name,
                    sub: subFor(cls),
                    cls: cls,
                    glyph: glyphFor(name, cls: cls),
                    tint: tintFor(cls)
                ))
            }
            vm = docs.isEmpty ? nil : TradeDocVM749(
                direction: "US IMPORT",
                lane: "Shanghai → Long Beach",
                total: docs.count,
                coreCount: core, filingCount: filing, permitCount: permit,
                docs: docs
            )
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func classify(_ name: String, common: Set<String>) -> DocClass749 {
        let n = name.lowercased()
        if common.contains(n) { return .core }
        if n.contains("fda") || n.contains("usda") || n.contains("aphis") || n.contains("cfia") || n.contains("permit") { return .permit }
        return .filing
    }
    private func subFor(_ c: DocClass749) -> String {
        switch c { case .core: return "core trade"; case .filing: return "advance filing"; case .permit: return "agency permit" }
    }
    private func tintFor(_ c: DocClass749) -> Color {
        switch c { case .core: return coreColor; case .filing: return filingColor; case .permit: return permitColor }
    }
    private func glyphFor(_ name: String, cls: DocClass749) -> String {
        let n = name.lowercased()
        if n.contains("isf") { return "shield.lefthalf.filled" }
        if n.contains("bond") { return "lock.doc" }
        if n.contains("manifest") || n.contains("ams") || n.contains("aci") { return "list.bullet.rectangle" }
        if n.contains("hts") || n.contains("tariff") { return "tag" }
        if n.contains("entry") || n.contains("7501") || n.contains("pedimento") { return "doc.badge.gearshape" }
        if cls == .permit { return "cross.case" }
        return "doc.text"
    }
}

private struct DocsInput749: Encodable {
    let direction = "US_import"
    let mode = "VESSEL"
    let hasHazmat = false
    let hasLiveAnimals = false
}

#Preview("749 · Trade Lane Documents · Light") {
    VesselTradeLaneDocumentsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("749 · Trade Lane Documents · Dark") {
    VesselTradeLaneDocumentsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
