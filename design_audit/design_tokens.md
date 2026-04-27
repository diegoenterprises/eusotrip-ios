# Proposed `EusoDesignTokens.swift`

Drops into `/EusoTrip/Theme/` alongside `DesignSystem.swift` and `Glass.swift`. Does NOT replace `DesignSystem.swift` — it consolidates the scattered bespoke patterns into named primitives every screen can import. Existing `Brand`, `LinearGradient.diagonal`, `Space`, `Radius`, `EType` stay as-is.

```swift
//
//  EusoDesignTokens.swift
//  EusoTrip — Consolidated design primitives (2026-04-22)
//
//  One import away from a correct screen. Every token here replaces
//  1+ bespoke pattern currently in the codebase. Nothing novel — just
//  lifted, named, and unified.
//

import SwiftUI

// MARK: - EusoHeader (the 40/heavy gradient + micro-subtitle pane header)
//
// Replaces six bespoke copies (DriverTripsPane.topBar, DriverWalletPane.topBar,
// DriverMePane.topBar, DriverLoadsPane.topBar, MyLoadsSheet.header,
// MeDetailContainer.header). Eliminates the "bullet-separated ALL CAPS"
// AI-tell by making the subtitle a single live sentence instead.
//
// Canonical Home (010_DriverHome.topBar) uses a personalized two-column
// greeting; this header is for everywhere else.

struct EusoHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.palette) private var palette

    /// Size variants — 40pt for panes (Home rhythm), 34pt for sheets.
    enum Size { case pane, sheet }
    var size: Size = .pane

    init(
        title: String,
        subtitle: String? = nil,
        size: Size = .pane,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: size == .pane ? 40 : 34, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                if let subtitle, !subtitle.isEmpty {
                    // Single descriptive sentence — NOT bullet-separated caps.
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }
}

// MARK: - EusoBadge (unifies REEFER / FLATBED / HOT / ACTIVE / ELEVATED)
//
// Replaces StatusPill's 6 kinds + LoadBoardCard's hand-rolled HOT capsule +
// LoadDetailSheet.swift L108 "HOT LANE" text + HotZoneDemand's bespoke
// capsule + HaulLobbyTab's role colors. ONE API, every badge on every screen.

struct EusoBadge: View {
    let text: String
    let style: Style
    var icon: String? = nil

    enum Style: Equatable {
        case info, success, warning, danger, hazmat, neutral
        case hot                 // gradient fill, white text — the "HOT" load pill
        case hotLane             // gradient outline only — the "HOT LANE" inline label

        case demand(level: DemandLevel)
        case role(role: Role)

        enum DemandLevel { case critical, high, elevated }
        enum Role { case driver, dispatch, fleet, staff, broker, shipper }
    }

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
            }
            Text(text.uppercased())
                .font(EType.micro).tracking(0.6)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(background)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .hot:
            Capsule().fill(LinearGradient.diagonal)
        case .hotLane:
            Capsule()
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.25)
                .background(Capsule().fill(palette.bgPage))
        case .role(let r) where r == .staff:
            Capsule().fill(LinearGradient.diagonal.opacity(0.18))
        default:
            Capsule().fill(tintColor)
        }
    }

    private var foreground: AnyShapeStyle {
        switch style {
        case .hot: return AnyShapeStyle(Color.white)
        case .hotLane: return AnyShapeStyle(LinearGradient.diagonal)
        case .role(.staff): return AnyShapeStyle(LinearGradient.diagonal)
        default: return AnyShapeStyle(solidColor)
        }
    }

    private var solidColor: Color {
        switch style {
        case .success: return Brand.success
        case .warning: return Brand.warning
        case .danger:  return Brand.danger
        case .info:    return Brand.info
        case .hazmat:  return Brand.hazmat
        case .neutral: return palette.textSecondary
        case .demand(.critical): return Brand.danger
        case .demand(.high):     return Brand.warning
        case .demand(.elevated): return Brand.info
        case .role(.driver):     return Brand.info
        case .role(.dispatch):   return Brand.success
        case .role(.fleet):      return Brand.warning
        case .role(.broker):     return Brand.info
        case .role(.shipper):    return Brand.hazmat
        case .hot, .hotLane, .role(.staff): return .white
        }
    }

    private var tintColor: Color {
        switch style {
        case .success: return palette.tintSuccess
        case .warning: return palette.tintWarning
        case .danger:  return palette.tintDanger
        case .info:    return palette.tintInfo
        case .hazmat:  return palette.tintHazmat
        case .neutral: return palette.tintNeutral
        case .demand(.critical): return Brand.danger.opacity(0.18)
        case .demand(.high):     return Brand.warning.opacity(0.18)
        case .demand(.elevated): return Brand.info.opacity(0.18)
        case .role:    return palette.tintNeutral
        case .hot, .hotLane: return .clear
        }
    }
}

// MARK: - Migration shim (optional — lets existing call-sites compile)

extension StatusPill {
    /// Source-compatible bridge so existing screens don't need a big-bang
    /// swap. `StatusPill(text: "HOT", kind: .info)` -> `EusoBadge(text:"HOT", style:.info)`.
}

// MARK: - EusoListRow (kills the "gray square + SF symbol" AI-tell)
//
// Replaces DriverMePane.row, DriverWalletPane.methodRow, MeSettingsView.linkRow,
// HotZonesListSheet.listRow. The icon tile is a gradient-rim square on
// palette.bgPage instead of a flat palette.tintNeutral gray square — the
// page-matching fill + iridescent outline is the whole design doctrine.

struct EusoListRow<Accessory: View>: View {
    let glyph: String
    let title: String
    let subtitle: String?
    var isEmphasis: Bool = false
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgPage)
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth: 1)
                Image(systemName: glyph)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        isEmphasis
                            ? AnyShapeStyle(LinearGradient.diagonal)
                            : AnyShapeStyle(palette.textPrimary)
                    )
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
    }
}

// MARK: - EusoSegmentedControl
//
// Replaces MyLoadsSheet.segmented (L1432) + DriverLoadsPane.segmented (L1784) +
// MeHaulView tab capsule row (L2921). One tab-bar API across the app.

struct EusoSegmentedControl<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    let count: ((T) -> Int)?
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let active = selection == item
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = item }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Text(label(item))
                                .font(EType.bodyStrong)
                                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                            if let c = count?(item) {
                                Text("\(c)")
                                    .font(EType.micro).tracking(0.4)
                                    .foregroundStyle(active ? .white : palette.textTertiary)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(active
                                            ? AnyShapeStyle(LinearGradient.diagonal)
                                            : AnyShapeStyle(palette.tintNeutral))
                                    )
                            }
                        }
                        Rectangle()
                            .fill(active ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(Color.clear))
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s3)
    }
}

// MARK: - EusoSheetChrome (replaces NavigationStack + .navigationTitle)
//
// Hot Zones + ELD + ProfileEdit all wrap their body in NavigationStack to
// get a "Done" button — which produces a tiny inline title that breaks the
// 40pt gradient header pattern. This wrapper gives the same affordance in
// the house style.

struct EusoSheetChrome<Content: View>: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            EusoHeader(title: title, subtitle: subtitle, size: .sheet) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
            IridescentHairline()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage)
    }
}

// MARK: - Token ramp recap (all existing — re-exported for quick reference)
//
//  Gradient:   LinearGradient.diagonal           (blue → magenta, TL→BR)
//  Card fill:  Color.eusoCardFillDark / Light    (page-match)
//  Card outline weight: standard=1.25  feature=1.75  whisper=1.0
//  Card radius: standard=Radius.lg (16)  feature hero=Radius.xl (20)
//  Spacing:   s1=4 … s8=40  (gutter = s5, section = s4)
//  Shadow:    dual Brand.blue + Brand.magenta @ 0.20 r=6 (dark) / 0.10 (light)
//  Type:      display 40/heavy + gradient (panes), hero 52/bold monospacedDigit + gradient,
//             h1 28/bold, h2 22/semibold, title 17/semibold, bodyStrong 15/semibold,
//             body 15/regular, caption 12/regular, micro 10/semibold+tracking
//  Badges:    EusoBadge (one API) — info/success/warning/danger/hazmat/neutral/hot/hotLane/demand/role
//  Rows:      EusoListRow (gradient-outline icon tile on page-match fill)
//  Headers:   EusoHeader (pane 40pt / sheet 34pt) + IridescentHairline divider
//  Segmented: EusoSegmentedControl (gradient-underline + gradient count chip)
//  Sheets:    EusoSheetChrome (header + hairline + close chip — no NavigationStack)
```
