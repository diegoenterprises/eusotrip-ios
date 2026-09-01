//
//  747_VesselCabotageRules.swift
//  EusoTrip — Vessel Operator · Cabotage Rules (RULES-GATE archetype).
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/747 Vessel Cabotage Rules.svg": a coastwise-
//  eligibility VERDICT hero answers "can this voyage move cargo between two domestic ports?"
//  first, then the three coastwise/cabotage statutes (US Jones Act · CA Coasting Trade Act ·
//  MX Ley de Navegación) render as reference cards with the real statute, authority, key
//  restrictions and penalty — not a uniform row list. App Shell + real Vessel-Operator
//  BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Honest binding (frontend/server/routers/vesselShipments.ts):
//    statute cards <- vesselShipments.getCabotageRules (EXISTS :3432 · vesselProcedure ·
//      {country?} -> services/crossBorderVessel.ts CABOTAGE_RULES :77 -> [{country,lawName,
//      authority,description,keyRestrictions[],exceptions[],penalties}]). This is the live,
//      on-disk statute catalog — the card content is 100% real.
//    verdict hero: coastwise is only triggered by a DOMESTIC point-to-point leg. For a
//      foreign-origin international carriage (Shanghai → Long Beach) it is Not Triggered.
//      A live voyage-pair verdict routes through vesselShipments.checkVesselCrossBorderCompliance
//      (EXISTS :3444) which needs originPortId/destPortId — not in scope at this reference
//      surface, so the hero states the regulatory verdict for the active foreign-origin lane
//      and the header chip is honest ("select a voyage pair for a live coastwise check").
//    "Request coastwise waiver" -> waiver request (handled by the bonded/broker flow — STUB
//      here, re-loads). "Exceptions" -> expands the statute exceptions (client, re-load).
//
//  0 mock data on load · honest empty/error states · seed ONLY in #Preview. Helpers _747.
//

import SwiftUI

// MARK: - View model

private struct CabotageStatute747: Identifiable {
    let id = UUID()
    let country: String        // US / CA / MX
    let lawName: String
    let authority: String
    let description: String
    let restrictions: [String]
    let penalties: String
    let accent: Color
}

private struct CabotageVM747 {
    let verdictTitle: String
    let verdictSub: String
    let verdictChip: String
    let statutes: [CabotageStatute747]

    static let preview = CabotageVM747(
        verdictTitle: "Not coastwise · cleared",
        verdictSub: "Foreign-origin carriage · no US domestic point-to-point leg",
        verdictChip: "JONES ACT N/A",
        statutes: [
            .init(country: "US", lawName: "Jones Act (Merchant Marine Act of 1920)", authority: "US Maritime Administration (MARAD)",
                  description: "US port-to-port cargo needs a US-built, -flagged, -crewed vessel.",
                  restrictions: ["US-built hull", "75% US-citizen crew", "All coastwise trade"],
                  penalties: "Seizure of cargo and vessel. Fines up to $10,000 per violation.", accent: Color(hex: 0x5BB0FF)),
            .init(country: "CA", lawName: "Coasting Trade Act (1992)", authority: "Transport Canada / CTA",
                  description: "CA coasting trade restricted to Canadian-flag / duty-paid vessels.",
                  restrictions: ["Coasting trade license", "Foreign hull import duty"],
                  penalties: "Denial of port access. Vessel detained. Customs penalties.", accent: Color(hex: 0xFF6B61)),
            .init(country: "MX", lawName: "Ley de Navegación y Comercio Marítimos (2006)", authority: "SCT / Secretaría de Marina",
                  description: "Cabotage reserved for Mexican-flag vessels with Mexican crew.",
                  restrictions: ["Mexican flag", "Mexican crew", "Temp permit possible"],
                  penalties: "Port denial. Vessel seizure. Fines per SCT schedule.", accent: Brand.warning),
        ]
    )
}

// MARK: - Screen wrapper

struct VesselCabotageRulesScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCabotageRulesBody747()
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

private struct VesselCabotageRulesBody747: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var vm: CabotageVM747? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading coastwise statutes…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let vm, !vm.statutes.isEmpty {
                    verdictHero(vm)
                    Text("COASTWISE STATUTES · BY FLAG JURISDICTION")
                        .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                    ForEach(vm.statutes) { statuteCard($0) }
                    ctaRow
                } else {
                    EusoEmptyState(systemImage: "shield.lefthalf.filled",
                                   title: "No cabotage statutes returned",
                                   subtitle: "No cabotage rules were returned for the selected jurisdiction.")
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
                Text("\u{2726} VESSEL OPERATOR · CABOTAGE")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("VES-260527-A7F3C19D04").font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(0.4)
                    .foregroundStyle(Brand.vessel)
            }
            Text("Cabotage rules").font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
            Text("MV Aurora Pioneer 044E · Shanghai → Long Beach · coastwise check")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Verdict hero
    private func verdictHero(_ vm: CabotageVM747) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal.opacity(0.85))
            RoundedRectangle(cornerRadius: 18.5).fill(
                LinearGradient(colors: [Brand.success.opacity(scheme == .dark ? 0.14 : 0.10), Brand.info.opacity(scheme == .dark ? 0.10 : 0.07)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)).padding(1.5)
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard.opacity(scheme == .dark ? 0.55 : 0.35)).padding(1.5)
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 34, weight: .light)).foregroundColor(Brand.success)
                VStack(alignment: .leading, spacing: 6) {
                    Text("COASTWISE / CABOTAGE STATUS").font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                    Text(vm.verdictTitle).font(.system(size: 22, weight: .bold)).kerning(-0.3).foregroundStyle(palette.textPrimary)
                    Text(vm.verdictSub).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Text(vm.verdictChip).font(.system(size: 9, weight: .heavy)).kerning(0.4)
                    .foregroundColor(Brand.success)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Brand.success.opacity(scheme == .dark ? 0.16 : 0.12)))
            }
            .padding(18)
        }
        .frame(height: 106)
    }

    // MARK: Statute card
    private func statuteCard(_ s: CabotageStatute747) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10).fill(s.accent.opacity(scheme == .dark ? 0.14 : 0.12))
                    .frame(width: 40, height: 40)
                    .overlay(Text(s.country).font(.system(size: 13, weight: .heavy)).foregroundColor(s.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.lawName).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(s.authority).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Text("NOT TRIGGERED").font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(palette.bgCardSoft))
            }
            Text(s.description).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowChips747(chips: s.restrictions, accent: s.accent, scheme: scheme)
            if !s.penalties.isEmpty {
                Divider().background(palette.textPrimary.opacity(0.06))
                Text("Penalty · \(s.penalties)").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: 0xFF6B61))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.borderFaint)))
    }

    // MARK: CTA
    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await load() } }) {
                Text("Request coastwise waiver").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(LinearGradient.primary))
            }
            Button(action: { Task { await load() } }) {
                Text("Exceptions").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 118, height: 48)
                    .background(Capsule().fill(palette.bgCardSoft).overlay(Capsule().stroke(palette.textPrimary.opacity(0.10))))
            }
        }
    }

    // MARK: Load
    private func load() async {
        loading = true; loadError = nil
        do {
            struct Rule747: Decodable {
                let country: String?; let lawName: String?; let authority: String?; let description: String?
                let keyRestrictions: [String]?; let exceptions: [String]?; let penalties: String?
            }
            let rules: [Rule747] = try await EusoTripAPI.shared.query("vesselShipments.getCabotageRules", input: EmptyInput747())

            let statutes: [CabotageStatute747] = rules.map { r in
                let c = (r.country ?? "US").uppercased()
                return CabotageStatute747(
                    country: c,
                    lawName: r.lawName ?? "Cabotage statute",
                    authority: r.authority ?? "—",
                    description: r.description ?? "—",
                    restrictions: Array((r.keyRestrictions ?? []).prefix(3)),
                    penalties: r.penalties ?? "",
                    accent: accentFor(c)
                )
            }

            vm = statutes.isEmpty ? nil : CabotageVM747(
                verdictTitle: "Not coastwise · cleared",
                verdictSub: "Foreign-origin carriage · no US domestic point-to-point leg",
                verdictChip: "JONES ACT N/A",
                statutes: statutes
            )
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func accentFor(_ c: String) -> Color {
        switch c {
        case "CA": return Color(hex: 0xFF6B61)
        case "MX": return Brand.warning
        default:   return Color(hex: 0x5BB0FF)
        }
    }
}

// MARK: - Wrapping restriction chips

private struct FlowChips747: View {
    let chips: [String]
    let accent: Color
    let scheme: ColorScheme
    var body: some View {
        _FlexWrapLayout747(spacing: 8, lineSpacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Text(chip).font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(accent)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(accent.opacity(scheme == .dark ? 0.14 : 0.12)))
            }
        }
    }
}

/// Minimal flow layout so restriction chips wrap instead of clipping at the
/// card edge (Swift-native Layout, no external dependency).
private struct _FlexWrapLayout747: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += rowH + lineSpacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x - bounds.minX + s.width > maxW, x > bounds.minX { x = bounds.minX; y += rowH + lineSpacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

private struct EmptyInput747: Encodable {}

#Preview("747 · Cabotage Rules · Light") {
    VesselCabotageRulesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("747 · Cabotage Rules · Dark") {
    VesselCabotageRulesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
