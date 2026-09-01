//
//  825_VesselEmptyRepositioning.swift
//  EusoTrip
//
//  Production contracts:
//    vesselShipments.getContainerPositions({ status: "empty", limit })
//    vesselShipments.getPorts({ limit, offset, activeOnly })
//    vesselShipments.requestEmptyRepositioning({ containerId, destinationPortId,
//      requestKey, priority, requestedPickupAt?, notes? })
//

import SwiftUI

private struct ContainerPositionsEnvelope825: Decodable {
    let containers: [ContainerPosition825]
    let total: Int
}

private struct ContainerPosition825: Decodable, Identifiable {
    let id: Int
    let containerNumber: String
    let sizeType: String
    let status: String?
    let currentPortId: Int?
    let currentLocation: ContainerLocation825?
    let currentPortLabel: String?
    let originPortLabel: String?
    let destinationPortLabel: String?
    let bookingNumber: String?
    let vesselName: String?
    let latestMovement: ContainerMovement825?
    let latestRepositionRequest: ContainerMovement825?
}

private struct ContainerLocation825: Decodable {
    let lat: Double
    let lng: Double
    let description: String?
}

private struct ContainerMovement825: Decodable {
    let id: Int
    let eventType: String
    let location: ContainerLocation825?
    let timestamp: String
    let metadata: RepositionMetadata825?
}

private struct RepositionMetadata825: Decodable {
    let status: String?
    let priority: String?
    let currentPortId: Int?
    let currentPortLabel: String?
    let destinationPortId: Int?
    let destinationPortLabel: String?
    let requestedPickupAt: String?
    let notes: String?
}

private struct PortRecord825: Decodable, Identifiable {
    let id: Int
    let name: String
    let unlocode: String?
    let city: String?
    let state: String?
    let country: String?
}

private struct GetPortsInput825: Encodable {
    let limit: Int
    let offset: Int
    let activeOnly: Bool
}

private struct RepositionRequestInput825: Encodable {
    let containerId: Int
    let destinationPortId: Int
    let requestKey: String
    let priority: String
    let requestedPickupAt: String?
    let notes: String?
}

private struct RepositionRequestResult825: Decodable {
    let success: Bool
    let requestId: Int
    let containerId: Int
    let shipmentId: Int
    let destinationPortId: Int
    let destinationPortLabel: String
    let status: String
    let requestedAt: String
    let alreadyRequested: Bool
}

private struct PortInventory825: Identifiable {
    let label: String
    let containers: [ContainerPosition825]

    var id: String { label }
}

struct VesselEmptyRepositioningScreen: View {
    let theme: Theme.Palette
    var corridor: String

    init(theme: Theme.Palette, corridor: String = "") {
        self.theme = theme
        self.corridor = corridor
    }

    var body: some View {
        Shell(theme: theme) {
            VesselEmptyRepositioningBody825(corridor: corridor)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true),
                ],
                trailing: [
                    NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                    NavSlot(label: "Me", systemImage: "person", isCurrent: false),
                ],
                orbState: .idle
            )
        }
    }
}

private struct VesselEmptyRepositioningBody825: View {
    @Environment(\.palette) private var palette

    let corridor: String

    @State private var containers: [ContainerPosition825] = []
    @State private var total = 0
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var selectedContainer: ContainerPosition825?

    private var locatedCount: Int {
        containers.filter { locationLabel(for: $0) != nil }.count
    }

    private var portInventories: [PortInventory825] {
        let grouped = Dictionary(grouping: containers) { container in
            locationLabel(for: container) ?? "Location pending"
        }

        return grouped.map { label, groupedContainers in
            PortInventory825(
                label: label,
                containers: groupedContainers.sorted {
                    $0.containerNumber.localizedStandardCompare($1.containerNumber) == .orderedAscending
                }
            )
        }
        .sorted {
            if $0.label == "Location pending" { return false }
            if $1.label == "Location pending" { return true }
            if $0.containers.count != $1.containers.count {
                return $0.containers.count > $1.containers.count
            }
            return $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }

    private var recentMovements: [ContainerPosition825] {
        containers
            .filter { $0.latestMovement != nil }
            .sorted {
                ($0.latestMovement?.timestamp ?? "") > ($1.latestMovement?.timestamp ?? "")
            }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                Text("Empty equipment inventory")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(palette.textPrimary)

                IridescentHairline()

                if let errorMessage {
                    errorBanner(errorMessage)
                }
                if let actionMessage {
                    successBanner(actionMessage)
                }

                summaryCard
                inventoryByPort
                movementLedger
                refreshButton
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .sheet(item: $selectedContainer) { container in
            EmptyRepositionRequestSheet825(container: container) { result in
                errorMessage = nil
                actionMessage = result.alreadyRequested
                    ? "Request #\(result.requestId) was already recorded for \(result.destinationPortLabel)."
                    : "Request #\(result.requestId) was recorded for \(result.destinationPortLabel)."
                Task { await load() }
            }
            .presentationDetents([.large])
        }
    }

    private var eyebrow: some View {
        HStack(spacing: Space.s2) {
            EusoTripBrandMark(size: 12)
            Text("VESSEL OPERATOR · EMPTY CONTAINERS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("TENANT INVENTORY")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hasLoaded ? "\(total)" : "—")
                        .font(.system(size: 32, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("EMPTY CONTAINERS IN SCOPE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                if loading {
                    ProgressView()
                } else {
                    Text(hasLoaded ? "LIVE" : "NOT LOADED")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(hasLoaded ? Brand.success : palette.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(palette.bgCard))
                }
            }

            if !corridor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: Space.s2) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    Text(corridor)
                        .lineLimit(2)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            }

            HStack(spacing: Space.s3) {
                metric(value: "\(containers.count)", label: "RETURNED")
                metric(value: "\(locatedCount)", label: "LOCATED")
                metric(value: "\(max(0, containers.count - locatedCount))", label: "PENDING LOCATION")
            }

            if total > containers.count {
                Text("Showing the newest \(containers.count) of \(total) scoped empty containers.")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(.system(size: 7.5, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, Space.s3)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var inventoryByPort: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("EMPTY INVENTORY · CURRENT LOCATION", count: portInventories.count)

            if hasLoaded && containers.isEmpty {
                emptyState(
                    icon: "shippingbox",
                    title: "No scoped empty containers",
                    detail: "No empty container records are attached to your current vessel operations."
                )
            } else if portInventories.isEmpty {
                loadingState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(portInventories.enumerated()), id: \.element.id) { index, inventory in
                        VStack(alignment: .leading, spacing: Space.s2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(inventory.label)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(2)
                                Spacer()
                                Text("\(inventory.containers.count)")
                                    .font(.system(size: 12, weight: .heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(Brand.info)
                            }

                            VStack(spacing: 0) {
                                ForEach(Array(inventory.containers.enumerated()), id: \.element.id) { containerIndex, container in
                                    containerInventoryRow(container)
                                    if containerIndex < inventory.containers.count - 1 {
                                        Divider().overlay(palette.borderFaint)
                                    }
                                }
                            }
                        }
                        .padding(Space.s4)

                        if index < portInventories.count - 1 {
                            Rectangle()
                                .fill(palette.borderFaint)
                                .frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func containerInventoryRow(_ container: ContainerPosition825) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(container.containerNumber)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text([
                    pretty825(container.sizeType),
                    nonempty825(container.bookingNumber),
                    nonempty825(container.vesselName),
                ].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)

                if let request = container.latestRepositionRequest {
                    Text(repositionStatus825(request))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Space.s2)

            Button {
                actionMessage = nil
                errorMessage = nil
                selectedContainer = container
            } label: {
                Label(
                    container.latestRepositionRequest == nil ? "Reposition" : "Revise",
                    systemImage: "arrow.right.arrow.left"
                )
                .font(.system(size: 9.5, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Space.s2)
    }

    private var movementLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("LATEST PERSISTED MOVEMENTS", count: recentMovements.count)

            if hasLoaded && recentMovements.isEmpty {
                emptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No movement events recorded",
                    detail: "Container locations are available, but no tracking event has been persisted for this result set."
                )
            } else if recentMovements.isEmpty {
                loadingState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentMovements.prefix(12).enumerated()), id: \.element.id) { index, container in
                        movementRow(container)
                        if index < min(recentMovements.count, 12) - 1 {
                            Rectangle()
                                .fill(palette.borderFaint)
                                .frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func movementRow(_ container: ContainerPosition825) -> some View {
        let movement = container.latestMovement
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Brand.info.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(Brand.info)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(container.containerNumber)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text([pretty825(movement?.eventType), container.sizeType]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.system(size: 9.5))
                    .foregroundStyle(palette.textSecondary)
                if let location = movementLocation(for: container) {
                    Text(location)
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Space.s2)

            Text(movement?.timestamp ?? "")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(maxWidth: 112, alignment: .trailing)
        }
        .padding(Space.s4)
    }

    private var refreshButton: some View {
        CTAButton(
            title: "Refresh inventory",
            action: { Task { await load() } },
            trailingIcon: "arrow.clockwise",
            isLoading: loading
        )
    }

    private var loadingState: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text(loading ? "Loading scoped empty-container records..." : "Inventory has not loaded.")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("\(count)")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(palette.bgCard))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.55))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func successBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Brand.success)
            Text(message)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.55))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func locationLabel(for container: ContainerPosition825) -> String? {
        nonempty825(container.currentPortLabel)
            ?? nonempty825(container.currentLocation?.description)
    }

    private func movementLocation(for container: ContainerPosition825) -> String? {
        nonempty825(container.latestMovement?.location?.description)
            ?? locationLabel(for: container)
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        struct Input825: Encodable {
            let status: String
            let limit: Int
        }

        do {
            let response: ContainerPositionsEnvelope825 = try await EusoTripAPI.shared.query(
                "vesselShipments.getContainerPositions",
                input: Input825(status: "empty", limit: 500)
            )
            containers = response.containers
            total = response.total
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = "Empty-container positions could not be refreshed. \(error.eusoUserCopy)"
        }
    }
}

private struct EmptyRepositionRequestSheet825: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reachability = OfflineReachabilityHub.shared

    let container: ContainerPosition825
    let onRequested: (RepositionRequestResult825) -> Void

    @State private var ports: [PortRecord825] = []
    @State private var search = ""
    @State private var selectedPortId: Int?
    @State private var priority = "normal"
    @State private var includePickupTime = false
    @State private var requestedPickupAt = Date().addingTimeInterval(86_400)
    @State private var notes = ""
    @State private var loadingPorts = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var requestKey = UUID().uuidString

    private var filteredPorts: [PortRecord825] {
        let candidates = ports.filter { $0.id != container.currentPortId }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return candidates }
        return candidates.filter { port in
            [port.name, port.unlocode, port.city, port.state, port.country]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(container.containerNumber)
                                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                                .foregroundStyle(palette.textPrimary)
                            Text("Current port · \(nonempty825(container.currentPortLabel) ?? "Not recorded")")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                            if let prior = container.latestRepositionRequest {
                                Text(repositionStatus825(prior))
                                    .font(EType.caption)
                                    .foregroundStyle(Brand.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text("PRIORITY")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.7)
                                .foregroundStyle(palette.textTertiary)
                            Picker("Priority", selection: $priority) {
                                Text("Low").tag("low")
                                Text("Normal").tag("normal")
                                Text("High").tag("high")
                                Text("Urgent").tag("urgent")
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: Space.s2) {
                            Toggle("Request a pickup time", isOn: $includePickupTime)
                                .font(.system(size: 12, weight: .semibold))
                            if includePickupTime {
                                DatePicker(
                                    "Pickup",
                                    selection: $requestedPickupAt,
                                    in: Date()...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .font(EType.caption)
                            }
                        }
                        .padding(Space.s3)
                        .background(palette.bgCardSoft)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("OPERATING NOTES · OPTIONAL")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.7)
                                .foregroundStyle(palette.textTertiary)
                            TextEditor(text: $notes)
                                .frame(minHeight: 76)
                                .padding(8)
                                .background(palette.bgCardSoft)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        }

                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("ACTIVE DESTINATION PORT")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.7)
                                .foregroundStyle(palette.textTertiary)

                            TextField("Search port, UN/LOCODE, city, or country", text: $search)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(palette.bgCardSoft)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))

                            if loadingPorts {
                                HStack(spacing: Space.s2) {
                                    ProgressView()
                                    Text("Loading active ports…")
                                        .font(EType.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }
                                .padding(.vertical, Space.s3)
                            } else if ports.isEmpty && errorMessage == nil {
                                Text("No active destination ports were returned.")
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                                    .padding(.vertical, Space.s3)
                            } else if filteredPorts.isEmpty {
                                Text("No active port matches this search.")
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                                    .padding(.vertical, Space.s3)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(filteredPorts) { port in
                                        destinationPortRow825(port)
                                        if port.id != filteredPorts.last?.id {
                                            Divider().overlay(palette.borderFaint)
                                        }
                                    }
                                }
                                .background(palette.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                            }
                        }

                        if !reachability.isOnline {
                            Text("Reconnect to record a reposition request. Operational writes are never queued without confirmation.")
                                .font(EType.caption)
                                .foregroundStyle(Brand.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(EType.caption)
                                .foregroundStyle(Brand.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Space.s5)
                }

                Divider().overlay(palette.borderFaint)

                CTAButton(
                    title: loadingPorts ? "Loading ports…" : (selectedPortId == nil ? "Select a destination port" : (saving ? "Recording request…" : "Request repositioning")),
                    action: { Task { await submit() } },
                    trailingIcon: "arrow.right.arrow.left",
                    isLoading: saving || loadingPorts
                )
                .padding(Space.s4)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Empty repositioning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadPorts() }
        }
    }

    private func destinationPortRow825(_ port: PortRecord825) -> some View {
        Button {
            selectedPortId = port.id
            errorMessage = nil
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: selectedPortId == port.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selectedPortId == port.id ? Brand.success : palette.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(portLabel825(port))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let location = portLocation825(port) {
                        Text(location)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadPorts() async {
        guard !loadingPorts else { return }
        loadingPorts = true
        errorMessage = nil
        defer { loadingPorts = false }

        do {
            ports = try await EusoTripAPI.shared.query(
                "vesselShipments.getPorts",
                input: GetPortsInput825(limit: 1000, offset: 0, activeOnly: true)
            )
        } catch {
            errorMessage = "Destination ports could not be loaded. \(error.eusoUserCopy)"
        }
    }

    @MainActor
    private func submit() async {
        guard !saving else { return }
        guard reachability.isOnline else {
            errorMessage = "Reconnect to record a reposition request."
            return
        }
        guard let selectedPortId else {
            errorMessage = "Select an active destination port."
            return
        }
        guard notes.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2_000 else {
            errorMessage = "Operating notes must be 2,000 characters or fewer."
            return
        }
        saving = true
        errorMessage = nil
        defer { saving = false }

        let pickup = includePickupTime
            ? ISO8601DateFormatter().string(from: requestedPickupAt)
            : nil
        do {
            let result: RepositionRequestResult825 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.requestEmptyRepositioning",
                input: RepositionRequestInput825(
                    containerId: container.id,
                    destinationPortId: selectedPortId,
                    requestKey: requestKey,
                    priority: priority,
                    requestedPickupAt: pickup,
                    notes: nonempty825(notes)
                )
            )
            guard result.success else {
                errorMessage = "The reposition request was not recorded. Review the destination and retry."
                return
            }
            onRequested(result)
            dismiss()
        } catch {
            errorMessage = "The reposition request was not recorded. \(error.eusoUserCopy)"
        }
    }
}

private func nonempty825(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func repositionStatus825(_ movement: ContainerMovement825) -> String {
    let status = pretty825(movement.metadata?.status) ?? pretty825(movement.eventType) ?? "Recorded"
    let destination = nonempty825(movement.metadata?.destinationPortLabel) ?? "destination pending"
    let priority = pretty825(movement.metadata?.priority)
    return ["\(status) to \(destination)", priority].compactMap { $0 }.joined(separator: " · ")
}

private func portLabel825(_ port: PortRecord825) -> String {
    if let unlocode = nonempty825(port.unlocode) {
        return "\(port.name) · \(unlocode)"
    }
    return port.name
}

private func portLocation825(_ port: PortRecord825) -> String? {
    let cityState = [nonempty825(port.city), nonempty825(port.state)]
        .compactMap { $0 }
        .joined(separator: ", ")
    return [nonempty825(cityState), nonempty825(port.country)]
        .compactMap { $0 }
        .joined(separator: " · ")
        .nilIfEmpty825
}

private extension String {
    var nilIfEmpty825: String? { isEmpty ? nil : self }
}

private func pretty825(_ value: String?) -> String? {
    guard let value = nonempty825(value) else { return nil }
    return value
        .replacingOccurrences(of: "_", with: " ")
        .split(separator: " ")
        .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        .joined(separator: " ")
}

#Preview("825 · Vessel Empty Inventory · Night") {
    VesselEmptyRepositioningScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("825 · Vessel Empty Inventory · Light") {
    VesselEmptyRepositioningScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
