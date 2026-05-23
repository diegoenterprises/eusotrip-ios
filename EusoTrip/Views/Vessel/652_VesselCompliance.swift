//
//  652_VesselCompliance.swift
//  EusoTrip — Vessel Operator · Compliance (ISM, flag state, crew certs).
//

import SwiftUI

struct VesselComplianceScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselComplianceBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct VesselInspection: Decodable, Identifiable {
    let id: String
    let type: String?
    let date: String?
    let port: String?
    let status: String?
    let authority: String?
    let deficiencies: Int?
}

private struct VesselCertificate: Decodable, Identifiable {
    let id: String
    let name: String?
    let issuedBy: String?
    let expiresAt: String?
    let status: String?
}

// MARK: - Body

private struct VesselComplianceBody: View {
    @Environment(\.palette) private var palette
    @State private var inspections: [VesselInspection] = []
    @State private var certificates: [VesselCertificate] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    enum Tab: String, CaseIterable {
        case inspections = "Inspections"
        case certificates = "Certificates"
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
                    case .inspections:  inspectionsContent
                    case .certificates: certificatesContent
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
                Text("VESSEL OPERATOR · COMPLIANCE")
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
                           subtitle: "Vessel port state inspection records will appear here.")
        } else {
            VStack(spacing: Space.s2) {
                ForEach(inspections) { ins in inspectionRow(ins) }
            }
        }
    }

    @ViewBuilder
    private var certificatesContent: some View {
        if certificates.isEmpty {
            EusoEmptyState(systemImage: "scroll",
                           title: "No certificates",
                           subtitle: "Vessel statutory certificates will appear here.")
        } else {
            VStack(spacing: Space.s2) {
                ForEach(certificates) { cert in certificateRow(cert) }
            }
        }
    }

    private func inspectionRow(_ ins: VesselInspection) -> some View {
        let passed = (ins.status ?? "").lowercased() == "passed" || (ins.deficiencies ?? 0) == 0
        let statusColor: Color = passed ? Brand.success : Brand.danger
        return HStack(spacing: Space.s3) {
            Image(systemName: passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(ins.type ?? "PSC Inspection").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    if let port = ins.port { Text(port).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    if let date = ins.date { Text("· \(date)").font(EType.caption).foregroundStyle(palette.textSecondary) }
                    if let d = ins.deficiencies, d > 0 {
                        Text("· \(d) deficiencies").font(EType.caption).foregroundStyle(Brand.warning)
                    }
                }
            }
            Spacer()
            if let auth = ins.authority {
                Text(auth.uppercased())
                    .font(.system(size: 7, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func certificateRow(_ cert: VesselCertificate) -> some View {
        let isExpiringSoon: Bool = {
            guard let exp = cert.expiresAt else { return false }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: exp) else { return false }
            return date.timeIntervalSinceNow < 60 * 86400
        }()
        let statusColor: Color = isExpiringSoon ? Brand.warning : Brand.success
        return HStack(spacing: Space.s3) {
            Image(systemName: "scroll")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(cert.name ?? "Certificate").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    if let issuer = cert.issuedBy { Text(issuer).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    if let exp = cert.expiresAt {
                        Text("· Exp \(exp)").font(EType.caption).foregroundStyle(isExpiringSoon ? Brand.warning : palette.textSecondary)
                    }
                }
            }
            Spacer()
            Text((cert.status ?? "Valid").uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(statusColor.opacity(0.5), lineWidth: 1))
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
            async let ins: [VesselInspection] = EusoTripAPI.shared.query(
                "vesselShipments.getVesselInspections",
                input: ListIn(limit: 50)
            )
            async let certs: [VesselCertificate] = EusoTripAPI.shared.query(
                "vesselShipments.getVesselCertificates",
                input: ListIn(limit: 50)
            )
            let (insp, certList) = try await (ins, certs)
            self.inspections = insp
            self.certificates = certList
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("652 · Vessel Compliance · Night") { VesselComplianceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("652 · Vessel Compliance · Light") { VesselComplianceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
