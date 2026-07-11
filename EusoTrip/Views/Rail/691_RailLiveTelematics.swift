//
//  691_RailLiveTelematics.swift
//  EusoTrip — Rail Engineer · Live Telematics (RailPulse-style ingest view).
//
//  Bespoke port of "05 Rail/Dark-SVG/691 Rail Live Telematics.svg".
//  ARCHETYPE = LIVE-MAP — a rail-network map hero dominates the screen with a
//  telemetered car pin for every car in the cut that reports a position fix,
//  a live-feed badge, and a coverage count, over a per-car sensor panel. This
//  is the tracking surface, deliberately NOT a board (555 Consist) and NOT a
//  detail card.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getRailcars  EXISTS railShipments.ts:931 {limit} → {railcars:[
//        {railcarNumber,carType,status,currentLocation{lat,lng,description},
//         yardName,yardCoordinates{lat,lng}}], total}. This is the REAL position
//        feed: a car's own carrier-reported AEI/GPS fix (currentLocation), with
//        the spotted-yard coordinate as the fallback anchor. Pins plot only from
//        these real coordinates; a car with no fix is honestly "no feed", never
//        given an invented position.
//  VERIFIED ABSENT (honest state, never fabricated):
//    A RailPulse coalition sensor feed (impact-g, hatch, hand-brake, GPS age)
//    is not integrated on disk. The sensor panel surfaces what IS real — the
//    position fix and the car's operating status — and marks the coalition
//    sensor rows "no feed" rather than fabricating a g-reading or brake state.
//    coverage = cars with a real fix ÷ total, computed live, never a claim.
//

import SwiftUI

struct RailLiveTelematicsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailLiveTelematicsBody()
        } nav: {
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

// MARK: - Data shapes (mirror railShipments.getRailcars)

private struct Coord691: Decodable { let lat: Double?; let lng: Double? }

private struct Railcar691: Decodable, Identifiable {
    let id: Int?
    let railcarNumber: String?
    let carType: String?
    let status: String?
    let owner: String?
    let currentLocation: Loc?
    let yardName: String?
    let yardCoordinates: Coord691?
    struct Loc: Decodable { let lat: Double?; let lng: Double?; let description: String? }
    var rowId: Int { id ?? railcarNumber.hashValue }

    /// Real position: the car's own AEI/GPS fix first, its spotted yard second.
    var fix: (lat: Double, lng: Double)? {
        if let la = currentLocation?.lat, let ln = currentLocation?.lng { return (la, ln) }
        if let la = yardCoordinates?.lat, let ln = yardCoordinates?.lng { return (la, ln) }
        return nil
    }
    var hasFix: Bool { fix != nil }
    var display: String { railcarNumber ?? "Railcar" }
    var whereText: String {
        currentLocation?.description ?? yardName ?? (hasFix ? "position on file" : "no position")
    }
}

private struct RailcarsResult691: Decodable { let railcars: [Railcar691]?; let total: Int? }
private struct RailcarsInput691: Encodable { let limit: Int }

// MARK: - Body

private struct RailLiveTelematicsBody: View {
    @Environment(\.palette) private var palette
    @State private var cars: [Railcar691] = []
    @State private var total = 0
    @State private var selected: Int? = nil
    @State private var loading = true
    @State private var refreshing = false
    @State private var regime = 0

    private let regimes: [(String, String)] = [("US · RAILPULSE", "coalition"),
                                               ("CA · RAILPULSE", "coalition"),
                                               ("MX · FXE GPS",   "non-member")]

    private var telemetered: [Railcar691] { cars.filter { $0.hasFix } }
    private var selectedCar: Railcar691? {
        if let s = selected, let c = cars.first(where: { $0.rowId == s }) { return c }
        return telemetered.first ?? cars.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Live telematics")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text(cars.isEmpty ? "Telemetered car positions across the cut"
                              : "\(telemetered.count) of \(max(total, cars.count)) cars reporting a fix")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    mapHero
                    if let car = selectedCar {
                        sensorHeader(car)
                        sensorPanel(car)
                        carSelector
                    } else {
                        EusoEmptyState(systemImage: "dot.radiowaves.left.and.right",
                                       title: "No telemetered cars",
                                       subtitle: "No car in the cut reports a position fix. As cars pass a reader or coalition gateway, their pins appear on the map above.")
                    }
                    triBand
                    footerActions
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ CARRIER · RAIL · TELEMATICS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle().fill(Brand.success).frame(width: 6, height: 6)
                Text("RAILPULSE · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("\(telemetered.count) live", telemetered.isEmpty ? palette.textSecondary : Brand.success)
            chip("\(max(0, cars.count - telemetered.count)) no feed", palette.textSecondary)
            chip(regimes[regime].1, Brand.blue)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Map hero — real pins from real coordinates, normalized to the panel.

    private var mapHero: some View {
        let pts = telemetered.compactMap { car -> (Railcar691, Double, Double)? in
            guard let f = car.fix else { return nil }
            return (car, f.lat, f.lng)
        }
        let lats = pts.map { $0.1 }, lngs = pts.map { $0.2 }
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 1
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 1
        return VStack(spacing: 0) {
            HStack {
                Text("NETWORK MAP · TELEMETERED CARS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(telemetered.isEmpty ? "awaiting fixes" : "\(telemetered.count) pins live")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.success)
            }
            .padding(.horizontal, 16).frame(height: 40)
            GeometryReader { g in
                ZStack {
                    // Faint network graticule — a map surface, not a chart.
                    Path { p in
                        for i in 1..<5 { let x = g.size.width * CGFloat(i) / 5; p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: g.size.height)) }
                        for i in 1..<4 { let y = g.size.height * CGFloat(i) / 4; p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y)) }
                    }.stroke(palette.borderFaint, lineWidth: 0.5)
                    // Route spine through the pins, ordered W→E.
                    if pts.count >= 2 {
                        Path { p in
                            let ordered = pts.sorted { $0.2 < $1.2 }
                            for (idx, pt) in ordered.enumerated() {
                                let cp = plot(pt.1, pt.2, minLat, maxLat, minLng, maxLng, g.size)
                                if idx == 0 { p.move(to: cp) } else { p.addLine(to: cp) }
                            }
                        }.stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(pts.enumerated()), id: \.offset) { _, pt in
                        let cp = plot(pt.1, pt.2, minLat, maxLat, minLng, maxLng, g.size)
                        let isSel = pt.0.rowId == selectedCar?.rowId
                        ZStack {
                            Circle().fill((isSel ? Brand.blue : Brand.success).opacity(0.22)).frame(width: isSel ? 26 : 18, height: isSel ? 26 : 18)
                            Circle().fill(isSel ? Brand.blue : Brand.success).frame(width: 9, height: 9)
                        }
                        .position(cp)
                        .onTapGesture { selected = pt.0.rowId }
                    }
                    if pts.isEmpty {
                        Text("No position fixes to plot")
                            .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .frame(height: 190)
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
        .background(LinearGradient(colors: [palette.bgCardSoft, palette.bgCard], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func plot(_ lat: Double, _ lng: Double, _ minLat: Double, _ maxLat: Double, _ minLng: Double, _ maxLng: Double, _ size: CGSize) -> CGPoint {
        let padX: CGFloat = 18, padY: CGFloat = 18
        let w = size.width - padX * 2, h = size.height - padY * 2
        let nx = maxLng - minLng == 0 ? 0.5 : (lng - minLng) / (maxLng - minLng)
        let ny = maxLat - minLat == 0 ? 0.5 : (lat - minLat) / (maxLat - minLat)
        return CGPoint(x: padX + w * CGFloat(nx), y: padY + h * (1 - CGFloat(ny)))
    }

    private func sensorHeader(_ car: Railcar691) -> some View {
        HStack {
            Text("CAR \(car.display) · SENSOR HEALTH")
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(car.whereText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(palette.textTertiary).lineLimit(1)
        }
    }

    // MARK: Sensor panel — real fields real, coalition sensors honestly "no feed".

    private func sensorPanel(_ car: Railcar691) -> some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            sensorTile("Position", icon: "location.fill",
                       value: car.hasFix ? "ON FILE" : "NO FIX",
                       sub: car.hasFix ? car.whereText : "no reader pass yet",
                       tone: car.hasFix ? Brand.success : Brand.warning, live: car.hasFix)
            sensorTile("Car status", icon: "info.circle.fill",
                       value: (car.status ?? "unknown").uppercased(),
                       sub: car.carType.map { "type \($0)" } ?? "type unlisted",
                       tone: Brand.info, live: car.status != nil)
            sensorTile("Impact", icon: "waveform.path.ecg",
                       value: "NO FEED",
                       sub: "RailPulse coalition not connected",
                       tone: palette.textTertiary, live: false)
            sensorTile("Hand brake", icon: "hand.raised.fill",
                       value: "NO FEED",
                       sub: "coalition sensor not connected",
                       tone: palette.textTertiary, live: false)
        }
    }

    private func sensorTile(_ label: String, icon: String, value: String, sub: String, tone: Color, live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(tone)
                Spacer()
                if live {
                    HStack(spacing: 4) {
                        Circle().fill(Brand.success).frame(width: 5, height: 5)
                        Text("live").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.success)
                    }
                }
            }
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 17, weight: .bold)).foregroundStyle(tone == palette.textTertiary ? palette.textSecondary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private var carSelector: some View {
        if cars.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cars) { car in
                        let isSel = car.rowId == selectedCar?.rowId
                        VStack(alignment: .leading, spacing: 2) {
                            Text(car.display).font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundStyle(isSel ? palette.textPrimary : palette.textSecondary)
                            HStack(spacing: 4) {
                                Circle().fill(car.hasFix ? Brand.success : palette.textTertiary).frame(width: 5, height: 5)
                                Text(car.hasFix ? "live" : "no feed").font(.system(size: 8)).foregroundStyle(palette.textTertiary)
                            }
                        }
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .fill(isSel ? palette.bgCardSoft : palette.bgCard))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(isSel ? Brand.blue.opacity(0.5) : palette.borderFaint))
                        .onTapGesture { selected = car.rowId }
                    }
                }
            }
        }
    }

    private var triBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == regime ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { regime = i }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            RailSecondaryActionButton(
                title: "Open car detail",
                sheetTitle: selectedCar.map { "Car \($0.display)" } ?? "Car detail",
                lines: selectedCar.map { car in
                    ["Mark · \(car.display)",
                     "Type · \(car.carType ?? "unlisted")",
                     "Status · \(car.status ?? "unknown")",
                     "Position · \(car.hasFix ? car.whereText : "no fix on file")",
                     car.hasFix ? "Fix source · \(car.currentLocation?.lat != nil ? "car AEI/GPS" : "spotted yard anchor")" : "Awaiting first reader pass"]
                } ?? ["No car selected."],
                fillWidth: true,
                systemImage: "tram.fill")
            Button(action: { Task { await reload(isRefresh: true) } }) {
                Text(refreshing ? "Refreshing…" : "Refresh")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 118)
                    .frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(refreshing)
        }
    }

    private func reload(isRefresh: Bool = false) async {
        if isRefresh { refreshing = true } else { loading = true }
        let r: RailcarsResult691? = try? await EusoTripAPI.shared.query(
            "railShipments.getRailcars", input: RailcarsInput691(limit: 25))
        self.cars = r?.railcars ?? []
        self.total = r?.total ?? cars.count
        loading = false; refreshing = false
    }
}

#Preview("691 · Rail Live Telematics · Night") {
    RailLiveTelematicsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("691 · Rail Live Telematics · Light") {
    RailLiveTelematicsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
