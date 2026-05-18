//
//  093_MeDQFile.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · DQ File)
//
//  Screen 093 · Me · DQ File — the driver's full Driver Qualification
//  file. Compliance score hero, document breakdown (valid / expiring
//  / expired / missing), "Expiring soon" watchlist sourced from CDL
//  + medical card + hazmat + TWIC + certifications expiries, and a
//  chronological list of every DQ document on file.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Compliance score + counts from `driverQualification.getOverview`
//      — MCP-verified at
//      `frontend/server/routers/driverQualification.ts`.
//    • Document list from `getDocuments` — newest first, driver-scoped.
//    • Expiring list from `getExpiringItems` (60-day window). Server
//      watches CDL + medical + hazmat + TWIC columns + the
//      `certifications` table in one pass. Narrowed client-side to
//      just this driver's items.
//    • No fabricated compliance scores. No placeholder documents.
//      A brand-new driver with no docs uploaded sees a "Nothing
//      on file yet" empty state, not a green 100.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero score + compliant band.
//         Brand.warning on expiring <30d. Brand.magenta on expired.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeDQFile: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = DQFileStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                scoreHero
                documentsBreakdown
                expiringSection
                documentsSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await seedAndRefresh() }
        .refreshable { await seedAndRefresh() }
        .onChange(of: session.user?.id) { _, newId in
            store.driverId = newId ?? ""
            Task { await store.refresh() }
        }
    }

    private func seedAndRefresh() async {
        store.driverId = session.user?.id ?? ""
        await store.refresh()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("DQ File")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CDL · medical · hazmat · TWIC · annual review")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Score hero

    private var scoreHero: some View {
        let score = store.overview?.complianceScore ?? 0
        let hasData = (store.overview?.documents.total ?? 0) > 0
        let band = scoreBand(score, hasData: hasData)
        return VStack(spacing: Space.s3) {
            ZStack {
                Circle()
                    .stroke(palette.tintNeutral.opacity(0.5), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0, min(1, Double(score) / 100.0)))
                    .stroke(
                        LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(hasData ? "\(score)" : "—")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text(hasData ? "/ 100" : "no docs yet")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .frame(width: 160, height: 160)

            bandChip(band)

            if let name = store.overview?.driverName, !name.isEmpty {
                Text(name.uppercased())
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private enum ComplianceBand { case compliant, watch, atRisk, noData }

    private func scoreBand(_ score: Int, hasData: Bool) -> ComplianceBand {
        if !hasData { return .noData }
        if score >= 90 { return .compliant }
        if score >= 70 { return .watch }
        return .atRisk
    }

    @ViewBuilder
    private func bandChip(_ band: ComplianceBand) -> some View {
        switch band {
        case .compliant:
            Text("COMPLIANT")
                .font(EType.micro).tracking(1.3)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s3).padding(.vertical, 4)
                .background(Capsule().fill(LinearGradient.diagonal))
        case .watch:
            Text("WATCH")
                .font(EType.micro).tracking(1.3)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s3).padding(.vertical, 4)
                .overlay(Capsule().stroke(Brand.warning, lineWidth: 1))
        case .atRisk:
            Text("AT RISK")
                .font(EType.micro).tracking(1.3)
                .foregroundStyle(Brand.magenta)
                .padding(.horizontal, Space.s3).padding(.vertical, 4)
                .overlay(Capsule().stroke(Brand.magenta, lineWidth: 1))
        case .noData:
            Text("NO FILE")
                .font(EType.micro).tracking(1.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s3).padding(.vertical, 4)
                .overlay(Capsule().stroke(palette.textTertiary.opacity(0.55), lineWidth: 1))
        }
    }

    // MARK: Documents breakdown

    private var documentsBreakdown: some View {
        let d = store.overview?.documents
        return HStack(spacing: Space.s2) {
            countTile(label: "VALID",    value: "\(d?.valid ?? 0)",        gradient: true)
            countTile(label: "EXPIRING", value: "\(d?.expiringSoon ?? 0)", gradient: false)
            countTile(label: "EXPIRED",  value: "\(d?.expired ?? 0)",      gradient: false)
            countTile(label: "MISSING",  value: "\(d?.missing ?? 0)",      gradient: false)
        }
    }

    private func countTile(label: String, value: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(gradient
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Expiring

    private var expiringSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if !store.expiring.isEmpty {
                Text("EXPIRING WITHIN 60 DAYS")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                ForEach(store.expiring) { item in
                    expiringRow(item)
                }
            }
        }
    }

    private func expiringRow(_ item: DriverQualificationAPI.ExpiringItem) -> some View {
        let urgent = item.daysRemaining <= 14
        let critical = item.daysRemaining <= 7
        let tint: Color = critical ? Brand.magenta : (urgent ? Brand.warning : palette.textSecondary)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(tint.opacity(0.18))
                Text("\(item.daysRemaining)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.type)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("Expires \(humanizeDate(item.expiresAt))")
                    .font(EType.caption)
                    .foregroundStyle(tint)
            }

            Spacer()
            Text("\(item.daysRemaining) DAY\(item.daysRemaining == 1 ? "" : "S")")
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(tint)
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Documents list

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DOCUMENTS ON FILE")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if store.documents.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "Nothing on file yet",
                    subtitle: "Upload your CDL, medical card, and any endorsements so dispatch can match you to compliant loads."
                )
            } else {
                ForEach(store.documents) { doc in
                    documentRow(doc)
                }
            }
        }
    }

    private func documentRow(_ d: DriverQualificationAPI.DQDocument) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: docIcon(d.type))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.5))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(d.name?.isEmpty == false ? (d.name ?? d.type) : humanType(d.type))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: 4) {
                    Text(humanType(d.type))
                    if let reg = d.regulation, !reg.isEmpty {
                        Text("·")
                        Text(reg)
                    }
                    if let upl = d.uploadedAt, !upl.isEmpty {
                        Text("·")
                        Text("Added \(humanizeDate(upl))")
                    }
                }
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            }

            Spacer()
            statusChip(d.status ?? "pending")
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        switch status.lowercased() {
        case "valid", "active":
            Text("VALID")
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2).padding(.vertical, 3)
                .background(Capsule().fill(LinearGradient.diagonal))
        case "expired":
            Text("EXPIRED")
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(Brand.magenta)
                .padding(.horizontal, Space.s2).padding(.vertical, 3)
                .overlay(Capsule().stroke(Brand.magenta, lineWidth: 1))
        case "pending", "review":
            Text("PENDING")
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, Space.s2).padding(.vertical, 3)
                .overlay(Capsule().stroke(Brand.warning, lineWidth: 1))
        default:
            Text(status.uppercased())
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s2).padding(.vertical, 3)
                .overlay(Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1))
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text("Your DQ file is the regulatory record your carrier pulls for FMCSA audits. Upload + renew here; dispatch will only match compliant CDL profiles to loads.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func docIcon(_ type: String) -> String {
        switch type.lowercased() {
        case let t where t.contains("cdl") || t.contains("license"): return "creditcard"
        case let t where t.contains("medical") || t.contains("physical"): return "cross.case"
        case let t where t.contains("hazmat"): return "exclamationmark.triangle"
        case let t where t.contains("twic"): return "lock.shield"
        case let t where t.contains("drug"): return "testtube.2"
        case let t where t.contains("mvr"): return "car"
        case let t where t.contains("road") || t.contains("test"): return "checkmark.seal"
        case let t where t.contains("employ"): return "person.text.rectangle"
        case let t where t.contains("annual"): return "calendar.badge.clock"
        default: return "doc.text"
        }
    }

    private func humanType(_ type: String) -> String {
        type.replacingOccurrences(of: "_", with: " ")
            .capitalized(with: Locale(identifier: "en_US"))
    }

    private func humanizeDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let inF = DateFormatter()
        inF.dateFormat = "yyyy-MM-dd"
        inF.locale = Locale(identifier: "en_US_POSIX")
        let altF = ISO8601DateFormatter()
        let date = inF.date(from: String(iso.prefix(10))) ?? altF.date(from: iso)
        guard let date else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d, yyyy"
        return out.string(from: date)
    }
}

// MARK: - Screen wrapper

struct MeDQFileScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeDQFile()
        } nav: {
            BottomNav(
                leading: driverNavLeading_093(),
                trailing: driverNavTrailing_093(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_093() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_093() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("093 · DQ File · Night") {
    MeDQFileScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("093 · DQ File · Afternoon") {
    MeDQFileScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
