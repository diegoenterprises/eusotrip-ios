//
//  615_RailCrossDockPlan.swift
//  EusoTrip - Rail Engineer - Cross-dock operations.
//
//  Production contract:
//    yardManagement.getCrossDockOperations({ locationId? })
//    yardManagement.createCrossDockPlan({ requestKey, locationId, trailers,
//      docks, palletCount, scheduledStart, estimatedCompletion, priority })
//
//  Creation requires explicit location, trailer, dock, pallet, schedule, and
//  priority inputs. This read surface never invents those operational values.
//

import SwiftUI

private struct CrossDockOperation615: Decodable, Identifiable {
    let id: String
    let status: String
    let inboundDock: String?
    let outboundDock: String?
    let inboundTrailer: String?
    let outboundTrailer: String?
    let inboundCarrier: String?
    let outboundCarrier: String?
    let palletCount: Int
    let palletsTransferred: Int
    let startTime: String?
    let estimatedCompletion: String?
    let priority: String
}

private struct CrossDockSummary615: Decodable {
    let total: Int
    let inProgress: Int
    let planned: Int
    let completed: Int
    let avgTransferTimeMinutes: Int
}

private struct CrossDockResult615: Decodable {
    let operations: [CrossDockOperation615]
    let summary: CrossDockSummary615
}

private struct EmptyInput615: Encodable {}

private struct CrossDockCreateInput615: Encodable {
    let requestKey: String
    let locationId: String
    let inboundTrailerId: String
    let outboundTrailerId: String
    let inboundDockId: String
    let outboundDockId: String
    let palletCount: Int
    let scheduledStart: String
    let estimatedCompletion: String
    let priority: String
    let inboundCarrier: String?
    let outboundCarrier: String?
    let notes: String?
}

private struct CrossDockCreateResult615: Decodable {
    let success: Bool
    let operationId: String
    let status: String
    let scheduledStart: String
    let estimatedCompletion: String
    let createdAt: String
    let alreadyCreated: Bool
}

struct RailCrossDockPlanScreen: View {
    let theme: Theme.Palette
    var facility: String = ""

    var body: some View {
        Shell(theme: theme) {
            RailCrossDockPlanBody615(facilityContext: facility)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true),
                ],
                trailing: [
                    NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                    NavSlot(label: "Me", systemImage: "person", isCurrent: false),
                ],
                orbState: .idle
            )
        }
    }
}

private struct RailCrossDockPlanBody615: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let facilityContext: String

    @State private var operations: [CrossDockOperation615] = []
    @State private var summary = CrossDockSummary615(
        total: 0,
        inProgress: 0,
        planned: 0,
        completed: 0,
        avgTransferTimeMinutes: 0
    )
    @State private var loading = false
    @State private var loadError: String?
    @State private var activeFirst = false
    @State private var showingCreatePlan = false
    @State private var actionMessage: String?

    private var visibleOperations: [CrossDockOperation615] {
        guard activeFirst else { return operations }
        return operations.sorted {
            statusRank615($0.status) < statusRank615($1.status)
        }
    }

    private var facilityLabel: String {
        let supplied = facilityContext.trimmingCharacters(in: .whitespacesAndNewlines)
        return supplied.isEmpty ? "ALL LOCATIONS" : supplied.uppercased()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()

                if loading && operations.isEmpty {
                    loadingCard
                } else if let loadError, operations.isEmpty {
                    errorCard(loadError)
                } else {
                    summaryStrip
                    flowCard
                    assignmentsCard
                    if let loadError { errorCard(loadError) }
                    if let actionMessage { successCard(actionMessage) }
                    controls
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .sheet(isPresented: $showingCreatePlan) {
            CrossDockPlanSheet615(initialLocation: facilityContext) { receipt in
                actionMessage = receipt.alreadyCreated
                    ? "Cross-dock plan \(receipt.operationId) was already recorded."
                    : "Cross-dock plan \(receipt.operationId) is scheduled."
                Task { await load() }
            }
            .presentationDetents([.large])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center) {
                EusoTripEyebrow(verbatim: "RAIL ENGINEER · TRANSLOAD FLOW")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(facilityLabel)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: Space.s3) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Text("Cross-dock flow")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: Space.s2) {
            metricCell(label: "PLANNED", value: "\(summary.planned)", tint: Brand.rail)
            metricCell(label: "IN PROGRESS", value: "\(summary.inProgress)", tint: Brand.info)
            metricCell(label: "COMPLETED", value: "\(summary.completed)", tint: Brand.success)
        }
    }

    private func metricCell(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(value)
                .font(.system(size: 21, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 64)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
    }

    private var flowCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("DOCK TRANSFER FLOW")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(palette.textTertiary)

            if visibleOperations.isEmpty {
                EusoEmptyState(
                    systemImage: "arrow.left.arrow.right.square",
                    title: "No cross-dock operations",
                    subtitle: "No persisted cross-dock operations were returned for this company and location."
                )
            } else {
                CrossDockFloor615(operations: Array(visibleOperations.prefix(4)), palette: palette)
                    .frame(height: 158)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1))
    }

    private var assignmentsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CROSS-DOCK OPERATIONS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(summary.total) RECORDED")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }

            if !visibleOperations.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(visibleOperations.enumerated()), id: \.element.id) { index, operation in
                        assignmentRow(operation)
                        if index < visibleOperations.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, 52)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    private func assignmentRow(_ operation: CrossDockOperation615) -> some View {
        let status = flowState615(operation.status)
        let inboundDock = nonempty615(operation.inboundDock) ?? "Inbound dock pending"
        let outboundDock = nonempty615(operation.outboundDock) ?? "Outbound dock pending"

        return HStack(spacing: Space.s3) {
            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(status.color)
                .frame(width: 38, height: 38)
                .background(status.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(inboundDock) → \(outboundDock)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(operationDetail615(operation))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                Text(status.label)
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(status.color)
                Text(operation.priority.uppercased())
                    .font(EType.mono(.micro))
                    .foregroundStyle(priorityColor615(operation.priority))
            }
        }
        .padding(Space.s3)
    }

    private var controls: some View {
        VStack(spacing: Space.s2) {
            CTAButton(
                title: "Create cross-dock plan",
                action: {
                    actionMessage = nil
                    showingCreatePlan = true
                },
                trailingIcon: "plus"
            )

            HStack(spacing: Space.s2) {
                Button { activeFirst.toggle() } label: {
                    Label(activeFirst ? "Server order" : "Active first", systemImage: "arrow.up.arrow.down")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(palette.bgCardSoft)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)

                CTAButton(
                    title: loading ? "Refreshing…" : "Refresh",
                    action: { Task { await load() } },
                    trailingIcon: "arrow.clockwise",
                    isLoading: loading
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var loadingCard: some View {
        RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(height: 220)
            .overlay(ProgressView().tint(palette.textPrimary))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.4)))
    }

    private func successCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Brand.success)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.success.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.success.opacity(0.4)))
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        loadError = nil

        struct LocationInput615: Encodable {
            let locationId: String
        }

        do {
            let locationId = facilityContext.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: CrossDockResult615
            if locationId.isEmpty {
                result = try await EusoTripAPI.shared.query(
                    "yardManagement.getCrossDockOperations",
                    input: EmptyInput615()
                )
            } else {
                result = try await EusoTripAPI.shared.query(
                    "yardManagement.getCrossDockOperations",
                    input: LocationInput615(locationId: locationId)
                )
            }
            operations = result.operations
            summary = result.summary
        } catch {
            loadError = error.eusoUserCopy
        }
    }
}

private struct CrossDockPlanSheet615: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var reachability = OfflineReachabilityHub.shared

    let initialLocation: String
    let onCreated: (CrossDockCreateResult615) -> Void

    @State private var locationId = ""
    @State private var inboundTrailer = ""
    @State private var outboundTrailer = ""
    @State private var inboundDock = ""
    @State private var outboundDock = ""
    @State private var palletCount = ""
    @State private var scheduledStart = Date().addingTimeInterval(3600)
    @State private var estimatedCompletion = Date().addingTimeInterval(9000)
    @State private var priority = "normal"
    @State private var inboundCarrier = ""
    @State private var outboundCarrier = ""
    @State private var notes = ""
    @State private var saving = false
    @State private var actionError: String?
    @State private var requestKey = UUID().uuidString

    private var validationMessage: String? {
        let location = trimmed615(locationId)
        let inboundTrailerId = trimmed615(inboundTrailer)
        let outboundTrailerId = trimmed615(outboundTrailer)
        let inboundDockId = trimmed615(inboundDock)
        let outboundDockId = trimmed615(outboundDock)
        guard !location.isEmpty, !inboundTrailerId.isEmpty, !outboundTrailerId.isEmpty,
              !inboundDockId.isEmpty, !outboundDockId.isEmpty else {
            return "Location, both trailers, and both docks are required."
        }
        guard location.count <= 50, inboundTrailerId.count <= 50, outboundTrailerId.count <= 50 else {
            return "Location and trailer identifiers must be 50 characters or fewer."
        }
        guard inboundDockId.count <= 20, outboundDockId.count <= 20 else {
            return "Dock identifiers must be 20 characters or fewer."
        }
        guard inboundTrailerId.caseInsensitiveCompare(outboundTrailerId) != .orderedSame else {
            return "Inbound and outbound trailers must differ."
        }
        guard inboundDockId.caseInsensitiveCompare(outboundDockId) != .orderedSame else {
            return "Inbound and outbound docks must differ."
        }
        guard let pallets = Int(palletCount), (1...100_000).contains(pallets) else {
            return "Pallet count must be between 1 and 100,000."
        }
        guard estimatedCompletion > scheduledStart else {
            return "Estimated completion must follow the scheduled start."
        }
        guard trimmed615(inboundCarrier).count <= 100, trimmed615(outboundCarrier).count <= 100 else {
            return "Carrier names must be 100 characters or fewer."
        }
        guard trimmed615(notes).count <= 2_000 else {
            return "Notes must be 2,000 characters or fewer."
        }
        guard reachability.isOnline else {
            return "Reconnect to create the plan. Operational writes are not queued without confirmation."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Persist the physical handoff plan. Trailer identifiers are matched to your company assets when an exact VIN or plate exists.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    field("Location", text: $locationId, prompt: "Facility or terminal code")
                    HStack(spacing: Space.s2) {
                        field("Inbound trailer", text: $inboundTrailer, prompt: "VIN, plate, or operating ID")
                        field("Outbound trailer", text: $outboundTrailer, prompt: "VIN, plate, or operating ID")
                    }
                    HStack(spacing: Space.s2) {
                        field("Inbound dock", text: $inboundDock, prompt: "Dock")
                        field("Outbound dock", text: $outboundDock, prompt: "Dock")
                    }
                    field("Pallet count", text: $palletCount, prompt: "Required")
                        .keyboardType(.numberPad)
                    HStack(spacing: Space.s2) {
                        field("Inbound carrier", text: $inboundCarrier, prompt: "Optional")
                        field("Outbound carrier", text: $outboundCarrier, prompt: "Optional")
                    }

                    DatePicker("Scheduled start", selection: $scheduledStart)
                        .foregroundStyle(palette.textPrimary)
                    DatePicker("Estimated completion", selection: $estimatedCompletion)
                        .foregroundStyle(palette.textPrimary)

                    Picker("Priority", selection: $priority) {
                        Text("Low").tag("low")
                        Text("Normal").tag("normal")
                        Text("High").tag("high")
                        Text("Urgent").tag("urgent")
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTES")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        TextEditor(text: $notes)
                            .frame(minHeight: 88)
                            .padding(8)
                            .background(palette.bgCardSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    }

                    if let actionError {
                        Text(actionError)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CTAButton(
                        title: saving ? "Creating…" : "Create plan",
                        action: { Task { await submit() } },
                        trailingIcon: "checkmark",
                        isLoading: saving
                    )
                }
                .padding(Space.s5)
            }
        .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("New cross-dock plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if locationId.isEmpty {
                    locationId = trimmed615(initialLocation)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            TextField(prompt, text: text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(palette.bgCardSoft)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func submit() async {
        guard !saving else { return }
        if let validationMessage {
            actionError = validationMessage
            return
        }
        guard let pallets = Int(palletCount) else { return }
        saving = true
        actionError = nil
        defer { saving = false }

        let input = CrossDockCreateInput615(
            requestKey: requestKey,
            locationId: trimmed615(locationId),
            inboundTrailerId: trimmed615(inboundTrailer),
            outboundTrailerId: trimmed615(outboundTrailer),
            inboundDockId: trimmed615(inboundDock),
            outboundDockId: trimmed615(outboundDock),
            palletCount: pallets,
            scheduledStart: ISO8601DateFormatter().string(from: scheduledStart),
            estimatedCompletion: ISO8601DateFormatter().string(from: estimatedCompletion),
            priority: priority,
            inboundCarrier: optional615(inboundCarrier),
            outboundCarrier: optional615(outboundCarrier),
            notes: optional615(notes)
        )
        do {
            let receipt: CrossDockCreateResult615 = try await EusoTripAPI.shared.mutation(
                "yardManagement.createCrossDockPlan",
                input: input
            )
            guard receipt.success else {
                actionError = "The cross-dock plan was not created. Review the details and try again."
                return
            }
            onCreated(receipt)
            dismiss()
        } catch {
            actionError = error.eusoUserCopy
        }
    }
}

private struct CrossDockFloor615: View {
    let operations: [CrossDockOperation615]
    let palette: Theme.Palette

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let rowHeight = height / CGFloat(max(operations.count, 1))

            ZStack {
                VStack {
                    HStack {
                        Text("INBOUND")
                        Spacer()
                        Text("OUTBOUND")
                    }
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                    Spacer()
                }

                ForEach(Array(operations.enumerated()), id: \.element.id) { index, operation in
                    let y = rowHeight * (CGFloat(index) + 0.5) + 8
                    let state = flowState615(operation.status)

                    Path { path in
                        path.move(to: CGPoint(x: width * 0.28, y: y))
                        path.addLine(to: CGPoint(x: width * 0.72, y: y))
                    }
                    .stroke(state.color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: operation.status == "planned" ? [4, 5] : []))

                    floorChip615(
                        nonempty615(operation.inboundDock) ?? "Pending",
                        tint: Brand.rail,
                        palette: palette
                    )
                    .position(x: width * 0.14, y: y)

                    floorChip615(
                        nonempty615(operation.outboundDock) ?? "Pending",
                        tint: state.color,
                        palette: palette
                    )
                    .position(x: width * 0.86, y: y)
                }
            }
        }
    }
}

private func floorChip615(_ label: String, tint: Color, palette: Theme.Palette) -> some View {
    Text(label)
        .font(.system(size: 8.5, weight: .bold))
        .foregroundStyle(palette.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .frame(width: 78, height: 28)
        .background(tint.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(tint.opacity(0.35)))
}

private func statusRank615(_ status: String?) -> Int {
    switch (status ?? "").lowercased() {
    case "in_progress": return 0
    case "planned": return 1
    case "completed": return 2
    case "cancelled": return 3
    default: return 4
    }
}

private func flowState615(_ status: String?) -> (label: String, color: Color) {
    switch (status ?? "").lowercased() {
    case "completed": return ("COMPLETED", Brand.success)
    case "in_progress": return ("IN PROGRESS", Brand.info)
    case "planned": return ("PLANNED", Brand.rail)
    case "cancelled": return ("CANCELLED", Brand.warning)
    default: return ("RECORDED", Color.secondary)
    }
}

private func operationDetail615(_ operation: CrossDockOperation615) -> String {
    var parts: [String] = []
    if let inbound = nonempty615(operation.inboundTrailer) { parts.append(inbound) }
    if let outbound = nonempty615(operation.outboundTrailer) { parts.append(outbound) }
    parts.append("\(operation.palletsTransferred)/\(operation.palletCount) pallets")
    if let time = nonempty615(operation.startTime) { parts.append(time) }
    return parts.joined(separator: " · ")
}

private func priorityColor615(_ priority: String) -> Color {
    switch priority.lowercased() {
    case "urgent": return Brand.danger
    case "high": return Brand.warning
    default: return Color.secondary
    }
}

private func nonempty615(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func trimmed615(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func optional615(_ value: String) -> String? {
    let value = trimmed615(value)
    return value.isEmpty ? nil : value
}

#Preview("615 · Rail Cross-Dock Flow · Night") {
    RailCrossDockPlanScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("615 · Rail Cross-Dock Flow · Light") {
    RailCrossDockPlanScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
