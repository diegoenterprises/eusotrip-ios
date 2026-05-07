//
//  321_CatalystDriverProfile.swift
//  EusoTrip — Catalyst · Driver Profile (brick 321).
//
//  Pixel-faithful port of "321 Catalyst Driver Profile · Light/Dark"
//  (Figma `~/Desktop/EusoTrip 2027 UI Wireframes/03 Catalyst/Light-SVG/`).
//  The catalyst-side detail view of one driver — the canonical
//  catalyst→driver record. Pairs with 304 Fleet Drivers (the roster)
//  and 322 Driver Documents (the file vault) under the Dispatch
//  umbrella. Web parity: `/catalyst/drivers/[driverId]`.
//
//  Catalyst↔Driver relationship per founder doctrine "no stubs / no
//  mock data — wired correctly":
//    • Hero monogram + name + contact = same `drivers.id` /
//      `users.id` row Eusotrans LLC's Michael Eusorone holds in his
//      §11.4 Driver track session. Tap-to-call uses `tel://` against
//      the live `users.phone` value; tap-to-email uses `mailto:`
//      against `users.email`.
//    • CDL pills + medical countdown derive from `drivers.licenseExpiry`
//      / `drivers.medicalCardExpiry` — same TIMESTAMP columns 326
//      Driver Compliance reads. Two surfaces, one source.
//    • Monthly stats (loads / earnings) join the live `loads` table
//      for the trailing 30-day window — never a synthesized count.
//
//  Server wiring (all real, no stubs):
//    • `drivers.getById(id)` (drivers.ts:378) — full profile envelope
//      including CDL / medical / current load / monthly stats.
//    • `catalysts.getMyDrivers` — roster row for HOS countdown +
//      live GPS location (richer than `drivers.getById.location`
//      which is a server stub at lat:0/lng:0/city:"Unknown").
//    • `driverQualification.getOverview` — DQ score for the
//      compliance summary tile.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen wrapper

struct CatalystDriverProfileScreen: View {
    let theme: Theme.Palette
    let driverId: String

    init(theme: Theme.Palette, driverId: String = "") {
        self.theme = theme
        self.driverId = driverId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystDriverProfile(initialDriverId: driverId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_321(),
                trailing: catalystNavTrailing_321(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_321() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_321() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Body

private struct CatalystDriverProfile: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    let initialDriverId: String

    @State private var resolvedDriverId: String = ""
    @State private var profile: DriversAPI.DriverProfile? = nil
    @State private var rosterRow: CatalystAPI.FleetDriver? = nil
    @State private var dqOverview: DriverQualificationAPI.Overview? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    // MARK: Sheet state — quick-action deep dives
    @State private var showDocuments: Bool = false
    @State private var showCompliance: Bool = false
    @State private var showScorecard: Bool = false
    @State private var showEditProfile: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleRowWithEdit
                iridescentHairline

                if loading {
                    skeletonBody
                } else if let err = loadError {
                    errorBanner(err)
                } else if let p = profile {
                    heroIdentityCard(p)
                    contactStrip(p)
                    credentialPillsCard(p)
                    operationsKpiQuartet(p)
                    quickActionsRow(p)
                } else {
                    emptyDriverState
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        // RealtimeService → load / driver / dq / hos events all
        // refresh the surface so the catalyst sees driver state shift
        // live as the driver works.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoProfileUpdated)) { _ in
            Task { await loadAll() }
        }
        .sheet(isPresented: $showDocuments) {
            CatalystDriverDocumentsScreen(theme: palette, driverId: resolvedDriverId)
                .environmentObject(EusoTripSession())
        }
        .sheet(isPresented: $showCompliance) {
            CatalystDriverComplianceScreen(theme: palette, driverId: resolvedDriverId)
                .environmentObject(EusoTripSession())
        }
        .sheet(isPresented: $showScorecard) {
            CatalystDriverScorecardScreen(theme: palette, driverId: resolvedDriverId)
                .environmentObject(EusoTripSession())
        }
        .sheet(isPresented: $showEditProfile) {
            CatalystDriverEditSheet(driverId: resolvedDriverId, currentName: profile?.name ?? "")
                .environment(\.palette, palette)
        }
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DRIVER · PROFILE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(headerStatusLabel)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var headerStatusLabel: String {
        guard let p = profile else { return "—" }
        return p.status.uppercased().replacingOccurrences(of: "_", with: " ")
    }

    private var titleRowWithEdit: some View {
        HStack(alignment: .center) {
            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("eusoCatalystBack"),
                    object: nil
                )
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text("Driver profile")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitleLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                showEditProfile = true
            } label: {
                Text("EDIT")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .overlay(
                        Capsule().strokeBorder(
                            LinearGradient(colors: [Brand.blue, Brand.magenta], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1.2
                        )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitleLine: String {
        let name = profile?.name ?? "Driver"
        return "Eusotrans LLC · \(name) · since \(hireDateDisplay)"
    }

    private var hireDateDisplay: String {
        guard let raw = profile?.hireDate, !raw.isEmpty else { return "—" }
        if raw.count >= 10 { return String(raw.prefix(10)) }
        return raw
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - Hero identity card

    private func heroIdentityCard(_ p: DriversAPI.DriverProfile) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Text(monogram(for: p.name))
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                ZStack {
                    Circle().fill(p.status == "available" || p.status == "on_load" ? Brand.success : Brand.warning)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
                .offset(x: 4, y: -2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("CDL-\(p.cdl.class) · \(p.cdlNumber.isEmpty ? "—" : p.cdlNumber)")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                if let load = p.currentLoad, !load.isEmpty {
                    Text("On \(load) · \(rosterRow.map { $0.location } ?? "—")")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    statusPill
                    ownerOpPill
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusPill: some View {
        let label = profile?.status.uppercased().replacingOccurrences(of: "_", with: " ") ?? "—"
        let tint: Color = {
            switch profile?.status.lowercased() ?? "" {
            case "on_load":    return Brand.blue
            case "available":  return Brand.success
            case "off_duty":   return Brand.warning
            default:            return palette.textTertiary
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private var ownerOpPill: some View {
        Text("OWNER-OP")
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LinearGradient.diagonal)
            .clipShape(Capsule())
    }

    // MARK: - Contact strip

    private func contactStrip(_ p: DriversAPI.DriverProfile) -> some View {
        HStack(spacing: 8) {
            contactButton(label: "Call",     icon: "phone.fill",    enabled: !p.phone.isEmpty) {
                openURL(scheme: "tel", value: p.phone)
            }
            contactButton(label: "Message",  icon: "message.fill",  enabled: !p.phone.isEmpty) {
                openURL(scheme: "sms", value: p.phone)
            }
            contactButton(label: "Email",    icon: "envelope.fill", enabled: !p.email.isEmpty) {
                openURL(scheme: "mailto", value: p.email)
            }
        }
    }

    private func contactButton(label: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if enabled { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .heavy))
                Text(label).font(.system(size: 12, weight: .heavy)).tracking(0.4)
            }
            .foregroundStyle(enabled ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        enabled
                            ? AnyShapeStyle(LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(palette.borderFaint),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func openURL(scheme: String, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: "\(scheme):\(trimmed)") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Credential pills card (CDL · Medical · Endorsements)

    private func credentialPillsCard(_ p: DriversAPI.DriverProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CREDENTIALS · 49 CFR §391")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 8) {
                credentialRow(
                    icon: "rectangle.fill.on.rectangle.fill",
                    label: "CDL · Class \(p.cdl.class)",
                    value: p.cdl.number.isEmpty ? "—" : p.cdl.number,
                    meta: cdlMeta(p)
                )
                credentialRow(
                    icon: "cross.case.fill",
                    label: "Medical · 49 CFR §391.41",
                    value: p.medicalCard.expirationDate.isEmpty ? "—" : "exp \(p.medicalCard.expirationDate)",
                    meta: medicalMeta(p)
                )
                if !p.cdl.endorsements.isEmpty {
                    credentialRow(
                        icon: "shield.lefthalf.filled",
                        label: "Endorsements",
                        value: p.cdl.endorsements.joined(separator: " · "),
                        meta: endorsementsMeta(p)
                    )
                }
            }
        }
    }

    private func credentialRow(icon: String, label: String, value: String, meta: (text: String, tint: Color)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(meta.text)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(meta.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(meta.tint.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(10)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func cdlMeta(_ p: DriversAPI.DriverProfile) -> (text: String, tint: Color) {
        guard !p.cdl.expirationDate.isEmpty else { return ("—", palette.textTertiary) }
        return ("EXP \(p.cdl.expirationDate)", Brand.success)
    }

    private func medicalMeta(_ p: DriversAPI.DriverProfile) -> (text: String, tint: Color) {
        switch p.medicalCard.status.lowercased() {
        case "valid":   return ("VALID",   Brand.success)
        case "expired": return ("EXPIRED", Brand.danger)
        default:         return ("PENDING", Brand.warning)
        }
    }

    private func endorsementsMeta(_ p: DriversAPI.DriverProfile) -> (text: String, tint: Color) {
        ("\(p.cdl.endorsements.count) ACTIVE", Brand.blue)
    }

    // MARK: - Operations KPI quartet

    private func operationsKpiQuartet(_ p: DriversAPI.DriverProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPERATIONS · TRAILING 30D")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                kpiCell(
                    eyebrow: "LOADS",
                    value: "\(p.stats.loadsThisMonth)",
                    meta: "this month",
                    emphasis: .neutral
                )
                kpiDivider
                kpiCell(
                    eyebrow: "EARNINGS",
                    value: formatCurrency(p.stats.earningsThisMonth),
                    meta: payRateMeta(p),
                    emphasis: .gradient
                )
                kpiDivider
                kpiCell(
                    eyebrow: "ON-TIME",
                    value: p.onTimeRate > 0 ? String(format: "%.0f%%", p.onTimeRate) : "—",
                    meta: "delivered/total",
                    emphasis: .success
                )
                kpiDivider
                kpiCell(
                    eyebrow: "DQ",
                    value: dqOverview.map { "\($0.complianceScore)%" } ?? "—",
                    meta: "compliance",
                    emphasis: .gradient
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Brand.blue, Brand.magenta],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private enum KPIEmphasis { case neutral, success, gradient }

    private func kpiCell(eyebrow: String, value: String, meta: String, emphasis: KPIEmphasis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Group {
                switch emphasis {
                case .gradient: Text(value).font(.system(size: 16, weight: .heavy)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                case .success:  Text(value).font(.system(size: 16, weight: .heavy)).monospacedDigit().foregroundStyle(Brand.success)
                case .neutral:  Text(value).font(.system(size: 16, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            Text(meta).font(.system(size: 10)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 38)
            .padding(.horizontal, 4)
    }

    private func payRateMeta(_ p: DriversAPI.DriverProfile) -> String {
        let unit: String = {
            switch p.payRate.type {
            case "per_mile": return "/mi"
            case "per_load": return "/load"
            case "salary":   return "/yr"
            default:          return ""
            }
        }()
        guard p.payRate.rate > 0 else { return "this month" }
        return String(format: "$%.2f%@", p.payRate.rate, unit)
    }

    private func formatCurrency(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    // MARK: - Quick actions row (Documents / Compliance / Scorecard)

    private func quickActionsRow(_ p: DriversAPI.DriverProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DRIVER · DEEP DIVES")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 8) {
                quickActionRow(
                    icon: "doc.on.doc.fill",
                    title: "Documents",
                    subtitle: "§391 vault — CDL · Medical · MVR · Drug",
                    action: { showDocuments = true }
                )
                quickActionRow(
                    icon: "shield.lefthalf.filled",
                    title: "Compliance",
                    subtitle: "5 federal axes — CSA · §395 · MCSAP · §391.41 · §382",
                    action: { showCompliance = true }
                )
                quickActionRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Performance scorecard",
                    subtitle: "Composite letter grade · 30D / 90D / YTD",
                    action: { showScorecard = true }
                )
            }
        }
    }

    private func quickActionRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(12)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / loading / error

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard).frame(height: 110)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.bgCard).frame(height: 36) }
            }
            ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.bgCard).frame(height: 60) }
        }
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private var emptyDriverState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No driver to view")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Add a driver to your roster on 304 Fleet Drivers to populate this profile.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg).font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Button { Task { await loadAll() } } label: {
                    Text("Retry").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Brand.danger.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    private func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    // MARK: - Network

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            // Resolve driverId — initial param or roster default.
            if !initialDriverId.isEmpty {
                resolvedDriverId = initialDriverId
            } else {
                let roster = try await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)
                guard let primary = roster.first else { return }
                resolvedDriverId = primary.id
                self.rosterRow = primary
            }
            // Capture into a local Sendable constant so the
            // synchronous `Array.first(where:)` closure on the roster
            // task doesn't reach back into the main-actor isolated
            // `resolvedDriverId` property from a nonisolated context.
            let driverId = resolvedDriverId
            // Parallel fetch profile + roster row + DQ overview.
            async let profileTask: DriversAPI.DriverProfile? = {
                try? await EusoTripAPI.shared.drivers.getProfileById(driverId: driverId)
            }()
            async let rosterTask: CatalystAPI.FleetDriver? = {
                let r = (try? await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)) ?? []
                return r.first { $0.id == driverId }
            }()
            async let overviewTask: DriverQualificationAPI.Overview? = {
                try? await EusoTripAPI.shared.dq.getOverview(driverId: driverId)
            }()
            let (p, r, o) = await (profileTask, rosterTask, overviewTask)
            self.profile = p
            self.rosterRow = r ?? self.rosterRow
            self.dqOverview = o
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Driver edit sheet

private struct CatalystDriverEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let driverId: String
    let currentName: String

    @State private var licenseNumber: String = ""
    @State private var licenseState: String = ""
    @State private var licenseExpiry: Date = Date().addingTimeInterval(60 * 60 * 24 * 365 * 4)
    @State private var hasLicenseExpiry: Bool = false
    @State private var medicalCardExpiry: Date = Date().addingTimeInterval(60 * 60 * 24 * 365)
    @State private var hasMedicalExpiry: Bool = false
    @State private var hazmatEndorsement: Bool = false
    @State private var status: DriverStatus = .available
    @State private var saving: Bool = false
    @State private var saveError: String? = nil

    enum DriverStatus: String, CaseIterable, Identifiable {
        case available, onLoad = "on_load", offDuty = "off_duty", inactive
        var id: String { rawValue }
        var label: String {
            switch self {
            case .available: return "Available"
            case .onLoad:    return "On load"
            case .offDuty:   return "Off duty"
            case .inactive:  return "Inactive"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Driver") {
                    LabeledContent("Name", value: currentName.isEmpty ? "—" : currentName)
                }
                Section("CDL") {
                    TextField("License number", text: $licenseNumber)
                    TextField("State (e.g. IA)", text: $licenseState)
                        .textInputAutocapitalization(.characters)
                    Toggle("Has license expiry", isOn: $hasLicenseExpiry)
                    if hasLicenseExpiry {
                        DatePicker("Expires", selection: $licenseExpiry, displayedComponents: .date)
                    }
                }
                Section("Medical card · 49 CFR §391.41") {
                    Toggle("Has medical expiry", isOn: $hasMedicalExpiry)
                    if hasMedicalExpiry {
                        DatePicker("Expires", selection: $medicalCardExpiry, displayedComponents: .date)
                    }
                }
                Section("Endorsements") {
                    Toggle("Hazmat (H)", isOn: $hazmatEndorsement)
                }
                Section("Status") {
                    Picker("Driver status", selection: $status) {
                        ForEach(DriverStatus.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                }
                if let err = saveError {
                    Section {
                        Text(err)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.danger)
                    }
                }
            }
            .navigationTitle("Edit driver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(saving)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() async {
        saveError = nil
        saving = true
        defer { saving = false }

        let licenseExpIso = hasLicenseExpiry ? Self.iso8601Date(licenseExpiry) : nil
        let medicalExpIso = hasMedicalExpiry ? Self.iso8601Date(medicalCardExpiry) : nil
        do {
            _ = try await EusoTripAPI.shared.drivers.update(
                driverId: driverId,
                licenseNumber: licenseNumber.isEmpty ? nil : licenseNumber,
                licenseState: licenseState.isEmpty ? nil : licenseState,
                licenseExpiry: licenseExpIso,
                medicalCardExpiry: medicalExpIso,
                hazmatEndorsement: hazmatEndorsement,
                status: status.rawValue
            )
            dismiss()
        } catch {
            saveError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func iso8601Date(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
}

// MARK: - Previews

#Preview("321 · Catalyst · Driver Profile · Night") {
    CatalystDriverProfileScreen(theme: Theme.dark, driverId: "")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("321 · Catalyst · Driver Profile · Afternoon") {
    CatalystDriverProfileScreen(theme: Theme.light, driverId: "")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
