//
//  036_ESangSmartStop.swift
//  EusoTrip 2027 UI — Wave 2 (main haul · ESANG suggested stop overlay)
//
//  Screen 036 · ESANG Smart Stop — mid-haul (after 035 En Route Drive),
//  ESANG surfaces a ranked next-stop recommendation that aligns the
//  driver's pickup of (cheap diesel · mandatory HOS reset · confirmed
//  parking · weather pre-empt). The screen is a non-modal overlay
//  the driver can accept or skip. Card layout:
//
//    [topbar: back · "ESANG SUGGESTS · {time}" gradient kicker]
//    [hero headline + subhead + map-attribution micro]
//    [stop card · neutral mappin tile + name + ESANG score + location +
//     3-up metrics (DISTANCE · ETA DELTA · PARK SPACES)]
//    [WHY ESANG PICKED THIS · 3 reason rows w/ icon tile + chip]
//    [amenity row (pumps/scale/shower/cat/food/restroom/wifi)]
//    [footer attribution: "ESANG RANKED N CANDIDATES · DATA FUSED FROM …"]
//    [actions · skip outline + accept gradient]
//
//  92nd-firing visible-copy retrofit (Cohort A → Cohort B under M2):
//
//      ALL register-keyed Figma fixtures (Pilot/Love's brand vignettes,
//      hard-coded scores, cherry-picked clock times) are replaced with
//      live-or-neutral accessors. The screen is now data-driven:
//
//        clockTime          — local wall-clock formatted HH:mm (live)
//        heroHeadline/sub   — neutral "ESANG is sourcing your next stop"
//                             until candidate data is wired in (which
//                             happens via HereParkingStrip below the
//                             card right now; SmartStopCandidateStore
//                             will hoist it into the top card later)
//        stopBrandLetter    — generic "·" pin-tile (no third-party brand)
//        stopBrandColor     — palette.tintNeutral (no Pilot Yellow / Love's Red)
//        stopName/score/etc — em-dash placeholders until live candidate
//        reasons[2]         — already product-aware via ctx.smartStopProductReason
//        skipTitle          — fixed "Skip"
//        acceptTitle        — fixed "Accept & route →"
//
//      The HereMatrixCandidatesStrip / HereParkingStrip / HereEVStrip
//      below the card already render live candidates from HERE; they
//      self-hide cleanly when nothing is returned. The top card no
//      longer competes with them by displaying Figma vignettes that
//      look like real ranked candidates.
//
//      Result: in production with a live load + active route, the
//      screen renders ESANG signal + product-aware copy + live
//      HERE candidate strips. With no live load (signed-out, between
//      trips, preview), the top card renders neutral em-dash
//      placeholders — never fixture data, never Figma vignettes.
//
//  Doctrine refs:
//    §2  gradient, not flat blue — kicker, ESANG score, ETA delta numeral,
//        and chips all render LinearGradient.diagonal; amenity icons are
//        neutral palette glyphs (utility, not brand accent).
//    §4.3 iridescent hairline above the amenity row separator.
//    §6  dual register — both Dark + Light previews at the bottom; the
//        previews now exercise the neutral-state branch (no live load),
//        so they show what the production "0 data" state looks like.
//    §7  breathe density — vertical scroll, 14pt horizontal page padding,
//        Space.s4 between section blocks.
//    §11 visible copy is store-driven, not Figma-keyed. Cohort B under M2.
//
//  92nd firing.
//

import SwiftUI

// MARK: - Data model

private struct StopReason: Identifiable {
    let id = UUID()
    let icon: String       // SF Symbol
    let title: String
    let subtitle: String
    let chip: String       // gradient pill label (uppercased on render)
}

private struct AmenityIcon: Identifiable {
    let id = UUID()
    let icon: String       // SF Symbol
    let label: String
}

// MARK: - Screen body

struct ESangSmartStop: View {
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.lifecycleAdvance) private var advance

    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?

    /// Vertical + product dispatcher. The third "why ESANG picked
    /// this" reason swaps via ctx so a dry-van load shows secure
    /// linehaul parking, a reefer load shows shore power, and a
    /// hazmat load shows PG-class spaces — never a hazmat row on a
    /// non-hazmat load.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: live or neutral copy (§11) — 92nd firing M2 retrofit
    //
    // Every accessor below is one of two states:
    //
    //   (a) LIVE — derived from `activeLoad` + `ctx` + system state
    //   (b) NEUTRAL — em-dash / generic icon / generic copy when no
    //       data is wired yet (today: the smart-stop top card; the
    //       HERE strips below the card already render live candidates)
    //
    // No more `register == .dark ? "Figma dark" : "Figma light"`. No
    // third-party brand vignettes (Pilot/Love's). No cherry-picked
    // ESANG scores. The screen looks the same in both registers — the
    // palette is what makes register-aware visual decisions, not copy.

    /// Live wall-clock in `HH:mm`, recomputed when the body draws.
    private var clockTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    /// Hero headline — product-aware when a load is hydrated, neutral
    /// "ESANG is sourcing" copy when not. Never mentions a specific
    /// truckstop brand or fixture distance.
    private var heroHeadline: String {
        guard activeLoad != nil else {
            return "ESANG is sourcing your next stop"
        }
        if ctx.isHazmat {
            return "Plan a hazmat-rated stop ahead"
        }
        switch ctx.product {
        case .reefer:
            return "Plan a cold-rated stop ahead"
        case .flatbed:
            return "Plan a wide-body / heavy-haul stop"
        case .container, .railIntermodal, .vesselContainer:
            return "Plan a chassis-friendly stop"
        case .railBulk, .vesselBulk:
            return "Plan a bulk-yard staging stop"
        default:
            return "Plan your next legal stop"
        }
    }

    /// Hero subhead — neutral system copy until a candidate is ranked.
    /// No fixture distances, no fixture ETA deltas, no fixture weather.
    private var heroSubhead: String {
        guard activeLoad != nil else {
            return "We'll surface ranked options as live route + parking data lands."
        }
        return "Live ranking from EusoMap, OPIS, HERE Parking, and FMCSA HOS rules."
    }

    // Stop card — fully neutral until SmartStopCandidateStore ships.

    /// Generic pin-tile letter — never a third-party brand initial.
    private var stopBrandLetter: String { "·" }

    /// Neutral palette tile — never a third-party trademark color.
    private var stopBrandColor: Color { palette.tintNeutral }

    /// Stop name — em-dash placeholder until ranked candidate lands.
    private var stopName: String { "—" }

    /// ESANG score — em-dash until ranked candidate lands.
    private var stopScore: String { "—" }

    /// Location string — em-dash until ranked candidate lands.
    private var stopLocation: String { "AWAITING LIVE CANDIDATE" }

    private var distanceValue: String { "—" }
    private var etaDeltaValue:  String { "—" }
    private var parkSpacesValue: String { "—" }

    /// Reasons list — the third row is product-aware via ctx (live).
    /// Rows 1+2 are neutral system descriptors of what ESANG considers
    /// when ranking, not Figma vignettes pretending to be candidate data.
    private var reasons: [StopReason] {
        let third: StopReason = {
            let r = ctx.smartStopProductReason
            return StopReason(
                icon: r.icon,
                title: r.title,
                subtitle: "ESANG · PRODUCT-AWARE FILTER",
                chip: r.chip
            )
        }()

        return [
            StopReason(
                icon: "fuelpump.fill",
                title: "Cheapest legal diesel within HOS reach",
                subtitle: "OPIS · LIVE FUEL RACK",
                chip: "Cost"
            ),
            StopReason(
                icon: "clock.fill",
                title: "Aligns with mandatory HOS reset window",
                subtitle: "FMCSA 395.3 · LIVE CLOCK",
                chip: "HOS"
            ),
            third,
        ]
    }

    private let amenities: [AmenityIcon] = [
        .init(icon: "fuelpump.fill",       label: "Pumps"),
        .init(icon: "scalemass.fill",      label: "Scale"),
        .init(icon: "shower.fill",         label: "Shower"),
        .init(icon: "pawprint.fill",       label: "Cat"),
        .init(icon: "fork.knife",          label: "Food"),
        .init(icon: "toilet.fill",         label: "Restroom"),
        .init(icon: "wifi",                label: "Wifi"),
    ]

    /// Footer attribution — neutral system descriptor of the ranking
    /// inputs. No fixture candidate counts.
    private var footerAttribution: String {
        "ESANG RANKS LIVE · DATA FUSED FROM EUSOMAP, OPIS, HERE PARKING, FMCSA HOS RULE"
    }

    private var skipTitle: String { "Skip" }
    private var acceptTitle: String { "Accept & route →" }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topbar
            VStack(alignment: .leading, spacing: Space.s4) {
                heroBlock
                stopCard
                whyHeader
                reasonsList
                amenityRow
                footerLine
                actions
                // HERE Matrix — parallel ETA across the top candidate
                // truckstops fed by the parking nearby query, computed
                // with truck-aware travel time. Hides cleanly when
                // matrix access isn't licensed on the tenant key.
                HereMatrixCandidatesStrip()
                // HERE Parking — side-by-side alternative options
                // (off-street lots + garages + truck stops) near the
                // driver's live fix. Silent when HERE returns empty
                // or CoreLocation isn't authorized.
                HereParkingStrip()
                // HERE EV Charging — surfaces automatically on
                // routes where stations exist. Future-proof for
                // the EV-truck fleet; silent on today's diesel
                // corridors when HERE has no EV coverage nearby.
                HereEVStrip()
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        // Uniform cafe-door entrance.
        .screenTileRoot()
        .task { await hydrateLiveTrip() }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    // MARK: - Topbar

    private var topbar: some View {
        HStack(spacing: 12) {
            Button { navBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Back")

            Spacer()

            // Centered ESANG kicker — gradient text
            Text("ESANG SUGGESTS · \(clockTime)")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(LinearGradient.diagonal)

            Spacer()

            // Right-side spacer matched to back button width for visual centering
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: - Hero block (headline + sub + attribution)

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heroHeadline)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(heroSubhead)
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 9))
                Text("Map data ©2026")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(palette.textTertiary)
            .padding(.top, 2)
        }
    }

    // MARK: - Stop card

    private var stopCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .center, spacing: 12) {
                    // Brand logo tile (third-party brand color, not Eusorone gradient)
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(stopBrandColor)
                            .frame(width: 44, height: 44)
                        Text(stopBrandLetter)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                    }

                    // Name
                    Text(stopName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    // ESANG score — gradient numeral, kicker label
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(stopScore)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("ESANG SCORE")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                    }
                }

                // Location line
                Text(stopLocation)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)

                // 3-up metric row
                HStack(spacing: 10) {
                    MetricTile(label: "Distance",  value: distanceValue)
                    MetricTile(label: "ETA delta", value: etaDeltaValue, gradientNumeral: true)
                    MetricTile(label: "Park spaces", value: parkSpacesValue)
                }
            }
        }
    }

    // MARK: - Why header

    private var whyHeader: some View {
        Text("WHY ESANG PICKED THIS")
            .font(EType.micro).tracking(0.8)
            .foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s1)
    }

    // MARK: - Reasons list

    private var reasonsList: some View {
        VStack(spacing: 8) {
            ForEach(reasons) { reason in
                reasonRow(reason)
            }
        }
    }

    private func reasonRow(_ r: StopReason) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon tile
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(palette.tintNeutral)
                    .frame(width: 36, height: 36)
                Image(systemName: r.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LinearGradient.diagonal)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(r.title)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(r.subtitle.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }

            Spacer(minLength: 8)

            // Gradient chip
            gradientChip(r.chip)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    private func gradientChip(_ text: String) -> some View {
        Text(text.uppercased())
            .font(EType.micro).tracking(0.6)
            .foregroundStyle(LinearGradient.diagonal)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1)
            )
            .fixedSize()
    }

    // MARK: - Amenity row

    private var amenityRow: some View {
        VStack(spacing: Space.s2) {
            IridescentHairline()

            HStack(spacing: 0) {
                ForEach(amenities) { a in
                    VStack(spacing: 4) {
                        Image(systemName: a.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                            .frame(height: 16)
                        Text(a.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, Space.s2)
        }
    }

    // MARK: - Footer attribution

    private var footerLine: some View {
        Text(footerAttribution)
            .font(EType.micro).tracking(0.5)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                // 49th firing: "Skip" declines ESANG's smart-stop suggestion
                // and walks the trip state machine forward past the prompt.
                advance?()
            } label: {
                Text(skipTitle)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderSoft)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .accessibilityLabel(skipTitle)

            LifecycleCTAButton(title: acceptTitle)
                .accessibilityLabel(acceptTitle)
        }
        .padding(.top, Space.s2)
    }
}

// MARK: - Wrapper

struct ESangSmartStopScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            // 92nd-firing M2 retrofit: register no longer drives visible
            // copy. The screen is identical in both registers; the palette
            // makes register-aware visual decisions.
            ESangSmartStop()
        } nav: {
            BottomNav(leading: driverNavLeading_036(),
                      trailing: driverNavTrailing_036(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_036() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",     isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: true)]
}
private func driverNavTrailing_036() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",     isCurrent: false)]
}

// MARK: - Previews

// 92nd-firing previews exercise the production neutral-state branch
// (no live load) — what a driver sees between trips when ESANG is
// awaiting candidate data. With a hydrated load + active route, the
// hero / reasons swap to product-aware copy via ctx, and the HERE
// strips below the card render live ranked candidates.

#Preview("036 · ESANG Smart Stop · Night") {
    ESangSmartStopScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("036 · ESANG Smart Stop · Afternoon") {
    ESangSmartStopScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
