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
import CoreLocation

struct HereAddressField: View {
    @Binding var text: String
    @Binding var lat: Double?
    @Binding var lng: Double?
    var placeholder: String = "City, ST or lat,lng"
    /// Anchor for the autosuggest call. Defaults to a continental-US
    /// centroid (Lebanon, KS) so US lookups bias toward US results
    /// without requiring location authorization.
    var anchor: (lat: Double, lng: Double) = (39.5, -98.0)
    /// ISO-3166 alpha-3 country code (USA/CAN/MEX) to bias autosuggest to;
    /// nil = no country filter. Threaded to HERE `in=countryCode:` server-side
    /// so a Mexico load surfaces Nuevo Laredo, not Laredo TX.
    var country: String? = nil

    @Environment(\.palette) private var palette
    @State private var suggestions: [HereSuggestion] = []
    @State private var isLoading: Bool = false
    @State private var debounceTask: Task<Void, Never>? = nil
    @State private var suppressNextSuggest: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: parsedBindingCoordinate != nil ? "checkmark.circle.fill" : "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(parsedBindingCoordinate != nil ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
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
            if let coordHint = LatLongParser.parse(text) {
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

    private func coordChip(_ coordinate: CLLocationCoordinate2D) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("Coordinates · \(LatLongParser.displayString(coordinate))")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Behavior

    private func handleTextChange(_ newValue: String) {
        // Coord paste — short-circuit autosuggest entirely so the user
        // gets a clean confirmation chip without a bogus dropdown.
        if let coordinate = LatLongParser.parse(newValue) {
            lat = coordinate.latitude
            lng = coordinate.longitude
            suggestions = []
            return
        }

        // A programmatic suggestion selection owns its resolved coordinate.
        // Do not clear that coordinate when assigning the suggestion label.
        if suppressNextSuggest {
            suppressNextSuggest = false
            return
        }

        // Manual edit invalidates the previous geocode pin. Don't keep
        // a stale lat/lng paired with new text — the server-side
        // geocode fallback will rebuild it on submit if needed.
        if lat != nil || lng != nil {
            lat = nil; lng = nil
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
        struct In: Encodable { let query: String; let anchor: Anchor; let limit: Int; let country: String? }
        struct Item: Decodable, Identifiable {
            let id: String; let title: String
            let lat: Double?; let lng: Double?
            // Optional structured hints — present when the server proc passes
            // HERE's address admin through; nil-tolerant if it doesn't. The
            // confirming geocode in `acceptSuggestion` uses these to pin the
            // right same-named place across states.
            let city: String?; let state: String?; let resultType: String?
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let items: [Item] = try await EusoTripAPI.shared.query(
                "hereMaps.autosuggest",
                input: In(
                    query: q,
                    anchor: Anchor(lat: anchor.lat, lng: anchor.lng),
                    limit: 8,
                    country: country
                )
            )
            suggestions = items.map {
                HereSuggestion(id: $0.id, title: $0.title, lat: $0.lat, lng: $0.lng,
                               city: $0.city, stateCode: $0.state, resultType: $0.resultType)
            }
        } catch {
            // Silent — suggestion list disappears on error so the user
            // can still type a free-form address. Server-side geocode
            // fallback runs at submit time so submission isn't blocked.
            suggestions = []
        }
    }

    private func acceptSuggestion(_ s: HereSuggestion) async {
        suppressNextSuggest = true
        suggestions = []
        focused = false
        isLoading = true
        defer { isLoading = false }

        // CONFIRMING RESOLVE — do NOT trust the suggestion's ride-along
        // coordinate or its raw title. The autosuggest `at=` hint can drag a
        // same-named place 1,000+ mi to another state (Houston "Barbours Cut"
        // → "Barbour Ct, San Pedro CA"; "Terminal Island" → Miami FL). We
        // forward-geocode the chosen title with NO `at=` bias and lock onto
        // the result whose admin (city/state) matches — so origin AND
        // destination each resolve to their TRUE coordinate independently,
        // and the stored label is rebuilt from structured fields, never the
        // raw "Part near (of) …" title.
        let suggestionCoordinate = LatLongParser.validatedCoordinate(
            latitude: s.lat,
            longitude: s.lng
        )
        let hint = HereGeocodeItem(
            id: s.id,
            title: s.title,
            address: HereAddress(
                label: s.title, countryCode: nil, countryName: nil,
                stateCode: s.stateCode, state: nil, county: nil,
                city: s.city, district: nil, street: nil,
                postalCode: nil, houseNumber: nil
            ),
            position: suggestionCoordinate.map {
                HerePlace.Coord(lat: $0.latitude, lng: $0.longitude)
            },
            mapView: nil,
            resultType: s.resultType
        )

        if let resolved = await HereGeocodingClient.shared.resolve(hint),
           let coordinate = LatLongParser.validatedCoordinate(
               latitude: resolved.coordinate.latitude,
               longitude: resolved.coordinate.longitude
           ) {
            text = resolved.label
            self.lat = coordinate.latitude
            self.lng = coordinate.longitude
            // Re-suppress: assigning `text` after the await re-fires
            // onChange, which would re-pop the dropdown.
            suppressNextSuggest = true
            return
        }

        // Confirming resolve failed entirely (offline / HERE error). Keep the
        // raw title and the suggestion's own coord if it had one, so the user
        // isn't blocked — server-side geocode fallback still runs at submit.
        text = s.title
        suppressNextSuggest = true
        if let coordinate = LatLongParser.validatedCoordinate(
            latitude: s.lat,
            longitude: s.lng
        ) {
            self.lat = coordinate.latitude
            self.lng = coordinate.longitude
        }
    }

    private var parsedBindingCoordinate: CLLocationCoordinate2D? {
        LatLongParser.validatedCoordinate(latitude: lat, longitude: lng)
    }
}

private struct HereSuggestion: Identifiable {
    let id: String
    let title: String
    let lat: Double?
    let lng: Double?
    /// Structured admin from the autosuggest hit (nil when the server proc
    /// doesn't forward it). Seeds the confirming geocode's admin match so the
    /// right same-named place wins across states.
    var city: String? = nil
    var stateCode: String? = nil
    var resultType: String? = nil
}
