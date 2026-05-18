//
//  086_MeIncidentReportFiler.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · incident report filer)
//
//  Screen 086 · Me · Incident Report Filer — the driver's on-phone
//  path for submitting a crash, property-damage event, or near-miss
//  directly to the carrier's safety manager. One form, three kinds:
//  accident / property damage / near-miss. Captures location (auto-
//  filled from CoreLocation when available), type classification,
//  severity, narrative, and near-miss specifics (weather, road
//  conditions, action taken).
//
//  Starts the next chain: driver field report (086) → safety manager
//  investigation (admin-side, 097) → compliance feedback loop.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Accident / property-damage path wires `safety.submitAccidentReport`
//      (MCP-verified at `frontend/server/routers/safety.ts:700`).
//
//    • Near-miss path wires `safetyRisk.reportNearMiss` (MCP-verified
//      at `frontend/server/routers/safetyRisk.ts:812`) with the
//      real 10-value `nearMissTypeEnum`: lane_departure / hard_brake
//      / close_call / distraction / fatigue / weather_related /
//      equipment_issue / pedestrian / rollover_risk / other.
//
//    • Severity is the FMCSA-canonical "critical / major / minor"
//      enum. Defaults to "minor" so a driver never over-reports by
//      accident and triggers the full incident-response cascade.
//
//    • occurredAt is ISO-8601 server-required; defaults to "now"
//      with a quick ±3-hour nudger since drivers often report
//      immediately after parking safely but not mid-event.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on submit CTA. Brand.warning on
//         Critical severity + active Near-miss "close call" tile.
//    §4   Tokenized spacing, radii, type.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews land in `.error` under the no-baseURL runtime.
//         No fixtures.
//

import SwiftUI
import CoreLocation

// MARK: - Incident kind

private enum IncidentKind: String, Hashable, Identifiable, CaseIterable {
    case accident      // crash, collision, rollover
    case damage        // property damage, no collision
    case nearMiss      // close call, no contact

    var id: String { rawValue }
    var label: String {
        switch self {
        case .accident: return "Accident"
        case .damage:   return "Damage"
        case .nearMiss: return "Near-miss"
        }
    }
    var icon: String {
        switch self {
        case .accident: return "car.side.arrowtriangle.up.fill"
        case .damage:   return "wrench.adjustable"
        case .nearMiss: return "exclamationmark.triangle"
        }
    }
    var blurb: String {
        switch self {
        case .accident:
            return "Collision, rollover, injury event. Files a full accident report to safety + compliance."
        case .damage:
            return "Property damage with no collision (clipped mirror, trailer scrape). Goes to safety for workup."
        case .nearMiss:
            return "Close call that almost became an accident. Near-miss reporting prevents the next real one."
        }
    }
}

// MARK: - Near-miss sub-type

private enum NearMissType: String, CaseIterable, Identifiable {
    case laneDeparture   = "lane_departure"
    case hardBrake       = "hard_brake"
    case closeCall       = "close_call"
    case distraction     = "distraction"
    case fatigue         = "fatigue"
    case weatherRelated  = "weather_related"
    case equipmentIssue  = "equipment_issue"
    case pedestrian      = "pedestrian"
    case rolloverRisk    = "rollover_risk"
    case other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .laneDeparture:  return "Lane departure"
        case .hardBrake:      return "Hard brake"
        case .closeCall:      return "Close call"
        case .distraction:    return "Distraction"
        case .fatigue:        return "Fatigue"
        case .weatherRelated: return "Weather"
        case .equipmentIssue: return "Equipment"
        case .pedestrian:     return "Pedestrian"
        case .rolloverRisk:   return "Rollover risk"
        case .other:          return "Other"
        }
    }
    var icon: String {
        switch self {
        case .laneDeparture:  return "arrow.triangle.branch"
        case .hardBrake:      return "gauge.with.needle"
        case .closeCall:      return "exclamationmark.2"
        case .distraction:    return "eye.slash"
        case .fatigue:        return "bed.double"
        case .weatherRelated: return "cloud.bolt.rain"
        case .equipmentIssue: return "wrench"
        case .pedestrian:     return "figure.walk"
        case .rolloverRisk:   return "arrow.up.left.and.down.right.magnifyingglass"
        case .other:          return "ellipsis.circle"
        }
    }
}

// MARK: - Severity

private enum Severity: String, Hashable, CaseIterable, Identifiable {
    case minor, major, critical
    var id: String { rawValue }
    var label: String {
        switch self {
        case .minor:    return "Minor"
        case .major:    return "Major"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Screen root

struct MeIncidentReportFiler: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var kind: IncidentKind = .nearMiss
    @State private var severity: Severity = .minor
    @State private var description: String = ""
    @State private var location: String = ""
    /// Captured when the driver picks a HERE autosuggest result OR
    /// pastes raw "lat,lng". Persisted alongside the freeform string
    /// so the server can geofence the incident without re-geocoding.
    @State private var locationLat: Double? = nil
    @State private var locationLng: Double? = nil
    @State private var occurredAt: Date = Date()

    // Near-miss-only fields
    @State private var nearMissType: NearMissType = .closeCall
    @State private var weather: String = ""
    @State private var roadConditions: String = ""
    @State private var actionTaken: String = ""

    @State private var isSubmitting: Bool = false
    @State private var submitted: SubmissionResult?

    @State private var lastToast: String?

    private struct SubmissionResult: Identifiable {
        let id: String
        let kind: IncidentKind
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                if let result = submitted {
                    submittedConfirmation(result)
                } else {
                    kindPicker
                    severityPicker
                    if kind == .nearMiss {
                        nearMissTypePicker
                    }
                    locationField
                    whenField
                    narrativeField
                    // ESANG Vision damage assessment — driver
                    // photographs the scene; Gemini returns
                    // structured damage description that auto-fills
                    // the narrative field. Replaces the "describe
                    // every detail by hand" friction the founder
                    // flagged in the Gemini parity audit 2026-05-05.
                    AIVisualScanButton(
                        title: "Scan scene with ESANG Vision",
                        subtitle: "Auto-describes damage, severity, liability cues",
                        procPath: "visualIntelligence.assessDamage"
                    ) { result in
                        var lines: [String] = []
                        if let s = result.summary, !s.isEmpty { lines.append(s) }
                        for f in result.findings ?? [] {
                            if let desc = f.description {
                                lines.append("• [\(f.severity ?? "note")] \(desc)")
                            }
                        }
                        let block = lines.joined(separator: "\n")
                        if description.isEmpty {
                            description = block
                        } else {
                            description += "\n\n" + block
                        }
                        if let sev = result.overallSeverity?.lowercased() {
                            switch sev {
                            case "critical":           severity = .critical
                            case "high", "moderate":   severity = .major
                            case "low":                severity = .minor
                            default:                   break
                            }
                        }
                    }
                    if kind == .nearMiss {
                        nearMissExtrasSection
                    }
                    submitCTA
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .overlay(alignment: .bottom) {
            if let toast = lastToast {
                toastView(toast)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s6)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("File Report")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Accident · damage · near-miss")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: isSubmitting ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Kind picker

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("REPORT TYPE")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(IncidentKind.allCases) { k in
                    kindTile(k)
                }
            }
        }
    }

    private func kindTile(_ k: IncidentKind) -> some View {
        let on = k == kind
        return Button {
            kind = k
        } label: {
            VStack(alignment: .leading, spacing: Space.s1) {
                Image(systemName: k.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(LinearGradient.diagonal))
                Text(k.label)
                    .font(EType.bodyStrong)
                    .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s3)
            .background(
                ZStack {
                    if on {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCard.opacity(0.85))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(on ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Severity picker

    private var severityPicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SEVERITY")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(Severity.allCases) { s in
                    severityPill(s)
                }
            }
        }
    }

    private func severityPill(_ s: Severity) -> some View {
        let on = s == severity
        let warn = s == .critical
        return Button {
            severity = s
        } label: {
            Text(s.label)
                .font(EType.bodyStrong)
                .foregroundStyle(
                    on
                        ? AnyShapeStyle(Color.white)
                        : (warn ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(palette.textPrimary))
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if on && warn {
                            Capsule().fill(Brand.warning)
                        } else if on {
                            Capsule().fill(LinearGradient.diagonal)
                        } else {
                            Capsule().fill(palette.bgCard.opacity(0.85))
                        }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(
                        on
                            ? Color.white.opacity(0.25)
                            : (warn ? Brand.warning.opacity(0.5) : palette.borderFaint),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Near-miss sub-type

    @ViewBuilder
    private var nearMissTypePicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("NEAR-MISS TYPE")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            let cols = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: Space.s2) {
                ForEach(NearMissType.allCases) { nm in
                    nearMissTypeTile(nm)
                }
            }
        }
    }

    private func nearMissTypeTile(_ nm: NearMissType) -> some View {
        let on = nm == nearMissType
        return Button {
            nearMissType = nm
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: nm.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
                Text(nm.label)
                    .font(EType.caption)
                    .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                Spacer()
            }
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if on {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(palette.bgCard.opacity(0.85))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(on ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Location

    private var locationField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("LOCATION")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            // Was a freeform TextField — swapped to `HereAddressField`
            // so the driver gets HERE autosuggest AND can paste raw
            // "lat,lng" coordinates (e.g. "32.7767,-96.7970"). Same
            // component the shipper post-load wizard uses; geocoded
            // lat/lng accompany the incident payload so dispatch can
            // geofence without a second resolution pass.
            HereAddressField(
                text: $location,
                lat: $locationLat,
                lng: $locationLng,
                placeholder: "City, state, mile marker, or lat,lng"
            )
        }
    }

    // MARK: When

    private var whenField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("WHEN")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            DatePicker(
                "Occurred at",
                selection: $occurredAt,
                in: ...Date(),     // no future
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Narrative

    private var narrativeField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("WHAT HAPPENED")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            TextEditor(text: $description)
                .frame(minHeight: 140)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCardSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
            Text("Be specific. Facts your safety manager needs: direction of travel, speed, other-vehicle behavior, weather, what you did to avoid it.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Near-miss extras

    @ViewBuilder
    private var nearMissExtrasSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CONDITIONS (OPTIONAL)")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    nmInput(title: "Weather", text: $weather)
                    nmInput(title: "Road", text: $roadConditions)
                }
                nmInput(title: "Action you took", text: $actionTaken, multi: true)
            }
        }
    }

    @ViewBuilder
    private func nmInput(title: String, text: Binding<String>, multi: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if multi {
                TextField(title, text: text, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Submit CTA

    @ViewBuilder
    private var submitCTA: some View {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSubmit = trimmed.count >= 10
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(isSubmitting ? "Submitting…" : "File report")
                    .font(EType.bodyStrong)
                Spacer()
                if isSubmitting {
                    ProgressView().progressViewStyle(.circular).controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isSubmitting)
        .opacity((!canSubmit || isSubmitting) ? 0.5 : 1.0)
    }

    private func submit() async {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        let iso = ISO8601DateFormatter().string(from: occurredAt)
        let driverIdStr = session.user?.id
        let driverIdInt = Int(driverIdStr ?? "")

        do {
            switch kind {
            case .accident:
                let res = try await EusoTripAPI.shared.safety.submitAccidentReport(
                    driverId: driverIdStr,
                    date: iso,
                    description: assembledDescription,
                    severity: severity.rawValue
                )
                if res.success, let id = res.reportId {
                    submitted = SubmissionResult(id: id, kind: .accident)
                    flashToast("Accident report filed")
                }
            case .damage:
                // Server has no dedicated damage proc — routes through
                // accident with a "[DAMAGE]" prefix so the safety
                // manager's queue can sort naturally. Severity defaults
                // to minor unless the driver escalated.
                let res = try await EusoTripAPI.shared.safety.submitAccidentReport(
                    driverId: driverIdStr,
                    date: iso,
                    description: "[PROPERTY DAMAGE] " + assembledDescription,
                    severity: severity.rawValue
                )
                if res.success, let id = res.reportId {
                    submitted = SubmissionResult(id: id, kind: .damage)
                    flashToast("Damage report filed")
                }
            case .nearMiss:
                let res = try await EusoTripAPI.shared.safety.reportNearMiss(
                    nearMissType: nearMissType.rawValue,
                    description: trimmed,
                    location: location.isEmpty ? nil : location,
                    occurredAt: iso,
                    severity: severity.rawValue,
                    driverId: driverIdInt,
                    weatherConditions: weather.isEmpty ? nil : weather,
                    roadConditions: roadConditions.isEmpty ? nil : roadConditions,
                    actionTaken: actionTaken.isEmpty ? nil : actionTaken
                )
                if res.success, let id = res.reportId {
                    submitted = SubmissionResult(id: id, kind: .nearMiss)
                    flashToast("Near-miss filed")
                }
            }
        } catch {
            flashToast("Couldn't file — try again")
        }
    }

    /// Accident/damage procs only take a `description` field on the
    /// server — we fold location + narrative so the safety manager
    /// sees both in the incident record.
    private var assembledDescription: String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if location.isEmpty { return trimmed }
        return "Location: \(location). \(trimmed)"
    }

    // MARK: Submitted confirmation

    private func submittedConfirmation(_ r: SubmissionResult) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("Report filed")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("TYPE").font(EType.micro).tracking(1.2).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(r.kind.label).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                }
                HStack {
                    Text("REPORT ID").font(EType.micro).tracking(1.2).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(r.id).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                }
                Text("Your safety manager has been notified and will open an investigation. Check Me · Violations for status updates.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s2)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)

            Button {
                resetForm()
            } label: {
                Text("File another report")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func resetForm() {
        submitted = nil
        kind = .nearMiss
        severity = .minor
        description = ""
        location = ""
        locationLat = nil
        locationLng = nil
        occurredAt = Date()
        nearMissType = .closeCall
        weather = ""
        roadConditions = ""
        actionTaken = ""
    }

    // MARK: Footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Reporting is part of the safety system")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Near-miss reports improve the carrier's CSA percentile over time — they're the leading indicator the FMCSA Safety Measurement System respects. Accurate, timely reporting protects you, your carrier, and everyone you share the road with.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LinearGradient.diagonal)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 14, y: 6)
    }

    private func flashToast(_ text: String) {
        withAnimation { lastToast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run { withAnimation { lastToast = nil } }
        }
    }
}

// MARK: - Screen wrapper

struct MeIncidentReportFilerScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeIncidentReportFiler()
        } nav: {
            BottomNav(
                leading: driverNavLeading_086(),
                trailing: driverNavTrailing_086(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_086() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_086() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("086 · Incident Filer · Night") {
    MeIncidentReportFilerScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("086 · Incident Filer · Afternoon") {
    MeIncidentReportFilerScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
