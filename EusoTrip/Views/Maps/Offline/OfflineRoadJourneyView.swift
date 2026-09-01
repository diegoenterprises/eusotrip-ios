//
//  OfflineRoadJourneyView.swift
//  EusoTrip
//
//  Production caller for radio-silent HERE road and truck journeys. Search,
//  routing, and guidance stay inside OfflineMapProductionComposition; this
//  surface never falls back to a web map, Apple Maps, or an online request.
//

import Combine
import CoreLocation
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
struct OfflineRoadJourneyView: View {
    @EnvironmentObject private var session: EusoTripSession
    @ObservedObject private var composition: OfflineMapProductionComposition
    @ObservedObject private var owner: OfflineMapCompositionOwner
    @StateObject private var model: OfflineRoadJourneyViewModel

    init(composition: OfflineMapProductionComposition) {
        self.composition = composition
        self.owner = composition.owner
        _model = StateObject(
            wrappedValue: OfflineRoadJourneyViewModel(composition: composition)
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                orientation
                readiness
                currentLocation
                destinationSearch
                routeProfile
                routeRegister
                guidance
            }
            .padding(20)
        }
        .background(pageBackground.ignoresSafeArea())
        .offlineRoadJourneyNavigationTitle()
        .task(id: sessionScope) {
            await model.bindPrincipal(sessionScope)
        }
        .onDisappear {
            model.cancelPendingOperation()
        }
    }

    private var pageBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }

    private var sessionScope: OfflineRoadJourneyPrincipalScope? {
        guard session.phase == .signedIn,
              let user = session.user,
              let tenantID = user.companyId?.trimmedNonempty,
              let userID = user.id.trimmedNonempty else {
            return nil
        }
        return OfflineRoadJourneyPrincipalScope(
            tenantID: tenantID,
            userID: userID
        )
    }

    private var blockers: [String] {
        OfflineRoadJourneyReadiness.blockers(
            composition: composition,
            snapshot: owner.snapshot,
            hasBoundPrincipal: model.hasBoundPrincipal,
            mode: model.routeMode,
            requireGuidance: false
        )
    }

    private var guidanceBlockers: [String] {
        OfflineRoadJourneyReadiness.blockers(
            composition: composition,
            snapshot: owner.snapshot,
            hasBoundPrincipal: model.hasBoundPrincipal,
            mode: model.routeMode,
            requireGuidance: true
        )
    }

    private var orientation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("RADIO-SILENT ROAD DESK", systemImage: "location.north.line.fill")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.teal)

            Text("Search, route, depart")
                .font(.largeTitle.bold())

            Text("Search installed HERE data around a fresh device fix, calculate a covered road or truck route, then start native on-device guidance. No network or alternate map provider is used.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var readiness: some View {
        journeySection(title: "Departure authority", systemImage: "checkmark.shield.fill") {
            if model.isPreparingPrincipal {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Binding this surface to the signed-in account and checking local HERE custody.")
                }
                .foregroundStyle(.secondary)
            } else if blockers.isEmpty {
                Label("Verified for local search and \(model.routeMode == .truck ? "truck" : "road") routing", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Journey blocked", systemImage: "exclamationmark.lock.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(Array(blockers.enumerated()), id: \.offset) { _, blocker in
                        Text(blocker)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let failure = model.failure {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(failure.title)
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(failure.message)
                        .font(.callout)
                    if let recovery = failure.recovery {
                        Text(recovery)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Dismiss") { model.dismissFailure() }
                        .buttonStyle(.bordered)
                }
                .accessibilityElement(children: .combine)
            }

            if model.operation != .idle {
                Divider()
                HStack(spacing: 10) {
                    ProgressView()
                    Text(model.operation.title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button("Cancel") { model.cancelPendingOperation() }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private var currentLocation: some View {
        journeySection(title: "Current-device origin", systemImage: "location.fill") {
            if let fix = model.locationFix {
                VStack(alignment: .leading, spacing: 5) {
                    Text(fix.provenance.title)
                        .font(.headline)
                    Text("\(OfflineRoadJourneyFormat.coordinate(fix.coordinate)) · ±\(OfflineRoadJourneyFormat.meters(fix.horizontalAccuracyMeters))")
                        .font(.system(.callout, design: .monospaced))
                    Text("Captured \(fix.timestamp.formatted(.relative(presentation: .named))). Every search and route calculation requests a new precise fix.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("No current fix has been accepted. EusoTrip does not substitute a depot, account address, cached POI, or simulated coordinate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.refreshLocation()
            } label: {
                Label("Refresh precise location", systemImage: "location.circle")
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy || model.isPreparingPrincipal || !model.hasBoundPrincipal)
        }
    }

    private var destinationSearch: some View {
        journeySection(title: "Installed-data search", systemImage: "magnifyingglass") {
            TextField("Restaurant, terminal, address, hospital…", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
                .onSubmit {
                    guard blockers.isEmpty else { return }
                    model.search()
                }

            Button {
                model.search()
            } label: {
                Label("Search near current location", systemImage: "magnifyingglass.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                model.isBusy ||
                model.isPreparingPrincipal ||
                !model.hasSearchText ||
                !blockers.isEmpty
            )

            if let evidence = model.searchCoverage {
                coverageEvidence(evidence, prefix: "Search verified by")
            }

            if model.didCompleteSearch && model.searchResults.isEmpty {
                Text("No matching place exists in the verified installed search area.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.searchResults) { result in
                Button {
                    model.selectDestination(result)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: model.selectedDestination?.id == result.id
                              ? "checkmark.circle.fill"
                              : "mappin.circle")
                            .font(.title3)
                            .foregroundStyle(model.selectedDestination?.id == result.id ? .green : .teal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if let address = result.address {
                                Text(address)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Text("\(OfflineRoadJourneyFormat.coordinate(result.coordinate)) · installed region \(result.regionID.rawValue)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var routeProfile: some View {
        journeySection(title: "Route profile", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            Picker("Routing mode", selection: $model.routeMode) {
                Text("Road").tag(OfflineRouteMode.road)
                Text("Truck").tag(OfflineRouteMode.truck)
            }
            .pickerStyle(.segmented)

            if let destination = model.selectedDestination {
                Label("Destination: \(destination.title)", systemImage: "flag.checkered")
                    .font(.callout.weight(.semibold))
            } else {
                Text("Select one verified search result before calculating a route.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if model.routeMode == .truck {
                truckProfile
            }

            Button {
                model.calculateRoute()
            } label: {
                Label("Calculate covered route", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                model.isBusy ||
                model.isPreparingPrincipal ||
                model.selectedDestination == nil ||
                !blockers.isEmpty
            )
        }
    }

    private var truckProfile: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Explicit truck constraints")
                .font(.headline)
            Text("Blank optional fields stay unknown. EusoTrip never supplies default dimensions, weights, axles, trailers, tunnel class, or hazardous-goods classes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Truck type", selection: $model.truckDraft.truckType) {
                Text("Choose truck type").tag(Optional<OfflineTruckType>.none)
                ForEach(OfflineTruckType.allCases, id: \.rawValue) { value in
                    Text(value.title).tag(Optional(value))
                }
            }

            Picker("Restriction category", selection: $model.truckDraft.truckCategory) {
                Text("Choose restriction category").tag(Optional<OfflineTruckCategory>.none)
                ForEach(OfflineTruckCategory.allCases, id: \.rawValue) { value in
                    Text(value.title).tag(Optional(value))
                }
            }

            Picker("Tunnel category", selection: $model.truckDraft.tunnelCategory) {
                Text("Not specified").tag(Optional<OfflineTruckTunnelCategory>.none)
                ForEach(OfflineTruckTunnelCategory.allCases, id: \.rawValue) { value in
                    Text("Category \(value.rawValue.uppercased())")
                        .tag(Optional(value))
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    truckNumberField("Gross weight", text: $model.truckDraft.grossWeightKilograms, unit: "kg")
                    truckNumberField("Per axle", text: $model.truckDraft.weightPerAxleKilograms, unit: "kg")
                }
                VStack(spacing: 10) {
                    truckNumberField("Gross weight", text: $model.truckDraft.grossWeightKilograms, unit: "kg")
                    truckNumberField("Per axle", text: $model.truckDraft.weightPerAxleKilograms, unit: "kg")
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    truckNumberField("Height", text: $model.truckDraft.heightCentimeters, unit: "cm")
                    truckNumberField("Width", text: $model.truckDraft.widthCentimeters, unit: "cm")
                    truckNumberField("Length", text: $model.truckDraft.lengthCentimeters, unit: "cm")
                }
                VStack(spacing: 10) {
                    truckNumberField("Height", text: $model.truckDraft.heightCentimeters, unit: "cm")
                    truckNumberField("Width", text: $model.truckDraft.widthCentimeters, unit: "cm")
                    truckNumberField("Length", text: $model.truckDraft.lengthCentimeters, unit: "cm")
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    truckNumberField("Axles", text: $model.truckDraft.axleCount, unit: "count")
                    truckNumberField("Trailers", text: $model.truckDraft.trailerCount, unit: "count")
                }
                VStack(spacing: 10) {
                    truckNumberField("Axles", text: $model.truckDraft.axleCount, unit: "count")
                    truckNumberField("Trailers", text: $model.truckDraft.trailerCount, unit: "count")
                }
            }

            DisclosureGroup("Hazardous goods") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(OfflineHazardousGoodsClass.allCases, id: \.rawValue) { hazard in
                        Toggle(
                            hazard.title,
                            isOn: Binding(
                                get: { model.truckDraft.hazardousGoods.contains(hazard) },
                                set: { model.setHazard(hazard, selected: $0) }
                            )
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func truckNumberField(
        _ title: String,
        text: Binding<String>,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
            #if canImport(UIKit)
            TextField(unit, text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .accessibilityLabel("\(title), \(unit)")
            #else
            TextField(unit, text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("\(title), \(unit)")
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var routeRegister: some View {
        if model.didCompleteRouteCalculation || !model.routes.isEmpty {
            journeySection(title: "Covered route register", systemImage: "list.number") {
                if model.didCompleteRouteCalculation && model.routes.isEmpty {
                    Text("The local engine returned no covered route. Guidance remains unavailable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ForEach(model.routes) { route in
                    routeCard(route)
                }
            }
        }
    }

    private func routeCard(_ route: OfflineLocalRoute) -> some View {
        let maneuvers = OfflineRoadJourneyFormat.maneuvers(route)
        let isSelected = model.selectedRoute?.id == route.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(OfflineRoadJourneyFormat.distance(route.summary.distanceMeters)) · \(OfflineRoadJourneyFormat.duration(route.summary.durationSeconds))")
                        .font(.headline)
                    Text("\(route.sections.count) section\(route.sections.count == 1 ? "" : "s") · \(maneuvers.count) maneuver\(maneuvers.count == 1 ? "" : "s") · no traffic basis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
            }

            coverageEvidence(route.coverage, prefix: "Route corridor verified by")

            if !route.notices.isEmpty {
                DisclosureGroup("Route notices (\(route.notices.count))") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(route.notices.enumerated()), id: \.offset) { _, notice in
                            Text(notice)
                                .font(.callout)
                        }
                    }
                    .padding(.top, 6)
                }
            }

            DisclosureGroup("Maneuver summary (\(maneuvers.count))") {
                VStack(alignment: .leading, spacing: 8) {
                    if maneuvers.isEmpty {
                        Text("The native route returned no textual maneuver register.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(maneuvers) { row in
                        HStack(alignment: .top, spacing: 9) {
                            Text("\(row.ordinal)")
                                .font(.caption.monospacedDigit().bold())
                                .frame(width: 24, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.maneuver.instruction)
                                    .font(.callout)
                                if let distance = row.maneuver.distanceFromStartMeters {
                                    Text("At \(OfflineRoadJourneyFormat.distance(distance)) from origin")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }

            Button(isSelected ? "Route selected" : "Select this route") {
                model.selectRoute(route)
            }
            .buttonStyle(.bordered)
            .disabled(isSelected)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.green.opacity(0.10) : Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.green.opacity(0.55) : Color.secondary.opacity(0.18))
        )
        .accessibilityElement(children: .contain)
    }

    private var guidance: some View {
        journeySection(title: "Native guidance", systemImage: "speaker.wave.3.fill") {
            VStack(alignment: .leading, spacing: 6) {
                Text(OfflineRoadJourneyFormat.navigationState(composition.navigationState))
                    .font(.headline)
                Text(OfflineRoadJourneyFormat.navigationCoverage(composition.navigationCoverage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if let failure = composition.lastNavigationFailure {
                VStack(alignment: .leading, spacing: 5) {
                    Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)
                    if let recovery = failure.recovery {
                        Text(recovery)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !guidanceBlockers.isEmpty {
                Text(guidanceBlockers.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { guidanceButtons }
                VStack(spacing: 10) { guidanceButtons }
            }

            Text("Start guidance only while safely stopped. Native audio, rerouting, coverage checks, and continuous best-for-navigation location are owned by the app-scoped offline composition.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var guidanceButtons: some View {
        Button {
            model.startGuidance()
        } label: {
            Label("Start guidance", systemImage: "location.north.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            model.isBusy ||
            model.isPreparingPrincipal ||
            model.selectedRoute == nil ||
            !model.selectedRouteMatchesInputs ||
            model.navigationIsActive ||
            !guidanceBlockers.isEmpty
        )

        Button(role: .destructive) {
            model.stopGuidance()
        } label: {
            Label("Stop guidance", systemImage: "stop.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(model.isBusy || !model.navigationIsActive)
    }

    private func coverageEvidence(
        _ evidence: OfflineInstalledCoverageEvidence,
        prefix: String
    ) -> some View {
        Text("\(prefix) \(evidence.regionIDs.map(\.rawValue).joined(separator: ", ")).")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func journeySection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.16))
        )
    }
}

// MARK: - Production presentation model

private struct OfflineRoadJourneyPrincipalScope: Hashable, Sendable {
    let tenantID: String
    let userID: String
}

private enum OfflineRoadJourneyOperation: Equatable {
    case idle
    case locating
    case searching
    case calculatingRoute
    case startingGuidance
    case stoppingGuidance

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .locating: return "Waiting for a fresh precise location"
        case .searching: return "Searching verified installed HERE data"
        case .calculatingRoute: return "Calculating a covered local route"
        case .startingGuidance: return "Starting native offline guidance"
        case .stoppingGuidance: return "Stopping native guidance"
        }
    }
}

private struct OfflineRoadJourneyFailure: Identifiable, Equatable, Error {
    let id = UUID()
    let title: String
    let message: String
    let recovery: String?

    static func input(_ message: String, recovery: String? = nil) -> Self {
        Self(title: "Check journey input", message: message, recovery: recovery)
    }
}

private struct OfflineRoadJourneyTruckDraft: Equatable {
    var truckType: OfflineTruckType?
    var truckCategory: OfflineTruckCategory?
    var tunnelCategory: OfflineTruckTunnelCategory?
    var grossWeightKilograms = ""
    var weightPerAxleKilograms = ""
    var heightCentimeters = ""
    var widthCentimeters = ""
    var lengthCentimeters = ""
    var axleCount = ""
    var trailerCount = ""
    var hazardousGoods = Set<OfflineHazardousGoodsClass>()

    func constraints() throws -> OfflineTruckConstraints {
        guard let truckType else {
            throw OfflineRoadJourneyFailure.input(
                "Choose the truck type. EusoTrip will not let HERE invent one."
            )
        }
        guard let truckCategory else {
            throw OfflineRoadJourneyFailure.input(
                "Choose the truck restriction category. EusoTrip will not supply a default."
            )
        }
        return try OfflineTruckConstraints(
            truckType: truckType,
            truckCategory: truckCategory,
            tunnelCategory: tunnelCategory,
            grossWeightKilograms: try positiveInteger(grossWeightKilograms, field: "Gross weight"),
            weightPerAxleKilograms: try positiveInteger(weightPerAxleKilograms, field: "Weight per axle"),
            heightCentimeters: try positiveInteger(heightCentimeters, field: "Height"),
            widthCentimeters: try positiveInteger(widthCentimeters, field: "Width"),
            lengthCentimeters: try positiveInteger(lengthCentimeters, field: "Length"),
            axleCount: try positiveInteger(axleCount, field: "Axle count"),
            trailerCount: try nonnegativeInteger(trailerCount, field: "Trailer count"),
            hazardousGoods: hazardousGoods
        )
    }

    private func positiveInteger(_ text: String, field: String) throws -> Int? {
        try integer(text, field: field, permitsZero: false)
    }

    private func nonnegativeInteger(_ text: String, field: String) throws -> Int? {
        try integer(text, field: field, permitsZero: true)
    }

    private func integer(
        _ text: String,
        field: String,
        permitsZero: Bool
    ) throws -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.allSatisfy(\.isNumber),
              let parsed = Int(value),
              permitsZero ? parsed >= 0 : parsed > 0 else {
            throw OfflineRoadJourneyFailure.input(
                "\(field) must be a whole \(permitsZero ? "non-negative" : "positive") number in the displayed unit."
            )
        }
        return parsed
    }
}

private struct OfflineRoadJourneyRouteSignature: Equatable {
    let mode: OfflineRouteMode
    let destinationID: String
    let truckDraft: OfflineRoadJourneyTruckDraft?
}

@MainActor
private final class OfflineRoadJourneyViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var routeMode: OfflineRouteMode = .road {
        didSet {
            guard oldValue != routeMode else { return }
            invalidateCalculatedRoutes()
        }
    }
    @Published var truckDraft = OfflineRoadJourneyTruckDraft() {
        didSet {
            guard oldValue != truckDraft else { return }
            invalidateCalculatedRoutes()
        }
    }
    @Published private(set) var locationFix: OfflineRoadJourneyLocationFix?
    @Published private(set) var searchResults: [OfflineSearchResult] = []
    @Published private(set) var searchCoverage: OfflineInstalledCoverageEvidence?
    @Published private(set) var selectedDestination: OfflineSearchResult?
    @Published private(set) var routes: [OfflineLocalRoute] = []
    @Published private(set) var selectedRouteID: String?
    @Published private(set) var didCompleteSearch = false
    @Published private(set) var didCompleteRouteCalculation = false
    @Published private(set) var operation: OfflineRoadJourneyOperation = .idle
    @Published private(set) var failure: OfflineRoadJourneyFailure?
    @Published private(set) var hasBoundPrincipal = false
    @Published private(set) var isPreparingPrincipal = false

    private let composition: OfflineMapProductionComposition
    private let locationProvider: OfflineRoadJourneyCurrentLocationProvider
    private var activePrincipal: OfflineRoadJourneyPrincipalScope?
    private var operationTask: Task<Void, Never>?
    private var operationGeneration = UUID()
    private var calculatedRouteSignature: OfflineRoadJourneyRouteSignature?

    init(
        composition: OfflineMapProductionComposition,
        locationProvider: OfflineRoadJourneyCurrentLocationProvider? = nil
    ) {
        self.composition = composition
        self.locationProvider = locationProvider ?? OfflineRoadJourneyCurrentLocationProvider()
    }

    var hasSearchText: Bool { searchText.trimmedNonempty != nil }
    var isBusy: Bool { operation != .idle }

    var selectedRoute: OfflineLocalRoute? {
        guard let selectedRouteID else { return nil }
        return routes.first { $0.id == selectedRouteID }
    }

    var selectedRouteMatchesInputs: Bool {
        guard calculatedRouteSignature != nil else { return false }
        return calculatedRouteSignature == routeSignature
    }

    var navigationIsActive: Bool {
        switch composition.navigationState {
        case .starting, .navigating, .paused, .offRoute, .rerouting:
            return true
        case .idle, .arrived, .stopped, .failed:
            return false
        }
    }

    func bindPrincipal(_ scope: OfflineRoadJourneyPrincipalScope?) async {
        cancelPendingOperation()
        let changed = activePrincipal != scope
        activePrincipal = scope
        hasBoundPrincipal = false
        isPreparingPrincipal = true
        failure = nil
        if changed {
            clearJourneyState()
        }

        await composition.activatePrincipal(
            tenantID: scope?.tenantID,
            userID: scope?.userID
        )
        guard !Task.isCancelled, activePrincipal == scope else { return }

        guard scope != nil else {
            isPreparingPrincipal = false
            failure = OfflineRoadJourneyFailure(
                title: "Signed-in account required",
                message: "Offline journey data is account-scoped and cannot be opened without both a tenant and user identity.",
                recovery: "Sign in to the owning EusoTrip account, then reopen this surface."
            )
            return
        }

        hasBoundPrincipal = true
        await composition.prepare()
        guard !Task.isCancelled, activePrincipal == scope else { return }
        isPreparingPrincipal = false
    }

    func refreshLocation() {
        let generation = begin(.locating)
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fix = try await self.locationProvider.freshFix()
                try self.requireCurrent(generation)
                self.locationFix = fix
                self.finish(generation)
            } catch {
                self.fail(error, generation: generation)
            }
        }
    }

    func search() {
        guard let text = searchText.trimmedNonempty else {
            present(.input("Enter a place, category, or address to search installed HERE data."))
            return
        }
        guard let block = operationBlockReason(requireGuidance: false) else {
            let generation = begin(.searching)
            searchResults = []
            searchCoverage = nil
            selectedDestination = nil
            didCompleteSearch = false
            invalidateCalculatedRoutes()
            operationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let fix = try await self.locationProvider.freshFix()
                    try self.requireCurrent(generation)
                    self.locationFix = fix
                    let response = try await self.composition.searchOffline(
                        text: text,
                        center: fix.coordinate,
                        maximumResultCount: 20
                    )
                    try self.requireCurrent(generation)
                    guard self.searchText.trimmedNonempty == text else {
                        throw CancellationError()
                    }
                    guard Set(response.results.map(\.id)).count == response.results.count else {
                        throw OfflineRoadJourneyFailure(
                            title: "Search result identity invalid",
                            message: "The local HERE search returned duplicate result identities, so no destination can be selected safely.",
                            recovery: "Reinitialize the offline engine and retry."
                        )
                    }
                    self.searchResults = response.results
                    self.searchCoverage = response.coverage
                    self.didCompleteSearch = true
                    self.finish(generation)
                } catch {
                    self.fail(error, generation: generation)
                }
            }
            return
        }
        present(block)
    }

    func selectDestination(_ result: OfflineSearchResult) {
        guard searchResults.contains(where: { $0.id == result.id }) else { return }
        selectedDestination = result
        invalidateCalculatedRoutes()
    }

    func setHazard(_ hazard: OfflineHazardousGoodsClass, selected: Bool) {
        if selected {
            truckDraft.hazardousGoods.insert(hazard)
        } else {
            truckDraft.hazardousGoods.remove(hazard)
        }
    }

    func calculateRoute() {
        guard let destination = selectedDestination else {
            present(.input("Select a verified installed-data search result as the destination."))
            return
        }
        guard let block = operationBlockReason(requireGuidance: false) else {
            do {
                let constraints = routeMode == .truck ? try truckDraft.constraints() : nil
                let requestedMode = routeMode
                let signature = routeSignature
                let generation = begin(.calculatingRoute)
                routes = []
                selectedRouteID = nil
                calculatedRouteSignature = nil
                didCompleteRouteCalculation = false
                operationTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let fix = try await self.locationProvider.freshFix()
                        try self.requireCurrent(generation)
                        self.locationFix = fix
                        let response = try await self.composition.calculateOfflineRoute(
                            waypoints: [
                                OfflineRouteWaypoint(
                                    coordinate: fix.coordinate,
                                    label: "Current device location"
                                ),
                                OfflineRouteWaypoint(
                                    coordinate: destination.coordinate,
                                    label: destination.title
                                )
                            ],
                            mode: requestedMode,
                            truckConstraints: constraints,
                            departureTime: Date()
                        )
                        try self.requireCurrent(generation)
                        guard signature == self.routeSignature else {
                            throw CancellationError()
                        }
                        guard Set(response.routes.map(\.id)).count == response.routes.count else {
                            throw OfflineRoadJourneyFailure(
                                title: "Route identity invalid",
                                message: "The local HERE engine returned duplicate route identities, so no alternative can be selected safely.",
                                recovery: "Reinitialize the offline engine and calculate the route again."
                            )
                        }
                        self.routes = response.routes
                        self.calculatedRouteSignature = signature
                        self.didCompleteRouteCalculation = true
                        self.finish(generation)
                    } catch {
                        self.fail(error, generation: generation)
                    }
                }
            } catch {
                present(Self.presentation(for: error))
            }
            return
        }
        present(block)
    }

    func selectRoute(_ route: OfflineLocalRoute) {
        guard routes.contains(where: { $0.id == route.id }),
              calculatedRouteSignature == routeSignature else {
            present(.input("Route inputs changed. Calculate the route again before selecting it."))
            return
        }
        selectedRouteID = route.id
    }

    func startGuidance() {
        guard let route = selectedRoute else {
            present(.input("Select one calculated route before starting guidance."))
            return
        }
        guard selectedRouteMatchesInputs else {
            present(.input("Route inputs changed. Calculate and select a fresh route before starting guidance."))
            return
        }
        guard let block = operationBlockReason(requireGuidance: true) else {
            let generation = begin(.startingGuidance)
            operationTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.composition.startNavigation(route: route)
                    try self.requireCurrent(generation)
                    self.finish(generation)
                } catch {
                    self.fail(error, generation: generation)
                }
            }
            return
        }
        present(block)
    }

    func stopGuidance() {
        guard navigationIsActive else { return }
        let generation = begin(.stoppingGuidance)
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.composition.stopNavigation()
            guard !Task.isCancelled else { return }
            self.finish(generation)
        }
    }

    func cancelPendingOperation() {
        operationGeneration = UUID()
        operationTask?.cancel()
        operationTask = nil
        locationProvider.cancelActiveRequest()
        operation = .idle
    }

    func dismissFailure() {
        failure = nil
    }

    private var routeSignature: OfflineRoadJourneyRouteSignature? {
        guard let destinationID = selectedDestination?.id else { return nil }
        return OfflineRoadJourneyRouteSignature(
            mode: routeMode,
            destinationID: destinationID,
            truckDraft: routeMode == .truck ? truckDraft : nil
        )
    }

    private func operationBlockReason(requireGuidance: Bool) -> OfflineRoadJourneyFailure? {
        let blockers = OfflineRoadJourneyReadiness.blockers(
            composition: composition,
            snapshot: composition.owner.snapshot,
            hasBoundPrincipal: hasBoundPrincipal,
            mode: routeMode,
            requireGuidance: requireGuidance
        )
        guard !blockers.isEmpty else { return nil }
        return OfflineRoadJourneyFailure(
            title: requireGuidance ? "Guidance blocked" : "Offline journey blocked",
            message: blockers.joined(separator: " "),
            recovery: "Return to the on-device map library and clear every named blocker before retrying."
        )
    }

    private func begin(_ nextOperation: OfflineRoadJourneyOperation) -> UUID {
        cancelPendingOperation()
        let generation = UUID()
        operationGeneration = generation
        operation = nextOperation
        failure = nil
        return generation
    }

    private func requireCurrent(_ generation: UUID) throws {
        guard operationGeneration == generation,
              !Task.isCancelled,
              activePrincipal != nil else {
            throw CancellationError()
        }
    }

    private func finish(_ generation: UUID) {
        guard operationGeneration == generation else { return }
        operationTask = nil
        operation = .idle
    }

    private func fail(_ error: Error, generation: UUID) {
        guard operationGeneration == generation else { return }
        operationTask = nil
        operation = .idle
        guard !(error is CancellationError) else { return }
        failure = Self.presentation(for: error)
    }

    private func present(_ failure: OfflineRoadJourneyFailure) {
        self.failure = failure
    }

    private func invalidateCalculatedRoutes() {
        routes = []
        selectedRouteID = nil
        calculatedRouteSignature = nil
        didCompleteRouteCalculation = false
    }

    private func clearJourneyState() {
        locationFix = nil
        searchResults = []
        searchCoverage = nil
        selectedDestination = nil
        didCompleteSearch = false
        invalidateCalculatedRoutes()
    }

    private static func presentation(for error: Error) -> OfflineRoadJourneyFailure {
        if let failure = error as? OfflineRoadJourneyFailure {
            return failure
        }
        if let failure = error as? OfflineNavigationFailure {
            return OfflineRoadJourneyFailure(
                title: "Native guidance unavailable",
                message: failure.message,
                recovery: failure.recovery
            )
        }
        if let failure = error as? any OfflineMapFailureProviding {
            let detail = failure.offlineMapFailure
            return OfflineRoadJourneyFailure(
                title: "Local HERE operation failed",
                message: detail.message,
                recovery: detail.recovery
            )
        }
        if let core = error as? OfflineMapCoreError {
            return OfflineRoadJourneyFailure(
                title: "Offline journey unavailable",
                message: core.errorDescription ?? "The local map safety contract rejected this operation.",
                recovery: "Review installed coverage, persistent-map health, and Radio Silent status."
            )
        }
        return OfflineRoadJourneyFailure(
            title: "Offline journey unavailable",
            message: "The local route operation failed a device, coverage, or native-engine check.",
            recovery: "Review the map library and retry from a safe stop. No online fallback was attempted."
        )
    }
}

// MARK: - Fresh current-device location

private struct OfflineRoadJourneyLocationFix: Sendable {
    let coordinate: OfflineGeoCoordinate
    let timestamp: Date
    let horizontalAccuracyMeters: Double
    let provenance: OfflineLocationProvenance
}

@MainActor
private final class OfflineRoadJourneyCurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    private static let maximumAgeSeconds: TimeInterval = 15
    private static let maximumHorizontalAccuracyMeters: CLLocationAccuracy = 65
    private static let requestTimeoutNanoseconds: UInt64 = 20_000_000_000

    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<OfflineRoadJourneyLocationFix, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var isUpdating = false

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    func freshFix() async throws -> OfflineRoadJourneyLocationFix {
        guard continuation == nil else {
            throw OfflineRoadJourneyFailure(
                title: "Location request already active",
                message: "A precise current-device location request is already in progress.",
                recovery: "Wait for that request or cancel it before retrying."
            )
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: Self.requestTimeoutNanoseconds)
                    } catch {
                        return
                    }
                    self?.finish(
                        .failure(
                            OfflineRoadJourneyFailure(
                                title: "Precise location unavailable",
                                message: "No fresh current-device fix reached ±\(Int(Self.maximumHorizontalAccuracyMeters)) meters before the safety timeout.",
                                recovery: "Move to a clear view of the sky, confirm Precise Location is enabled, and retry."
                            )
                        )
                    )
                }
                self.beginLocationRequest()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelActiveRequest()
            }
        }
    }

    func cancelActiveRequest() {
        guard continuation != nil else { return }
        finish(.failure(CancellationError()))
    }

    private func beginLocationRequest() {
        guard CLLocationManager.locationServicesEnabled() else {
            finish(
                .failure(
                    OfflineRoadJourneyFailure(
                        title: "Location Services disabled",
                        message: "A real current-device origin is required for offline search and routing.",
                        recovery: "Enable Location Services and Precise Location for EusoTrip."
                    )
                )
            )
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(
                .failure(
                    OfflineRoadJourneyFailure(
                        title: "Location permission unavailable",
                        message: "EusoTrip cannot establish a current-device origin without location permission.",
                        recovery: "Allow Precise Location for EusoTrip in Settings."
                    )
                )
            )
        case .authorizedAlways, .authorizedWhenInUse:
            guard manager.accuracyAuthorization == .fullAccuracy else {
                finish(
                    .failure(
                        OfflineRoadJourneyFailure(
                            title: "Precise Location disabled",
                            message: "Reduced-accuracy location cannot authorize this offline journey origin.",
                            recovery: "Enable Precise Location for EusoTrip and retry."
                        )
                    )
                )
                return
            }
            guard !isUpdating else { return }
            isUpdating = true
            manager.startUpdatingLocation()
        @unknown default:
            finish(
                .failure(
                    OfflineRoadJourneyFailure(
                        title: "Location authorization unknown",
                        message: "The device did not provide a verifiable location authorization state.",
                        recovery: "Review EusoTrip location permission in Settings and retry."
                    )
                )
            )
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.accept(location)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.continuation != nil else { return }
            if (error as? CLError)?.code == .locationUnknown {
                return
            }
            self.finish(
                .failure(
                    OfflineRoadJourneyFailure(
                        title: "Current location failed",
                        message: (error as? CLError)?.code == .denied
                            ? "Location permission was withdrawn before a current-device fix was established."
                            : "Core Location could not establish a fresh, precise device fix.",
                        recovery: "Confirm Precise Location, move to a clear GNSS view, and retry."
                    )
                )
            )
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _: CLLocationManager
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.continuation != nil else { return }
            self.beginLocationRequest()
        }
    }

    private func accept(_ location: CLLocation) {
        guard continuation != nil else { return }
        guard manager.accuracyAuthorization == .fullAccuracy else {
            finish(
                .failure(
                    OfflineRoadJourneyFailure(
                        title: "Precise Location disabled",
                        message: "Location accuracy changed before the journey origin was established.",
                        recovery: "Restore Precise Location and retry."
                    )
                )
            )
            return
        }
        if location.sourceInformation?.isSimulatedBySoftware == true {
            finish(
                .failure(
                    OfflineRoadJourneyFailure(
                        title: "Simulated location rejected",
                        message: "A simulated coordinate cannot authorize a production offline journey.",
                        recovery: "Use a physical device with a real Precise Location fix."
                    )
                )
            )
            return
        }

        let age = Date().timeIntervalSince(location.timestamp)
        guard age >= -5, age <= Self.maximumAgeSeconds,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maximumHorizontalAccuracyMeters else {
            return
        }

        do {
            let coordinate = try OfflineGeoCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            let provenance: OfflineLocationProvenance =
                location.sourceInformation?.isProducedByAccessory == true
                ? .externalGNSS
                : .deviceFusedLocation
            finish(
                .success(
                    OfflineRoadJourneyLocationFix(
                        coordinate: coordinate,
                        timestamp: location.timestamp,
                        horizontalAccuracyMeters: location.horizontalAccuracy,
                        provenance: provenance
                    )
                )
            )
        } catch {
            finish(
                .failure(
                    OfflineRoadJourneyFailure(
                        title: "Invalid device location",
                        message: "Core Location returned a coordinate outside the accepted geographic range.",
                        recovery: "Wait for a new device fix and retry."
                    )
                )
            )
        }
    }

    private func finish(_ result: Result<OfflineRoadJourneyLocationFix, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        if isUpdating {
            manager.stopUpdatingLocation()
            isUpdating = false
        }
        continuation.resume(with: result)
    }
}

// MARK: - Readiness and text

@MainActor
private enum OfflineRoadJourneyReadiness {
    static func blockers(
        composition: OfflineMapProductionComposition,
        snapshot: OfflineMapSnapshot,
        hasBoundPrincipal: Bool,
        mode: OfflineRouteMode,
        requireGuidance: Bool
    ) -> [String] {
        var values: [String] = []
        if !hasBoundPrincipal {
            values.append("A signed-in tenant and user must be bound before local route data can be used.")
        }
        if !composition.installedCoverageTrustAvailable {
            values.append(
                composition.installedCoverageFailure
                    ?? "Signed installed-region coverage authority is unavailable."
            )
        }
        switch snapshot.readiness {
        case .unchecked:
            values.append("The native HERE engine has not completed its readiness check.")
        case .checking:
            values.append("The native HERE engine readiness check is still running.")
        case .blocked(let engineBlockers):
            values.append(contentsOf: engineBlockers.map(\.message))
        case .limited, .ready:
            break
        }
        if snapshot.connectivityPolicy != .radioSilent {
            values.append("Radio Silent must be selected before this surface can run.")
        }
        if snapshot.radioSilenceState != .enforced {
            values.append("The native SDK has not proven Radio Silent enforcement.")
        }
        if !snapshot.persistentHealth.permitsRegionMutation {
            values.append("Persistent map health is not verified as healthy.")
        }
        if !snapshot.installedRegionsState.isCurrent {
            values.append("Installed-region inventory is not current on this device.")
        } else if !snapshot.installedRegions.contains(where: { $0.state.isUsableCoverage }) {
            values.append("No verified usable HERE region is installed.")
        }
        if snapshot.activeOperation != nil {
            values.append("Finish or cancel the active map-library operation first.")
        }

        var required: OfflineMapCapabilities = [
            .offlineSearch,
            mode == .truck ? .offlineTruckRouting : .offlineRoadRouting,
            .radioSilence
        ]
        if requireGuidance {
            required.formUnion([.offlineGuidance, .offlineVoiceGuidance])
        }
        let missing = required.subtracting(snapshot.availableCapabilities)
        if !missing.isEmpty {
            values.append("This build has not proven every required local \(requireGuidance ? "guidance" : "search and routing") capability.")
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

private enum OfflineRoadJourneyFormat {
    static func maneuvers(_ route: OfflineLocalRoute) -> [OfflineRoadJourneyManeuverRow] {
        var rows: [OfflineRoadJourneyManeuverRow] = []
        for (sectionIndex, section) in route.sections.enumerated() {
            for maneuver in section.maneuvers.sorted(by: { $0.sequence < $1.sequence }) {
                rows.append(
                    OfflineRoadJourneyManeuverRow(
                        id: "\(sectionIndex):\(maneuver.sequence)",
                        ordinal: rows.count + 1,
                        maneuver: maneuver
                    )
                )
            }
        }
        return rows
    }

    static func coordinate(_ coordinate: OfflineGeoCoordinate) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    static func meters(_ value: Double) -> String {
        value < 1_000
            ? "\(Int(value.rounded())) m"
            : String(format: "%.1f km", value / 1_000)
    }

    static func distance(_ meters: Int64) -> String {
        meters < 1_000
            ? "\(meters) m"
            : String(format: "%.1f km", Double(meters) / 1_000)
    }

    static func duration(_ seconds: Int64) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 { return "\(hours) hr \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(seconds) sec"
    }

    static func navigationState(_ state: OfflineNavigationSessionState) -> String {
        switch state {
        case .idle:
            return "Guidance idle"
        case .starting:
            return "Starting guidance"
        case .navigating:
            return "Guidance active"
        case .paused(_, let reason):
            return "Guidance paused · \(reason)"
        case .offRoute(_, let deviation):
            return "Off route · \(Int(deviation.crossTrackMeters.rounded())) m cross-track"
        case .rerouting:
            return "Calculating an offline reroute"
        case .arrived(_, let date):
            return "Arrived \(date.formatted(.relative(presentation: .named)))"
        case .stopped(_, let date):
            return "Guidance stopped \(date.formatted(.relative(presentation: .named)))"
        case .failed(_, let failure):
            return "Guidance failed · \(failure.message)"
        }
    }

    static func navigationCoverage(_ coverage: OfflineNavigationCoverage) -> String {
        switch coverage {
        case .verified(let evidence):
            return "Corridor coverage verified by \(evidence.regionIDs.map(\.rawValue).joined(separator: ", "))."
        case .approachingBoundary(let evidence, let distance):
            let distanceText = distance.map { " in \(OfflineRoadJourneyFormat.distance($0))" } ?? ""
            return "Approaching the verified boundary\(distanceText); last covered by \(evidence.regionIDs.map(\.rawValue).joined(separator: ", "))."
        case .outsideInstalledCoverage(let evidence):
            let regions = evidence?.regionIDs.map(\.rawValue).joined(separator: ", ")
            return regions.map { "Outside installed coverage; last covered by \($0)." }
                ?? "Outside installed coverage; no last-covered region is available."
        case .unknown:
            return "Navigation coverage has not been verified for the active session."
        }
    }
}

private struct OfflineRoadJourneyManeuverRow: Identifiable {
    let id: String
    let ordinal: Int
    let maneuver: OfflineRouteManeuver
}

private extension String {
    var trimmedNonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension OfflineLocationProvenance {
    var title: String {
        switch self {
        case .deviceGNSS: return "Device GNSS fix"
        case .deviceFusedLocation: return "Precise device-fused fix"
        case .externalGNSS: return "External GNSS fix"
        case .simulated: return "Simulated fix"
        case .unknown: return "Unknown location source"
        }
    }
}

private extension OfflineTruckType {
    var title: String {
        switch self {
        case .straight: return "Straight truck"
        case .tractor: return "Tractor"
        }
    }
}

private extension OfflineTruckCategory {
    var title: String {
        switch self {
        case .straight: return "Straight-truck restrictions"
        case .tractor: return "Tractor restrictions"
        }
    }
}

private extension OfflineHazardousGoodsClass {
    var title: String {
        switch self {
        case .explosive: return "Explosives"
        case .gas: return "Gas"
        case .flammable: return "Flammable"
        case .combustible: return "Combustible"
        case .organic: return "Organic substances"
        case .poison: return "Poison"
        case .radioActive: return "Radioactive"
        case .corrosive: return "Corrosive"
        case .poisonousInhalation: return "Poisonous by inhalation"
        case .harmfulToWater: return "Harmful to water"
        case .other: return "Other regulated goods"
        }
    }
}

private extension View {
    @ViewBuilder
    func offlineRoadJourneyNavigationTitle() -> some View {
        #if os(iOS)
        navigationTitle("Offline journey")
            .navigationBarTitleDisplayMode(.inline)
        #else
        navigationTitle("Offline journey")
        #endif
    }
}
