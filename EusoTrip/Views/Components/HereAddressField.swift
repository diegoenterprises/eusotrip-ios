//
//  HereAddressField.swift
//  EusoTrip — autocomplete-aware address input.
//
//  Wraps a `TextField` with HERE Geocoding integration so the user
//  gets typeahead suggestions as they type AND can paste raw
//  coordinates ("32.7767,-96.7970") in lieu of an address — the way
//  truckers actually capture pickup/delivery locations when an
//  address is unknown (oilfield pad, agricultural site, port slip).
//
//  Responsibilities:
//    1. Debounced calls to `hereMaps.autosuggest` (300ms idle gap)
//       so we don't burn the HERE quota per keystroke.
//    2. Suggestion list rendered inline; tap fills `text` + sets
//       `lat`/`lng` (via the suggest result, or a follow-up
//       `hereMaps.geocode` if HERE returned a categorical hit
//       without coordinates).
//    3. "lat,lng" / "lat lng" / "lat;lng" raw-coord parser. When
//       both numbers parse cleanly into the lat/lng ranges we set
//       `lat`/`lng` directly + suppress the autosuggest dropdown.
//    4. Disposable Task per debounce — typing fast cancels the
//       in-flight HERE call so suggestions reflect the latest text.
//
//  Caller contract:
//    HereAddressField(text: $draft.origin,
//                     lat:  $draft.originLat,
//                     lng:  $draft.originLng,
//                     placeholder: "City, ST or lat,lng")
//
//  When the user clears the field manually, lat/lng are also reset
//  to nil so a stale geocode doesn't ride along with a half-typed
//  re-edit.
//

import SwiftUI

struct HereAddressField: View {
    @Binding var text: String
    @Binding var lat: Double?
    @Binding var lng: Double?
    var placeholder: String = "City, ST or lat,lng"
    /// Anchor for the autosuggest call. Defaults to a continental-US
    /// centroid (Lebanon, KS) so US lookups bias toward US results
    /// without requiring location authorization.
    var anchor: (lat: Double, lng: Double) = (39.5, -98.0)

    @Environment(\.palette) private var palette
    @State private var suggestions: [HereSuggestion] = []
    @State private var isLoading: Bool = false
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var suppressNextSuggest: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: lat != nil ? "checkmark.circle.fill" : "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(lat != nil ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(EType.body)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)
                    .focused($focused)
                    .onChange(of: text) { _, newValue in
                        handleTextChange(newValue)
                    }
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                } else if !text.isEmpty {
                    Button {
                        text = ""; lat = nil; lng = nil; suggestions = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.textTertiary)
                    }.buttonStyle(.plain)
                }
            }

            if focused, !suggestions.isEmpty {
                suggestionList
            }
            if let coordHint = parseCoords(text) {
                coordChip(coordHint)
            }
        }
    }

    // MARK: - Suggestion list

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions.prefix(6)) { s in
                suggestionRow(s)
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Extracted into its own builder to keep `suggestionList` simple
    /// enough for the SwiftUI type checker. Inlining a Button + nested
    /// HStack + foreach modifiers triggered "compiler is unable to
    /// type-check this expression in reasonable time."
    @ViewBuilder
    private func suggestionRow(_ s: HereSuggestion) -> some View {
        Button {
            Task { await acceptSuggestion(s) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "mappin.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(s.title)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        Divider().overlay(palette.borderFaint)
    }

    private func coordChip(_ c: (Double, Double)) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(String(format: "Coordinates · %.4f, %.4f", c.0, c.1))
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Behavior

    private func handleTextChange(_ newValue: String) {
        // Coord paste — short-circuit autosuggest entirely so the user
        // gets a clean confirmation chip without a bogus dropdown.
        if let coords = parseCoords(newValue) {
            lat = coords.0; lng = coords.1
            suggestions = []
            return
        }

        // Manual edit invalidates the previous geocode pin. Don't keep
        // a stale lat/lng paired with new text — the server-side
        // geocode fallback will rebuild it on submit if needed.
        if lat != nil || lng != nil {
            lat = nil; lng = nil
        }

        // Skip the network round-trip when we know the next change
        // came from `acceptSuggestion` (it sets text + lat/lng then
        // dismisses the list — running autosuggest on that exact
        // string would re-pop the dropdown immediately).
        if suppressNextSuggest {
            suppressNextSuggest = false
            return
        }

        debounceTask?.cancel()
        let q = newValue.trimmingCharacters(in: .whitespaces)
        if q.count < 2 { suggestions = []; return }

        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetchAutosuggest(q)
        }
    }

    private func fetchAutosuggest(_ q: String) async {
        struct Anchor: Encodable { let lat: Double; let lng: Double }
        struct In: Encodable { let query: String; let anchor: Anchor; let limit: Int }
        struct Item: Decodable, Identifiable {
            let id: String; let title: String
            let lat: Double?; let lng: Double?
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let items: [Item] = try await EusoTripAPI.shared.query(
                "hereMaps.autosuggest",
                input: In(
                    query: q,
                    anchor: Anchor(lat: anchor.lat, lng: anchor.lng),
                    limit: 8
                )
            )
            suggestions = items.map { HereSuggestion(id: $0.id, title: $0.title, lat: $0.lat, lng: $0.lng) }
        } catch {
            // Silent — suggestion list disappears on error so the user
            // can still type a free-form address. Server-side geocode
            // fallback runs at submit time so submission isn't blocked.
            suggestions = []
        }
    }

    private func acceptSuggestion(_ s: HereSuggestion) async {
        suppressNextSuggest = true
        text = s.title
        suggestions = []
        focused = false

        if let lat = s.lat, let lng = s.lng {
            self.lat = lat; self.lng = lng
            return
        }

        // Categorical hit (no coords on the suggestion). Resolve via
        // a follow-up geocode so the create payload still ships coords.
        struct In: Encodable { let query: String }
        struct Geo: Decodable { let ok: Bool; let lat: Double; let lng: Double }
        if let geo: Geo = try? await EusoTripAPI.shared.query("hereMaps.geocode", input: In(query: s.title)) {
            if geo.ok { self.lat = geo.lat; self.lng = geo.lng }
        }
    }

    // MARK: - Coordinate parsing

    /// Accepts "lat,lng", "lat, lng", "lat lng", "lat;lng". Both numbers
    /// must fall in valid ranges (lat ±90, lng ±180); otherwise nil.
    /// `40.7,-74.0` → (40.7, -74.0); `40 -74` → nil (whitespace alone is
    /// ambiguous against city-state strings like "Austin TX").
    private func parseCoords(_ s: String) -> (Double, Double)? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(",") || trimmed.contains(";") else { return nil }
        let parts = trimmed
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",", maxSplits: 1)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]), let lng = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lng)
        else { return nil }
        return (lat, lng)
    }
}

private struct HereSuggestion: Identifiable {
    let id: String
    let title: String
    let lat: Double?
    let lng: Double?
}
