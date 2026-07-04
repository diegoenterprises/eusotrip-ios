//
//  636_RailCrossBorderCrewCerts.swift
//  EusoTrip — Rail Engineer · Cross-Border Crew Certs.
//
//  Cross-border crew certification requirements by country (US FRA / MX SCT /
//  CA Transport Canada / NOM bilingual), live requirement readiness by
//  country. Single-country catalog inside one brick. Distinct from
//  595 Crew Certifications (general per-member certs).
//
//  tRPC anchors (REAL · railShipments.ts):
//    railShipments.getCrossBorderCrewCerts          :1014  (input { country })
//    railShipments.getCrossBorderInterchangePoints  :1010  (input { country, railroad })
//
//  The server returns the cross-border crew-cert *requirements catalog*
//  (getCrewCertRequirements → RAIL_CREW_CERTS filtered by country). It is
//  country-scoped (one country per call), so the matrix below fans out to
//  US + MX + CA concurrently and merges. Per-engineer holding state
//  (current / expiring / missing + expiry dates) is NOT modeled by any
//  rail endpoint — see PORT-GAP notes in `reload()`.
//

import SwiftUI

struct RailCrossBorderCrewCertsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailCrossBorderCrewCertsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror RailCrewCertification — crossBorderRail.ts :17)

private struct RailCrewCert: Decodable, Identifiable {
    let country: String
    let certType: String
    let description: String?
    let issuingAuthority: String?
    let regulation: String?
    let validityYears: Int?
    let requiredFor: String?
    let crossBorderReciprocity: String?

    var id: String { "\(country)·\(certType)" }
}

// MARK: - Body

private struct RailCrossBorderCrewCertsBody: View {
    @Environment(\.palette) private var palette

    @State private var certs: [RailCrewCert] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showingCrewCatalog = false

    // Country order matches the SVG matrix rows: US · MX · CA.
    private let countries: [String] = ["US", "MX", "CA"]

    private var countryCount: Int {
        Set(certs.map { $0.country }).count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                IridescentHairline()

                if loading {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(palette.bgCardSoft).frame(height: 124)
                            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    readinessCard
                    requirementsCard
                    tileRow
                    buttonRow
                    crewCatalogPanel
                    footer
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow  (SVG translate(20,72))

    private var eyebrow: some View {
        HStack(spacing: 4) {
            Text("✦ RAIL ENGINEER · X-BORDER CREW")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("USMCA")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title block  (back chevron + title + right meta)

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(Color(hex: 0x1C2128))
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Crew cert matrix")
                    .font(.system(size: 22, weight: .bold)).tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("cross-border · by country")
                    .font(EType.mono(.caption)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("KCSM / UP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("synced 6m ago")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Readiness card  (SVG translate(20,160) · 124h)

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CREW · CERTIFICATION READINESS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(countryCount) COUNTRIES")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(certs.count)")
                    .font(.system(size: 34, weight: .semibold)).tracking(-0.3)
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("requirements loaded")
                    .font(.system(size: 13, weight: .medium)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(countryCount == countries.count ? "LIVE" : "SYNC")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced)).tracking(0.2)
                    .foregroundStyle(countryCount == countries.count ? Brand.success : Brand.warning)
            }
            .padding(.top, 10)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(countryCount) / CGFloat(max(countries.count, 1)))
                }
            }
            .frame(height: 6)
            .padding(.top, 14)
            Text("\(certs.count) cross-border crew requirements loaded across \(countryCount) countr\(countryCount == 1 ? "y" : "ies")")
                .font(.system(size: 11, weight: .medium)).tracking(0.2)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 14)
            Text("Crew-by-crew filing status is not on file yet; renewal packet uses live country rules.")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 6)
        }
        .padding(Space.s4)
        .background(Color(hex: 0x1C2128))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Requirements card  (SVG translate(20,296) · 300h)

    private var requirementsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("REQUIREMENTS · BY COUNTRY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(countryCount) COUNTRIES")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)

            if matrixRows.isEmpty {
                EusoEmptyState(systemImage: "person.text.rectangle",
                               title: "No crew cert requirements",
                               subtitle: "Cross-border crew certification rules will appear here.")
                    .padding(.vertical, Space.s2)
            } else {
                VStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(matrixRows) { row in requirementRow(row) }
                }
            }

            // Readiness · recommendation block (SVG y=232..288)
            Text("READINESS · RECOMMENDATION")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s4)
            Text(recommendationHeadline)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)
            Text("Source: live US / MX / CA cross-border crew requirements catalog")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 6)
            Text("Action: share packet with the compliance owner; crew filing status is pending record intake.")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 6)
        }
        .padding(Space.s4)
        .background(Color(hex: 0x1C2128))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // A row for the by-country matrix — one live cert requirement. The
    // backend currently returns requirement templates, not per-engineer
    // holding state, so rows show required catalog status instead of
    // fabricated current / expiring / missing labels.
    private struct MatrixRow: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let country: String
    }

    private var matrixRows: [MatrixRow] {
        countries.flatMap { country in
            certs.filter { $0.country == country }.map { c in
                MatrixRow(
                id: c.id,
                title: "\(country) · \(cleanCertType(c.certType))",
                subtitle: certSubtitle(c),
                country: country
                )
            }
        }
    }

    private func requirementRow(_ row: MatrixRow) -> some View {
        let color = countryAccent(row.country)
        return HStack(alignment: .top, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(row.subtitle)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 4)
            Text("required")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.18)))
        }
    }

    // MARK: - Tile row  (SVG translate(20,612) · 3 × 128×66)

    private var tileRow: some View {
        HStack(spacing: Space.s2) {
            statTile(label: "US", value: "\(certCount("US"))", unit: "rules")
            statTile(label: "MX", value: "\(certCount("MX"))", unit: "rules")
            statTile(label: "CA", value: "\(certCount("CA"))", unit: "rules")
        }
    }

    private func statTile(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .semibold)).tracking(0.4)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text(unit)
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x1C2128))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Button row  (SVG translate(20,692) · 2 × 196×48)

    private var buttonRow: some View {
        HStack(spacing: Space.s2) {
            ShareLink(item: renewalPacketText) {
                Text("Renewal packet")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }

            Button { showingCrewCatalog.toggle() } label: {
                Text("Crew certs")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                    .background(Color(hex: 0x1C2128))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var crewCatalogPanel: some View {
        if showingCrewCatalog {
            LifecycleCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    LifecycleSection(label: "LIVE CREW CERT CATALOG", icon: "person.text.rectangle.fill")
                    if certs.isEmpty {
                        Text("No cross-border crew requirements returned.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        ForEach(Array(matrixRows.prefix(8).enumerated()), id: \.element.id) { idx, row in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(row.subtitle)
                                    .font(EType.mono(.micro))
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                            if idx < min(matrixRows.count, 8) - 1 {
                                Divider().overlay(palette.borderFaint)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recommendationHeadline: String {
        let mx = certCount("MX")
        if mx > 0 { return "Export MX / NOM renewal packet from \(mx) live requirement\(mx == 1 ? "" : "s")" }
        if certs.isEmpty { return "Reload cross-border crew requirements before filing" }
        return "Export cross-border crew renewal packet"
    }

    private var renewalPacketText: String {
        var lines: [String] = [
            "EusoTrip Rail Cross-Border Crew Renewal Packet",
            "Generated: \(Date().formatted(date: .abbreviated, time: .shortened))",
            "Source: live cross-border crew requirements catalog",
            "",
            "Summary",
            "- US requirements: \(certCount("US"))",
            "- MX requirements: \(certCount("MX"))",
            "- CA requirements: \(certCount("CA"))",
            "",
            "Renewal candidates",
        ]
        let candidates = certs.filter {
            $0.country == "MX"
            || $0.certType.localizedCaseInsensitiveContains("nom")
            || $0.certType.localizedCaseInsensitiveContains("sct")
            || ($0.regulation ?? "").localizedCaseInsensitiveContains("nom")
        }
        let packetRows = candidates.isEmpty ? certs : candidates
        if packetRows.isEmpty {
            lines.append("- No live requirement rows were returned.")
        } else {
            for cert in packetRows {
                lines.append("- \(cert.country) \(cleanCertType(cert.certType)): \(certSubtitle(cert))")
            }
        }
        lines.append("")
        lines.append("Note: crew-by-crew renewal filing status is pending record intake.")
        return lines.joined(separator: "\n")
    }

    private func certCount(_ country: String) -> Int {
        certs.filter { $0.country == country }.count
    }

    private func cleanCertType(_ certType: String) -> String {
        certType
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func certSubtitle(_ cert: RailCrewCert) -> String {
        var parts: [String] = []
        if let authority = cert.issuingAuthority, !authority.isEmpty { parts.append(authority) }
        if let regulation = cert.regulation, !regulation.isEmpty { parts.append(regulation) }
        if let years = cert.validityYears { parts.append("\(years)y validity") }
        if let requiredFor = cert.requiredFor, !requiredFor.isEmpty { parts.append(requiredFor) }
        return parts.isEmpty ? (cert.description ?? "Cross-border requirement") : parts.joined(separator: " · ")
    }

    private func countryAccent(_ country: String) -> Color {
        switch country {
        case "US": return Brand.blue
        case "MX": return Brand.warning
        case "CA": return Brand.success
        default: return palette.textSecondary
        }
    }

    // MARK: - Footer  (SVG translate(20,756) · mono metadata)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("X-border crew certs · live records")
            Text("\(certs.count) requirement rows · \(countryCount) countries")
            Text("Crew filing status appears when expiry records are loaded")
        }
        .font(EType.mono(.micro)).tracking(0.3)
        .foregroundStyle(palette.textTertiary)
        .padding(.top, Space.s2)
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct CountryIn: Encodable { let country: String }
        do {
            // The endpoint is country-scoped (one country per call). Fan
            // out US + MX + CA concurrently and merge into the matrix.
            // PORT-GAP: railShipments.getCrossBorderCrewCerts returns the
            //   cross-border crew-cert REQUIREMENTS catalog only — there is
            //   no per-engineer holding endpoint, so the current/expiring/
            //   missing state + expiry dates are not server-modeled. This
            //   screen therefore renders live requirement counts and a
            //   shareable renewal packet instead of fabricated holding state.
            async let us:  [RailCrewCert] = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderCrewCerts", input: CountryIn(country: "US"))
            async let mx:  [RailCrewCert] = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderCrewCerts", input: CountryIn(country: "MX"))
            async let ca:  [RailCrewCert] = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderCrewCerts", input: CountryIn(country: "CA"))
            let (usC, mxC, caC) = try await (us, mx, ca)
            // Preserve SVG row order: US · MX · CA.
            self.certs = usC + mxC + caC
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("636 · Rail X-Border Crew Certs · Night") {
    RailCrossBorderCrewCertsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("636 · Rail X-Border Crew Certs · Light") {
    RailCrossBorderCrewCertsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
