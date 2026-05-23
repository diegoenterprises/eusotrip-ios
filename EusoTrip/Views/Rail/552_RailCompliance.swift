//
//  552_RailCompliance.swift
//  EusoTrip — Rail Engineer · Compliance (inspections + hazmat + crew).
//

import SwiftUI

struct RailComplianceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailComplianceBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct RailInspection: Decodable, Identifiable {
    let id: String
    let type: String?
    let date: String?
    let location: String?
    let status: String?
    let inspector: String?
    let notes: String?
    let passed: Bool?
}

private struct RailHazmatPermit: Decodable, Identifiable {
    let id: String
    let permitNumber: String?
    let commodity: String?
    let expiresAt: String?
    let status: String?
}

// MARK: - Body

private struct RailComplianceBody: View {
    @Environment(\.palette) private var palette
    @State private var inspections: [RailInspection] = []
    @State private var hazmatPermits: [RailHazmatPermit] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    enum Tab: String, CaseIterable {
        case inspections = "Inspections"
        case hazmat = "Hazmat"
    }
    @State private var activeTab: Tab = .inspections

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                tabPicker
                if loading {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft).frame(height: 70)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .strokeBorder(palette.borderFaint))
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    switch activeTab {
                    case .inspections: inspectionsContent
                    case .hazmat:      hazmatContent
                    }
                }
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
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · COMPLIANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Compliance").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { activeTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: activeTab == tab ? .heavy : .semibold))
                        .foregroundStyle(activeTab == tab ? palette.textPrimary : palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s2)
                        .background(activeTab == tab ? palette.bgCard : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private var inspectionsContent: some View {
        if inspections.isEmpty {
            EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                           title: "No inspections",
                           subtitle: "Rail inspection records will appear here.")
        } else {
            VStack(spacing: Space.s2) {
                ForEach(inspections) { ins in inspectionRow(ins) }
            }
        }
    }

    @ViewBuilder
    private var hazmatContent: some View {
        if hazmatPermits.isEmpty {
            EusoEmptyState(systemImage: "exclamationmark.triangle",
                           title: "No hazmat permits",
                           subtitle: "Hazmat permit records will appear here.")
        } else {
            VStack(spacing: Space.s2) {
                ForEach(hazmatPermits) { permit in hazmatRow(permit) }
            }
        }
    }

    private func inspectionRow(_ ins: RailInspection) -> some View {
        let passed = ins.passed ?? (ins.status?.lowercased() == "passed")
        let statusColor: Color = passed ? Brand.success : Brand.danger
        return HStack(spacing: Space.s3) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(ins.type ?? "Inspection").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    if let date = ins.date {
                        Text(date).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    if let loc = ins.location {
                        Text("· \(loc)").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
            Spacer()
            Text((ins.status ?? (passed ? "Passed" : "Failed")).uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(statusColor.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func hazmatRow(_ permit: RailHazmatPermit) -> some View {
        let isExpiringSoon: Bool = {
            guard let exp = permit.expiresAt else { return false }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: exp) else { return false }
            return date.timeIntervalSinceNow < 30 * 86400
        }()
        return HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isExpiringSoon ? Brand.warning : Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(permit.commodity ?? "Hazmat Commodity").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    if let num = permit.permitNumber {
                        Text(num).font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textSecondary)
                    }
                    if let exp = permit.expiresAt {
                        Text("· Expires \(exp)").font(EType.caption).foregroundStyle(isExpiringSoon ? Brand.warning : palette.textSecondary)
                    }
                }
            }
            Spacer()
            Text((permit.status ?? "Active").uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(isExpiringSoon ? Brand.warning : Brand.success)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(
                    (isExpiringSoon ? Brand.warning : Brand.success).opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(
            isExpiringSoon ? Brand.warning.opacity(0.35) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int }
        do {
            async let ins: [RailInspection] = EusoTripAPI.shared.query(
                "railShipments.getRailInspections",
                input: ListIn(limit: 50)
            )
            async let haz: [RailHazmatPermit] = EusoTripAPI.shared.query(
                "railShipments.getRailHazmatPermits",
                input: ListIn(limit: 50)
            )
            let (insp, permits) = try await (ins, haz)
            self.inspections = insp
            self.hazmatPermits = permits
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("552 · Rail Compliance · Night") { RailComplianceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("552 · Rail Compliance · Light") { RailComplianceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
