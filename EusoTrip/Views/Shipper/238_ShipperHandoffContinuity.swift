//
//  238_ShipperHandoffContinuity.swift
//  EusoTrip iOS — Shipper Continuity / Handoff / Universal Clipboard
//                 authoring (§35.3 Arc L)
//
//  iOS twin of:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/02 Shipper/Code/
//    238_ShipperHandoffContinuity.swift
//
//  Surface: per-device Continuity authoring. Eighth Arc L brick after
//  231 push → 232 lock screen → 233 watch complication → 234 haptic →
//  235 Focus Mode → 236 widget gallery → 237 App Intents. Three paired
//  Apple devices (iPhone / MacBook Pro / iPad) each carry an
//  NSUserActivity passthrough flag; live endpoints surface a Dock badge
//  / Spotlight handoff affordance. Universal Clipboard last-copy item
//  hydrates the lower CLIPBOARD card.
//
//  §11.2 row 1 active hero anchor (§11.4 row 1):
//    LD-260427-A38FB12C7E · Eusorone Technologies (companyId 1) ·
//    Houston TX → Dallas TX · MC-306 Gasoline UN1203 · $1,900. Diego
//    just finished editing the load on his iPhone; Continuity has
//    posted `com.eusorone.app.LoadDetailActivity` to the boardroom
//    MacBook Pro's Dock. "Run on Mac" promotes the iPhone session into
//    a full Mac session at the same lifecycle stage. Universal
//    Clipboard last copied the same load ID from the Mac twelve
//    seconds ago.
//
//  Doctrine: §2 nav, §3 numbers-first, §4.3 single hairline, §7 breathe
//  density, §11/§11.2/§11.4 Diego canon + MATRIX-50, §17.2 width-locked
//  status grammar, §19.2 file-scoped helpers (PillToggle,
//  GradientLivePill, GradientCapsuleCTA, DeviceDotStrip, InitialsTile,
//  DeviceRow, ClipboardCard, OutlinedGradientCTA), §20.4 no dead
//  buttons, §22.2 counter eyebrow color encodes screen-status, §35.3
//  Arc L iOS-platform integration surfaces.
//
//  Backend (server) endpoints owed (EUSO-2159):
//    continuity.listPairedDevices        -> [PairedDevice]
//    continuity.setHandoffEnabled(deviceId, enabled)
//    continuity.recordActivityHandoff(activityType, fromDeviceId, toDeviceId)
//    continuity.getLastClipboardItem      -> ClipboardItem?
//
//  iOS API surface (consumed by LiveDataStore):
//    ShipperContinuityAPI.currentDevices()             -> [PairedDevice]
//    ShipperContinuityAPI.setEnabled(deviceId:enabled:)
//    ShipperContinuityAPI.promoteSession(toDeviceId:)
//    ShipperContinuityAPI.lastClipboardItem()           -> ClipboardItem?
//
//  iOS framework binding:
//    NSUserActivity / NSUserActivityDelegate / Continuity. Each
//    handoff-enabled screen registers an activity with
//    `activityType = "com.eusorone.app.LoadDetailActivity"` and
//    `userInfo = ["loadId": "LD-..."]`. Continuity broadcasts to
//    iCloud-paired devices via Bluetooth LE; receivers surface a
//    Dock-badge / app-switcher affordance that re-instantiates the
//    activity on tap. UIPasteboard.general pushes Universal Clipboard
//    items via the same iCloud channel.
//
//  Both #Preview blocks (Dark + Light) ship per §11.4 doctrine.
//

import SwiftUI

// MARK: - Screen

struct ShipperHandoffContinuity: View {
    @Environment(\.palette) var palette

    private let counterEyebrow = "3 DEVICES · 2 ACTIVE"

    private let activeHandoff = ActiveHandoff(
        id:                 "handoff_2026-04-29T13:30:00Z_loaddetail",
        activeLabel:        "ACTIVE · LOAD DETAIL · IPHONE \u{2192} MAC",
        headline:           "Pick up on Mac",
        bindingAndCount:    "NSUserActivity · LD-260427-A38FB12C7E",
        passthroughEyebrow: "DEVICES · 3 PAIRED",
        passthroughCaption: "MATRIX-50 · row 1 · Houston\u{2192}Dallas",
        relativeAgo:        "passed 38s ago",
        ctaLabel:           "Run on Mac",
        // 0 iPhone, 1 MacBook Pro, 2 iPad
        passthrough: [true, true, false]
    )

    private let devices: [PairedDevice] = [
        PairedDevice(
            id:          "iphone",
            initials:    "IP",
            name:        "Diego\u{2019}s iPhone 17 Pro Max",
            spec:        "iOS 19.3 · A19 Pro · 5G · this device",
            binding:     "LoadDetailActivity · LD-\u{2026}A38FB12C7E",
            enabled:     true
        ),
        PairedDevice(
            id:          "macbook_pro",
            initials:    "MA",
            name:        "Diego\u{2019}s MacBook Pro 16\u{201D}",
            spec:        "macOS 16.4 · M5 Max · Wi-Fi 7 · boardroom",
            binding:     "Dock badge · awaiting handoff",
            enabled:     true
        ),
        PairedDevice(
            id:          "ipad_pro",
            initials:    "TA",
            name:        "Diego\u{2019}s iPad Pro 13\u{201D}",
            spec:        "iPadOS 19.3 · M4 · Wi-Fi · idle 2h 14m",
            binding:     "no NSUserActivity exposed",
            enabled:     false
        )
    ]

    private let activeDeviceId: String = "iphone"

    private let clipboardItem = ClipboardItem(
        id:           "clip_2026-04-29T13:29:48Z_loadid",
        eyebrowLeft:  "LAST COPIED · 12s AGO",
        eyebrowRight: "FROM MACBOOK PRO",
        loadId:       "LD-260427-A38FB12C7E",
        subLine:      "paste in Numbers/Sheets to log · Houston\u{2192}Dallas · MC-306 UN1203 · $1,900",
        ctaLabel:     "Paste"
    )

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, Space.s5)
            titleBlock
                .padding(.top, Space.s3)

            IridescentHairline()
                .padding(.top, Space.s3)

            sectionLabel("ACTIVE HANDOFF · LOAD DETAIL")
                .padding(.top, Space.s5)
            heroCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("DEVICES · 3 PAIRED")
                .padding(.top, Space.s5)
            devicesCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("CLIPBOARD · UNIVERSAL")
                .padding(.top, Space.s5)
            ClipboardCard(item: clipboardItem,
                          onPasteTap: tapPasteClipboard)
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
            Text("\u{2726} SHIPPER · HANDOFF")
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
                .accessibilityLabel("Three paired Apple devices. Two are currently live handoff endpoints.")
        }
        .padding(.horizontal, Space.s5)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Handoff")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Continuity · Eusorone Technologies")
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
                GradientLivePill(label: activeHandoff.activeLabel)
                Spacer(minLength: 0)
                Text(activeHandoff.relativeAgo)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(activeHandoff.headline)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)

                Text(activeHandoff.bindingAndCount)
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
                    Text(activeHandoff.passthroughEyebrow)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)

                    HStack(alignment: .center, spacing: 0) {
                        DeviceDotStrip(payload: activeHandoff.passthrough)
                        Spacer().frame(width: 8)
                        Text(activeHandoff.passthroughCaption)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }

                Spacer(minLength: 0)

                Button(action: tapRunOnMac) {
                    GradientCapsuleCTA(label: activeHandoff.ctaLabel, width: 140)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Run the active handoff on the Mac — promotes the iPhone session into a Mac session via NSUserActivity continuation.")
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

    private var devicesCard: some View {
        VStack(spacing: 0) {
            ForEach(devices.indices, id: \.self) { idx in
                DeviceRow(
                    device:       devices[idx],
                    isActive:     devices[idx].id == activeDeviceId,
                    onToggleTap:  { tapDeviceToggle(devices[idx]) },
                    onRowTap:     { tapDeviceRow(devices[idx]) }
                )
                if idx < devices.count - 1 {
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
        Button(action: tapManageContinuity) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Continuity integration")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Per-device passthrough matrix · 211 Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\u{2192}")
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
        .accessibilityLabel("Manage Continuity integration. Per-device passthrough matrix lives in 211 Settings.")
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Powered by Continuity · Apple Handoff · Universal Clipboard")
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

    private func tapRunOnMac() {
        NotificationCenter.default.post(
            name: .eusoShipperHandoffRun,
            object: nil,
            userInfo: [
                "source": "238_ShipperHandoffContinuity",
                "handoffId": activeHandoff.id,
                "activeDeviceId": activeDeviceId,
                "targetDeviceId": "macbook_pro",
                "loadId": "LD-260427-A38FB12C7E",
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapDeviceToggle(_ device: PairedDevice) {
        NotificationCenter.default.post(
            name: .eusoShipperHandoffToggle,
            object: nil,
            userInfo: [
                "source": "238_ShipperHandoffContinuity",
                "deviceId": device.id,
                "priorEnabled": device.enabled,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapDeviceRow(_ device: PairedDevice) {
        NotificationCenter.default.post(
            name: .eusoShipperHandoffRow,
            object: nil,
            userInfo: [
                "source": "238_ShipperHandoffContinuity",
                "deviceId": device.id,
                "binding": device.binding,
                "isActiveDevice": device.id == activeDeviceId,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapPasteClipboard() {
        NotificationCenter.default.post(
            name: .eusoShipperHandoffClipboardPaste,
            object: nil,
            userInfo: [
                "source": "238_ShipperHandoffContinuity",
                "clipboardItemId": clipboardItem.id,
                "loadId": clipboardItem.loadId,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapManageContinuity() {
        NotificationCenter.default.post(
            name: .eusoShipperHandoffManage,
            object: nil,
            userInfo: [
                "source": "238_ShipperHandoffContinuity",
                "targetScreen": "211 Settings",
                "shipperCompanyId": 1
            ]
        )
    }
}

// MARK: - Domain models (file-scoped — wired by LiveDataStore from
//          ShipperContinuityAPI.currentDevices() + continuity.listPairedDevices
//          + continuity.getLastClipboardItem)

private struct ActiveHandoff {
    let id:                 String
    let activeLabel:        String
    let headline:           String
    let bindingAndCount:    String
    let passthroughEyebrow: String
    let passthroughCaption: String
    let relativeAgo:        String
    let ctaLabel:           String
    let passthrough:        [Bool]
}

private struct PairedDevice: Identifiable {
    let id:       String
    let initials: String
    let name:     String
    let spec:     String
    let binding:  String
    let enabled:  Bool
}

private struct ClipboardItem {
    let id:           String
    let eyebrowLeft:  String
    let eyebrowRight: String
    let loadId:       String
    let subLine:      String
    let ctaLabel:     String
}

// MARK: - GradientLivePill (240×22 ACTIVE pill — 234/235/236/237 recipe)

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

// MARK: - GradientCapsuleCTA (140×22 hero CTA — 234/235/236/237 recipe)

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

// MARK: - DeviceDotStrip (3-dot visualizer — gradient pair when device
//          is a live passthrough endpoint, neutral pair when idle;
//          lifted from 235/236/237's CategoryDotStrip recipe)

private struct DeviceDotStrip: View {
    @Environment(\.palette) var palette
    let payload: [Bool]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(payload.indices, id: \.self) { idx in
                ZStack {
                    if payload[idx] {
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

// MARK: - InitialsTile (36×36 — gradient fill + white mono initials when
//          live, neutral fill + textTertiary mono initials when idle;
//          lifted verbatim from 237 with semantic pivot from "intent
//          enabled" to "device live")

private struct InitialsTile: View {
    @Environment(\.palette) var palette
    let initials: String
    let enabled:  Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(enabled
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.textPrimary.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(enabled
                                      ? Color.clear
                                      : palette.borderFaint)
                )
            Text(initials)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(enabled
                                 ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(palette.textTertiary))
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

// MARK: - DeviceRow (per-device row — initials tile + name + spec +
//          activity binding + PillToggle; active row gets 12% gradient
//          wash, leading marker dot, gradient title/binding/chevron)

private struct DeviceRow: View {
    @Environment(\.palette) var palette
    let device:       PairedDevice
    let isActive:     Bool
    let onToggleTap:  () -> Void
    let onRowTap:     () -> Void

    var body: some View {
        Button(action: onRowTap) {
            ZStack(alignment: .leading) {
                if isActive {
                    LinearGradient.primary
                        .opacity(0.12)
                }

                HStack(alignment: .center, spacing: 14) {
                    if isActive {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 6, height: 6)
                            .padding(.leading, 4)
                    } else {
                        Color.clear.frame(width: 10, height: 6)
                    }

                    InitialsTile(initials: device.initials,
                                 enabled:  device.enabled)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textPrimary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(device.spec)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        HStack(alignment: .center, spacing: 6) {
                            Text(device.binding)
                                .font(EType.mono(.micro))
                                .tracking(0.3)
                                .foregroundStyle(isActive
                                                 ? AnyShapeStyle(LinearGradient.primary)
                                                 : AnyShapeStyle(palette.textTertiary))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                            if isActive {
                                Text("\u{2192}")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(LinearGradient.primary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onToggleTap) {
                        PillToggle(enabled: device.enabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(device.name), \(device.enabled ? "enabled" : "disabled")")
                    .accessibilityHint("Toggles handoff for the \(device.name).")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(minHeight: 60)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(device.name). \(device.spec). Binds to \(device.binding). \(device.enabled ? "Live passthrough endpoint" : "Idle").\(isActive ? " Active source." : "")")
    }
}

// MARK: - PillToggle (44×24 — 211/234/235/236/237 recipe)

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

// MARK: - ClipboardCard (88pt card with eyebrow row + mono load-ID +
//          sub-line + outlined Paste CTA — lifted from 232's lock-screen
//          mono load-ID display recipe at clipboard-card scale)

private struct ClipboardCard: View {
    @Environment(\.palette) var palette
    let item: ClipboardItem
    let onPasteTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.eyebrowLeft)
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(item.eyebrowRight)
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
            }
            .padding(.top, 16)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.loadId)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(LinearGradient.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(item.subLine)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onPasteTap) {
                    OutlinedGradientCTA(label: item.ctaLabel, width: 76)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste the Universal Clipboard load ID into the active text field.")
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - OutlinedGradientCTA (76×22 outlined gradient pill — for the
//          Paste CTA. Hollow fill, 1.5pt 55%-opacity gradient stroke,
//          gradient-tinted text. Reusable for any "secondary action"
//          where a solid gradient capsule would compete with the screen's
//          primary action.)

private struct OutlinedGradientCTA: View {
    let label: String
    let width: CGFloat

    var body: some View {
        ZStack {
            Capsule()
                .strokeBorder(LinearGradient.primary.opacity(0.55), lineWidth: 1.5)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
        }
        .frame(width: width, height: 22)
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// "Run on Mac" CTA — re-fires the active NSUserActivity donation
    /// via Continuity so the MacBook Pro's Dock badge promotes into a
    /// full session at the same lifecycle stage. Payload: handoffId +
    /// loadId + activeDeviceId + targetDeviceId.
    static let eusoShipperHandoffRun       = Notification.Name("eusoShipperHandoffRun")

    /// Per-device PillToggle tap — flips per-device handoff enabled
    /// state via continuity.setHandoffEnabled. Carries priorEnabled for
    /// revert if the Continuity registration handshake fails.
    static let eusoShipperHandoffToggle    = Notification.Name("eusoShipperHandoffToggle")

    /// Per-device row tap — opens the per-device edit sheet (passthrough
    /// capability matrix, last-handoff timestamp, current NSUserActivity
    /// binding). Tapping the active source row re-fires the activity donation.
    static let eusoShipperHandoffRow       = Notification.Name("eusoShipperHandoffRow")

    /// Universal Clipboard "Paste" CTA tap — pulls the last clipboard
    /// item via UIPasteboard.general and posts it into the active text
    /// field. Payload: clipboardItemId + loadId.
    static let eusoShipperHandoffClipboardPaste = Notification.Name("eusoShipperHandoffClipboardPaste")

    /// "Manage Continuity integration" pointer link tap — routes into
    /// 211 Settings's Continuity card (source of truth for the per-
    /// device passthrough matrix + global Continuity opt-in).
    static let eusoShipperHandoffManage    = Notification.Name("eusoShipperHandoffManage")
}

// MARK: - Shell wrapper + Shipper BottomNav (Me current)

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

struct ShipperHandoffContinuityScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperHandoffContinuity()
        } nav: {
            BottomNav(leading: shipperNavLeading(),
                      trailing: shipperNavTrailing(),
                      orbState: .idle)
        }
    }
}

// MARK: - Previews (Dark + Light per §11.4 doctrine)

#Preview("Shipper Handoff Continuity · Dark") {
    ShipperHandoffContinuityScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Shipper Handoff Continuity · Light") {
    ShipperHandoffContinuityScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}
