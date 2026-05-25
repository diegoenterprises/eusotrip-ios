//
//  565_RailContainerTimeline.swift
//  EusoTrip — Rail Engineer · Container Timeline (carrier-side ISO-6346 intermodal box).
//
//  Verbatim port of "565 Rail Container Timeline.svg" (Light + Dark).
//  Carrier-side milestone history for the active intermodal box:
//  gated-in / lift-on / depart / in-transit / arrive-ramp with dwell + next-ramp ETA.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    railShipments.getRailTracking          (EXISTS railShipments.ts:485)  → {events, currentLocation, …}
//    railShipments.trackIntermodalContainer (EXISTS railShipments.ts:770)  → container metadata + events
//    intermodal.getIntermodalTracking       (EXISTS intermodal.ts:269)     → nextRampEta + rampDwell
//

import SwiftUI

struct RailContainerTimelineScreen: View {
    let theme: Theme.Palette
    let containerNumber: String
    let shipmentId: Int

    var body: some View {
        Shell(theme: theme) { RailContainerTimelineBody(containerNumber: containerNumber, shipmentId: shipmentId) } nav: {
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

// MARK: - Data shapes

private struct TrackingEvent565: Decodable, Identifiable {
    let id: Int
    let eventType: String?
    let description: String?
    let location: String?
    let timestamp: String?
    let details: String?
    let isCurrent: Bool?
    let isPredicted: Bool?
    let speedMph: Double?
    let heading: String?
    let trainId: String?
    let lastPingMinutesAgo: Int?
}

private struct TrackingData565: Decodable {
    let events: [TrackingEvent565]?
    let currentLocation: String?
    let currentSpeedMph: Double?
    let currentHeading: String?
    let trainId: String?
    let lastPingMinutesAgo: Int?
}

private struct ContainerInfo565: Decodable {
    let containerNumber: String?
    let containerSize: String?
    let railroadCode: String?
    let status: String?
}

private struct IntermodalTracking565: Decodable {
    let nextRampName: String?
    let nextRampEtaHours: Double?
    let nextRampEtaDateStr: String?
    let rampDwellHours: Double?
}

// MARK: - Body

private struct RailContainerTimelineBody: View {
    @Environment(\.palette) private var palette
    let containerNumber: String
    let shipmentId: Int

    @State private var tracking: TrackingData565? = nil
    @State private var container: ContainerInfo565? = nil
    @State private var intermodal: IntermodalTracking565? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived state

    private enum MilestoneState { case done, now, eta }

    private func milestoneState(_ e: TrackingEvent565) -> MilestoneState {
        if e.isPredicted == true { return .eta }
        if e.isCurrent == true   { return .now }
        return .done
    }

    private var events: [TrackingEvent565] { tracking?.events ?? [] }
    private var clearedCount: Int { events.filter { milestoneState($0) == .done }.count }

    private var rampDwellLabel: String {
        if let h = intermodal?.rampDwellHours { return String(format: "%.1fh", h) }
        return "—"
    }
    private var etaHoursLabel: String {
        if let h = intermodal?.nextRampEtaHours { return "\(Int(h))h" }
        return "—"
    }
    private var etaDateLabel: String { intermodal?.nextRampEtaDateStr ?? "—" }
    private var destAbbrev: String {
        let name = intermodal?.nextRampName ?? ""
        guard !name.isEmpty else { return "DEST" }
        return String(name.prefix(3)).uppercased() + " ETA"
    }

    private var liveSpeedLabel: String {
        if let spd = tracking?.currentSpeedMph {
            let dir = tracking?.currentHeading ?? ""
            return "\(Int(spd)) mph\(dir.isEmpty ? "" : " \(dir)")"
        }
        return "—"
    }
    private var liveSpeedInt: String {
        if let spd = tracking?.currentSpeedMph { return "\(Int(spd))" }
        return "—"
    }
    private var liveHeading: String { tracking?.currentHeading ?? "" }
    private var locationLabel: String { tracking?.currentLocation ?? "—" }
    private var trainLabel: String { tracking?.trainId ?? "—" }
    private var pingLabel: String {
        if let p = tracking?.lastPingMinutesAgo { return "ping \(p)m ago" }
        return "—"
    }

    private var containerLabel: String {
        let num  = container?.containerNumber ?? containerNumber
        let size = container?.containerSize ?? "—"
        let rr   = container?.railroadCode ?? "—"
        return "\(num) · \(size) · \(rr)"
    }
    private var containerStatus: String { (container?.status ?? "IN TRANSIT").uppercased() }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading timeline…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    milestoneList
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · CONTAINER TIMELINE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(container?.containerNumber ?? containerNumber)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Container Timeline")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(containerStatus)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(Brand.info)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.info.opacity(0.14)))
                Text(containerLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(liveSpeedInt)
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("mph \(liveHeading)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text(locationLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text("train \(trainLabel) · \(pingLabel)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(destAbbrev)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(etaHoursLabel)
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(etaDateLabel)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "RAMP DWELL",  value: rampDwellLabel)
            MetricTile(label: "MILESTONES",  value: "\(events.count)")
            MetricTile(label: "CLEARED",     value: "\(clearedCount)", gradientNumeral: clearedCount > 0)
        }
    }

    // MARK: - Milestone list

    private var milestoneList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("MILESTONES")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getRailTracking")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if events.isEmpty {
                EusoEmptyState(
                    systemImage: "tram.fill",
                    title: "No milestones",
                    subtitle: "Container tracking events will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { idx, evt in
                        milestoneRow(evt)
                        if idx < events.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                                .overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func milestoneRow(_ evt: TrackingEvent565) -> some View {
        let state = milestoneState(evt)
        return HStack(spacing: 12) {
            milestoneChip(state)
            VStack(alignment: .leading, spacing: 4) {
                Text(evt.description ?? evt.eventType?.replacingOccurrences(of: "_", with: " ").capitalized ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(evt.details ?? evt.location ?? evt.timestamp ?? "—")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            stateWord(state)
        }
        .padding(16)
    }

    @ViewBuilder
    private func milestoneChip(_ state: MilestoneState) -> some View {
        ZStack {
            switch state {
            case .done:
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.success.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Brand.success)
            case .now:
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.info.opacity(0.14))
                    .frame(width: 40, height: 40)
                Circle()
                    .strokeBorder(Brand.info, lineWidth: 2)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(Brand.info)
                    .frame(width: 6, height: 6)
            case .eta:
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.textTertiary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Circle()
                    .strokeBorder(palette.textTertiary, style: StrokeStyle(lineWidth: 2, dash: [2.5, 3]))
                    .frame(width: 18, height: 18)
            }
        }
    }

    @ViewBuilder
    private func stateWord(_ state: MilestoneState) -> some View {
        switch state {
        case .done:
            Text("done")
                .font(.system(size: 11, weight: .bold)).kerning(0.6)
                .foregroundStyle(Brand.success)
        case .now:
            Text("NOW")
                .font(.system(size: 11, weight: .bold)).kerning(0.6)
                .foregroundStyle(LinearGradient.primary)
        case .eta:
            Text("eta")
                .font(.system(size: 11, weight: .bold)).kerning(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "View shipment detail", leadingIcon: "shippingbox.fill")
            CTAButton(title: "Share", leadingIcon: "square.and.arrow.up", style: .secondary)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct TrackIn: Encodable { let shipmentId: Int }
        struct ContainerIn: Encodable { let containerNumber: String }
        struct IntermodalIn: Encodable { let intermodalShipmentId: Int }
        do {
            async let trackResult: TrackingData565 = EusoTripAPI.shared.query(
                "railShipments.getRailTracking", input: TrackIn(shipmentId: shipmentId))
            async let containerResult: ContainerInfo565 = EusoTripAPI.shared.query(
                "railShipments.trackIntermodalContainer", input: ContainerIn(containerNumber: containerNumber))
            let (tr, cr) = try await (trackResult, containerResult)
            self.tracking   = tr
            self.container  = cr
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        do {
            let im: IntermodalTracking565 = try await EusoTripAPI.shared.query(
                "intermodal.getIntermodalTracking", input: IntermodalIn(intermodalShipmentId: shipmentId))
            self.intermodal = im
        } catch { /* best-effort ETA enrichment */ }
        loading = false
    }
}

#Preview("565 · Rail Container Timeline · Night") { RailContainerTimelineScreen(theme: Theme.dark, containerNumber: "TCNU7693120", shipmentId: 0).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("565 · Rail Container Timeline · Light") { RailContainerTimelineScreen(theme: Theme.light, containerNumber: "TCNU7693120", shipmentId: 0).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
