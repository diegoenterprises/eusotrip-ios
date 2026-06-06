//
//  287_CatalystRiskFlag.swift
//  EusoTrip — Shipper · Catalyst risk flag (Arc F).
//
//  Highway-style fraud / authority / insurance flagger. Server-side
//  this is `carrierIntelligence.riskFlags(catalystId)` (routers.ts
//  `carrierIntelligence.riskFlags`), returning
//  `{ catalystId, flags: [{ id, kind, severity, title, detail, source }] }`.
//
//  Honesty contract:
//    • The proc DERIVES flags from real persisted signals only
//      (companies.isActive / companies.complianceStatus + FMCSA
//      getCarrierSafetyIntel). It NEVER returns a positive-compliance
//      assertion field.
//    • An empty `flags` array means "no negative signal tripped against
//      the EusoTrip registry" — NOT "FMCSA authority active, insurance
//      verified." The server's FMCSA lookup is wrapped in a swallowing
//      catch{}, so an empty array can occur even when the safety feed was
//      unavailable. We therefore never assert verified-positive compliance.
//    • If the call fails (404 / network / decode), we surface
//      "risk signals unavailable" — we do NOT fall through to a clean
//      record, because absence-of-data is not the same as a clean record.
//

import SwiftUI

struct CatalystRiskFlagScreen: View {
    let theme: Theme.Palette
    let catalystId: String
    var body: some View {
        Shell(theme: theme) { CatalystRiskFlagBody(catalystId: catalystId) } nav: { shipperLifecycleNav() }
    }
}

private struct RiskFlagsEnvelope: Decodable, Hashable {
    struct Flag: Decodable, Hashable, Identifiable {
        let id: String
        let kind: String
        let severity: String
        let title: String
        let detail: String
        let source: String
    }
    let catalystId: String
    let flags: [Flag]
}

private struct CatalystRiskFlagBody: View {
    @Environment(\.palette) private var palette
    let catalystId: String
    @State private var env: RiskFlagsEnvelope? = nil
    @State private var loading: Bool = true
    @State private var unavailable: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await loadRisk() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("SHIPPER · CATALYST · RISK FLAGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.warning)
            }
            Text("Risk & fraud signals").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Pulling risk signals…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if unavailable {
            // Call failed (404 / network / decode). NEVER assert positive
            // compliance on a failure — show that signals are unavailable.
            LifecycleCard(accentWarning: true) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
                    Text("Risk signals unavailable. We couldn't reach the carrier-intelligence feed — re-vet authority and insurance directly before tendering.")
                        .font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let e = env, !e.flags.isEmpty {
            ForEach(e.flags) { f in
                LifecycleCard(accentDanger: f.severity == "critical", accentWarning: f.severity == "warning") {
                    LifecycleSection(label: f.kind.uppercased(), icon: "exclamationmark.triangle.fill")
                    LifecycleRow(label: "Severity", value: f.severity.uppercased())
                    LifecycleRow(label: "Source",   value: f.source)
                    Text(f.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(f.detail).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            // Loaded, zero flags. The proc has NO positive-compliance field,
            // so we do not claim "FMCSA authority active, insurance verified."
            // We report exactly what the empty array means: no negative
            // signal tripped against our registry — and note that this is
            // not, by itself, a compliance verification.
            LifecycleCard {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield").foregroundStyle(palette.textSecondary)
                    Text("No risk signals tripped against the EusoTrip carrier registry. This is not a positive compliance verification — confirm authority and insurance before tendering.")
                        .font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func loadRisk() async {
        loading = true; unavailable = false
        struct In: Encodable { let catalystId: String }
        do {
            let e: RiskFlagsEnvelope = try await EusoTripAPI.shared.query(
                "carrierIntelligence.riskFlags",
                input: In(catalystId: catalystId)
            )
            env = e
        } catch {
            // Call failed — absence of data is NOT a clean record. Mark the
            // panel unavailable instead of asserting positive compliance.
            env = nil
            unavailable = true
        }
        loading = false
    }
}

#Preview("287 · Risk · Night") {
    CatalystRiskFlagScreen(theme: Theme.dark, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("287 · Risk · Afternoon") {
    CatalystRiskFlagScreen(theme: Theme.light, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
