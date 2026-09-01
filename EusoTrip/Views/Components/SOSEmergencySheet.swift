//
//  SOSEmergencySheet.swift
//  EusoTrip — Driver emergency triage sheet. Presented from the active-trip
//  surface on the Trips tab when the driver hits the SOS button.
//
//  WEB PARITY (authoritative source — see
//  `eusoronetechnologiesinc/frontend/client/src/pages/ActiveTrip.tsx:40-177`):
//
//    const SOS_TYPES = [
//      { type: "medical",      label: "Medical",      desc: "Medical emergency" },
//      { type: "accident",     label: "Accident",     desc: "Vehicle collision" },
//      { type: "mechanical",   label: "Breakdown",    desc: "Mechanical failure" },
//      { type: "hazmat_spill", label: "Hazmat Spill", desc: "Chemical spill/leak" },
//      { type: "threat",       label: "Threat",       desc: "Security threat" },
//      { type: "weather",      label: "Weather",      desc: "Severe weather" },
//      { type: "other",        label: "Other",        desc: "Other emergency" },
//    ];
//
//  Server-side wiring (both iOS and web must hit the same procedures so a
//  driver signed in on either device sees the same data):
//
//    • `trpc.interstate.createSOS`
//      (`eusoronetechnologiesinc/frontend/server/routers/interstate.ts:262`)
//      Input: { loadId, alertType, severity, latitude, longitude,
//               description?, stateCode? }
//      Returns: { sosId, notifiedCount }
//      Side effects: inserts `sosAlerts`, WS-broadcasts to shipper,
//      catalyst, driver, and role rooms (dispatch / admin /
//      super_admin / safety_manager / compliance / catalyst / shipper
//      / broker). LIFE-SAFETY FANOUT. Does NOT page a mechanic.
//
//    • `trpc.zeunMechanics.reportBreakdown`
//      (`eusoronetechnologiesinc/frontend/server/routers/zeunMechanics.ts:237`)
//      Input: { vehicleId|vehicleVin, issueCategory, severity,
//               symptoms[], canDrive, latitude, longitude, loadId?,
//               faultCodes?, driverNotes?, photos?, videos?, telemetry… }
//      Creates `zeunBreakdownReports` row + runs ESANG-AI diagnosis +
//      matches `zeunRepairProviders`. This is what populates the
//      ZeunFleetDashboard mechanic queue.
//
//  FLOW (exactly mirrors the web — clean separation of concerns):
//
//    1. Driver taps SOS → picks emergency type → submit.
//    2. We fire `interstate.createSOS` ONLY. Single-tap life-safety
//       broadcast, minimum fields (loadId, alertType, severity, lat,
//       lng, optional description). Dispatch + admin + safety hear it
//       within a websocket round-trip.
//    3. If the type was `mechanical`, after the broadcast lands we
//       hand the driver to the Zeun breakdown screen so they can file
//       the detailed report (VIN, faultCodes, symptoms, canDrive,
//       photos, telemetry) at their own pace. THAT is the call that
//       actually lands the ticket in the Zeun mechanic queue and
//       triggers ESANG-AI diagnosis + provider matching. For all
//       other emergency types we just dismiss.
//
//  Why two procedures, not one fat call: SOS must go out instantly
//  with zero friction in the moment that matters most. The detailed
//  mechanic report needs context that takes time (VIN lookup, fault-
//  code reading, photos) — making it a follow-up step keeps the
//  life-safety broadcast unblocked.
//
//  Live network wiring is in: `submit()` resolves the loadId from the
//  active trip, validates manual coordinates before falling back to a
//  device fix, and calls the real `interstate.createSOS` mutation. On
//  success it dismisses (and routes mechanical types to the Zeun
//  breakdown screen via `onOpenZeun`); on failure it surfaces a
//  user-facing retry alert rather than silently swallowing the throw.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

struct SOSEmergencySheet: View {

    // MARK: - Emergency taxonomy (mirrors web `SOS_TYPES`)

    /// Raw values match the server-side `alertType` enum accepted by
    /// `interstate.createSOS`. Keep these in lockstep with
    /// `ActiveTrip.tsx:SOS_TYPES` — any change must ship in both places.
    enum Emergency: String, CaseIterable, Identifiable {
        case medical     = "medical"
        case accident    = "accident"
        case mechanical  = "mechanical"
        case hazmatSpill = "hazmat_spill"
        case threat      = "threat"
        case weather     = "weather"
        case other       = "other"
        var id: String { rawValue }

        var title: String {
            switch self {
            case .medical:     return "Medical"
            case .accident:    return "Accident"
            case .mechanical:  return "Breakdown"
            case .hazmatSpill: return "Hazmat Spill"
            case .threat:      return "Threat"
            case .weather:     return "Weather"
            case .other:       return "Other"
            }
        }

        var glyph: String {
            switch self {
            case .medical:     return "cross.case.fill"
            case .accident:    return "car.fill"
            case .mechanical:  return "wrench.and.screwdriver"
            case .hazmatSpill: return "flame.fill"
            case .threat:      return "exclamationmark.shield.fill"
            case .weather:     return "cloud.bolt.rain.fill"
            case .other:       return "ellipsis.circle"
            }
        }

        /// Short descriptor — mirrors the `desc` field in `SOS_TYPES`.
        var subtitle: String {
            switch self {
            case .medical:     return "Medical emergency"
            case .accident:    return "Vehicle collision"
            case .mechanical:  return "Mechanical failure"
            case .hazmatSpill: return "Chemical spill / leak"
            case .threat:      return "Security threat"
            case .weather:     return "Severe weather"
            case .other:       return "Other emergency"
            }
        }

        /// Matches the web's auto-severity rule at
        /// `ActiveTrip.tsx:76`. Medical / accident / hazmat-spill always
        /// ride at `critical`; everything else defaults to `high`.
        var defaultSeverity: Severity {
            switch self {
            case .medical, .accident, .hazmatSpill: return .critical
            default:                                 return .high
            }
        }
    }

    /// Mirrors the `severityEnum` on the server. Kept separate from the
    /// emergency type so a driver can escalate / de-escalate if the
    /// auto-default doesn't fit (e.g., a minor fender-bump → `high`).
    enum Severity: String, CaseIterable, Identifiable {
        case low, medium, high, critical
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    // MARK: - Environment + state

    @Environment(\.palette)     private var palette
    @Environment(\.dismiss)     private var dismiss
    @EnvironmentObject private var trip: DriverTripController

    /// Injected by the caller — invoked AFTER `interstate.createSOS`
    /// lands successfully and only when the emergency type was
    /// `.mechanical`. The parent dismisses this sheet and deep-links
    /// the driver into the Loads tab → ZEUN Mechanics breakdown screen
    /// so they can file the detailed `zeunMechanics.reportBreakdown`
    /// follow-up (VIN, fault codes, symptoms, telemetry, photos).
    let onOpenZeun: (() -> Void)?

    @State private var selected: Emergency? = nil
    @State private var severity: Severity = .high
    @State private var notes: String = ""
    @State private var locationContext: String = ""
    @State private var locationInputError: String? = nil
    @State private var submitting: Bool = false
    @State private var idempotencyKey: String = UUID().uuidString

    /// User-facing failure surface. SOS is life-safety — if the
    /// `interstate.createSOS` broadcast fails to land we MUST tell the
    /// driver (so they can retry, or fall back to a 911 voice call)
    /// rather than silently dismissing as if dispatch had heard them.
    @State private var submitError: String? = nil
    private var showError: Binding<Bool> {
        Binding(get: { submitError != nil }, set: { if !$0 { submitError = nil } })
    }

    init(onOpenZeun: (() -> Void)? = nil) {
        self.onOpenZeun = onOpenZeun
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    subhead
                    emergencyGrid
                    if selected != nil {
                        severityPicker
                        locationField
                        notesField
                        submitButton
                        if selected == .mechanical {
                            zeunHandoffNote
                        }
                    }
                    callHelpRow
                    Color.clear.frame(height: Space.s5)
                }
                .padding(Space.s5)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage)
        .onChange(of: selected) { _, newValue in
            // Re-sync severity to the web's auto-default when the driver
            // switches tiles. The driver can still manually override via
            // the severity picker afterwards.
            if let newValue { severity = newValue.defaultSeverity }
        }
        // Uniform cafe-door entrance.
        .screenTileRoot()
        // Life-safety failure surface — never silently swallow a failed
        // SOS broadcast. If `interstate.createSOS` throws, the sheet
        // stays open and the driver gets an actionable alert so they can
        // retry or escalate to a 911 voice call.
        .alert("Couldn't send SOS", isPresented: showError) {
            Button("Retry") { submit() }
            Button("Dismiss", role: .cancel) { submitError = nil }
        } message: {
            Text(submitError ?? "We couldn't reach dispatch. Call 911 if this is life-threatening, then try again.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SOS · Emergency")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH + SAFETY WILL BE NOTIFIED")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel SOS")
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    private var subhead: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("Pick what's happening")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
    }

    // MARK: Emergency picker grid (2 columns)

    private var emergencyGrid: some View {
        let cols = [GridItem(.flexible(), spacing: Space.s2),
                    GridItem(.flexible(), spacing: Space.s2)]
        return LazyVGrid(columns: cols, spacing: Space.s2) {
            ForEach(Emergency.allCases) { e in
                emergencyTile(e)
            }
        }
    }

    @ViewBuilder
    private func emergencyTile(_ e: Emergency) -> some View {
        let active = selected == e
        Button {
            withAnimation(.easeOut(duration: 0.18)) { selected = e }
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(active
                              ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(palette.bgCardSoft))
                    Image(systemName: e.glyph)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(active ? .white : palette.textPrimary)
                }
                .frame(width: 40, height: 40)

                Text(e.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(e.subtitle)
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        active
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Brand.blue, Brand.magenta],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            : AnyShapeStyle(palette.borderFaint),
                        lineWidth: active ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(e.title) - \(e.subtitle)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: Severity picker

    /// 4-segment severity pill — low / medium / high / critical.
    /// Default is set automatically by `selected.defaultSeverity` to
    /// match the web's auto-escalation rule, but the driver can override.
    private var severityPicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SEVERITY")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                ForEach(Severity.allCases) { s in
                    let active = severity == s
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { severity = s }
                    } label: {
                        Text(s.title.uppercased())
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(active ? .white : palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                Group {
                                    if active {
                                        RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                            .fill(severityTint(s))
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .fill(palette.bgCardSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
        }
    }

    private func severityTint(_ s: Severity) -> LinearGradient {
        switch s {
        case .low:
            return LinearGradient(colors: [Brand.success, Brand.success.opacity(0.78)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .medium:
            return LinearGradient(colors: [Color(red: 0.98, green: 0.65, blue: 0.20),
                                           Color(red: 0.95, green: 0.45, blue: 0.18)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .high:
            return LinearGradient(colors: [Color(red: 0.95, green: 0.35, blue: 0.22),
                                           Color(red: 0.88, green: 0.18, blue: 0.30)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        case .critical:
            return LinearGradient(colors: [Color(red: 0.95, green: 0.20, blue: 0.25),
                                           Color(red: 0.60, green: 0.05, blue: 0.55)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Notes field

    private var locationField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Location · optional")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            TextField("Address, landmark, or coordinates", text: $locationContext)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .padding(Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(locationInputError == nil ? palette.borderFaint : Brand.danger)
                )
                .accessibilityLabel("Emergency location context")
                .accessibilityHint("Enter an address, landmark, or a latitude and longitude pair.")
                .onChange(of: locationContext) { _, _ in
                    locationInputError = nil
                }
            if let locationInputError {
                Label(locationInputError, systemImage: "exclamationmark.triangle.fill")
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Location error. \(locationInputError)")
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ADDITIONAL DETAILS · OPTIONAL")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            TextEditor(text: $notes)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(Space.s3)
                .frame(minHeight: 96)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
        }
    }

    // MARK: Submit button

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: Space.s2) {
                if submitting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(submittingLabel)
                    .font(EType.bodyStrong)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.20, blue: 0.25),
                                Color(red: 0.76, green: 0.05, blue: 0.40)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.95, green: 0.20, blue: 0.25).opacity(0.40),
                    radius: 18, y: 6)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(submitting)
        .accessibilityLabel("Send SOS alert")
    }

    /// Human-readable submit label. Same wording regardless of type —
    /// SOS is always a broadcast-only action (the Zeun follow-up is a
    /// separate step, triggered after the broadcast lands).
    private var submittingLabel: String {
        submitting ? "Sending alert…" : "Send SOS alert"
    }

    /// Fires the SOS broadcast (web parity: `interstate.createSOS`
    /// only). On success, if the selected type was `mechanical`,
    /// dismisses and hands off to the Zeun breakdown screen so the
    /// driver can file the detailed `zeunMechanics.reportBreakdown`
    /// follow-up (VIN, fault codes, symptoms, telemetry, photos). For
    /// all other types we just dismiss — dispatch + safety + admin have
    /// already been notified by the broadcast.
    ///
    /// LIVE WIRING (no longer a mock): resolves the loadId from the
    /// active trip, validates any manual coordinate before using the
    /// device fix, maps the selected tile + severity to the server enums, and calls
    /// `EusoTripAPI.shared.interState.createSOS(...)`. The throw is
    /// surfaced — never swallowed — because a failed SOS is a
    /// life-safety event the driver must know about.
    private func submit() {
        guard let sel = selected else { return }
        // We must have an active load to anchor the SOS to — the server
        // keys the dispatch/role fanout off `loadId`. The button is only
        // reachable from the active-trip surface, but guard honestly.
        guard let loadId = trip.currentLoad?.id else {
            submitError = "No active load is bound to this trip yet. Reopen your active load, then send the SOS — or call 911 directly if this is life-threatening."
            return
        }

        let wasMechanical = sel == .mechanical
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = locationContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let manualLocation = LatLongParser.parseDetailed(trimmedLocation)
        if !trimmedLocation.isEmpty,
           manualLocation == nil,
           LatLongParser.hasCoordinateIntent(trimmedLocation) {
            locationInputError = "That coordinate is invalid or out of range. Correct it or clear the optional location field; your entry has not been changed."
            return
        }
        locationInputError = nil
        // `originState` is the closest honest state hint on the load.
        // The server treats `stateCode` as optional, so nil is fine when
        // the load row doesn't carry one.
        let stateCode = trip.currentLoad?.originState

        submitting = true
        submitError = nil

        Task { @MainActor in
            // A valid manual pair is authoritative and avoids waiting for GPS.
            // HERE receives the verbatim hint only for post-commit enrichment;
            // it never replaces or gates these exact coordinates.
            let deviceLocation: CLLocation?
            if manualLocation == nil {
                deviceLocation = await DriverLocationResolver.shared.currentLocation()
            } else {
                deviceLocation = nil
            }
            let deviceCoordinate = LatLongParser.validatedCoordinate(
                latitude: deviceLocation?.coordinate.latitude,
                longitude: deviceLocation?.coordinate.longitude
            )
            let manualCoordinate = manualLocation?.coordinate
            let submittedCoordinate = manualCoordinate ?? deviceCoordinate
            let locationSource = manualCoordinate == nil
                ? (deviceCoordinate == nil ? "not_recorded" : "device")
                : "manual_coordinates"
            let accuracy = manualCoordinate == nil && deviceCoordinate != nil
                && (0...100_000).contains(deviceLocation?.horizontalAccuracy ?? -1)
                ? deviceLocation?.horizontalAccuracy
                : nil
            let capturedAt = manualCoordinate == nil
                ? (deviceCoordinate == nil ? nil : deviceLocation?.timestamp)
                : Date()

            do {
                _ = try await EusoTripAPI.shared.interState.createSOS(
                    loadId: loadId,
                    alertType: sel.rawValue,          // matches server alertType enum
                    severity: severity.rawValue,      // low | medium | high | critical
                    latitude: submittedCoordinate?.latitude,
                    longitude: submittedCoordinate?.longitude,
                    locationSource: locationSource,
                    locationAccuracyMeters: accuracy,
                    locationCapturedAt: capturedAt,
                    addressHint: manualLocation?.originalText
                        ?? (trimmedLocation.isEmpty ? nil : trimmedLocation),
                    description: trimmedNotes.isEmpty ? nil : trimmedNotes,
                    stateCode: stateCode,
                    idempotencyKey: idempotencyKey
                )
                submitting = false
                dismiss()
                if wasMechanical {
                    // Post-dismiss hand-off to the Zeun breakdown screen,
                    // where the driver files the detailed
                    // `zeunMechanics.reportBreakdown` (VIN, fault codes,
                    // symptoms, canDrive, photos, telemetry) that lands
                    // the ticket in the mechanic queue. Small delay so the
                    // SOS sheet finishes animating away before the Zeun
                    // nav transition starts.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onOpenZeun?()
                    }
                }
            } catch {
                // Life-safety: keep the sheet open and tell the driver so
                // they can retry or fall back to a 911 voice call.
                submitting = false
                submitError = "We couldn't reach dispatch. \(error.eusoUserCopy) Call 911 if this is life-threatening, then tap Retry."
            }
        }
    }

    // MARK: Call-for-help row

    private var callHelpRow: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "phone.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("Life-threatening? Call 911 first, then send this alert so dispatch can track you.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.leading)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft)
        )
    }

    // MARK: Zeun hand-off note (post-submit messaging)

    /// Shown just under the submit button when the driver has selected
    /// the Breakdown tile. Sets the expectation that after the SOS
    /// lands, we'll walk them straight into the Zeun breakdown report.
    /// Mirrors the web flow — SOS fires first, Zeun follow-up second.
    private var zeunHandoffNote: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "cpu")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("After the broadcast lands, we'll open Zeun Mechanics so you can file the full breakdown report, VIN, fault codes, photos, telemetry. A mobile mechanic is matched from there.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.leading)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue.opacity(0.35), Brand.magenta.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}
