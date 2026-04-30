//
//  235_ShipperFocusModeWidget.swift
//  EusoTrip iOS — Shipper Focus Mode widget filter (§35.3 Arc L)
//
//  iOS twin of:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/02 Shipper/Code/
//    235_ShipperFocusModeWidget.swift
//
//  Surface: per-Focus-profile widget filter authoring. Each of three
//  iOS Focus profiles (Work / Driving / Sleep) carries a 7-bool
//  passthrough vector mapped to the 234 push taxonomy. Fifth Arc L
//  brick after 231 push → 232 lock screen → 233 watch complication →
//  234 haptic. Active profile is Driving — CarPlay + AirPods Pro auto-
//  engaged it 14m ago, 5/7 categories pass through (UN1005 escort + ETA
//  + stage promoted; bid + paperwork silenced).
//
//  §11.4 row 3 anchor (passthrough caption):
//    LD-260427-B41782FF02 · Eusorone Technologies (companyId 1) · Kansas
//    City MO → Omaha NE NH₃ UN1005 escort · MC-331 · stage 5 In transit.
//    Sleep profile silences everything except UN1005 escort divergence.
//
//  Doctrine: §2 nav, §3 numbers-first, §4.3 single hairline, §7 breathe
//  density, §11/§11.2/§11.4 Diego canon + MATRIX-50, §17.2 width-locked
//  status grammar, §19.2 file-scoped helpers (PillToggle,
//  GradientLivePill, GradientCapsuleCTA, CategoryDotStrip, FocusIconView,
//  ProfileRow), §20.4 no dead buttons, §22.2 counter eyebrow color
//  encodes screen-status, §35.3 Arc L iOS-platform integration surfaces.
//
//  Backend (server) endpoints owed (EUSO-2155):
//    focusModes.getForUser                              -> [FocusProfile]
//    focusModes.setEnabledForCategoryInProfile(p, c, b) -> Void
//    focusModes.setActiveProfile(profileId)             -> Void
//    focusModes.setProfileSchedule(profileId, schedule) -> Void
//
//  iOS API surface (consumed by LiveDataStore):
//    ShipperFocusModesAPI.currentProfiles()                  -> [FocusProfile]
//    ShipperFocusModesAPI.setEnabled(category:in:enabled:)
//    ShipperFocusModesAPI.setActiveProfile(_:)
//    ShipperFocusModesAPI.testFire(profileId:)               -> sample push
//
//  iOS framework binding:
//    FocusFilter (App Intent extension that surfaces per-profile
//    category opt-ins to the iOS Focus engine when the user assigns the
//    EusoTrip app to a Focus profile in Settings → Focus → [profile]
//    → Apps).
//
//  Both #Preview blocks (Dark + Light) ship per §11.4 doctrine.
//

import SwiftUI

// MARK: - Screen

struct ShipperFocusModeWidget: View {
    @Environment(\.palette) var palette

    private let counterEyebrow = "3 PROFILES · DRIVING ACTIVE"

    private let activeProfile = ActiveFocusProfile(
        id:                 "fp_2026-04-29T14:22:00Z_driving",
        profileLabel:       "ACTIVE · DRIVING · 5 OF 7 ENABLED",
        headline:           "ETA + stage promoted",
        filterIdAndDetect:  "DrivingFocusFilter · CarPlay+AirPods detected",
        passthroughEyebrow: "PASSTHROUGH · 7 CATEGORIES",
        passthroughCaption: "UN1005 escort + ETA + stage",
        relativeAgo:        "engaged 14m ago",
        ctaLabel:           "Test focus widget",
        passthrough: [
            // 0 bid_received, 1 lifecycle_stage_advance,
            // 2 hazmat_exception, 3 detention_exception,
            // 4 late_pickup, 5 late_delivery, 6 late_paperwork
            false, true, true, true, true, true, false
        ]
    )

    private let profiles: [FocusProfile] = [
        FocusProfile(
            id:           "work",
            title:        "Work",
            sub:          "8am – 6pm · Calendar-detected · Mon-Fri",
            iconKind:     .briefcase,
            passthrough:  [true, true, true, true, true, true, true],
            countCaption: "7 OF 7 · FULL WIDGET · BID + LIFECYCLE + HAZMAT + DETENTION + LATES",
            enabled:      true
        ),
        FocusProfile(
            id:           "driving",
            title:        "Driving",
            sub:          "CarPlay + AirPods Pro detected · auto-engages",
            iconKind:     .car,
            passthrough:  [false, true, true, true, true, true, false],
            countCaption: "5 OF 7 · ETA + STAGE PROMOTED · BID + PAPERWORK SILENCED",
            enabled:      true
        ),
        FocusProfile(
            id:           "sleep",
            title:        "Sleep",
            sub:          "10pm – 7am · Bedtime schedule · do-not-disturb",
            iconKind:     .moon,
            passthrough:  [false, false, true, false, false, false, false],
            countCaption: "1 OF 7 · UN1005 ESCORT ONLY · ALL ELSE SILENCED",
            enabled:      true
        )
    ]

    private let activeProfileId: String = "driving"

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, Space.s5)
            titleBlock
                .padding(.top, Space.s3)

            IridescentHairline()
                .padding(.top, Space.s3)

            sectionLabel("ACTIVE MODE · DRIVING")
                .padding(.top, Space.s5)
            heroCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("MODES · 3 PROFILES")
                .padding(.top, Space.s5)
            profilesCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            settingsPointerLink
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)

            footer
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s5)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · FOCUS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Three Focus profiles total. Driving currently engaged.")
        }
        .padding(.horizontal, Space.s5)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Focus modes")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Per-Focus widget behavior · Eusorone Technologies")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                GradientLivePill(label: activeProfile.profileLabel)
                Spacer(minLength: 0)
                Text(activeProfile.relativeAgo)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(activeProfile.headline)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)

                Text(activeProfile.filterIdAndDetect)
                    .font(EType.mono(.caption))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeProfile.passthroughEyebrow)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)

                    HStack(alignment: .center, spacing: 0) {
                        CategoryDotStrip(passthrough: activeProfile.passthrough,
                                         emphasis: .hero)
                        Spacer().frame(width: 8)
                        Text(activeProfile.passthroughCaption)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }

                Spacer(minLength: 0)

                Button(action: tapTestFocusWidget) {
                    GradientCapsuleCTA(label: activeProfile.ctaLabel, width: 140)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Test the active Focus profile's widget filter now.")
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var profilesCard: some View {
        VStack(spacing: 0) {
            ForEach(profiles.indices, id: \.self) { idx in
                ProfileRow(
                    profile:    profiles[idx],
                    isActive:   profiles[idx].id == activeProfileId,
                    onToggleTap:{ tapProfileToggle(profiles[idx]) },
                    onRowTap:   { tapProfileRow(profiles[idx]) }
                )
                if idx < profiles.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var settingsPointerLink: some View {
        Button(action: tapManageFocusProfiles) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Focus profiles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Per-mode opt-in matrix · 211 Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("→")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Manage Focus profiles. Per-mode opt-in matrix lives in 211 Settings.")
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Powered by FocusFilter · iOS Focus engine")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Text("companyId 1 · Eusorone Technologies · MATRIX-50-2026-04-26")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Tap handlers (§20.4 no dead buttons)

    private func tapTestFocusWidget() {
        NotificationCenter.default.post(
            name: .eusoShipperFocusTestWidget,
            object: nil,
            userInfo: [
                "source": "235_ShipperFocusModeWidget",
                "profileId": activeProfile.id,
                "activeProfileId": activeProfileId,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapProfileToggle(_ profile: FocusProfile) {
        NotificationCenter.default.post(
            name: .eusoShipperFocusProfileToggle,
            object: nil,
            userInfo: [
                "source": "235_ShipperFocusModeWidget",
                "profileId": profile.id,
                "priorEnabled": profile.enabled,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapProfileRow(_ profile: FocusProfile) {
        NotificationCenter.default.post(
            name: .eusoShipperFocusProfileRow,
            object: nil,
            userInfo: [
                "source": "235_ShipperFocusModeWidget",
                "profileId": profile.id,
                "passthroughCount": profile.passthrough.filter { $0 }.count,
                "isActiveProfile": profile.id == activeProfileId,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapManageFocusProfiles() {
        NotificationCenter.default.post(
            name: .eusoShipperFocusManageProfiles,
            object: nil,
            userInfo: [
                "source": "235_ShipperFocusModeWidget",
                "targetScreen": "211 Settings",
                "shipperCompanyId": 1
            ]
        )
    }
}

// MARK: - Domain models (file-scoped — wired by LiveDataStore from
//          ShipperFocusModesAPI.currentProfiles() + focusModes.getForUser)

private struct ActiveFocusProfile {
    let id:                 String
    let profileLabel:       String
    let headline:           String
    let filterIdAndDetect:  String
    let passthroughEyebrow: String
    let passthroughCaption: String
    let relativeAgo:        String
    let ctaLabel:           String
    let passthrough:        [Bool]
}

private enum FocusIcon {
    case briefcase
    case car
    case moon
}

private struct FocusProfile: Identifiable {
    let id:           String
    let title:        String
    let sub:          String
    let iconKind:     FocusIcon
    let passthrough:  [Bool]
    let countCaption: String
    let enabled:      Bool
}

// MARK: - GradientLivePill (240×22 ACTIVE pill — same recipe as 234)

private struct GradientLivePill: View {
    let label: String

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(LinearGradient.primary)
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                }
                .padding(.leading, 8)
                Text(label)
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.trailing, 10)
        }
        .frame(maxWidth: 240, minHeight: 22, maxHeight: 22)
        .accessibilityLabel(label)
    }
}

// MARK: - GradientCapsuleCTA (140×22 hero CTA — same as 234)

private struct GradientCapsuleCTA: View {
    let label: String
    let width: CGFloat

    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient.primary)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
        }
        .frame(width: width, height: 22)
    }
}

// MARK: - CategoryDotStrip (7-dot visualizer — one dot per 234-taxonomy
//          category. Gradient pair when passthrough enabled, neutral
//          pair when silenced. Same 12pt-pitch geometry across hero +
//          rows.)

private enum DotEmphasis {
    case hero
    case row
}

private struct CategoryDotStrip: View {
    @Environment(\.palette) var palette
    let passthrough: [Bool]
    let emphasis:    DotEmphasis

    var body: some View {
        HStack(spacing: 12) {
            ForEach(passthrough.indices, id: \.self) { idx in
                ZStack {
                    if passthrough[idx] {
                        Circle()
                            .fill(LinearGradient.primary.opacity(0.30))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .fill(palette.textPrimary.opacity(0.10))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(palette.textTertiary)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - FocusIconView (briefcase · car · moon — file-scoped icon
//          glyphs matching the SVG twin's stroke/fill geometry. Car
//          paints gradient when active.)

private struct FocusIconView: View {
    @Environment(\.palette) var palette
    let kind:     FocusIcon
    let isActive: Bool

    var body: some View {
        switch kind {
        case .briefcase:
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(palette.textPrimary, lineWidth: 1.6)
                    .frame(width: 28, height: 20)
                    .offset(y: 3)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .strokeBorder(palette.textPrimary, lineWidth: 1.6)
                    .frame(width: 10, height: 6)
                    .offset(y: -7)
                Rectangle()
                    .fill(palette.textPrimary)
                    .frame(width: 28, height: 2)
                    .offset(y: 4)
            }
            .frame(width: 32, height: 32)
        case .car:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive
                          ? AnyShapeStyle(LinearGradient.primary)
                          : AnyShapeStyle(palette.textPrimary))
                    .frame(width: 28, height: 14)
                    .offset(y: -2)
                Circle().fill(.white).frame(width: 5, height: 5).offset(x: -8, y: 6)
                Circle().fill(.white).frame(width: 5, height: 5).offset(x: 8,  y: 6)
                Capsule()
                    .fill(isActive
                          ? AnyShapeStyle(LinearGradient.primary)
                          : AnyShapeStyle(palette.textPrimary))
                    .frame(width: 18, height: 8)
                    .offset(y: -8)
            }
            .frame(width: 32, height: 32)
        case .moon:
            ZStack {
                Circle()
                    .fill(palette.textPrimary)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(palette.bgCard)
                    .frame(width: 18, height: 18)
                    .offset(x: 5, y: -3)
            }
            .frame(width: 32, height: 32)
        }
    }
}

// MARK: - ProfileRow (per-Focus-profile row — icon + name + sub +
//          7-dot strip + count caption + PillToggle; active row gets
//          12% gradient wash, leading marker dot, gradient title +
//          count caption + chevron)

private struct ProfileRow: View {
    @Environment(\.palette) var palette
    let profile:     FocusProfile
    let isActive:    Bool
    let onToggleTap: () -> Void
    let onRowTap:    () -> Void

    var body: some View {
        Button(action: onRowTap) {
            ZStack(alignment: .leading) {
                if isActive {
                    LinearGradient.primary
                        .opacity(0.12)
                }

                HStack(alignment: .top, spacing: 14) {
                    if isActive {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 6, height: 6)
                            .padding(.top, 30)
                            .padding(.leading, 8)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        FocusIconView(kind: profile.iconKind, isActive: isActive)
                            .padding(.top, 16)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isActive
                                                 ? AnyShapeStyle(LinearGradient.primary)
                                                 : AnyShapeStyle(palette.textPrimary))
                                .lineLimit(1)

                            Text(profile.sub)
                                .font(.system(size: 10))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            CategoryDotStrip(passthrough: profile.passthrough,
                                             emphasis: .row)
                                .padding(.top, 8)

                            HStack(alignment: .center, spacing: 0) {
                                Text(profile.countCaption)
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(isActive
                                                     ? AnyShapeStyle(LinearGradient.primary)
                                                     : AnyShapeStyle(palette.textTertiary))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                                if isActive {
                                    Text("→")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(LinearGradient.primary)
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onToggleTap) {
                        PillToggle(enabled: profile.enabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(profile.title), \(profile.enabled ? "on" : "off")")
                    .accessibilityHint("Toggles the \(profile.title) Focus profile.")
                    .padding(.top, 30)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(minHeight: 130)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(profile.title) Focus profile. \(profile.countCaption). \(profile.enabled ? "Enabled" : "Disabled").\(isActive ? " Active." : "")")
    }
}

// MARK: - PillToggle (44×24 — 211 Settings + 234 recipe)

private struct PillToggle: View {
    @Environment(\.palette) var palette
    let enabled: Bool

    var body: some View {
        ZStack(alignment: enabled ? .trailing : .leading) {
            Capsule()
                .fill(enabled
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.textPrimary.opacity(0.10)))
            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
                .padding(.horizontal, 3)
        }
        .frame(width: 44, height: 24)
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// "Test focus widget" CTA — fires the active profile's sample push
    /// through ShipperFocusModesAPI.testFire, routing through FocusFilter
    /// App Intent extension and surfacing the widget update on lock
    /// screen + Apple Watch + Dynamic Island per the active passthrough
    /// vector. Payload: profileId + activeProfileId.
    static let eusoShipperFocusTestWidget       = Notification.Name("eusoShipperFocusTestWidget")

    /// Per-profile PillToggle tap — flips per-profile enabled state via
    /// focusModes.setActiveProfile. Carries priorEnabled for revert.
    static let eusoShipperFocusProfileToggle    = Notification.Name("eusoShipperFocusProfileToggle")

    /// Per-profile row tap — opens the per-profile passthrough-edit
    /// sheet (7-toggle matrix mapping the 234 taxonomy to the profile's
    /// passthrough vector). Tapping the active row re-fires test playback.
    static let eusoShipperFocusProfileRow       = Notification.Name("eusoShipperFocusProfileRow")

    /// "Manage Focus profiles" pointer link tap — routes into 211
    /// Settings's Focus Mode toggles card (source of truth for the per-
    /// profile per-category opt-in matrix).
    static let eusoShipperFocusManageProfiles   = Notification.Name("eusoShipperFocusManageProfiles")
}

// MARK: - Shell wrapper + Shipper BottomNav (Me current — Focus surfaces
//          live behind the Me tab)

private func shipperNavLeading() -> [NavSlot] {
    [
        NavSlot(label: "Home",  systemImage: "house.fill",   isCurrent: false),
        NavSlot(label: "Loads", systemImage: "shippingbox",  isCurrent: false),
    ]
}
private func shipperNavTrailing() -> [NavSlot] {
    [
        NavSlot(label: "Wallet", systemImage: "creditcard",   isCurrent: false),
        NavSlot(label: "Me",     systemImage: "person.fill",  isCurrent: true),
    ]
}

struct ShipperFocusModeWidgetScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperFocusModeWidget()
        } nav: {
            BottomNav(leading: shipperNavLeading(),
                      trailing: shipperNavTrailing(),
                      orbState: .idle)
        }
    }
}

// MARK: - Previews (Dark + Light per §11.4 doctrine)

#Preview("Shipper Focus Mode Widget · Dark") {
    ShipperFocusModeWidgetScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Shipper Focus Mode Widget · Light") {
    ShipperFocusModeWidgetScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}
