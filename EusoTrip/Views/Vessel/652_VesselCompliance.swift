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

/// One probe row from `vesselShipments.getReeferTempLog` — the same
/// `{ zone, temp/tempF, timestamp }` shape `reeferTemp.getReadings`
/// returns for the truck surface. Tolerant decode: `temp` and `tempF`
/// are both accepted so the proc can ship either column name.
private struct ReeferLogRow652: Decodable, Hashable {
    let zone: String?
    let temp: Double?
    let tempF: Double?
    let timestamp: String?

    var resolvedTempF: Double? { tempF ?? temp }
}

// MARK: - Body

private struct VesselComplianceBody: View {
    @Environment(\.palette) private var palette
    @State private var inspections: [VesselInspection] = []
    @State private var certificates: [VesselCertificate652] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    /// Live reefer probe rows from `vesselShipments.getReeferTempLog`.
    /// Stays empty when the proc hasn't shipped / returns nothing — the
    /// Cold Chain tab then renders the honest seam card, never the prior
    /// fabricated 13-sample probe arrays.
    @State private var reeferLog: [ReeferLogRow652] = []
    @State private var reeferLogLoaded = false

    enum Tab: String, CaseIterable {
        case inspections = "Inspections"
        case certificates = "Certificates"
        case coldChain = "Cold Chain"
        case landfall = "Landfall"
    }
    @State private var activeTab: Tab = .inspections
    @State private var landfallCountry = "US"
    @State private var landfallRegime: EusoTripAPI.LandfallRegimeResponse? = nil
    @State private var loadingLandfall = false

    private var landfallRegimes: [LandfallRegime] {
        return [
            .init(code: "US", port: "US · LONG BEACH", portShort: "US·LGB", regimeLine: landfallRegime?.country == "US" ? landfallRegime!.arrivalInstrument : "USCG eNOA · USD", flag: .us, active: landfallCountry == "US"),
            .init(code: "CA", port: "CA · VANCOUVER",  portShort: "CA·VAN", regimeLine: landfallRegime?.country == "CA" ? landfallRegime!.arrivalInstrument : "TC PAIR · CAD",   flag: .ca, active: landfallCountry == "CA"),
            .init(code: "MX", port: "MX · MANZANILLO", portShort: "MX·ZLO", regimeLine: landfallRegime?.country == "MX" ? landfallRegime!.arrivalInstrument : "SEMAR · MXN",     flag: .mx, active: landfallCountry == "MX"),
        ]
    }

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
                    case .landfall:     landfallContent
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
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

    // MARK: - Cold chain

    /// FSMA Sanitary-Transportation excursion ceiling (°F). Regulatory
    /// constant, not per-tenant data.
    private let fsmaCeilingF: Double = 40

    @ViewBuilder
    private var coldChainContent: some View {
        if reeferZones.isEmpty {
            // Honest seam: decode path wired, no rows on the wire yet.
            VStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    VStack(spacing: 8) {
                        Image(systemName: "thermometer.snowflake")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Awaiting reefer temp log")
                            .font(.system(size: 14, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text("Probe traces light up here the moment real zone readings arrive for this operator's reefer containers. No series is invented in the meantime.")
                            .font(EType.caption).multilineTextAlignment(.center)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, Space.s4)
                    }
                    .padding(Space.s4)
                }
                .frame(height: 200)
            }
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                ReeferTempLogChart(
                    zones: reeferZones,
                    setpointF: nil,
                    ceilingF: fsmaCeilingF,
                    title: "REEFER COLD CHAIN",
                    unit: .celsius
                )
                Text("FSMA Sanitary-Transportation ceiling 40°F (4.4°C) · \(reeferLog.count) live readings.")
                    .font(EType.micro).foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, Space.s1)
            }
        }
    }

    /// Group the LIVE log rows by zone → TempZone traces, chronological.
    private var reeferZones: [TempZone] {
        guard !reeferLog.isEmpty else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func parse(_ s: String?) -> Date? {
            guard let s, !s.isEmpty else { return nil }
            return iso.date(from: s) ?? isoPlain.date(from: s)
        }
        var grouped: [String: [TempZone.Reading]] = [:]
        for row in reeferLog {
            guard let f = row.resolvedTempF, let t = parse(row.timestamp) else { continue }
            let key = (row.zone ?? "center").lowercased()
            grouped[key, default: []].append(.init(t: t, tempF: f))
        }
        func zone(_ key: String, _ name: String, _ pos: TempZone.Position, _ color: Color) -> TempZone? {
            guard let rs = grouped[key]?.sorted(by: { $0.t < $1.t }), rs.count >= 2 else { return nil }
            return TempZone(name: name, position: pos, color: color, readings: rs)
        }
        var zones: [TempZone] = []
        if let z = zone("front",  "Front",  .front,  Brand.success) { zones.append(z) }
        if let z = zone("center", "Center", .center, Brand.blue)    { zones.append(z) }
        if let z = zone("rear",   "Rear",   .rear,   Brand.warning) { zones.append(z) }
        // Extra (non-canonical) zones, alphabetical, capped to keep legible.
        let extras = grouped.keys
            .filter { !["front", "center", "rear"].contains($0) }
            .sorted().prefix(3)
        for key in extras {
            if let z = zone(key, key.capitalized, .center, Brand.info) { zones.append(z) }
        }
        return zones
    }

    // MARK: - Landfall

    @ViewBuilder
    private var landfallContent: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            LandfallRegimeRail(
                eyebrow: "LANDFALL REGIME · DESTINATION PORT",
                trailingEyebrow: "STATUS",
                regimes: landfallRegimes,
                variant: .selectorCaption,
                captionLines: [
                    .init(text: landfallRegime?.arrivalInstrument ?? "Awaiting regime instrument", tone: .primary),
                    .init(text: landfallRegime?.releaseInstrument ?? "Awaiting release instrument", tone: .secondary),
                    .init(text: landfallRegime?.freeTimeBasis ?? "Awaiting free-time basis", tone: .secondary)
                ],
                onSelect: { code in
                    landfallCountry = code
                    Task { await fetchLandfallRegime() }
                }
            )
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            
            if loadingLandfall {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
    }

    private func fetchLandfallRegime() async {
        loadingLandfall = true
        do {
            landfallRegime = try await EusoTripAPI.shared.getLandfallRegime(country: landfallCountry)
        } catch {
            landfallRegime = nil
        }
        loadingLandfall = false
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
            loadError = error.eusoUserCopy
        }
        loading = false

        // Cold chain
        do {
            let rows: [ReeferLogRow652] = try await EusoTripAPI.shared.query(
                "vesselShipments.getReeferTempLog", input: ListIn(limit: 200))
            self.reeferLog = rows
        } catch {
            self.reeferLog = []
        }
        reeferLogLoaded = true

        await fetchLandfallRegime()
    }
}

#Preview("652 · Vessel Compliance · Night") { VesselComplianceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("652 · Vessel Compliance · Light") { VesselComplianceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
