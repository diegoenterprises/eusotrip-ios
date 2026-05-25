//
//  566_RailIntermodalTransfer.swift
//  EusoTrip — Rail Engineer · Intermodal Transfer (carrier-side modal-interchange handoff board).
//
//  Verbatim port of "566 Rail Intermodal Transfer.svg" (Light + Dark).
//  Rail-truck / rail-vessel container transfers at a named ramp/yard with
//  transfer type, facility, cost, and a recent-transfer log.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    intermodal.getTransfers    (EXISTS intermodal.ts:376)  → intermodalTransfers[] desc
//    intermodal.recordTransfer  (EXISTS intermodal.ts:235)  → CTA action
//    intermodal.advanceSegment  (EXISTS intermodal.ts:198)  → segment cursor advance
//

import SwiftUI

struct RailIntermodalTransferScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int

    var body: some View {
        Shell(theme: theme) { RailIntermodalTransferBody(shipmentId: shipmentId) } nav: {
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

private struct IntermodalTransfer566: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let transferType: String?           // "truck_to_rail" | "rail_to_truck" | "rail_to_vessel"
    let fromSegmentId: Int?
    let toSegmentId: Int?
    let totalSegments: Int?
    let facilityName: String?
    let facilityType: String?           // "rail_yard" | "ramp" | "depot"
    let location: String?
    let transferCost: Double?
    let notes: String?
    let status: String?                 // "completed" | "active" | "queued"
    let timestamp: String?
    let transferTimeMinutes: Double?
}

// MARK: - Body

private struct RailIntermodalTransferBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var transfers: [IntermodalTransfer566] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isAdvancing = false

    // MARK: Derived

    private var activeTransfer: IntermodalTransfer566? {
        transfers.first { ($0.status ?? "").lowercased().contains("active") || ($0.status ?? "").lowercased().contains("in_progress") }
            ?? transfers.first
    }

    private var todayCount: Int { transfers.count }
    private var pendingCount: Int {
        transfers.filter { let s = ($0.status ?? "").lowercased(); return s == "queued" || s == "pending" }.count
    }
    private var avgTimeLabel: String {
        let times = transfers.compactMap { $0.transferTimeMinutes }
        guard !times.isEmpty else { return "—" }
        let avg = times.reduce(0, +) / Double(times.count)
        return "\(Int(avg))m"
    }

    private func transferTypeLabel(_ t: IntermodalTransfer566) -> String {
        switch (t.transferType ?? "").lowercased() {
        case "truck_to_rail": return "Truck → Rail"
        case "rail_to_truck": return "Rail → Truck"
        case "rail_to_vessel": return "Rail → Vessel"
        default: return (t.transferType ?? "Transfer").replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func chipColor(_ t: IntermodalTransfer566) -> Color {
        switch (t.transferType ?? "").lowercased() {
        case "truck_to_rail": return Brand.info
        case "rail_to_truck": return Brand.warning
        case "rail_to_vessel": return Color(red: 0.38, green: 0.49, blue: 0.55)
        default: return Brand.info
        }
    }

    private enum TransferStatus { case done, active, queued }
    private func transferStatus(_ t: IntermodalTransfer566) -> TransferStatus {
        switch (t.status ?? "").lowercased() {
        case "completed", "done": return .done
        case "active", "in_progress": return .active
        default: return .queued
        }
    }

    private var advanceLegTitle: String {
        if let notes = activeTransfer?.notes, !notes.isEmpty { return "Advance leg → \(notes)" }
        return "Advance leg → final drayage"
    }
    private var advanceLegSub: String {
        let to = activeTransfer?.toSegmentId ?? 0
        let total = activeTransfer?.totalSegments ?? to
        return "advanceSegment · seg \(to) of \(total)"
    }
    private var facilityAbbrev: String {
        let name = activeTransfer?.facilityName ?? ""
        guard !name.isEmpty else { return "—" }
        let words = name.split(separator: " ")
        if words.count >= 2 { return "\(words[0].prefix(3)) \(words[1].prefix(2))".uppercased() }
        return String(name.prefix(6)).uppercased()
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading transfers…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    transferList
                    advanceLegRow
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
                    Text("RAIL ENGINEER · INTERMODAL TRANSFER")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(facilityAbbrev)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Intermodal Transfer")
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
        let t = activeTransfer
        let isActive = t.map { transferStatus($0) == .active } ?? false
        let typeLabel = t.map { "\(transferTypeLabel($0)) · \(($0.facilityType ?? "ramp"))" } ?? "—"
        let costLabel = t.flatMap { $0.transferCost }.map { "$\(Int($0))" } ?? "—"
        let containerLabel = t?.containerNumber.map { "\($0) transfer" } ?? "—"
        let segLabel: String = {
            if let from = t?.fromSegmentId, let to = t?.toSegmentId {
                return "seg \(from) → seg \(to) · \(t?.notes ?? "drayage")"
            }
            return t?.notes ?? "—"
        }()
        let facilityType = t?.facilityType ?? "ramp"
        let facilityName: String = {
            let name = t?.facilityName ?? "—"
            let words = name.split(separator: " ")
            if words.count >= 2 { return "\(words[0]) \(words[1].prefix(2))" }
            return String(name.prefix(10))
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(isActive ? "IN PROGRESS" : "QUEUED")
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
                Text(typeLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(costLabel)
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(containerLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(segLabel)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("FACILITY")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(facilityType)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(facilityName)
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
            MetricTile(label: "TODAY",    value: "\(todayCount)")
            MetricTile(label: "AVG TIME", value: avgTimeLabel, gradientNumeral: avgTimeLabel != "—")
            MetricTile(label: "PENDING",  value: "\(pendingCount)", accent: pendingCount > 0 ? Brand.warning : nil)
        }
    }

    // MARK: - Transfer list

    private var transferList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RECENT TRANSFERS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getTransfers")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if transfers.isEmpty {
                EusoEmptyState(
                    systemImage: "arrow.left.arrow.right",
                    title: "No transfers",
                    subtitle: "Intermodal transfers will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(transfers.enumerated()), id: \.element.id) { idx, t in
                        transferRow(t)
                        if idx < transfers.count - 1 {
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

    private func transferRow(_ t: IntermodalTransfer566) -> some View {
        let color = chipColor(t)
        let status = transferStatus(t)
        let title = "\(transferTypeLabel(t))\(t.containerNumber.map { " · \($0)" } ?? "")"
        let sub = [t.facilityName, t.facilityType, t.timestamp].compactMap { $0 }.joined(separator: " · ")
        let costLabel = t.transferCost.map { "$\(Int($0))" }

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub.isEmpty ? "—" : sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                statusWord(status)
                if let cost = costLabel {
                    Text(cost)
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                } else {
                    Text("pending")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func statusWord(_ status: TransferStatus) -> some View {
        switch status {
        case .done:
            Text("DONE")
                .font(.system(size: 11, weight: .bold)).kerning(0.6)
                .foregroundStyle(Brand.success)
        case .active:
            Text("ACTIVE")
                .font(.system(size: 11, weight: .bold)).kerning(0.6)
                .foregroundStyle(LinearGradient.primary)
        case .queued:
            Text("QUEUED")
                .font(.system(size: 11, weight: .bold)).kerning(0.6)
                .foregroundStyle(Brand.warning)
        }
    }

    // MARK: - Advance-leg strip

    private var advanceLegRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.blue.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Brand.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(advanceLegTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(advanceLegSub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            if isAdvancing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .onTapGesture { Task { await advanceSegment() } }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Record transfer", leadingIcon: "plus")
            Button {} label: {
                Text("History")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 116, height: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int }
        do {
            let result: [IntermodalTransfer566] = try await EusoTripAPI.shared.query(
                "intermodal.getTransfers", input: ListIn(limit: 50))
            self.transfers = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func advanceSegment() async {
        guard let t = activeTransfer else { return }
        isAdvancing = true
        struct AdvIn: Encodable { let intermodalShipmentId: Int; let fromSegmentId: Int; let toSegmentId: Int }
        do {
            struct Empty: Decodable {}
            let _: Empty = try await EusoTripAPI.shared.query(
                "intermodal.advanceSegment",
                input: AdvIn(intermodalShipmentId: shipmentId, fromSegmentId: t.fromSegmentId ?? 0, toSegmentId: t.toSegmentId ?? 0))
            await load()
        } catch { /* surface error silently; list stays current */ }
        isAdvancing = false
    }
}

#Preview("566 · Rail Intermodal Transfer · Night") { RailIntermodalTransferScreen(theme: Theme.dark, shipmentId: 0).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("566 · Rail Intermodal Transfer · Light") { RailIntermodalTransferScreen(theme: Theme.light, shipmentId: 0).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
