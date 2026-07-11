//
//  729_VesselDualUseScreening.swift
//  EusoTrip — Vessel Operator · HS Dual-Use Export-Control Screening.
//
//  Faithful 1:1 native port of "729 Vessel HS Dual-Use Screening · Dark/Light".
//  SCREENING RISK-GATE archetype: an HS→ECCN→EAR classification chain + a 5-gate
//  export-control screening checklist (dual-use cross-ref, ECCN/EAR control,
//  denied-party, end-use, embargo) + an origin export-control-authority band.
//
//  HONEST BINDING (server/routers/vesselShipments.ts):
//    · vesselShipments.getVesselShipments — REAL shipment + commodity being screened.
//  HONEST GAP (proposed to the-oath): there is NO dual-use / ECCN / EAR
//  classifier or denied-party screening router today (ECCN appears only as a
//  string literal server-wide). The classification chain + 5 gates + verdict
//  surface as explicit awaiting states over the REAL commodity — never a
//  fabricated CLEAR/HOLD verdict (a wrong CLEAR is an export-control violation).
//  hold is human-gated + confirm:true + audited. RBAC vesselProcedure.
//

import SwiftUI

private struct VesselShipmentList729: Decodable { let shipments: [VesselShipmentRow729]? }
private struct VesselShipmentRow729: Decodable {
    let id: Int?
    let bookingNumber: String?
    let commodity: String?
    let cargoType: String?
    let hazmatClass: String?
    let numberOfContainers: Int?
}

private struct ScreenGate729: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
}

struct VesselDualUseScreeningScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselDualUseScreeningBody() } nav: {
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

private struct VesselDualUseScreeningBody: View {
    @Environment(\.palette) private var palette

    @State private var booking: VesselShipmentRow729? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil

    private let gates: [ScreenGate729] = [
        .init(name: "HS dual-use cross-reference", detail: "commodity vs EU Annex I / Wassenaar list"),
        .init(name: "ECCN / EAR control list", detail: "Commerce Control List category + §744 review"),
        .init(name: "Denied / sanctioned party", detail: "consignee vs OFAC SDN + BIS Entity List"),
        .init(name: "End-use / end-user", detail: "stated end-use vs prohibited end-uses"),
        .init(name: "Embargo destination", detail: "discharge country vs embargoed list"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if booking == nil {
                    EusoEmptyState(
                        systemImage: "checkmark.shield",
                        title: "No shipment to screen",
                        subtitle: "Export-control screening activates once a vessel booking has a commodity to classify.")
                } else {
                    heroCard
                    classificationChain
                    gateChecklist
                    authorityBand
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
                    Text("VESSEL OPERATOR · SCREENING")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("BIS · EAR").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            Text("Dual-use screen").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            ForEach([124, 74, 200], id: \.self) { h in
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: CGFloat(h))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(Color(hex: 0x141928)).padding(1.5)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(booking?.bookingNumber ?? "—") · \(booking?.numberOfContainers ?? 0) container\((booking?.numberOfContainers ?? 0) == 1 ? "" : "s")")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color(hex: 0xAAB2BB)).lineLimit(1)
                    Spacer()
                    StatusPill(text: "Screen pending", kind: .warning)
                }
                Text("Export-control screening").font(.system(size: 16, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("HS → ECCN → control list → party screen").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: 0xAAB2BB))
                Text("\(gates.count) gates awaiting classifier · hold loading until cleared")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            .padding(Space.s5)
        }
        .frame(minHeight: 124)
    }

    // HS → ECCN → EAR classification chain
    private var classificationChain: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("CLASSIFICATION CHAIN · screened line", ref: "commodity HS", gap: false)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(commodityLine).font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Spacer()
                    Text("DUAL-USE?").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                }
                HStack(spacing: 8) {
                    chainPill("HS code", filled: true)
                    chainArrow
                    chainPill("ECCN", filled: false)
                    chainArrow
                    chainPill("EAR §744", filled: false)
                }
                Text("HS → ECCN mapping awaits screening.dualUseClassify — commodity is real, codes are not fabricated.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
            .padding(16).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private func chainPill(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .heavy))
            .foregroundStyle(filled ? .white : palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Group { if filled { LinearGradient.primary } else { palette.bgCardSoft } })
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var chainArrow: some View {
        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
    }
    private var commodityLine: String {
        firstNonEmpty(booking?.commodity, booking?.cargoType) ?? "Commodity"
    }

    // 5-gate screening checklist
    private var gateChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SCREENING CHECKS · \(gates.count) gates", ref: "screening.dualUseClassify", gap: true)
            VStack(spacing: 0) {
                ForEach(Array(gates.enumerated()), id: \.element.id) { idx, g in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Brand.warning, lineWidth: 2).frame(width: 18, height: 18)
                            Image(systemName: "clock").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(g.detail).font(.system(size: 9)).foregroundStyle(palette.textTertiary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("AWAIT").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.warning)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    if idx < gates.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16) }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            Text("Gate verdicts (clear/flag) await screening.dualUseClassify — no gate is marked CLEAR without a real classifier result.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }

    private var authorityBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("EXPORT-CONTROL AUTHORITY", ref: "screening.getECCN·country", gap: false)
            CountryBand729(rows: [
                .init(code: "US", line: "US · BIS · EAR / Commerce Control List", active: true),
                .init(code: "CA", line: "CA · GAC · Export Control List (ECL)", active: false),
                .init(code: "MX", line: "MX · Secretaría de Economía · dual-use", active: false),
            ])
        }
    }

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Request license", action: {
                actionMessage = "Requesting a BIS export license + holding loading awaits screening.holdForExportControl (blocks loading, confirm-gated + audited + WS broadcast)."
            })
            Button { actionMessage = "Override requires a real classifier verdict first — screening.dualUseClassify not yet on the web peer." } label: {
                Text("Override").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
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
        struct ListInput: Encodable { let limit: Int; let offset: Int }
        do {
            let list: VesselShipmentList729 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipments", input: ListInput(limit: 5, offset: 0))
            booking = list.shipments?.first { $0.id != nil }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            booking = nil
        }
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { v -> String? in
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty == false) ? t : nil
        }.first
    }
}

private struct CountryBand729: View {
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

#Preview("729 · Vessel Dual-Use Screening · Night") { VesselDualUseScreeningScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("729 · Vessel Dual-Use Screening · Light") { VesselDualUseScreeningScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
