//
//  519_DispatcherBhDeliveryCardApproaching.swift
//  EusoTrip — Dispatcher · BH lifecycle 519 · Delivery approach (geofence proximity).
//
//  Wireframe slot: 04 Dispatcher / 519 Dispatcher BH Delivery Card Approaching (Light+Dark
//  SVG, golden re-port 2026-06-21 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition (SVG-verbatim): radial geofence-approach gauge hero (concentric rings +
//  progress arc + truck marker + center miles-to-gate readout) → TO GEOFENCE / HOS LEFT /
//  WINDOW KPI triple → appointment-window timeline card → detention free-time preview →
//  CTA pair (Notify receiver / Adjust ETA).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                          — load + delivery window + parties.
//    READ  location.tracking.getLoadTracking      — position / ETA / geofences / detention.
//    READ  dispatch.getDriverStatuses             — driver HOS hours.
//    WRITE location.navigation.recalculateETA     — Adjust ETA (re-predict from live fix).
//  Honest gaps (no server proc — rendered as data-absence states, never faked):
//    · receiver-notify push (Notify receiver surfaces the honest no-contact state)
//    · receiver appointment window (binds the load's own delivery timestamp)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens only.
//

import SwiftUI
import Combine

// MARK: - Screen

struct DispatcherBHApproaching519Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH519Body(loadId: loadId)
        } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct BH519Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var tracking: BH519Tracking?
    @State private var loadFailed = false
    @State private var driverRow: BH519DriverRow?
    @State private var etaInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var showNotifySheet = false
    @State private var now = Date()

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrowRow
                titleRow
                Rectangle().fill(palette.iridescentHairline).frame(height: 1)
                heroCard
                kpiTriple
                sectionLabel("DELIVERY APPOINTMENT · \(destinationLabel.uppercased())")
                appointmentCard
                detentionPreview
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(Brand.success) }
                }
                if let err = actionError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                }
                if loadFailed {
                    LifecycleCard(accentWarning: true) {
                        Text("Couldn't reach the board for this load. Everything shown is the last loaded state — pull to refresh.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .eusoRefreshable { await refresh() }
        .onReceive(clock) { now = $0 }
        .sheet(isPresented: $showNotifySheet) { BH519NotifySheet(destination: destinationLabel) }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BACKHAUL · APPROACHING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("\(load?.loadNumber ?? "—") · \(load?.rateDisplay ?? "—")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
        }
    }

    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Button { navHandler?("board") } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text("Approaching").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — radial geofence-approach gauge

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Brand.magenta).frame(width: 6, height: 6)
                    Text("APPROACHING GATE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.magenta)
                }
                Spacer()
                Text(geofenceCountLabel)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            BH519RadialGauge(progress: approachFraction,
                             centerValue: milesToGateText,
                             centerCaption: "MILES TO GATE",
                             hasFix: tracking?.position != nil)
                .frame(height: 210)
                .frame(maxWidth: .infinity)
            Text(heroFooter)
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }

    // MARK: KPI triple — TO GEOFENCE / HOS LEFT / WINDOW

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH519Kpi(label: "TO GEOFENCE",
                     value: minutesToGateText,
                     sub: minutesToGateText == "—" ? "no arrival prediction yet" : "until enter",
                     tint: minutesToGateText == "—" ? nil : Brand.info)
            BH519Kpi(label: "HOS LEFT",
                     value: hosText,
                     sub: hosText == "—" ? "not on the live driver board" : "drive window",
                     tint: nil)
            BH519Kpi(label: "WINDOW",
                     value: windowStateText,
                     sub: windowSubText,
                     tint: windowStateTint)
        }
    }

    // MARK: Appointment card

    private var appointmentCard: some View {
        LifecycleCard {
            if let windowDate = deliveryDate {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack {
                        Text("Window \(clockText(windowDate))").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(dayText(windowDate)).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.borderSoft).frame(height: 4)
                            if let frac = predictedFraction {
                                Capsule().fill(LinearGradient.primary)
                                    .frame(width: max(8, geo.size.width * frac), height: 4)
                                Circle().fill(Brand.success).frame(width: 10, height: 10)
                                    .offset(x: max(0, geo.size.width * frac - 5))
                            }
                        }
                    }
                    .frame(height: 12)
                    HStack {
                        Text(predictedLine).font(EType.mono(.micro))
                            .foregroundStyle(onTime == false ? Brand.danger : Brand.success)
                        Spacer()
                        Text(slackLine).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    }
                }
            } else {
                Text("No delivery appointment is on this load record — the window paints when one is set.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Detention preview

    private var detentionPreview: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: Space.s2) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Detention free time arms at the gate")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(detentionSub)
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                BH519Chip(text: detentionArmed ? "ARMED" : "—", tint: detentionArmed ? Brand.info : Brand.neutral)
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { showNotifySheet = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bell.and.waves.left.and.right").font(.system(size: 13, weight: .bold))
                    Text("Notify receiver").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { Task { await adjustEta() } } label: {
                HStack(spacing: 6) {
                    if etaInFlight { ProgressView().scaleEffect(0.8) }
                    Text(etaInFlight ? "Re-predicting…" : "Adjust ETA").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(palette.textPrimary)
                .background(Capsule().fill(palette.bgCard))
                .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(etaInFlight)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Derived display

    private var deliveryDate: Date? { bh519ISODate(load?.deliveryDate) }
    private var predictedEta: Date? { bh519ISODate(tracking?.eta?.predictedEta) }

    private var approachFraction: CGFloat {
        guard let remaining = tracking?.eta?.remainingMiles,
              let total = tracking?.route?.distanceMiles ?? load?.distance,
              total > 0 else { return 0 }
        return CGFloat(min(0.98, max(0.02, 1.0 - remaining / total)))
    }

    private var milesToGateText: String {
        guard let r = tracking?.eta?.remainingMiles else { return "—" }
        return "\(Int(r.rounded()))"
    }

    private var minutesToGateText: String {
        guard let m = tracking?.eta?.remainingMinutes else { return "—" }
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    private var geofenceCountLabel: String {
        let n = tracking?.geofences?.count ?? 0
        return n > 0 ? "GEOFENCES \(n)" : "GEOFENCE —"
    }

    private var heroFooter: String {
        var parts: [String] = []
        if let e = predictedEta { parts.append("ETA \(clockText(e))") }
        else { parts.append("ETA —") }
        parts.append(destinationLabel)
        return parts.joined(separator: " · ")
    }

    private var destinationLabel: String {
        let c = load?.deliveryLocation?.city ?? "receiver"
        if let s = load?.deliveryLocation?.state { return "\(c), \(s)" }
        return c
    }

    private var hosText: String {
        guard let h = driverRow?.hoursRemaining else { return "—" }
        let whole = Int(h)
        let mins = Int((h - Double(whole)) * 60)
        return "\(whole)h \(String(format: "%02d", mins))"
    }

    private var onTime: Bool? {
        guard let w = deliveryDate, let p = predictedEta else { return nil }
        return p <= w
    }

    private var windowStateText: String {
        switch onTime {
        case true: return "ON TIME"
        case false: return "AT RISK"
        default: return "—"
        }
    }

    private var windowStateTint: Color? {
        switch onTime {
        case true: return Brand.success
        case false: return Brand.danger
        default: return nil
        }
    }

    private var windowSubText: String {
        guard let w = deliveryDate else { return "no appointment on this record" }
        return "appointment \(clockText(w))"
    }

    private var predictedFraction: CGFloat? {
        guard let w = deliveryDate, let p = predictedEta else { return nil }
        // Paint the prediction inside a two-hour lead-up to the appointment.
        let windowStart = w.addingTimeInterval(-2 * 3600)
        let frac = p.timeIntervalSince(windowStart) / (2 * 3600)
        return CGFloat(min(1.0, max(0.0, frac)))
    }

    private var predictedLine: String {
        guard let p = predictedEta else { return "No arrival prediction has posted yet" }
        switch onTime {
        case true: return "Predicted \(clockText(p)) — inside the window"
        case false: return "Predicted \(clockText(p)) — past the appointment"
        default: return "Predicted \(clockText(p))"
        }
    }

    private var slackLine: String {
        guard let w = deliveryDate, let p = predictedEta else { return "" }
        let mins = Int(w.timeIntervalSince(p) / 60)
        if mins >= 0 { return "+\(bh519HoursMinutes(mins)) slack" }
        return "\(bh519HoursMinutes(-mins)) late"
    }

    private var detentionArmed: Bool {
        !(tracking?.geofences ?? []).isEmpty
    }

    private var detentionSub: String {
        if let rec = tracking?.detention?.first, let free = rec.freeTimeMinutes {
            return "\(free) min free on this facility's clock · auto-clock on geofence entry"
        }
        if detentionArmed { return "auto-clock starts on geofence entry" }
        return "no delivery geofence is active on this load"
    }

    private func clockText(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func dayText(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s1)
    }

    // MARK: Data

    private func refresh() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
            loadFailed = false
        } catch { loadFailed = load == nil }
        await fetchTracking()
        await fetchDriverRow()
        now = Date()
    }

    private func fetchTracking() async {
        struct In: Encodable { let loadId: Int }
        guard let numeric = Int((load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")) else { return }
        do {
            tracking = try await EusoTripAPI.shared.query("location.tracking.getLoadTracking", input: In(loadId: numeric))
        } catch { tracking = nil }
    }

    private func fetchDriverRow() async {
        struct In: Encodable { let limit: Int }
        do {
            let rows: [BH519DriverRow] = try await EusoTripAPI.shared.query("dispatch.getDriverStatuses", input: In(limit: 50))
            let ln = load?.loadNumber
            let dn = load?.driver?.name
            driverRow = rows.first(where: { $0.load != nil && $0.load == ln })
                ?? rows.first(where: { dn != nil && $0.name == dn })
        } catch { driverRow = nil }
    }

    private func adjustEta() async {
        guard !etaInFlight else { return }
        etaInFlight = true; actionAck = nil; actionError = nil
        defer { etaInFlight = false }
        guard let pos = tracking?.position, let lat = pos.lat, let lng = pos.lng else {
            actionError = "No live GPS fix is on this load, so the arrival prediction can't re-run. It re-arms on the next heartbeat."
            return
        }
        guard let dLat = load?.deliveryLocation?.lat ?? tracking?.destination?.lat,
              let dLng = load?.deliveryLocation?.lng ?? tracking?.destination?.lng else {
            actionError = "The receiver location isn't geocoded on this load, so the arrival prediction can't re-run."
            return
        }
        guard let numeric = Int((load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")) else {
            actionError = "This load id didn't resolve, so the arrival prediction can't re-run."
            return
        }
        struct In: Encodable {
            let loadId: Int
            let currentLat: Double
            let currentLng: Double
            let destLat: Double
            let destLng: Double
        }
        struct Out: Decodable { let eta: String?; let estimatedArrival: String? }
        do {
            let _: Out = try await EusoTripAPI.shared.query(
                "location.navigation.recalculateETA",
                input: In(loadId: numeric, currentLat: lat, currentLng: lng, destLat: dLat, destLng: dLng))
            actionAck = "Arrival prediction re-ran from the live fix — the board and the receiver view both carry the fresh ETA."
            await fetchTracking()
        } catch {
            actionError = "The prediction didn't re-run. The last ETA stays on the board — try again."
        }
    }
}

// MARK: - Radial gauge

private struct BH519RadialGauge: View {
    @Environment(\.palette) private var palette
    let progress: CGFloat
    let centerValue: String
    let centerCaption: String
    let hasFix: Bool

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                // Concentric proximity rings
                ForEach([0.55, 0.75, 0.95], id: \.self) { scale in
                    Circle()
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                        .frame(width: side * scale, height: side * scale)
                        .position(center)
                }
                // Progress arc
                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: side * 0.75, height: side * 0.75)
                    .position(center)
                // Truck marker on the arc
                if hasFix {
                    let angle = Double(progress) * 2 * .pi - .pi / 2
                    let r = side * 0.375
                    Circle().fill(LinearGradient.diagonal).frame(width: 24, height: 24)
                        .overlay(Image(systemName: "truck.box.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                        .position(x: center.x + CGFloat(cos(angle)) * r,
                                  y: center.y + CGFloat(sin(angle)) * r)
                }
                // Center readout
                VStack(spacing: 3) {
                    Text(centerValue)
                        .font(.system(size: 40, weight: .heavy).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text(centerCaption)
                        .font(.system(size: 8, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    if !hasFix {
                        Text("awaiting GPS fix")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .position(center)
            }
        }
    }
}

// MARK: - Notify-receiver honest sheet

private struct BH519NotifySheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let destination: String

    var body: some View {
        ZStack {
            palette.bgPrimary.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("Notify receiver").font(EType.h2).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                LifecycleCard(accentWarning: true) {
                    Text("No notification contact is on file for the receiving facility at \(destination) on this load.")
                        .font(EType.caption).foregroundStyle(palette.textPrimary)
                    Text("The approach view and the arrival prediction stay live on this board. To reach the facility now, hail the driver from the in-transit board or call the receiver directly from the load's contact sheet.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(Space.s4)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Small primitives

private struct BH519Chip: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }
}

private struct BH519Kpi: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let sub: String
    let tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

// MARK: - File-local decode + helpers

private struct BH519Tracking: Decodable {
    struct Point: Decodable { let lat: Double?; let lng: Double?; let city: String?; let state: String? }
    struct Position: Decodable { let lat: Double?; let lng: Double?; let speed: Double?; let updatedAt: String? }
    struct Route: Decodable { let distanceMiles: Double?; let durationSeconds: Int? }
    struct Geofence: Decodable { let id: Int?; let name: String?; let type: String? }
    struct Detention: Decodable { let id: Int?; let enterAt: String?; let exitAt: String?; let totalDwellMinutes: Int?; let detentionMinutes: Int?; let detentionCharge: Double?; let isBillable: Bool?; let freeTimeMinutes: Int? }
    struct Eta: Decodable { let predictedEta: String?; let remainingMiles: Double?; let remainingMinutes: Int? }
    let loadId: Int?
    let status: String?
    let origin: Point?
    let destination: Point?
    let position: Position?
    let route: Route?
    let geofences: [Geofence]?
    let detention: [Detention]?
    let eta: Eta?
}

private struct BH519DriverRow: Decodable {
    let id: String?
    let name: String?
    let status: String?
    let load: String?
    let hoursRemaining: Double?
}

private func bh519HoursMinutes(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
}

private func bh519ISODate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    return ISO8601DateFormatter().date(from: s)
}

// MARK: - Previews

#Preview("519 Approaching · Dark") {
    DispatcherBHApproaching519Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("519 Approaching · Light") {
    DispatcherBHApproaching519Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
