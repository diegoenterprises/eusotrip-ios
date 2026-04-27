//
//  701_TerminalGateQueue.swift
//  EusoTrip — Terminal · Gate Queue (brick 701).
//
//  Second brick on the Terminal Manager role track (700s). The natural
//  follow-on to 700_TerminalHome — when the operator taps the
//  "ACTIVE MOVEMENTS" section header on the home, this is the deep
//  gate-queue surface that opens. Until 701 shipped, that header was
//  read-only chrome. Now the tap presents this real surface so
//  Terminal depth matches the structural depth of Catalyst (500/501/
//  502), Carrier (300/301/302), and Broker (400/401/402): two
//  production screens with the home → detail tap path wired
//  end-to-end (parity with Escort 600 → 601).
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §1 (gradient-only
//  accent — no `.fill(Brand.blue)` / `.tint(Brand.blue)`), §2 (no
//  Toggles on this brick), §4 (tokenized spacing / radius / type —
//  Space.s*, Radius.*, EType.*), §5 (palette semantic only — no
//  hard-coded `Color.white` / `Color.black` / `Color.gray` fills
//  outside the CTA inverse-text and shadow opacities), §3
//  (`AnyShapeStyle` wrapping for ternary shape-styles in fill /
//  stroke), §10 (previews compile in isolation — `.task` doesn't
//  run in the preview canvas, so the store stays in `.loading` and
//  never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data,
//  plugged into backend"):
//
//    • Gate-queue list → `TerminalGateQueueStore` (LiveDataStores.swift)
//      → `terminals.getGateQueue` (input `{ limit: number }`). If the
//      parallel router has not shipped, the store resolves to `.error`
//      and the screen surfaces an honest retry banner. No fixture
//      data ever.
//    • "Assign dock" CTA per row → `terminals.assignDock` mutation
//      (input `{ id: string, dock: string }`). Each row owns its own
//      in-flight + error state independently of the others, so a
//      failed assign on row B doesn't disturb row A's idle CTA.
//      On success the row repaints from the mutation's returned
//      envelope (no extra round-trip). On failure the CTA flips back
//      to its idle label and the inline error surfaces — local state
//      never lies about the commit landing.
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—") — every nullable column on a fresh queue row (no priority
//      hint, no hazmat class, no appointment window) renders as a
//      neutral em-dash, never a fabricated value.
//
//  Wired into `ContentView.ScreenRegistry` as id="701".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct TerminalGateQueue: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var queue = TerminalGateQueueStore()

    /// Per-row in-flight state for the "Assign dock" CTA. Indexed by
    /// queue-row id so a failed assign on row B doesn't disturb row A.
    @State private var assignInFlight: Set<String> = []
    /// Per-row error message (post-mutation). Cleared when the row's
    /// CTA is tapped again or the queue refresh fires.
    @State private var assignError: [String: String] = [:]
    /// Local override for `dockAssignment` keyed by row id. Set by a
    /// successful mutation so the row re-paints immediately without
    /// waiting for the next refresh round-trip.
    @State private var localDockAssignment: [String: String] = [:]

    /// Row currently presenting the dock-input sheet. `nil` while no
    /// row has its CTA tapped.
    @State private var assignSheetRow: TerminalAPI.GateQueueItem? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                contentBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await queue.refresh() }
        .refreshable { await queue.refresh() }
        // Dock-input sheet — opened by tapping the inline "Assign dock"
        // button on a queue row. Detents `[.medium]` + drag indicator
        // matches the lightweight one-input doctrine.
        .sheet(item: $assignSheetRow) { row in
            assignDockSheet(for: row)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("TERMINAL · GATE QUEUE")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text(headline)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(subhead)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }

    /// Identity-aware headline. Falls back to a neutral title so the
    /// header never reads as a placeholder.
    private var headline: String {
        if let name = session.user?.firstName, !name.isEmpty {
            return "Queue, \(name)"
        }
        return "Gate Queue"
    }

    private var subhead: String {
        switch queue.state {
        case .loading:
            return "Loading queue…"
        case .loaded(let rows):
            let count = rows.count
            return "\(count) in queue · awaiting dock"
        case .empty:
            return "0 in queue · gate is clear"
        case .error:
            return "Queue couldn't load"
        }
    }

    // MARK: - Content body (state machine)

    @ViewBuilder
    private var contentBody: some View {
        switch queue.state {
        case .loading:
            listSkeleton
        case .loaded(let rows):
            VStack(spacing: Space.s2) {
                ForEach(rows) { row in
                    queueRow(row)
                }
            }
        case .empty:
            EusoEmptyState(
                systemImage: "tray",
                title: "Gate is clear",
                subtitle: "When a truck or container gates in and waits for a dock, it'll show up here with a one-tap assign."
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    // MARK: - Queue row

    private func queueRow(_ row: TerminalAPI.GateQueueItem) -> some View {
        let resolvedDock = localDockAssignment[row.id] ?? row.dockAssignment
        let isAssigned = !resolvedDock.isEmpty
        let inFlight = assignInFlight.contains(row.id)
        let errMsg = assignError[row.id]

        return VStack(alignment: .leading, spacing: Space.s2) {
            // Top: load number + lane + priority chip
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.loadNumber.isEmpty ? "—" : row.loadNumber)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(row.origin.isEmpty ? "—" : row.origin) → \(row.destination.isEmpty ? "—" : row.destination)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if let priority = row.priority, !priority.isEmpty {
                    priorityChip(priority)
                }
            }

            // Middle: stage / arrived / hazmat / appointment
            HStack(spacing: 8) {
                metaChip(icon: "mappin.circle.fill",
                         label: row.stage.replacingOccurrences(of: "_", with: " ").uppercased())
                if !row.arrivedAt.isEmpty {
                    metaChip(icon: "clock", label: "ARR \(row.arrivedAt)")
                }
                if let hz = row.hazmatClass, !hz.isEmpty {
                    metaChip(icon: "flame.fill", label: "HZ \(hz)")
                }
                if let appt = row.appointmentWindow, !appt.isEmpty {
                    metaChip(icon: "calendar", label: appt.uppercased())
                }
                Spacer()
                if row.dwellHours > 0 {
                    Text(dwell(row.dwellHours))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
            }

            // Bottom: dock-assignment row + inline CTA
            HStack(spacing: Space.s3) {
                HStack(spacing: 6) {
                    Image(systemName: isAssigned ? "tray.full.fill" : "tray")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isAssigned
                                         ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(palette.textTertiary))
                    Text(isAssigned ? "Dock \(resolvedDock)" : "No dock yet")
                        .font(EType.caption)
                        .foregroundStyle(isAssigned ? palette.textPrimary : palette.textSecondary)
                }
                Spacer()
                Button {
                    assignError[row.id] = nil
                    assignSheetRow = row
                } label: {
                    HStack(spacing: 6) {
                        if inFlight {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: isAssigned ? "arrow.triangle.2.circlepath" : "plus.circle.fill")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        Text(isAssigned ? "Reassign" : "Assign dock")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LinearGradient.diagonal.opacity(inFlight ? 0.55 : 1.0))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            }

            if let msg = errMsg, !msg.isEmpty {
                Text(msg)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Assign-dock sheet

    @ViewBuilder
    private func assignDockSheet(for row: TerminalAPI.GateQueueItem) -> some View {
        AssignDockInputSheet(
            row: row,
            currentDock: localDockAssignment[row.id] ?? row.dockAssignment,
            onSubmit: { dock in
                Task { await commitAssignDock(row: row, dock: dock) }
            },
            onCancel: {
                assignSheetRow = nil
            }
        )
        .environment(\.palette, palette)
    }

    private func commitAssignDock(row: TerminalAPI.GateQueueItem, dock: String) async {
        let trimmed = dock.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !assignInFlight.contains(row.id) else { return }
        assignInFlight.insert(row.id)
        assignError[row.id] = nil
        defer {
            assignInFlight.remove(row.id)
            assignSheetRow = nil
        }
        do {
            let updated = try await EusoTripAPI.shared.terminal.assignDock(id: row.id, dock: trimmed)
            // Re-paint the row immediately from the mutation envelope.
            localDockAssignment[row.id] = updated.dockAssignment
        } catch {
            assignError[row.id] = readableError(error)
        }
    }

    // MARK: - Loading + error states

    private var listSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: { Task { await queue.refresh() } }) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    private func metaChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private func priorityChip(_ raw: String) -> some View {
        let label = raw.uppercased()
        let isHot = ["EXPEDITED", "HOT", "URGENT"].contains(label)
        let style: AnyShapeStyle = isHot
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.tintNeutral)
        let fg: Color = isHot ? .white : palette.textSecondary
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(style)
            .clipShape(Capsule())
    }

    /// Format dwell hours as a one-decimal "12.4 hr" label. Returns
    /// "—" for zero so the empty case never renders as "0.0 hr".
    private func dwell(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        return String(format: "%.1f hr", v)
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }
}

// MARK: - Assign-dock input sheet (split into its own struct so the
//         text field's @State isn't trapped inside an @ViewBuilder
//         closure on the parent view)

private struct AssignDockInputSheet: View {
    @Environment(\.palette) private var palette

    let row: TerminalAPI.GateQueueItem
    /// Currently-assigned dock, if any — pre-fills the text field on
    /// reassign so the operator sees what's there before typing over it.
    let currentDock: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var dockInput: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // Drag handle area is provided by SwiftUI's
            // .presentationDragIndicator(.visible).
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(currentDock.isEmpty ? "ASSIGN DOCK" : "REASSIGN DOCK")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(row.loadNumber.isEmpty ? "—" : row.loadNumber)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("\(row.origin.isEmpty ? "—" : row.origin) → \(row.destination.isEmpty ? "—" : row.destination)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("DOCK IDENTIFIER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                TextField("e.g. D-12", text: $dockInput)
                    .textFieldStyle(.plain)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .padding(Space.s3)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .submitLabel(.done)
                    .onSubmit { commit() }
                    .focused($inputFocused)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.characters)
            }

            HStack(spacing: Space.s3) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(palette.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: commit) {
                    Text("Assign")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(LinearGradient.diagonal.opacity(canSubmit ? 1.0 : 0.55))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }

            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgPage)
        .onAppear {
            // Pre-fill on reassign so the operator sees the current
            // dock identifier before typing over it.
            dockInput = currentDock
            // Defer focus by one runloop turn so the sheet's
            // appearance animation doesn't fight the keyboard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                inputFocused = true
            }
        }
    }

    private var canSubmit: Bool {
        let trimmed = dockInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != currentDock
    }

    private func commit() {
        let trimmed = dockInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentDock else { return }
        onSubmit(trimmed)
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct TerminalGateQueueScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TerminalGateQueue()
        } nav: {
            BottomNav(
                leading: terminalNavLeading_701(),
                trailing: terminalNavTrailing_701(),
                orbState: .idle
            )
        }
    }
}

private func terminalNavLeading_701() -> [NavSlot] {
    [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
     NavSlot(label: "Movements", systemImage: "shippingbox.fill", isCurrent: true)]
}

private func terminalNavTrailing_701() -> [NavSlot] {
    [NavSlot(label: "Yard", systemImage: "map",    isCurrent: false),
     NavSlot(label: "Me",   systemImage: "person", isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("701 · Terminal · Gate Queue · Night") {
    TerminalGateQueueScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("701 · Terminal · Gate Queue · Afternoon") {
    TerminalGateQueueScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
