//
//  099_MeFreightClaims.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Freight Claims)
//
//  Screen 099 · Me · Freight Claims — file and track cargo
//  damage / loss / shortage / delay / contamination claims from
//  the cab. Dashboard hero shows open / pending / resolved counts
//  plus total value in dispute. Aging strip surfaces claims
//  stuck in the pipeline >30 / 60 / 90 days so drivers can push
//  for resolution. Recent claims list with status chips.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Dashboard + claims + file all hit real `freightClaims.*`
//      procs — MCP-verified at
//      `frontend/server/routers/freightClaims.ts`.
//    • File mutation maps the driver's claim type to the
//      canonical `incidents.type` enum server-side — we pass the
//      driver-facing vocabulary (damage, loss, shortage, delay,
//      contamination) and the server auto-routes to the safety
//      workflow (property_damage, hazmat_spill, near_miss).
//    • No fabricated aging buckets. Counters reflect the
//      server's live view of the company's claims table.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero + submit CTA.
//         Brand.warning on aging >60d, Brand.magenta on >90d.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeFreightClaims: View {
    @Environment(\.palette) var palette
    @StateObject private var store = FreightClaimsStore()

    @State private var showingFile = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                counterStrip
                agingSection
                fileCTA
                claimsSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showingFile) {
            FileClaimSheet(store: store)
                .eusoSheetX()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Freight Claims")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Cargo damage · loss · shortage · delay · contamination")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                Text("Truck / trailer mechanical + accident → Zeun")
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary.opacity(0.8))
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Counter strip

    private var counterStrip: some View {
        let d = store.dashboard
        return VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                countTile(label: "OPEN",     value: "\(d?.open ?? 0)",     gradient: true)
                countTile(label: "PENDING",  value: "\(d?.pending ?? 0)",  gradient: false)
                countTile(label: "RESOLVED", value: "\(d?.resolved ?? 0)", gradient: false)
                countTile(label: "DENIED",   value: "\(d?.denied ?? 0)",   gradient: false)
            }
            HStack(spacing: Space.s2) {
                moneyTile(
                    label: "TOTAL VALUE",
                    value: currency(d?.totalValue ?? 0)
                )
                metaTile(
                    label: "AVG RESOLUTION",
                    value: "\(Int((d?.avgResolutionDays ?? 0).rounded()))d"
                )
            }
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

    private func moneyTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    private func metaTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Aging

    @ViewBuilder
    private var agingSection: some View {
        if let aging = store.dashboard?.aging,
           aging.under30 + aging.days30to60 + aging.days60to90 + aging.over90 > 0 {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("AGING")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: Space.s2) {
                    agingTile(label: "<30D",    count: aging.under30,    tint: palette.textSecondary)
                    agingTile(label: "30-60D",  count: aging.days30to60, tint: palette.textPrimary)
                    agingTile(label: "60-90D",  count: aging.days60to90, tint: Brand.warning)
                    agingTile(label: ">90D",    count: aging.over90,     tint: Brand.magenta)
                }
            }
        }
    }

    private func agingTile(label: String, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text("\(count)")
                .font(EType.bodyStrong)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
                )
        )
    }

    // MARK: File CTA

    private var fileCTA: some View {
        Button {
            showingFile = true
        } label: {
            HStack {
                Image(systemName: "plus.rectangle.on.rectangle")
                Text("File a claim")
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(EType.bodyStrong)
            .foregroundStyle(.white)
            .padding(Space.s3)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.diagonal)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Claims

    private var claimsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("RECENT CLAIMS")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if store.claims.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "shippingbox",
                    title: "No claims filed",
                    subtitle: "If something gets damaged, short, or contaminated on your next load, file it here so safety + billing can pull POD photos + start recovery."
                )
            } else {
                ForEach(store.claims, id: \.stableId) { c in
                    claimRow(c)
                }
            }
        }
    }

    private func claimRow(_ c: FreightClaimsAPI.Claim) -> some View {
        let statusLower = (c.status ?? "").lowercased()
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: claimTypeIcon(c.type))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.5))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text((c.type ?? "claim").replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let desc = c.description, !desc.isEmpty {
                    Text(desc)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                if let ts = c.createdAt {
                    Text(relativeTime(ts))
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            statusChip(statusLower)
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    private func claimTypeIcon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "property_damage":      return "shippingbox.and.arrow.backward"
        case "hazmat_spill":         return "exclamationmark.triangle"
        case "near_miss":            return "clock.badge.exclamationmark"
        default:                     return "doc.text"
        }
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        let (label, tint, filled): (String, Color, Bool) = {
            switch status {
            case "resolved", "approved", "paid":
                return (status.uppercased(), .green, true)
            case "denied", "disputed":
                return (status.uppercased(), Brand.magenta, false)
            case "investigating", "open":
                return (status.uppercased(), Brand.warning, false)
            default:
                return (status.isEmpty ? "PENDING" : status.uppercased(), palette.textTertiary, false)
            }
        }()
        Text(label)
            .font(EType.micro)
            .tracking(1.2)
            .foregroundStyle(filled ? .white : tint)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(
                Group {
                    if filled {
                        Capsule().fill(LinearGradient.diagonal)
                    } else {
                        Capsule().stroke(tint, lineWidth: 1)
                    }
                }
            )
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Space.s1) {
            Text("Claims older than 9 months often drop below the Carmack-Act recovery threshold. Photograph cargo damage on-site + file the same day when you can.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Text("Accident? Breakdown? Mechanical? That flow lives in Zeun — DVIR, roadside, provider dispatch all route through there.")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func relativeTime(_ iso: String) -> String {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = full.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        let s = -date.timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86400))d ago"
    }
}

// MARK: - File sheet

private struct FileClaimSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FreightClaimsStore

    @State private var loadId: String = ""
    @State private var type: FreightClaimsAPI.ClaimType = .damage
    @State private var amount: String = ""
    @State private var commodity: String = ""
    @State private var description: String = ""
    @State private var damageExtent: String = ""
    @State private var submitError: String?

    private var canSubmit: Bool {
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let amt = Double(amount) ?? 0
        return !loadId.isEmpty && desc.count >= 10 && amt > 0 && !store.isFiling
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Load") {
                    TextField("Load ID or number", text: $loadId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Claim type") {
                    Picker("Type", selection: $type) {
                        ForEach(FreightClaimsAPI.ClaimType.allCases) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Amount") {
                    TextField("USD", text: $amount)
                        .keyboardType(.decimalPad)
                }
                Section("Commodity (optional)") {
                    TextField("e.g. 24 pallets pharma cold chain", text: $commodity)
                }
                Section("Description (≥10 chars)") {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                }
                Section("Damage extent (optional)") {
                    TextField("e.g. 4 pallets wet, 12 cases crushed", text: $damageExtent)
                }
                if let err = submitError {
                    Section {
                        Text(err)
                            .foregroundStyle(Brand.warning)
                            .font(EType.caption)
                    }
                }
            }
            .navigationTitle("File freight claim")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if store.isFiling {
                            ProgressView()
                        } else {
                            Text("File").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private func submit() async {
        submitError = nil
        let amt = Double(amount) ?? 0
        do {
            _ = try await store.fileClaim(
                loadId: loadId.trimmingCharacters(in: .whitespaces),
                type: type,
                amount: amt,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                commodity: commodity.isEmpty ? nil : commodity,
                damageExtent: damageExtent.isEmpty ? nil : damageExtent
            )
            dismiss()
        } catch {
            submitError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't file claim — try again in a moment."
        }
    }
}

// MARK: - Screen wrapper

struct MeFreightClaimsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeFreightClaims()
        } nav: {
            BottomNav(
                leading: driverNavLeading_099(),
                trailing: driverNavTrailing_099(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_099() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_099() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("099 · Freight Claims · Night") {
    MeFreightClaimsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("099 · Freight Claims · Afternoon") {
    MeFreightClaimsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
