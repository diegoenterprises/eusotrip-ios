//
//  542_DispatcherCredentialsWatchtower.swift
//  EusoTrip — Dispatcher · Credentials Watchtower.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/542 Dispatcher Credentials Watchtower.svg`
//
//  COMPLIANCE / RUNWAY archetype — a 90-day expiry RUNWAY (a forward time-axis
//  with 0-30 / 31-60 / 61-90 risk bands and a marker pin per credential) over a
//  soonest-first ledger where every credential carries its own urgency runway
//  bar. One forward view of every CDL, medical card, hazmat endorsement, IFTA
//  decal and COI about to lapse — so a renewal goes out before a driver is
//  grounded mid-lane.
//
//  Honest wiring — 0 stubs, fully dynamic (certifications confirmed on disk
//  2026-07-11):
//    • READ  certifications.getExpiring        (…:212, {daysAhead,entityType})
//            → runway pins + roster rows (type / name / entity / daysRemaining /
//            expiresAt). Canonical source — CDL, medical, hazmat, IFTA, COI all
//            surface here.
//    • WRITE certifications.sendRenewalReminder (…:308, {certificationId}) →
//            "Send renewal reminders" fires one per credential inside 30 days.
//    • READ  certifications.getComplianceReport (…:281) → "Report" surfaces the
//            fleet compliance score.
//    (cdlVerification.getExpiring :275 is the complementary CDL-only feed; the
//     certifications feed already carries CDL rows so a single source keeps the
//     runway honest.)
//
//  Persona: Aurora Freight Lines · Renée Marquette (RM); fleet scope via
//  ctx.user.companyId. transportMode=truck. NAV: HOME · BOARD(current) · [orb]
//  · COMMS · ME. Author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoder

private struct ExpiringCred542: Decodable, Identifiable {
    let id: String
    let type: String?
    let name: String?
    let entityName: String?
    let expiresAt: String?         // YYYY-MM-DD
    let daysRemaining: Int
}

// MARK: - Screen

struct DispatcherCredentialsWatchtowerScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatcherCredentialsWatchtowerBody() } nav: { DispatchPortNav() }
    }
}

// MARK: - Body

private struct DispatcherCredentialsWatchtowerBody: View {
    @Environment(\.palette) private var palette

    @State private var creds: [ExpiringCred542] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var working = false
    @State private var actionNote: String?

    private var sorted: [ExpiringCred542] { creds.sorted { $0.daysRemaining < $1.daysRemaining } }
    private var dueIn30: [ExpiringCred542] { creds.filter { $0.daysRemaining <= 30 } }

    private func bandColor(_ days: Int) -> Color {
        if days <= 30 { return Brand.danger }
        if days <= 60 { return Brand.warning }
        return Brand.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, Space.s3)

            if loading {
                DispatchPortLoadingCard(text: "Loading credentials…").padding(.top, Space.s5)
            } else if let err = loadError, creds.isEmpty {
                DispatchPortErrorCard(message: err) { Task { await load() } }.padding(.top, Space.s5)
            } else if creds.isEmpty {
                EusoEmptyState(systemImage: "checkmark.shield.fill",
                               title: "Nothing expiring in 90 days",
                               subtitle: "Every CDL, medical card, endorsement and decal in the fleet is current.")
                    .padding(.top, Space.s6)
            } else {
                runwayCard.padding(.top, Space.s5)
                roster.padding(.top, Space.s5)
                if let note = actionNote {
                    Text(note).font(EType.caption).foregroundStyle(palette.textSecondary).padding(.top, Space.s3)
                }
                ctaPair.padding(.top, Space.s5)
            }
        }
        .padding(.horizontal, 20).padding(.top, Space.s2)
        .task { await load() }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ DISPATCHER · CREDENTIALS")
                    .font(EType.micro).tracking(1.0).foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("EXPIRY").font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                DispatchPortBackChevron()
                Text("Watchtower").font(EType.h1).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: 90-day runway hero

    private var runwayCard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("90-DAY EXPIRY RUNWAY · AURORA FLEET")
                .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("\(dueIn30.count)")
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .foregroundStyle(Brand.danger)
                Text("expiring in 30 days")
                    .font(EType.caption.weight(.bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(creds.count) tracked").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            }

            // Runway axis with risk bands + pins
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 6).fill(Brand.danger.opacity(0.16))
                        Rectangle().fill(Brand.warning.opacity(0.16))
                        RoundedRectangle(cornerRadius: 6).fill(Brand.success.opacity(0.16))
                    }
                    .frame(height: 46)
                    // pins
                    ForEach(creds) { c in
                        let x = min(max(CGFloat(c.daysRemaining) / 90, 0), 1) * (w - 8) + 4
                        Rectangle().fill(bandColor(c.daysRemaining))
                            .frame(width: 2, height: 46)
                            .overlay(alignment: .top) {
                                Circle().fill(bandColor(c.daysRemaining)).frame(width: 7, height: 7).offset(y: -1)
                            }
                            .position(x: x, y: 23)
                    }
                }
            }
            .frame(height: 46)

            HStack {
                Text("NOW").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textTertiary)
                Spacer(); Text("30d").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textTertiary)
                Spacer(); Text("60d").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textTertiary)
                Spacer(); Text("90d").font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }

            if let first = sorted.first {
                Text("\(first.name ?? credLabel(first.type)) due first in \(first.daysRemaining)d — send renewals now")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Roster (soonest first)

    private var roster: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CREDENTIALS · SOONEST FIRST")
                    .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("certifications").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                ForEach(Array(sorted.prefix(5).enumerated()), id: \.element.id) { idx, c in
                    credRow(c)
                    if idx < min(5, sorted.count) - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                    }
                }
                if sorted.count > 5 {
                    Text("+ \(sorted.count - 5) more tracked · fleet scope · DU / Eusorone")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s4)
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func credRow(_ c: ExpiringCred542) -> some View {
        let color = bandColor(c.daysRemaining)
        let fillFrac = min(max(1 - CGFloat(c.daysRemaining) / 90, 0.05), 1)
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.18))
                Image(systemName: credIcon(c.type)).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(c.name ?? credLabel(c.type)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(c.entityName?.isEmpty == false ? c.entityName! : credLabel(c.type))
                    .font(EType.mono(.caption)).tracking(0.3).foregroundStyle(palette.textSecondary).lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 5)
                        Capsule().fill(color).frame(width: geo.size.width * fillFrac, height: 5)
                    }
                }
                .frame(height: 5)
            }
            Spacer(minLength: Space.s2)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(c.daysRemaining)d")
                    .font(.system(size: 13, weight: .heavy).monospacedDigit()).foregroundStyle(color)
                Text(shortDate(c.expiresAt)).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await sendReminders() } } label: {
                HStack(spacing: Space.s2) {
                    if working { ProgressView().tint(palette.textOnGradient) }
                    Text(working ? "Sending…" : "Send \(dueIn30.count) renewal reminders")
                        .font(EType.bodyStrong).foregroundStyle(palette.textOnGradient)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(working || dueIn30.isEmpty)
            .opacity(dueIn30.isEmpty ? 0.5 : 1)

            Button { Task { await fetchReport() } } label: {
                Text("Report").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(width: 110).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Color(hex: 0x232932)))
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(working)
        }
    }

    // MARK: Data + actions

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let daysAhead: Int; let entityType: String }
        do {
            creds = try await EusoTripAPI.shared.query("certifications.getExpiring", input: In(daysAhead: 90, entityType: "all"))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func sendReminders() async {
        let targets = dueIn30
        guard !targets.isEmpty else { return }
        working = true; actionNote = nil
        struct In: Encodable { let certificationId: String }
        struct Out: Decodable { let success: Bool? }
        var sent = 0
        for c in targets {
            do { let _: Out = try await EusoTripAPI.shared.mutation("certifications.sendRenewalReminder", input: In(certificationId: c.id)); sent += 1 }
            catch { /* tally honestly */ }
        }
        actionNote = sent == targets.count
            ? "Sent \(sent) renewal \(sent == 1 ? "reminder" : "reminders")."
            : "Sent \(sent) of \(targets.count) reminders — retry the rest."
        working = false
    }

    private func fetchReport() async {
        working = true; actionNote = nil
        struct In: Encodable { let entityType: String }
        struct Out: Decodable { let overallCompliance: Double? }
        do {
            let out: Out = try await EusoTripAPI.shared.query("certifications.getComplianceReport", input: In(entityType: "fleet"))
            actionNote = "Fleet compliance \(Int((out.overallCompliance ?? 0).rounded()))%."
        } catch {
            actionNote = "Couldn't load the compliance report."
        }
        working = false
    }

    // MARK: Formatting

    private func credLabel(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "cdl": return "CDL"
        case "medical_card", "medical": return "DOT Medical Card"
        case "hazmat": return "Hazmat Endorsement"
        case "ifta": return "IFTA Decal"
        case "coi", "insurance": return "Insurance COI"
        case "twic": return "TWIC Card"
        default: return (type ?? "Credential").replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    private func credIcon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "cdl": return "creditcard.fill"
        case "medical_card", "medical": return "cross.case.fill"
        case "hazmat": return "diamond.fill"
        case "ifta": return "checkmark.seal.fill"
        case "coi", "insurance": return "shield.lefthalf.filled"
        case "twic": return "person.badge.key.fill"
        default: return "doc.text.fill"
        }
    }
    private func shortDate(_ iso: String?) -> String {
        guard let iso, iso.count >= 10 else { return "" }
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return String(iso.prefix(10)) }
        let names = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard m >= 1, m <= 12 else { return String(iso.prefix(10)) }
        return "\(names[m]) \(String(format: "%02d", d))"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("542 · Credentials Watchtower · Dark") {
    DispatcherCredentialsWatchtowerScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
#Preview("542 · Credentials Watchtower · Light") {
    DispatcherCredentialsWatchtowerScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#endif
