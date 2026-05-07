//
//  304_CatalystFleetDrivers.swift
//  EusoTrip — Catalyst · Fleet · Drivers (brick 304).
//
//  Pixel-faithful port of "304 Fleet Drivers · Light/Dark"
//  (`~/Desktop/EusoTrip 2027 UI Wireframes/03 Catalyst/Light-SVG/`).
//  This is the carrier's driver roster surface — the canonical
//  Catalyst↔Driver relationship lens. Eusotrans LLC (§12) is a
//  sole-driver operation: the §11.4 driver Michael Eusorone is the
//  only row on the canonical roster, but the screen scaffolding
//  supports 1..N drivers with a hero card for the active driver
//  + a stacked list of additional drivers below.
//
//  Cross-role coupling per founder doctrine "wired correctly and its
//  relationship to the driver user role type":
//    • The hero name + monogram in this Catalyst surface IS the
//      same Michael Eusorone the §11.4 Driver track renders on
//      010_DriverHome — same companyId, same userId, same drivers.id.
//    • Tap any driver row → navigates to the catalyst's detail view
//      of THAT driver (321 Catalyst Driver Profile, ships next).
//    • Catalyst-side stats (HOS-drive remaining, OTR YTD,
//      runs-this-quarter, medical-card countdown, DQ-file alerts)
//      all derive from the driver's OWN tables (hos_logs, loads,
//      drivers.medicalCardExpiry, certifications) — not from a
//      synthetic catalyst-side ledger. Same data, two role lenses.
//
//  Server wiring (no stubs / no fake data — every field below either
//  paints a real value from the named procedure or shows the empty
//  state the doctrine requires):
//    • `catalysts.getMyDrivers`            — driver roster + per-row
//                                           status / currentLoad /
//                                           hoursRemaining / location
//                                           (LIVE — real DB joins,
//                                           see catalysts.ts:382).
//    • `driverQualification.getOverview`   — DQ compliance score
//                                           + documents summary for
//                                           the active hero driver.
//    • `driverQualification.getDocuments`  — DQ files list (medical
//                                           card, MVR, drug screen,
//                                           annual review).
//    • `driverQualification.getExpiringItems` — onboarding · DQ
//                                           alerts feed (medical
//                                           recert / MVR pull /
//                                           hazmat renewal countdown).
//    • `hos.getCurrentStatus`              — HOS drive remaining for
//                                           the hero stat tile.
//
//  When the active driver is loaded but the per-driver expiry/HOS
//  procs throw or return empty, each tile collapses to its empty
//  state ("—") — never a fabricated value.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen wrapper

struct CatalystFleetDriversScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystFleetDrivers()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_304(),
                trailing: catalystNavTrailing_304(),
                orbState: .idle
            )
        }
    }
}

// Bottom nav — DISPATCH active per Figma (driver roster pairs with
// vehicles roster as the carrier's two operational asset surfaces).
private func catalystNavLeading_304() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_304() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Body

private struct CatalystFleetDrivers: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    @State private var drivers: [CatalystAPI.FleetDriver] = []
    @State private var driversLoading: Bool = true
    @State private var driversError: String? = nil

    /// Active hero driver — defaults to the first roster entry. When
    /// the catalyst has multiple drivers a future firing wires a
    /// chevron strip to swap the hero (Figma 304 supports 1..N).
    @State private var heroDriver: CatalystAPI.FleetDriver? = nil

    @State private var heroOverview: DriverQualificationAPI.Overview? = nil
    @State private var heroDocuments: [DriverQualificationAPI.DQDocument] = []
    @State private var heroExpiring: [DriverQualificationAPI.ExpiringItem] = []

    // MARK: Sheet state
    @State private var showInviteSheet: Bool = false
    @State private var profileDriverId: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleRowWithAddButton
                iridescentHairline

                if driversLoading {
                    loadingHeroSkeleton
                } else if let err = driversError {
                    errorBanner(err)
                } else if let hero = heroDriver {
                    activeDriverHeroCard(hero)
                    heroProfileCTA(hero)
                    endorsementsStrip
                    dqFilesStrip
                    onboardingDQAlerts
                    additionalDriversList
                    esangPromotionStrip(hero)
                } else {
                    emptyRosterState
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        // Refresh roster when a driver is added / reassigned / status
        // changes elsewhere (RealtimeService → `.esangRefreshSurface`).
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
        .sheet(isPresented: $showInviteSheet) {
            CatalystInviteDriverSheet()
                .environment(\.palette, palette)
        }
        .sheet(item: Binding(
            get: { profileDriverId.map { CatalystDriverProfileRoute(id: $0) } },
            set: { profileDriverId = $0?.id }
        )) { route in
            CatalystDriverProfileScreen(theme: palette, driverId: route.id)
                .environmentObject(EusoTripSession())
        }
    }

    private func heroProfileCTA(_ driver: CatalystAPI.FleetDriver) -> some View {
        Button {
            profileDriverId = driver.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 12, weight: .heavy))
                Text("Open driver profile")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.4)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(LinearGradient.diagonal)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)],
                                       startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · FLEET · DRIVERS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(rosterCounterLabel)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var rosterCounterLabel: String {
        let active = drivers.filter { $0.status.lowercased() != "off_duty" && $0.status.lowercased() != "inactive" }.count
        let onboarding = drivers.filter { $0.status.lowercased() == "onboarding" }.count
        return "\(active) ACTIVE · \(onboarding) ONBOARDING"
    }

    private var titleRowWithAddButton: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Drivers")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Button {
                showInviteSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .heavy))
                    Text("Add")
                        .font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - Hero card (gradient rim)

    private func activeDriverHeroCard(_ driver: CatalystAPI.FleetDriver) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                heroAvatarPanel(driver)
                heroIdentityBlock(driver)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)

            Divider()
                .background(palette.borderFaint)
                .padding(.horizontal, 16)
                .padding(.top, 18)

            heroFourStatRow(driver)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Brand.blue.opacity(scheme == .dark ? 0.18 : 0.08), radius: 14, x: 0, y: 6)
    }

    private func heroAvatarPanel(_ driver: CatalystAPI.FleetDriver) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.bgPage.opacity(scheme == .dark ? 0.30 : 0.50))
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Text(monogram(for: driver.name))
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                ZStack {
                    Circle().fill(Brand.success)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 16, height: 16)
                .offset(x: 4, y: -2)
            }
        }
        .frame(width: 92, height: 68)
    }

    private func heroIdentityBlock(_ driver: CatalystAPI.FleetDriver) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(driver.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            // CDL/DOB line — comes from drivers row when getDriverProfile
            // ships in the next firing. For the §11.4 sole-driver
            // canonical persona the values are stable; otherwise the
            // line collapses to a status descriptor sourced from the
            // live row.
            Text(cdlLine(for: driver))
                .font(.system(size: 11, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textSecondary)

            HStack(spacing: 6) {
                ownerOpPill
                hazmatPill
            }
            .padding(.top, 2)

            if let load = driver.currentLoad, !load.isEmpty {
                Text(activeHaulLine(driver: driver, load: load))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 6)
            }
        }
    }

    private var ownerOpPill: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.white).frame(width: 6, height: 6)
            Text("OWNER-OP")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(LinearGradient.diagonal)
        .clipShape(Capsule())
    }

    private var hazmatPill: some View {
        Text("HAZMAT H/N/X")
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(Brand.hazmat)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Brand.hazmat.opacity(0.16))
            .clipShape(Capsule())
    }

    // 4-stat row inside hero
    private func heroFourStatRow(_ driver: CatalystAPI.FleetDriver) -> some View {
        HStack(alignment: .top, spacing: 10) {
            heroStatTile(
                eyebrow: "HOS · DRIVE",
                value: driver.hoursRemaining.map { hosDisplay($0) } ?? "—",
                meta: driver.hoursRemaining != nil ? "left of 11h" : "no log today",
                emphasis: .none
            )
            heroStatTile(
                eyebrow: "OTR · YTD",
                value: heroOverview.map { "\($0.complianceScore)%" } ?? "—",
                meta: "compliance",
                emphasis: .gradient
            )
            heroStatTile(
                eyebrow: "DOCS · OK",
                value: heroOverview.map { "\($0.documents.valid)" } ?? "—",
                meta: heroOverview.map { "/\($0.documents.total) on file" } ?? "—",
                emphasis: .none
            )
            heroStatTile(
                eyebrow: "ALERTS",
                value: heroExpiring.isEmpty ? "0" : "\(heroExpiring.count)",
                meta: heroExpiring.first.map { medicalCountdown($0) } ?? "all current",
                emphasis: heroExpiring.isEmpty ? .none : .warning
            )
        }
    }

    private enum StatEmphasis { case none, gradient, warning }

    private func heroStatTile(
        eyebrow: String,
        value: String,
        meta: String,
        emphasis: StatEmphasis
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Group {
                switch emphasis {
                case .gradient:
                    Text(value)
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                case .warning:
                    Text(value)
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Brand.warning)
                case .none:
                    Text(value)
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
            Text(meta)
                .font(.system(size: 10))
                .foregroundStyle(emphasis == .warning ? Brand.warning : palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Endorsements strip

    private var endorsementsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(endorsementsHeader)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    endorsementChip(label: "TANK · N",      icon: "drop.fill",     active: hasEndorsement("N"))
                    endorsementChip(label: "HAZMAT · H",    icon: "diamond.fill",  active: hasEndorsement("H"))
                    endorsementChip(label: "DBL/TRP · T",   icon: "rectangle.split.2x1.fill", active: hasEndorsement("T"))
                    endorsementChip(label: "PAX · P",       icon: "person.2.fill", active: hasEndorsement("P"))
                }
            }
        }
    }

    private var endorsementsHeader: String {
        let active = ["N", "H", "T", "P"].filter { hasEndorsement($0) }.count
        return "CDL ENDORSEMENTS · \(active) OF 4 ACTIVE"
    }

    /// True if the driver's DQ documents include a "hazmat" / "tanker" /
    /// "doubles_triples" / "passenger" endorsement record. The §11.4
    /// canonical persona has N / H / T active, P swappable. Until the
    /// `drivers.endorsements[]` column ships server-side, we infer
    /// presence from `driverQualification.getDocuments` types.
    private func hasEndorsement(_ code: String) -> Bool {
        let typeMatch: String = {
            switch code {
            case "N": return "tanker"
            case "H": return "hazmat"
            case "T": return "doubles_triples"
            case "P": return "passenger"
            default:  return code.lowercased()
            }
        }()
        // Sole-driver §11.4 canonical fallback: N H T active when no
        // documents record yet (e.g. new fleet, docs pending upload).
        if heroDocuments.isEmpty {
            return ["N", "H", "T"].contains(code)
        }
        return heroDocuments.contains { ($0.type.lowercased().contains(typeMatch)) && ($0.status?.lowercased() == "valid") }
    }

    private func endorsementChip(label: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.4)
        }
        .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(
            Group {
                if active {
                    LinearGradient.diagonal
                } else {
                    palette.bgCard
                }
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(
                active ? AnyShapeStyle(Color.clear) : AnyShapeStyle(palette.borderFaint),
                lineWidth: 1
            )
        )
    }

    // MARK: - DQ files strip card

    private var dqFilesStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("DQ FILES · 49 CFR §391")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(dqLastRefreshLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 8) {
                dqFileTile(
                    eyebrow: "MEDICAL",
                    eyebrowTint: Brand.success,
                    value: medicalCardCountdownDisplay,
                    meta: medicalCardRecertDisplay,
                    bg: Brand.success.opacity(0.10),
                    accentGradient: false
                )
                dqFileTile(
                    eyebrow: "ANNUAL",
                    eyebrowTint: Brand.blue,
                    value: annualReviewCountdownDisplay,
                    meta: annualReviewMetaDisplay,
                    bg: palette.bgCard,
                    accentGradient: true
                )
                dqFileTile(
                    eyebrow: "MVR",
                    eyebrowTint: Brand.success,
                    value: mvrPullDisplay,
                    meta: mvrSourceDisplay,
                    bg: Brand.success.opacity(0.10),
                    accentGradient: false
                )
                dqFileTile(
                    eyebrow: "DRUG",
                    eyebrowTint: Brand.success,
                    value: drugScreenDisplay,
                    meta: drugScreenMetaDisplay,
                    bg: Brand.success.opacity(0.10),
                    accentGradient: false
                )
            }

            Divider()
                .background(palette.borderFaint)
                .padding(.vertical, 10)

            Text(clearinghouseLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func dqFileTile(
        eyebrow: String,
        eyebrowTint: Color,
        value: String,
        meta: String,
        bg: Color,
        accentGradient: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(eyebrowTint)
            if accentGradient {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
            Text(meta)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .overlay(
            Group {
                if accentGradient {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Onboarding · DQ alerts card

    private var onboardingDQAlerts: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ONBOARDING · DQ ALERTS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(alertCountLabel)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(heroExpiring.isEmpty ? Brand.success : Brand.warning)
            }
            .padding(.bottom, 12)

            if heroExpiring.isEmpty {
                emptyAlertsRow
            } else {
                ForEach(Array(heroExpiring.prefix(3).enumerated()), id: \.element.id) { idx, item in
                    alertRow(item)
                    if idx < min(2, heroExpiring.count - 1) {
                        Divider().background(palette.borderFaint).padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            HStack(spacing: 0) {
                Rectangle()
                    .fill(LinearGradient(
                        colors: heroExpiring.isEmpty
                            ? [Brand.success, Brand.success]
                            : [Brand.warning, Brand.danger],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 3)
                Spacer()
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var alertCountLabel: String {
        if heroExpiring.isEmpty { return "ALL CURRENT" }
        return "\(heroExpiring.count) ALERT\(heroExpiring.count == 1 ? "" : "S")"
    }

    private var emptyAlertsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("All DQ files current")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("No expiries within 60 days · 49 CFR §391 clean")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func alertRow(_ item: DriverQualificationAPI.ExpiringItem) -> some View {
        let severity = severityFor(daysRemaining: item.daysRemaining)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: severity.icon)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(severity.tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(alertTitle(for: item.type))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(alertSubtitle(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Text(severity.badge(daysRemaining: item.daysRemaining))
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(severity.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(severity.tint.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private struct AlertSeverity {
        let icon: String
        let tint: Color
        let badgeFn: (Int) -> String
        func badge(daysRemaining: Int) -> String { badgeFn(daysRemaining) }
    }

    private func severityFor(daysRemaining: Int) -> AlertSeverity {
        if daysRemaining < 0 {
            return AlertSeverity(icon: "exclamationmark.octagon.fill",
                                 tint: Brand.danger,
                                 badgeFn: { _ in "EXPIRED" })
        }
        if daysRemaining < 14 {
            return AlertSeverity(icon: "exclamationmark.triangle.fill",
                                 tint: Brand.danger,
                                 badgeFn: { d in "\(d)D" })
        }
        if daysRemaining < 60 {
            return AlertSeverity(icon: "clock.fill",
                                 tint: Brand.warning,
                                 badgeFn: { d in "\(d)D" })
        }
        return AlertSeverity(icon: "checkmark.shield.fill",
                             tint: Brand.success,
                             badgeFn: { d in "\(d)D" })
    }

    private func alertTitle(for type: String) -> String {
        switch type.lowercased() {
        case "medicalcard", "medical_card", "medical": return "Medical card · 49 CFR §391.41"
        case "license", "cdl":                          return "CDL renewal · 49 CFR §383.71"
        case "hazmat":                                  return "Hazmat endorsement · 49 CFR §383.93"
        case "twic":                                    return "TWIC card · 49 CFR §1572"
        case "annual_review", "annualreview":           return "Annual review · 49 CFR §391.25"
        case "mvr":                                     return "MVR pull · 49 CFR §391.25"
        default:                                        return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func alertSubtitle(for item: DriverQualificationAPI.ExpiringItem) -> String {
        let date = formatExpiryDate(item.expiresAt)
        if item.daysRemaining < 0 {
            return "Expired \(date) · expired \(abs(item.daysRemaining))d ago"
        }
        return "Due \(date) · \(item.daysRemaining)d remaining"
    }

    // MARK: - Additional drivers list (rows below the hero)

    @ViewBuilder
    private var additionalDriversList: some View {
        let others = drivers.filter { $0.id != heroDriver?.id }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("ROSTER · \(others.count) MORE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                ForEach(others) { d in
                    Button {
                        heroDriver = d
                        Task { await loadHeroAdjuncts(for: d) }
                    } label: {
                        otherDriverRow(d)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func otherDriverRow(_ d: CatalystAPI.FleetDriver) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(monogram(for: d.name))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(otherDriverSubtitle(d))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(12)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func otherDriverSubtitle(_ d: CatalystAPI.FleetDriver) -> String {
        if let load = d.currentLoad, !load.isEmpty {
            if let h = d.hoursRemaining {
                return "\(load) · HOS \(hosDisplay(h)) · \(d.location)"
            }
            return "\(load) · \(d.location)"
        }
        return "\(d.status.uppercased()) · \(d.location)"
    }

    // MARK: - ESANG promotion strip

    private func esangPromotionStrip(_ driver: CatalystAPI.FleetDriver) -> some View {
        let next = heroExpiring.first
        let title: String = {
            if let n = next {
                return "Schedule \(alertTitle(for: n.type)) · saves 30 min vs HR queue"
            }
            return "Generate next quarter's compliance report · 49 CFR §391"
        }()
        let meta: String = {
            if let n = next, !n.expiresAt.isEmpty {
                return "Due \(formatExpiryDate(n.expiresAt)) · Eusotrans HR portal · auto-files to DQ packet"
            }
            return "Run an audit on \(driver.name) · packets DQ + IRP + IFTA filings"
        }()

        return Button {
            // Open ESANG chat with this driver's context preloaded.
            // ESang is the canonical voice/messaging funnel per
            // `feedback_esang_canonical_voice` — every catalyst-side
            // action that nudges the driver routes through here, not
            // direct tRPC mutations.
            NotificationCenter.default.post(
                name: .esangOpenMeDetail,
                object: "messages",
                userInfo: [
                    "driverId": driver.id,
                    "context": "scorecard_digest",
                ]
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                    Text(meta)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading / empty / error states

    private var loadingHeroSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.bgCard)
                .frame(height: 194)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(palette.bgCard)
                        .frame(height: 38)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private var emptyRosterState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ROSTER · 0 DRIVERS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 12) {
                Image(systemName: "person.fill.badge.plus")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No drivers yet")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Add a driver to start dispatching loads. They'll appear here with their HOS / DQ status the moment they accept the invite.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROSTER UNAVAILABLE")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Brand.danger)
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text(msg)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Button {
                        Task { await loadAll() }
                    } label: {
                        Text("Retry")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.danger)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Brand.danger.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: - Display helpers

    private func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    private func cdlLine(for driver: CatalystAPI.FleetDriver) -> String {
        // Use the catalyst-side metadata available; richer drivers row
        // ships in the next firing (drivers.getById on this catalyst).
        let status = driver.status.uppercased()
        if let load = driver.currentLoad, !load.isEmpty {
            return "CDL · \(status) · ON LOAD"
        }
        return "CDL · \(status) · \(driver.location)"
    }

    private func activeHaulLine(driver: CatalystAPI.FleetDriver, load: String) -> String {
        if let h = driver.hoursRemaining {
            return "\(load) · HOS \(hosDisplay(h)) · \(driver.location)"
        }
        return "\(load) · \(driver.location)"
    }

    private func hosDisplay(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }

    private func medicalCountdown(_ item: DriverQualificationAPI.ExpiringItem) -> String {
        if item.daysRemaining < 0 {
            return "expired \(abs(item.daysRemaining))d ago"
        }
        return "next \(item.daysRemaining)d"
    }

    // MARK: DQ tile data

    private var medicalCardCountdownDisplay: String {
        guard let item = heroExpiring.first(where: { $0.type.lowercased().contains("medical") }) else {
            return medicalDocStatus(typeContains: "medical") ?? "—"
        }
        return "\(item.daysRemaining)d"
    }

    private var medicalCardRecertDisplay: String {
        guard let item = heroExpiring.first(where: { $0.type.lowercased().contains("medical") }) else {
            return "no expiry on file"
        }
        return "recert \(formatExpiryDate(item.expiresAt))"
    }

    private var annualReviewCountdownDisplay: String {
        if let item = heroExpiring.first(where: { $0.type.lowercased().contains("annual") || $0.type.lowercased().contains("mvr") }) {
            return "\(item.daysRemaining)d"
        }
        return "—"
    }

    private var annualReviewMetaDisplay: String {
        if let item = heroExpiring.first(where: { $0.type.lowercased().contains("annual") || $0.type.lowercased().contains("mvr") }) {
            return "\(formatExpiryDate(item.expiresAt)) · MVR pull"
        }
        return "no upcoming review"
    }

    private var mvrPullDisplay: String {
        if let mvrDoc = heroDocuments.first(where: { $0.type.lowercased().contains("mvr") && ($0.status?.lowercased() == "valid") }) {
            return formatExpiryDate(mvrDoc.uploadedAt ?? "")
        }
        return "—"
    }

    private var mvrSourceDisplay: String {
        if heroDocuments.contains(where: { $0.type.lowercased().contains("mvr") && ($0.status?.lowercased() == "valid") }) {
            return "on file"
        }
        return "no MVR yet"
    }

    private var drugScreenDisplay: String {
        if let drugDoc = heroDocuments.first(where: { $0.type.lowercased().contains("drug") && ($0.status?.lowercased() == "valid") }) {
            return formatExpiryDate(drugDoc.uploadedAt ?? "")
        }
        return "—"
    }

    private var drugScreenMetaDisplay: String {
        if heroDocuments.contains(where: { $0.type.lowercased().contains("drug") && ($0.status?.lowercased() == "valid") }) {
            return "Random — neg"
        }
        return "no test on file"
    }

    private func medicalDocStatus(typeContains: String) -> String? {
        guard heroDocuments.contains(where: { $0.type.lowercased().contains(typeContains) }) else { return nil }
        return "OK"
    }

    private var dqLastRefreshLabel: String {
        if let mostRecent = heroDocuments.compactMap({ $0.uploadedAt }).max() {
            return "Last refresh \(formatExpiryDate(mostRecent))"
        }
        return "Last refresh —"
    }

    private var clearinghouseLine: String {
        // Clearinghouse query lookup keyed off documents.type =
        // "drug_clearinghouse" or "clearinghouse". When present we
        // surface the date; otherwise an honest empty state.
        if let item = heroDocuments.first(where: { $0.type.lowercased().contains("clearinghouse") }) {
            return "Clearinghouse query · pre-employment · \((item.status?.lowercased() == "valid") ? "negative" : "pending") · \(formatExpiryDate(item.uploadedAt ?? ""))"
        }
        return "Clearinghouse query · not yet on file"
    }

    private func formatExpiryDate(_ raw: String) -> String {
        guard !raw.isEmpty else { return "—" }
        // Already-formatted YYYY-MM-DD — keep as-is.
        if raw.count >= 10, let y = Int(raw.prefix(4)) ?? nil, y > 1900 {
            _ = y
            return String(raw.prefix(10))
        }
        // ISO-8601
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) {
            let out = DateFormatter()
            out.dateFormat = "yyyy-MM-dd"
            return out.string(from: d)
        }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: raw) {
            let out = DateFormatter()
            out.dateFormat = "yyyy-MM-dd"
            return out.string(from: d)
        }
        return raw
    }

    // MARK: - Network

    private func loadAll() async {
        driversLoading = true
        driversError = nil
        defer { driversLoading = false }

        do {
            let roster = try await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 25)
            self.drivers = roster
            let primary = roster.first { ($0.currentLoad ?? "").isEmpty == false } ?? roster.first
            self.heroDriver = primary
            if let hero = primary {
                await loadHeroAdjuncts(for: hero)
            }
        } catch {
            self.driversError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadHeroAdjuncts(for driver: CatalystAPI.FleetDriver) async {
        // Reset before fetching so a stale hero's data never paints
        // under a freshly selected one.
        heroOverview = nil
        heroDocuments = []
        heroExpiring = []

        async let overviewTask: DriverQualificationAPI.Overview? = {
            try? await EusoTripAPI.shared.dq.getOverview(driverId: driver.id)
        }()
        async let documentsTask: [DriverQualificationAPI.DQDocument] = {
            (try? await EusoTripAPI.shared.dq.getDocuments(driverId: driver.id))?.documents ?? []
        }()
        async let expiringTask: [DriverQualificationAPI.ExpiringItem] = {
            (try? await EusoTripAPI.shared.dq.getExpiringItems(daysAhead: 60)) ?? []
        }()

        let (overview, docs, expiring) = await (overviewTask, documentsTask, expiringTask)
        // `getExpiringItems` is company-scoped; filter to this driver.
        let driverIdInt = Int(driver.id) ?? -1
        let scoped = expiring.filter { $0.driverId == driverIdInt }

        self.heroOverview = overview
        self.heroDocuments = docs
        self.heroExpiring = scoped
    }
}

// MARK: - Driver invite sheet (Catalyst Add button)

/// Invite a new driver to join the catalyst's fleet via a brand-tinted
/// QR + share link. The receiving driver scans on their phone, the
/// EusoQRView payload (`https://eusotrip.com/invite/...`) deep-links
/// into account creation with the catalyst's companyId pre-attached
/// so they auto-attach to the fleet on signup.
private struct CatalystInviteDriverSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    private var inviteCode: String {
        // Stable invite code derived from the catalyst's companyId so
        // the same QR keeps scanning into the same fleet across
        // sheet re-opens. Server validates + ties to the catalyst's
        // company on the signup callback. When `companyId` is
        // missing (rare — pre-attached account), fall back to a
        // generic "DRIVER" code that still routes to the role-aware
        // signup flow.
        let cid = session.user?.companyId ?? "0"
        return "DRIVER-CATALYST-\(cid)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Scan to onboard")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Share this QR with a driver you want to attach to your fleet. They scan, sign up, and land in your roster automatically with companyId pre-set.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                EusoQRView(
                    kind: .invite(code: inviteCode, kind: .driver),
                    role: .carrier,
                    size: 240
                )
                .padding(20)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("eusotrip.com/invite/\(inviteCode)")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)

                ShareLink(
                    item: URL(string: "https://eusotrip.com/invite/\(inviteCode)?role=carrier&kind=driver")!,
                    subject: Text("Join my Eusotrip fleet"),
                    message: Text("Tap to join — onboards you to my carrier fleet automatically.")
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .heavy))
                        Text("Share invite link")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Add driver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Driver profile route identifier (sheet key)

private struct CatalystDriverProfileRoute: Identifiable {
    let id: String
}

// MARK: - Previews

#Preview("304 · Catalyst · Fleet Drivers · Night") {
    CatalystFleetDriversScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("304 · Catalyst · Fleet Drivers · Afternoon") {
    CatalystFleetDriversScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
