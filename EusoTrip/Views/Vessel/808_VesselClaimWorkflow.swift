//
//  808_VesselClaimWorkflow.swift
//  EusoTrip
//
//  Purpose: trace one vessel booking claim through server-confirmed milestones
//  without inventing permitted transitions, investigators, or evidence.
//  Archetype: maritime resolution track.
//

import SwiftUI

struct VesselClaimWorkflowScreen: View {
    let theme: Theme.Palette
    var claimId: String

    init(theme: Theme.Palette, claimId: String = "") {
        self.theme = theme
        self.claimId = claimId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselClaimWorkflowBody(claimId: claimId)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)
                ],
                trailing: [
                    NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                    NavSlot(label: "Me", systemImage: "person", isCurrent: false)
                ],
                orbState: .idle
            )
        }
    }
}

private struct VesselClaimWorkflowBody: View {
    @Environment(\.palette) private var palette
    let claimId: String

    @State private var claim: FreightClaimsAPI.ClaimDetail?
    @State private var loading = true
    @State private var loadError: String?
    @State private var pendingTransitionKey: String?
    @State private var transitionRequestKeys: [String: UUID] = [:]
    @State private var transitionError: String?
    @State private var investigatorDirectory: FreightClaimsAPI.ClaimInvestigatorCandidateDirectory?
    @State private var investigatorDirectoryLoading = false
    @State private var investigatorDirectoryError: String?
    @State private var selectedAssignmentType: FreightClaimsAPI.ClaimAssignmentType = .investigator
    @State private var selectedInvestigatorId = ""
    @State private var investigatorPriority = ""
    @State private var investigatorNotes = ""
    @State private var investigatorRequestKey: UUID?
    @State private var investigatorRequestFingerprint: String?
    @State private var investigatorAssignmentPending = false
    @State private var investigatorAssignmentConfirmation: String?
    @State private var pendingConflictAttestationAssignmentId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Vessel claim workflow",
                title: "Resolution track",
                purpose: "Trace a booking-bound cargo claim through the milestones, evidence, and decision currently recorded by the claims service."
            )

            if loading && claim == nil {
                ProgressView("Loading resolution track")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let loadError {
                LifecycleCard(accentDanger: true) {
                    Text(loadError).font(.body).foregroundStyle(Brand.danger)
                }
            } else if let claim {
                resolutionHeader(claim)
                FreightClaimWorkflowRegister(workflow: claim.workflow)
                quantityEvidenceState(claim)
                proofState(claim)
                lifecycleLedgers(claim)
                outcomeState(claim)
            } else {
                EusoEmptyState(
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    title: "No vessel claim workflow",
                    subtitle: "No claim tied to a vessel booking is available to this account."
                )
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .task { await load() }
        .eusoRefreshable { await load() }
        .confirmationDialog(
            "Conflict attestation",
            isPresented: Binding(
                get: { pendingConflictAttestationAssignmentId != nil },
                set: { if !$0 { pendingConflictAttestationAssignmentId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Attest and accept") { confirmAssignmentAcceptance() }
            Button("Cancel", role: .cancel) { pendingConflictAttestationAssignmentId = nil }
        } message: {
            Text("I attest that I have no known personal, financial, professional, or organizational conflict affecting this claim.")
        }
    }

    private func resolutionHeader(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        LifecycleCard {
            VStack(spacing: 0) {
                FreightClaimValueRow(label: "Claim", value: claim.claimNumber)
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Vessel booking",
                    value: FreightClaimConsumerCanon.reference(for: claim, mode: .vessel)
                )
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Status", value: FreightClaimConsumerCanon.label(claim.status))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Investigator", value: investigatorLabel(claim.investigator))
                if let investigator = claim.investigator {
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Assignment status", value: FreightClaimConsumerCanon.label(investigator.status))
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Priority", value: FreightClaimConsumerCanon.label(investigator.priority))
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Assigned", value: FreightClaimConsumerCanon.clean(investigator.assignedAt))
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Assignment source", value: investigatorSourceLabel(investigator.provenance))
                    if let assignmentId = FreightClaimConsumerCanon.clean(investigator.assignmentId) {
                        Divider().opacity(0.25)
                        FreightClaimValueRow(label: "Assignment ID", value: assignmentId)
                    }
                }
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Last updated", value: FreightClaimConsumerCanon.clean(claim.updatedAt))
            }
        }
    }

    private func quantityEvidenceState(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        let evidence = claim.quantityEvidence
        let complete = evidence.expectedQuantity != nil
            && evidence.receivedQuantity != nil
            && FreightClaimConsumerCanon.clean(evidence.quantityUnit) != nil

        return LifecycleCard(accentDanger: evidence.state == "recorded" && !complete) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Quantity evidence")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if evidence.state == "recorded", complete,
                   let expected = evidence.expectedQuantity,
                   let received = evidence.receivedQuantity,
                   let unit = FreightClaimConsumerCanon.clean(evidence.quantityUnit) {
                    FreightClaimValueRow(label: "Expected", value: "\(expected.formatted()) \(unit)")
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Received", value: "\(received.formatted()) \(unit)")
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Source", value: quantitySourceLabel(evidence.source))
                } else if evidence.state == "not_recorded" {
                    Text("No typed expected quantity, received quantity, and unit are recorded for this claim.")
                        .font(.body)
                        .foregroundStyle(palette.textSecondary)
                } else if evidence.state == "recorded" {
                    Text("The quantity record is incomplete. No cargo shortage is inferred from booking weight.")
                        .font(.body)
                        .foregroundStyle(Brand.danger)
                } else {
                    Text("Quantity evidence state is unknown. No quantity conclusion is shown.")
                        .font(.body)
                        .foregroundStyle(palette.textSecondary)
                }

                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Access", value: accessLabel(evidence.accessState))
                FreightClaimValueRow(label: "Tracking", value: trackingLabel(evidence.trackingState))
                FreightClaimValueRow(label: "Source", value: quantitySourceLabel(evidence.provenance.source))
                FreightClaimValueRow(label: "Observed", value: FreightClaimConsumerCanon.clean(evidence.provenance.observedAt))
                FreightClaimValueRow(label: "Assembled", value: evidence.provenance.computedAt)
                Text(evidence.provenance.basis)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func proofState(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Resolution proof")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            LifecycleCard {
                VStack(spacing: 0) {
                    FreightClaimValueRow(label: "Evidence records", value: claim.evidence.count.formatted())
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Timeline events", value: claim.timeline.count.formatted())
                    Divider().opacity(0.25)
                    FreightClaimValueRow(label: "Notes", value: claim.notes.count.formatted())
                }
            }
            Text("No workflow action is shown unless the service provides an allowed transition for this account and claim.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lifecycleLedgers(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Claim lifecycle ledgers")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if let transitionError {
                LifecycleCard(accentDanger: true) {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Claim update not confirmed")
                            .font(.headline)
                            .foregroundStyle(Brand.danger)
                            .accessibilityAddTraits(.isHeader)
                        Text(transitionError)
                            .font(.body)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Dismiss") { self.transitionError = nil }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .accessibilityHint("Hides this claim update error.")
                    }
                }
            }

            FreightClaimLifecycleRecorder(
                claim: $claim,
                error: $transitionError,
                mode: .vessel
            )
            assetLedger(claim.assetLedger)
            deadlineLedger(claim.deadlineLedger)
            investigatorAssignmentCommand(claim)
            assignmentLedger(claim.assignmentLedger)
            reserveLedger(claim.reserveLedger)
        }
    }

    @ViewBuilder
    private func investigatorAssignmentCommand(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        if claim.lifecycleCapabilities.assignInvestigator.allowed {
            LifecycleCard(accentDanger: investigatorDirectoryError != nil) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Assign claim specialist")
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    if investigatorDirectoryLoading && investigatorDirectory == nil {
                        ProgressView("Loading eligible \(selectedAssignmentType.label.lowercased())s")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    } else if let investigatorDirectoryError {
                        Text(investigatorDirectoryError)
                            .font(.body)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry directory") {
                            Task { await loadInvestigatorDirectory(for: claim) }
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityHint("Reloads the eligible vessel claim specialist directory.")
                    } else if let directory = investigatorDirectory,
                              directory.claimId == claim.claimId,
                              directory.transportMode == .vessel {
                        investigatorDirectoryContent(directory, claim: claim)
                    } else {
                        Text("The specialist directory does not match this vessel claim. Pull down to refresh before assigning anyone.")
                            .font(.body)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let investigatorAssignmentConfirmation {
                        Text(investigatorAssignmentConfirmation)
                            .font(.caption)
                            .foregroundStyle(Brand.success)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Assignment confirmed. \(investigatorAssignmentConfirmation)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func investigatorDirectoryContent(
        _ directory: FreightClaimsAPI.ClaimInvestigatorCandidateDirectory,
        claim: FreightClaimsAPI.ClaimDetail
    ) -> some View {
        let actionable = investigatorDirectoryIsActionable(directory, for: claim)

        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Responsibility")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
            Picker("Responsibility", selection: $selectedAssignmentType) {
                ForEach(FreightClaimsAPI.ClaimAssignmentType.allCases) { specialty in
                    Text(specialty.label).tag(specialty)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedAssignmentType) { _, _ in
                selectedInvestigatorId = ""
                investigatorAssignmentConfirmation = nil
                Task { await loadInvestigatorDirectory(for: claim) }
            }
            .accessibilityHint("Selects the credentialed claim specialty to invite.")
        }

        if directory.state.accessState != "granted" || directory.state.trackingState != "tracked" {
            Text(directory.state.reason ?? "Eligible claim specialists are unavailable for this account.")
                .font(.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !actionable {
            Text(directory.state.reason ?? "The specialist directory lacks the claim scope or provenance required for assignment.")
                .font(.body)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
        } else if directory.candidates.isEmpty {
            Text(directory.state.reason ?? "No current verified \(selectedAssignmentType.label.lowercased()) is eligible for this vessel claim and jurisdiction.")
                .font(.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Eligible \(selectedAssignmentType.label.lowercased())")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                Picker("Eligible specialist", selection: $selectedInvestigatorId) {
                    Text("Select \(selectedAssignmentType.label.lowercased())").tag("")
                    ForEach(directory.candidates) { candidate in
                        Text(investigatorCandidateLabel(candidate)).tag(candidate.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityHint("Selects a current verified vessel claim specialist eligible for this jurisdiction.")
            }

            if let candidate = directory.candidates.first(where: { $0.id == selectedInvestigatorId }) {
                investigatorCredentialEvidence(candidate)
            }

            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Priority")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                Picker("Priority", selection: $investigatorPriority) {
                    Text("Select priority").tag("")
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                    Text("Urgent").tag("urgent")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityHint("Sets the persisted priority for this vessel claim assignment.")
            }

            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Assignment scope (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                TextEditor(text: $investigatorNotes)
                    .frame(minHeight: 88)
                    .padding(Space.s1)
                    .scrollContentBackground(.hidden)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(palette.borderStrong, lineWidth: 1)
                    }
                    .accessibilityLabel("Assignment scope")
                    .accessibilityHint("Optional notes persisted with the vessel claim assignment.")
            }

            Button {
                Task { await assignInvestigator(for: claim, directory: directory) }
            } label: {
                HStack(spacing: Space.s2) {
                    if investigatorAssignmentPending { ProgressView().controlSize(.small) }
                    Text(investigatorAssignmentPending ? "Recording invitation" : "Invite \(selectedAssignmentType.label.lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                selectedInvestigatorId.isEmpty ||
                investigatorPriority.isEmpty ||
                investigatorAssignmentPending ||
                pendingTransitionKey != nil
            )
            .accessibilityHint("Records an invitation for the selected verified specialist and verifies the refreshed vessel claim register.")
        }

        if let reason = directory.state.reason, !directory.candidates.isEmpty {
            Text(reason)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Divider().opacity(0.25)
        FreightClaimValueRow(label: "Directory state", value: FreightClaimConsumerCanon.label(directory.state.dataState))
        FreightClaimValueRow(label: "Access", value: accessLabel(directory.state.accessState))
        FreightClaimValueRow(label: "Tracking", value: trackingLabel(directory.state.trackingState))
        FreightClaimValueRow(label: "Source", value: FreightClaimConsumerCanon.clean(directory.state.provenance.source))
        FreightClaimValueRow(label: "Scope", value: FreightClaimConsumerCanon.label(directory.state.provenance.scope))
        FreightClaimValueRow(label: "Observed", value: FreightClaimConsumerCanon.clean(directory.state.provenance.observedAt))
        FreightClaimValueRow(label: "Assembled", value: FreightClaimConsumerCanon.clean(directory.state.provenance.computedAt))
        FreightClaimValueRow(
            label: "Candidates",
            value: "\(directory.page.returnedCount.formatted())\(directory.page.truncated ? " · partial directory" : "")"
        )
        if let basis = FreightClaimConsumerCanon.clean(directory.state.provenance.basis) {
            Text(basis)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func assetLedger(_ ledger: FreightClaimsAPI.ClaimAssetLedger) -> some View {
        ledgerSection(
            title: "Cargo and transport assets",
            state: effectiveState(ledger.state, count: ledger.records.count),
            accessState: ledger.accessState,
            trackingState: ledger.trackingState,
            provenance: ledger.provenance,
            emptyMessage: "No bill of lading, container, parcel, seal, delivery receipt, survey, or other typed claim asset is recorded.",
            restrictedMessage: "Claim asset details are restricted for this account."
        ) {
            ForEach(ledger.records) { record in
                VStack(alignment: .leading, spacing: Space.s1) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        FreightClaimValueRow(label: "Asset", value: FreightClaimConsumerCanon.label(record.assetType))
                        FreightClaimValueRow(label: "Identifier", value: FreightClaimConsumerCanon.clean(record.identifier))
                        FreightClaimValueRow(label: "Quantity", value: quantityLabel(record.quantity, unit: record.quantityUnit))
                        FreightClaimValueRow(label: "Verification", value: FreightClaimConsumerCanon.label(record.verificationStatus))
                        FreightClaimValueRow(label: "Observed", value: FreightClaimConsumerCanon.clean(record.observedAt))
                    }
                    .accessibilityElement(children: .combine)

                    if !record.allowedActions.isEmpty {
                        LazyVGrid(columns: actionColumns, spacing: Space.s2) {
                            ForEach(record.allowedActions, id: \.self) { action in
                                let key = assetTransitionKey(record: record, action: action)
                                VesselClaimLifecycleActionButton(
                                    title: assetActionLabel(action),
                                    accessibilityLabel: "\(assetActionLabel(action)) asset \(FreightClaimConsumerCanon.clean(record.identifier) ?? FreightClaimConsumerCanon.label(record.assetType) ?? "record")",
                                    pending: pendingTransitionKey == key,
                                    disabled: pendingTransitionKey != nil,
                                    destructive: action != .verified
                                ) {
                                    Task { await transitionAsset(record: record, action: action) }
                                }
                            }
                        }
                        .padding(.top, Space.s1)
                    }
                }
                if record.id != ledger.records.last?.id { Divider().opacity(0.25) }
            }
        }
    }

    private func deadlineLedger(_ ledger: FreightClaimsAPI.ClaimDeadlineLedger) -> some View {
        ledgerSection(
            title: "Notice and filing deadlines",
            state: effectiveState(ledger.state, count: ledger.records.count),
            accessState: ledger.accessState,
            trackingState: ledger.trackingState,
            provenance: ledger.provenance,
            emptyMessage: "No entered authority or due date is recorded. The app does not infer a statutory deadline.",
            restrictedMessage: "Claim deadline details are restricted for this account."
        ) {
            ForEach(ledger.records) { record in
                VStack(alignment: .leading, spacing: Space.s1) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        FreightClaimValueRow(label: "Deadline", value: FreightClaimConsumerCanon.label(record.deadlineType))
                        FreightClaimValueRow(label: "Due", value: record.dueAt)
                        FreightClaimValueRow(label: "Status", value: FreightClaimConsumerCanon.label(record.status))
                        FreightClaimValueRow(label: "Authority", value: authorityLabel(record))
                        FreightClaimValueRow(label: "Jurisdiction", value: FreightClaimConsumerCanon.clean(record.jurisdictionCode))
                    }
                    .accessibilityElement(children: .combine)

                    if !record.allowedActions.isEmpty {
                        LazyVGrid(columns: actionColumns, spacing: Space.s2) {
                            ForEach(record.allowedActions, id: \.self) { action in
                                let key = deadlineTransitionKey(record: record, action: action)
                                VesselClaimLifecycleActionButton(
                                    title: deadlineActionLabel(action),
                                    accessibilityLabel: "\(deadlineActionLabel(action)) \(FreightClaimConsumerCanon.label(record.deadlineType) ?? "claim deadline")",
                                    pending: pendingTransitionKey == key,
                                    disabled: pendingTransitionKey != nil,
                                    destructive: action == .waive || action == .supersede
                                ) {
                                    Task { await transitionDeadline(record: record, action: action) }
                                }
                            }
                        }
                        .padding(.top, Space.s1)
                    }
                }
                if record.id != ledger.records.last?.id { Divider().opacity(0.25) }
            }
        }
    }

    private func assignmentLedger(_ ledger: FreightClaimsAPI.ClaimAssignmentLedger) -> some View {
        ledgerSection(
            title: "Claim assignments",
            state: effectiveState(ledger.state, count: ledger.records.count),
            accessState: ledger.accessState,
            trackingState: ledger.trackingState,
            provenance: ledger.provenance,
            emptyMessage: "No typed investigator, adjuster, surveyor, or other claim assignment is recorded.",
            restrictedMessage: "Claim assignment details are restricted for this account."
        ) {
            ForEach(ledger.records) { record in
                VStack(alignment: .leading, spacing: Space.s1) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        FreightClaimValueRow(label: "Assignment", value: FreightClaimConsumerCanon.label(record.assignmentType))
                        FreightClaimValueRow(label: "Assignee", value: assigneeLabel(record))
                        FreightClaimValueRow(label: "Assignee state", value: FreightClaimConsumerCanon.label(record.assigneeState))
                        FreightClaimValueRow(label: "Status", value: FreightClaimConsumerCanon.label(record.status))
                        FreightClaimValueRow(label: "Priority", value: FreightClaimConsumerCanon.label(record.scope.priority))
                        FreightClaimValueRow(label: "Jurisdiction", value: assignmentJurisdictionLabel(record.scope))
                        FreightClaimValueRow(label: "Credential", value: assignmentCredentialLabel(record.verification))
                        FreightClaimValueRow(label: "Credential valid through", value: FreightClaimConsumerCanon.clean(record.verification.validUntil))
                        FreightClaimValueRow(label: "Conflict attestation", value: conflictAttestationLabel(record.scope))
                        FreightClaimValueRow(label: "Assigned", value: record.createdAt)
                    }
                    .accessibilityElement(children: .combine)

                    if !record.allowedActions.isEmpty {
                        LazyVGrid(columns: actionColumns, spacing: Space.s2) {
                            ForEach(record.allowedActions, id: \.self) { action in
                                let key = assignmentTransitionKey(record: record, action: action)
                                VesselClaimLifecycleActionButton(
                                    title: assignmentActionLabel(action),
                                    accessibilityLabel: "\(assignmentActionLabel(action)) \(FreightClaimConsumerCanon.label(record.assignmentType) ?? "claim assignment")",
                                    pending: pendingTransitionKey == key,
                                    disabled: pendingTransitionKey != nil,
                                    destructive: action == .declined || action == .cancelled
                                ) {
                                    if action == .accepted {
                                        pendingConflictAttestationAssignmentId = record.id
                                    } else {
                                        Task { await transitionAssignment(record: record, action: action) }
                                    }
                                }
                            }
                        }
                        .padding(.top, Space.s1)
                    }
                }
                if record.id != ledger.records.last?.id { Divider().opacity(0.25) }
            }
        }
    }

    private func reserveLedger(_ ledger: FreightClaimsAPI.ClaimReserveLedger) -> some View {
        let count = ledger.records?.count
        return ledgerSection(
            title: "Financial reserves",
            state: effectiveState(ledger.state, count: count),
            accessState: ledger.accessState,
            trackingState: ledger.trackingState,
            provenance: ledger.provenance,
            emptyMessage: "No reserve is recorded by the respondent financial authority.",
            restrictedMessage: "Reserve visibility is restricted to the respondent financial authority."
        ) {
            if let records = ledger.records {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        FreightClaimValueRow(label: "Reserve", value: "\(record.amount.formatted()) \(record.currency)")
                        FreightClaimValueRow(label: "Version", value: record.version.formatted())
                        FreightClaimValueRow(label: "Status", value: FreightClaimConsumerCanon.label(record.status))
                        FreightClaimValueRow(label: "Basis", value: record.basis)
                        FreightClaimValueRow(label: "Recorded", value: record.createdAt)
                    }
                    .accessibilityElement(children: .combine)
                    if record.id != records.last?.id { Divider().opacity(0.25) }
                }
            }
        }
    }

    private func ledgerSection<Content: View>(
        title: String,
        state: String,
        accessState: String,
        trackingState: String,
        provenance: FreightClaimsAPI.ClaimLedgerProvenance,
        emptyMessage: String,
        restrictedMessage: String,
        @ViewBuilder records: () -> Content
    ) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                FreightClaimValueRow(label: "Record state", value: ledgerStateLabel(state))
                FreightClaimValueRow(label: "Access", value: accessLabel(accessState))
                FreightClaimValueRow(label: "Tracking", value: trackingLabel(trackingState))

                if accessState == "restricted" || state == "restricted" {
                    Text(restrictedMessage).font(.body).foregroundStyle(palette.textSecondary)
                } else if state == "recorded" {
                    Divider().opacity(0.25)
                    records()
                } else if state == "no_records" {
                    Text(emptyMessage).font(.body).foregroundStyle(palette.textSecondary)
                } else {
                    Text("This ledger cannot currently assert whether records exist.")
                        .font(.body)
                        .foregroundStyle(palette.textSecondary)
                }

                Divider().opacity(0.25)
                Text(provenance.basis)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                FreightClaimValueRow(label: "Source", value: provenanceSourceLabel(provenance.source))
                FreightClaimValueRow(label: "Observed", value: FreightClaimConsumerCanon.clean(provenance.observedAt))
                FreightClaimValueRow(label: "Assembled", value: provenance.computedAt)
            }
        }
    }

    private func effectiveState(_ state: String, count: Int?) -> String {
        if state == "recorded" && (count == nil || count == 0) { return "unknown" }
        if state == "no_records" && count != 0 { return "unknown" }
        return state
    }

    private func investigatorLabel(_ investigator: FreightClaimsAPI.Investigator?) -> String {
        guard let investigator else { return "No investigator recorded" }
        return FreightClaimConsumerCanon.clean(investigator.name)
            ?? FreightClaimConsumerCanon.clean(investigator.email)
            ?? "Investigator assignment recorded"
    }

    private func investigatorSourceLabel(_ provenance: String) -> String {
        switch provenance {
        case "freight_claim_assignments": return "Typed claim assignment ledger"
        case "audit_logs": return "Legacy claim audit record"
        default: return "Recorded claim source"
        }
    }

    private func assigneeLabel(_ record: FreightClaimsAPI.ClaimAssignmentRecord) -> String {
        FreightClaimConsumerCanon.clean(record.assignedUserName)
            ?? FreightClaimConsumerCanon.clean(record.assignedUserEmail)
            ?? (record.assignedCompanyId == nil ? "Assignee identity unavailable" : "Company assignment")
    }

    private func investigatorCandidateLabel(
        _ candidate: FreightClaimsAPI.ClaimInvestigatorCandidateDirectory.Candidate
    ) -> String {
        let name = FreightClaimConsumerCanon.clean(candidate.displayName) ?? "Name unavailable"
        return "\(name) · \(candidate.companyName) · \(candidate.credentialType)"
    }

    private func specialistProfileIdIsValid(_ opaqueId: String) -> Bool {
        guard opaqueId.hasPrefix("specialist_profile_") else { return false }
        let numericToken = opaqueId.dropFirst("specialist_profile_".count)
        return Int(numericToken).map { $0 > 0 } == true
    }

    private func normalizedInvestigatorNotes(_ value: String) -> String? {
        FreightClaimConsumerCanon.clean(value)
    }

    private func investigatorDirectoryIsActionable(
        _ directory: FreightClaimsAPI.ClaimInvestigatorCandidateDirectory,
        for claim: FreightClaimsAPI.ClaimDetail
    ) -> Bool {
        guard directory.claimId == claim.claimId,
              claim.transportMode == .vessel,
              directory.transportMode == .vessel,
              directory.state.accessState == "granted",
              directory.state.trackingState == "tracked",
              directory.specialty == selectedAssignmentType,
              directory.state.provenance.scope == "verified_specialist_directory",
              directory.state.provenance.source?.contains("freight_claim_specialist_profiles") == true,
              FreightClaimConsumerCanon.clean(directory.state.provenance.basis) != nil,
              FreightClaimConsumerCanon.clean(directory.state.provenance.computedAt) != nil,
              directory.page.limit > 0,
              directory.page.returnedCount == directory.candidates.count else {
            return false
        }

        let identifiers = directory.candidates.map(\.id)
        guard Set(identifiers).count == identifiers.count,
              identifiers.allSatisfy(specialistProfileIdIsValid),
              directory.candidates.allSatisfy({
                  $0.specialty == selectedAssignmentType.rawValue
                      && $0.credentialState == "verified_current"
                      && FreightClaimConsumerCanon.clean($0.companyName) != nil
                      && FreightClaimConsumerCanon.clean($0.credentialType) != nil
                      && FreightClaimConsumerCanon.clean($0.issuingAuthority) != nil
              }) else {
            return false
        }

        switch directory.state.dataState {
        case "empty":
            return directory.candidates.isEmpty && !directory.page.truncated
        case "populated":
            return !directory.candidates.isEmpty &&
                !directory.page.truncated &&
                FreightClaimConsumerCanon.clean(directory.state.provenance.observedAt) != nil
        case "partial":
            return !directory.candidates.isEmpty &&
                directory.page.truncated &&
                FreightClaimConsumerCanon.clean(directory.state.provenance.observedAt) != nil
        default:
            return false
        }
    }

    private func makeInvestigatorRequestFingerprint(
        claimId: String,
        investigatorId: String,
        assignmentType: FreightClaimsAPI.ClaimAssignmentType,
        jurisdiction: FreightClaimsAPI.ClaimAssignmentJurisdiction,
        priority: String,
        notes: String?
    ) -> String {
        [claimId, investigatorId, assignmentType.rawValue, jurisdiction.scope, jurisdiction.code, priority, notes ?? "<none>"]
            .joined(separator: "\u{001F}")
    }

    private func assignmentReadbackConfirms(
        _ record: FreightClaimsAPI.ClaimAssignmentRecord,
        assignmentId: String,
        specialistProfileId: String,
        assignmentType: FreightClaimsAPI.ClaimAssignmentType,
        jurisdiction: FreightClaimsAPI.ClaimAssignmentJurisdiction,
        priority: String,
        notes: String?
    ) -> Bool {
        record.id == assignmentId &&
        record.assignmentType == assignmentType.rawValue &&
        record.specialistProfileId == specialistProfileId &&
        record.assigneeState == "active" &&
        record.status == "invited" &&
        record.scope.priority == priority &&
        normalizedInvestigatorNotes(record.scope.notes ?? "") == notes &&
        record.scope.jurisdictionScope == jurisdiction.scope &&
        record.scope.jurisdictionCode == jurisdiction.code &&
        record.verification.profileState == "linked" &&
        record.verification.snapshotState == "recorded" &&
        record.verification.trackingState == "tracked" &&
        record.verification.accessState == "granted" &&
        record.acceptedAt == nil
    }

    @ViewBuilder
    private func investigatorCredentialEvidence(
        _ candidate: FreightClaimsAPI.ClaimInvestigatorCandidateDirectory.Candidate
    ) -> some View {
        VStack(spacing: 0) {
            FreightClaimValueRow(label: "Company", value: candidate.companyName)
            Divider().opacity(0.25)
            FreightClaimValueRow(label: "Credential", value: candidate.credentialType)
            Divider().opacity(0.25)
            FreightClaimValueRow(label: "Issuing authority", value: candidate.issuingAuthority)
            Divider().opacity(0.25)
            FreightClaimValueRow(
                label: "Jurisdiction",
                value: specialistJurisdictionLabel(candidate.jurisdiction.scope, code: candidate.jurisdiction.code)
            )
            Divider().opacity(0.25)
            FreightClaimValueRow(label: "Valid through", value: FreightClaimConsumerCanon.clean(candidate.validUntil))
        }
        .accessibilityElement(children: .combine)
    }

    private func specialistJurisdictionLabel(_ scope: String, code: String?) -> String {
        let scopeLabel = FreightClaimConsumerCanon.label(scope) ?? scope
        guard let code = FreightClaimConsumerCanon.clean(code) else { return scopeLabel }
        return "\(scopeLabel) · \(code)"
    }

    private func assignmentJurisdictionLabel(_ scope: FreightClaimsAPI.ClaimAssignmentScope) -> String {
        guard let jurisdictionScope = FreightClaimConsumerCanon.clean(scope.jurisdictionScope) else {
            return "Not recorded"
        }
        return specialistJurisdictionLabel(jurisdictionScope, code: scope.jurisdictionCode)
    }

    private func assignmentCredentialLabel(_ verification: FreightClaimsAPI.ClaimAssignmentVerification) -> String {
        guard verification.profileState == "linked", verification.snapshotState == "recorded" else {
            return "Verification unavailable"
        }
        return FreightClaimConsumerCanon.label(verification.profileStatus) ?? "Recorded snapshot"
    }

    private func conflictAttestationLabel(_ scope: FreightClaimsAPI.ClaimAssignmentScope) -> String {
        guard scope.conflictAttestation == "no_known_conflict" else { return "Not attested" }
        guard let at = FreightClaimConsumerCanon.clean(scope.conflictAttestedAt) else { return "Recorded" }
        return "No known conflict · \(at)"
    }

    private func authorityLabel(_ record: FreightClaimsAPI.ClaimDeadlineRecord) -> String {
        FreightClaimConsumerCanon.clean(record.authorityCitation)
            ?? FreightClaimConsumerCanon.clean(record.authorityType)
            ?? "Authority not recorded"
    }

    private func quantityLabel(_ quantity: Double?, unit: String?) -> String {
        guard let quantity else { return "Not recorded" }
        guard let unit = FreightClaimConsumerCanon.clean(unit) else {
            return "\(quantity.formatted()) · unit not recorded"
        }
        return "\(quantity.formatted()) \(unit)"
    }

    private func quantitySourceLabel(_ source: String?) -> String {
        source == "incidents.expectedQuantity+receivedQuantity+quantityUnit"
            ? "Typed claim quantity fields"
            : source == "incidents.claimDetails"
                ? "Legacy claim details"
                : "Source unavailable"
    }

    private func ledgerStateLabel(_ state: String) -> String {
        switch state {
        case "recorded": return "Recorded"
        case "no_records": return "No records"
        case "restricted": return "Restricted"
        default: return "Unknown"
        }
    }

    private func accessLabel(_ state: String) -> String {
        switch state {
        case "granted": return "Granted"
        case "restricted": return "Restricted"
        default: return "Unknown"
        }
    }

    private func trackingLabel(_ state: String) -> String {
        switch state {
        case "tracked": return "Tracked"
        case "not_tracked": return "Not tracked"
        default: return "Unknown"
        }
    }

    private func provenanceSourceLabel(_ source: String?) -> String {
        switch source {
        case "freight_claim_assets": return "Claim asset ledger"
        case "freight_claim_deadlines": return "Claim deadline ledger"
        case "freight_claim_assignments": return "Claim assignment ledger"
        case "freight_claim_reserves": return "Claim reserve ledger"
        case nil: return "Not disclosed"
        default: return "Recorded claim source"
        }
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 132), spacing: Space.s2)]
    }

    private func assetActionLabel(_ action: FreightClaimsAPI.ClaimAssetAction) -> String {
        switch action {
        case .verified: return "Verify"
        case .rejected: return "Reject"
        case .superseded: return "Supersede"
        }
    }

    private func deadlineActionLabel(_ action: FreightClaimsAPI.ClaimDeadlineAction) -> String {
        switch action {
        case .verifyAuthority: return "Verify authority"
        case .complete: return "Complete"
        case .waive: return "Waive"
        case .supersede: return "Supersede"
        }
    }

    private func assignmentActionLabel(_ action: FreightClaimsAPI.ClaimAssignmentAction) -> String {
        switch action {
        case .accepted: return "Accept"
        case .declined: return "Decline"
        case .completed: return "Complete"
        case .cancelled: return "Cancel"
        }
    }

    private func assetTransitionKey(
        record: FreightClaimsAPI.ClaimAssetRecord,
        action: FreightClaimsAPI.ClaimAssetAction
    ) -> String {
        "asset:\(record.id):\(action.rawValue)"
    }

    private func deadlineTransitionKey(
        record: FreightClaimsAPI.ClaimDeadlineRecord,
        action: FreightClaimsAPI.ClaimDeadlineAction
    ) -> String {
        "deadline:\(record.id):\(action.rawValue)"
    }

    private func assignmentTransitionKey(
        record: FreightClaimsAPI.ClaimAssignmentRecord,
        action: FreightClaimsAPI.ClaimAssignmentAction
    ) -> String {
        "assignment:\(record.id):\(action.rawValue)"
    }

    @MainActor
    private func loadInvestigatorDirectory(for claim: FreightClaimsAPI.ClaimDetail) async {
        guard claim.lifecycleCapabilities.assignInvestigator.allowed else {
            investigatorDirectory = nil
            investigatorDirectoryError = nil
            investigatorDirectoryLoading = false
            return
        }

        investigatorDirectoryLoading = true
        investigatorDirectoryError = nil
        investigatorDirectory = nil
        defer { investigatorDirectoryLoading = false }

        do {
            investigatorDirectory = try await EusoTripAPI.shared.freightClaims
                .getClaimSpecialistCandidates(
                    claimId: claim.claimId,
                    specialty: selectedAssignmentType
                )
        } catch {
            investigatorDirectoryError = FreightClaimConsumerCanon.errorMessage(error)
        }
    }

    @MainActor
    private func assignInvestigator(
        for claim: FreightClaimsAPI.ClaimDetail,
        directory: FreightClaimsAPI.ClaimInvestigatorCandidateDirectory
    ) async {
        guard !investigatorAssignmentPending,
              pendingTransitionKey == nil,
              self.claim == claim,
              investigatorDirectory == directory,
              claim.lifecycleCapabilities.assignInvestigator.allowed,
              investigatorDirectoryIsActionable(directory, for: claim),
              let candidate = directory.candidates.first(where: { $0.id == selectedInvestigatorId }),
              ["low", "medium", "high", "urgent"].contains(investigatorPriority) else {
            transitionError = "Select a current vessel-qualified \(selectedAssignmentType.label.lowercased()) and priority from the refreshed claim directory."
            return
        }

        let notes = normalizedInvestigatorNotes(investigatorNotes)
        guard (notes?.count ?? 0) <= 2_000 else {
            transitionError = "Assignment scope must be 2,000 characters or fewer."
            return
        }
        guard let referenceNumber = FreightClaimConsumerCanon.clean(claim.load.referenceNumber) else {
            transitionError = "This vessel claim has no recorded booking reference, so the assignment acknowledgement cannot be verified."
            return
        }

        let fingerprint = makeInvestigatorRequestFingerprint(
            claimId: claim.claimId,
            investigatorId: candidate.id,
            assignmentType: selectedAssignmentType,
            jurisdiction: directory.jurisdiction,
            priority: investigatorPriority,
            notes: notes
        )
        let requestKey: UUID
        if investigatorRequestFingerprint == fingerprint, let existingKey = investigatorRequestKey {
            requestKey = existingKey
        } else {
            requestKey = UUID()
            investigatorRequestKey = requestKey
            investigatorRequestFingerprint = fingerprint
        }

        investigatorAssignmentPending = true
        investigatorAssignmentConfirmation = nil
        transitionError = nil
        defer { investigatorAssignmentPending = false }

        do {
            let result = try await EusoTripAPI.shared.freightClaims.assignClaimSpecialist(
                claimId: claim.claimId,
                specialistProfileId: candidate.id,
                assignmentType: selectedAssignmentType,
                jurisdiction: directory.jurisdiction,
                priority: investigatorPriority,
                notes: notes,
                requestKey: requestKey
            )
            guard result.success,
                  result.claimId == claim.claimId,
                  result.transportMode == .vessel,
                  result.specialistProfileId == candidate.id,
                  result.assignmentType == selectedAssignmentType,
                  result.assignmentStatus == "invited",
                  result.priority == investigatorPriority,
                  result.referenceNumber == referenceNumber,
                  Int(result.assignmentId).map({ $0 > 0 }) == true,
                  result.assignedBy > 0,
                  FreightClaimConsumerCanon.clean(result.assignedAt) != nil else {
                transitionError = "EusoTrip did not return an exact acknowledgement for this vessel specialist assignment. The same request identity is retained for retry."
                return
            }

            guard let refreshed = try await FreightClaimConsumerCanon.detail(
                claimId: claim.claimId,
                mode: .vessel
            ) else {
                transitionError = "The assignment was acknowledged, but the refreshed vessel claim was unavailable. The same request identity is retained for retry."
                return
            }
            self.claim = refreshed
            await loadInvestigatorDirectory(for: refreshed)

            guard refreshed.transportMode == .vessel,
                  refreshed.status == result.status,
                  refreshed.assignmentLedger.state == "recorded",
                  refreshed.assignmentLedger.accessState == "granted",
                  refreshed.assignmentLedger.trackingState == "tracked",
                  refreshed.assignmentLedger.provenance.source == "freight_claim_assignments",
                  FreightClaimConsumerCanon.clean(refreshed.assignmentLedger.provenance.observedAt) != nil,
                  let assignment = refreshed.assignmentLedger.records.first(where: { $0.id == result.assignmentId }),
                  assignmentReadbackConfirms(
                    assignment,
                    assignmentId: result.assignmentId,
                    specialistProfileId: candidate.id,
                    assignmentType: selectedAssignmentType,
                    jurisdiction: directory.jurisdiction,
                    priority: investigatorPriority,
                    notes: notes
                  ) else {
                transitionError = "The invitation was acknowledged, but the refreshed vessel assignment register did not confirm the same verified specialist profile, jurisdiction, priority, and credential snapshot. The same request identity is retained for retry."
                return
            }

            investigatorRequestKey = nil
            investigatorRequestFingerprint = nil
            selectedInvestigatorId = ""
            investigatorPriority = ""
            investigatorNotes = ""
            investigatorAssignmentConfirmation = "\(investigatorCandidateLabel(candidate)) was invited to \(claim.claimNumber)."
        } catch {
            transitionError = "The vessel specialist assignment is not confirmed. \(FreightClaimConsumerCanon.errorMessage(error)) The same request identity is retained for retry."
        }
    }

    @MainActor
    private func transitionAsset(
        record: FreightClaimsAPI.ClaimAssetRecord,
        action: FreightClaimsAPI.ClaimAssetAction
    ) async {
        guard pendingTransitionKey == nil, let currentClaim = claim else { return }
        let key = assetTransitionKey(record: record, action: action)
        let requestKey = transitionRequestKeys[key] ?? UUID()
        transitionRequestKeys[key] = requestKey
        pendingTransitionKey = key
        transitionError = nil
        defer { pendingTransitionKey = nil }

        do {
            let result = try await EusoTripAPI.shared.freightClaims.verifyClaimAsset(
                claimId: currentClaim.claimId,
                assetId: record.id,
                verificationStatus: action,
                requestKey: requestKey
            )
            guard result.success,
                  result.assetId == record.id,
                  result.verificationStatus == action,
                  result.transportMode == .vessel else {
                transitionError = "EusoTrip did not return a matching confirmation for this vessel claim asset. Pull down to refresh before retrying."
                return
            }
            await reloadAfterConfirmedTransition(
                requestKey: key,
                claimId: currentClaim.claimId,
                subject: "vessel claim asset"
            ) { refreshed in
                refreshed.assetLedger.records.first(where: { $0.id == record.id })?.verificationStatus == action.rawValue
            }
        } catch {
            transitionError = FreightClaimConsumerCanon.errorMessage(error)
        }
    }

    @MainActor
    private func transitionDeadline(
        record: FreightClaimsAPI.ClaimDeadlineRecord,
        action: FreightClaimsAPI.ClaimDeadlineAction
    ) async {
        guard pendingTransitionKey == nil, let currentClaim = claim else { return }
        let key = deadlineTransitionKey(record: record, action: action)
        let requestKey = transitionRequestKeys[key] ?? UUID()
        transitionRequestKeys[key] = requestKey
        pendingTransitionKey = key
        transitionError = nil
        defer { pendingTransitionKey = nil }

        do {
            let result = try await EusoTripAPI.shared.freightClaims.transitionClaimDeadline(
                claimId: currentClaim.claimId,
                deadlineId: record.id,
                action: action,
                requestKey: requestKey
            )
            guard result.success,
                  result.deadlineId == record.id,
                  result.action == action,
                  result.transportMode == .vessel else {
                transitionError = "EusoTrip did not return a matching confirmation for this vessel claim deadline. Pull down to refresh before retrying."
                return
            }
            await reloadAfterConfirmedTransition(
                requestKey: key,
                claimId: currentClaim.claimId,
                subject: "vessel claim deadline"
            ) { refreshed in
                deadlineReadbackConfirms(recordId: record.id, action: action, claim: refreshed)
            }
        } catch {
            transitionError = FreightClaimConsumerCanon.errorMessage(error)
        }
    }

    @MainActor
    private func transitionAssignment(
        record: FreightClaimsAPI.ClaimAssignmentRecord,
        action: FreightClaimsAPI.ClaimAssignmentAction,
        conflictAttestation: String? = nil
    ) async {
        guard pendingTransitionKey == nil, let currentClaim = claim else { return }
        let key = assignmentTransitionKey(record: record, action: action)
        let requestKey = transitionRequestKeys[key] ?? UUID()
        transitionRequestKeys[key] = requestKey
        pendingTransitionKey = key
        transitionError = nil
        defer { pendingTransitionKey = nil }

        do {
            let result = try await EusoTripAPI.shared.freightClaims.transitionClaimAssignment(
                claimId: currentClaim.claimId,
                assignmentId: record.id,
                status: action,
                conflictAttestation: conflictAttestation,
                requestKey: requestKey
            )
            guard result.success,
                  result.assignmentId == record.id,
                  result.status == action,
                  result.transportMode == .vessel else {
                transitionError = "EusoTrip did not return a matching confirmation for this vessel claim assignment. Pull down to refresh before retrying."
                return
            }
            await reloadAfterConfirmedTransition(
                requestKey: key,
                claimId: currentClaim.claimId,
                subject: "vessel claim assignment"
            ) { refreshed in
                assignmentTransitionReadbackConfirms(recordId: record.id, action: action, claim: refreshed)
            }
        } catch {
            transitionError = FreightClaimConsumerCanon.errorMessage(error)
        }
    }

    @MainActor
    private func confirmAssignmentAcceptance() {
        guard let assignmentId = pendingConflictAttestationAssignmentId,
              let record = claim?.assignmentLedger.records.first(where: { $0.id == assignmentId }),
              record.allowedActions.contains(.accepted) else {
            pendingConflictAttestationAssignmentId = nil
            transitionError = "The vessel claim invitation changed before acceptance. Pull down to refresh the assignment register."
            return
        }
        pendingConflictAttestationAssignmentId = nil
        Task {
            await transitionAssignment(
                record: record,
                action: .accepted,
                conflictAttestation: "no_known_conflict"
            )
        }
    }

    @MainActor
    private func reloadAfterConfirmedTransition(
        requestKey: String,
        claimId: String,
        subject: String,
        confirms: (FreightClaimsAPI.ClaimDetail) -> Bool
    ) async {
        do {
            guard let refreshed = try await FreightClaimConsumerCanon.detail(claimId: claimId, mode: .vessel) else {
                transitionError = "The claim update was confirmed, but the refreshed vessel claim was not returned. Pull down to refresh."
                return
            }
            claim = refreshed
            guard confirms(refreshed) else {
                transitionError = "The update was acknowledged, but the refreshed \(subject) does not yet show that state. Pull down to refresh before retrying."
                return
            }
            transitionRequestKeys.removeValue(forKey: requestKey)
        } catch {
            transitionError = "The claim update was confirmed, but its refreshed vessel record could not be loaded. \(FreightClaimConsumerCanon.errorMessage(error))"
        }
    }

    private func deadlineReadbackConfirms(
        recordId: String,
        action: FreightClaimsAPI.ClaimDeadlineAction,
        claim: FreightClaimsAPI.ClaimDetail
    ) -> Bool {
        guard let record = claim.deadlineLedger.records.first(where: { $0.id == recordId }) else {
            return false
        }
        switch action {
        case .verifyAuthority:
            return record.authorityStatus == "verified"
        case .complete:
            return record.status == "completed"
        case .waive:
            return record.status == "waived"
        case .supersede:
            return record.status == "superseded" && record.authorityStatus == "superseded"
        }
    }

    private func assignmentTransitionReadbackConfirms(
        recordId: String,
        action: FreightClaimsAPI.ClaimAssignmentAction,
        claim: FreightClaimsAPI.ClaimDetail
    ) -> Bool {
        guard let record = claim.assignmentLedger.records.first(where: { $0.id == recordId }),
              record.status == action.rawValue else {
            return false
        }
        if action == .accepted {
            return record.scope.conflictAttestation == "no_known_conflict"
                && FreightClaimConsumerCanon.clean(record.scope.conflictAttestedAt) != nil
                && record.verification.profileState == "linked"
                && record.verification.snapshotState == "recorded"
        }
        return true
    }

    @ViewBuilder
    private func outcomeState(_ claim: FreightClaimsAPI.ClaimDetail) -> some View {
        if let decision = claim.decision {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Recorded outcome")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                LifecycleCard {
                    VStack(spacing: 0) {
                        FreightClaimValueRow(label: "Decision", value: FreightClaimConsumerCanon.label(decision.type))
                        Divider().opacity(0.25)
                        FreightClaimValueRow(
                            label: "Decision amount",
                            value: FreightClaimConsumerCanon.financialContext(amount: decision.amount, currency: claim.currency)
                        )
                        Divider().opacity(0.25)
                        FreightClaimValueRow(label: "Decided by", value: FreightClaimConsumerCanon.clean(decision.decidedBy))
                        Divider().opacity(0.25)
                        FreightClaimValueRow(label: "Decided at", value: FreightClaimConsumerCanon.clean(decision.decidedAt))
                    }
                }
            }
        } else {
            Text("No recorded outcome is available for this claim.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    @MainActor
    private func load() async {
        loading = claim == nil
        loadError = nil
        if pendingTransitionKey == nil && !investigatorAssignmentPending { transitionError = nil }
        do {
            let refreshed = try await FreightClaimConsumerCanon.detail(claimId: claimId, mode: .vessel)
            claim = refreshed
            if let refreshed {
                await loadInvestigatorDirectory(for: refreshed)
            } else {
                investigatorDirectory = nil
                investigatorDirectoryError = nil
                investigatorDirectoryLoading = false
            }
        } catch {
            investigatorDirectory = nil
            investigatorDirectoryError = nil
            investigatorDirectoryLoading = false
            loadError = FreightClaimConsumerCanon.errorMessage(error)
        }
        loading = false
    }
}

private struct VesselClaimLifecycleActionButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDestructiveConfirmation = false

    let title: String
    let accessibilityLabel: String
    let pending: Bool
    let disabled: Bool
    let destructive: Bool
    let action: () -> Void

    var body: some View {
        Button {
            if destructive {
                showsDestructiveConfirmation = true
            } else {
                action()
            }
        } label: {
            HStack(spacing: Space.s2) {
                if pending {
                    if reduceMotion {
                        Image(systemName: "hourglass")
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(pending ? "Submitting" : title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(destructive ? Brand.danger : Brand.info)
        .disabled(disabled)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(pending ? "Submitting" : "Available"))
        .accessibilityHint(destructive
            ? "Requests confirmation before committing this claim action online."
            : "Commits this claim action online and reloads the confirmed record.")
        .confirmationDialog(
            "Confirm \(title.lowercased())",
            isPresented: $showsDestructiveConfirmation,
            titleVisibility: .visible
        ) {
            Button(title, role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes the persisted claim register and cannot be undone from this screen.")
        }
    }
}

#Preview("Vessel claim workflow") {
    VesselClaimWorkflowScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
