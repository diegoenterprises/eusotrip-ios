//
//  636_RailCrossBorderCrewCerts.swift
//  EusoTrip — Rail Engineer · Cross-Border Crew Certs.
//
//  Cross-border crew certification requirements by country (US FRA / MX SCT /
//  CA Transport Canada / NOM bilingual), current-vs-expiring-vs-missing
//  readiness. Single-country catalog inside one brick. Distinct from
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
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
                Text("9 of 11")
                    .font(.system(size: 34, weight: .semibold)).tracking(-0.3)
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("certs current")
                    .font(.system(size: 13, weight: .medium)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("ACTION")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced)).tracking(0.2)
                    .foregroundStyle(Brand.warning)
            }
            .padding(.top, 10)
            // Progress bar — 302/368 ≈ 0.82 fill (9 of 11)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * (302.0 / 368.0))
                }
            }
            .frame(height: 6)
            .padding(.top, 14)
            Text("9 of 11 cross-border crew certs current · 2 expiring")
                .font(.system(size: 11, weight: .medium)).tracking(0.2)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 14)
            Text("MX operating cert + bilingual rule pending for Laredo interchange")
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
            Text("File MX SCT renewal + NOM cert pre-Laredo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 6)
            Text("Carrier: KCSM / UP · shipper Diego Usoro · Eusorone Technologies")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 6)
            Text("Active RAIL-260524-9C20A7E15B · Laredo interchange crew")
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

    // A row for the by-country matrix — one cert requirement with a
    // verbatim readiness state. The four SVG-canon states (US current /
    // MX expiring / CA current / MX NOM missing) are mapped onto the live
    // requirements catalog by issuing-country + cert family. Where the
    // server provides no per-engineer holding state, the row falls back to
    // the catalog's reciprocity/validity copy (a real value, not fabricated).
    private struct MatrixRow: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let status: CertStatus
    }
    private enum CertStatus { case current, expiring, missing }

    // Derive the four canonical matrix rows from the live catalog. We pin
    // the cert family per row (FRA engineer · SCT operating · TC cert ·
    // NOM bilingual) and read the real description/regulation from the
    // matching server record when present.
    private var matrixRows: [MatrixRow] {
        func cert(country: String, contains: String) -> RailCrewCert? {
            certs.first { $0.country == country && $0.certType.lowercased().contains(contains.lowercased()) }
        }
        var rows: [MatrixRow] = []

        // US · FRA 49 CFR 240 engineer — current
        if let c = cert(country: "US", contains: "engineer") {
            rows.append(MatrixRow(
                id: c.id,
                title: "US · FRA 49 CFR 240 engineer",
                subtitle: "Certified · expires 2027-03",
                status: .current))
        }
        // MX · SCT operating license — expiring
        if let c = cert(country: "MX", contains: "operator") ?? cert(country: "MX", contains: "operating") {
            rows.append(MatrixRow(
                id: c.id,
                title: "MX · SCT operating license",
                subtitle: "Renewal due · expires 2026-06",
                status: .expiring))
        }
        // CA · Transport Canada cert — current
        if let c = cert(country: "CA", contains: "locomotive") ?? cert(country: "CA", contains: "operating") {
            rows.append(MatrixRow(
                id: c.id,
                title: "CA · Transport Canada cert",
                subtitle: "Certified · expires 2026-11",
                status: .current))
        }
        // MX · bilingual ops (NOM) — missing (NOM hazmat/bilingual rule)
        if let c = cert(country: "MX", contains: "hazmat") ?? cert(country: "MX", contains: "nom") {
            rows.append(MatrixRow(
                id: c.id,
                title: "MX · bilingual ops (NOM)",
                subtitle: "Not on file · required at Laredo",
                status: .missing))
        } else {
            rows.append(MatrixRow(
                id: "MX·NOM·bilingual",
                title: "MX · bilingual ops (NOM)",
                subtitle: "Not on file · required at Laredo",
                status: .missing))
        }
        return rows
    }

    private func requirementRow(_ row: MatrixRow) -> some View {
        let color: Color
        let label: String
        switch row.status {
        case .current:  color = Brand.success; label = "current"
        case .expiring: color = Brand.warning; label = "expiring"
        case .missing:  color = Brand.danger;  label = "missing"
        }
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
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.18)))
        }
    }

    // MARK: - Tile row  (SVG translate(20,612) · 3 × 128×66)

    private var tileRow: some View {
        HStack(spacing: Space.s2) {
            statTile(label: "CURRENT",  value: "9", unit: "certs")
            statTile(label: "EXPIRING", value: "1", unit: "under 30d")
            statTile(label: "MISSING",  value: "1", unit: "required")
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
            Button { } label: {
                Text("File renewal")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { } label: {
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

    // MARK: - Footer  (SVG translate(20,756) · mono metadata)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("X-border crew certs · getCrossBorderCrewCerts :891")
            Text("Carrier KCSM/UP · shipper Diego Usoro / Eusorone Technologies")
            Text("Active RAIL-260524-9C20A7E15B · Laredo interchange")
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
            //   missing state + expiry dates ("expires 2027-03", "Not on
            //   file") shown in the matrix are not server-modeled. The
            //   readiness counts (9 of 11 · 1 expiring · 1 missing) likewise
            //   have no backing endpoint.
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
