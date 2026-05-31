//
//  632_RailCrewAvailability.swift
//  EusoTrip — Rail Engineer · Crew Availability (carrier vantage).
//
//  Verbatim port of "632 Rail Crew Availability · Dark".
//  Flagship DETAIL grammar (per 621 / 609 / 553): back chevron + eyebrow +
//  mono caption + 28/-0.4 title, gradient-rimmed hero ActiveCard (lead figure
//  + progress), 3-cell KPI strip (cell-1 eusoDiagonal), itemized status stack
//  (40x40 icon chip + title + mono sub + short status pill + right tabular
//  value), context strip, Call crew / HOS roster CTA pair.
//
//  Crew-availability-by-yard board under FRA 49 CFR Part 228.
//  Real wiring: railShipments.getCrewAvailability(yardId) → CloudMoyo
//  CrewAvailabilityResult. NAV (RailEngineerNavController): HOME ·
//  SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//

import SwiftUI

struct RailCrewAvailabilityScreen: View {
    let theme: Theme.Palette
    /// Yard the board is scoped to. SVG hero/footer anchor is "LB ICTF"
    /// (Los Angeles ICTF — Intermodal Container Transfer Facility).
    var yardId: String = "LB ICTF"

    var body: some View {
        Shell(theme: theme) { RailCrewAvailabilityBody(yardId: yardId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror CloudMoyoCrewService.CrewAvailabilityResult)

private struct AvailableCrewMember632: Decodable, Identifiable {
    let crewMemberId: String
    let name: String?
    let role: String?
    let hoursRemaining: Double?
    let qualifications: [String]?
    let certifications: [String]?
    let seniority: Int?
    let boardPosition: Int?
    let estimatedCallTime: String?
    let restStatus: String?

    var id: String { crewMemberId }
}

private struct CrewAvailabilityResult632: Decodable {
    let yardId: String?
    let yardName: String?
    let railroad: String?
    let engineers: [AvailableCrewMember632]?
    let conductors: [AvailableCrewMember632]?
    let totalAvailable: Int?
    let totalOnDuty: Int?
    let totalResting: Int?
    let asOf: String?
}

// MARK: - Body

private struct RailCrewAvailabilityBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    let yardId: String

    @State private var board: CrewAvailabilityResult632? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var callingCrew = false

    // Derived crew tallies. CloudMoyo returns totals; total crew is the
    // sum of every roster line (available + on-duty + resting).
    private var availableCount: Int { board?.totalAvailable ?? 0 }
    private var onDutyCount:    Int { board?.totalOnDuty ?? 0 }
    private var restedOutCount: Int { board?.totalResting ?? 0 }
    private var totalCrew:      Int { availableCount + onDutyCount + restedOutCount }

    private var yardLabel: String { board?.yardName ?? yardId }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header

                if loading {
                    LifecycleCard {
                        Text("Loading crew availability…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if board != nil {
                    heroCard
                    kpiStrip
                    byStatusCard
                    nextAvailableStrip
                    ctaPair
                } else {
                    EusoEmptyState(systemImage: "person.2",
                                   title: "No crew board",
                                   subtitle: "Crew availability for \(yardLabel) will appear here.")
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Header (eyebrow + back chevron + title + sync block)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row: gradient sparkle eyebrow + right mono regulation tag.
            HStack {
                Text("✦  RAIL ENGINEER · CREW AVAIL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("FRA PART 228")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            // Back chevron + title block, sync metadata trailing.
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 6)
                Text("Crew availability")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(yardLabel)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(syncedLabel)
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, Space.s3)

            IridescentHairline()
                .padding(.top, Space.s3)
        }
    }

    private var syncedLabel: String {
        guard let asOf = board?.asOf, let date = parseDate(asOf) else { return "synced 5m ago" }
        let mins = max(0, Int(-date.timeIntervalSinceNow / 60))
        if mins < 1  { return "synced just now" }
        if mins < 60 { return "synced \(mins)m ago" }
        return "synced \(mins / 60)h ago"
    }

    // MARK: - Hero ActiveCard (gradient-rimmed)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                // Pill row: "by yard" (neutral) + "staffed" (success).
                HStack(spacing: Space.s2) {
                    Text("by yard")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    Text("staffed")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color(hex: 0x34D8A6))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.success.opacity(0.20)))
                    Spacer()
                }

                HStack(alignment: .top) {
                    // Lead figure + caption.
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Text("\(availableCount)")
                            .font(.system(size: 30, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("of \(totalCrew) crew")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text("\(yardLabel) · next call in \(nextCallLabel)")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 8)
                    // Right: regulation tag + status keyword.
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("49 CFR 228")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(staffedKeyword)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .tracking(0.2)
                            .foregroundStyle(staffedColor)
                    }
                }

                // Progress bar — availability fraction of total crew.
                GeometryReader { geo in
                    let frac = totalCrew > 0 ? CGFloat(availableCount) / CGFloat(totalCrew) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(6, geo.size.width * frac))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private var staffedKeyword: String { availableCount > 0 ? "STAFFED" : "SHORT" }
    private var staffedColor: Color { availableCount > 0 ? Color(hex: 0x34D8A6) : Brand.warning }

    // MARK: - KPI strip (3 cells, cell-1 gradient fill)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // CREW — eusoDiagonal-filled gradient cell, white numerals.
            VStack(alignment: .leading, spacing: 8) {
                Text("CREW")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("\(totalCrew)")
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiCell(label: "AVAIL", value: "\(availableCount)", valueColor: Color(hex: 0x34D8A6))
            kpiCell(label: "NEXT",  value: nextCallShort,       valueColor: Color(hex: 0xF5B544))
        }
    }

    private func kpiCell(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CREW · BY STATUS card

    private var byStatusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CREW · BY STATUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("railShipments.ts:795")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                statusRow(
                    chipTint: Brand.success.opacity(0.20),
                    glyphColor: Color(hex: 0x34D8A6),
                    title: "Available · ready",
                    sub: "\(availableCount) crew · within HOS limits",
                    pillText: "READY",
                    pillTint: Brand.success.opacity(0.22),
                    pillColor: Color(hex: 0x34D8A6),
                    value: "\(availableCount)",
                    valueColor: Color(hex: 0x34D8A6))
                Divider().overlay(palette.borderFaint)
                statusRow(
                    chipTint: Brand.info.opacity(0.20),
                    glyphColor: Color(hex: 0x5BB0F5),
                    title: "On duty · assigned",
                    sub: "\(onDutyCount) crew · linehaul + yard",
                    pillText: "ON DUTY",
                    pillTint: Brand.info.opacity(0.22),
                    pillColor: Color(hex: 0x5BB0F5),
                    value: "\(onDutyCount)",
                    valueColor: Color(hex: 0x5BB0F5))
                Divider().overlay(palette.borderFaint)
                statusRow(
                    chipTint: Brand.danger.opacity(0.18),
                    glyphColor: Color(hex: 0xFF6B5E),
                    title: "Rested-out · HOS",
                    sub: "\(restedOutCount) crew · 49 CFR 228",
                    pillText: "HOS",
                    pillTint: Brand.danger.opacity(0.22),
                    pillColor: Color(hex: 0xFF6B5E),
                    value: "\(restedOutCount)",
                    valueColor: Color(hex: 0xFF6B5E))

                HStack {
                    Text("+ Deadheading 0 crew en route · \(totalCrew) crew yard total · next call \(nextCallLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                .padding(.top, Space.s3)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func statusRow(chipTint: Color, glyphColor: Color, title: String, sub: String,
                           pillText: String, pillTint: Color, pillColor: Color,
                           value: String, valueColor: Color) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipTint)
                    .frame(width: 40, height: 40)
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(glyphColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            Text(pillText)
                .font(.system(size: 11, weight: .bold)).tracking(0.5)
                .foregroundStyle(pillColor)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(pillTint))
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - NEXT AVAILABLE · CALL context strip

    private var nextAvailableStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEXT AVAILABLE · CALL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("railShipments.ts:784")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("Next engineer available in \(nextCallLabel) · crew assigned \(yardLabel)")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(consignorLine)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var consignorLine: String {
        // Carrier-vantage shipper-of-record line. SVG anchor is
        // "Eusorone Technologies (DU)"; fall back to it when the session
        // has no display name rather than fabricating a different one.
        let raw = session.user?.name?.trimmingCharacters(in: .whitespaces)
        let company = (raw?.isEmpty == false) ? raw! : "Eusorone Technologies (DU)"
        return "\(company) · RAIL-260524-9C20A7E15B · \(yardLabel)"
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Call crew", action: { Task { await callCrew() } }, isLoading: callingCrew)
                .frame(maxWidth: .infinity)
            Button {
                NotificationCenter.default.post(
                    name: .eusoRailNavSwap, object: nil,
                    userInfo: ["screenId": "Rail554"]) // 554 Rail Crew HOS Roster
            } label: {
                Text("HOS roster")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(hex: 0x232932))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 148)
        }
    }

    // MARK: - Next-call derivation

    /// Earliest estimated call time across all rostered crew, rendered as a
    /// human "Nh Mm" gap. Falls back to the SVG anchor when the board has no
    /// future estimatedCallTime (real empty, not fabricated).
    private var nextCallDate: Date? {
        let members = (board?.engineers ?? []) + (board?.conductors ?? [])
        let future = members.compactMap { $0.estimatedCallTime.flatMap(parseDate) }
            .filter { $0.timeIntervalSinceNow > 0 }
        return future.min()
    }

    private var nextCallLabel: String {
        guard let d = nextCallDate else { return "—" }
        let secs = max(0, Int(d.timeIntervalSinceNow))
        let h = secs / 3600, m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private var nextCallShort: String {
        guard let d = nextCallDate else { return "—" }
        let secs = max(0, Int(d.timeIntervalSinceNow))
        let h = secs / 3600, m = (secs % 3600) / 60
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func parseDate(_ s: String) -> Date? {
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }

    // MARK: - Load + actions

    private func reload() async {
        loading = true; loadError = nil
        struct YardIn: Encodable { let yardId: String }
        do {
            let result: CrewAvailabilityResult632 = try await EusoTripAPI.shared.query(
                "railShipments.getCrewAvailability", input: YardIn(yardId: yardId))
            self.board = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// "Call crew" — issues a duty-call against the board. The crew-call
    /// mutation is not exposed on the rail router this fire (only the
    /// per-crew duty-status report exists server-side), so this surfaces a
    /// real not-yet-wired error rather than fabricating a success ack.
    private func callCrew() async {
        callingCrew = true; loadError = nil
        // PORT-GAP: railShipments.callCrew (no crew-call mutation on the rail
        // router; CloudMoyoCrewService.reportDutyStatus is per-crew only and
        // is not exposed as a board-level "call crew" tRPC procedure).
        loadError = "Crew-call dispatch is not yet wired for \(yardLabel)."
        callingCrew = false
    }
}

#Preview("632 · Rail Crew Availability · Night") { RailCrewAvailabilityScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("632 · Rail Crew Availability · Light") { RailCrewAvailabilityScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
