//
//  766_VesselLetterOfIndemnity.swift
//  EusoTrip — Vessel Operator · Letter of Indemnity (UNDERTAKING / SIGNATORY).
//
//  Verbatim bespoke port of canonical wireframe "766 Vessel Letter of
//  Indemnity · Dark" (06 Vessel · Vessel Operator). Guarantee archetype,
//  purpose-built as an indemnity-amount hero (110% cargo value) over an
//  undertaking-terms checklist + TWO counter-signatory cards (merchant with
//  the DU initials disc, bank guarantor countersigned) — deliberately
//  DISTINCT from the carrier-side release pipeline (679 Telex Release) and
//  the B/L surfaces. A bank-counter-signed undertaking to release cargo
//  WITHOUT the original bill of lading.
//
//  Docked under COMPLIANCE. transportMode=vessel · tri-country US·CA·MX.
//
//  REAL WIRING (tRPC):
//    · vesselShipments.surrenderBOL (server/routers/vesselShipments.ts:974) +
//      getBOL (:944) — the underlying B/L surrender state the LOI substitutes
//      for. EXISTS. listBOLs (:961) anchors the master B/L under indemnity.
//  STUB (handed to the-oath): loi.issue / loi.acceptRelease — there is no
//  indemnity model server-wide (grep 'indemnity' = 0); no signatory/guarantor
//  capture, no link to release-without-OBL. The undertaking terms + signatory
//  cards render the certified reference model; accept-release is irreversible
//  financial exposure, human-gated + audited when the endpoint lands.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselLetterOfIndemnityScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselLetterOfIndemnityBody()
        } nav: {
            BottomNav.vesselOperatorShipments()
        }
    }
}

// MARK: - Body

private struct VesselLetterOfIndemnityBody: View {
    @Environment(\.palette) private var palette

    @State private var bols: [VesselDocBOL] = []
    @State private var loading = true

    private var subjectBOL: VesselDocBOL? {
        bols.first(where: { ($0.bolType ?? "").lowercased() == "master" }) ?? bols.first
    }

    private let terms: [String] = [
        "Deliver cargo without production of original B/L",
        "Indemnify carrier against all consequences",
        "Provide originals to carrier when available",
        "ITIC / P&I club approved wording",
        "Valid until originals surrendered",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDocTopBar(eyebrow: "VESSEL OPERATOR · INDEMNITY",
                            idCaption: "P&I · LOI",
                            title: "Letter of indemnity")
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    VesselDocSkeleton(bodyHeight: 340)
                } else {
                    heroCard
                    termsSection
                    signatorySection
                    TriCountryAuthorityBand(title: "LOI JURISDICTION · RELEASE AUTHORITY",
                                            regimes: jurisdictionRegimes)
                    VesselDocCTAPair(primaryTitle: "Submit to carrier",
                                     secondaryTitle: "Save draft",
                                     primaryIcon: "paperplane.fill",
                                     onPrimary: {}, onSecondary: {})
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("LOI-260615 · master B/L \(String((subjectBOL?.bolNumber ?? "MSCUSH6840").prefix(11)))")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("BANK COUNTER-SIGNED")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.16)))
            }
            Text(vesselDocCurrency(1_320_000))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .padding(.top, Space.s3)
            Text("110% cargo value · single-bank LOI form")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 3)
            Text("Trigger: original B/L not yet available")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Undertaking terms

    private var termsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "UNDERTAKING TERMS", right: "\(terms.count) clauses")
            VStack(spacing: 0) {
                ForEach(Array(terms.enumerated()), id: \.offset) { idx, t in
                    HStack(spacing: Space.s3) {
                        ZStack {
                            Circle().fill(Brand.success).frame(width: 15, height: 15)
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                        }
                        Text(t)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, Space.s4).padding(.vertical, 10)
                    if idx < terms.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: Counter-signatories

    private var signatorySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "COUNTER-SIGNATORIES", right: "2 of 2")
            HStack(spacing: Space.s3) {
                merchantCard
                bankCard
            }
            VesselDocGapNote(text: "Reference undertaking. Signatory capture + the release-without-OBL link persist when the indemnity endpoint lands.")
        }
    }

    private var merchantCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.s2) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0x7A4DFF), Brand.magenta],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                    Text("DU").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Merchant").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text("Eusorone Tech.").font(.system(size: 8.5, weight: .medium)).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            Text("● SIGNED")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(palette.bgCardSoft))
                .padding(.top, Space.s3)
            Text("Diego Usoro · shipper of record")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s3)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var bankCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.s2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.bgCardSoft).frame(width: 30, height: 28)
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x5AB0FF))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bank").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text("Std Chartered").font(.system(size: 8.5, weight: .medium)).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            Text("● COUNTERSIGNED")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(palette.bgCardSoft))
                .padding(.top, Space.s3)
            Text("Joint & several liability")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s3)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var jurisdictionRegimes: [CountryRegime] {
        [
            .init(code: "US", authority: "US · English-law LOI", detail: "USCG/CBP release", consequence: nil, state: .active),
            .init(code: "CA", authority: "CA · LOI", detail: "CBSA release control", consequence: nil, state: .standby),
            .init(code: "MX", authority: "MX · carta de indemnización", detail: "Aduanas", consequence: nil, state: .standby),
        ]
    }

    private func load() async {
        loading = true
        struct ListIn: Encodable { let limit: Int }
        do {
            self.bols = try await EusoTripAPI.shared.query(
                "vesselShipments.listBOLs", input: ListIn(limit: 20))
        } catch {
            self.bols = []
        }
        loading = false
    }
}

#Preview("766 · Vessel Letter of Indemnity · Night") {
    VesselLetterOfIndemnityScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("766 · Vessel Letter of Indemnity · Light") {
    VesselLetterOfIndemnityScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
