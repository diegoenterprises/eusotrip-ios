//
//  204_ShipperPostLoad.swift
//  EusoTrip — Shipper · Post Load (brick 204).
//
//  Fifth brick on the Shipper role track (200s). Lifted out of the
//  201 Shipper · Loads "Post a load" CTA — this is the dedicated form
//  surface that captures origin / destination / cargo type / pickup
//  date / weight / rate / notes and posts a fresh load row to the
//  backend via `shippers.create`.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §2 (gradient-only
//  accent — no flat Brand.info / Brand.blue fills, no .tint(.blue)),
//  §4 (tokenized spacing / radius / type — Space.s*, Radius.*,
//  EType.*), §5 (palette semantic only — no hard-coded Color.white /
//  Color.black / Color.gray fills outside the white text on the
//  gradient submit pill), §7 (`AnyShapeStyle` wrapping for ternary
//  shape-styles in fill / stroke), §10 (previews compile in isolation
//  — `.task` doesn't run in the preview canvas, so the store stays
//  in `.idle` and never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Form fields are user-typed. There is NO seeded text, NO
//      placeholder origin/destination strings, NO fake cargo
//      defaults beyond the backend's "general" Zod default. Every
//      keystroke is real.
//    • Cargo type picker → drives the `ShipperAPI.CargoType` enum
//      (mirrors the backend Zod enum verbatim — see
//      EusoTripAPI.swift L8825 / shippers.ts:22). "general" is the
//      initial selection because the backend coerces to "general"
//      when the wire field is absent.
//    • Submit CTA → `ShipperAPI.create(...)` →
//      `frontend/server/routers/shippers.ts:18`. Returns
//      `{ success, id, loadNumber }`. The screen surfaces the
//      verbatim server-emitted `loadNumber` in the success banner —
//      no client-side reformatting.
//    • Empty / blank optional fields (rate, weight, notes,
//      pickupDate) are wire-omitted (sent as nil) so the backend's
//      `.optional()` defaults apply. Whitespace-only strings are
//      coalesced to nil before send so the wire never carries a
//      meaningless value.
//    • Server errors surface via `EusoTripAPIError.errorDescription`
//      in an inline banner with a Retry CTA. Never a synthesised
//      success.
//    • On success, the parent `ShipperActiveLoadsStore` (when this
//      screen is reached from the 201 Shipper · Loads context) is
//      invalidated by the caller; here we surface a success banner
//      and reset the form so the user can post another.
//
//  Wired into `ContentView.ScreenRegistry` as id="204".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct ShipperPostLoad: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var store = ShipperPostLoadStore()

    /// Form state. Plain `@State` — the store only owns the
    /// mutation phase, not the typed text. This keeps the form
    /// trivially resettable and the store free of "form glue."
    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var cargoType: ShipperAPI.CargoType = .general
    @State private var hasPickupDate: Bool = false
    @State private var pickupDate: Date = Date()
    @State private var weightText: String = ""
    @State private var rateText: String = ""
    @State private var notes: String = ""

    /// Successful posts captured for the in-session ticker tile so
    /// the user can see "you just posted SHP-123, here's another"
    /// without re-fetching the full loads list. Cleared when the
    /// view is dismissed; not persisted.
    @State private var lastSuccess: ShipperAPI.PostLoadAck? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let ack = lastSuccess {
                    successBanner(ack)
                }
                if case .error(let message) = store.phase {
                    errorBanner(message)
                }
                originDestinationCard
                cargoTypePicker
                pickupDateCard
                weightAndRateCard
                notesCard
                submitButton
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenTileRoot()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "plus.square.on.square.fill")
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
                    Text("SHIPPER · POST LOAD")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Post a fresh load")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(headerSubhead)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var headerSubhead: String {
        switch store.phase {
        case .submitting:
            return "Posting your load to the network…"
        case .success:
            return "Posted. Catalysts can now bid on this load."
        case .error:
            return "We hit a snag posting that. Fix it and try again."
        case .idle:
            if origin.isEmpty || destination.isEmpty {
                return "Fill origin and destination — everything else is optional."
            }
            return "Ready to post. Catalysts will see it instantly."
        }
    }

    // MARK: - Success / error banners

    private func successBanner(_ ack: ShipperAPI.PostLoadAck) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Load posted")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(loadNumberSubtitle(ack))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation { lastSuccess = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func loadNumberSubtitle(_ ack: ShipperAPI.PostLoadAck) -> String {
        let trimmed = ack.loadNumber.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Bids will land in your Bids inbox." }
        return "\(trimmed) · bids will land in your Bids inbox."
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't post that load")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button {
                store.reset()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Origin + destination card

    private var originDestinationCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel(
                systemImage: "mappin.and.ellipse",
                text: "ORIGIN & DESTINATION"
            )
            VStack(alignment: .leading, spacing: Space.s3) {
                fieldLabeledTextField(
                    label: "Origin",
                    placeholder: "e.g. Houston, TX",
                    text: $origin,
                    systemImage: "circle.dashed"
                )
                Divider().background(palette.borderFaint)
                fieldLabeledTextField(
                    label: "Destination",
                    placeholder: "e.g. Atlanta, GA",
                    text: $destination,
                    systemImage: "flag.checkered"
                )
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: - Cargo type picker

    private var cargoTypePicker: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel(
                systemImage: "shippingbox.and.arrow.backward",
                text: "CARGO TYPE"
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShipperAPI.CargoType.allCases) { type in
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                cargoType = type
                            }
                        } label: {
                            cargoChip(for: type)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func cargoChip(for type: ShipperAPI.CargoType) -> some View {
        let on = (cargoType == type)
        HStack(spacing: 6) {
            Image(systemName: type.systemImage)
                .font(.system(size: 10, weight: .heavy))
            Text(type.label)
                .font(.system(size: 11, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(
                on ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard)
            )
        )
        .overlay(
            Capsule().strokeBorder(
                on ? AnyShapeStyle(Color.clear) : AnyShapeStyle(palette.borderFaint),
                lineWidth: 1
            )
        )
    }

    // MARK: - Pickup date card

    private var pickupDateCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel(
                systemImage: "calendar",
                text: "PICKUP DATE"
            )
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("Schedule a pickup")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Toggle(
                        "Schedule a pickup",
                        isOn: $hasPickupDate.animation(.spring(response: 0.22, dampingFraction: 0.85))
                    )
                    .toggleStyle(GradientToggleStyle())
                    .labelsHidden()
                }
                if hasPickupDate {
                    Divider().background(palette.borderFaint)
                    DatePicker(
                        "Pickup date",
                        selection: $pickupDate,
                        in: Date()...,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .tint(LinearGradient.diagonal)
                    .foregroundStyle(palette.textPrimary)
                    .disabled(isSubmitting)
                } else {
                    Text("No pickup date — leave blank to let the catalyst propose one.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: - Weight + rate card

    private var weightAndRateCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel(
                systemImage: "scalemass.fill",
                text: "WEIGHT & RATE (OPTIONAL)"
            )
            VStack(alignment: .leading, spacing: Space.s3) {
                fieldLabeledNumberField(
                    label: "Weight",
                    placeholder: "0",
                    text: $weightText,
                    systemImage: "scalemass",
                    suffix: "lbs"
                )
                Divider().background(palette.borderFaint)
                fieldLabeledNumberField(
                    label: "Posted rate",
                    placeholder: "0",
                    text: $rateText,
                    systemImage: "dollarsign.circle",
                    suffix: "USD"
                )
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: - Notes card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel(
                systemImage: "text.alignleft",
                text: "NOTES (OPTIONAL)"
            )
            VStack(alignment: .leading, spacing: Space.s2) {
                TextField(
                    "Anything carriers should know — temperature ranges, dock hours, COI requirements…",
                    text: $notes,
                    axis: .vertical
                )
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .tint(LinearGradient.diagonal)
                .lineLimit(3...6)
                .disabled(isSubmitting)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: - Submit button

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                }
                Text(submitButtonText)
                    .font(.system(size: 13, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(
                        canSubmit
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.tintNeutral.opacity(0.4))
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var submitButtonText: String {
        switch store.phase {
        case .submitting: return "Posting…"
        case .success:    return "Post another"
        default:          return "Post this load"
        }
    }

    // MARK: - Section label helper

    private func sectionLabel(systemImage: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    // MARK: - Field helpers

    private func fieldLabeledTextField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        systemImage: String
    ) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                TextField(placeholder, text: text)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(LinearGradient.diagonal)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .disabled(isSubmitting)
            }
        }
    }

    private func fieldLabeledNumberField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        systemImage: String,
        suffix: String
    ) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 6) {
                    TextField(placeholder, text: text)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .tint(LinearGradient.diagonal)
                        .keyboardType(.decimalPad)
                        .disabled(isSubmitting)
                    Text(suffix)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    // MARK: - Submit pipeline

    private var isSubmitting: Bool {
        if case .submitting = store.phase { return true }
        return false
    }

    /// CTA enabled iff (origin and destination non-empty) AND
    /// (not currently submitting). Doctrine: never let the user
    /// fire a known-invalid mutation.
    private var canSubmit: Bool {
        let trimOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimDest   = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimOrigin.isEmpty || trimDest.isEmpty { return false }
        if isSubmitting { return false }
        return true
    }

    private func submit() async {
        // If we're already in success state, the CTA acts as
        // "post another" — clear the form, reset the store, and
        // bail out so the user types a fresh load.
        if case .success = store.phase {
            resetForm()
            store.reset()
            return
        }
        let pickupISO = hasPickupDate ? isoDate(pickupDate) : nil
        let weight    = parseDouble(weightText)
        let rate      = parseDouble(rateText)
        await store.submit(
            origin: origin,
            destination: destination,
            cargoType: cargoType,
            rate: rate,
            weight: weight,
            notes: notes,
            pickupDate: pickupISO
        )
        if case .success(let ack) = store.phase {
            self.lastSuccess = ack
            // Form clears so the user can post another without
            // remounting the screen. Cargo type stays on the user's
            // last selection by design — most shippers post the
            // same kind of load repeatedly.
            resetForm()
        }
    }

    private func resetForm() {
        origin = ""
        destination = ""
        hasPickupDate = false
        pickupDate = Date()
        weightText = ""
        rateText = ""
        notes = ""
    }

    /// Permissive decimal parser — tolerates "1,200" as well as
    /// "1200" and "1200.50". Returns nil for empty or unparseable
    /// strings (so the wire field gets omitted).
    private func parseDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    /// `YYYY-MM-DD` — the form the backend accepts at
    /// `new Date(input.pickupDate)`. Locale-independent.
    private func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}

// MARK: - Screen wrapper

struct ShipperPostLoadScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperPostLoad()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_204(),
                trailing: shipperNavTrailing_204(),
                orbState: .idle
            )
        }
    }
}

// 204 sits one tap deeper than the four primary BottomNav slots —
// it's the dedicated form behind the "Post a load" CTA on
// Shipper bottom-nav doctrine — 204 is the canonical "Create Load"
// destination; the leading[1] slot lights up when this screen is active.
private func shipperNavLeading_204() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                              isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle.fill",   isCurrent: true)]
}

private func shipperNavTrailing_204() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.idle` and the
// form renders with empty fields — both registers compile in
// isolation per doctrine §10.

#Preview("204 · Shipper · Post Load · Night") {
    ShipperPostLoadScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("204 · Shipper · Post Load · Afternoon") {
    ShipperPostLoadScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
