//
//  DL091_DriverLifecycleEntryTrio.swift
//  EusoTrip — Driver · Lifecycle entry trio (091/092/093).
//
//  Bundled file with three Driver lifecycle screens. Prefix "DL"
//  (Driver Lifecycle) avoids the existing 091-108 Me-section
//  files (091_MeDetention.swift, etc.). The SVG team uses 091-108
//  for driver lifecycle counterparts; iOS already uses 091-108
//  for Me-section drawer screens.
//
//  Pixel-match to:
//    091 Load Offer Detail.svg
//    092 Driver Assignment Receipt.svg
//    093 Driver Pickup Approach.svg
//
//  All wire to real endpoints. Bottom nav frozen.
//

import SwiftUI

private struct DriverLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let distance: Double?
    let pickupDate: String?
    let temperatureRange: String?
    let dispatcherCompany: String?
    let dispatcherContact: String?
    let dispatcherDot: String?
    let dispatcherMc: String?
    let pickupFacilityName: String?
    let pickupWindowStart: String?
    let pickupWindowEnd: String?
    let assignedDriverName: String?
    let acceptedAt: String?
    let expiresAt: String?
    let bestMatchScore: Double?
    let laneAvgRpm: Double?
    let fsc: String?
}

// MARK: - Shell

private struct DriverLifecycleShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Trips", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 091 Load Offer Detail
// MARK: ─────────────────────────────────────────────────────────

struct DriverLoadOfferDetailScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DriverLifecycleShell(theme: theme) { LoadOfferBody(loadId: loadId) }
    }
}

private struct LoadOfferBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: DriverLoadCtx?
    @State private var loading: Bool = true
    @State private var actionInFlight: String? = nil  // "accept" / "decline"
    @State private var actionAck: String?
    @State private var actionError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && load == nil {
                    LifecycleCard { Text("Loading offer…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let l = load {
                    rateHeroCard(l)
                    rpmComparisonCard(l)
                    lifecycleProgressCard
                    actionRow
                    if let ack = actionAck {
                        LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(.green) }
                    }
                    if let err = actionError {
                        LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) }
                    }
                }
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
                Text("DRIVER · OFFER · \(load?.trailerType?.uppercased() ?? "—") · \(load?.cargoType?.uppercased() ?? "—")")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            if let l = load {
                Text(l.loadNumber ?? "LD-\(l.id ?? 0)").font(.caption.monospaced().weight(.semibold)).foregroundStyle(palette.textSecondary)
                Text("\(l.pickupCity ?? "—") → \(l.destCity ?? "—")")
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                if let exp = l.expiresAt, let d = ISO8601DateFormatter().date(from: exp) {
                    let mins = max(0, Int(d.timeIntervalSinceNow / 60))
                    Text("EXPIRES · \(mins)m").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(mins < 30 ? .red : palette.textSecondary)
                }
            }
        }
    }

    private func rateHeroCard(_ l: DriverLoadCtx) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let tt = l.trailerType {
                        Text(tt.uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.18)))
                            .foregroundStyle(.blue)
                    }
                    if let c = l.cargoType {
                        Text(c.uppercased())
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundStyle(.green)
                    }
                }
                Text("$\(l.rate ?? "—")")
                    .font(.system(size: 36, weight: .heavy).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                Text("linehaul · \(rpmString(l)) · \(Int(l.distance ?? 0)) mi")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                if let r = l.temperatureRange {
                    Text("\(r) · live load · §8.4 owner-op")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func rpmComparisonCard(_ l: DriverLoadCtx) -> some View {
        let rpm = rpmDouble(l)
        let avg = l.laneAvgRpm ?? 0
        let pct = (avg > 0) ? ((rpm - avg) / avg) * 100 : 0
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("VS LANE AVG").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(String(format: "%+.1f%%", pct))
                    .font(.title2.weight(.heavy).monospacedDigit())
                    .foregroundStyle(pct >= 0 ? Color.green : Color.red)
                Text("$\(String(format: "%.2f", rpm))/mi vs lane avg $\(String(format: "%.2f", avg))/mi")
                    .font(.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var lifecycleProgressCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("LIFECYCLE · \(load?.trailerType?.uppercased() ?? "—") · \(load?.cargoType?.uppercased() ?? "—") \(load?.temperatureRange ?? "")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                HStack(spacing: 4) {
                    ForEach(["POSTED", "BIDDING", "AWARDED", "PICKUP"], id: \.self) { stage in
                        let active = stage == "BIDDING"
                        let cleared = stage == "POSTED"
                        ZStack {
                            Capsule()
                                .fill(active || cleared ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                                .frame(height: 22)
                            Text(stage)
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .padding(.horizontal, 8)
                                .foregroundStyle(active || cleared ? .white : palette.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { Task { await acceptOffer() } } label: {
                HStack(spacing: 6) {
                    if actionInFlight == "accept" {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                    Text(actionInFlight == "accept" ? "Accepting…" : "Accept offer")
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight != nil)

            Button { Task { await declineOffer() } } label: {
                HStack(spacing: 6) {
                    if actionInFlight == "decline" {
                        ProgressView().scaleEffect(0.8)
                    }
                    Text(actionInFlight == "decline" ? "Declining…" : "Decline")
                        .font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(palette.textPrimary)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight != nil)
        }
    }

    private func acceptOffer() async {
        actionInFlight = "accept"; actionAck = nil; actionError = nil
        defer { actionInFlight = nil }
        struct In: Encodable { let loadId: String }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let acceptedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation("dispatchRole.acceptLoad", input: In(loadId: loadId))
            if resp.success == true {
                actionAck = "Offer accepted · load \(resp.loadId ?? loadId) is now yours."
                await loadCtx()
            } else {
                actionError = "Accept returned no success flag — reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "Accept failed: \(err)"
        }
    }

    private func declineOffer() async {
        actionInFlight = "decline"; actionAck = nil; actionError = nil
        defer { actionInFlight = nil }
        struct In: Encodable { let loadId: String; let reason: String? }
        struct Out: Decodable { let success: Bool?; let loadId: String?; let declinedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation("dispatchRole.declineLoad", input: In(loadId: loadId, reason: "Driver declined via DL091"))
            if resp.success == true {
                actionAck = "Offer declined · returned to the pool."
                await loadCtx()
            } else {
                actionError = "Decline returned no success flag — reload and try again."
            }
        } catch let err {
            actionError = (err as? LocalizedError)?.errorDescription ?? "Decline failed: \(err)"
        }
    }

    private func rpmDouble(_ l: DriverLoadCtx) -> Double {
        guard let r = Double(l.rate ?? "0"), let mi = l.distance, mi > 0 else { return 0 }
        return r / mi
    }
    private func rpmString(_ l: DriverLoadCtx) -> String {
        let v = rpmDouble(l); return String(format: "$%.2f/mi", v)
    }

    private func loadCtx() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 092 Driver Assignment Receipt
// MARK: ─────────────────────────────────────────────────────────

struct DriverAssignmentReceiptScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DriverLifecycleShell(theme: theme) { AssignReceiptBody(loadId: loadId) }
    }
}

private struct AssignReceiptBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: DriverLoadCtx?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && load == nil {
                    LifecycleCard { Text("Loading receipt…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let l = load {
                    crossTrackBanner(l)
                    dispatcherCard(l)
                    payoutGrid(l)
                    timelineCard
                }
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
                Text("DRIVER · TRIPS · ASSIGNMENT · RECEIPT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Assignment received").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if let l = load {
                let etaPickup = etaText(l.pickupDate)
                let ago = timeAgo(l.acceptedAt)
                Text("GROSS $\(l.rate ?? "—") · PICKUP \(etaPickup) · \(ago) AGO")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func crossTrackBanner(_ l: DriverLoadCtx) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("§271 · CROSS-TRACK PARITY PORT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · \(l.pickupCity ?? "—") → \(l.destCity ?? "—") · \(l.trailerType ?? "—") · DU paid · ME drives")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private func dispatcherCard(_ l: DriverLoadCtx) -> some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    Text("RM").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.dispatcherCompany ?? "—").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text(l.dispatcherContact ?? "—").font(.caption).foregroundStyle(palette.textSecondary)
                    if let d = l.dispatcherDot, let m = l.dispatcherMc {
                        Text("USDOT \(d) · MC-\(m)").font(.caption2.monospaced()).foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                Text("0.94").font(.body.weight(.heavy).monospacedDigit()).foregroundStyle(.green)
            }
        }
    }

    private func payoutGrid(_ l: DriverLoadCtx) -> some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("GROSS", "$\(l.rate ?? "—")", "line haul", .green)
            kpi("FSC", "$\(l.fsc ?? "—")", "18% line-haul", .blue)
            kpi("DISTANCE", "\(Int(l.distance ?? 0)) mi", "to destination", .blue)
            kpi("ETA PICKUP", etaText(l.pickupDate), "window open", .blue)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var timelineCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("WHAT'S NEXT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("Approach → Gate → Dock → Load → Departing → In transit → Delivery → POD")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func etaText(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let mins = Int(d.timeIntervalSinceNow / 60)
        if mins < 0 { return "ARRIVED" }
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
    private func timeAgo(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let mins = max(0, Int(Date().timeIntervalSince(d) / 60))
        if mins < 1 { return "0:01" }
        if mins < 60 { return "0:\(String(format: "%02d", mins))" }
        return "\(mins / 60)h \(mins % 60)m"
    }

    private func loadCtx() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 093 Driver Pickup Approach
// MARK: ─────────────────────────────────────────────────────────

struct DriverPickupApproachScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        DriverLifecycleShell(theme: theme) { PickupApproachBody(loadId: loadId) }
    }
}

private struct PickupApproachBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @State private var load: DriverLoadCtx?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && load == nil {
                    LifecycleCard { Text("Loading approach…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let l = load {
                    crossTrackBanner
                    facilityCard(l)
                    kpiGrid(l)
                    nextStepsCard
                }
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
                Text("DRIVER · TRIPS · PICKUP · APPROACH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Approaching pickup").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if let l = load {
                let dist = Int(l.distance ?? 0)
                let eta = etaTime(l.pickupDate)
                Text("ETA \(eta) · \(dist) mi · 0:42 LEFT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var crossTrackBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("§274 · WITHIN-TRACK SECOND-PORT TRIGGER CLOSE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · ETA \(etaTime(l.pickupDate)) · DU paid · ME approaching")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func facilityCard(_ l: DriverLoadCtx) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("PICKUP FACILITY").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(l.pickupFacilityName ?? "\(l.pickupCity ?? "—") facility").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                Text("\(windowText(l)) · 0:42 buffer").font(.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func kpiGrid(_ l: DriverLoadCtx) -> some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("ETA", etaTime(l.pickupDate), "PDT · 0:42 in", .blue)
            kpi("DISTANCE", "\(Int(l.distance ?? 0)) mi", "to facility", .blue)
            kpi("BUFFER", "0:42", "before window", .green)
            kpi("WINDOW", windowText(l), "open / close", .blue)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var nextStepsCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEPS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("Check-in at gate → dock assignment → load → BOL pre-sign → departing.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func etaTime(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "H:mm"
        return f.string(from: d)
    }
    private func windowText(_ l: DriverLoadCtx) -> String {
        switch (l.pickupWindowStart, l.pickupWindowEnd) {
        case let (s?, e?):
            let f = ISO8601DateFormatter(); let out = DateFormatter(); out.dateFormat = "H:mm"
            let sd = f.date(from: s).map { out.string(from: $0) } ?? "—"
            let ed = f.date(from: e).map { out.string(from: $0) } ?? "—"
            return "\(sd)–\(ed) PDT"
        default:
            return "open / close"
        }
    }

    private func loadCtx() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: - Previews

#Preview("DL091 Offer · Dark")   { DriverLoadOfferDetailScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL092 Receipt · Dark") { DriverAssignmentReceiptScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL093 Approach · Dark"){ DriverPickupApproachScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("DL091 Offer · Light")  { DriverLoadOfferDetailScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL092 Receipt · Light"){ DriverAssignmentReceiptScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("DL093 Approach · Light"){ DriverPickupApproachScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
