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

private struct VesselCertificate652: Decodable, Identifiable {
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
    @State private var certificates: [VesselCertificate652] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    enum Tab: String, CaseIterable {
        case inspections = "Inspections"
        case certificates = "Certificates"
        case coldChain = "Cold Chain"
    }
    @State private var activeTab: Tab = .inspections

    private var passedCount:   Int { inspections.filter { ($0.status ?? "").lowercased() == "passed" || ($0.deficiencies ?? 0) == 0 }.count }
    private var failedCount:   Int { inspections.count - passedCount }
    private var expiringCerts: Int {
        certificates.filter { cert in
            guard let exp = cert.expiresAt,
                  let date = {
                      let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: exp)
                  }() else { return false }
            return date.timeIntervalSinceNow < 60 * 86400
        }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if !loading && loadError == nil {
                    kpiStrip
                }
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
                    case .coldChain:    coldChainContent
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

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
            HStack(alignment: .firstTextBaseline) {
                Text("Compliance")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if !inspections.isEmpty {
                    let status = failedCount == 0 ? "COMPLIANT" : "\(failedCount) DEFICIENCIES"
                    Text(status)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(failedCount == 0 ? Brand.success : Brand.danger)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder((failedCount == 0 ? Brand.success : Brand.danger).opacity(0.5), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "PASSED",      value: "\(passedCount)",   gradientNumeral: passedCount > 0 && failedCount == 0)
            MetricTile(label: "DEFICIENCIES", value: "\(failedCount)",   accent: failedCount > 0 ? Brand.danger : nil)
            MetricTile(label: "CERTS EXPIRING", value: "\(expiringCerts)", accent: expiringCerts > 0 ? Brand.warning : nil)
        }
    }

    // MARK: - Tab picker

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

    // MARK: - Inspections

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

    private func inspectionRow(_ ins: VesselInspection) -> some View {
        let passed = (ins.status ?? "").lowercased() == "passed" || (ins.deficiencies ?? 0) == 0
        let statusColor: Color = passed ? Brand.success : Brand.danger
        let defCount = ins.deficiencies ?? 0
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ins.type ?? "PSC Inspection")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    if let port = ins.port { Text(port).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    if let date = ins.date { Text("· \(date)").font(EType.caption).foregroundStyle(palette.textSecondary) }
                    if defCount > 0 {
                        Text("· \(defCount) deficienc\(defCount == 1 ? "y" : "ies")")
                            .font(EType.caption).foregroundStyle(Brand.danger)
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
        .background(passed ? palette.bgCard : Brand.danger.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(passed ? palette.borderFaint : Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Certificates

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

    private func certificateRow(_ cert: VesselCertificate652) -> some View {
        let isExpiringSoon: Bool = {
            guard let exp = cert.expiresAt,
                  let date = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: exp) }()
            else { return false }
            return date.timeIntervalSinceNow < 60 * 86400
        }()
        let color: Color = isExpiringSoon ? Brand.warning : Brand.success
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "scroll")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cert.name ?? "Certificate")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                HStack(spacing: 6) {
                    if let issuer = cert.issuedBy {
                        Text(issuer).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    if let exp = cert.expiresAt {
                        Text("· Exp \(exp)").font(EType.caption)
                            .foregroundStyle(isExpiringSoon ? Brand.warning : palette.textSecondary)
                    }
                }
            }
            Spacer()
            Text((cert.status ?? "Valid").uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(isExpiringSoon ? Brand.warning.opacity(0.04) : palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(isExpiringSoon ? Brand.warning.opacity(0.35) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Cold chain (FSMA reefer temp log)
    //
    // FSMA Sanitary Transportation rule: reefer cargo must hold below the
    // 40°F excursion ceiling; the commanded setpoint here is 34°F. The chart
    // plots the front/center/rear probe traces against those two rails.

    /// FSMA Sanitary-Transportation excursion ceiling (°F).
    private let fsmaCeilingF: Double = 40
    /// Commanded reefer box temperature (°F).
    private let reeferSetpointF: Double = 34

    @ViewBuilder
    private var coldChainContent: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ReeferTempLogChart(
                zones: reeferZones,
                setpointF: reeferSetpointF,
                ceilingF: fsmaCeilingF,
                title: "REEFER COLD CHAIN"
            )
            Text("FSMA Sanitary-Transportation ceiling 40°F · setpoint 34°F.")
                .font(EType.micro).foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s1)
        }
    }

    /// Front/center/rear probe traces for the cold-chain chart.
    ///
    /// TODO(vessel-reefer): wire to a real vessel reefer temp-log endpoint
    /// once exposed to iOS (the existing `reeferTemp.getReadings` is scoped to
    /// the truck driver's `driverId`/`loadId`, not a vessel operator's reefer
    /// containers, so it is not the correct source for this surface). When a
    /// `vesselShipments.getReeferTempLog` (or equivalent) endpoint lands,
    /// decode its `{ zone, temp/tempF, timestamp }` rows — the same shape
    /// `reeferTemp.getReadings` already returns — group by `zone`, and map each
    /// group into a `TempZone` exactly as below. Until then this renders the
    /// component's reference series so the card is live (not preview-only) and
    /// the swap is a drop-in. No fabricated tenant data is persisted.
    private var reeferZones: [TempZone] {
        let now = Date()
        func mk(_ vals: [Double]) -> [TempZone.Reading] {
            let n = vals.count
            return vals.enumerated().map { i, v in
                .init(t: now.addingTimeInterval(-Double(n - 1 - i) * 3600), tempF: v)
            }
        }
        let front  = mk([34.1, 33.9, 34.0, 34.2, 33.8, 34.0, 34.1, 33.9, 34.0, 34.2, 34.0, 33.9, 34.1])
        let center = mk([34.6, 34.4, 34.8, 35.1, 34.9, 35.2, 35.0, 35.3, 35.1, 35.4, 35.2, 35.5, 35.3])
        let rear   = mk([34.8, 34.9, 35.2, 35.6, 35.9, 36.3, 36.6, 36.9, 37.2, 37.5, 37.8, 38.1, 38.4])
        return [
            TempZone(name: "Front",  position: .front,  color: Brand.success, readings: front),
            TempZone(name: "Center", position: .center, color: Brand.blue,    readings: center),
            TempZone(name: "Rear",   position: .rear,   color: Brand.warning, readings: rear),
        ]
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int }
        do {
            async let ins: [VesselInspection] = EusoTripAPI.shared.query(
                "vesselShipments.getVesselInspections", input: ListIn(limit: 50))
            async let certs: [VesselCertificate652] = EusoTripAPI.shared.query(
                "vesselShipments.getVesselCertificates", input: ListIn(limit: 50))
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
