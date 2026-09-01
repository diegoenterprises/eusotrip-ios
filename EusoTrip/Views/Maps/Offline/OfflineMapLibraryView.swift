//
//  OfflineMapLibraryView.swift
//  EusoTrip
//
//  OPERATIONS BOARD archetype. This surface helps an operator verify and
//  maintain the HERE regions required for a journey before connectivity loss.
//  The region register is the accessibility-equivalent source of truth while
//  the native coverage-map renderer is not yet mounted in this surface.
//

import SwiftUI

@MainActor
struct OfflineMapManagementView: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: OfflineMapLibraryViewModel

    init(viewModel: OfflineMapLibraryViewModel) {
        _model = StateObject(wrappedValue: viewModel)
    }

    init(owner: OfflineMapCompositionOwner) {
        _model = StateObject(wrappedValue: OfflineMapLibraryViewModel(owner: owner))
    }

    /// Composition-ready entry for navigation surfaces. The caller must pass
    /// the app's explicit storage policy; this view never invents a reserve or
    /// update-staging multiplier for the device.
    init(
        storagePolicy: OfflineMapStoragePolicy,
        connectivityPolicy: OfflineMapConnectivityPolicy = .radioSilent,
        requiredCapabilities: OfflineMapCapabilities = .fullRoadFreightParity
    ) {
        let owner = OfflineMapComposition.makeOwner(
            storagePolicy: storagePolicy,
            connectivityPolicy: connectivityPolicy,
            requiredCapabilities: requiredCapabilities
        )
        _model = StateObject(wrappedValue: OfflineMapLibraryViewModel(owner: owner))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                orientationHeader
                IridescentHairline()

                if let feedback = model.feedback {
                    feedbackRegister(feedback)
                }

                readinessRegister
                decisionRail
                coverageInstrumentWell
                inventoryScopeRail
                inventoryRegister
                operationRegister
                capabilityRegister

                Color.clear.frame(height: Space.s8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .background(palette.bgPage.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Offline map management")
        .accessibilityValue("\(readinessTitle). \(installedBytesAccessibilityText). \(freeStorageAccessibilityText). Radio silence \(radioSilenceTitle.lowercased()).")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            commandDock
        }
        .task {
            await model.prepare()
        }
        .refreshable {
            await model.refresh()
        }
        .confirmationDialog(
            model.pendingAction?.title ?? "Confirm map-library command",
            isPresented: Binding(
                get: { model.pendingAction != nil },
                set: { if !$0 { model.pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = model.pendingAction {
                Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                    Task { await model.confirmPendingAction() }
                }
            }
            Button("Cancel", role: .cancel) {
                model.pendingAction = nil
            }
        } message: {
            Text(model.pendingAction?.message ?? "")
        }
    }

    // MARK: - Orientation

    private var orientationHeader: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Label("OFFLINE MAP LIBRARY", systemImage: "map.fill")
                    .font(EType.micro)
                    .tracking(1)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text(lastCheckedText)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.trailing)
            }

            HStack(alignment: .top, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Offline map custody")
                        .font(EType.h1)
                        .tracking(-0.4)
                        .foregroundStyle(palette.textPrimary)
                    Text("Inspect the native HERE engine, installed-region register, and storage. Journey corridor coverage requires a separate explicit verification.")
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                readinessPill
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s2) {
                    connectivityMenu
                    recheckButton
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    connectivityMenu
                    recheckButton
                }
            }

            if let reason = model.policyAvailability.disabledReason,
               !model.policyAvailability.isEnabled {
                Label(reason, systemImage: "lock.fill")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var readinessPill: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: readinessSymbol)
            Text(readinessTitle)
        }
        .font(EType.caption.weight(.semibold))
        .foregroundStyle(readinessColor)
        .padding(.horizontal, Space.s3)
        .frame(minHeight: 32)
        .background(Capsule().fill(readinessColor.opacity(0.12)))
        .overlay(Capsule().strokeBorder(readinessColor.opacity(0.35)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Native engine readiness: \(readinessTitle)")
    }

    private var connectivityMenu: some View {
        Menu {
            connectivityPolicyButton(
                .onlineAllowed,
                label: "Allow network for setup",
                systemImage: "network"
            )
            connectivityPolicyButton(
                .radioSilent,
                label: "Enforce radio silence",
                systemImage: "antenna.radiowaves.left.and.right.slash"
            )
        } label: {
            Label(connectivityPolicyTitle, systemImage: connectivityPolicySymbol)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s4)
                .frame(minHeight: 44)
                .background(palette.bgCardSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft)
                )
        }
        .disabled(!model.policyAvailability.isEnabled)
        .accessibilityLabel("Connectivity policy, \(connectivityPolicyTitle)")
        .accessibilityHint(model.policyAvailability.disabledReason ?? "Choose how HERE may use the network.")
    }

    @ViewBuilder
    private func connectivityPolicyButton(
        _ policy: OfflineMapConnectivityPolicy,
        label: String,
        systemImage: String
    ) -> some View {
        let isCurrent = policy == model.snapshot.connectivityPolicy
        let canRetryRadioSilence = policy == .radioSilent && model.snapshot.radioSilenceState != .enforced
        Button {
            Task { await model.setConnectivityPolicy(policy) }
        } label: {
            Label(isCurrent && !canRetryRadioSilence ? "\(label) · Current" : label, systemImage: systemImage)
        }
        .disabled(isCurrent && !canRetryRadioSilence)
    }

    private var recheckButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            Label("Recheck library", systemImage: "arrow.clockwise")
                .font(EType.bodyStrong)
                .foregroundStyle(model.refreshAvailability.isEnabled ? Brand.blue : palette.textTertiary)
                .padding(.horizontal, Space.s4)
                .frame(minHeight: 44)
                .background(Brand.blue.opacity(model.refreshAvailability.isEnabled ? 0.11 : 0.04))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Brand.blue.opacity(model.refreshAvailability.isEnabled ? 0.35 : 0.10))
                )
        }
        .buttonStyle(.plain)
        .disabled(!model.refreshAvailability.isEnabled)
        .accessibilityHint(model.refreshAvailability.disabledReason ?? "Rechecks HERE health, coverage, and storage.")
    }

    // MARK: - Readiness truth

    @ViewBuilder
    private var readinessRegister: some View {
        switch model.snapshot.readiness {
        case .blocked(let blockers):
            VStack(alignment: .leading, spacing: 0) {
                registerHeading(
                    title: "NATIVE ENGINE BLOCKERS",
                    detail: "\(blockers.count) unresolved",
                    systemImage: "exclamationmark.shield.fill",
                    color: Brand.danger
                )
                ForEach(Array(blockers.enumerated()), id: \.offset) { index, blocker in
                    if index > 0 { Divider().overlay(palette.borderFaint) }
                    blockerRow(blocker)
                }
            }
            .padding(Space.s4)
            .background(Brand.danger.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.30))
            )
        case .limited(_, let missing):
            Label {
                Text("The native offline engine is limited. \(missing.individualCapabilities.count) required capability\(missing.individualCapabilities.count == 1 ? " is" : "ies are") not proven.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(EType.caption)
            .foregroundStyle(Brand.warning)
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.warning.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        case .unchecked:
            Label("Native engine readiness has not been checked.", systemImage: "questionmark.diamond")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        case .checking:
            Label("Checking native HERE readiness…", systemImage: "hourglass")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        case .ready:
            Label("Native HERE engine capabilities are ready. Journey corridor coverage is not proven on this screen.", systemImage: "checkmark.shield.fill")
                .font(EType.caption)
                .foregroundStyle(Brand.success)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func blockerRow(_ blocker: OfflineMapReadinessBlocker) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: blockerSymbol(blocker.code))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.danger)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(blockerTitle(blocker.code))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(blocker.message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let recovery = blocker.recovery {
                    Text(recovery)
                        .font(EType.caption)
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, Space.s3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Decision rail

    private var decisionRail: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            registerHeading(
                title: "NATIVE ENGINE & STORAGE",
                detail: "device evidence",
                systemImage: "gauge.with.dots.needle.67percent",
                color: Brand.info
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    decisionCell(
                        label: "INSTALLED DATA",
                        value: installedBytesText,
                        detail: installedFeedDetail,
                        systemImage: "internaldrive.fill",
                        color: Brand.blue
                    )
                    decisionDivider
                    decisionCell(
                        label: "FREE STORAGE",
                        value: freeStorageText,
                        detail: storageFeedDetail,
                        systemImage: "externaldrive.fill.badge.checkmark",
                        color: Brand.info
                    )
                    decisionDivider
                    decisionCell(
                        label: "UPDATES",
                        value: updateCountText,
                        detail: updateFeedDetail,
                        systemImage: "arrow.triangle.2.circlepath",
                        color: updateStatusColor
                    )
                    decisionDivider
                    healthDecisionCell
                    decisionDivider
                    decisionCell(
                        label: "RADIO SILENCE",
                        value: radioSilenceTitle,
                        detail: connectivityPolicyTitle,
                        systemImage: radioSilenceSymbol,
                        color: radioSilenceColor
                    )
                }
                .padding(.vertical, Space.s2)
            }
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderSoft)
            )
        }
    }

    private func decisionCell(
        label: String,
        value: String,
        detail: String,
        systemImage: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label(label, systemImage: systemImage)
                .font(EType.micro)
                .tracking(0.7)
                .foregroundStyle(color)
                .lineLimit(1)
            Text(value)
                .font(EType.title.monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 142, idealWidth: 142, maxWidth: 142, minHeight: 92, alignment: .topLeading)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .accessibilityElement(children: .combine)
    }

    private var healthDecisionCell: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label("MAP HEALTH", systemImage: healthSymbol)
                .font(EType.micro)
                .tracking(0.7)
                .foregroundStyle(healthColor)
            Text(healthTitle)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
            Button {
                model.requestRepair()
            } label: {
                Label("Repair", systemImage: "wrench.and.screwdriver")
                    .font(EType.caption.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.repairAvailability.isEnabled ? Brand.warning : palette.textTertiary)
            .disabled(!model.repairAvailability.isEnabled)
            .accessibilityHint(model.repairAvailability.disabledReason ?? "Repairs HERE persistent map data.")
        }
        .frame(minWidth: 142, idealWidth: 142, maxWidth: 142, minHeight: 92, alignment: .topLeading)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private var decisionDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 88)
    }

    // MARK: - Coverage instrument

    private var coverageInstrumentWell: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            registerHeading(
                title: "COVERAGE INSTRUMENT",
                detail: "verified text register · native map pending",
                systemImage: "scope",
                color: Brand.magenta
            )

            ZStack {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgSecondary)
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderStrong)

                VStack(spacing: Space.s3) {
                    ZStack {
                        Image(systemName: "map.fill")
                            .font(.system(size: 42, weight: .regular))
                            .foregroundStyle(LinearGradient.diagonal)
                        Image(systemName: "slash.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Brand.warning)
                            .offset(x: 24, y: 18)
                    }
                    Text("Native coverage map unavailable")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("A native coverage preview is unavailable in this build. The verified region register below remains the source of truth; no stock or substitute map is shown.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Space.s5)
                }
            }
            .frame(minHeight: 180)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Inventory register

    private var inventoryScopeRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(OfflineMapLibraryScope.allCases) { scope in
                    Button {
                        selectScope(scope)
                    } label: {
                        HStack(spacing: Space.s2) {
                            Image(systemName: scope.systemImage)
                            Text(scope.title)
                            Text(scopeCount(scope))
                                .font(EType.mono(.micro))
                                .foregroundStyle(scope == model.scope ? palette.textOnGradient : palette.textTertiary)
                        }
                        .font(EType.bodyStrong)
                        .foregroundStyle(scope == model.scope ? palette.textOnGradient : palette.textSecondary)
                        .padding(.horizontal, Space.s4)
                        .frame(minHeight: 44)
                        .background(scope == model.scope ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().strokeBorder(scope == model.scope ? Color.clear : palette.borderSoft)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scope == model.scope ? .isSelected : [])
                }
            }
        }
        .accessibilityLabel("Coverage register view")
    }

    @ViewBuilder
    private var inventoryRegister: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.scope {
            case .installed:
                feedStatus(model.snapshot.installedRegionsState, feedName: "Installed regions")
                installedRegister
            case .available:
                feedStatus(model.snapshot.downloadableCatalogState, feedName: "Downloadable catalog")
                availableRegister
            case .updates:
                feedStatus(model.snapshot.installedRegionsState, feedName: "Update status")
                updatesRegister
            }
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderSoft)
        )
    }

    @ViewBuilder
    private var installedRegister: some View {
        if model.snapshot.installedRegions.isEmpty {
            inventoryEmptyState(
                systemImage: "internaldrive",
                title: installedEmptyTitle,
                detail: installedEmptyDetail
            )
        } else {
            ForEach(Array(model.snapshot.installedRegions.enumerated()), id: \.element.id) { index, region in
                if index > 0 { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                installedRow(region)
            }
        }
    }

    private func installedRow(_ region: OfflineMapInstalledRegion) -> some View {
        let selected = model.installedSelection.contains(region.id)
        return Button {
            model.toggleInstalled(region)
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(selected ? Brand.blue : palette.textTertiary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(region.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("\(OfflineMapLibraryFormat.bytes(region.installedBytes)) · \(catalogText(region.catalogVersion))")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verificationText(region.lastVerifiedAt))
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: Space.s2)
                stateBadge(installedStateTitle(region.state), color: installedStateColor(region.state))
            }
            .padding(Space.s4)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(region.name), \(installedStateTitle(region.state)), \(OfflineMapLibraryFormat.bytes(region.installedBytes)), \(selected ? "selected" : "not selected")")
        .accessibilityHint("Selects this installed region for removal.")
    }

    @ViewBuilder
    private var availableRegister: some View {
        if model.availableRegionEntries.isEmpty {
            inventoryEmptyState(
                systemImage: "map",
                title: availableEmptyTitle,
                detail: availableEmptyDetail
            )
        } else {
            let installedStates = model.snapshot.installedRegions.reduce(
                into: [OfflineMapRegionID: OfflineMapInstalledRegionState]()
            ) { result, region in
                result[region.id] = region.state
            }
            ForEach(Array(model.availableRegionEntries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                availableRow(entry, installedState: installedStates[entry.id])
            }
        }
    }

    private func availableRow(
        _ entry: OfflineMapRegionRegisterEntry,
        installedState: OfflineMapInstalledRegionState?
    ) -> some View {
        let region = entry.region
        let selected = model.availableSelection.contains(region.id)
        let isInstalled = installedState?.isUsableCoverage == true
        let isResumable = installedState?.isResumableTransfer == true
        return Button {
            model.toggleAvailable(region)
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: isInstalled ? "checkmark.square.fill" : (selected ? "checkmark.square.fill" : "square"))
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isInstalled ? Brand.success : (selected ? Brand.blue : palette.textTertiary))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(region.name)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .multilineTextAlignment(.leading)
                        if region.childCount > 0 {
                            Text("\(region.childCount) subregion\(region.childCount == 1 ? "" : "s")")
                                .font(EType.micro)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    Text("\(regionLevelTitle(region.level)) · \(OfflineMapLibraryFormat.optionalBytes(region.estimatedDownloadBytes))")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                if isInstalled {
                    stateBadge("Installed", color: Brand.success)
                } else if isResumable {
                    stateBadge(selected ? "Resume selected" : "Resume", color: Brand.info)
                } else {
                    Label(selected ? "Selected" : "Select", systemImage: selected ? "checkmark" : "plus")
                        .font(EType.micro)
                        .foregroundStyle(selected ? Brand.blue : palette.textTertiary)
                }
            }
            .padding(.leading, Space.s4 + CGFloat(min(entry.depth, 6)) * Space.s3)
            .padding(.trailing, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isInstalled)
        .accessibilityLabel("\(region.name), \(regionLevelTitle(region.level)), estimated size \(OfflineMapLibraryFormat.optionalBytes(region.estimatedDownloadBytes)), \(isInstalled ? "installed" : (isResumable ? (selected ? "resume selected" : "incomplete download") : (selected ? "selected" : "not selected")))")
        .accessibilityHint(isInstalled ? "This region is already installed." : (isResumable ? "Selects this incomplete region to resume its HERE download." : "Selects this region for storage preflight and download."))
    }

    @ViewBuilder
    private var updatesRegister: some View {
        if model.updateRegisterRegions.isEmpty {
            inventoryEmptyState(
                systemImage: "checkmark.seal",
                title: updatesEmptyTitle,
                detail: updatesEmptyDetail
            )
        } else {
            ForEach(Array(model.updateRegisterRegions.enumerated()), id: \.element.id) { index, region in
                if index > 0 { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: region.state == .updateAvailable ? "arrow.triangle.2.circlepath" : "questionmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(region.state == .updateAvailable ? Brand.warning : Brand.neutral)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(region.name)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("\(OfflineMapLibraryFormat.bytes(region.installedBytes)) installed · \(catalogText(region.catalogVersion))")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        Text(verificationText(region.lastVerifiedAt))
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: Space.s2)
                    stateBadge(
                        region.state == .updateAvailable ? "Update" : "Status unknown",
                        color: region.state == .updateAvailable ? Brand.warning : Brand.neutral
                    )
                }
                .padding(Space.s4)
                .frame(minHeight: 72)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Operation register

    private var operationRegister: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            registerHeading(
                title: "ACTIVE OPERATION",
                detail: model.snapshot.activeOperation == nil ? "none" : "device task",
                systemImage: "bolt.horizontal.circle",
                color: Brand.blue
            )

            if let operation = model.snapshot.activeOperation {
                ActiveCard {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        HStack(alignment: .top, spacing: Space.s3) {
                            VStack(alignment: .leading, spacing: Space.s1) {
                                Text(model.operationName(operation.kind))
                                    .font(EType.title)
                                    .foregroundStyle(palette.textPrimary)
                                Text(operationPhaseTitle(operation.phase))
                                    .font(EType.caption)
                                    .foregroundStyle(operationPhaseColor(operation.phase))
                            }
                            Spacer(minLength: Space.s2)
                            Text(OfflineMapLibraryFormat.relative(operation.startedAt))
                                .font(EType.mono(.micro))
                                .foregroundStyle(palette.textTertiary)
                        }

                        operationProgress(operation)

                        Label("Keep EusoTrip open until this operation completes; iOS may interrupt a HERE region transfer after the app leaves the foreground.", systemImage: "iphone.and.arrow.forward")
                            .font(EType.caption)
                            .foregroundStyle(Brand.warning)
                            .fixedSize(horizontal: false, vertical: true)

                        if !operation.targetRegionIDs.isEmpty {
                            VStack(alignment: .leading, spacing: Space.s2) {
                                Text("TARGET REGIONS")
                                    .font(EType.micro)
                                    .tracking(0.8)
                                    .foregroundStyle(palette.textTertiary)
                                ForEach(operation.targetRegionIDs, id: \.self) { id in
                                    Label(model.regionName(for: id), systemImage: "mappin.and.ellipse")
                                        .font(EType.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                        }

                        operationControls(operation)
                    }
                }
            } else {
                HStack(spacing: Space.s3) {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(palette.textTertiary)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("No map transfer is active")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("Downloads and catalog updates appear here while running. Keep EusoTrip open until each transfer completes.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Space.s4)
                .eusoRow(radius: Radius.lg)
                .accessibilityElement(children: .combine)
            }

            if let failure = model.snapshot.lastFailure {
                HStack(alignment: .top, spacing: Space.s3) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(Brand.danger)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(failure.message)
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                        if let recovery = failure.recovery {
                            Text(recovery)
                                .font(EType.caption)
                                .foregroundStyle(Brand.warning)
                        }
                        Text("Failure code · \(failure.code)")
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .padding(Space.s4)
                .background(Brand.danger.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Brand.danger.opacity(0.25))
                )
            }
        }
    }

    @ViewBuilder
    private func operationProgress(_ operation: OfflineMapOperationState) -> some View {
        let progress = operation.progress
        VStack(alignment: .leading, spacing: Space.s2) {
            if let fraction = progress?.fractionCompleted {
                ProgressView(value: fraction)
                    .tint(Brand.blue)
                HStack {
                    Text(OfflineMapLibraryFormat.percent(fraction))
                    Spacer()
                    Text(progressBytes(progress))
                }
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textSecondary)
            } else {
                HStack(spacing: Space.s2) {
                    if operation.phase == .running || operation.phase == .preparing || operation.phase == .finalizing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Transfer percentage unknown")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(progressBytes(progress))
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if let detail = progress?.detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(detail)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func operationControls(_ operation: OfflineMapOperationState) -> some View {
        let pauseEnabled = (operation.kind == .downloadRegions || operation.kind == .updatePersistentMap) && operation.phase == .running
        let resumeEnabled = (operation.kind == .downloadRegions || operation.kind == .updatePersistentMap) && operation.phase == .paused
        let cancelEnabled = (operation.kind == .downloadRegions || operation.kind == .updatePersistentMap) && (operation.phase == .running || operation.phase == .paused)

        return VStack(alignment: .leading, spacing: Space.s2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s2) {
                    if resumeEnabled {
                        operationButton("Resume", systemImage: "play.fill", color: Brand.success, enabled: true) {
                            Task { await model.resumeActiveTransfer() }
                        }
                    } else {
                        operationButton("Pause", systemImage: "pause.fill", color: Brand.warning, enabled: pauseEnabled) {
                            Task { await model.pauseActiveTransfer() }
                        }
                    }
                    operationButton("Cancel", systemImage: "xmark", color: Brand.danger, enabled: cancelEnabled) {
                        Task { await model.cancelActiveTransfer() }
                    }
                }
                VStack(spacing: Space.s2) {
                    if resumeEnabled {
                        operationButton("Resume", systemImage: "play.fill", color: Brand.success, enabled: true) {
                            Task { await model.resumeActiveTransfer() }
                        }
                    } else {
                        operationButton("Pause", systemImage: "pause.fill", color: Brand.warning, enabled: pauseEnabled) {
                            Task { await model.pauseActiveTransfer() }
                        }
                    }
                    operationButton("Cancel", systemImage: "xmark", color: Brand.danger, enabled: cancelEnabled) {
                        Task { await model.cancelActiveTransfer() }
                    }
                }
            }
            if !resumeEnabled && !pauseEnabled {
                Text(pauseDisabledReason(operation))
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !cancelEnabled {
                Text(cancelDisabledReason(operation))
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func operationButton(
        _ title: String,
        systemImage: String,
        color: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(EType.bodyStrong)
                .foregroundStyle(enabled ? color : palette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(color.opacity(enabled ? 0.11 : 0.03))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(color.opacity(enabled ? 0.30 : 0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Capability proof

    private var capabilityRegister: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            registerHeading(
                title: "OFFLINE CAPABILITY PROOF",
                detail: "native inspection",
                systemImage: "checkmark.shield",
                color: Brand.success
            )
            VStack(spacing: 0) {
                ForEach(Array(capabilityDescriptors.enumerated()), id: \.offset) { index, descriptor in
                    if index > 0 { Divider().overlay(palette.borderFaint).padding(.leading, 52) }
                    capabilityRow(descriptor)
                }
            }
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderSoft)
            )
        }
    }

    private func capabilityRow(_ descriptor: CapabilityDescriptor) -> some View {
        let state = capabilityState(descriptor.capability)
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: descriptor.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(state.color)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(descriptor.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(descriptor.detail)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            stateBadge(state.title, color: state.color)
        }
        .padding(Space.s4)
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Selection-aware command dock

    private var commandDock: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(commandContextTitle)
                        .font(EType.micro)
                        .tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(commandContextDetail)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                commandButton
            }
            if let reason = currentCommandAvailability.disabledReason,
               !currentCommandAvailability.isEnabled {
                Label(reason, systemImage: "info.circle")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s3)
        .background(.ultraThinMaterial)
        .background(palette.bgNav)
        .overlay(alignment: .top) { IridescentHairline() }
    }

    @ViewBuilder
    private var commandButton: some View {
        switch model.scope {
        case .installed:
            dockButton(
                title: "Remove",
                systemImage: "trash",
                color: Brand.danger,
                availability: model.deleteAvailability
            ) { model.requestDelete() }
        case .available:
            dockButton(
                title: "Check & download",
                systemImage: "square.and.arrow.down",
                color: Brand.blue,
                availability: model.downloadAvailability
            ) { Task { await model.requestDownload() } }
        case .updates:
            dockButton(
                title: "Update all",
                systemImage: "arrow.triangle.2.circlepath",
                color: Brand.warning,
                availability: model.updateAvailability
            ) { model.requestUpdate() }
        }
    }

    private func dockButton(
        title: String,
        systemImage: String,
        color: Color,
        availability: OfflineMapCommandAvailability,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(EType.bodyStrong)
                .foregroundStyle(availability.isEnabled ? palette.textOnGradient : palette.textTertiary)
                .padding(.horizontal, Space.s4)
                .frame(minHeight: 44)
                .background(
                    availability.isEnabled
                        ? AnyShapeStyle(color == Brand.blue ? LinearGradient.primary : LinearGradient(colors: [color, color.opacity(0.78)], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(palette.bgCardSoft)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!availability.isEnabled)
        .accessibilityHint(availability.disabledReason ?? commandContextDetail)
    }

    // MARK: - Shared register pieces

    private func feedbackRegister(_ feedback: OfflineMapLibraryFeedback) -> some View {
        let color: Color = {
            switch feedback.kind {
            case .information: return Brand.info
            case .success: return Brand.success
            case .failure: return Brand.danger
            }
        }()
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: feedback.kind == .success ? "checkmark.circle.fill" : (feedback.kind == .failure ? "xmark.octagon.fill" : "info.circle.fill"))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(feedback.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(feedback.message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
            Button {
                model.dismissFeedback()
            } label: {
                Label("Dismiss", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(palette.textSecondary)
            .accessibilityLabel("Dismiss message")
        }
        .padding(Space.s4)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(color.opacity(0.28))
        )
        .accessibilityElement(children: .contain)
    }

    private func registerHeading(
        title: String,
        detail: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Label(title, systemImage: systemImage)
                .font(EType.micro)
                .tracking(0.9)
                .foregroundStyle(color)
            Spacer(minLength: Space.s2)
            Text(detail)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private func feedStatus(_ state: OfflineMapInventoryFeedState, feedName: String) -> some View {
        let presentation = feedPresentation(state, feedName: feedName)
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: presentation.systemImage)
                .foregroundStyle(presentation.color)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(presentation.title)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(presentation.detail)
                    .font(EType.micro)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s2)
        }
        .padding(Space.s4)
        .background(presentation.color.opacity(0.06))
        Divider().overlay(palette.borderFaint)
    }

    private func inventoryEmptyState(systemImage: String, title: String, detail: String) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text(title)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(detail)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 148)
        .padding(Space.s5)
        .accessibilityElement(children: .combine)
    }

    private func stateBadge(_ title: String, color: Color) -> some View {
        Text(title.uppercased())
            .font(EType.micro)
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, Space.s2)
            .frame(minHeight: 24)
            .background(Capsule().fill(color.opacity(0.11)))
            .overlay(Capsule().strokeBorder(color.opacity(0.25)))
            .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Presentation truth

    private var readinessTitle: String {
        switch model.snapshot.readiness {
        case .unchecked: return "Engine unchecked"
        case .checking: return "Engine checking"
        case .blocked: return "Engine blocked"
        case .limited: return "Engine limited"
        case .ready: return "Engine ready"
        }
    }

    private var readinessSymbol: String {
        switch model.snapshot.readiness {
        case .unchecked: return "questionmark"
        case .checking: return "hourglass"
        case .blocked: return "xmark.shield.fill"
        case .limited: return "exclamationmark.triangle.fill"
        case .ready: return "checkmark.shield.fill"
        }
    }

    private var readinessColor: Color {
        switch model.snapshot.readiness {
        case .unchecked, .checking: return Brand.neutral
        case .blocked: return Brand.danger
        case .limited: return Brand.warning
        case .ready: return Brand.success
        }
    }

    private var connectivityPolicyTitle: String {
        switch model.snapshot.connectivityPolicy {
        case .onlineAllowed: return "Network allowed"
        case .preferOffline: return "Prefer offline"
        case .radioSilent: return "Radio silent"
        }
    }

    private var connectivityPolicySymbol: String {
        switch model.snapshot.connectivityPolicy {
        case .onlineAllowed: return "network"
        case .preferOffline: return "internaldrive"
        case .radioSilent: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var lastCheckedText: String {
        guard let date = model.snapshot.lastRefreshedAt else { return "NOT CHECKED" }
        return "CHECKED · \(OfflineMapLibraryFormat.relative(date).uppercased())"
    }

    private var installedBytesText: String {
        let value: String
        let state: OfflineMapInventoryFeedState
        if let storage = model.snapshot.storage {
            value = OfflineMapLibraryFormat.bytes(storage.installedMapBytes)
            state = model.snapshot.storageState
        } else if model.snapshot.installedRegionsState.lastSuccessfulAt != nil {
            guard let total = OfflineMapByteMath.sum(
                model.snapshot.installedRegions.lazy.map(\.installedBytes)
            ) else { return "Unknown" }
            value = OfflineMapLibraryFormat.bytes(total)
            state = model.snapshot.installedRegionsState
        } else {
            return "Unknown"
        }
        return state.isCurrent ? value : "\(value) · last verified"
    }

    private var freeStorageText: String {
        guard let bytes = model.snapshot.storage?.availableBytes else { return "Unknown" }
        let value = OfflineMapLibraryFormat.bytes(bytes)
        return model.snapshot.storageState.isCurrent ? value : "\(value) · last verified"
    }

    private var installedBytesAccessibilityText: String {
        if model.snapshot.storageState.isCurrent ||
            (model.snapshot.storage == nil && model.snapshot.installedRegionsState.isCurrent) {
            return "\(installedBytesText) installed"
        }
        if model.snapshot.storageState.lastSuccessfulAt != nil ||
            model.snapshot.installedRegionsState.lastSuccessfulAt != nil {
            return "Installed bytes are a last verified snapshot: \(installedBytesText)"
        }
        if case .unavailable = model.snapshot.storageState {
            return "Installed bytes are unavailable and have not been verified."
        }
        if case .unavailable = model.snapshot.installedRegionsState {
            return "Installed bytes are unavailable and have not been verified."
        }
        return "Installed bytes have not yet been verified."
    }

    private var freeStorageAccessibilityText: String {
        if model.snapshot.storageState.isCurrent {
            return "\(freeStorageText) free storage"
        }
        if model.snapshot.storageState.lastSuccessfulAt != nil {
            return "Free storage is a last verified snapshot: \(freeStorageText)"
        }
        if case .unavailable = model.snapshot.storageState {
            return "Free storage is unavailable and has not been verified."
        }
        return "Free storage has not yet been verified."
    }

    private var updateCountText: String {
        guard model.snapshot.installedRegionsState.isCurrent else { return "Unknown" }
        if !model.updateStatusUnknownRegions.isEmpty {
            if model.updateRegions.isEmpty { return "Unknown" }
            return "\(model.updateRegions.count) known"
        }
        return "\(model.updateRegions.count)"
    }

    private var installedFeedDetail: String {
        feedCompactDetail(model.snapshot.installedRegionsState)
    }

    private var storageFeedDetail: String {
        feedCompactDetail(model.snapshot.storageState)
    }

    private var updateFeedDetail: String {
        if !model.updateStatusUnknownRegions.isEmpty {
            return "\(model.updateStatusUnknownRegions.count) status\(model.updateStatusUnknownRegions.count == 1 ? "" : "es") unverified"
        }
        return feedCompactDetail(model.snapshot.installedRegionsState)
    }

    private var updateStatusColor: Color {
        switch model.snapshot.installedRegionsState {
        case .current:
            return model.updateRegions.isEmpty && model.updateStatusUnknownRegions.isEmpty
                ? Brand.neutral
                : Brand.warning
        case .notLoaded, .loading:
            return Brand.neutral
        case .stale:
            return Brand.warning
        case .unavailable:
            return Brand.danger
        }
    }

    private var healthTitle: String {
        switch model.snapshot.persistentHealth {
        case .unknown: return "Unknown"
        case .healthy: return "Healthy"
        case .needsRepair: return "Repair needed"
        case .repairing: return "Repairing"
        case .unusable: return "Unusable"
        }
    }

    private var healthSymbol: String {
        switch model.snapshot.persistentHealth {
        case .unknown: return "questionmark.diamond"
        case .healthy: return "checkmark.seal.fill"
        case .needsRepair: return "wrench.and.screwdriver.fill"
        case .repairing: return "gearshape.2.fill"
        case .unusable: return "xmark.octagon.fill"
        }
    }

    private var healthColor: Color {
        switch model.snapshot.persistentHealth {
        case .unknown: return Brand.neutral
        case .healthy: return Brand.success
        case .needsRepair, .repairing: return Brand.warning
        case .unusable: return Brand.danger
        }
    }

    private var radioSilenceTitle: String {
        switch model.snapshot.radioSilenceState {
        case .notRequested: return "Not requested"
        case .applying: return "Applying"
        case .enforced: return "Enforced"
        case .notEnforced: return "Not enforced"
        }
    }

    private var radioSilenceSymbol: String {
        switch model.snapshot.radioSilenceState {
        case .notRequested: return "antenna.radiowaves.left.and.right"
        case .applying: return "hourglass"
        case .enforced: return "antenna.radiowaves.left.and.right.slash"
        case .notEnforced: return "exclamationmark.triangle.fill"
        }
    }

    private var radioSilenceColor: Color {
        switch model.snapshot.radioSilenceState {
        case .notRequested, .applying: return Brand.neutral
        case .enforced: return Brand.success
        case .notEnforced: return Brand.danger
        }
    }

    private func scopeCount(_ scope: OfflineMapLibraryScope) -> String {
        switch scope {
        case .installed:
            return model.snapshot.installedRegionsState.lastSuccessfulAt == nil ? "—" : "\(model.snapshot.installedRegions.count)"
        case .available:
            return model.snapshot.downloadableCatalogState.lastSuccessfulAt == nil ? "—" : "\(model.snapshot.downloadableRegions.count)"
        case .updates:
            guard model.snapshot.installedRegionsState.isCurrent else { return "—" }
            if !model.updateStatusUnknownRegions.isEmpty {
                return model.updateRegions.isEmpty ? "—" : "\(model.updateRegions.count)+?"
            }
            return "\(model.updateRegions.count)"
        }
    }

    private func selectScope(_ scope: OfflineMapLibraryScope) {
        if reduceMotion {
            model.scope = scope
        } else {
            withAnimation(.easeInOut(duration: 0.16)) {
                model.scope = scope
            }
        }
    }

    private var installedEmptyTitle: String {
        switch model.snapshot.installedRegionsState {
        case .current: return "No regions installed"
        case .stale: return "Last verified: no regions installed"
        case .loading: return "Loading installed regions"
        case .notLoaded: return "Installed regions not loaded"
        case .unavailable: return "Installed regions unavailable"
        }
    }

    private var installedEmptyDetail: String {
        switch model.snapshot.installedRegionsState {
        case .current:
            return "This device has zero verified HERE regions. Choose Available while network access is allowed to prepare a journey."
        case .stale(_, let failure):
            return "The last verified installed-map snapshot was empty. Current refresh failed: \(failure.message)"
        case .unavailable(let failure):
            return failure.message
        case .loading:
            return "The device inventory is being read from HERE."
        case .notLoaded:
            return "Recheck the library to read the on-device region inventory."
        }
    }

    private var availableEmptyTitle: String {
        switch model.snapshot.downloadableCatalogState {
        case .current: return "No downloadable regions"
        case .stale: return "Last verified: no downloadable regions"
        case .loading: return "Loading region catalog"
        case .notLoaded: return "Region catalog not loaded"
        case .unavailable: return "Region catalog unavailable"
        }
    }

    private var availableEmptyDetail: String {
        switch model.snapshot.downloadableCatalogState {
        case .current:
            return "HERE returned zero downloadable regions for the current SDK catalog."
        case .stale(_, let failure):
            return "The last verified downloadable catalog snapshot was empty. Current refresh failed: \(failure.message)"
        case .unavailable(let failure):
            return failure.message
        case .loading:
            return "The downloadable HERE region hierarchy is loading."
        case .notLoaded:
            return "Allow network access for setup, then recheck the library."
        }
    }

    private var updatesEmptyTitle: String {
        if !model.updateStatusUnknownRegions.isEmpty { return "Update status unknown" }
        switch model.snapshot.installedRegionsState {
        case .current: return "No updates reported"
        case .stale: return "Update status stale"
        case .loading: return "Checking update status"
        case .notLoaded: return "Update status not loaded"
        case .unavailable: return "Update status unavailable"
        }
    }

    private var updatesEmptyDetail: String {
        if !model.updateStatusUnknownRegions.isEmpty {
            return "Allow network access and recheck to verify whether newer HERE map data is available."
        }
        switch model.snapshot.installedRegionsState {
        case .current:
            return "No installed HERE region currently reports an available update."
        case .stale(_, let failure), .unavailable(let failure):
            return failure.message
        case .loading:
            return "Installed-region status is being checked."
        case .notLoaded:
            return "Recheck the library to read update status."
        }
    }

    private func feedPresentation(
        _ state: OfflineMapInventoryFeedState,
        feedName: String
    ) -> FeedPresentation {
        switch state {
        case .notLoaded:
            return .init(title: "\(feedName) not loaded", detail: "No value is being inferred.", systemImage: "questionmark.circle", color: Brand.neutral)
        case .loading(let lastSuccessfulAt):
            let detail = lastSuccessfulAt.map { "Refreshing; last verified \(OfflineMapLibraryFormat.relative($0))." } ?? "Waiting for the first verified response."
            return .init(title: "\(feedName) loading", detail: detail, systemImage: "hourglass", color: Brand.info)
        case .current(let loadedAt):
            return .init(title: "\(feedName) current", detail: "Verified \(OfflineMapLibraryFormat.relative(loadedAt)).", systemImage: "checkmark.circle.fill", color: Brand.success)
        case .stale(let lastSuccessfulAt, let failure):
            return .init(title: "Showing stale \(feedName.lowercased())", detail: "Last verified \(OfflineMapLibraryFormat.relative(lastSuccessfulAt)). Refresh failed: \(failure.message)", systemImage: "clock.badge.exclamationmark", color: Brand.warning)
        case .unavailable(let failure):
            return .init(title: "\(feedName) unavailable", detail: failure.message, systemImage: "xmark.octagon.fill", color: Brand.danger)
        }
    }

    private func feedCompactDetail(_ state: OfflineMapInventoryFeedState) -> String {
        switch state {
        case .notLoaded: return "not loaded"
        case .loading(let date): return date == nil ? "loading" : "refreshing"
        case .current(let date): return "verified \(OfflineMapLibraryFormat.relative(date))"
        case .stale(let date, _): return "stale · \(OfflineMapLibraryFormat.relative(date))"
        case .unavailable: return "unavailable"
        }
    }

    private func blockerTitle(_ code: OfflineMapReadinessBlockerCode) -> String {
        switch code {
        case .sdkUnavailable: return "HERE Navigate SDK"
        case .sdkInitializationFailed: return "SDK initialization"
        case .credentialsUnavailable: return "SDK credentials"
        case .entitlementUnavailable: return "Navigate entitlement"
        case .persistentMapUnavailable: return "Persistent map"
        case .persistentMapNeedsRepair: return "Persistent map health"
        case .capabilityUnavailable: return "Offline capabilities"
        case .radioSilenceNotEnforced: return "Radio silence"
        case .configurationInvalid: return "SDK configuration"
        }
    }

    private func blockerSymbol(_ code: OfflineMapReadinessBlockerCode) -> String {
        switch code {
        case .sdkUnavailable: return "shippingbox"
        case .sdkInitializationFailed: return "bolt.slash"
        case .credentialsUnavailable: return "key.slash"
        case .entitlementUnavailable: return "person.badge.key"
        case .persistentMapUnavailable: return "map"
        case .persistentMapNeedsRepair: return "wrench.and.screwdriver"
        case .capabilityUnavailable: return "square.stack.3d.up.slash"
        case .radioSilenceNotEnforced: return "antenna.radiowaves.left.and.right"
        case .configurationInvalid: return "gearshape.fill"
        }
    }

    private func installedStateTitle(_ state: OfflineMapInstalledRegionState) -> String {
        switch state {
        case .installed: return "Installed"
        case .updateAvailable: return "Update available"
        case .updateStatusUnknown: return "Update status unknown"
        case .pausedDownload: return "Paused"
        case .incomplete: return "Incomplete"
        }
    }

    private func installedStateColor(_ state: OfflineMapInstalledRegionState) -> Color {
        switch state {
        case .installed: return Brand.success
        case .updateAvailable: return Brand.warning
        case .updateStatusUnknown: return Brand.neutral
        case .pausedDownload: return Brand.info
        case .incomplete: return Brand.danger
        }
    }

    private func regionLevelTitle(_ level: OfflineMapRegionLevel) -> String {
        switch level {
        case .world: return "World"
        case .continent: return "Continent"
        case .country: return "Country"
        case .stateOrProvince: return "State or province"
        case .county: return "County"
        case .city: return "City"
        case .customArea: return "Custom area"
        case .other: return "Other region"
        }
    }

    private func catalogText(_ catalogVersion: String?) -> String {
        guard let catalogVersion, !catalogVersion.isEmpty else { return "catalog unknown" }
        return "catalog \(catalogVersion)"
    }

    private func verificationText(_ date: Date?) -> String {
        guard let date else { return "NOT YET VERIFIED" }
        return "VERIFIED · \(OfflineMapLibraryFormat.relative(date).uppercased())"
    }

    private func operationPhaseTitle(_ phase: OfflineMapOperationPhase) -> String {
        switch phase {
        case .preparing: return "Preparing"
        case .running: return "Running"
        case .pausing: return "Pausing"
        case .paused: return "Paused"
        case .resuming: return "Resuming"
        case .cancelling: return "Cancelling"
        case .finalizing: return "Finalizing and verifying"
        }
    }

    private func operationPhaseColor(_ phase: OfflineMapOperationPhase) -> Color {
        switch phase {
        case .running, .resuming: return Brand.success
        case .paused, .pausing: return Brand.warning
        case .cancelling: return Brand.danger
        case .preparing, .finalizing: return Brand.info
        }
    }

    private func progressBytes(_ progress: OfflineMapTransferProgress?) -> String {
        switch (progress?.completedBytes, progress?.totalBytes) {
        case let (completed?, total?):
            return "\(OfflineMapLibraryFormat.bytes(completed)) / \(OfflineMapLibraryFormat.bytes(total))"
        case let (completed?, nil):
            return "\(OfflineMapLibraryFormat.bytes(completed)) / total unknown"
        case let (nil, total?):
            return "completed unknown / \(OfflineMapLibraryFormat.bytes(total))"
        case (nil, nil):
            return "bytes unknown"
        }
    }

    private func pauseDisabledReason(_ operation: OfflineMapOperationState) -> String {
        guard operation.kind == .downloadRegions || operation.kind == .updatePersistentMap else {
            return "This operation does not support pause or resume."
        }
        switch operation.phase {
        case .preparing: return "Pause becomes available after the transfer starts."
        case .pausing: return "The pause request is being applied."
        case .resuming: return "The transfer is resuming."
        case .cancelling: return "The transfer is being cancelled."
        case .finalizing: return "The transfer is finalizing and can no longer pause."
        case .running, .paused: return ""
        }
    }

    private func cancelDisabledReason(_ operation: OfflineMapOperationState) -> String {
        switch operation.phase {
        case .preparing: return "Cancel becomes available after the transfer starts."
        case .pausing: return "Wait for the transfer to finish pausing before cancelling."
        case .resuming: return "Wait for the transfer to resume before cancelling."
        case .cancelling: return "Cancellation is already in progress."
        case .finalizing: return "The operation is finalizing and can no longer be cancelled."
        case .running, .paused: return "This operation does not support cancellation."
        }
    }

    private func capabilityState(_ capability: OfflineMapCapabilities) -> CapabilityPresentation {
        switch model.snapshot.readiness {
        case .unchecked:
            return .init(title: "Unknown", color: Brand.neutral)
        case .checking:
            return .init(title: "Checking", color: Brand.info)
        case .blocked:
            return .init(title: "Not proven", color: Brand.danger)
        case .limited(let available, _), .ready(let available):
            return available.contains(capability)
                ? .init(title: "Proven", color: Brand.success)
                : .init(title: "Unavailable", color: Brand.danger)
        }
    }

    private var capabilityDescriptors: [CapabilityDescriptor] {
        [
            .init(capability: .persistentRegionLifecycle, title: "Persistent region lifecycle", detail: "Download, inspect, and remove on-device HERE regions.", systemImage: "internaldrive"),
            .init(capability: .offlineVectorRendering, title: "Offline vector rendering", detail: "Render installed vector map data without a network response.", systemImage: "square.stack.3d.up"),
            .init(capability: .detailedRendering, title: "Detailed rendering", detail: "Render the detailed cartographic layer configured for installed regions.", systemImage: "map.fill"),
            .init(capability: .offlineSearch, title: "Local search", detail: "Search installed HERE places and addresses on device.", systemImage: "magnifyingglass"),
            .init(capability: .offlineRoadRouting, title: "Road routing", detail: "Calculate eligible road routes using installed data.", systemImage: "car.fill"),
            .init(capability: .offlineTruckRouting, title: "Truck routing", detail: "Calculate road-freight routes with explicit truck constraints.", systemImage: "truck.box.fill"),
            .init(capability: .offlineGuidance, title: "Maneuver guidance", detail: "Generate on-device maneuver events and text for supported road modes.", systemImage: "location.north.line.fill"),
            .init(capability: .offlineVoiceGuidance, title: "Audible offline guidance", detail: "Speak maneuvers with an installed device-local voice, without a network voice dependency.", systemImage: "speaker.wave.2.fill"),
            .init(capability: .radioSilence, title: "Radio-silent execution", detail: "Prohibit HERE network access when radio silence is enforced.", systemImage: "antenna.radiowaves.left.and.right.slash"),
            .init(capability: .persistentMapRepair, title: "Persistent-map repair", detail: "Repair damaged or incompatible on-device map storage.", systemImage: "wrench.and.screwdriver"),
            .init(capability: .persistentMapUpdates, title: "Persistent-map updates", detail: "Update installed HERE map catalogs with storage preflight.", systemImage: "arrow.triangle.2.circlepath")
        ]
    }

    private var currentCommandAvailability: OfflineMapCommandAvailability {
        switch model.scope {
        case .installed: return model.deleteAvailability
        case .available: return model.downloadAvailability
        case .updates: return model.updateAvailability
        }
    }

    private var commandContextTitle: String {
        switch model.scope {
        case .installed: return "INSTALLED SELECTION"
        case .available: return "DOWNLOAD SELECTION"
        case .updates: return "CATALOG UPDATE"
        }
    }

    private var commandContextDetail: String {
        switch model.scope {
        case .installed:
            return "\(model.installedSelection.count) region\(model.installedSelection.count == 1 ? "" : "s") selected for removal"
        case .available:
            return "\(model.availableSelection.count) region\(model.availableSelection.count == 1 ? "" : "s") selected · storage checked before transfer"
        case .updates:
            guard model.snapshot.installedRegionsState.isCurrent else {
                return "Update status \(feedCompactDetail(model.snapshot.installedRegionsState))"
            }
            if !model.updateStatusUnknownRegions.isEmpty {
                return "\(model.updateRegions.count) known update\(model.updateRegions.count == 1 ? "" : "s") · \(model.updateStatusUnknownRegions.count) status\(model.updateStatusUnknownRegions.count == 1 ? "" : "es") unknown"
            }
            return "\(model.updateRegions.count) installed region\(model.updateRegions.count == 1 ? "" : "s") report an update"
        }
    }
}

private struct FeedPresentation {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
}

private struct CapabilityDescriptor {
    let capability: OfflineMapCapabilities
    let title: String
    let detail: String
    let systemImage: String
}

private struct CapabilityPresentation {
    let title: String
    let color: Color
}

private enum OfflineMapLibraryFormat {
    static func bytes(_ value: Int64) -> String {
        if value == 0 { return "0 bytes" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func optionalBytes(_ value: Int64?) -> String {
        value.map(bytes) ?? "Unknown"
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}
