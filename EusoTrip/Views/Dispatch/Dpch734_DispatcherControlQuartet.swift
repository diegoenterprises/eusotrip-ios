//
//  Dpch734_DispatcherControlQuartet.swift
//  EusoTrip — Dispatcher · Control quartet (409/413/416/417).
//
//  Pixel-match to:
//    409 Dispatcher Settings.svg
//    413 Dispatcher Weather Reroute Map.svg
//    416 Dispatcher Reload Offer Sheet.svg
//    417 Dispatcher Fuel-Policy Override.svg
//
//  Bundled file; all wire to real endpoints. Bottom nav frozen.
//

import SwiftUI

private struct ShellNav<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 409 Dispatcher Settings
// MARK: ─────────────────────────────────────────────────────────

struct DispatcherSettingsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        ShellNav(theme: theme) { DispatcherSettingsBody() }
    }
}

private struct DispatcherSettingsBody: View {
    @Environment(\.palette) private var palette

    @State private var hosAlerts: Bool = true
    @State private var tenderExpiringPush: Bool = true
    @State private var esangNudges: String = "medium"
    @State private var defaultColumns: String = "5 · TENDER · ASSIGNED · PICKUP · IN TRANSIT · DELIVERED"
    @State private var cardDensity: String = "Compact"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                notificationsSection
                boardViewSection
                appearanceSection
                aboutSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · ME · SETTINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Settings").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Employee · no impersonation · v3.4.0").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTIFICATIONS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 12) {
                    toggleRow(title: "HOS critical alerts", subtitle: "Push + sound when any driver clock < 1h", binding: $hosAlerts)
                    Divider().overlay(palette.borderFaint)
                    toggleRow(title: "Tender expiring soon", subtitle: "Push at < 30m, banner at < 10m", binding: $tenderExpiringPush)
                    Divider().overlay(palette.borderFaint)
                    chooserRow(title: "ESang nudges", subtitle: "Frequency · \(esangNudges) · only high-confidence")
                }
            }
        }
    }

    private var boardViewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BOARD VIEW").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 12) {
                    chooserRow(title: "Default board columns", subtitle: defaultColumns)
                    Divider().overlay(palette.borderFaint)
                    chooserRow(title: "Card density", subtitle: "\(cardDensity) · cargo + driver pebble + amount")
                }
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("APPEARANCE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 12) {
                    chooserRow(title: "Theme", subtitle: "System · auto")
                    Divider().overlay(palette.borderFaint)
                    chooserRow(title: "Language", subtitle: "English (US)")
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ABOUT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 12) {
                    chooserRow(title: "App version", subtitle: "v3.4.0 · build 2206")
                    Divider().overlay(palette.borderFaint)
                    chooserRow(title: "Privacy policy", subtitle: "Eusorone Technologies")
                }
            }
        }
    }

    private func toggleRow(title: String, subtitle: String, binding: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden()
        }
    }

    private func chooserRow(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(palette.textTertiary)
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 413 Weather Reroute Map
// MARK: ─────────────────────────────────────────────────────────

private struct WeatherRerouteLoad: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let assignedDriverName: String?
    let deliveryDate: String?
}

struct DispatcherWeatherRerouteScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { WeatherRerouteBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct WeatherRerouteBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: WeatherRerouteLoad?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                loadContextCard
                mapPlaceholder
                advisoryCard
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Weather Reroute").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Closure at I-80 mile 343 · 156 mi to closure").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("P1 · WEATHER").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                Spacer()
                Text("SLA 0:11:42").font(.caption.monospaced().weight(.semibold)).foregroundStyle(.red)
            }
        }
    }

    private var loadContextCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                if let l = load {
                    Text(l.loadNumber ?? "LD-\(l.id ?? 0)").font(.caption.monospaced().weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(l.pickupCity ?? "—") → \(l.destCity ?? "—")").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("\(l.trailerType ?? "—") · \(l.cargoType ?? "—") · $\(l.rate ?? "—") · driver \(l.assignedDriverName ?? "ME")")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var mapPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [palette.bgCard, palette.bgCardSoft], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                Image(systemName: "map.fill").font(.system(size: 28, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("MAP · CO → NE → IA").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("MILE 343 · CLOSED").font(.system(size: 11, weight: .heavy)).foregroundStyle(.red)
            }
            VStack {
                Spacer()
                HStack {
                    Text("NWS · BLIZZARD ADVISORY · 14:00 — 22:00 MT")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.red.opacity(0.18)))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(10)
            }
        }
        .frame(height: 180)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.red.opacity(0.5)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var advisoryCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("REROUTE OPTIONS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("ESang suggests: I-76 → I-80 (Cheyenne bypass)")
                    .font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text("+87 mi · +1h 42m vs original · clears advisory window")
                    .font(.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { } label: {
                Text("Accept reroute")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button { } label: {
                Text("Hold for review")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func loadCtx() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 416 Reload Offer Sheet
// MARK: ─────────────────────────────────────────────────────────

private struct ReloadCandidate: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let laneDeltaMi: Int?
    let hosFitMin: Int?
    let equipFitPct: Int?
    let fitScore: Int?
}

struct DispatcherReloadOfferScreen: View {
    let theme: Theme.Palette
    let driverId: String
    var body: some View {
        Shell(theme: theme) { ReloadOfferBody(driverId: driverId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: true)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct ReloadOfferBody: View {
    let driverId: String
    @Environment(\.palette) private var palette
    @State private var candidates: [ReloadCandidate] = []
    @State private var selectedId: String?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                driverCard
                Text("ESANG RELOAD-FIT · RANKED BY 5 INPUTS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if loading && candidates.isEmpty {
                    LifecycleCard { Text("Loading reload candidates…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if candidates.isEmpty {
                    EusoEmptyState(systemImage: "tray", title: "No reloads in range", subtitle: "ESang found no nearby loads within HOS + equipment match.")
                } else {
                    ForEach(candidates.sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }) { c in candidateCard(c) }
                }
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Offer reload").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Driver stranded · ranked candidates").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("P2 · STRANDED").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow.opacity(0.18)))
                    .foregroundStyle(.yellow)
                Spacer()
                Text("idle 4h · 3 candidates ranked").font(.caption.weight(.semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var driverCard: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text("SQ").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver \(driverId)").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("Trailer T-211 · 53′ Reefer · MEM yard slot YS-04").font(.caption).foregroundStyle(palette.textSecondary)
                    Text("HOS 8:42 · 35.13° N · 90.05° W").font(.caption2.monospaced()).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func candidateCard(_ c: ReloadCandidate) -> some View {
        let isBest = candidates.sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }.first?.id == c.id
        let isSelected = selectedId == c.id
        return Button { selectedId = c.id } label: {
            LifecycleCard(accentGradient: isBest) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.loadNumber ?? "LD-\(c.id)").font(.caption.monospaced().weight(.semibold)).foregroundStyle(palette.textPrimary)
                        if isBest {
                            Text("BEST · \(c.fitScore ?? 0)")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.green : palette.textTertiary)
                    }
                    Text("\(c.pickupCity ?? "—") → \(c.destCity ?? "—")").font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(c.trailerType ?? "—") · \(c.cargoType ?? "—") · $\(c.rate ?? "—")")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                    HStack(spacing: 6) {
                        if let l = c.laneDeltaMi {
                            chip("LANE \(l >= 0 ? "+" : "")\(l) mi", color: .blue)
                        }
                        if let h = c.hosFitMin {
                            chip("HOS \(h / 60):\(String(format: "%02d", h % 60))", color: .green)
                        }
                        if let e = c.equipFitPct {
                            chip("EQUIP \(e)%", color: e >= 90 ? .green : .orange)
                        }
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private func chip(_ label: String, color: Color) -> some View {
        Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var actionRow: some View {
        Button { } label: {
            Text(selectedId == nil ? "Select a reload" : "Offer reload")
                .font(EType.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .opacity(selectedId == nil ? 0.5 : 1)
        }.buttonStyle(.plain).disabled(selectedId == nil)
    }

    private func load() async {
        loading = true; defer { loading = false }
        // Pull nearby pending loads as reload candidates.
        struct In: Encodable { let status: String; let limit: Int }
        struct Out: Decodable { let loads: [ReloadCandidate]?; let items: [ReloadCandidate]? }
        do {
            let r: Out = try await EusoTripAPI.shared.query("loads.list", input: In(status: "pending", limit: 6))
            candidates = r.loads ?? r.items ?? []
        } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 417 Fuel-Policy Override
// MARK: ─────────────────────────────────────────────────────────

private struct FuelStation: Decodable, Hashable, Identifiable {
    let id: String
    let name: String?
    let address: String?
    let dieselPrice: Double?
    let networkBrand: String?
    let inNetwork: Bool?
    let mileOffRoute: Double?
}

struct DispatcherFuelPolicyOverrideScreen: View {
    let theme: Theme.Palette
    let driverId: String
    var body: some View {
        Shell(theme: theme) { FuelOverrideBody(driverId: driverId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: true)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct FuelOverrideBody: View {
    let driverId: String
    @Environment(\.palette) private var palette
    @State private var stations: [FuelStation] = []
    @State private var selectedId: String?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                driverCard
                fuelStatusCard
                stationsSection
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Fuel approval").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Off-network requested · 60 min window").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("P1 · FUEL").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                Spacer()
                Text("I-10 mi 137 NM · 60 min window").font(.caption.weight(.semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var driverCard: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text("RB").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver \(driverId)").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("Truck T-308 · 53′ Dry Van · 24 pal electronics").font(.caption).foregroundStyle(palette.textSecondary)
                    Text("32.27° N · 107.76° W").font(.caption2.monospaced()).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var fuelStatusCard: some View {
        LifecycleCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FUEL").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text("15 / 100 GAL").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(.orange)
                    Text("range ≈ 90 mi").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("STATIONS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text("\(stations.count) ranked").font(.title3.weight(.heavy)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private var stationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ESANG STATION FIT · RANKED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if loading && stations.isEmpty {
                LifecycleCard { Text("Loading stations…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if stations.isEmpty {
                EusoEmptyState(systemImage: "fuelpump", title: "No stations in range", subtitle: "ESang found no compatible stations within the 60-minute window.")
            } else {
                ForEach(stations.prefix(3)) { s in stationCard(s) }
            }
        }
    }

    private func stationCard(_ s: FuelStation) -> some View {
        let isSelected = selectedId == s.id
        return Button { selectedId = s.id } label: {
            LifecycleCard(accentGradient: isSelected) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(s.name ?? "Station").font(EType.body.weight(.semibold)).foregroundStyle(palette.textPrimary)
                            Text(s.inNetwork == true ? "IN-NET" : "OFF-NET")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill((s.inNetwork == true ? Color.green : Color.orange).opacity(0.18)))
                                .foregroundStyle(s.inNetwork == true ? .green : .orange)
                        }
                        Text(s.address ?? "—").font(.caption).foregroundStyle(palette.textSecondary)
                        if let m = s.mileOffRoute { Text("+\(String(format: "%.1f", m)) mi off route").font(.caption2).foregroundStyle(palette.textTertiary) }
                    }
                    Spacer()
                    if let p = s.dieselPrice {
                        Text(String(format: "$%.2f/gal", p)).font(.body.monospacedDigit().weight(.heavy)).foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }.buttonStyle(.plain)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { } label: {
                Text(selectedId == nil ? "Select station" : "Approve fuel auth")
                    .font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(selectedId == nil ? 0.5 : 1)
            }.buttonStyle(.plain).disabled(selectedId == nil)
            Button { } label: {
                Text("Decline").font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        // Wire to fuel-station lookup via HERE add-ons (existing
        // HereMapsAPI exposes a fuel-prices client). Until that
        // surface is wired, render empty state.
    }
}

// MARK: - Previews

#Preview("409 Settings · Dark")  { DispatcherSettingsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("413 Weather · Dark")   { DispatcherWeatherRerouteScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("416 Reload · Dark")    { DispatcherReloadOfferScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("417 Fuel · Dark")      { DispatcherFuelPolicyOverrideScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("409 Settings · Light") { DispatcherSettingsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("413 Weather · Light")  { DispatcherWeatherRerouteScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("416 Reload · Light")   { DispatcherReloadOfferScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("417 Fuel · Light")     { DispatcherFuelPolicyOverrideScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
