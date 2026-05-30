//
//  392_CatalystCargoInsurance.swift
//  EusoTrip — Catalyst · Cargo Insurance (CARRIER-side fleet coverage + per-load compliance).
//
//  Verbatim iOS-house port of "03 Catalyst/Code/392_CatalystCargoInsurance.swift"
//  (cross-checked against Dark-SVG "392 Catalyst Cargo Insurance.svg").
//
//  CARRIER vantage. Fleet coverage + per-load compliance: a cargo-limit hero
//  (cargo $250K · auto $1M · MCS-90), a getCoverage detail card (limits · reefer
//  breakdown · MCS-90 · expiry · verifyCarrierCoverage line), a per-load
//  checkLoadCompliance strip, a COI-on-file tie, and the generateCOI CTA.
//  Cross-mode parity gap fill — Rail (606) and Vessel (733) had cargo-insurance
//  surfaces; the Truck Catalyst band had none against the mode-agnostic insurance
//  router. Carrier vantage (own cover, verify per load) is distinct from the
//  shipper per-load buy. Docked under FLEET.
//
//  PERSONA: CATALYST — Aurora Freight Lines · USDOT 3 482 119 · MC-942 008.
//  COI holder / shipper-of-record DU pin: Eusorone Technologies.
//
//  WIRING (web peer · server/routers/insurance.ts · grep 2026-05-24):
//    There is NO `insurance` service namespace on the iOS EusoTripAPI (verified
//    by grep of Services/EusoTripAPI.swift — no getCoverage / verifyCarrierCoverage
//    / checkLoadCompliance / getCommodityInsuranceRequirements / getCertificates /
//    generateCOI / getPerLoadQuote / purchasePerLoad). Per house doctrine the
//    representative Code/ seed figures stand ("0% mock — seeds overwritten on
//    hydrate") and one // WIRE: marker is left per missing call.
//
//      // WIRE: insurance.getCoverage                     (insurance.ts:664)  hero + detail
//      // WIRE: insurance.verifyCarrierCoverage           (insurance.ts:747)  meets-load line
//      // WIRE: insurance.checkLoadCompliance             (insurance.ts:1340) per-load strip
//      // WIRE: insurance.getCommodityInsuranceRequirements (insurance.ts:1763) per-load strip
//      // WIRE: insurance.getCertificates                 (insurance.ts:442)  COI tie
//      // WIRE: insurance.generateCOI                     (insurance.ts:1559) mutation · CTA
//      // WIRE: insurance.getPerLoadQuote                 (insurance.ts:887)  above-limit
//      // WIRE: insurance.purchasePerLoad                 (insurance.ts:930)
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystCargoInsuranceScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            CargoInsuranceBody_392()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_392(),
                trailing: catalystNavTrailing_392(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_392() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_392() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "truck.box",          isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.crop.circle", isCurrent: true)]
}

// MARK: - Body

private struct CargoInsuranceBody_392: View {
    @Environment(\.palette) private var palette

    // Representative coverage-detail rows (getCoverage return shape).
    // Seeds — overwritten on hydrate once insurance.getCoverage is wired.
    private let coverageRows_392: [CoverageRow_392] = [
        CoverageRow_392(label: "Cargo limit",        value: "$250,000"),
        CoverageRow_392(label: "Auto liability",     value: "$1,000,000"),
        CoverageRow_392(label: "Reefer breakdown",   value: "included"),
        CoverageRow_392(label: "MCS-90 endorsement", value: "on file"),
        CoverageRow_392(label: "Expires",            value: "2026-11-30"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                IridescentHairline()
                    .padding(.horizontal, -20)

                heroCard
                provenanceLine("COVERAGE · getCoverage · verifyCarrierCoverage")
                coverageDetailCard
                perLoadStrip
                coiTieStrip
                generateCTA
                ctaSchemaFootnote

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · CARGO INSURANCE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("FLEET COVER")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Cargo Insurance")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("getCoverage · fleet · Aurora Freight Lines · USDOT 3 482 119 · MC-942 008")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Hero (cargo limit · active policy)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CARGO LIMIT · ACTIVE POLICY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("in force")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.14)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$250,000")
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("cargo")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("auto liability $1M · MCS-90 on file · deductible $1,000")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Coverage detail (getCoverage · verifyCarrierCoverage)

    private var coverageDetailCard: some View {
        VStack(spacing: 0) {
            ForEach(coverageRows_392) { row in
                HStack {
                    Text(row.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Text(row.value)
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.vertical, 7)
            }
            HStack {
                Text("verifyCarrierCoverage · meets Eusorone Technologies load requirements")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Per-load strip (checkLoadCompliance · getCommodityInsuranceRequirements)

    private var perLoadStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PER-LOAD · checkLoadCompliance · getCommodityInsuranceRequirements")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            perLoadLine("reefer berries load needs $100K cargo · met")
            perLoadLine("NH\u{2083} UN1005 hazmat load needs MCS-90 + $5M · met")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func perLoadLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Brand.success)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - COI tie (getCertificates · getPerLoadQuote)

    private var coiTieStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("2 active COIs on file · 1 expiring in 22d · getCertificates")
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("COI holder Eusorone Technologies · DU · per-load on demand")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
            Text("getPerLoadQuote available for above-limit high-value loads")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.info.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.info.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA (generateCOI)

    private var generateCTA: some View {
        // WIRE: insurance.generateCOI (insurance.ts:1559) — mutation · {loadId,holder,limits}
        CTAButton(
            title: "Generate certificate (COI)",
            action: {},
            leadingIcon: "doc.badge.plus"
        )
    }

    private var ctaSchemaFootnote: some View {
        Text("generateCOI · {loadId,holder,limits}")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Provenance eyebrow

    private func provenanceLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
    }

    // MARK: - Network
    //
    // No `insurance` namespace exists on EusoTripAPI yet (verified by grep of
    // Services/EusoTripAPI.swift). When the insurance router is bridged, the
    // // WIRE: calls above hydrate the seeds via @State here. Until then the
    // representative Code/ figures stand — honest house pattern.
    private func loadAll() async {
        // WIRE: insurance.getCoverage                       (insurance.ts:664)
        // WIRE: insurance.verifyCarrierCoverage             (insurance.ts:747)
        // WIRE: insurance.checkLoadCompliance               (insurance.ts:1340)
        // WIRE: insurance.getCommodityInsuranceRequirements (insurance.ts:1763)
        // WIRE: insurance.getCertificates                   (insurance.ts:442)
        // WIRE: insurance.getPerLoadQuote                   (insurance.ts:887)
        // WIRE: insurance.purchasePerLoad                   (insurance.ts:930)
    }
}

// MARK: - Models

private struct CoverageRow_392: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

// MARK: - Previews

#Preview("392 · Catalyst · Cargo Insurance · Night") {
    CatalystCargoInsuranceScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("392 · Catalyst · Cargo Insurance · Afternoon") {
    CatalystCargoInsuranceScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
