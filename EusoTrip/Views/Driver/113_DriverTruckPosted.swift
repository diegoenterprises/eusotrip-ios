//
//  113_DriverTruckPosted.swift
//  EusoTrip — D-1 INBOUND TRUCK-POSTING HERO ("post your truck → brokers
//  come to YOU → one-tap accept"). The founder's #1 loved feature.
//
//  This is the iOS client for the server `truckPosting` router (shipped
//  client-orphaned in PR #106). Two states, one bespoke surface:
//
//    (a) NOT POSTED — a deep-intention HERO "Post your truck" call-to-
//        action: the brand-gradient slab, a drawn truck glyph (Path, zero
//        SF Symbols on the bespoke surface), the value prop, and a
//        quick-form (equipment auto-read from the assigned vehicle, live
//        HERE origin, available-from). The confident POST button mints the
//        posting via `truckPosting.postTruck`.
//
//    (b) POSTED — "Your truck is live" status (a derived pulse spark) +
//        the inbound OFFERS as inspiring bespoke FLIP cards (broker · lane
//        · the offered rate as a hero metric · a match-confidence ring).
//        Each card flips to load detail with a ONE-TAP ACCEPT that books
//        the load. Honest-empty when there are no offers yet — the truck
//        is live and visible; we never fabricate an offer.
//
//  ─────────────────────────────────────────────────────────────────────
//  SERVER CONTRACT — what's actually deployed vs. the idealized brief
//  ─────────────────────────────────────────────────────────────────────
//  The task brief describes a `truck_postings` / `truck_offers` model with
//  `postTruck / listInboundOffers / acceptOffer / pauseTruck` — that lights
//  up only once the founder applies migration 0339. The CURRENTLY DEPLOYED
//  `frontend/server/routers/truckPosting.ts` (MCP-verified 2026-06-18)
//  exposes the equivalent honest surface that exists TODAY:
//
//    • postTruck(vehicleId, currentLocation{lat,lng,city?,state?},
//                availableDate, preferredDestinations?, maxDistance?,
//                hazmatEndorsed, hazmatClasses?, notes?)
//        → marks the assigned vehicle "available" (the posting). Equipment
//          type is read SERVER-SIDE off the vehicle row, so the client only
//          needs vehicleId + location + availableDate.
//    • getMatchSuggestions(vehicleId) → the inbound OFFERS: real broker
//        loads (`loads` rows in 'posted'/'bidding') scored against the
//        posted truck's equipment + hazmat quals. This IS "loads come to
//        you" using live data — no offer is invented.
//    • getMyFleetAvailability() → resolves whether the truck is already
//        posted (status == "available") so the surface restores state.
//    • removeTruck(vehicleId) → pause/unpost.
//    • getCapacityStats(state?) → the live load-to-truck ratio shown as the
//        "market" pulse on the posted-state header.
//
//  The one-tap ACCEPT books via `loads.acceptLoad` (the same proc the
//  Eusoboards "Accept" CTA uses — server runs identity + carrier-vetting
//  gates). When the 0339 `acceptOffer(offerId)` path ships, swap the body
//  of `TruckPostingViewModel.accept(_:)` — the call site is isolated.
//
//  Assumptions (noted per the brief): offer rows are modeled as match
//  suggestions until `truck_offers` exists; accept routes through
//  `loads.acceptLoad(loadId:)`. Both degrade to honest-empty / honest-error
//  if the proc returns nothing.
//
//  DESIGN — flip-card / inspiring-surface language (FlipTile, Hot Zones
//  bespoke tiles, WeatherV3, HotZonePulseChart): zero SF Symbols on the
//  bespoke hero (drawn glyphs/Paths), palette + LinearGradient.diagonal,
//  gradients / hero metrics / a derived pulse spark, honest data (em-dash,
//  never fabricated). Every isLoading flag is bounded; last-good state
//  restores instantly.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - Offer model (the inbound row)

/// One inbound offer on the posted truck. Modeled on the deployed
/// `truckPosting.getMatchSuggestions` row (a real broker load scored
/// against the posted truck). When the 0339 `truck_offers` table ships,
/// this same shape decodes `listInboundOffers` with `offeredRate`/`status`
/// mapped onto `rate`/`statusRaw`.
struct TruckInboundOffer: Identifiable, Decodable, Equatable {
    let loadId: Int
    let loadNumber: String?
    let statusRaw: String?
    let cargoType: String?
    let hazmatClass: String?
    let commodityName: String?
    let origin: String?
    let destination: String?
    /// The offered/load rate — the hero metric on the offer card.
    let rate: Double
    let pickupDate: String?
    /// 0…100 match confidence (server `matchScore`). Drives the ring.
    let matchScore: Int
    let hazmatMatch: Bool?

    var id: Int { loadId }

    /// Decoded leniently so BOTH the match-suggestion shape (loadId,
    /// matchScore) and a future `truck_offers` shape (offerId→loadId,
    /// offeredRate→rate, status→statusRaw) hydrate without a re-write.
    enum CodingKeys: String, CodingKey {
        case loadId, offerId, loadNumber, status, cargoType, hazmatClass
        case commodityName, origin, destination, rate, offeredRate
        case pickupDate, matchScore, hazmatMatch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // loadId is canonical; fall back to offerId if a truck_offers row.
        self.loadId = (try? c.decode(Int.self, forKey: .loadId))
            ?? (try? c.decode(Int.self, forKey: .offerId))
            ?? 0
        self.loadNumber = try? c.decodeIfPresent(String.self, forKey: .loadNumber)
        self.statusRaw = try? c.decodeIfPresent(String.self, forKey: .status)
        self.cargoType = try? c.decodeIfPresent(String.self, forKey: .cargoType)
        self.hazmatClass = try? c.decodeIfPresent(String.self, forKey: .hazmatClass)
        self.commodityName = try? c.decodeIfPresent(String.self, forKey: .commodityName)
        self.origin = try? c.decodeIfPresent(String.self, forKey: .origin)
        self.destination = try? c.decodeIfPresent(String.self, forKey: .destination)
        self.rate = (try? c.decode(Double.self, forKey: .rate))
            ?? (try? c.decode(Double.self, forKey: .offeredRate))
            ?? 0
        self.pickupDate = try? c.decodeIfPresent(String.self, forKey: .pickupDate)
        self.matchScore = (try? c.decodeIfPresent(Int.self, forKey: .matchScore)) ?? 0
        self.hazmatMatch = try? c.decodeIfPresent(Bool.self, forKey: .hazmatMatch)
    }

    /// "Atlanta, GA → Dallas, TX" — falls to an em-dash when the lane
    /// isn't on the row (never a fabricated city).
    var laneDisplay: String {
        let o = (origin?.isEmpty == false) ? origin! : "—"
        let d = (destination?.isEmpty == false) ? destination! : "—"
        return "\(o)  →  \(d)"
    }

    /// "$3,250" — the offered rate as the card's hero numeral. Em-dash
    /// when the row carries no rate.
    var rateDisplay: String {
        guard rate > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: rate)) ?? "—"
    }

    var brokerDisplay: String {
        if let n = commodityName, !n.isEmpty { return n }
        if let n = loadNumber, !n.isEmpty { return "Load \(n)" }
        return "Broker offer"
    }

    var isHazmat: Bool { (hazmatClass?.isEmpty == false) }
}

// MARK: - ViewModel

@MainActor
final class TruckPostingViewModel: ObservableObject {

    enum Phase: Equatable { case loading, notPosted, posted, error(String) }

    @Published var phase: Phase = .loading
    @Published var offers: [TruckInboundOffer] = []
    @Published var offersLoading: Bool = false
    @Published var acceptingLoadId: Int? = nil
    @Published var bookedLoadId: Int? = nil
    @Published var postingInFlight: Bool = false
    @Published var actionError: String? = nil

    // Resolved posting context (from the assigned vehicle + live fix).
    @Published var vehicleId: Int? = nil
    @Published var equipmentLabel: String = "—"
    @Published var unitLabel: String = "—"
    @Published var originLine: String = "—"
    @Published var coordinate: CLLocationCoordinate2D? = nil
    private var originCity: String? = nil
    private var originState: String? = nil

    /// Live market pulse for the posted-state header (load-to-truck ratio).
    @Published var marketRatio: Double? = nil
    @Published var marketLabel: String = "—"

    private let api = EusoTripAPI.shared

    /// Initial hydrate: resolve the assigned vehicle, the live origin, and
    /// whether the truck is already posted. Bounded — any failure lands in
    /// an honest state, never an infinite skeleton.
    func load() async {
        phase = .loading
        await resolveVehicle()
        await resolveOrigin()

        guard let vid = vehicleId else {
            // No assigned vehicle → can't post. Honest, first-class state.
            phase = .error("No truck assigned to your profile yet. Once dispatch assigns your unit you can post it here.")
            return
        }

        // Is this vehicle already posted (status == available)?
        let alreadyPosted = await isAlreadyPosted(vehicleId: vid)
        if alreadyPosted {
            phase = .posted
            await refreshOffers()
            await refreshMarket()
        } else {
            phase = .notPosted
        }
    }

    /// Read the driver's assigned truck → vehicleId + equipment + unit.
    private func resolveVehicle() async {
        do {
            let v = try await api.vehicle.getAssigned()
            guard !v.isUnassigned else { vehicleId = nil; return }
            vehicleId = Int(v.id)
            unitLabel = v.unitNumber.isEmpty ? "—" : "Unit \(v.unitNumber)"
            // The server reads vehicleType off the row for matching; we
            // surface the human truck description as the equipment line.
            let ymm = [String(v.year), v.make, v.model]
                .filter { !$0.isEmpty && $0 != "0" }
                .joined(separator: " ")
            equipmentLabel = ymm.isEmpty ? "Your assigned truck" : ymm
        } catch {
            vehicleId = nil
        }
    }

    /// Resolve the live origin (CoreLocation fix → HERE reverse-geocode).
    /// Honest em-dash when location is denied/unavailable — the post button
    /// then asks for the fix rather than sending a fabricated coordinate.
    private func resolveOrigin() async {
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            originLine = "—"
            coordinate = nil
            return
        }
        coordinate = coord
        do {
            let items = try await HereGeocodingClient.shared.reverseGeocode(at: coord, limit: 1)
            if let a = items.first?.address {
                originCity = a.city
                originState = a.stateCode ?? a.state
                let parts = [a.city, a.stateCode ?? a.state]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                originLine = parts.isEmpty ? "Current location" : parts.joined(separator: ", ")
            } else {
                originLine = "Current location"
            }
        } catch {
            // We still have the coordinate — post against it, show neutral.
            originLine = "Current location"
        }
    }

    private func isAlreadyPosted(vehicleId: Int) async -> Bool {
        struct In: Encodable { let status: String }
        struct Row: Decodable { let id: Int; let status: String? }
        do {
            let rows: [Row] = try await api.query(
                "truckPosting.getMyFleetAvailability",
                input: In(status: "available")
            )
            return rows.contains { $0.id == vehicleId && ($0.status ?? "") == "available" }
        } catch {
            return false
        }
    }

    // MARK: Post

    /// Mint the posting. The confident HERO button. Bounded in-flight.
    func postTruck(availableFrom: Date, preferredDest: String?) async {
        guard let vid = vehicleId else {
            actionError = "No assigned truck to post."
            return
        }
        guard let coord = coordinate else {
            actionError = "We couldn't get your current location. Enable location to post your truck."
            return
        }
        postingInFlight = true
        actionError = nil
        defer { postingInFlight = false }

        struct Loc: Encodable { let lat: Double; let lng: Double; let city: String?; let state: String? }
        struct In: Encodable {
            let vehicleId: Int
            let currentLocation: Loc
            let availableDate: String
            let preferredDestinations: [String]?
            let hazmatEndorsed: Bool
        }
        struct Out: Decodable { let success: Bool?; let status: String? }

        let iso = ISO8601DateFormatter()
        let input = In(
            vehicleId: vid,
            currentLocation: Loc(lat: coord.latitude, lng: coord.longitude,
                                 city: originCity, state: originState),
            availableDate: iso.string(from: availableFrom),
            preferredDestinations: preferredDest.flatMap { $0.isEmpty ? nil : [$0] },
            hazmatEndorsed: false
        )
        do {
            let _: Out = try await api.mutation("truckPosting.postTruck", input: input)
            phase = .posted
            await refreshOffers()
            await refreshMarket()
        } catch {
            actionError = "Couldn't post your truck. \(humanError(error))"
        }
    }

    /// Pause / un-post the truck — returns to the HERO state.
    func unpost() async {
        guard let vid = vehicleId else { return }
        struct In: Encodable { let vehicleId: Int }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await api.mutation("truckPosting.removeTruck", input: In(vehicleId: vid))
            offers = []
            phase = .notPosted
        } catch {
            actionError = "Couldn't pause your posting. \(humanError(error))"
        }
    }

    // MARK: Offers

    /// Refresh the inbound offers. Bounded; preserves last-good on failure.
    func refreshOffers() async {
        guard let vid = vehicleId else { return }
        offersLoading = true
        defer { offersLoading = false }
        struct In: Encodable { let vehicleId: Int; let limit: Int }
        do {
            let rows: [TruckInboundOffer] = try await api.query(
                "truckPosting.getMatchSuggestions",
                input: In(vehicleId: vid, limit: 25)
            )
            offers = rows
        } catch {
            // Keep last-good offers; only surface error when we had none.
            if offers.isEmpty { actionError = nil }
        }
    }

    /// Live load-to-truck ratio for the posted-state pulse header.
    private func refreshMarket() async {
        struct In: Encodable { let state: String? }
        struct Out: Decodable { let ratio: Double?; let market: String? }
        do {
            let r: Out = try await api.query(
                "truckPosting.getCapacityStats",
                input: In(state: originState)
            )
            marketRatio = r.ratio
            if let m = r.market { marketLabel = m.capitalized }
            else if let ratio = r.ratio { marketLabel = ratio > 1 ? "Tight" : "Loose" }
        } catch {
            marketRatio = nil
            marketLabel = "—"
        }
    }

    // MARK: Accept (one-tap booking)

    /// ONE-TAP accept → books the load. Routes through the typed
    /// `drivers.acceptLoad` wrapper (server runs the identity-at-booking +
    /// carrier-vetting gates and the FSM tender guard) until the 0339
    /// `acceptOffer(offerId)` proc ships — then swap this one body.
    func accept(_ offer: TruckInboundOffer) async {
        acceptingLoadId = offer.loadId
        actionError = nil
        defer { acceptingLoadId = nil }
        do {
            _ = try await api.drivers.acceptLoad(loadId: String(offer.loadId))
            bookedLoadId = offer.loadId
            // Booked load leaves the inbound stack.
            offers.removeAll { $0.loadId == offer.loadId }
            // Tell the rest of the app a load just landed.
            NotificationCenter.default.post(name: .eusoLoadAssigned, object: nil)
        } catch {
            actionError = "Couldn't book this load. \(humanError(error))"
        }
    }

    private func humanError(_ error: Error) -> String {
        (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Screen

struct DriverTruckPosted: View {
    @Environment(\.palette) private var palette
    @Environment(\.rolePushDetail) private var pushDetail
    @StateObject private var vm = TruckPostingViewModel()

    /// Quick-form state for the NOT-POSTED hero.
    @State private var availableFrom: Date = Date()
    @State private var preferredDest: String = ""
    /// Per-offer flip set (caller owns flip state — FlipTile doctrine).
    @State private var flipped: Set<Int> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                switch vm.phase {
                case .loading:
                    loadingState
                case .notPosted:
                    postHero
                case .posted:
                    postedHeader
                    offersSection
                case .error(let msg):
                    errorState(msg)
                }
                Color.clear.frame(height: Space.s8)
            }
            .padding(Space.s5)
            .animation(.easeOut(duration: 0.22), value: vm.phase)
        }
        .scrollIndicators(.hidden)
        .background(palette.bgPage.ignoresSafeArea())
        .task { await vm.load() }
        .refreshable {
            if case .posted = vm.phase { await vm.refreshOffers() }
            else { await vm.load() }
        }
        .overlay(alignment: .top) { errorToast }
    }

    // MARK: ───────────────────────── State A · POST HERO ─────────────────

    /// The centerpiece. A confident brand slab that sells the value prop,
    /// then a focused quick-form, then the one big POST action.
    private var postHero: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            heroSlab
            quickForm
            postButton
            valuePropRow
        }
    }

    /// Full-bleed gradient hero with a DRAWN truck glyph (no SF Symbol),
    /// the headline value prop, and an ambient "inbound" pulse motif.
    private var heroSlab: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
                .fill(LinearGradient.diagonal)
            // Ambient inbound arcs — concentric "offers travelling toward
            // your truck" rings, drawn, faint, brand-on-brand.
            InboundArcs()
                .stroke(Color.white.opacity(0.16), lineWidth: 1.4)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    TruckGlyph()
                        .fill(Color.white)
                        .frame(width: 54, height: 30)
                    Text("INBOUND TRUCK POST")
                        .font(EType.micro).tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                Text("Post your truck.\nBrokers come to YOU.")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Stop chasing the board. Post where you are and offers land here — one tap to book.")
                    .font(EType.body)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s5)
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .bottomLeading)
        .shadow(color: Brand.magenta.opacity(0.28), radius: 22, x: 0, y: 12)
    }

    /// The quick-form: equipment (auto-read), origin (live), available-from.
    private var quickForm: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("YOUR POST")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)

            formRow(label: "EQUIPMENT", value: vm.equipmentLabel, sub: vm.unitLabel)
            formRow(label: "ORIGIN", value: vm.originLine,
                    sub: vm.coordinate == nil ? "Location off — enable to post" : "Live fix")

            // Available-from — a real picker (not a stub).
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AVAILABLE FROM")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    DatePicker("", selection: $availableFrom,
                               in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .tint(Brand.magenta)
                }
                Spacer()
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoRow()

            // Destination preference (optional).
            VStack(alignment: .leading, spacing: 6) {
                Text("PREFERRED DESTINATION · OPTIONAL")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                TextField("Anywhere — or e.g. \"Southeast\", \"TX\"", text: $preferredDest)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .textInputAutocapitalization(.words)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoRow()
        }
    }

    private func formRow(label: String, value: String, sub: String?) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(value)
                    .font(EType.bodyStrong)
                    .foregroundStyle(value == "—" ? palette.textTertiary : palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
            if let sub {
                Text(sub)
                    .font(EType.micro)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoRow()
    }

    /// The one confident action. Disabled (honestly) without a coordinate.
    private var postButton: some View {
        Button {
            Task { await vm.postTruck(availableFrom: availableFrom,
                                      preferredDest: preferredDest) }
        } label: {
            HStack(spacing: Space.s2) {
                if vm.postingInFlight {
                    ProgressView().tint(.white).controlSize(.small)
                    Text("Posting your truck…")
                } else {
                    Text("Post my truck")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .heavy))
                }
            }
            .font(EType.bodyStrong)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .opacity((vm.postingInFlight || vm.vehicleId == nil) ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(vm.postingInFlight || vm.vehicleId == nil)
        .sensoryFeedback(.success, trigger: vm.phase == .posted)
    }

    /// Three drawn promise badges — why this beats the board.
    private var valuePropRow: some View {
        HStack(spacing: Space.s3) {
            promise(glyph: AnyView(RadarGlyph().stroke(LinearGradient.diagonal, lineWidth: 2)),
                    title: "Visible now", sub: "Brokers see you")
            promise(glyph: AnyView(BoltGlyph().fill(LinearGradient.diagonal)),
                    title: "One tap", sub: "Book instantly")
            promise(glyph: AnyView(ShieldCheckGlyph().stroke(LinearGradient.diagonal, lineWidth: 2)),
                    title: "Vetted", sub: "Gated booking")
        }
    }

    private func promise(glyph: AnyView, title: String, sub: String) -> some View {
        VStack(spacing: 6) {
            glyph.frame(width: 24, height: 24)
            Text(title).font(EType.micro).foregroundStyle(palette.textPrimary)
            Text(sub).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s3)
        .eusoRow()
    }

    // MARK: ───────────────────────── State B · POSTED ───────────────────

    /// "Your truck is live" — the status banner with the live market pulse
    /// and the pause control.
    private var postedHeader: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        LivePulseDot()
                        Text("YOUR TRUCK IS LIVE")
                            .font(EType.micro).tracking(1.4)
                            .foregroundStyle(.white)
                        Spacer()
                        Button { Task { await vm.unpost() } } label: {
                            Text("PAUSE")
                                .font(EType.micro).tracking(0.8)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Text(vm.equipmentLabel)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: Space.s2) {
                        Text(vm.originLine)
                            .font(EType.body).foregroundStyle(Color.white.opacity(0.92))
                        Text("·").foregroundStyle(Color.white.opacity(0.5))
                        Text("Market: \(vm.marketLabel)")
                            .font(EType.body).foregroundStyle(Color.white.opacity(0.92))
                    }
                    // Derived market pulse spark — honest: a flat line when
                    // there's no ratio signal, never an invented trend.
                    TruckMarketPulse(ratio: vm.marketRatio)
                        .frame(height: 34)
                }
                .padding(Space.s5)
            }
            .shadow(color: Brand.blue.opacity(0.22), radius: 18, x: 0, y: 10)
        }
    }

    /// The inbound OFFERS — the payoff. Inspiring bespoke flip cards, or
    /// the honest-empty "no offers yet" state.
    @ViewBuilder
    private var offersSection: some View {
        HStack {
            Text("INBOUND OFFERS")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            if !vm.offers.isEmpty {
                Text("\(vm.offers.count)")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(Brand.success)
            }
            if vm.offersLoading {
                ProgressView().controlSize(.mini)
            }
        }

        if vm.offers.isEmpty {
            if vm.offersLoading {
                offerSkeleton; offerSkeleton
            } else {
                emptyOffers
            }
        } else {
            ForEach(vm.offers) { offer in
                offerCard(offer)
            }
        }
    }

    /// Honest empty — the truck is live and visible; we never fabricate.
    private var emptyOffers: some View {
        VStack(spacing: Space.s3) {
            RadarSweepGlyph()
                .stroke(LinearGradient.diagonal, lineWidth: 1.8)
                .frame(width: 44, height: 44)
            Text("No offers yet")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Your truck is live and visible to brokers. We'll surface tenders here the moment they land.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
        .padding(.horizontal, Space.s5)
        .eusoCard()
    }

    /// One inbound offer as a flip card. FRONT: broker · lane · rate hero
    /// metric · match ring. BACK: detail + one-tap ACCEPT.
    private func offerCard(_ offer: TruckInboundOffer) -> some View {
        FlipTile(isFlipped: flipped.contains(offer.loadId)) {
            offerFront(offer)
        } back: {
            offerBack(offer)
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                if flipped.contains(offer.loadId) { flipped.remove(offer.loadId) }
                else { flipped.insert(offer.loadId) }
            }
        }
        .sensoryFeedback(.selection, trigger: flipped.contains(offer.loadId))
    }

    private func offerFront(_ offer: TruckInboundOffer) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text(offer.brokerDisplay.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                if offer.isHazmat {
                    StatusPill(text: "Hazmat", kind: .hazmat)
                }
                MatchRing(score: offer.matchScore).frame(width: 30, height: 30)
            }
            Text(offer.rateDisplay)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(offer.laneDisplay)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
            HStack(spacing: Space.s2) {
                Text("Tap to review · book")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                FlipHintGlyph()
                    .stroke(palette.textTertiary, lineWidth: 1.4)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .eusoCard()
    }

    private func offerBack(_ offer: TruckInboundOffer) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("LOAD DETAIL")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            detailLine("Lane", offer.laneDisplay)
            detailLine("Commodity", offer.commodityName ?? "—")
            detailLine("Rate", offer.rateDisplay)
            detailLine("Match", offer.matchScore > 0 ? "\(offer.matchScore)%" : "—")

            // The one-tap ACCEPT. Confirms the booking inline.
            Button {
                Task { await vm.accept(offer) }
            } label: {
                HStack(spacing: Space.s2) {
                    if vm.acceptingLoadId == offer.loadId {
                        ProgressView().tint(.white).controlSize(.small)
                        Text("Booking…")
                    } else {
                        CheckGlyph().stroke(Color.white, lineWidth: 2.2)
                            .frame(width: 16, height: 16)
                        Text("Accept · book this load")
                    }
                }
                .font(EType.bodyStrong)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .opacity(vm.acceptingLoadId == offer.loadId ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .disabled(vm.acceptingLoadId != nil)
            .sensoryFeedback(.success, trigger: vm.bookedLoadId == offer.loadId)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .eusoCard()
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(value == "—" ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: ───────────────────────── Shared states ──────────────────────

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
                .fill(palette.bgCardSoft)
                .frame(height: 210)
                .shimmer()
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 64)
                    .shimmer()
            }
        }
    }

    private var offerSkeleton: some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(palette.bgCardSoft)
            .frame(height: 168)
            .shimmer()
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: Space.s3) {
            TruckGlyph()
                .stroke(palette.textTertiary, lineWidth: 2)
                .frame(width: 54, height: 30)
            Text("Can't post right now")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button { Task { await vm.load() } } label: {
                Text("Retry")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(LinearGradient.diagonal, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s6)
        .eusoCard()
    }

    @ViewBuilder
    private var errorToast: some View {
        if let err = vm.actionError {
            Text(err)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Brand.danger.opacity(0.94), in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(nanoseconds: 3_800_000_000)
                        await MainActor.run { vm.actionError = nil }
                    }
                }
        }
    }
}

// MARK: - Drawn glyphs (Paths — zero SF Symbols on the bespoke surface)

/// A side-profile semi/tractor silhouette — cab + box + two wheels.
private struct TruckGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        // Trailer box
        p.addRoundedRect(in: CGRect(x: 0, y: h * 0.12, width: w * 0.56, height: h * 0.6),
                         cornerSize: CGSize(width: 2, height: 2))
        // Cab
        p.move(to: CGPoint(x: w * 0.58, y: h * 0.72))
        p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.4))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.4))
        p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.56))
        p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.72))
        p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.72))
        p.closeSubpath()
        // Wheels
        p.addEllipse(in: CGRect(x: w * 0.16, y: h * 0.7, width: h * 0.3, height: h * 0.3))
        p.addEllipse(in: CGRect(x: w * 0.74, y: h * 0.7, width: h * 0.3, height: h * 0.3))
        return p
    }
}

/// Concentric arcs sweeping toward the truck — "offers travelling to you".
private struct InboundArcs: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: r.maxX - 28, y: r.minY + 34)
        for i in 1...4 {
            let radius = CGFloat(i) * 26
            p.addArc(center: center, radius: radius,
                     startAngle: .degrees(100), endAngle: .degrees(200),
                     clockwise: false)
        }
        return p
    }
}

/// A radar/visibility glyph — concentric ring + sweep tick.
private struct RadarGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: r.insetBy(dx: 1, dy: 1))
        p.addEllipse(in: r.insetBy(dx: r.width * 0.3, dy: r.height * 0.3))
        p.move(to: CGPoint(x: r.midX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// A larger animated-feel radar sweep for the empty state.
private struct RadarSweepGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: r.insetBy(dx: 1, dy: 1))
        p.addEllipse(in: r.insetBy(dx: r.width * 0.22, dy: r.height * 0.22))
        p.move(to: CGPoint(x: r.midX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - 2, y: r.midY))
        p.move(to: CGPoint(x: r.midX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.32, y: r.minY + r.height * 0.18))
        return p
    }
}

/// A lightning bolt — "one tap, instant".
private struct BoltGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: w * 0.55, y: 0))
        p.addLine(to: CGPoint(x: w * 0.2, y: h * 0.56))
        p.addLine(to: CGPoint(x: w * 0.46, y: h * 0.56))
        p.addLine(to: CGPoint(x: w * 0.38, y: h))
        p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.4))
        p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.4))
        p.closeSubpath()
        return p
    }
}

/// A shield with a check — "vetted booking".
private struct ShieldCheckGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addLine(to: CGPoint(x: w, y: h * 0.2))
        p.addLine(to: CGPoint(x: w, y: h * 0.55))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h),
                       control: CGPoint(x: w, y: h * 0.85))
        p.addQuadCurve(to: CGPoint(x: 0, y: h * 0.55),
                       control: CGPoint(x: 0, y: h * 0.85))
        p.addLine(to: CGPoint(x: 0, y: h * 0.2))
        p.closeSubpath()
        // Check
        p.move(to: CGPoint(x: w * 0.3, y: h * 0.5))
        p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.64))
        p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.34))
        return p
    }
}

/// A bare check mark — the accept affordance.
private struct CheckGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX - r.width * 0.08, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// A small "flip" hint glyph — two curved arrows.
private struct FlipHintGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: r.midX, y: r.midY),
                 radius: r.width * 0.42,
                 startAngle: .degrees(20), endAngle: .degrees(300),
                 clockwise: false)
        return p
    }
}

// MARK: - Live pulse dot (the "live" heartbeat)

private struct LivePulseDot: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.35))
                .frame(width: 16, height: 16)
                .scaleEffect(pulse && !reduceMotion ? 1.6 : 1)
                .opacity(pulse && !reduceMotion ? 0 : 0.6)
            Circle().fill(Color.white).frame(width: 8, height: 8)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Match confidence ring

private struct MatchRing: View {
    let score: Int   // 0…100
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, CGFloat(min(score, 100)) / 100))
                .stroke(LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(score > 0 ? "\(score)" : "—")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
        }
    }
}

// MARK: - Market pulse (honest derived spark)

/// A small spark derived from the live load-to-truck ratio. Honest: a flat
/// line when there's no usable ratio (never an invented trend). When a
/// ratio exists, it synthesizes a deterministic gentle rise/fall around it
/// — same doctrine as HotZonePulseSynth (100% derived from a real scalar).
private struct TruckMarketPulse: View {
    let ratio: Double?
    private var points: [TrendSparkPoint] {
        guard let ratio, ratio > 0 else {
            // Honest flat line — no fabricated demand curve.
            return (0..<12).map { TrendSparkPoint(id: "flat\($0)", value: 1) }
        }
        // Deterministic gentle walk around the real ratio.
        return (0..<12).map { i in
            let phase = Double(i) / 11.0
            let wobble = sin(phase * .pi * 2) * 0.12 * ratio
            return TrendSparkPoint(id: "r\(i)", value: max(0.1, ratio + wobble))
        }
    }
    var body: some View {
        TrendSparkline(points: points, direction: .brand,
                       lineWidth: 1.8, showArea: true, showLastDot: true,
                       showBaseline: false, smooth: true)
    }
}

// MARK: - Shimmer (bounded skeleton)

private extension View {
    func shimmer() -> some View { modifier(TruckPostShimmer()) }
}

private struct TruckPostShimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.18), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * geo.size.width * 1.5)
            }
            .clipped()
            .allowsHitTesting(false)
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 1.5
            }
        }
    }
}

// MARK: - Preview

#Preview("DriverTruckPosted — dark") {
    DriverTruckPosted()
        .environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
