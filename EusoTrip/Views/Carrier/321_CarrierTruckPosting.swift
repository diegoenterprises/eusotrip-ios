//
//  321_CarrierTruckPosting.swift
//  EusoTrip — Carrier · TruckPosting board (brick 321; registry id "321C").
//
//  NOTE for registration: the carrier+catalyst surfaces share one lookup
//  pool, and registry id "321" is ALREADY taken by `.catalyst` "Driver
//  Profile" (ContentView). To avoid the dup/destroy collision (iOS
//  numbering ≠ purpose), register THIS screen under the carrier-
//  disambiguated id "321C" — the file number stays 321 (folder sibling of
//  320_CarrierVehiclesList). Suffix ids are an established convention here
//  ("404B", "402b", "Disp400").
//
//  The carrier-side "post your truck → brokers/loads come to you →
//  one-tap accept" board. iOS parity for the web TruckPosting surface
//  (PR #112) against the LIVE `truckPostingRouter`
//  (frontend/server/routers/truckPosting.ts, mounted as `truckPosting`).
//
//  Three sections, every one wired to a real proc — zero fabrication:
//
//    1. POSTING HERO — pick an AVAILABLE fleet vehicle, POST it
//       (truckPosting.postTruck) or PAUSE/resume the active posting
//       (truckPosting.pauseTruck). A live market CAPACITY-STATS grid
//       (truckPosting.getCapacityStats: available trucks vs posted
//       loads, hazmat split, tight/balanced/loose verdict) sits under
//       the control. Every absent number em-dashes — never a fake row.
//
//    2. INBOUND OFFERS — truckPosting.listInboundOffers. Each card:
//       broker · lane (origin→dest via TransportLexicon) · rate ·
//       equipment/commodity. One-tap ACCEPT (truckPosting.acceptOffer)
//       / DECLINE (truckPosting.declineOffer). Accept is DUAL-GATED on
//       the server (identity-at-booking + Montgomery carrier-vetting);
//       a gate BLOCK is surfaced HONESTLY via TruckPostingGateError
//       instead of a generic auth error.
//
//    3. MY FLEET — truckPosting.getMyFleetAvailability. The company's
//       vehicles with live operational status (available / in_use /
//       maintenance / out_of_service) and next-service dates.
//
//  No-lingering-load doctrine: every call flows through the shared
//  EusoTripAPI.session (22s request / 120s resource ceiling), last-good
//  rows stay on screen while a refresh runs, and every isLoading flag is
//  guaranteed to resolve in a `defer`. Navigation is the carrier surface
//  push/swap chrome — no slide-up modals. Mode-dependent freight terms
//  resolve through TransportLexicon (truck = BOL/origin/destination).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen wrapper

struct CarrierTruckPostingScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            CarrierTruckPostingBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Fleet", systemImage: "truck.box.fill", isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",         isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct CarrierTruckPostingBody: View {
    @Environment(\.palette) private var palette

    // The truck-posting board is a truck-mode surface; freight terms
    // (origin / destination / BOL) resolve through the truck lexicon.
    private let mode: TransportMode = .truck

    // ── Capacity stats (hero grid) ──
    @State private var stats: TruckCapacityStats? = nil
    @State private var statsLoading = true
    @State private var statsError: String? = nil

    // ── Inbound offers ──
    @State private var offers: [CarrierTruckInboundOffer] = []
    @State private var offersLoading = true
    @State private var offersError: String? = nil
    @State private var actingOfferId: Int? = nil          // accept/decline in flight

    // ── My fleet ──
    @State private var fleet: [TruckFleetVehicle] = []
    @State private var fleetLoading = true
    @State private var fleetError: String? = nil

    // ── Posting hero control ──
    @State private var selectedVehicleId: Int? = nil
    @State private var activePostingId: Int? = nil        // hydrated from the durable posting row
    @State private var postingStatus: String? = nil       // "active" / "paused" / nil
    @State private var posting = false                     // post/pause in flight
    @State private var heroBanner: String? = nil           // success line
    @State private var heroError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let b = heroBanner {
                    LifecycleCard(accentGradient: true) {
                        Text(b).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let e = heroError {
                    LifecycleCard(accentDanger: true) {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                postingHero
                inboundOffersSection
                myFleetSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · CAPACITY · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Post your truck")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Post an available truck and brokers’ open loads come to you. Accept the right offer in one tap — identity and carrier-vetting are verified before the load books.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 1 — Posting hero

    @ViewBuilder
    private var postingHero: some View {
        LifecycleCard(accentGradient: postingStatus == "active") {
            LifecycleSection(label: "POSTING", icon: "dot.radiowaves.up.forward")

            // Vehicle picker — only AVAILABLE vehicles can be posted.
            let availableFleet = fleet.filter { ($0.status ?? "").lowercased() == "available" }
            if fleetLoading && fleet.isEmpty {
                Text("Loading your fleet…")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else if availableFleet.isEmpty {
                Text("No available trucks to post. Free up a vehicle in MY FLEET below (a truck must be AVAILABLE — not in-use, in the shop, or out of service).")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("CHOOSE A TRUCK")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableFleet) { v in
                            vehicleChip(v)
                        }
                    }
                }
            }

            // Post / pause control.
            postControl(availableCount: availableFleet.count)

            // Live capacity stats grid.
            Divider().overlay(palette.borderFaint)
            capacityGrid
        }
    }

    private func vehicleChip(_ v: TruckFleetVehicle) -> some View {
        let isSel = selectedVehicleId == v.id
        let title = vehicleTitle(v)
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { selectedVehicleId = v.id }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .lineLimit(1)
                Text((v.vehicleType ?? "—").replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
            }
            .foregroundStyle(isSel ? .white : palette.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(isSel ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSel ? AnyShapeStyle(Color.clear) : AnyShapeStyle(palette.borderFaint), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func postControl(availableCount: Int) -> some View {
        if let pid = activePostingId, let st = postingStatus, st != "matched" {
            // We have an active posting we minted this session — show
            // pause/resume + status.
            HStack(spacing: 8) {
                statusPill(st)
                Spacer(minLength: 0)
                Button {
                    Task { await pauseResume(postingId: pid) }
                } label: {
                    HStack(spacing: 6) {
                        if posting { ProgressView().scaleEffect(0.6).tint(.white) }
                        Image(systemName: st == "paused" ? "play.fill" : "pause.fill")
                            .font(.system(size: 11, weight: .heavy))
                        Text(st == "paused" ? "RESUME POSTING" : "PAUSE POSTING")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(posting)
            }
        } else {
            // No live posting from this session — show POST.
            let geoReady = selectedVehicleGeoReady
            Button {
                Task { await postSelectedTruck() }
            } label: {
                HStack(spacing: 6) {
                    if posting { ProgressView().scaleEffect(0.6).tint(.white) }
                    Image(systemName: "paperplane.fill").font(.system(size: 11, weight: .heavy))
                    Text("POST THIS TRUCK")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    (selectedVehicleId != nil && geoReady)
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.bgCardSoft)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(posting || selectedVehicleId == nil || !geoReady || availableCount == 0)

            if selectedVehicleId != nil && !geoReady {
                Text("This truck has no live GPS position yet, so it can’t be posted to the market. Its location syncs once the driver’s device reports a fix.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusPill(_ st: String) -> some View {
        let isActive = st == "active"
        return Text(st.uppercased())
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(isActive ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.warning))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .overlay(
                Capsule().strokeBorder(
                    isActive ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.5)) : AnyShapeStyle(Brand.warning.opacity(0.5)),
                    lineWidth: 1
                )
            )
    }

    @ViewBuilder
    private var capacityGrid: some View {
        if statsLoading && stats == nil {
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCardSoft)
                        .frame(height: 56)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                }
            }
        } else if let e = statsError, stats == nil {
            Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
        } else if let s = stats {
            VStack(alignment: .leading, spacing: Space.s2) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                                    GridItem(.flexible(), spacing: Space.s2),
                                    GridItem(.flexible(), spacing: Space.s2)],
                          spacing: Space.s2) {
                    statTile(label: "AVAIL TRUCKS", value: "\(s.availableTrucks)", sub: "market-wide")
                    statTile(label: "OPEN LOADS",   value: "\(s.postedLoads)",     sub: "posted / bidding")
                    statTile(label: "LOAD/TRUCK",   value: ratioText(s),           sub: marketVerdict(s))
                    statTile(label: "HAZMAT TRUCKS", value: "\(s.hazmatTrucks)",    sub: "endorsed capacity")
                    statTile(label: "HAZMAT LOADS",  value: "\(s.hazmatLoads)",     sub: "open hazmat freight")
                    statTile(label: "HAZMAT RATIO",  value: hazmatRatioText(s),     sub: "load / truck")
                }
            }
        } else {
            Text("Market capacity isn’t available right now.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func statTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text(sub)
                .font(.system(size: 8, weight: .semibold)).tracking(0.2)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s2)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: 2 — Inbound offers

    @ViewBuilder
    private var inboundOffersSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("INBOUND OFFERS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if !offers.isEmpty {
                    Text("\(offers.count)")
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient.diagonal))
                }
            }

            if offersLoading && offers.isEmpty {
                offersSkeleton
            } else if let e = offersError, offers.isEmpty {
                LifecycleCard(accentDanger: true) {
                    Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if offers.isEmpty {
                EusoEmptyState(
                    systemImage: "tray",
                    title: "No inbound offers yet",
                    subtitle: "Post a truck above and compatible open loads land here as offers. Brokers can also offer a load directly to your posted truck."
                )
            } else {
                ForEach(offers) { offer in
                    offerCard(offer)
                }
            }
        }
    }

    private func offerCard(_ o: CarrierTruckInboundOffer) -> some View {
        let acting = actingOfferId == o.offerId
        let pending = o.status.lowercased() == "pending"
        return LifecycleCard(accentGradient: pending) {
            // Broker + status line.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dashIfEmpty(o.broker?.name))
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(o.load?.loadNumber.map { "Load \($0)" } ?? "Load —")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                Text(o.status.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(offerStatusColor(o.status))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(offerStatusColor(o.status).opacity(0.5), lineWidth: 1))
            }

            // Lane — origin → destination via TransportLexicon (truck = BOL).
            laneRow(o.load)

            // Detail rows.
            LifecycleRow(label: "Offered rate", value: moneyText(o.offeredRate))
            LifecycleRow(label: "Equipment",
                         value: dashIfEmpty(o.load?.cargoType?.replacingOccurrences(of: "_", with: " ").capitalized))
            if let commodity = o.load?.commodityName, !commodity.isEmpty {
                LifecycleRow(label: "Commodity", value: commodity)
            }
            if let hz = o.load?.hazmatClass, !hz.isEmpty {
                LifecycleRow(label: "Hazmat class", value: hz)
            }
            LifecycleRow(label: TransportLexicon.short(.originWindow, mode: mode),
                         value: humanISO(o.load?.pickupDate, format: "MMM d · HH:mm"))

            // Actions — one-tap accept / decline (pending only).
            if pending {
                HStack(spacing: Space.s2) {
                    Button {
                        Task { await decline(o) }
                    } label: {
                        HStack(spacing: 5) {
                            if acting { ProgressView().scaleEffect(0.55) }
                            Image(systemName: "xmark").font(.system(size: 10, weight: .heavy))
                            Text("DECLINE").font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        }
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(acting)

                    Button {
                        Task { await accept(o) }
                    } label: {
                        HStack(spacing: 5) {
                            if acting { ProgressView().scaleEffect(0.55).tint(.white) }
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                            Text("ACCEPT").font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(acting)
                }
                .padding(.top, 2)

                Text("Accepting verifies your identity and carrier authority / insurance before the load books.")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func laneRow(_ load: CarrierTruckInboundOffer.OfferLoad?) -> some View {
        let origin = placeLabel(load?.origin)
        let dest = placeLabel(load?.destination)
        return HStack(spacing: 6) {
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("\(origin)  →  \(dest)")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    // MARK: 3 — My fleet

    @ViewBuilder
    private var myFleetSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("MY FLEET")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if !fleet.isEmpty {
                    Text("\(fleet.count)")
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }

            if fleetLoading && fleet.isEmpty {
                offersSkeleton
            } else if let e = fleetError, fleet.isEmpty {
                LifecycleCard(accentDanger: true) {
                    Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if fleet.isEmpty {
                EusoEmptyState(
                    systemImage: "truck.box",
                    title: "No vehicles",
                    subtitle: "Add tractors / trailers via the carrier admin or bulk-upload, then post your available capacity here."
                )
            } else {
                ForEach(fleet) { v in
                    fleetRow(v)
                }
            }
        }
    }

    private func fleetRow(_ v: TruckFleetVehicle) -> some View {
        let st = (v.status ?? "unknown").lowercased()
        return LifecycleCard(
            accentDanger: st == "out_of_service",
            accentWarning: st == "maintenance",
            accentGradient: st == "available"
        ) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicleTitle(v))
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text((v.vehicleType ?? "—").replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                Text(st.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(fleetStatusColor(st))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(fleetStatusColor(st).opacity(0.5), lineWidth: 1))
            }
            LifecycleRow(label: "VIN",          value: dashIfEmpty(v.vin))
            LifecycleRow(label: "Plate",        value: dashIfEmpty(v.licensePlate))
            LifecycleRow(label: "Capacity",     value: capacityText(v.capacity))
            LifecycleRow(label: "Next service", value: humanISO(v.nextMaintenance, format: "MMM d, yyyy"))
            LifecycleRow(label: "Last GPS",     value: humanISO(v.lastGPSUpdate, format: "MMM d · HH:mm"))
        }
    }

    // MARK: - Shared skeleton

    private var offersSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Loaders

    private func loadAll() async {
        async let a: Void = loadStats()
        async let b: Void = loadOffers()
        async let c: Void = loadFleet()
        async let d: Void = loadPosting()
        _ = await (a, b, c, d)
    }

    private func loadStats() async {
        statsLoading = true; defer { statsLoading = false }
        do {
            stats = try await EusoTripAPI.shared.truckPosting.getCapacityStats()
            statsError = nil
        } catch {
            // Keep last-good stats on screen; only surface the error when
            // there's nothing to show.
            statsError = humanError(error)
        }
    }

    private func loadOffers() async {
        offersLoading = true; defer { offersLoading = false }
        do {
            let env = try await EusoTripAPI.shared.truckPosting.listInboundOffers(status: "pending")
            offers = env.offers
            offersError = env.matcherStatus == "degraded"
                ? "Existing offers are available, but matching new loads is temporarily delayed."
                : nil
        } catch {
            offersError = humanError(error)
        }
    }

    private func loadPosting() async {
        do {
            let posting = try await EusoTripAPI.shared.truckPosting.getPosting()
            activePostingId = posting?.id
            postingStatus = posting?.status
            if let vehicleId = posting?.vehicleId {
                selectedVehicleId = vehicleId
            }
        } catch {
            heroError = "Couldn't load the current truck posting. \(humanError(error))"
        }
    }

    private func loadFleet() async {
        fleetLoading = true; defer { fleetLoading = false }
        do {
            fleet = try await EusoTripAPI.shared.truckPosting.getMyFleetAvailability()
            fleetError = nil
            // Default-select the first available truck if none chosen.
            if selectedVehicleId == nil {
                selectedVehicleId = fleet.first(where: { ($0.status ?? "").lowercased() == "available" })?.id
            }
        } catch {
            fleetError = humanError(error)
        }
    }

    // MARK: - Actions

    private func postSelectedTruck() async {
        guard let vid = selectedVehicleId,
              let v = fleet.first(where: { $0.id == vid }),
              let lat = v.location?.lat, let lng = v.location?.lng else {
            heroError = "Select an available truck with a live GPS position to post."
            return
        }
        posting = true; heroError = nil; heroBanner = nil
        defer { posting = false }
        do {
            let loc = TruckPostLocation(lat: lat, lng: lng, city: nil, state: nil)
            let result = try await EusoTripAPI.shared.truckPosting.postTruck(
                vehicleId: vid,
                currentLocation: loc,
                availableDate: ISO8601DateFormatter().string(from: Date()),
                equipmentType: v.vehicleType
            )
            activePostingId = result.postingId
            postingStatus = result.status
            let surfaced = result.offersSurfaced ?? 0
            if result.matcherStatus == "degraded" {
                heroBanner = "\(vehicleTitle(v)) posted. New-offer matching is temporarily delayed; the posting remains live."
            } else {
                heroBanner = surfaced > 0
                    ? "\(vehicleTitle(v)) posted — \(surfaced) compatible open load\(surfaced == 1 ? "" : "s") surfaced as offer\(surfaced == 1 ? "" : "s")."
                    : "\(vehicleTitle(v)) posted. Compatible open loads will land in INBOUND OFFERS as they’re posted."
            }
            // Refresh offers + fleet (the vehicle is now flagged available/posted).
            await loadOffers()
            await loadFleet()
        } catch {
            heroError = humanError(error)
        }
    }

    private func pauseResume(postingId: Int) async {
        posting = true; heroError = nil; heroBanner = nil
        defer { posting = false }
        do {
            let result = try await EusoTripAPI.shared.truckPosting.pauseTruck(postingId: postingId)
            postingStatus = result.status
            if result.matcherStatus == "degraded" {
                heroBanner = "Posting resumed, but new-offer matching is temporarily delayed."
            } else {
                heroBanner = result.status == "paused"
                    ? "Posting paused — no new inbound offers until you resume."
                    : "Posting resumed."
            }
            await loadOffers()
        } catch {
            heroError = humanError(error)
        }
    }

    private func accept(_ o: CarrierTruckInboundOffer) async {
        actingOfferId = o.offerId; heroError = nil; heroBanner = nil
        defer { actingOfferId = nil }
        do {
            let result = try await EusoTripAPI.shared.truckPosting.acceptOffer(offerId: o.offerId)
            let conf = result.confirmationNumber.map { " (\($0))" } ?? ""
            heroBanner = "Offer accepted — load booked\(conf). The truck is now matched."
            postingStatus = "matched"
            // Reload: the matched posting expires sibling offers server-side.
            await loadOffers()
            await loadFleet()
        } catch let gate as TruckPostingGateError {
            // HONEST surface of the dual verification gate (identity /
            // carrier-vetting). The carrier sees exactly WHY it was blocked.
            heroError = gate.errorDescription
        } catch {
            heroError = humanError(error)
        }
    }

    private func decline(_ o: CarrierTruckInboundOffer) async {
        actingOfferId = o.offerId; heroError = nil; heroBanner = nil
        defer { actingOfferId = nil }
        do {
            _ = try await EusoTripAPI.shared.truckPosting.declineOffer(offerId: o.offerId)
            heroBanner = "Offer declined — your truck stays posted."
            await loadOffers()
        } catch {
            heroError = humanError(error)
        }
    }

    // MARK: - Formatting helpers (every absent value em-dashes)

    private var selectedVehicleGeoReady: Bool {
        guard let vid = selectedVehicleId,
              let v = fleet.first(where: { $0.id == vid }) else { return false }
        return v.location?.lat != nil && v.location?.lng != nil
    }

    private func vehicleTitle(_ v: TruckFleetVehicle) -> String {
        let parts = [v.year.map { "\($0)" }, v.make, v.model].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return "Vehicle #\(v.id)"
    }

    private func placeLabel(_ p: CarrierTruckInboundOffer.OfferLoad.Place?) -> String {
        guard let p else { return "—" }
        let city = p.city ?? ""
        let state = p.state ?? ""
        if !city.isEmpty && !state.isEmpty { return "\(city), \(state)" }
        if !city.isEmpty { return city }
        if !state.isEmpty { return state }
        return "—"
    }

    private func moneyText(_ v: Double?) -> String {
        guard let v, v > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func capacityText(_ v: Double?) -> String {
        guard let v, v > 0 else { return "—" }
        return "\(Int(v)) lb"
    }

    private func ratioText(_ s: TruckCapacityStats) -> String {
        s.availableTrucks > 0 ? String(format: "%.2f", s.ratio) : "—"
    }

    private func hazmatRatioText(_ s: TruckCapacityStats) -> String {
        guard let r = s.hazmatRatio, s.hazmatTrucks > 0 else { return "—" }
        return String(format: "%.2f", r)
    }

    private func marketVerdict(_ s: TruckCapacityStats) -> String {
        guard let m = s.market, s.availableTrucks > 0 else { return "—" }
        return m.uppercased()
    }

    private func offerStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "booked", "accepted": return Brand.blue
        case "declined", "expired": return Brand.danger
        default:                    return Brand.warning   // pending
        }
    }

    private func fleetStatusColor(_ st: String) -> Color {
        switch st {
        case "available":      return Brand.blue
        case "maintenance":    return Brand.warning
        case "out_of_service": return Brand.danger
        default:               return Brand.warning   // in_use / unknown
        }
    }

    private func humanError(_ error: Error) -> String {
        (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Previews
//
// Previews don't run `.task`, so each section stays in its loading
// register and renders the skeleton without hitting the network
// (doctrine §10 — previews compile + render in isolation, no live API).

#Preview("321 · TruckPosting · Night") {
    CarrierTruckPostingScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("321 · TruckPosting · Afternoon") {
    CarrierTruckPostingScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
