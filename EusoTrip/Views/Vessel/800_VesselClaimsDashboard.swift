//
//  800_VesselClaimsDashboard.swift
//  EusoTrip
//
//  Purpose: expose vessel-claim financial risk by original currency and show
//  which booking-bound claims still require action or verified status.
//  Archetype: maritime exposure register.
//

import SwiftUI

struct VesselClaimsDashboardScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            VesselClaimsDashboardBody()
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)
                ],
                trailing: [
                    NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                    NavSlot(label: "Me", systemImage: "person", isCurrent: false)
                ],
                orbState: .idle
            )
        }
    }
}

private struct VesselCurrencyExposure: Identifiable {
    let code: String
    let amount: Double
    var id: String { code }
}

private struct VesselClaimsDashboardBody: View {
    @Environment(\.palette) private var palette
    @State private var claims: [FreightClaimsAPI.Claim] = []
    @State private var loading = true
    @State private var loadError: String?

    private let terminalStatuses: Set<String> = ["settled", "paid", "closed", "denied"]

    private var activeClaims: [FreightClaimsAPI.Claim] {
        claims.filter { claim in
            guard let status = FreightClaimConsumerCanon.clean(claim.status)?.lowercased() else { return false }
            return !terminalStatuses.contains(status)
        }
    }

    private var unknownStatusCount: Int {
        claims.filter { FreightClaimConsumerCanon.clean($0.status) == nil }.count
    }

    private var incompleteFinancialCount: Int {
        claims.filter { $0.amount == nil || $0.currency == nil }.count
    }

    private var exposure: [VesselCurrencyExposure] {
        var totals: [String: Double] = [:]
        for claim in activeClaims {
            guard let amount = claim.amount, let currency = claim.currency else { continue }
            totals[currency.rawValue, default: 0] += amount
        }
        return totals
            .map { VesselCurrencyExposure(code: $0.key, amount: $0.value) }
            .sorted { $0.code < $1.code }
    }

    private var bookingsWithAnchors: Int {
        claims.filter { FreightClaimConsumerCanon.reference(for: $0, mode: .vessel) != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Vessel claims",
                title: "Exposure register",
                purpose: "Monitor booking-bound maritime claims without netting unlike currencies or treating missing status as resolved."
            )

            if loading && claims.isEmpty {
                ProgressView("Loading vessel claims")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let loadError {
                LifecycleCard(accentDanger: true) {
                    Text(loadError).font(.body).foregroundStyle(Brand.danger)
                }
            } else if claims.isEmpty {
                EusoEmptyState(
                    systemImage: "water.waves.and.arrow.trianglehead.clockwise",
                    title: "No vessel claims",
                    subtitle: "No claim tied to a vessel booking is available to this account."
                )
            } else {
                exposureSection
                integritySection
                bookingRegister
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var exposureSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Active exposure")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            if exposure.isEmpty {
                LifecycleCard {
                    Text("No active vessel claim has complete amount and currency context.")
                        .font(.body)
                        .foregroundStyle(palette.textSecondary)
                        .frame(minHeight: 44)
                }
            } else {
                ForEach(exposure) { item in
                    LifecycleCard {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.code)
                                .font(.headline)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            Text(item.amount.formatted(.number.precision(.fractionLength(2))))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(palette.textPrimary)
                                .monospacedDigit()
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var integritySection: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                FreightClaimValueRow(label: "Vessel claims", value: claims.count.formatted())
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Active", value: activeClaims.count.formatted())
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Booking anchor present", value: bookingsWithAnchors.formatted())
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Status unavailable", value: unknownStatusCount.formatted())
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Financial context incomplete", value: incompleteFinancialCount.formatted())
            }
        }
    }

    private var bookingRegister: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Recent booking claims")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            ForEach(claims.prefix(5)) { claim in
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(claim.claimNumber)
                                .font(.headline)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(FreightClaimConsumerCanon.label(claim.status) ?? "Status unavailable")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(claim.status == nil ? palette.textTertiary : Brand.info)
                        }
                        .frame(minHeight: 44)
                        Divider().opacity(0.25)
                        FreightClaimValueRow(
                            label: "Vessel booking",
                            value: FreightClaimConsumerCanon.reference(for: claim, mode: .vessel)
                        )
                        Divider().opacity(0.25)
                        FreightClaimValueRow(
                            label: "Exposure",
                            value: FreightClaimConsumerCanon.financialContext(amount: claim.amount, currency: claim.currency)
                        )
                    }
                }
            }
        }
    }

    @MainActor
    private func load() async {
        loading = claims.isEmpty
        loadError = nil
        do {
            claims = try await FreightClaimConsumerCanon.claims(mode: .vessel)
        } catch {
            loadError = FreightClaimConsumerCanon.errorMessage(error)
        }
        loading = false
    }
}

#Preview("Vessel claims dashboard") {
    VesselClaimsDashboardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
