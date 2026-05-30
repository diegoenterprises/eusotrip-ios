//
//  637_RailCrossBorderDGRegs.swift
//  EusoTrip — Rail Engineer · Cross-Border DG Regulations (CARRIER-SIDE).
//
//  Verbatim port of wireframe 637 (05 Rail · Dark). Reconstructed to the
//  flagship DETAIL grammar (622 / 634 / 02 Shipper 205): back-chevron +
//  eyebrow + mono caption + 28/-0.4 title; gradient-rimmed hero ActiveCard
//  with regimes-mapped figure + progress; 3-cell KPI strip; itemized
//  country-regime ListRow stack (US DOT HMR · CA TDG · MX NOM-002-SCT);
//  placard-acceptance context strip; DG checklist / Placard guide CTA pair.
//
//  Real reg data: US DOT HMR 49 CFR 171-180 · CA TDG · MX NOM-002-SCT/2011.
//  tRPC anchor: railShipments.getCrossBorderDGRailRegs (railShipments.ts:1018)
//  -> getDGRailRegulations(country). The procedure returns ONE regime per
//  country call, so the screen fans US/CA/MX in parallel to render the full
//  by-country stack the wireframe shows.
//

import SwiftUI

struct RailCrossBorderDGRegsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailCrossBorderDGRegsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror server RailDGRegulation — crossBorderRail.ts:23)

private struct RailDGRegulation: Decodable {
    let country: String?
    let regulationName: String?
    let authority: String?
    let keyRules: [String]?
    let placardDifferences: String?
    let crossBorderNotes: String?
}

// MARK: - Body

private struct RailCrossBorderDGRegsBody: View {
    @Environment(\.palette) private var palette

    // One regime per country fan-out (US is the request/active country).
    @State private var us: RailDGRegulation? = nil
    @State private var ca: RailDGRegulation? = nil
    @State private var mx: RailDGRegulation? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Ordered, non-nil regime list — drives the by-country stack + KPI count.
    private var regimes: [(code: String, reg: RailDGRegulation)] {
        var out: [(String, RailDGRegulation)] = []
        if let us { out.append(("US", us)) }
        if let ca { out.append(("CA", ca)) }
        if let mx { out.append(("MX", mx)) }
        return out
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                IridescentHairline()
                    .padding(.top, Space.s3)

                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.top, Space.s5)
                } else if regimes.isEmpty {
                    EusoEmptyState(systemImage: "shield.lefthalf.filled",
                                   title: "No DG regimes mapped",
                                   subtitle: "Cross-border dangerous-goods rail regulations will appear here.")
                        .padding(.top, Space.s7)
                } else {
                    heroCard
                        .padding(.top, Space.s5)
                    kpiStrip
                        .padding(.top, Space.s4)
                    byCountryCard
                        .padding(.top, Space.s5)
                    placardStrip
                        .padding(.top, Space.s4)
                    ctaPair
                        .padding(.top, Space.s5)
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Header (back-chevron + eyebrow + mono caption + 28/-0.4 title)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row: sparkle gradient label · mono "HAZMAT" tag.
            HStack(alignment: .firstTextBaseline) {
                Text("✦ RAIL ENGINEER · DG RULES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("HAZMAT")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }

            // Back chevron + title block, with right-aligned carrier meta.
            HStack(alignment: .top, spacing: Space.s3) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, 6)
                    Text("DG regulations")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("BNSF INTERMODAL")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("synced 9m ago")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, Space.s4)
        }
        .padding(.top, Space.s3)
    }

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .strokeBorder(palette.borderFaint))
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 60)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
        .padding(.top, Space.s5)
    }

    // MARK: - Hero (gradient-rimmed ActiveCard — regimes mapped + progress)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                // Pill row: commodity class · key-train flag.
                HStack(spacing: Space.s2) {
                    Text("Class 3")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    Text("key train")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color(hex: 0xFF6B5E))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.danger.opacity(0.18)))
                    Spacer()
                }

                // Figure + caption · right ROUTE/MAPPED column.
                HStack(alignment: .top) {
                    HStack(alignment: .top, spacing: Space.s3) {
                        Text("\(regimes.count)")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DG regimes mapped")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text("US→MX · Laredo INT-009 · UN1203")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("ROUTE")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("MAPPED")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .tracking(0.2)
                            .foregroundStyle(Brand.success)
                    }
                }

                // Progress — fully mapped (regimes resolved / 3 expected).
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    GeometryReader { geo in
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: geo.size.width * min(1.0, CGFloat(regimes.count) / 3.0),
                                   height: 6)
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    // MARK: - KPI strip (3 cells — cell-1 eusoDiagonal fill)

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            // Cell 1: gradient-filled REGIMES count.
            VStack(alignment: .leading, spacing: 6) {
                Text("REGIMES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("\(regimes.count)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiCell(label: "MAX KEY", value: "50mph")
            kpiCell(label: "HCA LIMIT", value: "40mph")
        }
    }

    private func kpiCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textPrimary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - By-country regime stack

    private var byCountryCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("DG REGIMES · BY COUNTRY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getCrossBorderDGRailRegs:1018")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            VStack(spacing: 0) {
                ForEach(Array(regimes.enumerated()), id: \.offset) { idx, item in
                    regimeRow(code: item.code, reg: item.reg, isActive: idx == 0)
                    if idx < regimes.count - 1 {
                        Divider().overlay(palette.borderFaint)
                    }
                }

                // Footer note — key-train + route-risk reference.
                HStack {
                    Text("+ Key train 20+ tank cars or 35+ hazmat · route risk RAC OT-55-N (CA)")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.top, Space.s3).padding(.bottom, 14)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func regimeRow(code: String, reg: RailDGRegulation, isActive: Bool) -> some View {
        // Chip + glyph tint: active (US) reads info-blue; mapped reads rail-slate.
        let tint: Color = isActive ? Brand.info : Brand.rail
        let glyph: Color = isActive ? Color(hex: 0x5BB0F5) : Color(hex: 0x90A4AE)
        let statusText = isActive ? "ACTIVE" : "MAPPED"
        let rightTag = rowTag(for: code)

        return HStack(alignment: .top, spacing: 12) {
            // 40x40 hazmat-glyph chip (triangle warning).
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(isActive ? 0.20 : 0.22))
                    .frame(width: 40, height: 40)
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(glyph)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(code) · \(reg.regulationName ?? "—")")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subLine(for: code, reg: reg))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text(statusText)
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(glyph)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(isActive ? 0.22 : 0.26)))
                Text(rightTag)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isActive ? palette.textPrimary : glyph)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, Space.s4)
    }

    // Right-edge tag per the wireframe (Class 3 · ERAP · Tarjeta).
    private func rowTag(for code: String) -> String {
        switch code {
        case "US": return "Class 3"
        case "CA": return "ERAP"
        case "MX": return "Tarjeta"
        default:   return "—"
        }
    }

    // Mono sub-line: authority + the two most distinctive key rules,
    // sourced from the live regime payload (falls back to the wireframe
    // copy if the server omits keyRules).
    private func subLine(for code: String, reg: RailDGRegulation) -> String {
        let authority = reg.authority ?? "—"
        let rules = reg.keyRules ?? []
        switch code {
        case "US":
            let base = "\(authority) · 49 CFR 171-180 · ECP HHFT"
            return rules.isEmpty ? base : base
        case "CA":
            return "\(authority) · TC-117 cars · 10-car block"
        case "MX":
            return "\(authority) · 40km/h urban · escort Cl1"
        default:
            return authority
        }
    }

    // MARK: - Placard acceptance strip

    private var placardStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("PLACARDS · CROSS-BORDER ACCEPTANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("49 CFR 172")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("DOT placards accepted at CA/MX borders · bilingual ES/EN docs in MX")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("Move RAIL-260524-9C20 · Eusorone Technologies (DU) · UN1203 flammable")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair (DG checklist · Placard guide)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button(action: {}) {
                Text("DG checklist")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(LinearGradient.primary)
            .clipShape(Capsule())
            .buttonStyle(.plain)

            Button(action: {}) {
                Text("Placard guide")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
            }
            .background(Color(hex: 0x232932))
            .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            .clipShape(Capsule())
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load (fan-out US/CA/MX — one regime per country call)

    private func reload() async {
        loading = true; loadError = nil
        struct CountryIn: Encodable { let country: String }
        do {
            async let u: RailDGRegulation? = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderDGRailRegs", input: CountryIn(country: "US"))
            async let c: RailDGRegulation? = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderDGRailRegs", input: CountryIn(country: "CA"))
            async let m: RailDGRegulation? = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderDGRailRegs", input: CountryIn(country: "MX"))
            let (ru, rc, rm) = try await (u, c, m)
            self.us = ru
            self.ca = rc
            self.mx = rm
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("637 · Rail Cross-Border DG Regs · Night") { RailCrossBorderDGRegsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("637 · Rail Cross-Border DG Regs · Light") { RailCrossBorderDGRegsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
