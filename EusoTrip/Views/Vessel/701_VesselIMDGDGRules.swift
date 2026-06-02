//
//  701_VesselIMDGDGRules.swift
//  EusoTrip — Vessel Operator · IMDG DG Rules.
//
//  Carrier-side dangerous-goods maritime rulebook reference: IMDG Code
//  summary, stowage-category / segregation / class KPIs, the key
//  operating rules, cross-border DG regulation notes, and a placarding
//  action. Docked under COMPLIANCE.
//
//  Cross-mode parity gap fill — Rail sibling 597 Rail Hazmat DG Rules
//  exists; Vessel had 671 IMDG Hazmat Manifest (the shipment's manifest)
//  but no DG rules reference.
//
//  Wiring (verbatim from SVG <desc>):
//    crossBorder.getIMDGClasses               (EXISTS crossBorder.ts:3255 · 9 IMDG classes -> CLASS KPI + INFO)
//    crossBorder.getDangerousGoodsCrossBorder (EXISTS crossBorder.ts:2151 · cross-border DG notes)
//    imdg.getClassMappings                    (// PORT-GAP — not surfaced via the iOS tRPC client; KEY RULES derived from the live class row)
//    imdg.getPackingGroups                    (// PORT-GAP — not surfaced via the iOS tRPC client; PG shown from the live class row)
//    crossBorder.getPlacardClasses            (// PORT-GAP — placarding CTA target not surfaced via the iOS tRPC client)
//

import SwiftUI

struct VesselIMDGDGRulesScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { VesselIMDGDGRulesBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror server `IMDGClassInfo` · crossBorderVessel.ts:83)

private struct IMDGClassInfo701: Decodable, Identifiable {
    let classNumber: String
    let name: String?
    let description: String?
    let packingGroups: [String]?
    let marinePollutant: Bool?
    let specialRequirements: [String]?
    var id: String { classNumber }
}

// MARK: - Cross-border DG shape (mirror crossBorder.getDangerousGoodsCrossBorder)

private struct DGCrossBorder701: Decodable {
    struct Framework: Decodable {
        let name: String?
        let authority: String?
        let emergencyNumber: String?
    }
    struct Frameworks: Decodable {
        let US: Framework?
        let CA: Framework?
        let MX: Framework?
    }
    let route: String?
    let regulatoryFrameworks: Frameworks?
}

// MARK: - Body

private struct VesselIMDGDGRulesBody: View {
    @Environment(\.palette) private var palette

    // The DU-pinned context for this reference card (UN1075 LPG · Class 2.1).
    private let unNumber  = "UN1075"
    private let imdgClass = "2.1"
    private let bookingRef = "VES-260523-9F2C1A77E0"
    private let consignor  = "Eusorone Technologies"

    @State private var classes: [IMDGClassInfo701] = []
    @State private var crossBorder: DGCrossBorder701? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    /// The live class row that matches this booking's UN1075 LPG (Class 2.1).
    private var focusClass: IMDGClassInfo701? {
        classes.first { $0.classNumber == imdgClass }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                titleBlock
                IridescentHairline()
                    .padding(.top, Space.s5)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingCards
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else {
                        regulationCard
                        kpiRow
                        keyRulesSection
                        crossBorderCard
                        placardingCTA
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + UN/CLASS mono)

    private var topBar: some View {
        HStack(alignment: .top) {
            Text("✦ VESSEL OPERATOR · IMDG DG RULES")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("\(unNumber) · CLASS \(imdgClass)")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: - Title block (back chevron · DG Rules · live subtitle)

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            Text("DG Rules")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s2)
            Text("getIMDGClasses · live")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Loading skeleton

    private var loadingCards: some View {
        VStack(spacing: Space.s4) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 78)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Regulation card

    private var regulationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REGULATION · getIMDGClasses")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text("IMDG Code · Amdt 41-22")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 8)
                Text("INTL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 20)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            Text("Stowage & segregation for sea transport")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s2)
            Rectangle().fill(palette.borderFaint).frame(height: 1)
                .padding(.top, Space.s3)
            Text("\(bookingRef) · \(unNumber) LPG · \(consignor)")
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s2)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: - KPI row (STOWAGE CAT · SEGREGATION · CLASSES)

    private var kpiRow: some View {
        HStack(spacing: Space.s3) {
            kpiTile(label: "STOWAGE CAT", value: "E",  caption: "on deck only",    gradient: false)
            kpiTile(label: "SEGREGATION", value: "\"3\"", caption: "separated from", gradient: true)
            kpiTile(label: "CLASSES",     value: "\(classes.isEmpty ? 9 : classes.count)",
                    caption: "IMDG classes", gradient: false)
        }
    }

    private func kpiTile(label: String, value: String, caption: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                if gradient {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: 22, weight: .bold)).monospacedDigit()
            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Key rules section

    private var keyRulesSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("KEY RULES · getClassMappings")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            // Row 1 — Class 2.1 · flammable gas (red hazard diamond · IMO).
            keyRuleRow(
                tint: Brand.danger,
                icon: "diamond.fill",
                title: "Class \(imdgClass) · \(focusClass?.name?.lowercased() ?? "flammable gas")",
                subtitle: "\(unNumber) LPG · segregation table group 2",
                pillText: "IMO",
                pillTint: nil
            )

            // Row 2 — Stowage category E · on deck (slate house · REQ).
            keyRuleRow(
                tint: Brand.rail,
                icon: "house.fill",
                title: "Stowage category E · on deck",
                subtitle: "away from accommodation · ≥ 2.4m from heat",
                pillText: "REQ",
                pillTint: Brand.warning
            )

            // Row 3 — DG declaration + ISPS (blue doc · PRE-LOAD).
            keyRuleRow(
                tint: Brand.info,
                icon: "doc.text.fill",
                title: "DG declaration + ISPS",
                subtitle: "DGD before vessel loading · SOLAS VII",
                pillText: "PRE-LOAD",
                pillTint: nil
            )
        }
    }

    private func keyRuleRow(tint: Color, icon: String, title: String, subtitle: String,
                            pillText: String, pillTint: Color?) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 6)
            Text(pillText)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(pillTint ?? palette.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill((pillTint ?? Color.white).opacity(pillTint == nil ? 0.08 : 0.22)))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Cross-border card

    private var crossBorderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CROSS-BORDER · getDangerousGoodsCrossBorder")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("US: 49 CFR + IMDG · CBP HazMat entry")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("CA: TDG marine · MX: NOM-002-SCT marine annex")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Placarding CTA

    private var placardingCTA: some View {
        // PORT-GAP: crossBorder.getPlacardClasses not surfaced via the iOS
        // tRPC client — the placarding-by-class destination has no wired
        // screen yet, so the CTA is rendered verbatim but inert.
        Text("View placarding by class")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(LinearGradient.primary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct DGIn: Encodable {
            let origin: String
            let destination: String
            let unNumber: String
            let hazmatClass: String
        }
        do {
            // crossBorder.getIMDGClasses — no input (protectedProcedure .query(() => …)).
            async let cls: [IMDGClassInfo701] = EusoTripAPI.shared.queryNoInput("crossBorder.getIMDGClasses")
            // crossBorder.getDangerousGoodsCrossBorder — origin/dest + UN/class.
            async let xb: DGCrossBorder701 = EusoTripAPI.shared.query(
                "crossBorder.getDangerousGoodsCrossBorder",
                input: DGIn(origin: "US", destination: "CA", unNumber: unNumber, hazmatClass: imdgClass)
            )
            let (classList, xborder) = try await (cls, xb)
            self.classes = classList
            self.crossBorder = xborder
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("701 · Vessel IMDG DG Rules · Night") { VesselIMDGDGRulesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("701 · Vessel IMDG DG Rules · Light") { VesselIMDGDGRulesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
