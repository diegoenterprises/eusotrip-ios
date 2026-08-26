//
//  EusoAddressField.swift
//  EusoTrip — Reusable HERE-powered address picker with coordinate-paste
//  short-circuit.
//
//  This is the one place in the app that should own "type an address string
//  and get a resolved lat/lng back." Replaces ad-hoc `GlassField` bindings to
//  plain `String`s that had no geocoding hooked up.
//
//  Visual language matches `GlassField` (see `EusoTrip/Theme/Glass.swift`):
//  ALL-CAPS tracked micro-label over a 50pt glass pill with a leading SF
//  Symbol icon; palette-sourced colors so Night + Afternoon themes both work.
//
//  Behavior:
//    1. On every keystroke run `LatLongParser.parse(_:)`. If it returns a
//       coordinate, we hide the suggestion list, call `reverseGeocode`, and
//       set `.source = .coord`.
//    2. Otherwise debounce 350ms and call `HereGeocodingClient.autosuggest`
//       with a `near=` bias. The in-flight task is cancelled on every new
//       keystroke so stale suggestions can never overwrite fresh ones.
//    3. Tapping a suggestion fills the field with the hit's title, keeps
//       the coord that HERE returned, and sets `.source = .autocomplete`.
//    4. Trailing button: X to clear when non-empty, otherwise a pin glyph.
//
//  `ResolvedAddress` lives in this file (rather than in Models/) because it's
//  the public contract of this component and has no other owner — keeping
//  them colocated means callers import one file instead of two.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - ResolvedAddress

/// The value a `EusoAddressField` produces. Callers should hold this in
/// `@Published` state on their view-model so both the display string AND
/// the coord stay in sync.
struct ResolvedAddress: Equatable {
    /// Where the current text came from. Drives downstream UX — e.g. a
    /// `.coord` source can show "Resolved: 1 WTC, NY" beneath the field.
    enum Source: Equatable { case typed, coord, autocomplete }

    /// What the user sees in the field.
    var text: String
    /// The lat/lng we resolved this address to. `nil` until the user
    /// either pastes a coord, picks a suggestion, or blur-resolves.
    var coordinate: CLLocationCoordinate2D?
    /// Where the coord came from (or `.typed` if none yet).
    var source: Source
    /// Provider/input provenance retained independently of coordinate state.
    var provenance: HereAddressProvenance

    init(
        text: String = "",
        coordinate: CLLocationCoordinate2D? = nil,
        source: Source = .typed,
        provenance: HereAddressProvenance? = nil
    ) {
        self.text = text
        self.coordinate = coordinate
        self.source = source
        self.provenance = provenance ?? {
            switch source {
            case .typed: return .userEntered
            case .coord: return .coordinateInput
            case .autocomplete: return .hereAutosuggest
            }
        }()
    }

    // Equatable by hand — CLLocationCoordinate2D isn't Equatable.
    static func == (lhs: ResolvedAddress, rhs: ResolvedAddress) -> Bool {
        lhs.text == rhs.text &&
        lhs.source == rhs.source &&
        lhs.provenance == rhs.provenance &&
        lhs.coordinate?.latitude == rhs.coordinate?.latitude &&
        lhs.coordinate?.longitude == rhs.coordinate?.longitude
    }
}

// MARK: - EusoAddressField

/// Glass-styled address input backed by HERE Autosuggest + a coordinate-
/// paste short-circuit. Drop-in replacement for `GlassField` wherever the
/// bound value is an address.
struct EusoAddressField: View {
    @Environment(\.palette) private var palette

    // MARK: Inputs

    /// ALL-CAPS micro-label shown above the pill (e.g. "ADDRESS", "PICKUP").
    let label: String
    /// Grayed placeholder shown when empty.
    let placeholder: String
    /// Two-way binding that carries text + coord + source back to the caller.
    @Binding var value: ResolvedAddress
    /// Optional real bias for HERE autosuggest. When unavailable, forward
    /// geocoding runs without a location bias instead of inventing one.
    var nearHint: CLLocationCoordinate2D?

    // MARK: Internal state

    @State private var suggestions: [HereGeocodeItem] = []
    @State private var showSuggestions: Bool = false
    @State private var autosuggestTask: Task<Void, Never>?
    @State private var reverseTask: Task<Void, Never>?
    @State private var resolvedLabel: String? = nil
    @FocusState private var focused: Bool

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)

            // Glass pill — same geometry as GlassField.
            HStack(spacing: Space.s2) {
                Image(systemName: "location")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 20)

                TextField(placeholder, text: Binding(
                    get: { value.text },
                    set: { newText in handleTextChange(newText) }
                ))
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .textInputAutocapitalization(.words)
                .keyboardType(.default)
                .textContentType(.fullStreetAddress)
                .autocorrectionDisabled(true)
                .focused($focused)

                Button {
                    if value.text.isEmpty {
                        // Pin glyph is decorative when empty.
                    } else {
                        clear()
                    }
                } label: {
                    Image(systemName: value.text.isEmpty ? "mappin" : "xmark.circle.fill")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value.text.isEmpty ? "Address pin" : "Clear address")
                .allowsHitTesting(!value.text.isEmpty)
            }
            .padding(.horizontal, Space.s4)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderSoft, lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Address")
            .accessibilityHint("Type an address or paste coordinates")

            // Resolved echo — appears when we have coords but no pick.
            if let resolvedLabel {
                Text("Resolved: \(resolvedLabel)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityLabel("Resolved to \(resolvedLabel)")
            }

            // Suggestion drop-down.
            if showSuggestions && !suggestions.isEmpty {
                suggestionList
            }
        }
        .onDisappear {
            autosuggestTask?.cancel()
            reverseTask?.cancel()
        }
    }

    // MARK: Subviews

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(suggestions.prefix(5)) { hit in
                let formatted = hit.formattedAddress(provenance: .hereAutosuggest)
                Button {
                    pick(hit)
                } label: {
                    HStack(alignment: .top, spacing: Space.s2) {
                        Image(systemName: "mappin")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 18)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatted.label)
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            if let sub = subtitle(for: hit), !sub.isEmpty {
                                Text(sub)
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s4)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(formatted.label)\(subtitle(for: hit).map { ", \($0)" } ?? "")")
                .accessibilityAddTraits(.isButton)

                if hit.id != suggestions.prefix(5).last?.id {
                    Divider().overlay(palette.borderFaint)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)
    }

    // MARK: Event handlers

    private func handleTextChange(_ newText: String) {
        // Strip newlines on paste.
        let cleaned = newText.replacingOccurrences(of: "\n", with: " ")
                             .replacingOccurrences(of: "\r", with: " ")

        // 1. Coord short-circuit.
        if let parsed = LatLongParser.parseDetailed(cleaned) {
            autosuggestTask?.cancel()
            showSuggestions = false
            suggestions = []
            value = ResolvedAddress(
                text: parsed.originalText,
                coordinate: parsed.coordinate,
                source: .coord,
                provenance: .coordinateInput
            )
            reverseResolve(parsed.coordinate)
            return
        }

        // 2. Normal path — a manual edit invalidates the prior coordinate and
        //    any in-flight reverse-geocode label.
        reverseTask?.cancel()
        value = ResolvedAddress(
            text: cleaned,
            coordinate: nil,
            source: .typed,
            provenance: .userEntered
        )
        resolvedLabel = nil

        guard !cleaned.trimmingCharacters(in: .whitespaces).isEmpty else {
            autosuggestTask?.cancel()
            showSuggestions = false
            suggestions = []
            return
        }

        // 3. Debounced autosuggest — cancel prior task first.
        autosuggestTask?.cancel()
        autosuggestTask = Task { [cleaned] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            await runAutosuggest(query: cleaned)
        }
    }

    private func runAutosuggest(query: String) async {
        do {
            let items: [HereGeocodeItem]
            if let hint = LatLongParser.validatedCoordinate(
                latitude: nearHint?.latitude,
                longitude: nearHint?.longitude
            ) {
                items = try await HereGeocodingClient.shared.autosuggest(
                    query: query,
                    near: hint,
                    limit: 5
                )
            } else {
                items = try await HereGeocodingClient.shared.geocode(
                    query: query,
                    near: nil,
                    limit: 5
                )
            }
            if Task.isCancelled { return }
            await MainActor.run {
                // Keep category/coordless matches too — `pick(_:)` resolves
                // them with a confirming, unbiased forward geocode, so they
                // no longer look broken when tapped.
                self.suggestions = items
                self.showSuggestions = !items.isEmpty
            }
        } catch {
            // Offline / missing API key / HTTP error. Silently drop the
            // suggestion UI; the user keeps typing and the raw string
            // stays as `.typed`.
            await MainActor.run {
                self.suggestions = []
                self.showSuggestions = false
            }
        }
    }

    private func pick(_ hit: HereGeocodeItem) {
        autosuggestTask?.cancel()
        reverseTask?.cancel()
        suggestions = []
        showSuggestions = false
        focused = false

        // CONFIRMING RESOLVE — never trust the autosuggest hit's ride-along
        // coordinate or raw title. The `near=` bias can surface a same-named
        // place 1,000+ mi away in another state (see HereGeocodingClient
        // .resolve). Forward-geocode the chosen title with no bias and lock
        // onto the admin-matching result; store a clean structured label.
        // Optimistically reflect the tap immediately, then correct once the
        // confirming geocode returns.
        if let pos = hit.position,
           let coordinate = LatLongParser.validatedCoordinate(
               latitude: pos.lat,
               longitude: pos.lng
           ) {
            let formatted = hit.formattedAddress(provenance: .hereAutosuggest)
            value = ResolvedAddress(
                text: formatted.label,
                coordinate: coordinate,
                source: .autocomplete,
                provenance: formatted.provenance
            )
        } else {
            let formatted = hit.formattedAddress(provenance: .hereAutosuggest)
            value = ResolvedAddress(
                text: formatted.label,
                coordinate: nil,
                source: .typed,
                provenance: formatted.provenance
            )
        }
        resolvedLabel = nil

        reverseTask = Task {
            guard let resolved = await HereGeocodingClient.shared.resolve(hit),
                  let coordinate = LatLongParser.validatedCoordinate(
                      latitude: resolved.coordinate.latitude,
                      longitude: resolved.coordinate.longitude
                  ) else { return }
            if Task.isCancelled { return }
            await MainActor.run {
                self.value = ResolvedAddress(
                    text: resolved.label,
                    coordinate: coordinate,
                    source: .autocomplete,
                    provenance: resolved.formattedAddress.provenance
                )
            }
        }
    }

    private func clear() {
        autosuggestTask?.cancel()
        reverseTask?.cancel()
        value = ResolvedAddress(
            text: "",
            coordinate: nil,
            source: .typed,
            provenance: .userEntered
        )
        suggestions = []
        showSuggestions = false
        resolvedLabel = nil
        focused = true
    }

    private func reverseResolve(_ coord: CLLocationCoordinate2D) {
        reverseTask?.cancel()
        reverseTask = Task {
            do {
                let items = try await HereGeocodingClient.shared.reverseGeocode(
                    at: coord, limit: 1
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    if let hit = items.first {
                        self.resolvedLabel = hit.formattedAddress(
                            provenance: .hereReverseGeocode
                        ).label
                    } else {
                        self.resolvedLabel = HereAddressFormatter.unknownLabel
                    }
                }
            } catch {
                // Keep the exact coordinate and surface an honest unknown.
                if Task.isCancelled { return }
                await MainActor.run {
                    self.resolvedLabel = HereAddressFormatter.unknownLabel
                }
            }
        }
    }

    private func subtitle(for hit: HereGeocodeItem) -> String? {
        let city = hit.address.city
        let state = hit.address.stateCode ?? hit.address.state
        switch (city, state) {
        case let (c?, s?): return "\(c), \(s)"
        case let (c?, nil): return c
        case let (nil, s?): return s
        default: return nil
        }
    }
}
