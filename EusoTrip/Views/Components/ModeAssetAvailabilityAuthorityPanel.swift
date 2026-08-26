//
//  ModeAssetAvailabilityAuthorityPanel.swift
//  EusoTrip
//
//  One owned capacity surface for Truck, Rail, and Vessel. Asset identity,
//  licensed observation evidence, and optional route-profile identity come
//  only from the tenant-scoped server prerequisite authority. Operators enter
//  commercial terms; they never type hidden database identifiers.
//

import SwiftUI

struct ModeAssetAvailabilityLaunchCard: View {
    let mode: PricedRouteCommerceClient.Mode

    @Environment(\.palette) private var palette
    @State private var showingAuthority = false
    @State private var offers: [PricedRouteCommerceClient.AvailabilityOffer] = []
    @State private var prerequisites: [PricedRouteCommerceClient.AvailabilityPublishPrerequisite] = []
    @State private var loading = true
    @State private var errorMessage: String?

    private let client = PricedRouteCommerceClient.shared

    var body: some View {
        LifecycleCard(accentGradient: activeOffers > 0) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s2) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                        Image(systemName: modeIcon)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(mode.accessibilityLabel.uppercased()) · OWNED CAPACITY")
                            .font(EType.micro.weight(.heavy))
                            .tracking(0.8)
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(modeHeadline)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer(minLength: Space.s2)
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(activeOffers > 0 ? "\(activeOffers) LIVE" : "NOT LIVE")
                            .font(EType.micro.weight(.heavy))
                            .tracking(0.5)
                            .foregroundStyle(activeOffers > 0 ? Brand.success : Brand.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((activeOffers > 0 ? Brand.success : Brand.warning).opacity(0.10))
                            .clipShape(Capsule())
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: Space.s2) {
                        metric("READY", "\(readyAssets)", Brand.success)
                        metric("BLOCKED", "\(blockedAssets)", blockedAssets > 0 ? Brand.warning : palette.textSecondary)
                        metric("ALLOCATED", "\(allocatedOffers)", allocatedOffers > 0 ? Brand.blue : palette.textSecondary)
                    }
                    Text(summaryCopy)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showingAuthority = true
                } label: {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text(manageLabel)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s3)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens licensed position evidence, mode-native terms, published offers, and allocation truth")
            }
        }
        .task { await refresh() }
        .sheet(isPresented: $showingAuthority, onDismiss: { Task { await refresh() } }) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    ModeAssetAvailabilityAuthorityPanel(mode: mode)
                        .padding(.horizontal, 14)
                        .padding(.vertical, Space.s3)
                }
                .background(palette.bgPage.ignoresSafeArea())
                .navigationTitle("Owned \(mode.accessibilityLabel) capacity")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showingAuthority = false }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(mode.accessibilityLabel) owned capacity authority")
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            async let currentOffers = client.listAvailability(mode: mode)
            async let currentPrerequisites = client.listAvailabilityPublishPrerequisites(mode: mode)
            offers = try await currentOffers
            prerequisites = try await currentPrerequisites.assets
            errorMessage = nil
        } catch {
            errorMessage = error.eusoUserCopy
        }
    }

    private var activeOffers: Int {
        offers.filter { $0.state == "available" || $0.state == "scheduled" }.count
    }

    private var allocatedOffers: Int {
        offers.filter { $0.currentAllocation != nil }.count
    }

    private var readyAssets: Int { prerequisites.filter(\.readyToPublish).count }
    private var blockedAssets: Int { prerequisites.filter { !$0.readyToPublish }.count }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(EType.micro.weight(.heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(EType.h2.monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var modeIcon: String {
        switch mode {
        case .truck: return "truck.box.fill"
        case .rail: return "tram.fill"
        case .vessel: return "ferry.fill"
        }
    }

    private var modeHeadline: String {
        switch mode {
        case .truck: return "Truck availability with deadhead ownership"
        case .rail: return "Railcar and consist capacity with positioning truth"
        case .vessel: return "Vessel capacity with laycan and ballast truth"
        }
    }

    private var manageLabel: String {
        switch mode {
        case .truck: return "Make my truck available"
        case .rail: return "Make rail capacity available"
        case .vessel: return "Make vessel capacity available"
        }
    }

    private var summaryCopy: String {
        switch mode {
        case .truck:
            return "Only an owned truck with a current licensed GNSS or ELD observation can publish. Deadhead range and responsibility remain explicit."
        case .rail:
            return "A railcar or consist publishes from authorized rail evidence with interchange, positioning, and empty-return terms—not a truck assumption."
        case .vessel:
            return "A vessel publishes from authorized AIS or terminal evidence with laycan, port range, draught, DWT, ballast, and approach terms."
        }
    }
}

struct ModeAssetAvailabilityAuthorityPanel: View {
    let mode: PricedRouteCommerceClient.Mode

    @Environment(\.palette) private var palette
    @State private var prerequisites: [PricedRouteCommerceClient.AvailabilityPublishPrerequisite] = []
    @State private var offers: [PricedRouteCommerceClient.AvailabilityOffer] = []
    @State private var selectedAssetKey: String?
    @State private var loading = true
    @State private var publishing = false
    @State private var withdrawingOfferId: String?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var withdrawalReasons: [String: String] = [:]

    @State private var availableFrom = Date()
    @State private var availableUntil = Date().addingTimeInterval(24 * 60 * 60)
    @State private var offerWindowConfirmed = false

    @State private var truckEquipmentTypes = ""
    @State private var truckPayloadKg = ""
    @State private var truckRadiusMiles = ""
    @State private var truckDeadheadMiles = ""
    @State private var truckRegions = ""
    @State private var truckRestrictions = ""
    @State private var deadheadResponsibility: PricedRouteCommerceClient.Responsibility?

    @State private var railCapacityKg = ""
    @State private var railVolumeCubicMeters = ""
    @State private var railInterchanges = ""
    @State private var railCommodityRestrictions = ""
    @State private var railClearanceRestrictions = ""
    @State private var positioningResponsibility: PricedRouteCommerceClient.Responsibility?
    @State private var emptyReturnResponsibility: PricedRouteCommerceClient.Responsibility?

    @State private var laycanStart = Date()
    @State private var laycanEnd = Date().addingTimeInterval(48 * 60 * 60)
    @State private var laycanConfirmed = false
    @State private var vesselPortRange = ""
    @State private var vesselMaximumDraughtMeters = ""
    @State private var vesselAvailableDWT = ""
    @State private var vesselCargoRestrictions = ""
    @State private var ballastResponsibility: PricedRouteCommerceClient.VesselAvailabilityTerms.CharterResponsibility?
    @State private var portApproachResponsibility: PricedRouteCommerceClient.VesselAvailabilityTerms.PortApproachResponsibility?

    private let client = PricedRouteCommerceClient.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            authorityHeader

            if loading && prerequisites.isEmpty && offers.isEmpty {
                LifecycleCard {
                    HStack(spacing: Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Reading owned assets and licensed evidence…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }

            if let errorMessage {
                LifecycleCard(accentDanger: true) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let statusMessage {
                LifecycleCard(accentGradient: true) {
                    Label(statusMessage, systemImage: "checkmark.seal.fill")
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            publishCard
            publishedOffers
        }
        .task { await refresh() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(mode.accessibilityLabel) mode-native availability authority")
    }

    private var authorityHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("FOUNDATION, NOT BOUNDARY · OWNED CAPACITY")
                .font(EType.micro.weight(.heavy))
                .tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(authorityTitle)
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            Text(authorityExplanation)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var publishCard: some View {
        LifecycleCard(accentGradient: selectedPrerequisite?.readyToPublish == true) {
            VStack(alignment: .leading, spacing: Space.s3) {
                LifecycleSection(label: "PUBLISH OWNED CAPACITY", icon: "dot.radiowaves.up.forward")

                if prerequisites.isEmpty && !loading {
                    Text("No company-owned \(assetPlural) are discoverable for this account. Nothing has been invented or published.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !prerequisites.isEmpty {
                    assetPicker
                    if let prerequisite = selectedPrerequisite {
                        prerequisiteTruth(prerequisite)
                        Divider().overlay(palette.borderFaint)
                        availabilityWindow
                        modeTerms(prerequisite)
                        publishButton(prerequisite)
                    }
                }
            }
        }
    }

    private var assetPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("OWNED ASSET")
            Picker("Owned asset", selection: selectedAssetBinding) {
                ForEach(prerequisites) { prerequisite in
                    Text("\(prerequisite.displayName) · \(prerequisite.operationalState.replacingOccurrences(of: "_", with: " "))")
                        .tag(Optional(prerequisite.assetIdentityKey))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func prerequisiteTruth(
        _ prerequisite: PricedRouteCommerceClient.AvailabilityPublishPrerequisite
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prerequisite.displayName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(prerequisite.detail)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s2)
                statePill(prerequisite.readyToPublish ? "EVIDENCE READY" : "BLOCKED",
                          color: prerequisite.readyToPublish ? Brand.success : Brand.warning)
            }

            if let observation = prerequisite.observation {
                HStack(spacing: Space.s2) {
                    evidenceMetric("POSITION", observation.freshness.uppercased())
                    evidenceMetric("AGE", "\(observation.ageSeconds)s")
                    evidenceMetric("QUALITY", observation.qualityState.replacingOccurrences(of: "_", with: " ").uppercased())
                }
                Text("\(observation.providerId) · \(observation.sourceClass.replacingOccurrences(of: "_", with: " ")) · \(observation.licenseName) v\(observation.licenseVersion)")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Evidence \(shortHash(observation.evidenceHashSha256)) · provenance \(shortHash(observation.provenanceHashSha256))")
                    .font(EType.micro.monospaced())
                    .foregroundStyle(palette.textTertiary)
            } else {
                Label("No licensed operational position is available.", systemImage: "location.slash.fill")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }

            ForEach(prerequisite.blockers) { blocker in
                VStack(alignment: .leading, spacing: 2) {
                    Label(blocker.message, systemImage: "exclamationmark.triangle.fill")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(Brand.warning)
                    Text(blocker.recovery)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var availabilityWindow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            fieldLabel("OFFER WINDOW")
            DatePicker("Available from", selection: $availableFrom)
                .font(EType.caption)
            DatePicker("Available until", selection: $availableUntil, in: availableFrom...)
                .font(EType.caption)
            Toggle("I confirm this exact availability window", isOn: $offerWindowConfirmed)
                .font(EType.caption)
                .tint(Brand.blue)
                .accessibilityHint("Required before publishing capacity")
        }
    }

    @ViewBuilder
    private func modeTerms(
        _ prerequisite: PricedRouteCommerceClient.AvailabilityPublishPrerequisite
    ) -> some View {
        switch mode {
        case .truck:
            truckTerms
        case .rail:
            railTerms(prerequisite)
        case .vessel:
            vesselTerms
        }
    }

    private var truckTerms: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            fieldLabel("TRUCK COMMERCIAL TERMS")
            input("Equipment types (comma separated)", text: $truckEquipmentTypes)
            HStack(spacing: Space.s2) {
                input("Payload kg", text: $truckPayloadKg, numeric: true)
                input("Service radius mi", text: $truckRadiusMiles, numeric: true)
            }
            input("Maximum deadhead mi", text: $truckDeadheadMiles, numeric: true)
            input("Operating regions", text: $truckRegions)
            input("Restrictions (optional)", text: $truckRestrictions)
            responsibilityPicker("Deadhead paid by", selection: $deadheadResponsibility)
        }
    }

    private func railTerms(
        _ prerequisite: PricedRouteCommerceClient.AvailabilityPublishPrerequisite
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            fieldLabel(prerequisite.asset.assetType == "railcar" ? "RAILCAR COMMERCIAL TERMS" : "CONSIST COMMERCIAL TERMS")
            HStack(spacing: Space.s2) {
                input("Capacity kg", text: $railCapacityKg, numeric: true)
                input("Volume m³", text: $railVolumeCubicMeters, numeric: true)
            }
            input("Interchange points", text: $railInterchanges)
            input("Commodity restrictions (optional)", text: $railCommodityRestrictions)
            input("Clearance restrictions (optional)", text: $railClearanceRestrictions)
            responsibilityPicker("Positioning paid by", selection: $positioningResponsibility)
            responsibilityPicker("Empty return paid by", selection: $emptyReturnResponsibility)
        }
    }

    private var vesselTerms: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            fieldLabel("VESSEL COMMERCIAL TERMS")
            DatePicker("Laycan opens", selection: $laycanStart)
                .font(EType.caption)
            DatePicker("Laycan closes", selection: $laycanEnd, in: laycanStart...)
                .font(EType.caption)
            Toggle("I confirm this exact laycan", isOn: $laycanConfirmed)
                .font(EType.caption)
                .tint(Brand.blue)
                .accessibilityHint("Required before publishing vessel capacity")
            input("Port range UN/LOCODEs", text: $vesselPortRange)
            HStack(spacing: Space.s2) {
                input("Maximum draught m", text: $vesselMaximumDraughtMeters, numeric: true)
                input("Available DWT", text: $vesselAvailableDWT, numeric: true)
            }
            input("Cargo restrictions (optional)", text: $vesselCargoRestrictions)
            enumPicker("Ballast paid by", selection: $ballastResponsibility)
            enumPicker("Port approach paid by", selection: $portApproachResponsibility)
        }
    }

    private func publishButton(
        _ prerequisite: PricedRouteCommerceClient.AvailabilityPublishPrerequisite
    ) -> some View {
        Button {
            Task { await publish(prerequisite) }
        } label: {
            HStack(spacing: Space.s2) {
                if publishing {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "dot.radiowaves.up.forward")
                }
                Text(publishLabel)
                Spacer()
                Image(systemName: "lock.shield.fill")
            }
            .font(EType.bodyStrong)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .background(prerequisite.readyToPublish ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(publishing || !prerequisite.readyToPublish || !termsAreValid(prerequisite))
        .opacity(prerequisite.readyToPublish && termsAreValid(prerequisite) ? 1 : 0.55)
        .accessibilityHint("Publishes only the selected owned asset, licensed observation, window, and mode-native commercial terms")
    }

    private var publishedOffers: some View {
        LifecycleCard(accentGradient: offers.contains(where: { $0.state == "available" })) {
            VStack(alignment: .leading, spacing: Space.s3) {
                LifecycleSection(label: "PUBLISHED + ALLOCATED TRUTH", icon: "list.bullet.clipboard.fill")
                if offers.isEmpty && !loading {
                    Text("No \(mode.accessibilityLabel.lowercased()) capacity offer is recorded for this company.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(offers) { offer in
                        offerCard(offer)
                    }
                }
            }
        }
    }

    private func offerCard(_ offer: PricedRouteCommerceClient.AvailabilityOffer) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: offer))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("VERSION \(offer.version) · \(shortHash(offer.availabilityHashSha256))")
                        .font(EType.micro.monospaced())
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: Space.s2)
                statePill(offer.state.uppercased(), color: offerColor(offer))
            }

            HStack(spacing: Space.s2) {
                evidenceMetric("FRESHNESS", offer.freshness.uppercased())
                evidenceMetric("WINDOW", compactWindow(offer))
                evidenceMetric("ALLOCATION", offer.currentAllocation?.state.uppercased() ?? "OPEN")
            }

            if let allocation = offer.currentAllocation {
                Text("Allocation \(allocation.state) · version \(allocation.version) · receipt \(shortHash(allocation.allocationHashSha256)). Every change requires a confirmed allocation action.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if offer.state == "available" || offer.state == "scheduled" {
                input("Reason to withdraw", text: withdrawalBinding(for: offer.offerPublicId))
                Button {
                    Task { await withdraw(offer) }
                } label: {
                    HStack(spacing: Space.s2) {
                        if withdrawingOfferId == offer.offerId {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "pause.circle.fill")
                        }
                        Text("Withdraw capacity")
                    }
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
                .disabled(withdrawingOfferId != nil || withdrawalReason(for: offer).isEmpty)
                .accessibilityHint("Creates a new immutable withdrawn version; it does not delete history")
            }
        }
        .padding(Space.s3)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            async let serverPrerequisites = client.listAvailabilityPublishPrerequisites(mode: mode)
            async let serverOffers = client.listAvailability(mode: mode)
            let (prerequisiteList, offerList) = try await (serverPrerequisites, serverOffers)
            prerequisites = prerequisiteList.assets
            offers = offerList
            if selectedAssetKey == nil || !prerequisites.contains(where: { $0.assetIdentityKey == selectedAssetKey }) {
                selectedAssetKey = prerequisites.first(where: \.readyToPublish)?.assetIdentityKey
                    ?? prerequisites.first?.assetIdentityKey
            }
            errorMessage = nil
        } catch {
            errorMessage = error.eusoUserCopy
        }
    }

    private func publish(
        _ prerequisite: PricedRouteCommerceClient.AvailabilityPublishPrerequisite
    ) async {
        guard let asset = prerequisite.asset.asset,
              let observation = prerequisite.observation,
              let liveObservationId = observation.liveObservationId else {
            errorMessage = "This asset does not have a publishable licensed observation."
            return
        }
        do {
            let terms = try availabilityTerms(for: prerequisite)
            publishing = true
            defer { publishing = false }
            let offer = try await client.publishAvailability(
                asset: asset,
                routeAssetProfileVersionId: prerequisite.routeProfileVersionID(covering: availableUntil),
                liveObservationId: liveObservationId,
                availableFrom: availableFrom,
                availableUntil: availableUntil,
                maxPositionAgeSeconds: observation.maximumPermittedAgeSeconds,
                terms: terms
            )
            statusMessage = "\(prerequisite.displayName) is recorded as \(offer.state). Version \(offer.version) is now the visible capacity truth."
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = error.eusoUserCopy
        }
    }

    private func withdraw(_ offer: PricedRouteCommerceClient.AvailabilityOffer) async {
        let reason = withdrawalReason(for: offer)
        guard !reason.isEmpty else { return }
        withdrawingOfferId = offer.offerId
        defer { withdrawingOfferId = nil }
        do {
            let withdrawn = try await client.withdrawAvailability(offer, reason: reason)
            statusMessage = "Capacity version \(withdrawn.version) is withdrawn. Its prior history remains auditable."
            withdrawalReasons[offer.offerPublicId] = ""
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = error.eusoUserCopy
        }
    }

    private func availabilityTerms(
        for prerequisite: PricedRouteCommerceClient.AvailabilityPublishPrerequisite
    ) throws -> PricedRouteCommerceClient.AvailabilityTerms {
        guard offerWindowConfirmed, availableUntil > availableFrom else {
            throw PanelError.unconfirmedAvailabilityWindow
        }
        switch mode {
        case .truck:
            guard let payload = positiveInt(truckPayloadKg),
                  let radius = positiveDouble(truckRadiusMiles),
                  let deadhead = nonnegativeDouble(truckDeadheadMiles),
                  let deadheadResponsibility,
                  !tokens(truckEquipmentTypes).isEmpty,
                  !tokens(truckRegions).isEmpty else {
                throw PanelError.invalidTruckTerms
            }
            return .truck(.init(
                equipmentTypes: tokens(truckEquipmentTypes),
                availablePayloadKg: payload,
                serviceRadiusMeters: meters(fromMiles: radius),
                maxDeadheadMeters: meters(fromMiles: deadhead),
                operatingRegions: tokens(truckRegions),
                restrictions: tokens(truckRestrictions),
                deadheadResponsibility: deadheadResponsibility
            ))
        case .rail:
            let capacity = optionalPositiveInt(railCapacityKg)
            let volume = optionalPositiveDouble(railVolumeCubicMeters)
            guard capacity != nil || volume != nil,
                  let positioningResponsibility,
                  let emptyReturnResponsibility,
                  !tokens(railInterchanges).isEmpty else {
                throw PanelError.invalidRailTerms
            }
            let kind: PricedRouteCommerceClient.RailAvailabilityTerms.AssetKind =
                prerequisite.asset.assetType == "railcar" ? .railcar : .railConsist
            return .rail(.init(
                assetKind: kind,
                availableCapacityKg: capacity,
                availableVolumeCubicMeters: volume,
                interchangePoints: tokens(railInterchanges),
                commodityRestrictions: tokens(railCommodityRestrictions),
                clearanceRestrictions: tokens(railClearanceRestrictions),
                positioningResponsibility: positioningResponsibility,
                emptyReturnResponsibility: emptyReturnResponsibility
            ))
        case .vessel:
            guard laycanConfirmed,
                  laycanEnd > laycanStart,
                  let draughtMeters = positiveDouble(vesselMaximumDraughtMeters),
                  let deadweight = positiveInt(vesselAvailableDWT),
                  let ballastResponsibility,
                  let portApproachResponsibility,
                  validUnlocodes.count == tokens(vesselPortRange).count,
                  !validUnlocodes.isEmpty else {
                throw PanelError.invalidVesselTerms
            }
            return .vessel(.init(
                laycanStart: Self.iso.string(from: laycanStart),
                laycanEnd: Self.iso.string(from: laycanEnd),
                portRangeUnlocodes: validUnlocodes,
                maximumDraughtMillimeters: Int((draughtMeters * 1_000).rounded()),
                availableDeadweightTonnage: deadweight,
                cargoRestrictions: tokens(vesselCargoRestrictions),
                ballastResponsibility: ballastResponsibility,
                portApproachResponsibility: portApproachResponsibility
            ))
        }
    }

    private func termsAreValid(
        _ prerequisite: PricedRouteCommerceClient.AvailabilityPublishPrerequisite
    ) -> Bool {
        guard offerWindowConfirmed, availableUntil > availableFrom else { return false }
        return (try? availabilityTerms(for: prerequisite)) != nil
    }

    private var selectedPrerequisite: PricedRouteCommerceClient.AvailabilityPublishPrerequisite? {
        prerequisites.first { $0.assetIdentityKey == selectedAssetKey }
    }

    private var selectedAssetBinding: Binding<String?> {
        Binding(get: { selectedAssetKey }, set: { selectedAssetKey = $0 })
    }

    private func withdrawalBinding(for offerId: String) -> Binding<String> {
        Binding(
            get: { withdrawalReasons[offerId, default: ""] },
            set: { withdrawalReasons[offerId] = $0 }
        )
    }

    private func withdrawalReason(for offer: PricedRouteCommerceClient.AvailabilityOffer) -> String {
        withdrawalReasons[offer.offerPublicId, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func input(_ title: String, text: Binding<String>, numeric: Bool = false) -> some View {
        TextField(title, text: text)
            .font(EType.caption)
            .foregroundStyle(palette.textPrimary)
            .keyboardType(numeric ? .decimalPad : .default)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
    }

    private func responsibilityPicker(
        _ title: String,
        selection: Binding<PricedRouteCommerceClient.Responsibility?>
    ) -> some View {
        HStack {
            Text(title).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Picker(title, selection: selection) {
                Text("Select payer").tag(Optional<PricedRouteCommerceClient.Responsibility>.none)
                ForEach(PricedRouteCommerceClient.Responsibility.allCases, id: \.self) { value in
                    Text(responsibilityLabel(value)).tag(Optional(value))
                }
            }
            .labelsHidden()
        }
    }

    private func enumPicker<T: RawRepresentable & CaseIterable & Hashable>(
        _ title: String,
        selection: Binding<T?>
    ) -> some View where T.RawValue == String, T.AllCases: RandomAccessCollection {
        HStack {
            Text(title).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Picker(title, selection: selection) {
                Text("Select payer").tag(Optional<T>.none)
                ForEach(Array(T.allCases), id: \.self) { value in
                    Text(value.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .tag(Optional(value))
                }
            }
            .labelsHidden()
        }
    }

    private func responsibilityLabel(_ value: PricedRouteCommerceClient.Responsibility) -> String {
        value.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func evidenceMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(EType.micro.weight(.heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(EType.micro.weight(.semibold)).foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func statePill(_ value: String, color: Color) -> some View {
        Text(value)
            .font(EType.micro.weight(.heavy))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func fieldLabel(_ value: String) -> some View {
        Text(value)
            .font(EType.micro.weight(.heavy))
            .tracking(0.7)
            .foregroundStyle(palette.textTertiary)
    }

    private func offerColor(_ offer: PricedRouteCommerceClient.AvailabilityOffer) -> Color {
        if offer.state == "withdrawn" || offer.state == "expired" { return palette.textSecondary }
        if offer.freshness == "current" { return Brand.success }
        return Brand.warning
    }

    private func displayName(for offer: PricedRouteCommerceClient.AvailabilityOffer) -> String {
        prerequisites.first { $0.assetIdentityKey == offer.assetIdentityKey }?.displayName
            ?? mode.accessibilityLabel + " capacity"
    }

    private func compactWindow(_ offer: PricedRouteCommerceClient.AvailabilityOffer) -> String {
        guard let start = Self.iso.date(from: offer.availableFrom),
              let end = Self.iso.date(from: offer.availableUntil) else { return "RECORDED" }
        return Self.windowFormatter.string(from: start) + "–" + Self.windowFormatter.string(from: end)
    }

    private func tokens(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var validUnlocodes: [String] {
        tokens(vesselPortRange)
            .map { $0.uppercased() }
            .filter { token in
                token.count == 5
                    && token.prefix(2).allSatisfy(\.isLetter)
                    && token.dropFirst(2).allSatisfy { $0.isLetter || $0.isNumber }
            }
    }

    private func positiveInt(_ value: String) -> Int? {
        guard let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), parsed > 0 else { return nil }
        return parsed
    }

    private func optionalPositiveInt(_ value: String) -> Int? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : positiveInt(value)
    }

    private func positiveDouble(_ value: String) -> Double? {
        guard let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              parsed.isFinite, parsed > 0 else { return nil }
        return parsed
    }

    private func nonnegativeDouble(_ value: String) -> Double? {
        guard let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              parsed.isFinite, parsed >= 0 else { return nil }
        return parsed
    }

    private func optionalPositiveDouble(_ value: String) -> Double? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : positiveDouble(value)
    }

    private func meters(fromMiles miles: Double) -> Int {
        Int((miles * 1_609.344).rounded())
    }

    private func shortHash(_ value: String) -> String {
        String(value.prefix(10))
    }

    private var assetPlural: String {
        switch mode {
        case .truck: return "trucks"
        case .rail: return "railcars or consists"
        case .vessel: return "vessels"
        }
    }

    private var authorityTitle: String {
        switch mode {
        case .truck: return "Make my truck available"
        case .rail: return "Make rail capacity available"
        case .vessel: return "Make vessel capacity available"
        }
    }

    private var authorityExplanation: String {
        switch mode {
        case .truck:
            return "Choose an owned truck. EusoTrip binds its current licensed position while you author equipment, payload, operating range, deadhead cap, and who pays the deadhead."
        case .rail:
            return "Choose an owned railcar or consist. EusoTrip binds current authorized rail evidence while you author capacity, interchange, positioning, empty-return, commodity, and clearance terms."
        case .vessel:
            return "Choose an operated vessel. EusoTrip binds current authorized AIS or terminal evidence while you author laycan, port range, draught, DWT, cargo, ballast, and port-approach terms."
        }
    }

    private var publishLabel: String {
        switch mode {
        case .truck: return "Publish truck capacity"
        case .rail: return "Publish rail capacity"
        case .vessel: return "Publish vessel capacity"
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let windowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum PanelError: LocalizedError {
    case unconfirmedAvailabilityWindow
    case invalidTruckTerms
    case invalidRailTerms
    case invalidVesselTerms

    var errorDescription: String? {
        switch self {
        case .unconfirmedAvailabilityWindow:
            return "Confirm the exact availability window before publishing capacity."
        case .invalidTruckTerms:
            return "Enter equipment, positive payload and service radius, a nonnegative deadhead cap, at least one operating region, and who pays deadhead."
        case .invalidRailTerms:
            return "Enter weight or volume capacity, at least one real interchange point, and who pays positioning and empty return."
        case .invalidVesselTerms:
            return "Confirm an ordered laycan, valid five-character UN/LOCODEs, positive maximum draught and DWT, plus ballast and port-approach responsibility."
        }
    }
}
