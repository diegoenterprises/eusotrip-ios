//
//  433_RecurringLoadsComposer.swift
//  EusoTrip - Shipper recurring-load governance.
//
//  Turns one verified source load into a server-governed schedule, then
//  exposes schedule, occurrence, and evidence state without simulating
//  recurrence on the device.
//

import SwiftUI

struct RecurringLoadsComposerScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RecurringLoadsWorkspace()
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private enum RecurringWorkspaceTab: String, CaseIterable, Identifiable {
    case create = "Create"
    case schedules = "Schedules"

    var id: String { rawValue }
}

private enum RecurringTemporalField: String, Identifiable {
    case startDate
    case endDate
    case pickupTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .startDate: return "Schedule start"
        case .endDate: return "Schedule end"
        case .pickupTime: return "Local pickup time"
        }
    }
}

private struct RecurringScheduleDraft {
    var name = ""
    var sourceLoadId: Int?
    var frequency: RecurringLoadsAPI.Frequency?
    var startDate: Date?
    var endDate: Date?
    var localPickupTime: Date?
    var timeZone = ""
    var weekdays = Set<Int>()
    var monthDays = ""
    var loadsPerOccurrence = ""
    var dstOverlapPolicy: RecurringLoadsAPI.DSTOverlapPolicy?
}

private struct EvidenceSelection {
    var industry = false
    var portIntelligence = false
}

private struct PendingScheduleCancellation: Identifiable {
    let schedule: RecurringLoadsAPI.Schedule
    var id: String { schedule.id }
}

@MainActor
private final class RecurringLoadsStore: ObservableObject {
    @Published private(set) var sourceLoads: [RecurringLoadsAPI.SourceLoad] = []
    @Published private(set) var schedules: [RecurringLoadsAPI.Schedule] = []
    @Published private(set) var occurrences: [RecurringLoadsAPI.Occurrence] = []
    @Published private(set) var sourceLoading = false
    @Published private(set) var scheduleLoading = false
    @Published private(set) var occurrenceLoading = false
    @Published private(set) var mutationKey: String?
    @Published var sourceError: String?
    @Published var scheduleError: String?
    @Published var occurrenceError: String?
    @Published var actionError: String?
    @Published var confirmation: String?
    @Published var selectedScheduleId: String?

    private let api = EusoTripAPI.shared
    private var sourceRequestId: UUID?
    private var scheduleRequestId: UUID?
    private var occurrenceRequestId: UUID?

    var selectedSchedule: RecurringLoadsAPI.Schedule? {
        schedules.first { $0.id == selectedScheduleId }
    }

    func loadInitial() async {
        await loadSourceLoads()
        await loadSchedules()
        if let selectedScheduleId {
            await loadOccurrences(scheduleId: selectedScheduleId)
        }
    }

    func refresh(tab: RecurringWorkspaceTab) async {
        switch tab {
        case .create:
            await loadSourceLoads()
        case .schedules:
            await loadSchedules(preferredScheduleId: selectedScheduleId)
            if let selectedScheduleId {
                await loadOccurrences(scheduleId: selectedScheduleId)
            }
        }
    }

    func loadSourceLoads() async {
        let requestId = UUID()
        sourceRequestId = requestId
        sourceLoading = true
        sourceError = nil
        do {
            let rows = try await api.recurringLoads.listSourceLoads(limit: 250)
            guard sourceRequestId == requestId else { return }
            sourceLoads = rows
        } catch {
            guard sourceRequestId == requestId else { return }
            sourceError = message(for: error)
        }
        if sourceRequestId == requestId {
            sourceLoading = false
        }
    }

    func loadSchedules(preferredScheduleId: String? = nil) async {
        let requestId = UUID()
        scheduleRequestId = requestId
        scheduleLoading = true
        scheduleError = nil
        do {
            let rows = try await api.recurringLoads.list(limit: 250)
            guard scheduleRequestId == requestId else { return }
            schedules = rows
            let preferred = preferredScheduleId ?? selectedScheduleId
            if let preferred, rows.contains(where: { $0.id == preferred }) {
                selectedScheduleId = preferred
            } else if let first = rows.first {
                selectedScheduleId = first.id
            } else {
                selectedScheduleId = nil
                occurrences = []
                occurrenceError = nil
            }
        } catch {
            guard scheduleRequestId == requestId else { return }
            scheduleError = message(for: error)
        }
        if scheduleRequestId == requestId {
            scheduleLoading = false
        }
    }

    func selectSchedule(_ id: String) async {
        selectedScheduleId = id
        await loadOccurrences(scheduleId: id)
    }

    func loadOccurrences(scheduleId: String) async {
        let requestId = UUID()
        occurrenceRequestId = requestId
        occurrenceLoading = true
        occurrenceError = nil
        defer {
            if occurrenceRequestId == requestId {
                occurrenceLoading = false
            }
        }
        do {
            let rows = try await api.recurringLoads.listOccurrences(
                scheduleId: scheduleId,
                limit: 500
            )
            guard occurrenceRequestId == requestId,
                  selectedScheduleId == scheduleId else { return }
            occurrences = rows
        } catch {
            guard occurrenceRequestId == requestId,
                  selectedScheduleId == scheduleId else { return }
            occurrenceError = message(for: error)
        }
    }

    func create(
        name: String,
        sourceLoadId: Int,
        rule: RecurringLoadsAPI.Rule
    ) async -> RecurringLoadsAPI.CreateAck? {
        guard mutationKey == nil else { return nil }
        mutationKey = "create"
        actionError = nil
        confirmation = nil
        defer { mutationKey = nil }
        do {
            let acknowledgement = try await api.recurringLoads.create(
                name: name,
                sourceLoadId: sourceLoadId,
                rule: rule
            )
            confirmation = acknowledgement.replayed
                ? "The server confirmed the existing idempotent schedule."
                : "The server created and versioned the recurring schedule."
            await loadSchedules(preferredScheduleId: acknowledgement.scheduleId)
            await loadOccurrences(scheduleId: acknowledgement.scheduleId)
            return acknowledgement
        } catch {
            actionError = message(for: error)
            return nil
        }
    }

    func setStatus(
        schedule: RecurringLoadsAPI.Schedule,
        action: RecurringLoadsAPI.StatusAction
    ) async -> Bool {
        guard mutationKey == nil else { return false }
        mutationKey = "schedule:\(schedule.id)"
        actionError = nil
        confirmation = nil
        defer { mutationKey = nil }
        do {
            _ = try await api.recurringLoads.setStatus(
                scheduleId: schedule.id,
                action: action
            )
            confirmation = "The server confirmed the \(action.rawValue) action."
            await loadSchedules(preferredScheduleId: schedule.id)
            await loadOccurrences(scheduleId: schedule.id)
            return true
        } catch {
            actionError = message(for: error)
            return false
        }
    }

    func acknowledge(
        occurrence: RecurringLoadsAPI.Occurrence,
        industry: Bool,
        portIntelligence: Bool
    ) async -> Bool {
        guard mutationKey == nil else { return false }
        mutationKey = "occurrence:\(occurrence.id)"
        actionError = nil
        confirmation = nil
        defer { mutationKey = nil }
        do {
            let acknowledgement = try await api.recurringLoads.acknowledgeOccurrence(
                occurrenceId: occurrence.id,
                acknowledgeIndustryAssessment: industry,
                acknowledgePortIntelligence: portIntelligence
            )
            confirmation = acknowledgement.retryReady
                ? "The server revalidated the evidence and marked the occurrence ready to retry."
                : "The server recorded the selected evidence acknowledgement."
            if let selectedScheduleId {
                await loadSchedules(preferredScheduleId: selectedScheduleId)
                await loadOccurrences(scheduleId: selectedScheduleId)
            }
            return true
        } catch {
            actionError = message(for: error)
            return false
        }
    }

    private func message(for error: Error) -> String {
        (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
    }
}

private struct RecurringLoadsWorkspace: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var store = RecurringLoadsStore()
    @State private var selectedTab: RecurringWorkspaceTab = .create
    @State private var draft = RecurringScheduleDraft()
    @State private var showSourcePicker = false
    @State private var showTimeZonePicker = false
    @State private var temporalField: RecurringTemporalField?
    @State private var temporalDraft = Date()
    @State private var attemptedCreate = false
    @State private var evidenceSelections: [String: EvidenceSelection] = [:]
    @State private var pendingCancellation: PendingScheduleCancellation?

    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: Space.s5) {
                header
                workspacePicker

                if let confirmation = store.confirmation {
                    RecurringNotice(title: "Confirmed", message: confirmation, kind: .success)
                }
                if let actionError = store.actionError {
                    RecurringNotice(title: "Action not completed", message: actionError, kind: .danger)
                }

                if selectedTab == .create {
                    createWorkspace
                } else {
                    schedulesWorkspace
                }

                Color.clear.frame(height: 108)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, 56)
        }
        .eusoRefreshable { await store.refresh(tab: selectedTab) }
        .task { await store.loadInitial() }
        .sheet(isPresented: $showSourcePicker) {
            RecurringSourceLoadPicker(
                store: store,
                selectedSourceLoadId: draft.sourceLoadId
            ) { source in
                draft.sourceLoadId = source.id
                showSourcePicker = false
            }
        }
        .sheet(isPresented: $showTimeZonePicker) {
            RecurringTimeZonePicker(selectedTimeZone: draft.timeZone) { identifier in
                draft.timeZone = identifier
                showTimeZonePicker = false
            }
        }
        .sheet(item: $temporalField) { field in
            RecurringTemporalPicker(field: field, initialValue: temporalDraft) { value in
                setTemporalValue(value, for: field)
                temporalField = nil
            }
        }
        .alert(item: $pendingCancellation) { pending in
            Alert(
                title: Text("Cancel recurring schedule?"),
                message: Text(
                    "The server will cancel pending, failed, review-required, and unleased processing work for \"\(pending.schedule.name)\". An actively leased occurrence must finish first. This cannot be resumed."
                ),
                primaryButton: .destructive(Text("Cancel schedule")) {
                    Task {
                        _ = await store.setStatus(schedule: pending.schedule, action: .cancel)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            EusoTripEyebrow(verbatim: "Shipper · Recurring loads")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Recurring loads")
                .font(.largeTitle.bold())
                .foregroundStyle(palette.textPrimary)
            Text("Create from a verified load. EusoTrip controls scheduling, evidence review, occurrence creation, and retries.")
                .font(.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var workspacePicker: some View {
        Picker("Recurring loads workspace", selection: $selectedTab) {
            ForEach(RecurringWorkspaceTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Switches between schedule creation and live schedule records.")
    }

    private var createWorkspace: some View {
        Group {
            sourceLoadSection
            scheduleDefinitionSection

            if attemptedCreate, !validationIssues.isEmpty {
                RecurringNotice(
                    title: "Required before creation",
                    message: validationIssues.joined(separator: "\n"),
                    kind: .warning
                )
            }

            Button {
                attemptedCreate = true
                guard let sourceLoadId = draft.sourceLoadId,
                      let rule = validatedRule else { return }
                Task {
                    if await store.create(
                        name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        sourceLoadId: sourceLoadId,
                        rule: rule
                    ) != nil {
                        draft = RecurringScheduleDraft()
                        attemptedCreate = false
                        selectedTab = .schedules
                    }
                }
            } label: {
                HStack(spacing: Space.s2) {
                    if store.mutationKey == "create" {
                        ProgressView().tint(palette.bgPage)
                    } else {
                        Image(systemName: "calendar.badge.plus")
                    }
                    Text(store.mutationKey == "create" ? "Creating schedule" : "Create recurring schedule")
                        .font(.headline)
                }
                .foregroundStyle(palette.bgPage)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.mutationKey != nil)
            .opacity(store.mutationKey != nil ? 0.48 : 1)
            .accessibilityHint("Creates a versioned recurring schedule on the EusoTrip server.")
        }
    }

    private var sourceLoadSection: some View {
        RecurringSurface {
            RecurringSectionHeader(
                title: "Verified source load",
                subtitle: "The exact governed load version becomes the schedule template.",
                systemImage: "shippingbox"
            )

            if let sourceError = store.sourceError, !store.sourceLoads.isEmpty {
                RecurringNotice(
                    title: "Source loads not refreshed",
                    message: "The last loaded source records remain visible. \(sourceError)",
                    kind: .danger
                )
            }

            if store.sourceLoading, store.sourceLoads.isEmpty {
                RecurringLoadingRow(label: "Loading eligible source loads")
            } else if let sourceError = store.sourceError, store.sourceLoads.isEmpty {
                RecurringInlineError(message: sourceError) {
                    Task { await store.loadSourceLoads() }
                }
            } else {
                Button { showSourcePicker = true } label: {
                    HStack(spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text(selectedSourceLoad?.loadNumber ?? "Choose a verified source load")
                                .font(.headline)
                                .foregroundStyle(palette.textPrimary)
                            Text(selectedSourceLoad.map(sourceLane) ?? "Eligibility and blockers come from the server.")
                                .font(.subheadline)
                                .foregroundStyle(palette.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: Space.s2)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Source load")
                .accessibilityValue(selectedSourceLoad?.loadNumber ?? "Not selected")

                if let source = selectedSourceLoad {
                    Divider().overlay(palette.borderFaint)
                    RecurringProofRow(label: "Commodity", value: recorded(source.commodityName))
                    RecurringProofRow(label: "Mode", value: recorded(source.transportMode))
                    RecurringProofRow(label: "Pickup", value: displayInstant(source.pickupDate))
                    RecurringProofRow(label: "Delivery", value: displayInstant(source.deliveryDate))
                    RecurringProofRow(label: "Governed rate", value: sourceRate(source))
                    RecurringProofRow(label: "Source updated", value: displayInstant(source.sourceUpdatedAt))
                    RecurringProofRow(label: "Template hash", value: recorded(source.templateHash), monospaced: true)
                    HStack {
                        Text("Eligibility")
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        StatusPill(
                            text: source.eligible ? "Eligible" : "Blocked",
                            kind: source.eligible ? .success : .danger
                        )
                    }
                    if !source.blockers.isEmpty {
                        RecurringReasonList(
                            title: "Eligibility blockers",
                            reasons: source.blockers,
                            tint: Brand.danger
                        )
                    }
                }
            }
        }
    }

    private var scheduleDefinitionSection: some View {
        RecurringSurface {
            RecurringSectionHeader(
                title: "Schedule definition",
                subtitle: "All times use the selected IANA time zone.",
                systemImage: "calendar"
            )

            RecurringTextField(
                label: "Schedule name",
                placeholder: "Name this recurring lane",
                text: $draft.name,
                keyboard: .default
            )

            RecurringMenuField(
                label: "Frequency",
                value: draft.frequency.map(frequencyLabel) ?? "Not selected"
            ) {
                ForEach(RecurringLoadsAPI.Frequency.allCases) { frequency in
                    Button(frequencyLabel(frequency)) {
                        draft.frequency = frequency
                        if frequency == .monthly {
                            draft.weekdays = []
                        } else {
                            draft.monthDays = ""
                        }
                    }
                }
            }

            if draft.frequency == .weekly || draft.frequency == .biweekly {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Pickup weekdays")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 4),
                        spacing: Space.s2
                    ) {
                        ForEach(0..<weekdayNames.count, id: \.self) { day in
                            Button {
                                if draft.weekdays.contains(day) {
                                    draft.weekdays.remove(day)
                                } else {
                                    draft.weekdays.insert(day)
                                }
                            } label: {
                                Text(weekdayNames[day])
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(draft.weekdays.contains(day) ? palette.bgPage : palette.textPrimary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(draft.weekdays.contains(day) ? palette.textPrimary : palette.bgElev)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(weekdayLongName(day))
                            .accessibilityValue(draft.weekdays.contains(day) ? "Selected" : "Not selected")
                        }
                    }
                }
            }

            if draft.frequency == .monthly {
                RecurringTextField(
                    label: "Calendar days",
                    placeholder: "For example: 1, 15, 28",
                    text: $draft.monthDays,
                    keyboard: .numbersAndPunctuation
                )
                Text("Monthly recurrence accepts calendar days 1 through 28.")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Space.s3) {
                    temporalButton(field: .startDate, value: draft.startDate)
                    temporalButton(field: .endDate, value: draft.endDate)
                }
            } else {
                HStack(spacing: Space.s3) {
                    temporalButton(field: .startDate, value: draft.startDate)
                    temporalButton(field: .endDate, value: draft.endDate)
                }
            }
            temporalButton(field: .pickupTime, value: draft.localPickupTime)

            VStack(alignment: .leading, spacing: Space.s2) {
                Text("IANA time zone")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                Button { showTimeZonePicker = true } label: {
                    HStack {
                        Text(draft.timeZone.isEmpty ? "Choose time zone" : draft.timeZone)
                            .font(.body)
                            .foregroundStyle(draft.timeZone.isEmpty ? palette.textTertiary : palette.textPrimary)
                        Spacer()
                        Image(systemName: "globe.americas")
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, Space.s3)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgElev)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)

                Button("Use device time zone: \(TimeZone.autoupdatingCurrent.identifier)") {
                    draft.timeZone = TimeZone.autoupdatingCurrent.identifier
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.info)
                .frame(minHeight: 44, alignment: .leading)
                .buttonStyle(.plain)
                .accessibilityHint("Explicitly sets the schedule to the current device time zone.")
            }

            RecurringTextField(
                label: "Loads per occurrence",
                placeholder: "1 through 50",
                text: $draft.loadsPerOccurrence,
                keyboard: .numberPad
            )

            RecurringMenuField(
                label: "Repeated-hour policy",
                value: draft.dstOverlapPolicy.map(dstPolicyLabel) ?? "Not selected"
            ) {
                ForEach(RecurringLoadsAPI.DSTOverlapPolicy.allCases) { policy in
                    Button(dstPolicyLabel(policy)) { draft.dstOverlapPolicy = policy }
                }
            }
            Text("When daylight saving time repeats a local pickup time, choose which occurrence to schedule.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var schedulesWorkspace: some View {
        Group {
            RecurringSurface {
                RecurringSectionHeader(
                    title: "Live schedules",
                    subtitle: "Current schedule state, ordered by latest update.",
                    systemImage: "list.bullet.rectangle"
                )

                if let scheduleError = store.scheduleError, !store.schedules.isEmpty {
                    RecurringNotice(
                        title: "Schedules not refreshed",
                        message: "The last loaded schedule records remain visible. \(scheduleError)",
                        kind: .danger
                    )
                }

                if store.scheduleLoading, store.schedules.isEmpty {
                    RecurringLoadingRow(label: "Loading recurring schedules")
                } else if let scheduleError = store.scheduleError, store.schedules.isEmpty {
                    RecurringInlineError(message: scheduleError) {
                        Task {
                            await store.loadSchedules()
                            if let selectedScheduleId = store.selectedScheduleId {
                                await store.loadOccurrences(scheduleId: selectedScheduleId)
                            }
                        }
                    }
                } else if store.schedules.isEmpty {
                    RecurringEmptyState(
                        title: "No recurring schedules",
                        message: "Create one from a verified source load when the lane is ready."
                    )
                } else {
                    ForEach(Array(store.schedules.enumerated()), id: \.element.id) { index, schedule in
                        if index > 0 { Divider().overlay(palette.borderFaint) }
                        Button {
                            Task { await store.selectSchedule(schedule.id) }
                        } label: {
                            RecurringScheduleRow(
                                schedule: schedule,
                                isSelected: store.selectedScheduleId == schedule.id
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this schedule and its live occurrences.")
                    }
                }
            }

            if let schedule = store.selectedSchedule {
                scheduleDetail(schedule)
                occurrenceRegister(schedule)
            }
        }
    }

    private func scheduleDetail(_ schedule: RecurringLoadsAPI.Schedule) -> some View {
        RecurringSurface {
            HStack(alignment: .top, spacing: Space.s3) {
                RecurringSectionHeader(
                    title: schedule.name,
                    subtitle: "Governed schedule record",
                    systemImage: "calendar.badge.clock"
                )
                Spacer(minLength: Space.s2)
                StatusPill(text: schedule.status.rawValue, kind: scheduleStatusKind(schedule.status))
            }
            Divider().overlay(palette.borderFaint)
            RecurringProofRow(label: "Schedule ID", value: schedule.id, monospaced: true)
            RecurringProofRow(label: "Source load", value: schedule.sourceLoadId.map(String.init) ?? "Not linked", monospaced: true)
            RecurringProofRow(label: "Version", value: schedule.currentVersion.map(String.init) ?? "Not recorded", monospaced: true)
            RecurringProofRow(label: "Template hash", value: recorded(schedule.templateHash), monospaced: true)
            RecurringProofRow(label: "Next occurrence", value: displayInstant(schedule.nextFireAt, timeZone: scheduleTimeZone(schedule)))
            RecurringProofRow(label: "Last occurrence", value: displayInstant(schedule.lastFireAt, timeZone: scheduleTimeZone(schedule)))
            RecurringProofRow(label: "Completed", value: String(schedule.completedOccurrenceCount))
            RecurringProofRow(label: "Consecutive failures", value: String(schedule.consecutiveFailures))
            RecurringProofRow(label: "Updated", value: displayInstant(schedule.updatedAt))

            if let rule = schedule.recurrenceRule {
                Divider().overlay(palette.borderFaint)
                Text("Recurrence contract")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                Text(ruleSummary(rule))
                    .font(.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                RecurringProofRow(label: "DST overlap", value: dstPolicyLabel(rule.dstOverlapPolicy))
            } else {
                RecurringNotice(
                    title: "Governance unavailable",
                    message: "This legacy schedule has no recorded recurrence rule. It stays paused until a governed version is saved.",
                    kind: .warning
                )
            }

            if let lastError = schedule.lastError {
                RecurringNotice(
                    title: recorded(lastError.code),
                    message: recorded(lastError.message),
                    kind: .danger
                )
            }
            scheduleActions(schedule)
        }
    }

    @ViewBuilder
    private func scheduleActions(_ schedule: RecurringLoadsAPI.Schedule) -> some View {
        let busy = store.mutationKey == "schedule:\(schedule.id)"
        if schedule.status != .cancelled {
            Divider().overlay(palette.borderFaint)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Space.s3) {
                    scheduleActionControls(schedule, busy: busy)
                }
                .disabled(store.mutationKey != nil)
            } else {
                HStack(spacing: Space.s3) {
                    scheduleActionControls(schedule, busy: busy)
                }
                .disabled(store.mutationKey != nil)
            }
        }
    }

    @ViewBuilder
    private func scheduleActionControls(
        _ schedule: RecurringLoadsAPI.Schedule,
        busy: Bool
    ) -> some View {
        if schedule.status == .active {
            RecurringActionButton(title: "Pause", systemImage: "pause.fill", busy: busy) {
                Task { _ = await store.setStatus(schedule: schedule, action: .pause) }
            }
        }
        if schedule.status == .paused || schedule.status == .completed {
            RecurringActionButton(title: "Resume", systemImage: "play.fill", busy: busy) {
                Task { _ = await store.setStatus(schedule: schedule, action: .resume) }
            }
        }
        if schedule.status == .active || schedule.status == .paused || schedule.status == .completed {
            RecurringActionButton(
                title: "Cancel",
                systemImage: "xmark",
                role: .destructive,
                busy: busy
            ) {
                pendingCancellation = PendingScheduleCancellation(schedule: schedule)
            }
        }
    }

    private func occurrenceRegister(_ schedule: RecurringLoadsAPI.Schedule) -> some View {
        RecurringSurface {
            HStack(alignment: .top, spacing: Space.s3) {
                RecurringSectionHeader(
                    title: "Occurrence register",
                    subtitle: "Materialization, evidence, retries, and resulting load IDs.",
                    systemImage: "clock.arrow.circlepath"
                )
                Spacer(minLength: Space.s2)
                Button {
                    Task { await store.loadOccurrences(scheduleId: schedule.id) }
                } label: {
                    Group {
                        if store.occurrenceLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textPrimary)
                .disabled(store.occurrenceLoading)
                .accessibilityLabel("Refresh occurrences")
            }

            if let occurrenceError = store.occurrenceError, !store.occurrences.isEmpty {
                RecurringNotice(
                    title: "Occurrences not refreshed",
                    message: "The last loaded occurrence records remain visible. \(occurrenceError)",
                    kind: .danger
                )
            }

            if store.occurrenceLoading, store.occurrences.isEmpty {
                RecurringLoadingRow(label: "Loading occurrences")
            } else if let occurrenceError = store.occurrenceError, store.occurrences.isEmpty {
                RecurringInlineError(message: occurrenceError) {
                    Task { await store.loadOccurrences(scheduleId: schedule.id) }
                }
            } else if store.occurrences.isEmpty {
                RecurringEmptyState(
                    title: "No occurrences yet",
                    message: "No occurrence has been generated for this schedule."
                )
            } else {
                ForEach(Array(store.occurrences.enumerated()), id: \.element.id) { index, occurrence in
                    if index > 0 { Divider().overlay(palette.borderFaint) }
                    RecurringOccurrenceRow(
                        occurrence: occurrence,
                        timeZone: scheduleTimeZone(schedule),
                        selection: evidenceSelectionBinding(for: occurrence.id),
                        mutationInProgress: store.mutationKey == "occurrence:\(occurrence.id)"
                    ) {
                        let selected = evidenceSelections[occurrence.id] ?? EvidenceSelection()
                        Task {
                            if await store.acknowledge(
                                occurrence: occurrence,
                                industry: selected.industry,
                                portIntelligence: selected.portIntelligence
                            ) {
                                evidenceSelections[occurrence.id] = EvidenceSelection()
                            }
                        }
                    }
                }
            }
        }
    }

    private var selectedSourceLoad: RecurringLoadsAPI.SourceLoad? {
        guard let sourceLoadId = draft.sourceLoadId else { return nil }
        return store.sourceLoads.first { $0.id == sourceLoadId }
    }

    private var parsedMonthDays: [Int]? {
        let fragments = draft.monthDays.split { character in
            character == "," || character == " " || character == ";" || character == "\n"
        }
        guard !fragments.isEmpty else { return nil }
        let values = fragments.compactMap { Int($0) }
        guard values.count == fragments.count,
              values.allSatisfy({ (1...28).contains($0) }) else { return nil }
        return Array(Set(values)).sorted()
    }

    private var validationIssues: [String] {
        var issues: [String] = []
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !(2...180).contains(trimmedName.count) {
            issues.append("Schedule name must contain 2 to 180 characters.")
        }
        if selectedSourceLoad == nil {
            issues.append("Choose a source load returned by the server.")
        } else if selectedSourceLoad?.eligible != true {
            issues.append("Resolve the source load's server blockers before scheduling it.")
        }
        if draft.frequency == nil {
            issues.append("Choose weekly, biweekly, or monthly recurrence.")
        }
        if draft.startDate == nil || draft.endDate == nil {
            issues.append("Choose the start and end dates.")
        } else if let start = draft.startDate, let end = draft.endDate {
            let calendar = Calendar(identifier: .gregorian)
            let startDay = calendar.startOfDay(for: start)
            let endDay = calendar.startOfDay(for: end)
            if let spanDays = calendar.dateComponents([.day], from: startDay, to: endDay).day {
                if endDay < startDay || spanDays > 366 * 5 {
                    issues.append("The schedule window must be 0 to 5 years.")
                }
            } else {
                issues.append("The schedule date window could not be resolved.")
            }
        }
        if draft.localPickupTime == nil {
            issues.append("Choose the local pickup time.")
        }
        if draft.timeZone.isEmpty || TimeZone(identifier: draft.timeZone) == nil {
            issues.append("Choose a valid IANA time zone.")
        }
        if (draft.frequency == .weekly || draft.frequency == .biweekly), draft.weekdays.isEmpty {
            issues.append("Choose at least one pickup weekday.")
        }
        if draft.frequency == .monthly, parsedMonthDays == nil {
            issues.append("Enter at least one calendar day from 1 through 28.")
        }
        if let count = Int(draft.loadsPerOccurrence), (1...50).contains(count) {
            // The validated value is copied into the exact server rule below.
        } else {
            issues.append("Loads per occurrence must be a whole number from 1 through 50.")
        }
        if draft.dstOverlapPolicy == nil {
            issues.append("Choose how repeated daylight-saving-time hours are resolved.")
        }
        return issues
    }

    private var validatedRule: RecurringLoadsAPI.Rule? {
        guard validationIssues.isEmpty,
              let frequency = draft.frequency,
              let startDate = draft.startDate,
              let endDate = draft.endDate,
              let pickupTime = draft.localPickupTime,
              let loadsPerOccurrence = Int(draft.loadsPerOccurrence),
              let dstOverlapPolicy = draft.dstOverlapPolicy,
              let localPickupTime = recurrenceTimeString(pickupTime),
              let startDateValue = recurrenceDateString(startDate),
              let endDateValue = recurrenceDateString(endDate) else { return nil }
        let ruleMonthDays: [Int]
        if frequency == .monthly {
            guard let parsedMonthDays else { return nil }
            ruleMonthDays = parsedMonthDays
        } else {
            ruleMonthDays = []
        }
        return RecurringLoadsAPI.Rule(
            frequency: frequency,
            timeZone: draft.timeZone,
            localPickupTime: localPickupTime,
            weekdays: frequency == .monthly ? [] : draft.weekdays.sorted(),
            monthDays: ruleMonthDays,
            loadsPerOccurrence: loadsPerOccurrence,
            startDate: startDateValue,
            endDate: endDateValue,
            dstOverlapPolicy: dstOverlapPolicy
        )
    }

    private func temporalButton(field: RecurringTemporalField, value: Date?) -> some View {
        Button {
            temporalDraft = value ?? Date()
            temporalField = field
        } label: {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(field.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                HStack {
                    Text(temporalDisplay(field: field, value: value))
                        .font(.body)
                        .foregroundStyle(value == nil ? palette.textTertiary : palette.textPrimary)
                    Spacer(minLength: Space.s2)
                    Image(systemName: field == .pickupTime ? "clock" : "calendar")
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, Space.s3)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(palette.bgElev)
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityValue(value.map { temporalDisplay(field: field, value: $0) } ?? "Not selected")
    }

    private func setTemporalValue(_ value: Date, for field: RecurringTemporalField) {
        switch field {
        case .startDate: draft.startDate = value
        case .endDate: draft.endDate = value
        case .pickupTime: draft.localPickupTime = value
        }
    }

    private func temporalDisplay(field: RecurringTemporalField, value: Date?) -> String {
        guard let value else { return "Not selected" }
        return field == .pickupTime
            ? value.formatted(date: .omitted, time: .shortened)
            : value.formatted(date: .abbreviated, time: .omitted)
    }

    private func recurrenceDateString(_ date: Date) -> String? {
        let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func recurrenceTimeString(_ date: Date) -> String? {
        let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private func sourceLane(_ source: RecurringLoadsAPI.SourceLoad) -> String {
        "\(recorded(source.origin)) to \(recorded(source.destination))"
    }

    private func sourceRate(_ source: RecurringLoadsAPI.SourceLoad) -> String {
        guard let rate = source.rate, !rate.isEmpty else { return "Not recorded" }
        var parts: [String] = []
        if let currency = source.currency, !currency.isEmpty {
            parts.append(currency)
        }
        parts.append(rate)
        if let unit = source.rateUnit, !unit.isEmpty {
            parts.append("/ \(unit)")
        }
        return parts.joined(separator: " ")
    }

    private func frequencyLabel(_ frequency: RecurringLoadsAPI.Frequency) -> String {
        switch frequency {
        case .weekly: return "Weekly"
        case .biweekly: return "Every two weeks"
        case .monthly: return "Monthly"
        }
    }

    private func dstPolicyLabel(_ policy: RecurringLoadsAPI.DSTOverlapPolicy) -> String {
        switch policy {
        case .earlier: return "Earlier repeated time"
        case .later: return "Later repeated time"
        }
    }

    private func weekdayLongName(_ index: Int) -> String {
        let names = Calendar(identifier: .gregorian).weekdaySymbols
        return names.indices.contains(index) ? names[index] : "Weekday \(index)"
    }

    private func ruleSummary(_ rule: RecurringLoadsAPI.Rule) -> String {
        let cadence: String
        switch rule.frequency {
        case .weekly, .biweekly:
            cadence = "\(frequencyLabel(rule.frequency)) on \(rule.weekdays.map(weekdayLongName).joined(separator: ", "))"
        case .monthly:
            cadence = "Monthly on day \(rule.monthDays.map(String.init).joined(separator: ", "))"
        }
        let noun = rule.loadsPerOccurrence == 1 ? "load" : "loads"
        return "\(cadence) at \(rule.localPickupTime) \(rule.timeZone), \(rule.loadsPerOccurrence) \(noun) per occurrence, from \(rule.startDate) through \(rule.endDate)."
    }

    private func scheduleTimeZone(_ schedule: RecurringLoadsAPI.Schedule) -> String? {
        if let value = schedule.timeZone, !value.isEmpty { return value }
        if let value = schedule.recurrenceRule?.timeZone, !value.isEmpty { return value }
        return nil
    }

    private func scheduleStatusKind(_ status: RecurringLoadsAPI.ScheduleStatus) -> StatusPill.Kind {
        switch status {
        case .active: return .success
        case .paused: return .warning
        case .completed: return .info
        case .cancelled: return .neutral
        }
    }

    private func evidenceSelectionBinding(for occurrenceId: String) -> Binding<EvidenceSelection> {
        Binding(
            get: { evidenceSelections[occurrenceId] ?? EvidenceSelection() },
            set: { evidenceSelections[occurrenceId] = $0 }
        )
    }
}

private struct RecurringSourceLoadPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @ObservedObject var store: RecurringLoadsStore
    let selectedSourceLoadId: Int?
    let onSelect: (RecurringLoadsAPI.SourceLoad) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if store.sourceLoading, store.sourceLoads.isEmpty {
                    ProgressView("Loading source loads")
                } else if let error = store.sourceError, store.sourceLoads.isEmpty {
                    VStack(spacing: Space.s4) {
                        Text(error)
                            .font(.body)
                            .foregroundStyle(Brand.danger)
                            .multilineTextAlignment(.center)
                        Button("Try again") { Task { await store.loadSourceLoads() } }
                            .frame(minHeight: 44)
                    }
                    .padding(Space.s5)
                } else if store.sourceLoads.isEmpty {
                    RecurringEmptyState(
                        title: "No source loads",
                        message: "No company load currently qualifies as a recurring template."
                    )
                    .padding(Space.s5)
                } else {
                    List(store.sourceLoads) { source in
                        Button {
                            guard source.eligible else { return }
                            onSelect(source)
                        } label: {
                            VStack(alignment: .leading, spacing: Space.s2) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(source.loadNumber)
                                        .font(.headline)
                                        .foregroundStyle(palette.textPrimary)
                                    Spacer()
                                    if source.id == selectedSourceLoadId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Brand.success)
                                    }
                                    StatusPill(
                                        text: source.eligible ? "Eligible" : "Blocked",
                                        kind: source.eligible ? .success : .danger
                                    )
                                }
                                Text("\(recorded(source.origin)) to \(recorded(source.destination))")
                                    .font(.subheadline)
                                    .foregroundStyle(palette.textSecondary)
                                Text(recorded(source.commodityName))
                                    .font(.caption)
                                    .foregroundStyle(palette.textSecondary)
                                ForEach(source.blockers, id: \.self) { blocker in
                                    Label(blocker, systemImage: "exclamationmark.circle")
                                        .font(.caption)
                                        .foregroundStyle(Brand.danger)
                                }
                            }
                            .padding(.vertical, Space.s2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!source.eligible)
                        .accessibilityHint(
                            source.eligible
                                ? "Selects this governed load as the recurring template."
                                : "This load cannot be selected until its server blockers are resolved."
                        )
                    }
                    .listStyle(.plain)
                    .eusoRefreshable { await store.loadSourceLoads() }
                }
            }
            .navigationTitle("Source load")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct RecurringTimeZonePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let selectedTimeZone: String
    let onSelect: (String) -> Void

    private var results: [String] {
        search.isEmpty
            ? TimeZone.knownTimeZoneIdentifiers
            : TimeZone.knownTimeZoneIdentifiers.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(results, id: \.self) { identifier in
                Button { onSelect(identifier) } label: {
                    HStack {
                        Text(identifier).font(.body)
                        Spacer()
                        if identifier == selectedTimeZone { Image(systemName: "checkmark") }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Search IANA time zones")
            .navigationTitle("Time zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct RecurringTemporalPicker: View {
    @Environment(\.dismiss) private var dismiss
    let field: RecurringTemporalField
    let onCommit: (Date) -> Void
    @State private var value: Date

    init(field: RecurringTemporalField, initialValue: Date, onCommit: @escaping (Date) -> Void) {
        self.field = field
        self.onCommit = onCommit
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.s5) {
                if field == .pickupTime {
                    DatePicker(field.title, selection: $value, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                } else {
                    DatePicker(field.title, selection: $value, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s5)
            .navigationTitle(field.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use selection") { onCommit(value) }
                }
            }
        }
        .presentationDetents(field == .pickupTime ? [.medium] : [.large])
    }
}

private struct RecurringScheduleRow: View {
    @Environment(\.palette) private var palette
    let schedule: RecurringLoadsAPI.Schedule
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(isSelected ? Brand.info : palette.textSecondary)
                .frame(width: 28, height: 44)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(schedule.name)
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                Text(schedule.recurrenceRule.map(compactRule) ?? "Governed rule not recorded")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Updated \(displayInstant(schedule.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: Space.s2) {
                StatusPill(text: schedule.status.rawValue, kind: statusKind)
                Image(systemName: isSelected ? "chevron.down" : "chevron.right")
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.vertical, Space.s2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var statusKind: StatusPill.Kind {
        switch schedule.status {
        case .active: return .success
        case .paused: return .warning
        case .completed: return .info
        case .cancelled: return .neutral
        }
    }

    private func compactRule(_ rule: RecurringLoadsAPI.Rule) -> String {
        "\(rule.frequency.rawValue.capitalized) · \(rule.localPickupTime) · \(rule.timeZone)"
    }
}

private struct RecurringOccurrenceRow: View {
    @Environment(\.palette) private var palette
    let occurrence: RecurringLoadsAPI.Occurrence
    let timeZone: String?
    @Binding var selection: EvidenceSelection
    let mutationInProgress: Bool
    let onAcknowledge: () -> Void

    private var canSelectIndustry: Bool {
        occurrence.status == .reviewRequired
            && occurrence.industryAssessmentId != nil
            && occurrence.industryAssessmentAcknowledgedAt == nil
    }

    private var canSelectPortIntelligence: Bool {
        occurrence.status == .reviewRequired
            && occurrence.portIntelligenceAssessmentId != nil
            && occurrence.portIntelligenceAcknowledgedAt == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Slot \(occurrence.slot)")
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                    Text(displayInstant(occurrence.scheduledFor, timeZone: timeZone))
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s2)
                StatusPill(text: occurrence.status.rawValue, kind: statusKind)
            }

            RecurringProofRow(label: "Occurrence ID", value: occurrence.id, monospaced: true)
            RecurringProofRow(label: "Schedule version", value: String(occurrence.scheduleVersion))
            RecurringProofRow(label: "Pickup", value: displayInstant(occurrence.pickupAt, timeZone: timeZone))
            RecurringProofRow(label: "Delivery", value: displayInstant(occurrence.deliveryAt, timeZone: timeZone))
            RecurringProofRow(label: "Materialized load", value: occurrence.loadId.map(String.init) ?? "Not materialized", monospaced: true)
            RecurringProofRow(label: "Attempts", value: String(occurrence.attemptCount))
            RecurringProofRow(label: "Next retry", value: displayInstant(occurrence.nextAttemptAt, timeZone: timeZone))
            RecurringProofRow(label: "Completed", value: displayInstant(occurrence.completedAt, timeZone: timeZone))

            if let reasons = occurrence.reviewRequiredReasons, !reasons.isEmpty {
                RecurringReasonList(title: "Review required", reasons: reasons, tint: Brand.warning)
            }
            if let error = occurrence.lastError {
                RecurringNotice(title: recorded(error.code), message: recorded(error.message), kind: .danger)
            }
            evidenceRegister
            if let provenance = occurrence.provenance {
                provenanceRegister(provenance)
            } else {
                RecurringProofRow(label: "Generation provenance", value: "Not recorded")
            }
        }
        .padding(.vertical, Space.s3)
    }

    @ViewBuilder
    private var evidenceRegister: some View {
        if occurrence.industryAssessmentId != nil
            || occurrence.portIntelligenceAssessmentId != nil
            || occurrence.status == .reviewRequired {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Evidence acknowledgement")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)

                if let id = occurrence.industryAssessmentId {
                    RecurringProofRow(label: "Industry assessment", value: id, monospaced: true)
                    if let timestamp = occurrence.industryAssessmentAcknowledgedAt {
                        Label("Acknowledged \(displayInstant(timestamp, timeZone: timeZone))", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Brand.success)
                    } else if canSelectIndustry {
                        Toggle("Acknowledge current industry assessment", isOn: $selection.industry)
                            .font(.body)
                            .tint(Brand.info)
                            .frame(minHeight: 44)
                    }
                }

                if let id = occurrence.portIntelligenceAssessmentId {
                    RecurringProofRow(label: "Port Intelligence", value: id, monospaced: true)
                    if let timestamp = occurrence.portIntelligenceAcknowledgedAt {
                        Label("Acknowledged \(displayInstant(timestamp, timeZone: timeZone))", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Brand.success)
                    } else if canSelectPortIntelligence {
                        Toggle("Acknowledge current Port Intelligence assessment", isOn: $selection.portIntelligence)
                            .font(.body)
                            .tint(Brand.info)
                            .frame(minHeight: 44)
                    }
                }

                if occurrence.status == .reviewRequired,
                   !canSelectIndustry,
                   !canSelectPortIntelligence {
                    Text("No unacknowledged current assessment is attached. Refresh after evidence evaluation finishes.")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if canSelectIndustry || canSelectPortIntelligence {
                    Button(action: onAcknowledge) {
                        HStack(spacing: Space.s2) {
                            if mutationInProgress { ProgressView() } else { Image(systemName: "checkmark.seal") }
                            Text(mutationInProgress ? "Revalidating evidence" : "Acknowledge selected evidence")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(mutationInProgress || (!selection.industry && !selection.portIntelligence))
                    .accessibilityHint("The server revalidates the selected evidence before making this occurrence eligible to retry.")
                }
            }
            .padding(.top, Space.s1)
        }
    }

    private func provenanceRegister(_ provenance: RecurringLoadsAPI.OccurrenceProvenance) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Generation provenance")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            RecurringProofRow(label: "Schedule version", value: provenance.scheduleVersion.map(String.init) ?? "Not recorded")
            RecurringProofRow(label: "Template hash", value: recorded(provenance.templateHash), monospaced: true)
            RecurringProofRow(label: "Industry assessment", value: recorded(provenance.industryAssessmentId), monospaced: true)
            RecurringProofRow(label: "Port assessment", value: recorded(provenance.portIntelligenceAssessmentId), monospaced: true)
            RecurringProofRow(label: "Port engine", value: recorded(provenance.portIntelligenceEngineVersion), monospaced: true)
            RecurringProofRow(label: "Evidence cutoff", value: displayInstant(provenance.portIntelligenceEvidenceCutoffAt, timeZone: timeZone))
            RecurringProofRow(label: "Generated", value: displayInstant(provenance.generatedAt, timeZone: timeZone))
        }
        .padding(.top, Space.s1)
    }

    private var statusKind: StatusPill.Kind {
        switch occurrence.status {
        case .pending, .processing: return .info
        case .reviewRequired: return .warning
        case .completed: return .success
        case .failed: return .danger
        case .cancelled: return .neutral
        }
    }
}

private struct RecurringSurface<Content: View>: View {
    @Environment(\.palette) private var palette
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) { content }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
}

private struct RecurringSectionHeader: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Brand.info)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).font(.headline).foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecurringProofRow: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label).font(.caption).foregroundStyle(palette.textSecondary)
            Text(value)
                .font(monospaced ? .system(.footnote, design: .monospaced) : .body)
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct RecurringTextField: View {
    @Environment(\.palette) private var palette
    let label: String
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            TextField(placeholder, text: $text)
                .font(.body)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .default ? .sentences : .never)
                .autocorrectionDisabled(keyboard != .default)
                .padding(.horizontal, Space.s3)
                .frame(minHeight: 48)
                .background(palette.bgElev)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
    }
}

private struct RecurringMenuField<Content: View>: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let content: Content

    init(label: String, value: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.value = value
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            Menu { content } label: {
                HStack {
                    Text(value)
                        .font(.body)
                        .foregroundStyle(value == "Not selected" ? palette.textTertiary : palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, Space.s3)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(palette.bgElev)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RecurringActionButton: View {
    @Environment(\.palette) private var palette
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: Space.s2) {
                if busy { ProgressView() } else { Image(systemName: systemImage) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .tint(role == .destructive ? Brand.danger : palette.textPrimary)
    }
}

private struct RecurringLoadingRow: View {
    @Environment(\.palette) private var palette
    let label: String

    var body: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text(label).font(.body).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct RecurringEmptyState: View {
    @Environment(\.palette) private var palette
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).font(.headline).foregroundStyle(palette.textPrimary)
            Text(message)
                .font(.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct RecurringInlineError: View {
    @Environment(\.palette) private var palette
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(message)
                .font(.body)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: retry)
                .font(.headline)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
                .foregroundStyle(palette.textPrimary)
        }
    }
}

private struct RecurringReasonList: View {
    @Environment(\.palette) private var palette
    let title: String
    let reasons: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            ForEach(reasons, id: \.self) { reason in
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(tint)
                        .padding(.top, 7)
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct RecurringNotice: View {
    enum Kind { case success, warning, danger }

    @Environment(\.palette) private var palette
    let title: String
    let message: String
    let kind: Kind

    private var color: Color {
        switch kind {
        case .success: return Brand.success
        case .warning: return Brand.warning
        case .danger: return Brand.danger
        }
    }

    private var icon: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title).font(.headline).foregroundStyle(color)
                Text(message)
                    .font(.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
        }
        .accessibilityElement(children: .combine)
    }
}

private func recorded(_ value: String?) -> String {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return "Not recorded"
    }
    return value
}

private func displayInstant(_ value: String?, timeZone: String? = nil) -> String {
    guard let value, !value.isEmpty else { return "Not recorded" }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    guard let date = fractional.date(from: value) ?? plain.date(from: value) else {
        return value
    }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    if let timeZone, let zone = TimeZone(identifier: timeZone) {
        formatter.timeZone = zone
        return "\(formatter.string(from: date)) · \(timeZone)"
    }
    let deviceTimeZone = TimeZone.autoupdatingCurrent
    formatter.timeZone = deviceTimeZone
    return "\(formatter.string(from: date)) · \(deviceTimeZone.identifier)"
}

#Preview("433 · Recurring · Night") {
    RecurringLoadsComposerScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("433 · Recurring · Afternoon") {
    RecurringLoadsComposerScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
