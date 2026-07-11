//
//  727_VesselMarpolRecordBook.swift
//  EusoTrip — Vessel Operator · MARPOL Record Book.
//
//  Faithful 1:1 native port of "727 Vessel MARPOL Record Book · Dark/Light".
//  REGULATED LOGBOOK archetype: an annex-tabbed operations logbook (Annex
//  I/II/V/VI) with officer-sealed dated entries + a port-state-control band.
//
//  HONEST BINDING (server/routers/vesselShipments.ts):
//    · vesselShipments.getVesselCompliance — REAL PSC/inspection status + inspection history.
//  The annex operation-code legend is MARPOL 73/78 regulatory reference (a
//  published constant, not shipment data). HONEST GAP (proposed to the-oath):
//  no MARPOL record-book model/procedure exists (marpol.getRecordBook /
//  appendEntry / sealEntry) — the dated sealed-entry log surfaces as an explicit
//  awaiting state, never fabricated logbook entries. sealEntry is irreversible →
//  human-gated + confirm:true + audited. RBAC vesselProcedure · transportMode=vessel.
//

import SwiftUI

private struct VesselCompliance727: Decodable {
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?
    let inspections: [Inspection727]?
}
private struct Inspection727: Decodable {
    let inspectionDate: String?
    let result: String?
    let inspectorAuthority: String?
    let port: String?
}

private enum MarpolAnnex727: String, CaseIterable, Identifiable {
    case oil = "I", nls = "II", garbage = "V", air = "VI"
    var id: String { rawValue }
    var tab: String {
        switch self {
        case .oil: return "I · Oil"; case .nls: return "II · NLS"
        case .garbage: return "V · Garbage"; case .air: return "VI · Air"
        }
    }
    var title: String {
        switch self {
        case .oil: return "Annex I — Oil Record Book, Part I"
        case .nls: return "Annex II — Cargo Record Book (NLS)"
        case .garbage: return "Annex V — Garbage Record Book"
        case .air: return "Annex VI — Air / fuel changeover log"
        }
    }
    var reg: String {
        switch self {
        case .oil: return "Machinery space operations · MARPOL 73/78 reg. 17"
        case .nls: return "Noxious liquid substances · reg. 15"
        case .garbage: return "Garbage categories A–J · reg. 10"
        case .air: return "Fuel-oil changeover / ODS · reg. 14/12"
        }
    }
    // Regulatory operation-code legend (MARPOL reference constants).
    var codes: [(String, String)] {
        switch self {
        case .oil:
            return [("C", "Collection of oil residues (sludge)"),
                    ("D", "Non-automatic disposal of bilge water"),
                    ("E", "Routine machinery operations"),
                    ("I", "ODME / 15ppm OWS discharge")]
        case .nls:
            return [("J", "Loading of cargo"), ("K", "Unloading of cargo"),
                    ("M", "Tank washing"), ("N", "Discharge of residues")]
        case .garbage:
            return [("A", "Plastics"), ("C", "Domestic wastes"),
                    ("E", "Food wastes"), ("I", "Incinerator ash")]
        case .air:
            return [("14", "Fuel-oil changeover (sulphur)"),
                    ("12", "Ozone-depleting substances"),
                    ("13", "NOx tier compliance"),
                    ("18", "Bunker delivery note / sample")]
        }
    }
}

struct VesselMarpolRecordBookScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselMarpolRecordBookBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselMarpolRecordBookBody: View {
    @Environment(\.palette) private var palette

    @State private var annex: MarpolAnnex727 = .oil
    @State private var compliance: VesselCompliance727? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil

    private var isCompliant: Bool { (compliance?.status ?? "") == "compliant" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    annexTabs
                    entryLog
                    pscBand
                    ctaRow
                    if let actionMessage {
                        LifecycleCard { Text(actionMessage).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · MARPOL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("73/78").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            Text("Record book").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            ForEach([120, 40, 232], id: \.self) { h in
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: CGFloat(h))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    // Hero
    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(Color(hex: 0x141928)).padding(1.5)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Machinery-space operations logbook").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color(hex: 0xAAB2BB))
                    Spacer()
                    StatusPill(text: isCompliant ? "Compliant" : (compliance == nil ? "Unknown" : "Review"),
                               kind: isCompliant ? .success : (compliance == nil ? .neutral : .warning))
                }
                Text(annex.title).font(.system(size: 16, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text(annex.reg).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xAAB2BB))
                Text(inspectionLine).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            .padding(Space.s5)
        }
        .frame(minHeight: 120)
    }
    private var inspectionLine: String {
        let n = compliance?.totalInspections ?? 0
        let failed = compliance?.failedCount ?? 0
        if n == 0 { return "Record-book entries await marpol.getRecordBook" }
        return "\(n) PSC inspection\(n == 1 ? "" : "s") on file · \(failed) adverse"
    }

    // Annex tab bar (real interactive)
    private var annexTabs: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("RECORD BOOK · select annex", ref: "marpol.getRecordBook", gap: true)
            HStack(spacing: 4) {
                ForEach(MarpolAnnex727.allCases) { a in
                    Button { annex = a } label: {
                        Text(a.tab)
                            .font(.system(size: 10.5, weight: annex == a ? .heavy : .semibold))
                            .foregroundStyle(annex == a ? .white : palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Group { if annex == a { LinearGradient.primary } else { Color.clear } })
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4).background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // Entry log — regulatory code legend (reference) + honest awaiting entries
    private var entryLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("OPERATION CODES · MARPOL reference", ref: "appendEntry · sealEntry", gap: true)
            VStack(spacing: 0) {
                ForEach(Array(annex.codes.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 12) {
                        Text(item.0)
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.bgCardSoft))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Brand.success.opacity(0.4)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Code \(item.0) — \(item.1)").font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text("dated entry · quantity · position · officer seal").font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Text("AWAIT").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.warning)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    if idx < annex.codes.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16) }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            if let latest = latestInspection {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(Brand.success)
                    Text(latest).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                    Spacer()
                }
            }
            Text("Sealed dated entries await marpol.getRecordBook — codes above are MARPOL 73/78 reference, not fabricated log data.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }
    private var latestInspection: String? {
        guard let i = compliance?.inspections?.first else { return nil }
        let date = i.inspectionDate.map { String($0.prefix(10)) } ?? "—"
        let result = i.result?.capitalized ?? "logged"
        let auth = i.inspectorAuthority.map { " · \($0)" } ?? ""
        return "Latest PSC: \(date) · \(result)\(auth)"
    }

    private var pscBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("PORT-STATE-CONTROL INSPECTION", ref: "getVesselCompliance·country", gap: false)
            CountryBand727(rows: [
                .init(code: "US", line: "US · USCG · 33 CFR 151 · PSC boarding", active: true),
                .init(code: "CA", line: "CA · Transport Canada · SOR/2012-69", active: false),
                .init(code: "MX", line: "MX · SEMAR · NOM-MARPOL · PROFEPA", active: false),
            ])
        }
    }

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Add & seal entry", action: {
                actionMessage = "Appending + officer-sealing a MARPOL Annex \(annex.rawValue) entry awaits marpol.appendEntry / sealEntry (irreversible seal, confirm-gated + audited)."
            })
            Button { actionMessage = "Record-book export awaits marpol.getRecordBook entry data." } label: {
                Text("Export").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 120, height: 52)
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ title: String, ref: String, gap: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(gap ? "STUB · \(ref)" : ref).font(EType.mono(.micro)).foregroundStyle(gap ? Brand.warning : palette.textTertiary)
        }
    }

    private func load() async {
        loading = true; loadError = nil; actionMessage = nil
        defer { loading = false }
        struct ComplianceInput: Encodable { let vesselId: Int? }
        do {
            compliance = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCompliance", input: ComplianceInput(vesselId: nil))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct CountryBand727: View {
    struct Row: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }
    let rows: [Row]
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                HStack(spacing: 10) {
                    Text(r.code).font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(r.active ? Color.white : palette.textSecondary)
                        .frame(width: 26, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(r.active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft)))
                    Text(r.line).font(.system(size: 10.5, weight: r.active ? .bold : .regular))
                        .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(r.active ? "ACTIVE" : "STANDBY").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(r.active ? Brand.success : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(r.active ? AnyShapeStyle(palette.bgCard) : AnyShapeStyle(Color.clear))
                if idx < rows.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
            }
        }
        .padding(6).background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("727 · Vessel MARPOL Record Book · Night") { VesselMarpolRecordBookScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("727 · Vessel MARPOL Record Book · Light") { VesselMarpolRecordBookScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
