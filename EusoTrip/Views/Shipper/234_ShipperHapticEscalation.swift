//
//  234_ShipperHapticEscalation.swift
//  EusoTrip iOS — Shipper Haptic Escalation authoring (§35.3 Arc L)
//
//  iOS twin of:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/02 Shipper/Code/
//    234_ShipperHapticEscalation.swift
//
//  Surface: per-category Taptic Engine + CoreHaptics authoring surface.
//  Each of the seven push categories from 231 routing taxonomy maps to
//  a specific UIImpactFeedbackGenerator / UINotificationFeedbackGenerator
//  / CHHapticEngine tap pattern. The active wrist signature plays back
//  when a real push lands inside an opted-in category. Fourth Arc L
//  brick after 231 push → 232 lock screen → 233 watch complication.
//
//  §11.4 row 3 anchor (active hero pattern):
//    LD-260427-B41782FF02 · Eusorone Technologies (companyId 1) · Kansas
//    City MO → Omaha NE NH₃ UN1005 escort divergence · Driver Michael
//    Eusorone (Eusotrans LLC USDOT 3 194 882). Hero pattern: 3 sharp
//    taps via UIImpactFeedbackGenerator(.heavy), 0.08s gaps.
//
//  Doctrine: §2 nav, §3 numbers-first, §4.3 single hairline, §7 breathe
//  density, §11/§11.2/§11.4 Diego canon + MATRIX-50, §17.2 width-locked
//  status grammar, §19.2 file-scoped helpers (PillToggle, GradientLivePill,
//  GradientCapsuleCTA, BigPulseDot, DotPattern, PatternRow), §20.4 no
//  dead buttons, §22.2 counter eyebrow color encodes screen-status,
//  §35.3 Arc L iOS-platform integration surfaces.
//
//  Backend (server) endpoints owed (EUSO-2153):
//    hapticPatterns.getForUser              -> [HapticPattern]
//    hapticPatterns.setIntensityForCategory(category, intensity, tapCount)
//    hapticPatterns.setEnabledForCategory(category, enabled)
//    users.getNotificationPreferences       (cross-validation)
//    users.setNotificationPreferences       (cross-validation)
//
//  iOS API surface (consumed by LiveDataStore):
//    ShipperHapticPatternsAPI.currentPatterns()           -> [HapticPattern]
//    ShipperHapticPatternsAPI.setIntensity(category:to:)
//    ShipperHapticPatternsAPI.setEnabled(category:enabled:)
//    ShipperHapticPatternsAPI.testFire(category:)         -> playback
//
//  CoreHaptics binding:
//    UIImpactFeedbackGenerator(.light/.medium/.heavy) — 1-to-3 tap variants
//    UINotificationFeedbackGenerator(.warning)        — late_pickup variant
//    CHHapticEngine + CHHapticPattern                 — late_delivery mixed
//    testFire(category:) dispatches based on pattern.intensity
//
//  Both #Preview blocks (Dark + Light) ship per §11.4 doctrine.
//

import SwiftUI

// MARK: - Screen

struct ShipperHapticEscalation: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL

    private let counterEyebrow = "7 CATEGORIES · 4 ENABLED"

    // §11.4 row 3 active hero pattern.
    private let activePattern = ActiveHapticPattern(
        id:               "hp_2026-04-28T14:14:00Z_hazmat_exception",
        categoryId:       "hazmat_exception",
        categoryLabel:    "ACTIVE · HAZMAT EXCEPTION · UN1005",
        headline:         "GPS escort divergence",
        loadAndGenerator: "LD-260427-B41782FF02 · UIImpactFeedbackGenerator(.heavy)",
        patternEyebrow:   "PATTERN · 3 SHARP TAPS",
        gapsLabel:        "0.08s · 0.08s · 0.08s gaps",
        relativeAgo:      "last fired 38m ago",
        ctaLabel:         "Tap to test on wrist"
    )

    // §35.3 Arc L taxonomy — seven categories sourced verbatim from 231.
    private let categories: [HapticCategory] = [
        HapticCategory(
            id:           "bid_received",
            title:        "Bid received",
            sub:          "→ 205 Load Detail · 1 soft tap · UIImpactFeedbackGenerator(.light)",
            intensity:    .soft,
            tapCount:     1,
            intensityTag: "SOFT · 1 TAP",
            enabled:      true
        ),
        HapticCategory(
            id:           "lifecycle_stage_advance",
            title:        "Lifecycle stage advance",
            sub:          "→ 205 Load Detail · 2 soft taps · 0.12s gap",
            intensity:    .soft,
            tapCount:     2,
            intensityTag: "SOFT · 2 TAPS",
            enabled:      false
        ),
        HapticCategory(
            id:           "hazmat_exception",
            title:        "Hazmat exception alert",
            sub:          "→ 212 Control Tower · 3 SHARP TAPS · UIImpactFeedbackGenerator(.heavy)",
            intensity:    .sharp,
            tapCount:     3,
            intensityTag: "SHARP · 3 TAPS · ACTIVE",
            enabled:      true
        ),
        HapticCategory(
            id:           "detention_exception",
            title:        "Detention exception",
            sub:          "→ 212 Control Tower · 3 medium taps · UIImpactFeedbackGenerator(.medium)",
            intensity:    .medium,
            tapCount:     3,
            intensityTag: "MEDIUM · 3 TAPS",
            enabled:      true
        ),
        HapticCategory(
            id:           "late_pickup",
            title:        "Late pickup risk",
            sub:          "→ 205 Load Detail · 2 medium taps · UINotificationFeedbackGenerator(.warning)",
            intensity:    .medium,
            tapCount:     2,
            intensityTag: "MEDIUM · 2 TAPS",
            enabled:      true
        ),
        HapticCategory(
            id:           "late_delivery",
            title:        "Late delivery risk",
            sub:          "→ 205 Load Detail · 1 soft + 1 medium · CHHapticPattern",
            intensity:    .mixed,
            tapCount:     2,
            intensityTag: "MIXED · 2 TAPS",
            enabled:      false
        ),
        HapticCategory(
            id:           "late_paperwork",
            title:        "Late paperwork",
            sub:          "→ 229 BOL Upload · 1 soft tap · UIImpactFeedbackGenerator(.light)",
            intensity:    .soft,
            tapCount:     1,
            intensityTag: "SOFT · 1 TAP",
            enabled:      false
        )
    ]

    private let activeCategoryId: String = "hazmat_exception"

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, Space.s5)
            titleBlock
                .padding(.top, Space.s3)

            IridescentHairline()
                .padding(.top, Space.s3)

            sectionLabel("ACTIVE PATTERN · HAZMAT EXCEPTION")
                .padding(.top, Space.s5)
            heroCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("PATTERNS · 7 CATEGORIES")
                .padding(.top, Space.s5)
            patternsCard
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

    // MARK: - TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · HAPTICS")
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
                .accessibilityLabel("Seven push categories total. Four currently have haptic patterns enabled.")
        }
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Haptic feedback")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Tap pattern per push category · Eusorone Technologies")
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

    // MARK: - HERO CARD (active pattern)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                GradientLivePill(label: activePattern.categoryLabel)
                Spacer(minLength: 0)
                Text(activePattern.relativeAgo)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(activePattern.headline)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)

                Text(activePattern.loadAndGenerator)
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
                    Text(activePattern.patternEyebrow)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)

                    HStack(alignment: .center, spacing: 0) {
                        BigPulseDot()
                        Spacer().frame(width: 12)
                        BigPulseDot()
                        Spacer().frame(width: 12)
                        BigPulseDot()
                        Spacer().frame(width: 8)
                        Text(activePattern.gapsLabel)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                Button(action: tapTestPattern) {
                    GradientCapsuleCTA(label: activePattern.ctaLabel, width: 140)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Test the active haptic pattern on your wrist now.")
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

    // MARK: - PATTERNS · 7 CATEGORIES card

    private var patternsCard: some View {
        VStack(spacing: 0) {
            ForEach(categories.indices, id: \.self) { idx in
                PatternRow(
                    category: categories[idx],
                    isActive: categories[idx].id == activeCategoryId,
                    onToggleTap: { tapCategoryToggle(categories[idx]) },
                    onRowTap:    { tapCategoryRow(categories[idx]) }
                )
                if idx < categories.count - 1 {
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

    // MARK: - Settings pointer

    private var settingsPointerLink: some View {
        Button(action: tapManageHapticPrefs) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage haptic categories")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Per-category opt-in + intensity prefs · 211 Settings")
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
        .accessibilityLabel("Manage haptic categories. Per-category opt-in and intensity preferences live in 211 Settings.")
    }

    // MARK: - Footer (engine attribution + persona+batch anchor)

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Powered by Taptic Engine · CoreHaptics · UIFeedbackGenerator family")
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

    private func tapTestPattern() {
        NotificationCenter.default.post(
            name: .eusoShipperHapticTestPattern,
            object: nil,
            userInfo: [
                "source": "234_ShipperHapticEscalation",
                "patternId": activePattern.id,
                "categoryId": activePattern.categoryId,
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/haptic/test/\(activePattern.id)") {
            openURL(url)
        }
    }

    private func tapCategoryToggle(_ category: HapticCategory) {
        NotificationCenter.default.post(
            name: .eusoShipperHapticCategoryToggle,
            object: nil,
            userInfo: [
                "source": "234_ShipperHapticEscalation",
                "categoryId": category.id,
                "priorEnabled": category.enabled,
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/haptic/category/\(category.id)/toggle") {
            openURL(url)
        }
    }

    private func tapCategoryRow(_ category: HapticCategory) {
        NotificationCenter.default.post(
            name: .eusoShipperHapticCategoryRow,
            object: nil,
            userInfo: [
                "source": "234_ShipperHapticEscalation",
                "categoryId": category.id,
                "intensity": category.intensity.rawValue,
                "tapCount": category.tapCount,
                "isActiveCategory": category.id == activeCategoryId,
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/haptic/category/\(category.id)") {
            openURL(url)
        }
    }

    private func tapManageHapticPrefs() {
        NotificationCenter.default.post(
            name: .eusoShipperHapticManagePrefs,
            object: nil,
            userInfo: [
                "source": "234_ShipperHapticEscalation",
                "targetScreen": "211 Settings",
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/settings/haptics") {
            openURL(url)
        }
    }
}

// MARK: - Domain models (file-scoped — wired by LiveDataStore from
//          ShipperHapticPatternsAPI.currentPatterns() + hapticPatterns.getForUser)

private struct ActiveHapticPattern {
    let id:               String
    let categoryId:       String
    let categoryLabel:    String
    let headline:         String
    let loadAndGenerator: String
    let patternEyebrow:   String
    let gapsLabel:        String
    let relativeAgo:      String
    let ctaLabel:         String
}

private enum HapticIntensity: String {
    case sharp
    case medium
    case soft
    case mixed
}

private struct HapticCategory: Identifiable {
    let id:           String
    let title:        String
    let sub:          String
    let intensity:    HapticIntensity
    let tapCount:     Int
    let intensityTag: String
    let enabled:      Bool
}

// MARK: - GradientLivePill (240×22 ACTIVE pill — wider than 232's 220×22
//          to fit "HAZMAT EXCEPTION · UN1005" caption)

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

// MARK: - GradientCapsuleCTA (140×22 hero CTA — narrower than 232's
//          full-width because it shares the hero card width with the
//          pattern visualizer)

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

// MARK: - BigPulseDot (12pt gradient dot with halo — hero pattern visualizer)

private struct BigPulseDot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient.primary.opacity(0.30))
                .frame(width: 16, height: 16)
            Circle()
                .fill(LinearGradient.primary)
                .frame(width: 12, height: 12)
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - DotPattern (n-dot intensity-sized visualizer for a row's
//          pattern cell — sharp = 3pt gradient, medium = 2.5pt warning,
//          soft = 2pt textTertiary, mixed = soft+medium sequence)

private struct DotPattern: View {
    @Environment(\.palette) var palette
    let intensity: HapticIntensity
    let tapCount:  Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<tapCount, id: \.self) { idx in
                dot(at: idx)
            }
        }
    }

    @ViewBuilder
    private func dot(at idx: Int) -> some View {
        switch intensity {
        case .sharp:
            Circle()
                .fill(LinearGradient.primary)
                .frame(width: 6, height: 6)
        case .medium:
            Circle()
                .fill(Color(red: 1.0, green: 0.478, blue: 0.0))
                .frame(width: 5, height: 5)
        case .soft:
            Circle()
                .fill(palette.textTertiary)
                .frame(width: 4, height: 4)
        case .mixed:
            if idx == 0 {
                Circle()
                    .fill(palette.textTertiary)
                    .frame(width: 4, height: 4)
            } else {
                Circle()
                    .fill(Color(red: 1.0, green: 0.478, blue: 0.0))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

// MARK: - PatternRow (per-category row — title + sub + dot pattern +
//          intensity tag + PillToggle; active row gets a 12% gradient
//          wash, gradient title, gradient intensity tag, gradient chevron,
//          and a leading 6pt gradient dot)

private struct PatternRow: View {
    @Environment(\.palette) var palette
    let category: HapticCategory
    let isActive: Bool
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
                            .padding(.top, 14)
                            .padding(.leading, 8)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textPrimary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(category.sub)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        HStack(alignment: .center, spacing: 12) {
                            DotPattern(intensity: category.intensity, tapCount: category.tapCount)
                            Text(category.intensityTag)
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.6)
                                .foregroundStyle(isActive
                                                 ? AnyShapeStyle(LinearGradient.primary)
                                                 : AnyShapeStyle(palette.textTertiary))
                            Spacer(minLength: 0)
                            if isActive {
                                Text("→")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(LinearGradient.primary)
                                    .padding(.trailing, 56)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onToggleTap) {
                        PillToggle(enabled: category.enabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(category.title), \(category.enabled ? "on" : "off")")
                    .accessibilityHint("Toggles the haptic feedback for the \(category.title.lowercased()) push category.")
                    .padding(.top, 16)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(category.title). \(category.intensityTag). \(category.enabled ? "Enabled" : "Disabled").\(isActive ? " Active." : "")")
    }
}

// MARK: - PillToggle (44×24 — gradient when ON, neutral 10% black when
//          OFF — same recipe as 211 ShipperSettings's notification-pref
//          toggle row)

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
    /// "Tap to test on wrist" CTA — fires the active pattern through
    /// ShipperHapticPatternsAPI.testFire(category:), which dispatches to
    /// UIImpactFeedbackGenerator / UINotificationFeedbackGenerator /
    /// CHHapticEngine based on intensity. Payload: patternId + categoryId.
    static let eusoShipperHapticTestPattern    = Notification.Name("eusoShipperHapticTestPattern")

    /// Per-category PillToggle tap — flips per-category enabled state via
    /// hapticPatterns.setEnabledForCategory. Carries priorEnabled so the
    /// receiver can revert if the server rejects the update.
    static let eusoShipperHapticCategoryToggle = Notification.Name("eusoShipperHapticCategoryToggle")

    /// Per-category row tap — opens the intensity-edit sheet (sharp /
    /// medium / soft + tap-count picker + custom CHHaptic builder for
    /// the "mixed" intensity). Tapping the active row re-fires test playback.
    static let eusoShipperHapticCategoryRow    = Notification.Name("eusoShipperHapticCategoryRow")

    /// "Manage haptic categories" pointer link tap — routes into 211
    /// Settings's haptic toggles card (source of truth for the per-category
    /// opt-in + intensity prefs).
    static let eusoShipperHapticManagePrefs    = Notification.Name("eusoShipperHapticManagePrefs")
}

// MARK: - Shell wrapper + Shipper BottomNav (Me current — Haptic surfaces
//          live behind the Me tab in the Shipper IA)

private func shipperNavLeading() -> [NavSlot] {
    [
        NavSlot(label: "Home",  systemImage: "house.fill",   isCurrent: false),
        NavSlot(label: "Loads", systemImage: "shippingbox",  isCurrent: false),
    ]
}
private func shipperNavTrailing() -> [NavSlot] {
    [
        NavSlot(label: "My Loads", systemImage: "creditcard",   isCurrent: false),
        NavSlot(label: "Me",     systemImage: "person.fill",  isCurrent: true),
    ]
}

struct ShipperHapticEscalationScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperHapticEscalation()
        } nav: {
            BottomNav(leading: shipperNavLeading(),
                      trailing: shipperNavTrailing(),
                      orbState: .idle)
        }
    }
}

// MARK: - Previews (Dark + Light per §11.4 doctrine)

#Preview("Shipper Haptic Escalation · Dark") {
    ShipperHapticEscalationScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Shipper Haptic Escalation · Light") {
    ShipperHapticEscalationScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}
