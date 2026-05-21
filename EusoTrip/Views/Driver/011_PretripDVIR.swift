//
//  011_PretripDVIR.swift
//  EusoTrip — Screen 011 · Pre-trip DVIR (LIVE-wired)
//
//  Backend:
//    inspections.getTemplate({ type: "pre_trip" })   — FMCSA walk-around
//    inspections.submit(InspectionSubmission)        — writes to inspections
//
//  Doctrine anchors (unchanged from the v1 mock):
//    §3  numbers up front (odometer, % complete, defect count)
//    §4.3 iridescent hairline = progress bar
//    §7  canvas density — rows edge-to-edge
//    §8  Driver rhythm
//    §9  ONE gradient-filled surface: the submit CTA
//    §12 DONE criteria
//
//  Driven by `PretripDVIRViewModel`.  The view is structural only —
//  all logic, API, state-machine work lives in the view-model.
//

import SwiftUI

// MARK: - Screen

struct PretripDVIR: View {
    @Environment(\.palette) var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverUploadPhoto) private var uploadPhoto
    @Environment(\.lifecycleExit) private var exit
    @StateObject private var vm: PretripDVIRViewModel

    /// 2026-05-20 · IO 2026 P0-6 — Astra camera capture target.
    /// When non-nil, presents the camera sheet; on dismissal-with-image
    /// the captured photo is handed to `vm.analyzeItemWithAstra`.
    @State private var astraCaptureForItemId: String? = nil

    // Initializers let callers inject the live vehicle / load in production.
    // Defaults are empty so an unconfigured render reads as a neutral
    // empty state ("Unit —") rather than the legacy "Unit 4821" Figma
    // fixture. Production call sites (DriverHomeGlances + lifecycle
    // dispatchers) must inject the real assigned-vehicle context. 97th
    // firing — fake-data eradication §11.
    init(vehicleId: String = "",
         trailerId: String? = nil,
         unitLabel: String = "",
         loadLabel: String? = nil,
         trailer: TrailerCode? = nil) {
        // T-018 · 2026-05-20 — `trailer` is the canonical TrailerCode for
        // the load on this pre-trip. Threaded into the ViewModel so the
        // walkaround template the server returns is keyed by trailer
        // (tanker pressure check / reefer setpoint / livestock 28-hr /
        // hazmat placards). Nil-safe — defaults to the legacy generic
        // FMCSA 393 walkaround.
        _vm = StateObject(wrappedValue: PretripDVIRViewModel(
            vehicleId: vehicleId,
            trailerId: trailerId,
            unitLabel: unitLabel,
            loadLabel: loadLabel,
            trailer: trailer
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            content
        }
        .task {
            if case .idle = vm.phase { await vm.load() }
        }
        // 2026-05-20 · IO 2026 P0-6 — Astra camera capture sheet.
        .sheet(item: Binding(
            get: { astraCaptureForItemId.map { AstraCapturePresentation(itemId: $0) } },
            set: { astraCaptureForItemId = $0?.itemId }
        )) { presentation in
            AstraCameraSheet(itemLabel: itemLabel(for: presentation.itemId)) { image in
                let id = presentation.itemId
                astraCaptureForItemId = nil
                if let image {
                    Task { await vm.analyzeItemWithAstra(itemId: id, image: image) }
                }
            }
        }
        .alert("Astra couldn't read this photo",
               isPresented: Binding(
                   get: { vm.astraErrorMessage != nil },
                   set: { if !$0 { vm.astraErrorMessage = nil } }
               )) {
            Button("OK", role: .cancel) { vm.astraErrorMessage = nil }
        } message: {
            Text(vm.astraErrorMessage ?? "")
        }
        // Uniform cafe-door entrance.
        .screenTileRoot()
    }

    /// Item label used in the camera-sheet title.
    private func itemLabel(for itemId: String) -> String {
        for sec in vm.sections {
            if let item = sec.items.first(where: { $0.id == itemId }) {
                return item.name
            }
        }
        return itemId
    }

    // MARK: - TopBar

    private var topBar: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerMetaLine.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .monospaced()
                Text("Pre-trip DVIR")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer()
            // Save-and-exit chip. Calls the `lifecycleExit` env closure that
            // ContentView wires to `trip.reset()`, returning the driver to
            // the idle Home dashboard. The button used to be an empty
            // `Button { }` placeholder (left over from the mock pass), which
            // made the DVIR screen un-exitable until the user tapped Submit.
            Button {
                exit?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save and exit DVIR")
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var headerMetaLine: String {
        // Empty unitLabel → em-dash neutral so we never paint a
        // hardcoded fixture. Production injection must populate this.
        let unit = vm.unitLabel.isEmpty ? "Unit —" : vm.unitLabel
        if let load = vm.loadLabel, !load.isEmpty { return "\(unit) · \(load)" }
        return unit
    }

    // MARK: - Content switch

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .idle, .loading:
            loadingState
        case .editing, .submitting:
            editor
        case .submitted(let resp):
            submittedCard(resp)
        case .error(let msg):
            errorState(msg)
        }
    }

    // MARK: - Loading state (shimmer row placeholders)

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            ProgressView().tint(palette.textPrimary)
            Text("Pulling FMCSA walk-around…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error state

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Brand.danger)
            Text("Couldn't load DVIR")
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s5)
            Button("Try again") { Task { await vm.load() } }
                .font(EType.bodyStrong)
                .foregroundStyle(LinearGradient.diagonal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editor (sections + submit band)

    private var editor: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Compliance strip — sits at the top of every Pre-trip
                    // DVIR session. Mirrors the web platform's
                    // RegulatoryCompliancePanel embedded at the top of
                    // LoadDetails: the rule is surfaced where the work
                    // happens, not hidden in a Me-tab hub. eDVIR (49 CFR
                    // § 396) took effect Mar 23, 2026 — this strip
                    // confirms the tap-to-sign + 14-day retention the
                    // driver is performing here now meets Part 396
                    // without a paper backup. Chip tap opens the detail
                    // sheet with the full rule and an ack action.
                    HStack {
                        ComplianceInlineChip(tag: .eDvir)
                        Spacer()
                    }
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                    // ESANG Vision DVIR scan — driver photographs a
                    // suspect part / fluid / wear; Gemini multi-pass
                    // returns findings with severity + recommendation.
                    // Real-data wiring per Gemini parity audit
                    // 2026-05-05.
                    AIVisualScanButton(
                        title: "Scan vehicle with ESANG Vision",
                        subtitle: "Photo → AI inspection (brakes, lights, leaks, tire wear)",
                        procPath: "visualIntelligence.inspectDVIR"
                    ) { result in
                        // Surface the result by appending findings to
                        // the current DVIR notes (the editor view-model
                        // owns the section state). Drivers see the AI
                        // signal inline and can mark sections accordingly.
                        if let summary = result.summary, !summary.isEmpty {
                            vm.appendInspectorNote(summary)
                        }
                        for f in result.findings ?? [] {
                            if let desc = f.description {
                                vm.appendInspectorNote("• [\(f.severity ?? "note")] \(desc)")
                            }
                        }
                    }
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                    ForEach(Array(vm.sections.enumerated()), id: \.element.id) { idx, section in
                        sectionBlock(section, index: idx + 1, total: vm.sections.count)
                    }
                    signatureCard
                        .padding(Space.s5)
                }
            }
            submitBand
        }
    }

    // MARK: - Section

    private func sectionBlock(_ section: PretripDVIRViewModel.EditableSection,
                              index: Int,
                              total: Int) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(palette.borderFaint)
                .padding(.top, Space.s5)
            sectionHeader(name: section.name, index: index, total: total)
            ForEach(section.items) { item in
                itemRow(item)
                if item.status == .fail {
                    defectDrawer(for: item)
                }
            }
        }
    }

    private func sectionHeader(name: String, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                (Text("Section \(index)").fontWeight(.semibold).foregroundStyle(palette.textPrimary)
                 + Text(" of \(total)").foregroundStyle(palette.textSecondary))
                    .font(EType.caption).monospacedDigit()
                Spacer()
                Text(vm.progressDisplay)
                    .font(EType.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
            Text(name)
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(vm.progress))
                }
            }
            .frame(height: 2)
            .padding(.top, 2)
            .accessibilityElement()
            .accessibilityLabel("DVIR progress, \(Int(vm.progress * 100)) percent complete")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: - Item row

    private func itemRow(_ item: PretripDVIRViewModel.EditableItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.s3) {
                stateOrb(for: item.status)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(item.categoryName)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Space.s2)

                // 2026-05-20 · IO 2026 P0-6 — Astra scan affordance.
                astraScanButton(for: item)
                    .padding(.top, 2)

                statusTrailingMenu(for: item)
                    .padding(.top, 2)
            }

            // 2026-05-20 · IO 2026 P0-6 — inline Astra observation.
            if let obs = vm.astraObservations[item.id] {
                astraObservationStrip(obs)
                    .padding(.top, Space.s2)
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s4)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.borderFaint).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(item.name), \(trailLabel(for: item.status))"))
    }

    /// "Scan with Astra" camera button. Opens the camera sheet; the
    /// captured photo flows into `vm.analyzeItemWithAstra(itemId:image:)`.
    /// Shows a spinner while the analyze call is in flight.
    @ViewBuilder
    private func astraScanButton(for item: PretripDVIRViewModel.EditableItem) -> some View {
        Button {
            astraCaptureForItemId = item.id
        } label: {
            ZStack {
                if vm.astraInFlightItemId == item.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vm.astraInFlightItemId != nil)
        .accessibilityLabel("Scan \(item.name) with Astra")
    }

    /// Inline strip under an item row showing the Astra observation
    /// summary + verdict pill. Tap-collapses by default; tap once to
    /// reveal the warnings list.
    @ViewBuilder
    private func astraObservationStrip(_ obs: AstraObservation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ASTRA")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(obs.passFail.rawValue.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Color(uiColor: obs.passFail.color))
            }
            Text(obs.summary)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !obs.warnings.isEmpty {
                ForEach(obs.warnings, id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(8)
        .background(palette.borderFaint.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Figma-verbatim trailing word label — tap opens a Menu so the driver
    /// can pick Pass / N/A / Defect.  Matches the PASS / PENDING / DEFECT
    /// uppercase word-mark shown in the 011 mock.
    private func statusTrailingMenu(for item: PretripDVIRViewModel.EditableItem) -> some View {
        Menu {
            Button("Pass") { vm.setStatus(.pass, forItemId: item.id) }
            Button("N/A")  { vm.setStatus(.na,   forItemId: item.id) }
            Button("Defect", role: .destructive) {
                vm.setStatus(.fail, forItemId: item.id)
            }
        } label: {
            Text(trailWord(for: item.status))
                .font(EType.micro).tracking(0.8).fontWeight(.bold)
                .foregroundStyle(trailTint(for: item.status))
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Set status for \(item.name)")
    }

    private func trailWord(for status: InspectionItemStatus?) -> String {
        guard let status else { return "PENDING" }
        switch status {
        case .pass: return "PASS"
        case .fail: return "DEFECT"
        case .na:   return "N/A"
        }
    }

    private func trailTint(for status: InspectionItemStatus?) -> Color {
        guard let status else { return palette.textTertiary }
        switch status {
        case .pass: return Brand.success
        case .fail: return Brand.warning
        case .na:   return palette.textTertiary
        }
    }

    @ViewBuilder
    private func stateOrb(for status: InspectionItemStatus?) -> some View {
        let size: CGFloat = 28
        ZStack {
            switch status {
            case .pass:
                Circle().fill(Brand.success).frame(width: size, height: size)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            case .fail:
                Circle().fill(palette.tintWarning)
                    .overlay(Circle().strokeBorder(Brand.warning, lineWidth: 1.5))
                    .frame(width: size, height: size)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.warning)
            case .na:
                Circle().strokeBorder(palette.borderSoft, lineWidth: 1.5)
                    .frame(width: size, height: size)
                Text("—")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            case .none:
                Circle().strokeBorder(palette.borderSoft, lineWidth: 1.5)
                    .frame(width: size, height: size)
                Circle().fill(palette.borderSoft).frame(width: 6, height: 6)
            }
        }
        .frame(width: size, height: size)
    }

    private func trailLabel(for status: InspectionItemStatus?) -> String {
        guard let status else { return "Pending" }
        switch status {
        case .pass: return "Pass"
        case .fail: return "Defect"
        case .na:   return "Not applicable"
        }
    }

    // MARK: - Defect drawer

    private func defectDrawer(for item: PretripDVIRViewModel.EditableItem) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                (Text("Defect flagged. ").fontWeight(.bold).foregroundStyle(Brand.warning)
                 + Text("Describe what you saw so the mechanic can triage. Photo recommended.")
                    .foregroundStyle(palette.textPrimary))
                    .font(EType.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s2)
                Button { uploadPhoto?() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add photo")
                            .font(EType.caption).fontWeight(.semibold)
                    }
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Upload defect photo")
            }
            TextField("e.g. slack adjuster travel 3.25\", leak at fifth-wheel",
                      text: Binding(
                        get: { item.note },
                        set: { vm.setNote($0, forItemId: item.id) }
                      ),
                      axis: .vertical)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2...4)
                .padding(Space.s3)
                .background(palette.bgCard.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .padding(.horizontal, Space.s5)
        .padding(.vertical, Space.s3)
        .background(palette.tintWarning)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.borderFaint).frame(height: 1)
        }
    }

    // MARK: - Signature / odometer / notes card

    private var signatureCard: some View {
        GlassCard(rim: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Sign & submit")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)

                HStack(spacing: Space.s3) {
                    odometerField
                    vehicleField
                }

                signatureField

                TextField("Notes for dispatch / mechanic (optional)",
                          text: $vm.notes, axis: .vertical)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2...4)
                    .padding(Space.s3)
                    .background(palette.bgCardSoft.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
        }
    }

    private var odometerField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ODOMETER")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            TextField("e.g. 412508", value: $vm.odometer, format: .number)
                .keyboardType(.numberPad)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s3)
                .frame(height: 48)
                .background(palette.bgCardSoft.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var vehicleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UNIT")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(vm.unitLabel.isEmpty ? "—" : vm.unitLabel)
                .font(EType.body)
                .foregroundStyle(vm.unitLabel.isEmpty ? palette.textTertiary : palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.s3)
                .frame(height: 48)
                .background(palette.bgCardSoft.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    private var signatureField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DRIVER SIGNATURE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            TextField("Type your full legal name", text: $vm.driverSignature)
                .font(EType.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s3)
                .frame(height: 48)
                .background(palette.bgCardSoft.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    // MARK: - Sticky submit band

    private var submitBand: some View {
        VStack(spacing: Space.s2) {
            if vm.pendingRequiredCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "circle.dotted")
                    Text("\(vm.pendingRequiredCount) required item\(vm.pendingRequiredCount == 1 ? "" : "s") left")
                }
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            }

            CTAButton(
                title: isSubmitting ? "Submitting…" : submitLabel,
                action: {
                    Task {
                        await vm.submit()
                        if case .submitted = vm.phase { advance?() }
                    }
                }
            )
            .opacity(vm.canSubmit ? 1 : 0.55)
            .disabled(!vm.canSubmit)
            .accessibilityLabel(submitLabel)

            (Text("Submitting opens a ").foregroundStyle(palette.textSecondary)
             + Text(vm.defectCount > 0 ? "shop route" : "safe-to-operate record")
                .foregroundStyle(vm.defectCount > 0 ? Brand.warning : Brand.success)
                .fontWeight(.semibold)
             + Text(vm.defectCount > 0
                    ? " — unit will not leave the yard until cleared."
                    : " — signed under 49 CFR 396.13.")
                .foregroundStyle(palette.textSecondary))
                .font(EType.caption)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
        .background(
            LinearGradient(
                colors: [palette.bgPage.opacity(0), palette.bgPage],
                startPoint: .top, endPoint: .center
            )
        )
    }

    private var submitLabel: String {
        if vm.defectCount > 0 { return "Submit defect · notify dispatcher" }
        return "Submit DVIR · safe to operate"
    }

    private var isSubmitting: Bool {
        if case .submitting = vm.phase { return true }
        return false
    }

    // MARK: - Submitted card

    private func submittedCard(_ resp: InspectionSubmitResponse) -> some View {
        VStack(spacing: Space.s5) {
            ZStack {
                Circle()
                    .fill(Brand.success.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Brand.success)
                    .symbolEffect(.bounce, value: true)
            }
            VStack(spacing: 6) {
                Text(resp.safeToOperate ? "Cleared to roll" : "Defect filed")
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                Text(resp.safeToOperate
                     ? "Pre-trip DVIR submitted · you're safe to operate."
                     : "Dispatcher notified. Unit is on a shop route until cleared.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s5)
                Text("DVIR #\(resp.id) · \(resp.submittedAt.prefix(16))")
                    .font(EType.micro).tracking(0.5).monospaced()
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 4)
            }
            CTAButton(title: "Back to Home", action: { advance?() })
                .padding(.horizontal, Space.s5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Space.s8)
    }
}

// MARK: - Wrapped in Shell + Driver nav

private func driverNavLeading() -> [NavSlot] {
    [
        NavSlot(label: "Home",  systemImage: "house", isCurrent: false),
        NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: true)
    ]
}
private func driverNavTrailing() -> [NavSlot] {
    [
        NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
        NavSlot(label: "Me",     systemImage: "person", isCurrent: false)
    ]
}

struct PretripDVIRScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            PretripDVIR()
        } nav: {
            BottomNav(leading: driverNavLeading(),
                      trailing: driverNavTrailing(),
                      orbState: .idle)
        }
    }
}

// MARK: - Previews (Dark + Light)

#Preview("Pre-trip DVIR · Dark") {
    PretripDVIRScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Pre-trip DVIR · Light") {
    PretripDVIRScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}

// MARK: - IO 2026 P0-6 · Astra camera bridge

/// Identifiable wrapper around the item id so SwiftUI's `.sheet(item:)`
/// reliably presents on iOS 17+ (raw String isn't Identifiable).
private struct AstraCapturePresentation: Identifiable {
    let itemId: String
    var id: String { itemId }
}

/// UIImagePickerController bridge — single capture, returns the
/// photo via the `onImage` callback. No editing, no library.
private struct AstraCameraSheet: UIViewControllerRepresentable {
    let itemLabel: String
    let onImage: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Camera if available, otherwise fall back to library so the
        // affordance is testable on simulator.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.title = "Scan \(itemLabel)"
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            onImage(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onImage(nil)
        }
    }
}
