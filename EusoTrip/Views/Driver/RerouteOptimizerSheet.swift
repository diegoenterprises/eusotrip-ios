//
//  RerouteOptimizerSheet.swift
//  EusoTrip 2027 UI — Driver · En-Route Reroute Optimizer (P1)
//
//  Pushed (NOT slide-up) from 013 En Route. The driver taps the
//  "Reroute" affordance on the active-enroute bottom sheet; this screen
//  pushes onto the driver lifecycle NavigationStack and lets them weigh
//  the current route against ranked alternates, then APPLY a chosen
//  route.
//
//  Server-backed — three LIVE procs, no stubs:
//    • `navigation.getRoute({ loadId })`        → resolves the persisted
//      `routes` row for the load. Its PK is the `routeId` the routing
//      procs require, and it carries the encoded HERE polyline for the
//      map preview. nil ⇒ no saved route for this load (honest empty
//      state — we never fabricate alternates against a phantom route).
//    • `routing.compareAlternatives({ routeId })` → the current route
//      (alternativeId 0) plus ranked candidates with ETA / fuel / toll /
//      risk DELTAS and the server's composite rankScore (lower = better).
//    • `routing.applyReroute({ routeId, alternativeId, reason, … })`
//      → logs the decision to `reroute_decisions` and (opt-in) commits
//      the chosen duration to the live route.
//
//  HONESTY ENVELOPE:
//    • The server marks the alternates as HEURISTIC placeholders until
//      HERE/OSRM multi-route geometry is wired server-side — so every
//      delta is labelled "estimated" and the candidates share the
//      baseline polyline preview (we never paint an invented geometry).
//    • No-lingering-load: the load row + compare call each run under the
//      shared 22s request ceiling; `isLoading` is resolved in a
//      `defer`, and any failure lands an honest, retryable error card.
//    • Apply shows an inline result banner with the server's verbatim
//      "logged at" timestamp + whether the route was committed.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - Screen

struct RerouteOptimizerSheet: View {
    @Environment(\.palette) private var palette

    /// The load whose route we're optimizing. When nil the screen
    /// hydrates the driver's currently-assigned load from the trip
    /// lifecycle store (so it works as a tab-root deep-link too).
    let loadId: Int?
    /// Mode badge + lexicon context. nil falls back to truck.
    let transportMode: String?

    init(loadId: Int? = nil, transportMode: String? = nil) {
        self.loadId = loadId
        self.transportMode = transportMode
    }

    @StateObject private var lifecycle = TripLifecycleStore()

    // ── Live state ──
    @State private var resolvedLoadId: Int?
    @State private var route: RoutingAPI.RouteRow?
    @State private var compare: RoutingAPI.CompareResult?
    @State private var routePolyline: [HereLatLng] = []

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var skeletonPulse = false

    /// Which alternative is selected for apply. nil = nothing chosen yet.
    @State private var selectedAltId: Int?
    @State private var isApplying = false
    @State private var applyResult: RoutingAPI.ApplyResult?
    @State private var applyError: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topbar
            content
        }
        .screenTileRoot()
        .task { await hydrate() }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                heroBlock

                if isLoading && compare == nil {
                    loadingSkeleton
                } else if let err = loadError {
                    errorCard(err)
                } else if let cmp = compare {
                    if cmp.baseline == nil && cmp.alternatives.isEmpty {
                        noRouteEmptyState
                    } else {
                        mapPreview
                        currentRouteCard(cmp)
                        alternativesHeader(cmp.alternatives.count)
                        if cmp.alternatives.isEmpty {
                            noAlternativesState
                        } else {
                            ForEach(cmp.alternatives) { alt in
                                alternativeCard(alt, baseline: cmp.baseline)
                            }
                        }
                        honestyFooter
                    }
                } else {
                    noRouteEmptyState
                }

                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .safeAreaInset(edge: .bottom) {
            if let cmp = compare, !(cmp.baseline == nil && cmp.alternatives.isEmpty) {
                applyBar(cmp)
            }
        }
    }

    // MARK: - Header strip
    //
    // NO back chevron here: this screen is pushed via `\.rolePushDetail`,
    // which auto-injects the canonical `BespokeBackBar` (back + title) above
    // the body. We render only the eyebrow + mode badge + refresh so we never
    // double-up on the back affordance. `navBack` is retained as a fallback
    // for the deep-link case (the env closure is nil outside a surface that
    // installs RoleDetailLayer, so the strip stays chevron-free either way).

    private var topbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("REROUTE · OPTIMIZER")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                LoadModeBadge(modeRaw: transportMode, multiVehicleCount: nil, compact: true)
            }

            Spacer()

            // Live refresh — re-pulls the compare model. Disabled while a
            // fetch is in flight so taps can't stack.
            Button { Task { await refreshCompare(force: true) } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isLoading ? palette.textTertiary : palette.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .disabled(isLoading)
            .accessibilityLabel("Refresh alternatives")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: - Hero

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weigh your alternates")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Ranked by a blended ETA · fuel · risk score. Pick a route to apply, or stay the course — either way the decision is logged.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Map preview (HERE native — baseline polyline)

    @ViewBuilder
    private var mapPreview: some View {
        if routePolyline.count >= 2, let center = polylineCenter {
            HereLiveMapView(
                center: center,
                zoom: 6,
                interactive: false,
                route: routePolyline,
                baseLayers: [.route(polyline: routePolyline, colorHex: "#1473FF")],
                addOns: [],
                showLegend: false,
                showTicker: false
            )
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderSoft, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                Text("CURRENT CORRIDOR")
                    .font(EType.micro).tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(10)
            }
        }
        // No polyline on the wire → no map block (honest absence). The
        // numeric current-route card below still renders the real figures.
    }

    private var polylineCenter: HereLatLng? {
        guard !routePolyline.isEmpty else { return nil }
        let lat = routePolyline.map(\.lat).reduce(0, +) / Double(routePolyline.count)
        let lng = routePolyline.map(\.lng).reduce(0, +) / Double(routePolyline.count)
        return HereLatLng(lat, lng)
    }

    // MARK: - Current route card

    private func currentRouteCard(_ cmp: RoutingAPI.CompareResult) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 8) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(cmp.baseline?.label ?? "Current route")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("ON THIS ROUTE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(Brand.success)
            }

            HStack(spacing: Space.s2) {
                figureTile(label: "ETA", value: durationText(cmp.baseline?.durationMinutes))
                figureTile(label: "MILES", value: milesText(cmp.baseline?.miles))
                figureTile(label: "FUEL", value: gallonsText(cmp.baseline?.fuelGal))
            }
            HStack(spacing: Space.s2) {
                figureTile(label: "FUEL $", value: dollarsText(cmp.baseline?.fuelCost))
                figureTile(label: "TOLLS", value: dollarsText(cmp.baseline?.tollCost))
                figureTile(label: "RISK", value: riskText(cmp.baseline?.riskScore))
            }
        }
        .padding(Space.s4)
        .eusoCard()
    }

    // MARK: - Alternatives

    private func alternativesHeader(_ count: Int) -> some View {
        HStack {
            Text("ALTERNATES")
                .font(EType.micro).tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(count == 0 ? "none ranked" : "\(count) ranked · best first")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, Space.s1)
    }

    private func alternativeCard(_ alt: RoutingAPI.RouteAlternative,
                                 baseline: RoutingAPI.RouteBaseline?) -> some View {
        let isSelected = (selectedAltId == alt.alternativeId)
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                selectedAltId = isSelected ? nil : alt.alternativeId
                applyResult = nil
                applyError = nil
            }
        } label: {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alt.label)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(alt.reason)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? Color.clear : palette.borderSoft, lineWidth: 1.5)
                            .background(
                                Circle().fill(isSelected ? AnyShapeStyle(LinearGradient.diagonal)
                                                          : AnyShapeStyle(Color.clear))
                            )
                            .frame(width: 24, height: 24)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }

                // Delta chips — the heart of the comparison.
                HStack(spacing: Space.s2) {
                    deltaChip(
                        title: "ETA",
                        value: signedMinutes(alt.etaDeltaSec),
                        good: alt.etaDeltaSec <= 0
                    )
                    deltaChip(
                        title: "FUEL",
                        value: signedGallons(alt.fuelDeltaGal),
                        good: alt.fuelDeltaGal <= 0
                    )
                    deltaChip(
                        title: "TOLLS",
                        value: signedDollars(alt.tollCostDelta),
                        good: alt.tollCostDelta <= 0
                    )
                }

                HStack(spacing: Space.s2) {
                    miniStat(label: "MILES", value: milesText(alt.miles))
                    miniStat(label: "RISK", value: riskText(alt.riskScore))
                    miniStat(label: "SURFACE", value: alt.surface.capitalized)
                    Spacer(minLength: 0)
                    Text("SCORE \(scoreText(alt.rankScore))")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(
                                isSelected ? AnyShapeStyle(LinearGradient.diagonal)
                                           : AnyShapeStyle(palette.borderSoft),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alt.label). \(signedMinutes(alt.etaDeltaSec)) ETA, \(signedGallons(alt.fuelDeltaGal)) fuel")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func deltaChip(title: String, value: String, good: Bool) -> some View {
        let tint = good ? Brand.success : Brand.warning
        return VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong.monospaced())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s2)
        .padding(.horizontal, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(tint.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption.monospaced())
                .foregroundStyle(palette.textPrimary)
        }
    }

    private func figureTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong.monospaced())
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 0.5)
                )
        )
    }

    private var honestyFooter: some View {
        Text("Alternates + deltas are estimated against your saved route. EusoTrip ranks them by composite ETA, fuel, and risk score. Live multi-route geometry follows; today every option shares the current corridor preview.")
            .font(EType.micro)
            .foregroundStyle(palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.s1)
    }

    // MARK: - Apply bar

    @ViewBuilder
    private func applyBar(_ cmp: RoutingAPI.CompareResult) -> some View {
        VStack(spacing: Space.s2) {
            if let res = applyResult {
                resultBanner(res)
            } else if let err = applyError {
                inlineErrorBanner(err)
            }

            HStack(spacing: Space.s2) {
                // Stay-the-course — logs alternativeId 0.
                Button {
                    Task { await apply(alternativeId: 0, alt: nil, commit: false) }
                } label: {
                    Text("Stay on route")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isApplying)

                // Apply the selected alternate.
                Button {
                    guard let id = selectedAltId,
                          let alt = cmp.alternatives.first(where: { $0.alternativeId == id })
                    else { return }
                    Task { await apply(alternativeId: id, alt: alt, commit: true) }
                } label: {
                    HStack(spacing: 6) {
                        if isApplying {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                        }
                        Text(applyButtonTitle)
                            .font(EType.body).fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(selectedAltId == nil
                                  ? AnyShapeStyle(palette.tintNeutral)
                                  : AnyShapeStyle(LinearGradient.diagonal))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isApplying || selectedAltId == nil)
                .accessibilityLabel("Apply selected reroute")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, Space.s2)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }

    private var applyButtonTitle: String {
        selectedAltId == nil ? "Pick an alternate" : "Apply reroute"
    }

    private func resultBanner(_ res: RoutingAPI.ApplyResult) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(res.alternativeId == 0
                     ? "Logged · staying on current route"
                     : (res.committed ? "Reroute applied · route updated" : "Reroute logged"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Recorded \(shortTime(res.loggedAt))" + (res.committed ? " · live ETA refreshed" : ""))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Brand.success.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.success.opacity(0.4), lineWidth: 1))
        )
    }

    private func inlineErrorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Brand.warning)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Brand.warning.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.warning.opacity(0.4), lineWidth: 1))
        )
    }

    // MARK: - Loading / empty / error states

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.5))
                    .frame(height: 118)
                    .opacity(skeletonPulse ? 0.45 : 0.95)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                skeletonPulse = true
            }
        }
    }

    private var noRouteEmptyState: some View {
        emptyCard(
            icon: "point.topleft.down.to.point.bottomright.curvepath",
            title: "No saved route to optimize",
            body: "This load doesn't have a persisted route yet, so there's nothing to compare alternates against. Once dispatch or the lifecycle plans a route, alternates light up here."
        )
    }

    private var noAlternativesState: some View {
        emptyCard(
            icon: "checkmark.circle",
            title: "Your route is the call",
            body: "The optimizer didn't surface a better alternate right now — you're already on a strong path."
        )
    }

    private func emptyCard(icon: String, title: String, body: String) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(LinearGradient.diagonal)
            Text(title)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(body)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
        .padding(.horizontal, Space.s4)
        .eusoCard()
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Brand.warning)
            Text("Couldn't load alternates")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await hydrate() }
            } label: {
                Text("Retry")
                    .font(EType.body).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s5)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
        .padding(.horizontal, Space.s4)
        .eusoCard()
    }

    // MARK: - Data

    /// Resolve the load → route → compare model. Bounded by the shared
    /// 22s request ceiling; `isLoading` is always resolved in `defer`.
    private func hydrate() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        // Resolve a loadId — either the one we were pushed with, or the
        // driver's active trip from the lifecycle store.
        var lid = loadId
        if lid == nil {
            await lifecycle.hydrateActiveLoad()
            if !lifecycle.loadId.isEmpty { lid = Int(lifecycle.loadId) }
        }
        resolvedLoadId = lid

        guard let lid else {
            // No active load → nothing to optimize. Honest empty state.
            compare = RoutingAPI.CompareResult(routeId: 0, baseline: nil, alternatives: [], rankedBy: "etaFuelRisk")
            return
        }

        do {
            let row = try await EusoTripAPI.shared.routing.getRoute(loadId: lid)
            route = row
            // Decode the persisted HERE polyline for the map preview.
            if let encoded = row?.polyline, !encoded.isEmpty {
                let coords = HereFlexiblePolyline.decode(encoded)
                routePolyline = coords.count >= 2 ? coords.map { HereLatLng($0) } : []
            } else {
                routePolyline = []
            }

            guard let rid = row?.id else {
                // No persisted route row → honest "no saved route" state.
                compare = RoutingAPI.CompareResult(routeId: 0, baseline: nil, alternatives: [], rankedBy: "etaFuelRisk")
                return
            }
            compare = try await EusoTripAPI.shared.routing.compareAlternatives(routeId: rid, maxAlternates: 4)
        } catch {
            loadError = friendly(error)
        }
    }

    /// Re-pull only the compare model (after a refresh tap) when we
    /// already have a routeId resolved.
    private func refreshCompare(force: Bool) async {
        guard let rid = route?.id else { await hydrate(); return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            compare = try await EusoTripAPI.shared.routing.compareAlternatives(routeId: rid, maxAlternates: 4)
        } catch {
            loadError = friendly(error)
        }
    }

    /// Apply (or log "stay") the chosen route.
    private func apply(alternativeId: Int, alt: RoutingAPI.RouteAlternative?, commit: Bool) async {
        guard let rid = route?.id else { return }
        isApplying = true
        applyError = nil
        applyResult = nil
        defer { isApplying = false }
        do {
            let reason: String = {
                if let alt { return "Driver chose \(alt.label) (est \(signedMinutes(alt.etaDeltaSec)) ETA, \(signedGallons(alt.fuelDeltaGal)) fuel)" }
                return "Driver reviewed alternates and stayed on current route"
            }()
            let res = try await EusoTripAPI.shared.routing.applyReroute(
                routeId: rid,
                alternativeId: alternativeId,
                reason: reason,
                etaDeltaSec: alt?.etaDeltaSec,
                fuelDeltaGal: alt?.fuelDeltaGal,
                commitToRoute: commit
            )
            applyResult = res
            // Reflect the committed duration locally so the current-route
            // card reads honestly without a full re-fetch.
            if res.committed { await refreshCompare(force: true) }
        } catch {
            applyError = friendly(error)
        }
    }

    // MARK: - Formatting helpers (honest em-dash when a figure is absent)

    private func durationText(_ minutes: Int?) -> String {
        guard let m = minutes, m > 0 else { return "—" }
        let h = m / 60, mm = m % 60
        return h > 0 ? "\(h)h \(mm)m" : "\(mm)m"
    }
    private func milesText(_ mi: Double?) -> String {
        guard let mi else { return "—" }
        return "\(Int(mi.rounded())) mi"
    }
    private func gallonsText(_ g: Double?) -> String {
        guard let g else { return "—" }
        return String(format: "%.0f gal", g)
    }
    private func dollarsText(_ d: Double?) -> String {
        guard let d else { return "—" }
        return "$" + String(format: "%.0f", d)
    }
    private func riskText(_ r: Double?) -> String {
        guard let r else { return "—" }
        return "\(Int((r * 100).rounded()))%"
    }
    private func scoreText(_ s: Double) -> String { String(format: "%.0f", s) }

    private func signedMinutes(_ sec: Int) -> String {
        if sec == 0 { return "±0m" }
        let m = Int((Double(sec) / 60).rounded())
        if m == 0 { return sec > 0 ? "+<1m" : "−<1m" }
        return (m > 0 ? "+" : "−") + "\(abs(m))m"
    }
    private func signedGallons(_ g: Double) -> String {
        if abs(g) < 0.05 { return "±0 gal" }
        return (g > 0 ? "+" : "−") + String(format: "%.1f gal", abs(g))
    }
    private func signedDollars(_ d: Double) -> String {
        if abs(d) < 0.5 { return "±$0" }
        return (d > 0 ? "+$" : "−$") + String(format: "%.0f", abs(d))
    }

    private func shortTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "just now" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "HH:mm"
        return out.string(from: date)
    }

    private func friendly(_ error: Error) -> String {
        if let e = error as? EusoTripAPIError {
            switch e {
            case .httpStatus(_, let body) where !body.isEmpty:
                return String(body.prefix(160))
            default:
                return "We couldn't reach the routing service. Check your connection and retry."
            }
        }
        return "We couldn't reach the routing service. Check your connection and retry."
    }
}
