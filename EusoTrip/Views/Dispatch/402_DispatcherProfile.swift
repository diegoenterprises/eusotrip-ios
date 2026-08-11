//
//  402_DispatcherProfile.swift
// OFFLINE: READ_CACHED(24h) pure read — hero/ladder/credentials/90D strip from cache with staleness line; no write verbs, nothing queues; reconnect FULL.
//  EusoTrip — Dispatcher · Profile (dispatcher-self vantage).
//
//  Verbatim port of "402 Dispatcher Profile.svg" (Dark canonical · 440×956).
//  THE OATH · §71 · round-robin Dispatcher port (lowest unbuilt VECTOR in the
//  04 Dispatcher 400-band; 402 was the lowest main screen with no Swift caller —
//  the Dpch720 trio covers 403/405/411, not 402).
//
//  Surface anatomy (verbatim to the SVG, element order preserved):
//    · TopBar eyebrow  "✦ DISPATCHER · ME · PROFILE"  +  right "TENURE {n}Y · ID {emp}"
//    · Display name (h1) + subtitle "{title} · {company} · {base}"
//    · Small initials avatar top-right
//    · IridescentHairline
//    · Identity hero card (gradient rim · gold-ring avatar · name/title/co/USDOT-MC
//      · status pills · FLEET / ROSTER / BASE stat row)
//    · Tier ladder (5 chips: Bronze 0 · Silver 80 · Gold 200 · Platinum 280 · Diamond 320)
//    · Credentials grid (real certifications, up to 6)
//    · Desk today card (4 rows: ACTIVE HAULS · PENDING TENDERS · DRIVERS IDLE · EXCEPTIONS)
//    · Dispatcher BottomNav (ME current)
//
//  Data (all real, no mock):
//    dispatch.getProfile        (NEW :gap-fill §71) → identity + fleet/roster counts +
//                                                     credentials (certifications) + tier ladder.
//                                                     composite/tier are NULL by design — there is
//                                                     NO persisted dispatcher composite metric in
//                                                     schema.ts (verified §71), so the ladder renders
//                                                     "NOT YET SCORED" with no active marker rather
//                                                     than fabricating the persona's "213/320 GOLD".
//    dispatch.getDashboardStats (EXISTS :359)        → desk-today counts (real, tri-modal,
//                                                      requireAccess-gated). Mapping (documented in
//                                                      report §71): ACTIVE HAULS=active ·
//                                                      PENDING TENDERS=unassigned (loads awaiting
//                                                      tender/assignment) · DRIVERS IDLE=availableDrivers ·
//                                                      EXCEPTIONS=issues. The SVG's persona sub-labels
//                                                      (on-time 92%, "4 expire <1h", avg HOS, "Karch ·
//                                                      sleeper berth") are NOT fabricated here — only the
//                                                      real headline counts render.
//
//  Nav: shipped Dispatcher bottom nav (Home · Drivers | Loads · Me) per the house
//  pattern used by 539_DispatcherCarrierScorecard. The SVG's literal tab labels
//  (HOME / BOARD / COMMS / ME) diverge from the shipped DispatchNavController set;
//  flagged for the nav lane in report §71 (no dead taps introduced here).
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decodable contracts (field-for-field with the REAL server returns)

private struct DispatchProfile402: Decodable {
    let userId: Int
    let name: String
    let initials: String
    let title: String
    let role: String
    let company: String
    let companyId: Int?
    let dotNumber: String?
    let mcNumber: String?
    let baseCity: String?
    let baseState: String?
    let baseLabel: String?
    let profilePicture: String?
    let verified: Bool
    let tenureYears: Int
    let tenureLabel: String
    let employeeId: String?
    let fleetCount: Int
    let rosterCount: Int
    let composite: Int?            // NULL until a real dispatcher score exists
    let compositeMax: Int
    let tier: String?             // NULL until scored
    let nextTier: String?
    let toNextTier: Int?
    let tierLadder: [TierRung402]
    let credentials: [Credential402]
    let credentialCount: Int
}

private struct TierRung402: Decodable, Identifiable {
    let name: String
    let threshold: Int
    var id: String { name }
}

private struct Credential402: Decodable, Identifiable {
    let id: Int
    let type: String
    let name: String
    let expiryDate: String?
    let status: String
}

// dispatch.getDashboardStats — decode only the fields the desk-today card needs (lenient).
private struct DeskStats402: Decodable {
    let active: Int?
    let unassigned: Int?
    let availableDrivers: Int?
    let issues: Int?
}

// MARK: - Screen

struct DispatcherProfileScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { DispatcherProfileBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct DispatcherProfileBody: View {
    @Environment(\.palette) private var palette

    @State private var profile: DispatchProfile402? = nil
    @State private var desk: DeskStats402? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Gold tier-ring gradient (verbatim to SVG #DAB033 → #FFD966).
    private let goldRing = LinearGradient(
        colors: [Color(hex: 0xDAB033), Color(hex: 0xFFD966)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar

            Text(profile?.name ?? "Dispatcher")
                .font(EType.h1).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 18)
            Text(subtitleLine)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)

            IridescentHairline().padding(.top, 16)

            if loading {
                placeholder("Loading profile…", danger: false)
            } else if let err = loadError, profile == nil {
                placeholder(err, danger: true)
            } else if let p = profile {
                identityCard(p).padding(.top, 20)
                tierLadder(p).padding(.top, 22)
                credentials(p).padding(.top, 22)
                deskToday().padding(.top, 22)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .task { await load() }
        .refreshable { await load() }
    }

    private var subtitleLine: String {
        guard let p = profile else { return "Dispatcher" }
        var parts: [String] = [p.title]
        if !p.company.isEmpty { parts.append(p.company) }
        if let b = p.baseLabel, !b.isEmpty { parts.append(b) }
        return parts.joined(separator: " · ")
    }

    // MARK: TopBar eyebrow

    private var topBar: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("✦ DISPATCHER · ME · PROFILE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text(tenureIdLine)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var tenureIdLine: String {
        guard let p = profile else { return "" }
        var s = "TENURE \(p.tenureLabel)"
        if let e = p.employeeId, !e.isEmpty { s += " · ID \(e)" }
        return s
    }

    // MARK: Identity hero card

    private func identityCard(_ p: DispatchProfile402) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                // Gold-ringed initials avatar
                ZStack {
                    Circle().stroke(goldRing, lineWidth: 3).frame(width: 96, height: 96)
                    Circle().fill(LinearGradient.diagonal).frame(width: 88, height: 88)
                    Text(p.initials)
                        .font(.system(size: 30, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(EType.h2).foregroundStyle(palette.textPrimary)
                    Text(p.title).font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                    Text(p.company).font(EType.caption).foregroundStyle(palette.textTertiary)
                    Text(dotMcLine(p))
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            // Status pills
            HStack(spacing: 6) {
                pill("ON-DESK", fill: AnyShapeStyle(Brand.success), fg: .white)
                pill(p.role.uppercased(), fill: AnyShapeStyle(LinearGradient.primary), fg: .white)
                pill("TENURE \(p.tenureLabel)", fill: AnyShapeStyle(palette.bgCardSoft), fg: palette.textPrimary, bordered: true)
            }
            .padding(.top, 18)

            Divider().overlay(palette.borderFaint).padding(.top, 16)

            // FLEET / ROSTER / BASE
            HStack(alignment: .top, spacing: 0) {
                statCell("FLEET", "\(p.fleetCount) truck\(p.fleetCount == 1 ? "" : "s")")
                statCell("ROSTER", "\(p.rosterCount) driver\(p.rosterCount == 1 ? "" : "s")")
                statCell("BASE", p.baseLabel ?? "-")
            }
            .padding(.top, 14)
        }
        .padding(20)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private func dotMcLine(_ p: DispatchProfile402) -> String {
        var bits: [String] = []
        if let d = p.dotNumber, !d.isEmpty { bits.append("USDOT \(d)") }
        if let m = p.mcNumber, !m.isEmpty { bits.append("MC \(m)") }
        return bits.isEmpty ? "-" : bits.joined(separator: " · ")
    }

    private func pill(_ text: String, fill: AnyShapeStyle, fg: Color, bordered: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
            .foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(fill))
            .overlay(bordered ? AnyView(Capsule().stroke(palette.borderFaint, lineWidth: 1)) : AnyView(EmptyView()))
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Tier ladder

    private func tierLadder(_ p: DispatchProfile402) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ladderHeader(p))
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let next = p.nextTier, let to = p.toNextTier {
                    Text("\(to) to \(next.capitalized) →")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(p.tierLadder) { rung in
                    tierChip(rung, active: isActiveTier(rung, p))
                }
            }
        }
    }

    private func ladderHeader(_ p: DispatchProfile402) -> String {
        if let c = p.composite, let t = p.tier {
            return "LADDER · \(c)/\(p.compositeMax) · \(t.uppercased())"
        }
        return "LADDER · NOT YET SCORED"
    }

    private func isActiveTier(_ rung: TierRung402, _ p: DispatchProfile402) -> Bool {
        guard let t = p.tier else { return false }
        return rung.name.caseInsensitiveCompare(t) == .orderedSame
    }

    private func tierChip(_ rung: TierRung402, active: Bool) -> some View {
        VStack(spacing: 4) {
            Text(rung.name)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(active ? Color.white : palette.textSecondary)
            Text("\(rung.threshold)")
                .font(EType.mono(.micro))
                .foregroundStyle(active ? Color.white.opacity(0.85) : palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(active ? AnyShapeStyle(goldRing) : AnyShapeStyle(palette.bgCard))
        )
        .overlay {
            if !active {
                RoundedRectangle(cornerRadius: Radius.md).stroke(palette.borderFaint, lineWidth: 1)
            }
        }
    }

    // MARK: Credentials grid

    private func credentials(_ p: DispatchProfile402) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CREDENTIALS · \(p.credentialCount) ACTIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if p.credentials.isEmpty {
                Text("No credentials on file. Add certifications in onboarding to populate this grid.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: Radius.md).stroke(palette.borderFaint, lineWidth: 1))
            } else {
                let cols = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(p.credentials.prefix(6)) { c in credentialCard(c) }
                }
            }
        }
    }

    private func credentialCard(_ c: Credential402) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 16, height: 16)
                Image(systemName: credentialGlyph(c))
                    .font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            Text(c.name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(credentialSub(c))
                .font(EType.caption)
                .foregroundStyle(c.status == "expired" ? Brand.danger : palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md).stroke(palette.borderFaint, lineWidth: 1))
    }

    private func credentialGlyph(_ c: Credential402) -> String {
        if c.status == "expired" { return "exclamationmark" }
        return "checkmark"
    }

    private func credentialSub(_ c: Credential402) -> String {
        if c.status == "expired" { return "expired" }
        if let iso = c.expiryDate, let d = isoDate(iso) {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM"
            return "exp \(f.string(from: d))"
        }
        return c.status
    }

    private func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: Desk today (real headline counts from getDashboardStats)

    private func deskToday() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DESK TODAY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                deskRow("ACTIVE HAULS", desk?.active, first: true)
                deskRow("PENDING TENDERS", desk?.unassigned)
                deskRow("DRIVERS IDLE", desk?.availableDrivers)
                deskRow("EXCEPTIONS", desk?.issues, danger: (desk?.issues ?? 0) > 0)
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: Radius.lg).stroke(palette.borderFaint, lineWidth: 1))
        }
    }

    private func deskRow(_ label: String, _ value: Int?, first: Bool = false, danger: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first { Divider().overlay(palette.borderFaint) }
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(value.map(String.init) ?? "-")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(danger ? Brand.danger : palette.textPrimary)
            }
            .frame(height: 40)
        }
    }

    // MARK: Placeholder

    private func placeholder(_ text: String, danger: Bool) -> some View {
        HStack(spacing: 8) {
            if !danger { ProgressView().tint(palette.textSecondary) }
            Text(text)
                .font(EType.caption)
                .foregroundStyle(danger ? Brand.danger : palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    // MARK: Load (both reads real; no mock, honest error surfacing)

    private func load() async {
        loading = true; loadError = nil
        do {
            let p: DispatchProfile402 = try await EusoTripAPI.shared.queryNoInput("dispatch.getProfile")
            self.profile = p
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        // Desk-today is best-effort; a failure here must not blank the whole profile.
        do {
            let d: DeskStats402 = try await EusoTripAPI.shared.queryNoInput("dispatch.getDashboardStats")
            self.desk = d
        } catch {
            self.desk = nil   // rows render "-" rather than a fabricated number
        }
        loading = false
    }
}

#Preview("402 Dispatcher Profile · Dark") {
    DispatcherProfileScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("402 Dispatcher Profile · Light") {
    DispatcherProfileScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
