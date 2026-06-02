//
//  589_RailTransloadConnection.swift
//  EusoTrip — Rail 589 · Transload Connection
//

import SwiftUI

// MARK: - Outer shell

struct RailTransloadConnectionScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) {
            RailTransloadConnectionBody(railId: railId)
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

// MARK: - Data shapes

private struct IntermodalTracking589: Decodable {
    let drayTimeLabel: String?
    let legCount: Int?
    let legDescription: String?
    let status: String?
    let locationName: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode the server's envelope shape
        let segments = (try? container.decode([AnyCodable].self, forKey: .segments)) ?? []
        let currentMode = try? container.decode(String?.self, forKey: .currentMode)
        
        // Derive summary values from segments
        self.legCount = segments.count > 0 ? segments.count : nil
        self.status = currentMode != nil ? "in_progress" : "pending"
        self.drayTimeLabel = "—"
        self.legDescription = currentMode != nil ? "\(currentMode?.lowercased() ?? "rail") + dray" : "rail + dray"
        self.locationName = currentMode != nil ? currentMode : nil
    }
    
    enum CodingKeys: String, CodingKey {
        case segments, containers, currentMode, activeSegmentId
    }
}

private struct AnyCodable: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int {
            try container.encode(int)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let double = value as? Double {
            try container.encode(double)
        }
    }
}

private struct TransferInfo589: Decodable {
    let transferCostUsd: Double?
    let cutoffLabel: String?

    init(from decoder: Decoder) throws {
        // Server returns bare array of transfer records; take the first one
        let c = try decoder.singleValueContainer()
        let records = try c.decode([TransferRecord].self)
        let first = records.first
        
        // Map server's transferCost (Decimal) to our transferCostUsd (Double)
        self.transferCostUsd = first.flatMap { Double($0.transferCost) }
        // Server has no cutoffLabel field; remain nil
        self.cutoffLabel = nil
    }
    
    private struct TransferRecord: Decodable {
        let id: Int
        let intermodalShipmentId: Int
        let transferCost: String  // Server sends Decimal as String via JSON
        let status: String
    }
}

private struct IntermodalSegment589: Decodable {
    let segmentName: String?
    let detail: String?
    let status: String?
    let valueLabel: String?
}

private struct ContainerInfo589: Decodable {
    let containerNumber: String?
    let lastEventLabel: String?
    let lastEventTime: String?
    let drayCutoffLabel: String?
    let slackLabel: String?
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.containerNumber = try c.decodeIfPresent(String.self, forKey: .containerNumber)
        self.lastEventLabel = try c.decodeIfPresent(String.self, forKey: .lastEventLabel)
        self.lastEventTime = try c.decodeIfPresent(String.self, forKey: .lastEventTime)
        self.drayCutoffLabel = try c.decodeIfPresent(String.self, forKey: .drayCutoffLabel)
        self.slackLabel = try c.decodeIfPresent(String.self, forKey: .slackLabel)
    }
    
    private enum CodingKeys: String, CodingKey {
        case containerNumber
        case lastEventLabel
        case lastEventTime
        case drayCutoffLabel
        case slackLabel
    }
}

private struct RailIdIn589: Encodable { let railId: String }

// MARK: - Body

private struct RailTransloadConnectionBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var tracking: IntermodalTracking589? = nil
    @State private var transfer: TransferInfo589? = nil
    @State private var segments: [IntermodalSegment589] = []
    @State private var container: ContainerInfo589? = nil
    @State private var isConfirming = false

    // MARK: Derived

    private var drayTimeLabel: String { tracking?.drayTimeLabel ?? "—" }
    private var legCount: Int         { tracking?.legCount      ?? 0 }
    private var legDesc: String       { tracking?.legDescription ?? "rail + dray" }
    private var locationLabel: String { tracking?.locationName   ?? "—" }
    private var statusInProgress: Bool {
        (tracking?.status ?? "in_progress").lowercased() == "in_progress"
    }
    private var statusLabel: String {
        switch (tracking?.status ?? "in_progress").lowercased() {
        case "completed": return "COMPLETED"
        case "pending":   return "PENDING"
        default:          return "IN PROGRESS"
        }
    }
    private var transferCostLabel: String {
        guard let c = transfer?.transferCostUsd, c > 0 else { return "—" }
        return "$\(Int(c))"
    }
    private var cutoffLabel: String { transfer?.cutoffLabel ?? "—" }
    private var containerLine1: String {
        let num   = container?.containerNumber  ?? "—"
        let event = container?.lastEventLabel   ?? "—"
        let time  = container?.lastEventTime    ?? "—"
        return "\(num) · last event \(event) · \(time)"
    }
    private var containerLine2: String {
        let cutoff = container?.drayCutoffLabel ?? "—"
        let slack  = container?.slackLabel      ?? "—"
        return "Dray cutoff \(cutoff) · \(slack) of slack on connection"
    }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                headline
                IridescentHairline()
                heroCard
                kpiStrip
                segmentsSection
                containerStrip
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task { await loadAll() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · TRANSLOAD")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(railId)
                .font(.system(size: 9, weight: .heavy).monospaced())
                .kerning(0.6)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Transload connection")
                .font(.system(size: 28, weight: .heavy))
                .kerning(-0.4)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: Hero card

    private var heroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill((statusInProgress ? Brand.warning : Brand.success).opacity(0.14)))
                        .foregroundColor(statusInProgress ? Brand.warning : Brand.success)

                    Text(locationLabel)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                        .foregroundColor(palette.textPrimary)
                }

                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: Space.s2) {
                        Text(drayTimeLabel)
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("to dray cutoff")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(palette.textSecondary)
                            Text("getIntermodalTracking")
                                .font(.system(size: 11))
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LEGS")
                            .font(.system(size: 10, weight: .black))
                            .kerning(0.6)
                            .foregroundColor(palette.textTertiary)
                        Text("\(legCount)")
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundColor(palette.textPrimary)
                        Text(legDesc)
                            .font(.system(size: 11))
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 116)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "TRANSFER", value: transferCostLabel, gradientNumeral: true)
            MetricTile(label: "LEGS",     value: "\(legCount)")
            MetricTile(label: "CUTOFF",   value: cutoffLabel)
        }
    }

    // MARK: Segments list

    private var segmentsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SEGMENTS")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundColor(palette.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                    if idx > 0 {
                        Divider()
                            .overlay(Color.black.opacity(0.06))
                            .padding(.horizontal, Space.s4)
                    }
                    segmentRow(seg)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func segmentRow(_ seg: IntermodalSegment589) -> some View {
        let (pillLabel, pillColor, pillBg) = segmentPillInfo(seg.status)
        let valueLabel = seg.valueLabel ?? "—"

        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Brand.blue.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Brand.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(seg.segmentName ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                if let detail = seg.detail {
                    Text(detail)
                        .font(.system(size: 11).monospaced())
                        .kerning(0.4)
                        .foregroundColor(palette.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(pillLabel)
                    .font(.system(size: 11, weight: .bold))
                    .kerning(0.5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(pillBg))
                    .foregroundColor(pillColor)
                Text(valueLabel)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundColor(palette.textPrimary)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }

    // MARK: Container strip

    private var containerStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CONTAINER")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.8)
                    .foregroundColor(palette.textTertiary)
                Spacer()
            }
            Text(containerLine1)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
            Text(containerLine2)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Confirm transfer",
                action: { isConfirming = true; Task { await confirmTransfer() } },
                leadingIcon: "plus",
                isLoading: isConfirming
            )
            Button("Container") {}
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Color.black.opacity(0.10), lineWidth: 1))
                )
        }
    }

    // MARK: Helpers

    private func segmentPillInfo(_ status: String?) -> (String, Color, Color) {
        switch (status ?? "pending").lowercased() {
        case "arrived":   return ("ARRIVED",     Brand.success,        Brand.success.opacity(0.14))
        case "lifting":   return ("LIFTING",      Brand.blue,           Brand.blue.opacity(0.12))
        case "booked":    return ("BOOKED",       palette.textSecondary, Color.black.opacity(0.05))
        case "completed": return ("COMPLETED",    Brand.success,        Brand.success.opacity(0.14))
        case "in_progress": return ("IN PROGRESS", Brand.warning,       Brand.warning.opacity(0.14))
        case "pending":   return ("PENDING",      Brand.info,           Brand.info.opacity(0.14))
        default:          return ("—",            palette.textTertiary, Color.black.opacity(0.05))
        }
    }

    // MARK: Data loading

    private func loadAll() async {
        async let trackTask: IntermodalTracking589 = EusoTripAPI.shared.query(
            "intermodal.getIntermodalTracking",
            input: RailIdIn589(railId: railId)
        )
        async let transferTask: TransferInfo589 = EusoTripAPI.shared.query(
            "intermodal.getTransfers",
            input: RailIdIn589(railId: railId)
        )
        async let segsTask: [IntermodalSegment589] = EusoTripAPI.shared.query(
            "intermodal.getIntermodalTracking",
            input: RailIdIn589(railId: railId)
        )
        async let containerTask: ContainerInfo589 = EusoTripAPI.shared.query(
            "railShipments.trackIntermodalContainer",
            input: RailIdIn589(railId: railId)
        )

        tracking  = try? await trackTask
        transfer  = try? await transferTask
        segments  = (try? await segsTask) ?? []
        container = try? await containerTask
    }

    private func confirmTransfer() async {
        defer { isConfirming = false }
        let result: IntermodalTracking589? = try? await EusoTripAPI.shared.query(
            "intermodal.getIntermodalTracking",
            input: RailIdIn589(railId: railId)
        )
        if let r = result { tracking = r }
    }
}
