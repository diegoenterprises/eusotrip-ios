//
//  720_VesselPGAHolds.swift
//  EusoTrip — Vessel Operator · PGA Holds (Partner Government Agency import holds).
//
//  Verbatim SwiftUI port of "720 Vessel PGA Holds.svg" (Dark + Light).
//  Archetype: COMPLIANCE / gate-board — a blocking-vs-cleared hero, a 3-cell
//  gate KPI strip, a per-agency gate list with CFR citations, an ACE
//  message-set strip, and a tri-country PGA-regime band. Nav: COMPLIANCE current.
//
//  WIRING (line-confirmed on disk, server/routers/vesselShipments.ts):
//    getCBPEntryStatus EXISTS vesselShipments.ts:2807 (entry + holds[] · the
//        hero gate readiness · REAL).
//    getCBPAlerts      EXISTS vesselShipments.ts:2818 (ACE hold/alert feed · REAL).
//    getISFStatus      EXISTS vesselShipments.ts:2080 (ISF 10+2 dependency · REAL).
//    getVesselCompliance EXISTS vesselShipments.ts:2047 (compliance context · REAL).
//  STUB · named-gap (surfaced to the-oath): a dedicated per-agency PGA hold model
//    is not broken out of getVesselCompliance today → vesselShipments.getPGAHolds
//    {shipmentId} → {entryNumber,agencies:[{agency,program,cfr,status,ref}]} and
//    vesselShipments.filePGADisposition {shipmentId,agency,dispositionDocUrl,
//    confirm}. The FDA/EPA/USDA gate matrix reflects the live entry hold count
//    where present and is labeled STUB. transportMode=vessel; tri-country US·CA·MX.
//

import SwiftUI

private struct CBPHold720: Decodable {
    let holdType: String?; let agency: String?; let reason: String?; let appliedAt: String?
}
private struct CBPEntry720: Decodable {
    let entryNumber: String?; let status: String?; let holds: [CBPHold720]?
    let releaseDate: String?; let lastUpdated: String?
}
private struct CBPAlert720: Decodable, Identifiable {
    let alertId: String?; let alertType: String?; let severity: String?; let description: String?; let agency: String?
    var id: String { alertId ?? UUID().uuidString }
}
private struct ISFStatus720: Decodable { let status: String?; let warning: String? }

private struct PGAGate720: Identifiable {
    enum Status { case cleared, hold, exam }
    let id = UUID()
    let agency: String
    let program: String
    let cfr: String
    let status: Status
    let note: String
    let tint: Color
}

struct VesselPGAHoldsScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 7
    var entryNumber: String = "300-1438820-6"
    var importerId: String = "eusorone-technologies"

    var body: some View {
        Shell(theme: theme) {
            VesselPGAHoldsBody(shipmentId: shipmentId, entryNumber: entryNumber, importerId: importerId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselPGAHoldsBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let entryNumber: String
    let importerId: String

    @State private var entry: CBPEntry720? = nil
    @State private var alerts: [CBPAlert720] = []
    @State private var isf: ISFStatus720? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var filing = false

    // Canonical PGA agency set. USDA hold reflects the live entry hold count.
    private var liveHoldCount: Int { entry?.holds?.count ?? 1 }
    private var gates: [PGAGate720] {
        let usdaHeld = liveHoldCount > 0
        return [
            .init(agency: "FDA", program: "Prior Notice — foodstuff", cfr: "21 CFR 1.276 · PN 26-PN-7741103", status: .cleared, note: "may proceed", tint: Color(hex: 0x5AB0FF)),
            .init(agency: "EPA", program: "TSCA §13 import cert", cfr: "40 CFR 707.20 · positive certification", status: .cleared, note: "filed 2026-06-12", tint: Color(hex: 0x34D8A6)),
            .init(agency: "USDA", program: "APHIS — Lacey Act", cfr: "7 CFR 357 · PPQ 505 declaration pending", status: usdaHeld ? .hold : .cleared, note: usdaHeld ? "docs required" : "cleared", tint: Color(hex: 0xFF6F61)),
        ]
    }
    private var clearedCount: Int { gates.filter { $0.status == .cleared }.count }
    private var holdCount: Int { gates.filter { $0.status == .hold }.count }
    private var examCount: Int { gates.filter { $0.status == .exam }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    gapCard("Polling ACE PGA message set…", "getCBPEntryStatus · \(entryNumber)", warn: false)
                } else if let err = loadError {
                    gapCard("Entry status unavailable", err, warn: true)
                } else {
                    gateHero
                    kpiStrip
                    agencyGates
                    aceStrip
                    esang
                    regimeBand
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
                Text("✦ VESSEL OPERATOR · CUSTOMS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("MSC · USLGB").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            Text("PGA holds").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var gateHero: some View {
        RimCard720 {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("CBP ENTRY \(entry?.entryNumber ?? entryNumber) · ACE").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer()
                    Text(holdCount > 0 ? "\(holdCount) PGA HOLD" : "CLEARED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(holdCount > 0 ? Color(hex: 0xFF6F61) : Brand.success)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill((holdCount > 0 ? Brand.danger : Brand.success).opacity(0.14)))
                }.padding(.bottom, 12)
                Text("Shanghai CNSHA → Long Beach USLGB").font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                Text("B/L MSCUSH6840517 · 40'HC reefer · foodstuff entry").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary).padding(.top, 4)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft).frame(height: 7)
                        Capsule().fill(LinearGradient.primary).frame(width: geo.size.width * CGFloat(Double(clearedCount) / 3.0), height: 7)
                    }
                }.frame(height: 7).padding(.top, 12)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(clearedCount) / 3").font(.system(size: 22, weight: .heavy, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                    Text(holdCount > 0 ? "agencies cleared · \(holdCount) hold blocks release" : "agencies cleared · release ready")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                }.padding(.top, 10)
            }
        }
    }

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiCell("CLEARED", "\(clearedCount)", "FDA · EPA", Brand.success, hero: true)
            kpiCell("OPEN HOLD", "\(holdCount)", "USDA", Color(hex: 0xFF6F61), hero: false)
            kpiCell("CES EXAM", "\(examCount)", "no intensive", palette.textSecondary, hero: false)
        }
    }
    private func kpiCell(_ label: String, _ value: String, _ sub: String, _ accent: Color, hero: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .foregroundStyle(hero ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(accent))
                Text(sub).font(.system(size: 9, weight: .semibold)).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(hero ? AnyShapeStyle(LinearGradient(colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(hero ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint), lineWidth: hero ? 1.3 : 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var agencyGates: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("PGA AGENCY GATES · getVesselCompliance")
                Spacer()
                Text("getPGAHolds · STUB").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(gates.enumerated()), id: \.element.id) { idx, g in
                    gateRow(g)
                    if idx < gates.count - 1 { divider }
                }
            }
            .padding(.horizontal, Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private func gateRow(_ g: PGAGate720) -> some View {
        let (verdict, vColor): (String, Color) = {
            switch g.status {
            case .cleared: return ("CLEARED", Color(hex: 0x34D8A6))
            case .hold: return ("HOLD", Color(hex: 0xFF6F61))
            case .exam: return ("EXAM", Brand.warning)
            }
        }()
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(g.tint.opacity(0.14)).frame(width: 40, height: 40)
                if g.status == .hold {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(g.tint)
                } else {
                    Text(g.agency).font(.system(size: 11, weight: .heavy)).foregroundStyle(g.tint)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(g.program).font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                Text(g.cfr).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verdict).font(.system(size: 8.5, weight: .heavy)).tracking(0.4).foregroundStyle(vColor)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(vColor.opacity(0.14)))
                Text(g.note).font(EType.mono(.micro)).foregroundStyle(g.status == .hold ? vColor : palette.textSecondary)
            }
        }
        .padding(.vertical, 12)
    }

    private var aceStrip: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ACE PGA MESSAGE SET").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text("getCBPAlerts · \(alerts.count) alert\(alerts.count == 1 ? "" : "s") on file").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(holdCount > 0 ? "SW7501 · CR" : "SW7501 · OK")
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(holdCount > 0 ? Color(hex: 0xFF6F61) : Brand.success)
        }
        .padding(Space.s4).background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.tintNeutral))
    }

    private var esang: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ESANG · DISPOSITION PLAN")
            HStack(alignment: .top, spacing: 12) {
                OrbeSang(state: .idle, diameter: 32).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(holdCount > 0 ? "Upload PPQ 505 to clear USDA — release in ~3h" : "All PGA gates cleared — cargo may proceed")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text(isf?.warning ?? "Lacey declaration drafted from B/L wood-packaging line · 1 tap")
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var regimeBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("PGA CHANNEL · IMPORT COUNTRY REGIME")
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ccBadge("US", true)
                    Text("CBP ACE · FDA · EPA · USDA APHIS").font(.system(size: 10.5, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text("● ACTIVE").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.blue)
                }
                divider
                HStack(spacing: 8) {
                    ccBadge("CA", false)
                    Text("CBSA SWI · CFIA").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    ccBadge("MX", false)
                    Text("VUCEM · COFEPRIS").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Text("STANDBY").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }
    private func ccBadge(_ cc: String, _ active: Bool) -> some View {
        Text(cc).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(active ? .white : palette.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.tintNeutral)))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: filing ? "Filing…" : "File disposition",
                      action: { /* STUB · vesselShipments.filePGADisposition */ }, isLoading: filing)
            Button {
                // Contacts — the PGA broker + agency contacts (routed by nav).
            } label: {
                Text("Contacts").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 140, minHeight: 48).background(palette.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }
    private var divider: some View { Rectangle().fill(palette.borderFaint).frame(height: 1) }
    private func gapCard(_ title: String, _ detail: String, warn: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warn ? "exclamationmark.triangle.fill" : "checkmark.shield")
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

    private func load() async {
        loading = true; loadError = nil
        struct EntryIn: Encodable { let entryNumber: String }
        struct AlertsIn: Encodable { let importerId: String }
        struct ISFIn: Encodable { let shipmentId: Int }
        do {
            async let e: CBPEntry720? = EusoTripAPI.shared.query("vesselShipments.getCBPEntryStatus", input: EntryIn(entryNumber: entryNumber))
            async let a: [CBPAlert720]? = EusoTripAPI.shared.query("vesselShipments.getCBPAlerts", input: AlertsIn(importerId: importerId))
            async let i: ISFStatus720? = EusoTripAPI.shared.query("vesselShipments.getISFStatus", input: ISFIn(shipmentId: shipmentId))
            let (ee, aa, ii) = try await (e, a, i)
            self.entry = ee; self.alerts = aa ?? []; self.isf = ii
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

private struct RimCard720<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            content().padding(Space.s5)
        }.frame(maxWidth: .infinity)
    }
}

#Preview("720 · Vessel PGA Holds · Night") {
    VesselPGAHoldsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("720 · Vessel PGA Holds · Light") {
    VesselPGAHoldsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
