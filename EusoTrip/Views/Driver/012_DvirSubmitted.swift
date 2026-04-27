//  012_DvirSubmitted.swift
//  EusoTrip — Screen 012 · Pre-trip DVIR — defect submitted (LIVE-wired Cohort B).
//
//  Backend wiring (verified in Services/EusoTripAPI.swift):
//    inspections.getDVIRHistory(vehicleId:Int?, limit:5)
//      → [DVIRHistoryEntry] · picks the most recent submission row
//        (unit number, report date, overall condition, defect count).
//    inspections.getOpenDefects(vehicleId:String?)
//      → [InspectionDefectEntry] · the defect row driving the OOS
//        classification + dispatcher routing.
//
//  Both feed `DvirSubmittedReviewStore` (a `BaseDynamicStore<Snapshot?>`),
//  which folds an all-clear fleet to `.empty` so the screen renders a
//  neutral `EusoEmptyState` ("No open defects on file") rather than a
//  fabricated brake-stroke vignette. Doctrine §13: no mock data.
//
//  Doctrine refs:
//    §3  numbers-first (severity, downtime, classification)
//    §4.3 one iridescent hairline
//    §6  dual register (night / morning) — copy that depends on time of
//        day stays register-driven; everything else binds to the snap.
//    §7  breathe — card padding intact
//    §8  Driver rhythm
//    §9  ActiveCard variant — status
//    §13 no mock data — `.empty` neutral state on miss
//

import SwiftUI

// MARK: - Screen

struct DvirSubmitted: View {
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverOpenDocDrawer) private var openDocDrawer
    @Environment(\.driverOpenMessages) private var openMessages
    @Environment(\.lifecycleAdvance) private var advance

    @Environment(\.palette) var palette

    @StateObject private var store = DvirSubmittedReviewStore()

    // Time-of-day register (doctrine §6) — drives ETA-window copy and
    // dispatcher salutation only. All identity fields (unit, defect,
    // classification) come from the live snapshot.
    enum Register {
        case night   // night dispatch · mobile repair
        case morning // day dispatch · yard shop
    }
    let register: Register

    init(register: Register = .night) {
        self.register = register
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            content
        }
        .task {
            if case .loading = store.state { await store.refresh() }
        }
        .screenTileRoot()
    }

    // MARK: Header

    /// Header is structural — it renders the same shape whether the
    /// store is loading or has a snap. The right-side timestamp swaps
    /// to "—" while the network round-trips.
    private var topBar: some View {
        HStack(spacing: Space.s3) {
            Button { navBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Back to DVIR")
            VStack(alignment: .leading, spacing: 2) {
                Text("Defect submitted")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text(headerMetaLine)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button { openDocDrawer?() } label: {
                Image(systemName: "doc.text")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            .accessibilityLabel("View full DVIR report")
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    private var headerMetaLine: String {
        switch store.state {
        case .loading:
            return "Loading…"
        case .empty:
            return "No defects on file · Pre-trip clean"
        case .error:
            return "Couldn't reach inspections service"
        case .loaded(let snap):
            let unit = snap?.unitDisplay ?? "—"
            let when = snap?.submittedDisplay ?? "—"
            return "\(unit) · Pre-trip DVIR · \(when)"
        }
    }

    // MARK: Content switch — drives the four states

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            loadingView
        case .empty:
            allClearView
        case .error(let err):
            errorView(err)
        case .loaded(let snap):
            if let snap = snap, snap.hasOpenDefect {
                loadedView(snap)
            } else {
                allClearView
            }
        }
    }

    // MARK: Loading skeleton

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ProgressView()
                .progressViewStyle(.circular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s8)
                .accessibilityLabel("Loading inspection summary")
        }
        .padding(Space.s5)
    }

    // MARK: Empty (all-clear) state — pre-trip submitted, no defects

    private var allClearView: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            EusoEmptyState(
                systemImage: "checkmark.shield",
                title: "No open defects on file",
                subtitle: "When a submitted DVIR flags a defect, it shows up here for the dispatcher's review.",
                cta: ("Continue pre-trip", { advance?() })
            )
            HStack {
                ComplianceInlineChip(tag: .eDvir)
                Spacer()
            }
        }
        .padding(Space.s5)
    }

    // MARK: Error banner

    private func errorView(_ err: Error) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            EusoEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't reach inspections",
                subtitle: err.localizedDescription,
                cta: ("Try again", { Task { await store.refresh() } })
            )
        }
        .padding(Space.s5)
    }

    // MARK: Loaded — defect surface

    private func loadedView(_ snap: DvirSubmittedReviewStore.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            confirmStrip(snap)
            oosCard(snap)
            shopTimeline(snap)
            dispatcherStrip(snap)
            metricRow(snap)
            actionsRow
            HStack {
                ComplianceInlineChip(tag: .eDvir)
                Spacer()
            }
        }
        .padding(Space.s5)
    }

    // MARK: Confirm strip

    private func confirmStrip(_ snap: DvirSubmittedReviewStore.Snapshot) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(palette.success).frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                (Text("Dispatcher notified. ").bold() + Text("Load held until cleared."))
                    .font(EType.body).foregroundStyle(palette.textPrimary)
            }
            Spacer()
            Text(snap.confirmRelative)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(palette.tintSuccess)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .combine)
    }

    // MARK: OOS card — defect identity, classification, FMCSA reference

    private func oosCard(_ snap: DvirSubmittedReviewStore.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center) {
                Text(snap.severityBadge.uppercased())
                    .font(EType.mono(.micro))
                    .tracking(0.8)
                    .foregroundStyle(snap.severityColor(palette))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(snap.severityTint(palette))
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                Spacer()
                Text(snap.unitTrimDisplay)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s3, verticalSpacing: 6) {
                GridRow {
                    defLabel("System")
                    defValue(snap.systemDisplay)
                }
                GridRow {
                    defLabel("Finding")
                    Text(snap.findingDisplay)
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                GridRow {
                    defLabel("Classification")
                    Text(snap.classificationDisplay)
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(snap.severityColor(palette))
                }
                GridRow {
                    defLabel("Reported")
                    Text(snap.reportedDisplay)
                        .font(EType.mono(.body))
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func defLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(EType.micro).tracking(0.6)
            .foregroundStyle(palette.textTertiary)
    }
    @ViewBuilder
    private func defValue(_ s: String) -> some View {
        Text(s).font(EType.body).fontWeight(.semibold).foregroundStyle(palette.textPrimary)
    }

    // MARK: Shop timeline — until backend ships repair-orders this is a
    // single neutral row that documents we're waiting for the
    // dispatcher's assignment. No fabricated tech name / ETA.

    private func shopTimeline(_ snap: DvirSubmittedReviewStore.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Repair coordination")
                    .font(EType.body).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("Awaiting dispatcher")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                        .frame(width: 32, height: 32)
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Repair order pending assignment")
                        .font(EType.body).fontWeight(.medium)
                        .foregroundStyle(palette.textPrimary)
                    Text("Dispatch will route a tech once accepted.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button {
                    openMessages?(nil)
                } label: {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(palette.bgElev)
                        .overlay(Circle().strokeBorder(palette.borderSoft))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Open dispatcher messaging")
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Dispatcher strip — opens messaging on tap. The dispatcher
    // identity is sourced from the active load when it lands. Until
    // then we render the role-level "Dispatch · open thread" affordance.

    private func dispatcherStrip(_ snap: DvirSubmittedReviewStore.Snapshot) -> some View {
        Button {
            openMessages?(nil)
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                // Doctrine §2.1: gradient on identity tile.
                ZStack {
                    Circle().fill(palette.tintInfo)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(palette.borderSoft))
                    Image(systemName: "headphones")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                VStack(alignment: .leading, spacing: 2) {
                    (Text("Dispatch").bold().foregroundColor(palette.textPrimary) +
                     Text(" · open thread").foregroundColor(palette.textSecondary))
                        .font(EType.caption)
                    Text(snap.dispatchPromptCopy)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(.system(size: 11))
                        Text("Reply".uppercased())
                            .font(EType.caption).tracking(0.4)
                    }
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(palette.bgElev)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .eusoCard(radius: Radius.lg)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open dispatcher conversation")
    }

    // MARK: Metric row — backend-derived

    private func metricRow(_ snap: DvirSubmittedReviewStore.Snapshot) -> some View {
        HStack(spacing: Space.s3) {
            MetricTile(label: "Load status", value: snap.loadStatusLabel)
            MetricTile(label: "Overall condition", value: snap.overallConditionLabel)
        }
    }

    // MARK: Actions row — both buttons are real handlers

    private var actionsRow: some View {
        HStack(spacing: Space.s2) {
            LifecycleCTAButton(title: "Track repair status")
                .accessibilityLabel("Track repair status")
            Button { advance?() } label: {
                Text("Continue pre-trip")
                    .font(EType.body).fontWeight(.medium)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .accessibilityLabel("Continue pre-trip on remaining sections")
        }
    }
}

// MARK: - Snapshot accessors — display-side derivation only.
//
// These keep the view body free of formatting/branching and let the
// store stay a pure data shape. All optionals fall back to neutral
// "—" so the layout never collapses on partial hydration.

extension DvirSubmittedReviewStore.Snapshot {

    var unitDisplay: String {
        if let unit = dvir?.unitNumber, !unit.isEmpty { return "Unit \(unit)" }
        if let vId = defect?.vehicleId, !vId.isEmpty { return "Unit \(vId)" }
        return "—"
    }

    /// "Freightliner Cascadia '24" trim line — only render when the
    /// backend supplied make+model. Otherwise we show just the unit.
    var unitTrimDisplay: String {
        var bits: [String] = []
        if let unit = dvir?.unitNumber, !unit.isEmpty {
            bits.append("Unit \(unit)")
        }
        if let make = dvir?.make, let model = dvir?.model,
           !make.isEmpty, !model.isEmpty {
            bits.append("\(make) \(model)")
        }
        return bits.isEmpty ? unitDisplay : bits.joined(separator: " · ")
    }

    var submittedDisplay: String {
        guard let raw = dvir?.reportDate ?? defect?.reportedAt, !raw.isEmpty
        else { return "—" }
        // Server returns ISO-8601 — surface the time portion when we
        // can parse it, else the raw prefix.
        if let date = ISO8601DateFormatter().date(from: raw) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f.string(from: date)
        }
        return String(raw.prefix(16))
    }

    /// Relative time chip ("+47s", "+12m") — kept simple. Falls back
    /// to "now" when we can't parse the timestamp.
    var confirmRelative: String {
        guard let raw = defect?.reportedAt ?? dvir?.reportDate,
              let date = ISO8601DateFormatter().date(from: raw) else { return "now" }
        let secs = max(0, Int(Date().timeIntervalSince(date)))
        if secs < 60 { return "+\(secs)s" }
        let mins = secs / 60
        if mins < 60 { return "+\(mins)m" }
        let hrs = mins / 60
        return "+\(hrs)h"
    }

    /// SEVERITY badge label — derived from the defect severity field
    /// (server canonical: "minor" | "major" | "out_of_service").
    var severityBadge: String {
        switch (defect?.severity ?? "").lowercased() {
        case "out_of_service": return "Out of service"
        case "major":          return "Major defect"
        case "minor":          return "Minor defect"
        default:               return "Defect submitted"
        }
    }

    func severityColor(_ palette: Theme.Palette) -> Color {
        switch (defect?.severity ?? "").lowercased() {
        case "out_of_service", "major": return palette.danger
        case "minor":                   return palette.warning
        default:                        return palette.textPrimary
        }
    }

    func severityTint(_ palette: Theme.Palette) -> Color {
        switch (defect?.severity ?? "").lowercased() {
        case "out_of_service", "major": return palette.tintDanger
        case "minor":                   return palette.tintWarning
        default:                        return palette.tintNeutral
        }
    }

    var systemDisplay: String {
        if let cat = defect?.category, !cat.isEmpty { return cat }
        return "—"
    }

    var findingDisplay: String {
        if let item = defect?.item, let desc = defect?.description,
           !item.isEmpty, !desc.isEmpty {
            return "\(item) · \(desc)"
        }
        if let desc = defect?.description, !desc.isEmpty { return desc }
        if let item = defect?.item, !item.isEmpty { return item }
        return "—"
    }

    /// FMCSA-style classification line. Until the backend exposes a
    /// regulatory citation per defect, we surface the severity word
    /// + reportType so the dispatcher row reads truthfully.
    var classificationDisplay: String {
        let sev = (defect?.severity ?? "").uppercased().replacingOccurrences(of: "_", with: " ")
        let report = dvir?.reportType?.uppercased().replacingOccurrences(of: "_", with: " ") ?? ""
        let parts = [sev.isEmpty ? nil : sev, report.isEmpty ? nil : report]
            .compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    var reportedDisplay: String {
        guard let raw = defect?.reportedAt ?? dvir?.reportDate, !raw.isEmpty
        else { return "—" }
        if let date = ISO8601DateFormatter().date(from: raw) {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return f.string(from: date)
        }
        return String(raw.prefix(19))
    }

    /// Drives the "Load held" metric — when the defect is OOS the
    /// load is held; otherwise it's flagged for review.
    var loadStatusLabel: String {
        switch (defect?.severity ?? "").lowercased() {
        case "out_of_service": return "Held · awaiting clear"
        case "major":          return "Flagged · review"
        case "minor":          return "Cleared to dispatch"
        default:               return "Submitted"
        }
    }

    var overallConditionLabel: String {
        guard let raw = dvir?.overallCondition, !raw.isEmpty else { return "—" }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Dispatcher prompt — driven by load id when present, generic
    /// otherwise. No fabricated dispatcher name.
    var dispatchPromptCopy: String {
        if let dvirId = dvir?.id {
            return "DVIR #\(dvirId) is open. Tap to follow up with dispatch."
        }
        return "Tap to open the dispatcher thread for this submission."
    }
}

// MARK: - Wrapper

struct DvirSubmittedScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DvirSubmitted(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_012(),
                      trailing: driverNavTrailing_012(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_012() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: true),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: false)]
}
private func driverNavTrailing_012() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

// MARK: - Previews (doctrine §12.10 + §12.11: both themes, both rendered)

#Preview("012 · DVIR Submitted · Dark") {
    DvirSubmittedScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("012 · DVIR Submitted · Light") {
    DvirSubmittedScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
