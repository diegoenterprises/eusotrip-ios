//
//  595_RailCrewCertifications.swift
//  EusoTrip — Rail Engineer · Crew Certifications (carrier-side credential matrix).
//
//  ARCHETYPE = CREDENTIAL MATRIX (crew rows × cert columns ENG/COND/HAZ/MX with
//  per-cell valid/expiring/expired/NA state + expiry). Carrier confirms the
//  assigned crew is lane-eligible across both countries (US + MX) before
//  tendering the Laredo lane. 49 CFR 240/242 · SCT.
//
//  Wired to railShipments.getRailCrew (roster) + railShipments.getCrossBorderCrewCerts
//  (per-country cert requirements). See PORT-GAP note in `load()` — the backend
//  has no endpoint returning per-crew × per-cert STATUS + expiry, so matrix cells
//  render real NA ("—") until that field exists. No fabricated expiry values.
//

import SwiftUI

struct RailCrewCertificationsScreen: View {
    let theme: Theme.Palette
    var consistId: String = ""
    var corridor: String = ""

    var body: some View {
        Shell(theme: theme) { RailCrewCertificationsBody() } nav: {
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

/// Roster row — railShipments.getRailCrew (rail_crew_assignments).
private struct RailCrewMember: Decodable, Identifiable {
    let id: Int
    let userId: Int?
    let consistId: Int?
    let role: String?
    let assignedAt: String?
    let relievedAt: String?
    let hoursOnDuty: String?
    let hoursOfServiceCompliant: Bool?
    let name: String?       // present only if the join surfaces it (else nil)
}

/// Per-country cert requirement template — railShipments.getCrossBorderCrewCerts.
private struct RailCrewCertReq: Decodable, Identifiable {
    let country: String?
    let certType: String?
    let description: String?
    let issuingAuthority: String?
    let regulation: String?
    let validityYears: Int?
    let requiredFor: String?
    let crossBorderReciprocity: String?
    var id: String { (country ?? "") + "·" + (certType ?? "") }
}

/// Per-cell credential state for the matrix. Backend supplies no per-crew
/// per-cert STATUS today (PORT-GAP), so every cell resolves to `.na` until
/// that field ships. No fabricated valid/expiring/expired values.
private enum CertCellState {
    case valid(String)      // e.g. "'28"
    case expiring(String)   // e.g. "24d"
    case expired            // "exp"
    case missing            // "none"
    case na                 // "—"
}

// MARK: - Body

private struct RailCrewCertificationsBody: View {
    @Environment(\.palette) private var palette

    @State private var crew: [RailCrewMember] = []
    @State private var certReqsUS: [RailCrewCertReq] = []
    @State private var certReqsMX: [RailCrewCertReq] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    /// Cert columns in the matrix, verbatim from the wireframe header row.
    private let columns: [String] = ["ENG", "COND", "HAZ", "MX"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                IridescentHairline()
                summaryCard
                matrixSection
                nextExpiryBanner
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Eyebrow

    private var eyebrow: some View {
        HStack {
            Text("✦ RAIL ENGINEER · CREW CERTS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("AURORA RAIL · \(crew.count) CREW")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Crew certs")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Summary card (LANE-READY · US + MX CERTS)

    private var summaryCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // Lane-ready fraction
            VStack(alignment: .leading, spacing: 8) {
                Text("LANE-READY · US + MX CERTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(laneReadyCount)")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("/\(crew.count)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            // Legend
            VStack(alignment: .leading, spacing: 8) {
                legendRow(color: Brand.success, "\(validCells) valid")
                legendRow(color: Brand.warning, "\(expiringCells) expiring <30d")
                legendRow(color: Brand.danger,  "\(expiredOrMissingCells) expired / missing")
            }
            Spacer(minLength: 0)
            // Corridor
            VStack(alignment: .trailing, spacing: 4) {
                Text("CORRIDOR")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text(corridorName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(corridorRailroads)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private func legendRow(color: Color, _ text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Credential matrix

    private var matrixSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CREDENTIAL MATRIX")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("49 CFR 240/242 · SCT")
                    .font(EType.mono(.micro)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                if loading {
                    ForEach(0..<4, id: \.self) { _ in matrixSkeletonRow }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(Space.s3)
                } else if crew.isEmpty {
                    EusoEmptyState(systemImage: "person.2",
                                   title: "No crew assigned",
                                   subtitle: "Assigned crew will appear here once a consist is staffed.")
                        .padding(.vertical, Space.s5)
                } else {
                    // Column header
                    matrixHeaderRow
                    Divider().overlay(palette.borderFaint)
                    ForEach(Array(crew.enumerated()), id: \.element.id) { idx, member in
                        crewRow(member)
                        if idx < crew.count - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                }
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var matrixHeaderRow: some View {
        HStack(spacing: 0) {
            Text("CREW")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { col in
                Text(col)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 40, alignment: .center)
            }
        }
        .padding(.bottom, Space.s2)
    }

    private func crewRow(_ member: RailCrewMember) -> some View {
        HStack(spacing: 0) {
            // Avatar + name + role
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                        .frame(width: 32, height: 32)
                    Text(initials(for: member))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: member))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(roleLabel(member.role))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(columns, id: \.self) { col in
                certCell(state: cellState(for: member, column: col))
                    .frame(width: 40, alignment: .center)
            }
        }
        .padding(.vertical, Space.s2)
    }

    private func certCell(state: CertCellState) -> some View {
        let label: String
        let color: Color
        let tinted: Bool
        switch state {
        case .valid(let v):    label = v;      color = Brand.success; tinted = true
        case .expiring(let v): label = v;      color = Brand.warning; tinted = true
        case .expired:         label = "exp";  color = Brand.danger;  tinted = true
        case .missing:         label = "none"; color = Brand.danger;  tinted = true
        case .na:              label = "—";    color = palette.textTertiary; tinted = false
        }
        return Text(label)
            .font(.system(size: 10, weight: tinted ? .bold : .regular))
            .foregroundStyle(color)
            .frame(width: 32, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tinted ? color.opacity(0.16) : Color.white.opacity(0.05))
            )
    }

    private var matrixSkeletonRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(palette.bgCardSoft).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4).fill(palette.bgCardSoft).frame(width: 90, height: 11)
                    RoundedRectangle(cornerRadius: 4).fill(palette.bgCardSoft).frame(width: 56, height: 9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { col in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(width: 32, height: 30)
                    .frame(width: 40, alignment: .center)
            }
        }
        .padding(.vertical, Space.s2)
        .redacted(reason: .placeholder)
    }

    // MARK: - Next-expiry banner

    @ViewBuilder
    private var nextExpiryBanner: some View {
        if let next = nextExpiry {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Brand.warning.opacity(0.18))
                        .frame(width: 30, height: 30)
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(next.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.warning.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Renew cert")
                .frame(maxWidth: .infinity)
            Button {
            } label: {
                Text("Roster")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Derived metrics

    /// Crew rows that are lane-ready. Backend has no per-cell cert STATUS yet
    /// (PORT-GAP), so a member is lane-ready only when their HOS-compliant flag
    /// is true AND they are still actively assigned (not relieved). This is the
    /// only honest signal the roster row carries; cert-cell readiness fills in
    /// once getRailCrewCerts (per-crew × per-cert) ships.
    private var laneReadyCount: Int {
        crew.filter { ($0.hoursOfServiceCompliant ?? false) && $0.relievedAt == nil }.count
    }

    private var allCells: [CertCellState] {
        crew.flatMap { member in columns.map { cellState(for: member, column: $0) } }
    }
    private var validCells: Int {
        allCells.reduce(into: 0) { acc, c in if case .valid = c { acc += 1 } }
    }
    private var expiringCells: Int {
        allCells.reduce(into: 0) { acc, c in if case .expiring = c { acc += 1 } }
    }
    private var expiredOrMissingCells: Int {
        allCells.reduce(into: 0) { acc, c in
            switch c { case .expired, .missing: acc += 1; default: break }
        }
    }

    /// Earliest upcoming expiry across the matrix. Returns nil until per-cell
    /// cert expiry data exists (PORT-GAP) — banner is hidden rather than faked.
    private var nextExpiry: (title: String, subtitle: String)? {
        // No per-cell expiry field on the wire yet → nothing honest to surface.
        return nil
    }

    private var corridorName: String {
        // Single Laredo/Nuevo Laredo interchange surface (no corridor selector on this screen).
        "Laredo"
    }
    private var corridorRailroads: String {
        // Laredo/Nuevo Laredo interchange (INT-009) railroads — US side UP, MX side FXE.
        "UP · FXE"
    }

    // MARK: - Cell + identity resolution

    /// Per-crew × per-cert STATUS is not exposed by the API (PORT-GAP:
    /// railShipments.getRailCrewCerts). Until that endpoint exists every cell
    /// resolves to `.na` — we never fabricate '28 / 24d / exp / none values.
    private func cellState(for member: RailCrewMember, column: String) -> CertCellState {
        return .na
    }

    private func displayName(for member: RailCrewMember) -> String {
        if let n = member.name, !n.trimmingCharacters(in: .whitespaces).isEmpty { return n }
        if let uid = member.userId { return "Crew #\(uid)" }
        return "Crew #\(member.id)"
    }

    private func initials(for member: RailCrewMember) -> String {
        let n = displayName(for: member)
        let parts = n.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }
        if chars.isEmpty { return "?" }
        return String(chars).uppercased()
    }

    private func roleLabel(_ role: String?) -> String {
        switch (role ?? "").lowercased() {
        case "engineer":   return "Engineer"
        case "conductor":  return "Conductor"
        case "brakeman":   return "Brakeman"
        case "dispatcher": return "Dispatcher"
        default:           return role?.capitalized ?? "Crew"
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct CrewIn: Encodable { let limit: Int }
        struct CountryIn: Encodable { let country: String }
        do {
            async let roster: [RailCrewMember] = EusoTripAPI.shared.query(
                "railShipments.getRailCrew", input: CrewIn(limit: 50))
            async let usReqs: [RailCrewCertReq] = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderCrewCerts", input: CountryIn(country: "US"))
            async let mxReqs: [RailCrewCertReq] = EusoTripAPI.shared.query(
                "railShipments.getCrossBorderCrewCerts", input: CountryIn(country: "MX"))
            let (r, us, mx) = try await (roster, usReqs, mxReqs)
            self.crew = r
            self.certReqsUS = us
            self.certReqsMX = mx
            // PORT-GAP: railShipments.getRailCrewCerts — no endpoint returns
            // per-crew × per-cert (ENG/COND/HAZ/MX) STATUS + expiry. getRailCrew
            // is roster-only; getCrossBorderCrewCerts is requirement-templates.
            // Matrix cells render real NA ("—") until that field ships.
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("595 · Rail Crew Certifications · Night") { RailCrewCertificationsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("595 · Rail Crew Certifications · Light") { RailCrewCertificationsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
