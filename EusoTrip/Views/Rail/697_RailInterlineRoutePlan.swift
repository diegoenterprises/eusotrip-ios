//
//  697_RailInterlineRoutePlan.swift
//  EusoTrip — Rail Engineer / Carrier · Interline Route Plan.
//
//  Reconstructed from the stamped gap-list skeleton into a purpose-built
//  VERTICAL RELAY ITINERARY: an origin dot, interchange diamonds and a
//  destination check strung down a road-colored spine, each segment tagged with
//  its owning road + miles + PTC state, over a ROADS/INTERCHANGES/PTC summary
//  strip and a Confirm-routing CTA. This is NOT a live network map — it lays out
//  the full run-through across roads + interchanges as one plannable itinerary.
//
//  Live wiring: railShipments.getRoutePlan({shipmentId}) → the spine + summary;
//  railShipments.confirmRouting (mutation, reversible plan) persists the
//  itinerary; railShipments.requestReroute (read-only) re-solves the skeleton.
//  Honest: per-leg miles + PTC read null in the skeleton → the row renders
//  'miles pend' / 'PTC pend' and the Confirm CTA is BLOCKED until every leg
//  carries a real PTC qualification — never auto-passes a missing one.
//

import SwiftUI

struct RailInterlineRoutePlanScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var body: some View {
        Shell(theme: theme) { RailInterlineRoutePlanBody(initialShipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodable model (matches railShipments.getRoutePlan)

private struct RouteLeg697: Decodable {
    let road: String?
    let from: String?
    let to: String?
    let miles: Double?
    let interchangeOut: String?
    let ptcOk: Bool?
}

private struct RoutePlan697: Decodable {
    let shipmentId: Int
    let routeDescription: String?
    var legs: [RouteLeg697]
    let ptcComplete: Bool
    let confirmed: Bool
    let confirmedAt: String?
}

private struct ConfirmResult697: Decodable {
    let success: Bool
    let routeId: String?
    let legCount: Int?
}

private enum NodeKind697 { case origin, interchange, destination }

private enum OfflineRoutePackageState697 {
    case idle
    case securing
    case ready(validUntil: Date?)
    case unavailable(String)
}

// MARK: - Body

private struct RailInterlineRoutePlanBody: View {
    let initialShipmentId: Int
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var plan: RoutePlan697? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var shipmentIdText: String = ""
    @State private var submitting = false
    @State private var rerouting = false
    @State private var toast: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil
    @State private var offlineRoutePackageState: OfflineRoutePackageState697 = .idle
    @State private var offlineCanonicalRoute: CanonicalRoutePackage? = nil
    @State private var routeLoadGeneration = UUID()

    // Road-colored spine palette (distinct rail hues; recolors at each interchange).
    private static let roadColors: [Color] = [
        Color(red: 0.36, green: 0.56, blue: 0.98),   // blue
        Color(red: 0.56, green: 0.44, blue: 0.95),   // indigo
        Color(red: 0.20, green: 0.74, blue: 0.70),   // teal
        Color(red: 0.95, green: 0.55, blue: 0.30),   // amber
    ]

    // Server logic mirror: routing is PTC-complete only when every leg carries a
    // real ptcOk === true. Recomputed locally so a reroute stays consistent.
    private var ptcComplete: Bool {
        let l = plan?.legs ?? []
        return !l.isEmpty && l.allSatisfy { $0.ptcOk == true }
    }

    private var enteredId: Int { Int(shipmentIdText.trimmingCharacters(in: .whitespaces)) ?? 0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                shipmentField
                if loading {
                    LifecycleCard { Text("Laying out interline routing…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let p = plan {
                    routeHeader(p)
                    offlineRoutePackageCard
                    if p.confirmed { confirmedBanner(p) }
                    summaryStrip(p)
                    if p.legs.isEmpty {
                        LifecycleCard { Text("No interline legs for this shipment — a single-road move or routing not yet solved.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                    } else {
                        Text("RELAY ITINERARY · run-through")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                        spine(p.legs)
                    }
                    CTAButton(
                        title: "Confirm routing",
                        action: { Task { await confirm() } },
                        subtitle: ptcComplete ? nil : "PTC PEND · CONFIRM BLOCKED",
                        isLoading: !ptcComplete || submitting
                    )
                    rerouteButton
                } else if let offlineCanonicalRoute {
                    offlineFallback(offlineCanonicalRoute)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    LifecycleCard { Text("Enter a shipment ID above to lay out its interline routing across roads and interchanges.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task {
            if shipmentIdText.isEmpty && initialShipmentId > 0 { shipmentIdText = "\(initialShipmentId)" }
            await load()
        }
        .eusoRefreshable { await load() }
        .onChange(of: session.user) { _, _ in
            routeLoadGeneration = UUID()
            offlineCanonicalRoute = nil
            offlineRoutePackageState = .idle
        }
        .overlay(alignment: .bottom) { toastView }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("CARRIER · RAIL · INTERLINE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Route plan")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Shipment ID entry

    private var shipmentField: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "number").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textTertiary)
            TextField("Shipment ID", text: $shipmentIdText)
                .keyboardType(.numberPad)
                .font(.system(size: 15, weight: .bold)).monospaced()
                .foregroundStyle(palette.textPrimary)
                .onSubmit { Task { await load() } }
            Button { Task { await load() } } label: {
                Text("Plan").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(enteredId <= 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Route header (description + derived tags)

    private func routeHeader(_ p: RoutePlan697) -> some View {
        let roads = orderedDistinctRoads(p.legs).count
        let interchanges = p.legs.filter { $0.interchangeOut != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            if let d = p.routeDescription, !d.isEmpty {
                Text(d).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 6) {
                Text("RAIL-\(p.shipmentId)").font(.system(size: 11, weight: .heavy)).monospaced().foregroundStyle(palette.textTertiary)
                if roads > 1 { tag("run-through", Brand.info) }
                if interchanges > 0 { tag("\(interchanges) interchange\(interchanges == 1 ? "" : "s")", Brand.warning) }
                if ptcComplete { tag("PTC ✓", Brand.success) } else { tag("PTC pend", Brand.warning) }
            }
        }
    }

    private var offlineRoutePackageCard: some View {
        let title: String
        let detail: String
        let symbol: String
        let color: Color

        switch offlineRoutePackageState {
        case .idle:
            title = "Offline route not secured"
            detail = "Load this shipment online to verify and save its signed rail itinerary."
            symbol = "arrow.down.circle"
            color = palette.textTertiary
        case .securing:
            title = "Securing offline route"
            detail = "Verifying the server-signed itinerary for this account and shipment."
            symbol = "arrow.triangle.2.circlepath"
            color = Brand.info
        case .ready(let validUntil):
            title = "Signed route saved on this device"
            if let validUntil {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                detail = "Available offline until \(formatter.string(from: validUntil)); freshness is rechecked before use."
            } else {
                detail = "Available offline; signature, account scope, and freshness are rechecked before use."
            }
            symbol = "checkmark.shield.fill"
            color = Brand.success
        case .unavailable(let message):
            title = "Offline route unavailable"
            detail = message
            symbol = "exclamationmark.shield.fill"
            color = Brand.warning
        }

        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(color)
                Text(detail)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(color.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(color.opacity(0.24))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func offlineFallback(_ package: CanonicalRoutePackage) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            LifecycleCard {
                HStack(alignment: .top, spacing: Space.s2) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(Brand.warning)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live rail data unavailable")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("Showing the last fresh server-signed route saved for this account and shipment.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            CanonicalOfflineRouteItineraryView(package: package)
        }
    }

    // MARK: Confirmed banner

    private func confirmedBanner(_ p: RoutePlan697) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Routing confirmed").font(.system(size: 14, weight: .heavy)).foregroundStyle(Brand.success)
                Text(confirmedSub(p)).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.success.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func confirmedSub(_ p: RoutePlan697) -> String {
        guard let iso = p.confirmedAt, let d = parseISO(iso) else { return "Reversible plan · re-confirm anytime" }
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"
        return "Confirmed \(f.string(from: d)) · reversible plan"
    }

    // MARK: Summary strip

    private func summaryStrip(_ p: RoutePlan697) -> some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "ROADS", value: "\(orderedDistinctRoads(p.legs).count)", gradientNumeral: true)
            MetricTile(label: "INTERCHANGES", value: "\(p.legs.filter { $0.interchangeOut != nil }.count)", accent: Brand.info)
            MetricTile(label: "PTC", value: ptcComplete ? "✓" : "pend", accent: ptcComplete ? Brand.success : Brand.warning)
        }
    }

    // MARK: Relay spine

    private func spine(_ legs: [RouteLeg697]) -> some View {
        VStack(spacing: 0) {
            if let first = legs.first {
                nodeRow(label: first.from ?? "Origin",
                        sub: "Origin terminal",
                        kind: .origin,
                        topColor: nil,
                        bottomColor: roadColor(first.road, allLegs: legs))
            }
            ForEach(Array(legs.enumerated()), id: \.offset) { idx, leg in
                legRow(leg)
                let isLast = idx == legs.count - 1
                nodeRow(label: leg.to ?? (isLast ? "Destination" : "Interchange"),
                        sub: isLast ? "Destination ramp" : (leg.interchangeOut.map { "\($0) interchange" } ?? "Interchange"),
                        kind: isLast ? .destination : .interchange,
                        topColor: roadColor(leg.road, allLegs: legs),
                        bottomColor: isLast ? nil : roadColor(legs[idx + 1].road, allLegs: legs))
            }
        }
    }

    private func nodeRow(label: String, sub: String, kind: NodeKind697, topColor: Color?, bottomColor: Color?) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            spineRail(topColor: topColor, bottomColor: bottomColor) { nodeGlyph(kind) }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 14, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(sub).font(EType.caption).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer()
        }
        .frame(minHeight: 46)
    }

    private func legRow(_ leg: RouteLeg697) -> some View {
        let color = roadColor(leg.road, allLegs: plan?.legs ?? [])
        return HStack(alignment: .center, spacing: Space.s3) {
            spineRail(topColor: color, bottomColor: color) {
                Circle().fill(color).frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(palette.bgSheet, lineWidth: 2).frame(width: 7, height: 7))
            }
            legCard(leg, color: color)
        }
        .frame(minHeight: 64)
    }

    private func legCard(_ leg: RouteLeg697, color: Color) -> some View {
        let pend = leg.ptcOk == nil
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 3, height: 14)
                    Text(leg.road ?? "—").font(.system(size: 14, weight: .heavy)).monospaced().foregroundStyle(palette.textPrimary)
                }
                Spacer()
                ptcPill(leg.ptcOk)
            }
            HStack(spacing: 6) {
                Text(leg.from ?? "—").font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
                Text(leg.to ?? "—").font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            HStack(spacing: Space.s2) {
                miniStat(icon: "ruler", text: milesText(leg.miles))
                if let ic = leg.interchangeOut, !ic.isEmpty {
                    miniStat(icon: "arrow.triangle.swap", text: ic)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pend ? Brand.warning.opacity(0.06) : palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(pend ? Brand.warning.opacity(0.30) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func tag(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func ptcPill(_ ptcOk: Bool?) -> some View {
        let txt: String
        let col: Color
        if ptcOk == true { txt = "PTC ✓"; col = Brand.success }
        else if ptcOk == false { txt = "PTC ✗"; col = Brand.danger }
        else { txt = "PTC pend"; col = Brand.warning }
        return Text(txt)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(col)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(col.opacity(0.16)))
    }

    private func miniStat(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(palette.textTertiary.opacity(0.08)))
    }

    // Continuous colored spine rail: flexible top/bottom line segments with a
    // centered glyph. A nil color draws a clear (invisible) segment so the origin
    // has no line above and the destination no line below.
    private func spineRail<G: View>(topColor: Color?, bottomColor: Color?, @ViewBuilder glyph: () -> G) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(topColor ?? Color.clear).frame(width: 2).frame(maxHeight: .infinity)
            glyph()
            Rectangle().fill(bottomColor ?? Color.clear).frame(width: 2).frame(maxHeight: .infinity)
        }
        .frame(width: 32)
    }

    private func nodeGlyph(_ kind: NodeKind697) -> AnyView {
        switch kind {
        case .origin:
            return AnyView(
                Circle().fill(LinearGradient.diagonal).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(palette.bgSheet, lineWidth: 3).frame(width: 14, height: 14))
            )
        case .interchange:
            return AnyView(
                Rectangle().fill(Brand.warning).frame(width: 12, height: 12)
                    .overlay(Rectangle().strokeBorder(palette.bgSheet, lineWidth: 2).frame(width: 12, height: 12))
                    .rotationEffect(.degrees(45))
            )
        case .destination:
            return AnyView(
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                }
            )
        }
    }

    // MARK: Reroute button (secondary)

    private var rerouteButton: some View {
        Button { Task { await reroute() } } label: {
            HStack {
                Spacer()
                if rerouting {
                    ProgressView().tint(palette.textSecondary)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13, weight: .bold))
                        Text("Reroute").font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        }
        .buttonStyle(.plain)
        .disabled(rerouting || plan == nil)
    }

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Helpers

    private func orderedDistinctRoads(_ legs: [RouteLeg697]) -> [String] {
        var seen = Set<String>()
        var out = [String]()
        for l in legs {
            if let r = l.road, !r.isEmpty, !seen.contains(r) { seen.insert(r); out.append(r) }
        }
        return out
    }

    private func roadColor(_ road: String?, allLegs: [RouteLeg697]) -> Color {
        let roads = orderedDistinctRoads(allLegs)
        guard let r = road, let i = roads.firstIndex(of: r) else { return Self.roadColors[0] }
        return Self.roadColors[i % Self.roadColors.count]
    }

    private func milesText(_ m: Double?) -> String {
        guard let m = m else { return "miles pend" }
        return "\(Int(m.rounded()).formatted()) mi"
    }

    private func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private func flashToast(_ msg: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { toast = msg }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: Data

    private func load() async {
        let generation = UUID()
        routeLoadGeneration = generation
        let id = enteredId
        guard id > 0 else {
            plan = nil
            loadError = nil
            offlineCanonicalRoute = nil
            offlineRoutePackageState = .idle
            loading = false
            return
        }
        plan = nil
        offlineCanonicalRoute = nil
        offlineRoutePackageState = .idle
        loading = true; loadError = nil
        struct In: Encodable { let shipmentId: Int }
        do {
            let loaded: RoutePlan697 = try await EusoTripAPI.shared.query(
                "railShipments.getRoutePlan",
                input: In(shipmentId: id)
            )
            guard routeLoadGeneration == generation else { return }
            guard loaded.shipmentId == id else {
                plan = nil
                loadError = "The server returned a route for a different shipment. Nothing was cached."
                offlineRoutePackageState = .idle
                loading = false
                return
            }
            self.plan = loaded
            loading = false
            await secureOfflineCanonicalRoute(
                shipmentId: loaded.shipmentId,
                generation: generation
            )
            return
        } catch {
            guard routeLoadGeneration == generation else { return }
            let liveError = (error as? EusoTripAPIError)?.errorDescription
                ?? error.localizedDescription
            if await restoreOfflineCanonicalRoute(
                shipmentId: id,
                generation: generation
            ) {
                loadError = liveError
            } else {
                loadError = liveError
            }
        }
        loading = false
    }

    private func secureOfflineCanonicalRoute(shipmentId: Int, generation: UUID) async {
        guard routeLoadGeneration == generation else { return }
        guard shipmentId > 0 else {
            offlineRoutePackageState = .unavailable(
                "The server did not provide an authoritative shipment identifier."
            )
            return
        }
        guard let authenticatedUser = session.user else {
            offlineRoutePackageState = .unavailable(
                "Sign in while online to secure this route for offline use."
            )
            return
        }
        guard let composition = OfflineMapProductionComposition.shared else {
            offlineRoutePackageState = .unavailable(
                "Offline route storage is unavailable in this app build."
            )
            return
        }

        offlineRoutePackageState = .securing
        do {
            let delivery = try await CanonicalRoutePlanClient().download(
                subject: .railShipment(Int64(shipmentId)),
                authenticatedUser: authenticatedUser
            )
            guard routeLoadGeneration == generation else { return }
            guard session.user?.id == authenticatedUser.id,
                  session.user?.companyId == authenticatedUser.companyId else {
                offlineRoutePackageState = .unavailable(
                    "The signed-in account changed before this route could be saved."
                )
                return
            }
            let package = try await composition.ingestCanonicalRoutePlan(
                encodedEnvelope: delivery.encodedEnvelope,
                expectedScope: delivery.expectedScope,
                receivedAt: delivery.receivedAt
            )
            guard routeLoadGeneration == generation else { return }
            guard session.user?.id == authenticatedUser.id,
                  session.user?.companyId == authenticatedUser.companyId else {
                offlineRoutePackageState = .unavailable(
                    "The signed-in account changed before this route could be saved."
                )
                return
            }
            offlineCanonicalRoute = package
            offlineRoutePackageState = .ready(validUntil: package.validUntil)
        } catch {
            guard routeLoadGeneration == generation else { return }
            if await restoreOfflineCanonicalRoute(
                shipmentId: shipmentId,
                generation: generation
            ) {
                return
            }
            offlineRoutePackageState = .unavailable(
                composition.canonicalRouteFailure
                    ?? "The signed route could not be verified and was not saved."
            )
        }
    }

    private func restoreOfflineCanonicalRoute(
        shipmentId: Int,
        generation: UUID
    ) async -> Bool {
        guard routeLoadGeneration == generation,
              let authenticatedUser = session.user,
              let composition = OfflineMapProductionComposition.shared else {
            return false
        }
        do {
            let package = try await CanonicalRouteOfflineReader(
                composition: composition
            ).freshPackage(
                subject: .railShipment(Int64(shipmentId)),
                authenticatedUser: authenticatedUser
            )
            guard routeLoadGeneration == generation,
                  session.user?.id == authenticatedUser.id,
                  session.user?.companyId == authenticatedUser.companyId else {
                return false
            }
            offlineCanonicalRoute = package
            offlineRoutePackageState = .ready(validUntil: package.validUntil)
            return true
        } catch let error as CanonicalRouteOfflineReadError {
            guard routeLoadGeneration == generation else { return false }
            offlineCanonicalRoute = nil
            offlineRoutePackageState = .unavailable(
                error.errorDescription ?? "The saved route is unavailable."
            )
            return false
        } catch {
            guard routeLoadGeneration == generation else { return false }
            offlineCanonicalRoute = nil
            offlineRoutePackageState = .unavailable(
                "The saved route could not be verified for offline use."
            )
            return false
        }
    }

    private func confirm() async {
        guard let p = plan, ptcComplete, !submitting else { return }
        struct LegIn: Encodable {
            let road: String?
            let from: String?
            let to: String?
            let miles: Double?
            let interchangeOut: String?
            let ptcOk: Bool?
        }
        struct In: Encodable { let shipmentId: Int; let legs: [LegIn] }
        submitting = true
        do {
            let legsIn = p.legs.map { LegIn(road: $0.road, from: $0.from, to: $0.to, miles: $0.miles, interchangeOut: $0.interchangeOut, ptcOk: $0.ptcOk) }
            let _: ConfirmResult697 = try await EusoTripAPI.shared.mutation(
                "railShipments.confirmRouting",
                input: In(shipmentId: p.shipmentId, legs: legsIn)
            )
            submitting = false
            await load()
            flashToast("Routing confirmed · \(orderedDistinctRoads(p.legs).count) roads")
        } catch {
            submitting = false
            flashToast((error as? EusoTripAPIError)?.errorDescription ?? "Confirm failed")
        }
    }

    private func reroute() async {
        guard let p = plan, !rerouting else { return }
        struct In: Encodable { let shipmentId: Int }
        struct RerouteResult697: Decodable { let shipmentId: Int; let legs: [RouteLeg697] }
        rerouting = true
        do {
            let res: RerouteResult697 = try await EusoTripAPI.shared.query(
                "railShipments.requestReroute",
                input: In(shipmentId: p.shipmentId)
            )
            guard res.shipmentId == p.shipmentId else {
                rerouting = false
                flashToast("Reroute returned the wrong shipment")
                return
            }
            routeLoadGeneration = UUID()
            plan?.legs = res.legs
            offlineRoutePackageState = .unavailable(
                "This reroute is only a preview. Confirm it online before it can replace the signed offline route."
            )
            rerouting = false
            flashToast("Routing re-solved · \(res.legs.count) leg\(res.legs.count == 1 ? "" : "s")")
        } catch {
            rerouting = false
            flashToast((error as? EusoTripAPIError)?.errorDescription ?? "Reroute failed")
        }
    }
}

#Preview("697 · Rail Interline Route Plan · Night") { RailInterlineRoutePlanScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("697 · Rail Interline Route Plan · Light") { RailInterlineRoutePlanScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
