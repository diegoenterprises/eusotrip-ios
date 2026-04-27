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

    init(text: String = "", coordinate: CLLocationCoordinate2D? = nil, source: Source = .typed) {
        self.text = text
        self.coordinate = coordinate
        self.source = source
    }

    // Equatable by hand — CLLocationCoordinate2D isn't Equatable.
    static func == (lhs: ResolvedAddress, rhs: ResolvedAddress) -> Bool {
        lhs.text == rhs.text &&
        lhs.source == rhs.source &&
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
    /// Bias for HERE autosuggest. Falls back to Dallas when nil — matches
    /// the seed data default used elsewhere in the app.
    var nearHint: CLLocationCoordinate2D?

    // MARK: Internal state

    @State private var suggestions: [HereGeocodeItem] = []
    @State private var showSuggestions: Bool = false
    @State private var autosuggestTask: Task<Void, Never>?
    @State private var reverseTask: Task<Void, Never>?
    @State private var resolvedLabel: String? = nil
    @FocusState private var focused: Bool

    /// Default bias when `nearHint == nil` and no other location source is
    /// available. Same origin as the load seed data (Dallas, TX) so the
    /// first suggestions lean toward the freight belt.
    private static let fallbackHint = CLLocationCoordinate2D(latitude: 32.7767,
                                                             longitude: -96.7970)

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
                            Text(hit.title)
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
                .accessibilityLabel("\(hit.title)\(subtitle(for: hit).map { ", \($0)" } ?? "")")
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
        if let coord = LatLongParser.parse(cleaned) {
            autosuggestTask?.cancel()
            showSuggestions = false
            suggestions = []
            value = ResolvedAddress(text: cleaned, coordinate: coord, source: .coord)
            reverseResolve(coord)
            return
        }

        // 2. Normal path — preserve existing coord if the caller had one
        //    and the text is unchanged; otherwise reset to .typed.
        value = ResolvedAddress(text: cleaned, coordinate: nil, source: .typed)
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
        let hint = nearHint ?? Self.fallbackHint
        do {
            let items = try await HereGeocodingClient.shared.autosuggest(
                query: query,
                near: hint,
                limit: 5
            )
            if Task.isCancelled { return }
            await MainActor.run {
                // Filter down to items that actually have a position we can
                // use — autosuggest sometimes returns category matches with
                // no coord, which would look broken if picked.
                self.suggestions = items.filter { _ in true }
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
        let coord = CLLocationCoordinate2D(latitude: hit.position.lat,
                                           longitude: hit.position.lng)
        value = ResolvedAddress(text: hit.title, coordinate: coord, source: .autocomplete)
        resolvedLabel = nil
        suggestions = []
        showSuggestions = false
        focused = false
    }

    private func clear() {
        autosuggestTask?.cancel()
        reverseTask?.cancel()
        value = ResolvedAddress(text: "", coordinate: nil, source: .typed)
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
                        self.resolvedLabel = hit.title
                    }
                }
            } catch {
                // Keep coord, skip the label.
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
